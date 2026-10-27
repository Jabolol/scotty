import SwiftUI

struct StatusSubtitle: View {
  let text: String
  let problem: String?
  let summary: String

  init(_ text: String, problem: String?, summary: String) {
    self.text = text
    self.problem = problem
    self.summary = summary
  }

  var body: some View {
    HStack(spacing: 4) {
      if problem != nil {
        Image(systemName: "exclamationmark.triangle.fill")
          .symbolRenderingMode(.multicolor)
          .imageScale(.small)
      }
      Text(problem == nil ? text : summary)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .help(problem ?? "")
  }
}
