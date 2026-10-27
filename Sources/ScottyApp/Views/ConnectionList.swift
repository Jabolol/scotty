import ScottyKit
import SwiftUI

struct ConnectionList: View {
  static let limit = 5

  @Environment(Traffic.self) private var traffic

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if traffic.flows.isEmpty {
        Text("No connections through the tunnel").font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(traffic.flows.prefix(Self.limit)) { flow in
          ConnectionRow(flow: flow, host: traffic.hostnames[flow.remote] ?? flow.remote)
        }
        if traffic.flows.count > Self.limit {
          Text("\(traffic.flows.count - Self.limit) more").font(.caption).foregroundStyle(
            .secondary)
        }
      }
    }
    .padding(.horizontal, MenuMetrics.inset)
    .padding(.top, 4)
    .padding(.bottom, 8)
  }
}

private struct ConnectionRow: View {
  let flow: Flow
  let host: String

  var body: some View {
    let app = NSRunningApplication(processIdentifier: flow.pid)
    HStack(spacing: MenuMetrics.spacing) {
      Group {
        if let icon = app?.icon {
          Image(nsImage: icon).resizable()
        } else {
          Image(systemName: "terminal").foregroundStyle(.secondary)
        }
      }
      .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 0) {
        Text(host).lineLimit(1).truncationMode(.middle)
        Text(origin(app?.localizedName ?? executableName))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Text(Int64(clamping: flow.received + flow.sent), format: .byteCount(style: .file))
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }

  private func origin(_ process: String) -> String {
    process.caseInsensitiveCompare(flow.service) == .orderedSame
      ? process : "\(process) · \(flow.service)"
  }

  private var executableName: String {
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(flow.pid, &path, UInt32(path.count)) > 0 else { return flow.process }
    let full = String(decoding: path.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    return URL(filePath: full).lastPathComponent
  }
}
