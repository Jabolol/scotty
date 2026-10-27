import SwiftUI

struct NetworkRow: View {
  @Environment(Campus.self) private var campus
  let state: RowState

  var body: some View {
    HighlightableRow(isHighlighted: state.isHighlighted) {
      StatusBadge(isActive: campus.link != nil && !campus.isLoading) {
        if campus.isLoading {
          ProgressView().controlSize(.small)
        } else {
          Image(nsImage: StatusIcon.on)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: 13)
        }
      }
      VStack(alignment: .leading, spacing: 1) {
        Text("Carnegie Mellon")
        TimelineView(.everyMinute) { _ in
          StatusSubtitle(
            status,
            problem: campus.phase == .idle ? campus.networkProblem : nil,
            summary: "Couldn't connect"
          )
        }
      }
    }
  }

  private var status: String {
    switch campus.phase {
    case .signingIn: campus.isAutomatic ? "Reconnecting…" : "Waiting for sign-in…"
    case .connecting: campus.isAutomatic ? "Reconnecting…" : "Connecting…"
    case .disconnecting: campus.isAutomatic ? "Renewing session…" : "Disconnecting…"
    case .idle, .renewing: idleStatus
    }
  }

  private var idleStatus: String {
    guard let link = campus.link else { return "Not Connected" }
    if let expires = link.expires, expires.timeIntervalSinceNow < 3600 {
      return "Session ends in \(duration(expires.timeIntervalSinceNow))"
    }
    return "Connected · \(duration(Date.now.timeIntervalSince(link.since)))"
  }

  private func duration(_ seconds: TimeInterval) -> String {
    Duration.seconds(max(seconds, 60))
      .formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2))
  }
}
