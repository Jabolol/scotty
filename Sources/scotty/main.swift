import AppKit
import ScottyKit

let usage = """
  Usage: scotty <command> [--json] [--timeout <seconds>]

  Commands:
    connect, up        Sign in to CMU and bring up the Campus VPN split tunnel
    ensure             Connect only if needed, signing in unattended; exits 3 when Duo or a password needs you
    wait               Block until the tunnel is up; exits 1 on timeout
    disconnect, down   Log off and tear down the tunnel
    status             Show the connection state
    stats              Show the tunnel's address, uptime, traffic and recent log
    ticket             Get a renewable Kerberos ticket and delegate it to every host listed in the hosts file
    help               Show this help

  Options:
    --json             Print status as JSON: tunnel, session expiry, sign-in and ticket
    --timeout <s>      Seconds that ensure and wait allow (default 90)

  Exit codes: 0 done, 1 failed, 2 usage, 3 a person must approve Duo or sign in
  """

struct Status: Encodable {
  let connected: Bool
  let wanted: Bool
  let signingIn: Bool
  let interface: String?
  let address: String?
  let since: Date?
  let expires: Date?
  let idleTimeout: TimeInterval?
  let ticket: Ticket?
}

func fail(_ error: any Error) -> Never {
  let message = error is CancellationError ? "sign-in cancelled" : error.localizedDescription
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(error as? ScottyError == .needsAttention ? 3 : 1)
}

func run(_ work: @escaping @MainActor () async throws -> Void) -> Never {
  MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.mainMenu = MainMenu.make()
    Task {
      do { try await work() } catch { fail(error) }
      exit(0)
    }
    app.run()
  }
  exit(0)
}

func option(_ name: String) -> String? {
  CommandLine.arguments.firstIndex(of: name).flatMap {
    CommandLine.arguments.dropFirst($0 + 1).first
  }
}

let timeout = Duration.seconds(option("--timeout").map { Int($0) ?? -1 } ?? 90)
guard timeout > .zero else {
  FileHandle.standardError.write(Data("error: --timeout takes a positive number of seconds\n".utf8))
  exit(2)
}

@MainActor
func ensure() async throws {
  let deadline = ContinuousClock.now + timeout
  var attempted = false
  while Tunnel.current() == nil {
    guard .now < deadline else { throw ScottyError.needsAttention }
    if !attempted, !Tunnel.signingIn {
      attempted = true
      do {
        try await Tunnel.connect(patience: deadline - .now) { print("Connecting...") }
      } catch ScottyError.busy {}
      continue
    }
    try await Task.sleep(for: .milliseconds(500))
  }
  print("Connected")
}

func wait() async throws {
  let deadline = ContinuousClock.now + timeout
  while Tunnel.current() == nil {
    guard .now < deadline else {
      throw ScottyError.failed("the tunnel didn't come up within \(timeout)")
    }
    try await Task.sleep(for: .milliseconds(500))
  }
  print("Connected")
}

func status() async throws {
  let link = Tunnel.current()
  guard CommandLine.arguments.contains("--json") else {
    return print(link == nil ? "Disconnected" : "Connected")
  }
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.sortedKeys]
  let status = Status(
    connected: link != nil,
    wanted: Tunnel.wanted,
    signingIn: Tunnel.signingIn,
    interface: link?.interface,
    address: link?.address,
    since: link?.since,
    expires: link?.expires,
    idleTimeout: link?.idleTimeout,
    ticket: await Kerberos.current()
  )
  print(String(decoding: try encoder.encode(status), as: UTF8.self))
}

func stats() async throws {
  guard let link = Tunnel.current() else { return print("Disconnected") }
  let counters = Tunnel.counters(link.interface)
  print(
    """
    Connected since \(link.since.formatted(date: .abbreviated, time: .standard))
    Interface \(link.interface)  Address \(link.address)
    Received \(Int64(counters.received).formatted(.byteCount(style: .file)))  Sent \(Int64(counters.sent).formatted(.byteCount(style: .file)))
    Session ends \(link.expires?.formatted(date: .abbreviated, time: .standard) ?? "unknown")

    """)
  fflush(stdout)
  let log = Process()
  log.executableURL = URL(filePath: "/usr/bin/log")
  log.arguments = [
    "show", "--last", "1h", "--style", "compact", "--predicate", "process == \"openconnect\"",
  ]
  try log.run()
  log.waitUntilExit()
}

func ticket() async throws {
  print("Getting a fresh Kerberos ticket...")
  print(try await Kerberos.renew(), terminator: "")
  let hosts = Kerberos.hosts
  let delivered = await Kerberos.delegate(to: hosts)
  for host in hosts {
    print(delivered.contains(host) ? "\(host): ticket delegated" : "\(host): no ticket")
  }
  let missing = hosts.filter { !delivered.contains($0) }
  guard missing.isEmpty else {
    throw ScottyError.failed("couldn't delegate the ticket to \(missing.joined(separator: ", "))")
  }
}

switch CommandLine.arguments.dropFirst().first ?? "help" {
case "connect", "up":
  run {
    print("Sign in to CMU in the window that opened...")
    try await Tunnel.connect { print("Connecting...") }
    print("Connected")
  }
case "ensure":
  run { try await ensure() }
case "wait":
  run { try await wait() }
case "disconnect", "down":
  run { try await Tunnel.disconnect() }
case "status":
  run { try await status() }
case "stats":
  run { try await stats() }
case "ticket":
  run { try await ticket() }
case "help", "-h", "--help":
  print(usage)
case let command:
  FileHandle.standardError.write(Data("error: unknown command: \(command)\n\n\(usage)\n".utf8))
  exit(2)
}
