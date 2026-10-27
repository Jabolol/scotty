import SwiftUI

struct TicketRow: View {
  @Environment(Campus.self) private var campus
  let state: RowState

  var body: some View {
    HighlightableRow(isHighlighted: state.isHighlighted) {
      StatusBadge(isActive: campus.ticket.map { $0.expires > .now } ?? false) {
        Image(systemName: "ticket.fill").font(.system(size: 11, weight: .semibold))
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(campus.ticket.map { String($0.principal.prefix { $0 != "@" }) } ?? "Andrew ID")
        TimelineView(.everyMinute) { _ in
          StatusSubtitle(
            expiry,
            problem: campus.phase == .idle ? campus.ticketProblem : nil,
            summary: "Couldn't renew"
          )
        }
      }
      Spacer()
      if state.isHighlighted && !campus.isBusy {
        Text("Renew").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var expiry: String {
    if campus.phase == .renewing { return "Renewing…" }
    guard let ticket = campus.ticket else { return "No ticket" }
    let relative = ticket.expires.formatted(.relative(presentation: .named))
    return ticket.expires > .now ? "Expires \(relative)" : "Expired \(relative)"
  }
}
