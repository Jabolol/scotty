import Foundation

enum Shell {
  static func run(_ path: String, _ arguments: [String], input: String? = nil) async throws
    -> String
  {
    try await Task.detached {
      let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: scratch) }
      let out = scratch.appending(path: "out")
      let err = scratch.appending(path: "err")
      FileManager.default.createFile(atPath: out.path, contents: nil)
      FileManager.default.createFile(atPath: err.path, contents: nil)

      let process = Process()
      let stdin = Pipe()
      process.executableURL = URL(filePath: path)
      process.arguments = arguments
      process.standardInput = stdin
      process.standardOutput = try FileHandle(forWritingTo: out)
      process.standardError = try FileHandle(forWritingTo: err)
      try process.run()
      try stdin.fileHandleForWriting.write(contentsOf: Data((input ?? "").utf8))
      try stdin.fileHandleForWriting.close()
      process.waitUntilExit()

      let output = try String(contentsOf: out, encoding: .utf8)
      guard process.terminationStatus == 0 else {
        let reason = try String(contentsOf: err, encoding: .utf8).trimmingCharacters(
          in: .whitespacesAndNewlines)
        throw ScottyError.failed(
          reason.isEmpty ? "\(path) exited with status \(process.terminationStatus)" : reason)
      }
      return output
    }.value
  }
}
