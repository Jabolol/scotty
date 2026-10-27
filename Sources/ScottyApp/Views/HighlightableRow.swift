import SwiftUI

struct HighlightableRow<Content: View>: View {
  let state: RowState
  var height = MenuMetrics.rowHeight
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: MenuMetrics.spacing) { content }
      .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
      .padding(.horizontal, MenuMetrics.inset - MenuMetrics.highlightInset)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: MenuMetrics.highlightRadius, style: .continuous)
          .fill(state.isHighlighted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
      )
      .padding(.horizontal, MenuMetrics.highlightInset)
  }
}
