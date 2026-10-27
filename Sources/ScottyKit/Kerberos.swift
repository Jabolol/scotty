import Foundation

public struct Ticket: Sendable, Equatable, Encodable {
  public let principal: String
  public let expires: Date
}

public enum Kerberos {
  private static let delegation = [
    "BatchMode=yes", "ConnectTimeout=10", "ControlMaster=no", "ControlPath=none",
    "GSSAPIAuthentication=yes", "GSSAPIDelegateCredentials=yes",
  ].flatMap { ["-o", $0] }

  private struct Cache: Decodable {
    let principal: String
    let tickets: [Entry]
  }

  private struct Entry: Decodable {
    let principal: String
    let expires: String
    enum CodingKeys: String, CodingKey {
      case principal = "Principal"
      case expires = "Expires"
    }
  }

  private static func date(_ stamp: String) -> Date? {
    let digits = stamp.compactMap(\.wholeNumberValue)
    guard digits.count == 14 else { return nil }
    func number(_ range: Range<Int>) -> Int { digits[range].reduce(0) { $0 * 10 + $1 } }
    return Calendar.current.date(
      from: DateComponents(
        year: number(0..<4), month: number(4..<6), day: number(6..<8),
        hour: number(8..<10), minute: number(10..<12), second: number(12..<14)
      ))
  }

  public static func current() async -> Ticket? {
    guard
      let json = try? await Shell.run("/usr/bin/klist", ["--json"]),
      let cache = try? JSONDecoder().decode(Cache.self, from: Data(json.utf8)),
      let tgt = cache.tickets.first(where: { $0.principal.hasPrefix("krbtgt/") }),
      let expires = date(tgt.expires)
    else { return nil }
    return Ticket(principal: cache.principal, expires: expires)
  }

  public static func renew() async throws -> String {
    let credentials = try await Credentials.load()
    let principal = "\(credentials.account)@\(Configuration.realm)"
    _ = try? await Shell.run("/usr/bin/kdestroy", [])
    _ = try await Shell.run(
      "/usr/bin/kinit", ["--forwardable", "-r", "7d", "--password-file=STDIN", principal],
      input: credentials.password + "\n"
    )
    return try await Shell.run("/usr/bin/klist", [])
  }

  public static func extend() async throws {
    _ = try await Shell.run("/usr/bin/kinit", ["-R"])
  }

  public static var hosts: [String] {
    ((try? String(contentsOf: Configuration.hosts, encoding: .utf8)) ?? "")
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  public static func delegate(to hosts: [String]) async -> Set<String> {
    await withTaskGroup(of: String?.self) { group in
      for host in hosts {
        group.addTask {
          (try? await Shell.run("/usr/bin/ssh", delegation + [host, "klist -s"])).map { _ in host }
        }
      }
      return await group.reduce(into: []) { delivered, host in
        if let host { delivered.insert(host) }
      }
    }
  }
}
