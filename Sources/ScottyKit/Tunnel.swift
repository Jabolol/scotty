import Darwin
import Foundation

public struct Session: Sendable, Equatable {
  public let interface: String
  public let address: String
  public let dns: [String]
  public let routes: [String]
  public let since: Date
  public let expires: Date?
  public let idleTimeout: TimeInterval?
}

public struct Counters: Sendable, Equatable {
  public static let zero = Counters(received: 0, sent: 0)

  public let received: UInt64
  public let sent: UInt64
}

public enum Tunnel {
  private static let closing = Duration.seconds(15)

  public static var wanted: Bool {
    FileManager.default.fileExists(atPath: Configuration.intent.path(percentEncoded: false))
  }

  public static var signingIn: Bool {
    do {
      return try FileLock(at: Configuration.lock) == nil
    } catch {
      return false
    }
  }

  @MainActor
  public static func connect(patience: Duration? = nil, signedIn: () -> Void) async throws {
    guard let lock = try FileLock(at: Configuration.lock) else { throw ScottyError.busy }
    defer { lock.unlock() }
    let gateway = try await Gateway.open()
    let challenge = try await gateway.challenge()
    let token = try await SignIn.token(for: challenge, patience: patience)
    signedIn()
    let grant = try await gateway.grant(challenge, token: token)
    _ = try await sudo(["up", grant.certificate], input: grant.token + "\n")
    try Data().write(to: Configuration.intent, options: .atomic)
  }

  public static func disconnect(forgetting: Bool = true) async throws {
    if forgetting {
      try? FileManager.default.removeItem(at: Configuration.intent)
    }
    _ = try await sudo(["down"])
    let deadline = ContinuousClock.now + closing
    while current() != nil {
      guard .now < deadline else { throw ScottyError.failed("The tunnel didn't close.") }
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  public static func current() -> Session? {
    guard
      let pid = try? String(contentsOf: Configuration.pidfile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
      let pid = pid_t(pid), isOpenConnect(pid),
      let lines = try? String(contentsOf: Configuration.state, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map({ $0.split(separator: " ").map(String.init) }),
      lines.count >= 3, lines[0].count == 2,
      let since = try? Configuration.pidfile
        .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    else { return nil }
    let timing = lines.count > 3 ? lines[3].compactMap(TimeInterval.init) : []
    var seen = Set<String>()
    return Session(
      interface: lines[0][0],
      address: lines[0][1],
      dns: lines[1],
      routes: lines[2].filter { seen.insert($0).inserted },
      since: since,
      expires: timing.first.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
      idleTimeout: timing.dropFirst().first.flatMap { $0 > 0 ? $0 : nil }
    )
  }

  public static func counters(_ interface: String) -> Counters {
    let index = if_nametoindex(interface)
    guard index > 0 else { return .zero }
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
    var length = 0
    guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
      return .zero
    }
    var buffer = [UInt8](repeating: 0, count: length)
    guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return .zero }
    return buffer.withUnsafeBytes { raw in
      var offset = 0
      while offset + MemoryLayout<if_msghdr>.size <= length {
        let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
        if Int32(header.ifm_type) == RTM_IFINFO2 {
          let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
          return Counters(received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
        }
        offset += Int(header.ifm_msglen)
      }
      return .zero
    }
  }

  private static func sudo(_ arguments: [String], input: String? = nil) async throws -> String {
    do {
      return try await Shell.run(
        "/usr/bin/sudo", ["-n", Configuration.tunnel] + arguments, input: input)
    } catch ScottyError.failed(let message) where message.contains("password is required") {
      throw ScottyError.failed("The tunnel helper isn't installed. Run install.sh.")
    }
  }

  private static func isOpenConnect(_ pid: pid_t) -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return false }
    let name = withUnsafeBytes(of: info.kp_proc.p_comm) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    return name == "openconnect"
  }
}
