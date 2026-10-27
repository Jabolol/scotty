import SwiftUI

struct SectionTitle: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, MenuMetrics.inset)
      .frame(height: MenuMetrics.titleHeight)
  }
}
