import AppKit
import ScottyKit
import SwiftUI

struct ConnectionList: View {
  static let visible = 8
  private static let stride = MenuMetrics.rowHeight + 4

  @Environment(Traffic.self) private var traffic
  @State private var hovered: Flow.ID?
  @State private var copied: Flow.ID?

  var body: some View {
    if traffic.flows.isEmpty {
      Text("No connections through the tunnel")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, MenuMetrics.inset)
        .padding(.top, 4)
        .padding(.bottom, 8)
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(traffic.flows) { flow in
            let host = traffic.hostnames[flow.remote] ?? flow.remote
            Button {
              copy(NSEvent.modifierFlags.contains(.option) ? flow.remote : host, from: flow)
            } label: {
              ConnectionRow(
                flow: flow, host: host, isHighlighted: hovered == flow.id,
                isCopied: copied == flow.id)
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 ? flow.id : hovered == flow.id ? nil : hovered }
            .accessibilityHint("Copies the host name. Option-click copies the IP address.")
          }
        }
      }
      .frame(height: height)
      .padding(.bottom, 4)
    }
  }

  private var height: CGFloat {
    let count = traffic.flows.count
    return Self.stride * (count < Self.visible ? CGFloat(count) : CGFloat(Self.visible) - 0.5)
  }

  private func copy(_ text: String, from flow: Flow) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    copied = flow.id
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      if copied == flow.id { copied = nil }
    }
  }
}

private struct ConnectionRow: View {
  let flow: Flow
  let host: String
  let isHighlighted: Bool
  let isCopied: Bool

  var body: some View {
    let app = NSRunningApplication(processIdentifier: flow.pid)
    HighlightableRow(isHighlighted: isHighlighted) {
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
      Group {
        if isCopied {
          Label("Copied", systemImage: "checkmark").labelStyle(.titleAndIcon)
        } else {
          Text(Int64(clamping: flow.received + flow.sent), format: .byteCount(style: .file))
            .monospacedDigit()
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .contentTransition(.opacity)
      .animation(.smooth(duration: 0.2), value: isCopied)
    }
    .contentShape(.rect)
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
