import Foundation
import Network
import Observation
import ScottyKit
import ServiceManagement
import UserNotifications

@MainActor
@Observable
final class Campus {
  enum Phase {
    case idle, signingIn, connecting, disconnecting, renewing
  }

  private static let poll: TimeInterval = 2
  private static let tick: TimeInterval = 0.25
  private static let ticketCheck: TimeInterval = 60
  private static let patience = Duration.seconds(90)
  private static let sessionLead: TimeInterval = 600
  private static let quietRate: Double = 1024
  private static let ticketLead: TimeInterval = 7200
  private static let ticketRespite: TimeInterval = 600

  let traffic = Traffic()
  private(set) var link: Session?
  private(set) var ticket: Ticket?
  private(set) var phase = Phase.idle
  private(set) var isAutomatic = false
  private(set) var networkProblem: String?
  private(set) var ticketProblem: String?
  private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled
  private var isOnline = false
  private var owesReconnect = Tunnel.wanted
  private var passwordRejected = false
  private var lastTicketAttempt: Date?
  private var delegatedExpiry: Date?
  private let pathMonitor = NWPathMonitor()

  init() {
    refresh()
    Task { await maintainTicket() }
    schedule(every: Self.poll) { $0.refresh() }
    schedule(every: Self.tick) { $0.sample() }
    schedule(every: Self.ticketCheck) { campus in Task { await campus.maintainTicket() } }
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let isOnline = path.status == .satisfied
      Task { @MainActor in
        self?.isOnline = isOnline
        self?.resume()
      }
    }
    pathMonitor.start(queue: .main)
    Task {
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }
  }

  var isBusy: Bool { phase != .idle }

  var isLoading: Bool { [.signingIn, .connecting, .disconnecting].contains(phase) }

  var isConnected: Bool {
    get { phase == .signingIn || phase == .connecting || (link != nil && phase != .disconnecting) }
    set { newValue ? connect() : disconnect() }
  }

  func connect() {
    perform(.signingIn, \.networkProblem, "Couldn't connect to Campus VPN") {
      try await Tunnel.connect { self.phase = .connecting }
    }
  }

  func disconnect() {
    perform(.disconnecting, \.networkProblem, "Couldn't disconnect Campus VPN") {
      try await Tunnel.disconnect()
    }
  }

  func renewTicket() {
    perform(.renewing, \.ticketProblem, "Couldn't renew your Kerberos ticket") {
      _ = try await Kerberos.renew()
      self.passwordRejected = false
      await self.maintainTicket()
    }
  }

  func watchConnections(_ active: Bool) {
    traffic.watch(active)
    guard active, let address = link?.address else { return }
    Task { await traffic.refreshFlows(through: address) }
  }

  func setOpensAtLogin(_ enabled: Bool) {
    do {
      try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    } catch {
      notify("Couldn't change Open at Login", error.localizedDescription)
    }
    opensAtLogin = SMAppService.mainApp.status == .enabled
  }

  private func reconnect() {
    isAutomatic = true
    perform(.signingIn, \.networkProblem, "Campus VPN disconnected") {
      try await Tunnel.connect(patience: Self.patience) { self.phase = .connecting }
    }
  }

  private func renewSession() {
    isAutomatic = true
    perform(.disconnecting, \.networkProblem, "Campus VPN disconnected") {
      try await Tunnel.disconnect(forgetting: false)
      self.phase = .signingIn
      try await Tunnel.connect(patience: Self.patience) { self.phase = .connecting }
    }
  }

  private func extendTicket() {
    lastTicketAttempt = .now
    perform(.renewing, \.ticketProblem, "Couldn't renew your Kerberos ticket") {
      do {
        try await Kerberos.extend()
      } catch {
        do {
          _ = try await Kerberos.renew()
        } catch ScottyError.failed(let message) where message.contains("Password incorrect") {
          self.passwordRejected = true
          throw ScottyError.failed(message)
        }
      }
      await self.maintainTicket()
    }
  }

  private func resume() {
    owesReconnect = owesReconnect && Tunnel.wanted
    guard owesReconnect, isOnline, link == nil, !isBusy else { return }
    owesReconnect = false
    reconnect()
  }

  private func schedule(every interval: TimeInterval, _ work: @escaping @MainActor (Campus) -> Void)
  {
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        if let self { work(self) }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
  }

  private func perform(
    _ phase: Phase,
    _ problem: ReferenceWritableKeyPath<Campus, String?>,
    _ failureTitle: String,
    _ work: @escaping @MainActor () async throws -> Void
  ) {
    guard !isBusy else { return }
    self.phase = phase
    self[keyPath: problem] = nil
    Task {
      do {
        try await work()
      } catch is CancellationError {
      } catch ScottyError.busy {
      } catch {
        self[keyPath: problem] = error.localizedDescription
        notify(failureTitle, error.localizedDescription)
      }
      refresh()
      self.phase = .idle
      isAutomatic = false
      resume()
    }
  }

  private func refresh() {
    let current = Tunnel.current()
    if link != nil, current == nil, phase == .idle {
      owesReconnect = true
    }
    if link == nil, current != nil {
      Task { await maintainTicket() }
    }
    if current?.interface != link?.interface || current?.since != link?.since {
      traffic.reset()
    }
    link = current
    if traffic.isWatched, let address = current?.address {
      Task { await traffic.refreshFlows(through: address) }
    }
    resume()
    if let expires = current?.expires, expires.timeIntervalSinceNow < Self.sessionLead,
      phase == .idle, Tunnel.wanted, traffic.isQuiet(below: Self.quietRate)
    {
      renewSession()
    }
  }

  private func sample() {
    guard let link else { return }
    traffic.record(Tunnel.counters(link.interface))
  }

  private func maintainTicket() async {
    ticket = await Kerberos.current()
    let isDue = ticket.map { $0.expires.timeIntervalSinceNow < Self.ticketLead } ?? true
    let isRested =
      lastTicketAttempt.map { Date.now.timeIntervalSince($0) > Self.ticketRespite } ?? true
    if isDue, isRested, !passwordRejected, phase == .idle {
      return extendTicket()
    }
    guard let ticket, ticket.expires > .now, link != nil, delegatedExpiry != ticket.expires else {
      return
    }
    let hosts = Kerberos.hosts
    guard !hosts.isEmpty else { return }
    delegatedExpiry = ticket.expires
    let delivered = await Kerberos.delegate(to: hosts)
    let missing = hosts.filter { !delivered.contains($0) }
    if !missing.isEmpty {
      notify(
        "Couldn't pass on your Kerberos ticket", "No ticket on \(missing.joined(separator: ", ")).")
    }
  }

  private func notify(_ title: String, _ body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }
}
