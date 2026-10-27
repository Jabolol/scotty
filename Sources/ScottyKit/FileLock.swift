import Darwin
import Foundation

final class FileLock {
  private let descriptor: Int32

  init?(at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = open(url.path(percentEncoded: false), O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw ScottyError.failed("couldn't open \(url.path): \(String(cString: strerror(errno)))")
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      return nil
    }
    self.descriptor = descriptor
  }

  func unlock() {
    flock(descriptor, LOCK_UN)
  }

  deinit {
    close(descriptor)
  }
}
