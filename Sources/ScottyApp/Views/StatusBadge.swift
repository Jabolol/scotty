import SwiftUI

struct StatusBadge<Glyph: View>: View {
  let isActive: Bool
  @ViewBuilder let glyph: Glyph

  var body: some View {
    Circle()
      .fill(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
      .frame(width: MenuMetrics.badgeSize, height: MenuMetrics.badgeSize)
      .overlay { glyph.foregroundStyle(isActive ? .white : .primary) }
      .animation(.easeInOut(duration: 0.2), value: isActive)
  }
}
