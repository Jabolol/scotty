import SwiftUI

struct HeaderRow: View {
  @Environment(Campus.self) private var campus

  var body: some View {
    HStack {
      Text("Scotty").fontWeight(.bold)
      Spacer()
      ToggleSwitch(isOn: campus.isConnected).opacity(campus.isBusy ? 0.5 : 1)
    }
    .padding(.horizontal, MenuMetrics.inset)
    .frame(height: MenuMetrics.headerHeight)
  }
}

private struct ToggleSwitch: View {
  let isOn: Bool

  var body: some View {
    Capsule()
      .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
      .frame(width: 54, height: 24)
      .overlay(alignment: isOn ? .trailing : .leading) {
        Capsule()
          .fill(.white.opacity(0.9))
          .frame(width: 32, height: 20)
          .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
          .padding(2)
      }
      .animation(.spring(duration: 0.3, bounce: 0.15), value: isOn)
  }
}
