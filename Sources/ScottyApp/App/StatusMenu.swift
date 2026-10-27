import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
  private let campus: Campus
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()
  private let header: MenuRow
  private let network: MenuRow
  private let ticket: MenuRow
  private let disclosure: MenuRow
  private let connections: MenuRow
  private let connectedOnly: [NSMenuItem]
  private let openAtLogin = NSMenuItem(
    title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
  private var highlighted: MenuRow?
  private var isOpen = false
  private var isWatching = false
  private var listedConnections = 0

  init(campus: Campus) {
    self.campus = campus
    header = MenuRow(dismisses: false) { _ in HeaderRow().environment(campus) }
    network = MenuRow(action: campus.connect) { NetworkRow(state: $0).environment(campus) }
    ticket = MenuRow(dismisses: false, action: campus.renewTicket) {
      TicketRow(state: $0).environment(campus)
    }
    disclosure = MenuRow(dismisses: false) { DisclosureRow(title: "Activity", state: $0) }
    connections = MenuRow { _ in ConnectionList().environment(campus.traffic) }
    let graph = MenuRow { _ in TrafficGraph().environment(campus.traffic) }
    connectedOnly = [
      .separator(), .sectionTitle("Traffic"), NSMenuItem(row: graph, isEnabled: false),
      .separator(), NSMenuItem(row: disclosure),
    ]
    super.init()
    header.action = { [weak self] in self?.toggleConnection() }
    disclosure.action = { [weak self] in self?.toggleActivity() }
    build()
    observe()
  }

  private func build() {
    menu.delegate = self
    menu.autoenablesItems = false
    openAtLogin.target = self
    let quit = NSMenuItem(
      title: "Quit Scotty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.items =
      [NSMenuItem(row: header), .separator()]
      + [.sectionTitle("Network"), NSMenuItem(row: network), .separator()]
      + [.sectionTitle("Kerberos"), NSMenuItem(row: ticket)]
      + connectedOnly
      + [NSMenuItem(row: connections, isEnabled: false), .separator(), openAtLogin, quit]
    statusItem.menu = menu
  }

  private func observe() {
    withObservationTracking {
      update()
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
  }

  private func update() {
    let isConnected = campus.link != nil
    statusItem.button?.image = isConnected || campus.isLoading ? StatusIcon.on : StatusIcon.off
    pulse(campus.isLoading)
    network.enclosingMenuItem?.isEnabled = !isConnected && !campus.isBusy
    for item in connectedOnly {
      item.isHidden = !isConnected
    }
    connections.enclosingMenuItem?.isHidden = !(isConnected && disclosure.state.isExpanded)
    openAtLogin.state = campus.opensAtLogin ? .on : .off
    fitConnections(listing: min(campus.traffic.flows.count, ConnectionList.limit + 1))
  }

  private func fitConnections(listing count: Int) {
    guard count != listedConnections else { return }
    listedConnections = count
    Task { @MainActor in
      connections.fit()
      if let item = connections.enclosingMenuItem {
        menu.itemChanged(item)
      }
    }
  }

  private func pulse(_ isPulsing: Bool) {
    guard let button = statusItem.button else { return }
    button.wantsLayer = true
    guard let layer = button.layer, isPulsing != (layer.animation(forKey: "pulse") != nil) else {
      return
    }
    guard isPulsing else { return layer.removeAnimation(forKey: "pulse") }
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 1
    animation.toValue = 0.3
    animation.duration = 0.8
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "pulse")
  }

  private func toggleConnection() {
    guard !campus.isBusy else { return }
    if !campus.isConnected {
      menu.cancelTracking()
    }
    campus.isConnected.toggle()
  }

  private func toggleActivity() {
    disclosure.state.isExpanded.toggle()
    connections.fit()
    updateWatching()
  }

  private func updateWatching() {
    let shouldWatch = isOpen && disclosure.state.isExpanded
    guard shouldWatch != isWatching else { return }
    isWatching = shouldWatch
    campus.watchConnections(shouldWatch)
  }

  @objc private func toggleOpenAtLogin() {
    campus.setOpensAtLogin(!campus.opensAtLogin)
  }

  func menuWillOpen(_: NSMenu) {
    isOpen = true
    updateWatching()
  }

  func menu(_: NSMenu, willHighlight item: NSMenuItem?) {
    highlighted?.state.isHighlighted = false
    highlighted = item?.view as? MenuRow
    highlighted?.state.isHighlighted = true
  }

  func menuDidClose(_: NSMenu) {
    menu(menu, willHighlight: nil)
    isOpen = false
    updateWatching()
  }
}
