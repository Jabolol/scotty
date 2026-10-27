import AppKit

@MainActor
enum StatusIcon {
  static let on = glyph(alpha: 1)
  static let off = glyph(alpha: 0.5)

  private static func glyph(alpha: CGFloat) -> NSImage {
    guard let source = Bundle.main.image(forResource: "StatusIcon") else { return NSImage() }
    let image = NSImage(size: source.size, flipped: false) { rect in
      source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Scotty"
    return image
  }
}
