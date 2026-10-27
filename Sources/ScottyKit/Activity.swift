import Darwin
import Foundation

public struct Flow: Sendable, Identifiable, Equatable {
  public let id: String
  public let process: String
  public let pid: pid_t
  public let transport: String
  public let remote: String
  public let port: Int
  public let received: UInt64
  public let sent: UInt64

  public var service: String {
    guard let entry = getservbyport(Int32(UInt16(port).bigEndian), transport),
      let name = entry.pointee.s_name
    else {
      return String(port)
    }
    return String(cString: name)
  }
}

public enum Activity {
  private static let responsible = dlsym(
    UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid"
  ).map { unsafeBitCast($0, to: (@convention(c) (pid_t) -> pid_t).self) }

  private static func owner(of pid: pid_t) -> pid_t {
    responsible.map { $0(pid) }.flatMap { $0 > 0 ? $0 : nil } ?? pid
  }

  public static func flows(through address: String) async throws -> [Flow] {
    let report = try await Shell.run(
      "/usr/bin/nettop", ["-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"])
    return report.split(separator: "\n").reduce(
      into: (owner: (name: "", pid: pid_t(0)), flows: [Flow](), rows: [String: Int]())
    ) { state, line in
      let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      guard let head = fields.first, !head.isEmpty else { return }
      guard head.hasPrefix("tcp4 ") || head.hasPrefix("udp4 ") else {
        let dot = head.lastIndex(of: ".")
        state.owner =
          dot.map { (String(head[..<$0]), owner(of: pid_t(head[head.index(after: $0)...]) ?? 0)) }
          ?? (head, 0)
        return
      }
      let ends = head.dropFirst(5).components(separatedBy: "<->")
      guard ends.count == 2, ends[0].hasPrefix(address + ":"),
        let colon = ends[1].lastIndex(of: ":"),
        let port = Int(ends[1][ends[1].index(after: colon)...])
      else { return }
      let transport = String(head.prefix(3))
      let remote = String(ends[1][..<colon])
      let id = "\(state.owner.pid) \(transport) \(remote):\(port)"
      let previous = state.rows[id].map { state.flows[$0] }
      let flow = Flow(
        id: id,
        process: previous?.process ?? state.owner.name,
        pid: state.owner.pid,
        transport: transport,
        remote: remote,
        port: port,
        received: (previous?.received ?? 0) + (fields.count > 1 ? UInt64(fields[1]) ?? 0 : 0),
        sent: (previous?.sent ?? 0) + (fields.count > 2 ? UInt64(fields[2]) ?? 0 : 0)
      )
      guard let row = state.rows[id] else {
        state.rows[id] = state.flows.count
        return state.flows.append(flow)
      }
      state.flows[row] = flow
    }.flows
  }

  public static func hostname(_ address: String) async -> String? {
    await Task.detached {
      var socket = sockaddr_in()
      socket.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      socket.sin_family = sa_family_t(AF_INET)
      guard inet_pton(AF_INET, address, &socket.sin_addr) == 1 else { return nil }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let status = withUnsafePointer(to: &socket) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          getnameinfo(
            $0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0,
            NI_NAMEREQD)
        }
      }
      guard status == 0 else { return nil }
      return String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        .lowercased()
    }.value
  }
}
