import AppKit
import ScottyKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusMenu: StatusMenu?

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }

  func applicationDidFinishLaunching(_: Notification) {
    NSApp.mainMenu = MainMenu.make()
    statusMenu = StatusMenu(campus: Campus())
  }
}
