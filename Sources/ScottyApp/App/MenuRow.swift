import AppKit
import SwiftUI

enum MenuMetrics {
  static let width: CGFloat = 315
  static let inset: CGFloat = 16
  static let headerHeight: CGFloat = 33
  static let titleHeight: CGFloat = 24
  static let rowHeight: CGFloat = 32
  static let badgeSize: CGFloat = 26
  static let spacing: CGFloat = 8
  static let highlightInset: CGFloat = 5
  static let highlightRadius: CGFloat = 8
}

@MainActor
@Observable
final class RowState {
  var isHighlighted = false
  var isExpanded = false
}

@MainActor
final class MenuRow: NSView {
  let state = RowState()
  var action: (@MainActor () -> Void)?
  private let dismisses: Bool
  private let hostingView: NSView

  init(
    dismisses: Bool = true,
    action: (@MainActor () -> Void)? = nil,
    @ViewBuilder content: (RowState) -> some View
  ) {
    self.dismisses = dismisses
    self.action = action
    hostingView = NSHostingView(
      rootView: content(state).frame(width: MenuMetrics.width, alignment: .leading))
    super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 1))
    autoresizingMask = [.width]
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
    fit()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { nil }

  func fit() {
    setFrameSize(NSSize(width: MenuMetrics.width, height: hostingView.fittingSize.height))
    hostingView.frame = bounds
  }

  @objc func performAction(_: NSMenuItem) {
    action?()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard action != nil else { return super.hitTest(point) }
    return bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func mouseUp(with _: NSEvent) {
    guard let action else { return }
    if dismisses {
      enclosingMenuItem?.menu?.cancelTracking()
    }
    action()
  }
}

extension NSMenuItem {
  @MainActor
  convenience init(row: MenuRow, isEnabled: Bool = true) {
    self.init()
    view = row
    self.isEnabled = isEnabled
    target = row
    action = #selector(MenuRow.performAction)
  }

  @MainActor
  static func sectionTitle(_ text: String) -> NSMenuItem {
    NSMenuItem(row: MenuRow { _ in SectionTitle(text) }, isEnabled: false)
  }
}
