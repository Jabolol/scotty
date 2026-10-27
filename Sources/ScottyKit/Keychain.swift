import Foundation

struct Credentials: Sendable {
  let account: String
  let password: String

  static func load() async throws -> Credentials {
    let item = try await Shell.run(
      "/usr/bin/security", ["find-generic-password", "-s", Configuration.keychainService])
    let account = item.split(separator: "\n")
      .first { $0.contains("\"acct\"<blob>") }?
      .split(separator: "\"").dropFirst(3).first
      .map { String($0.split(separator: "@")[0]) }
    guard let account else {
      throw ScottyError.failed("no account in Keychain item \(Configuration.keychainService)")
    }
    let password = try await Shell.run(
      "/usr/bin/security", ["find-generic-password", "-s", Configuration.keychainService, "-w"])
    return Credentials(account: account, password: password.trimmingCharacters(in: .newlines))
  }
}
