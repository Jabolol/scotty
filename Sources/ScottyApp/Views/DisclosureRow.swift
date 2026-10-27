import SwiftUI

struct DisclosureRow: View {
  let title: String
  let state: RowState

  var body: some View {
    HighlightableRow(state: state, height: MenuMetrics.titleHeight) {
      Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
      Spacer()
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .rotationEffect(.degrees(state.isExpanded ? 90 : 0))
        .animation(.smooth(duration: 0.2), value: state.isExpanded)
    }
  }
}
