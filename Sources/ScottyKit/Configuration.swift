import Foundation

enum Configuration {
  static let host = "vpn.cmu.edu"
  static let identityProvider = "login.cmu.edu"
  static let group = "Campus VPN"
  static let realm = "ANDREW.CMU.EDU"
  static let keychainService = "Scotty"
  static let openconnect = "/opt/homebrew/bin/openconnect"
  static let tunnel = "/usr/local/libexec/scotty/tunnel"
  static let pidfile = URL(filePath: "/var/run/scotty.pid")
  static let state = URL(filePath: "/var/run/scotty.state")
  static let support = URL.applicationSupportDirectory.appending(path: "Scotty")
  static let intent = support.appending(path: "on")
  static let lock = support.appending(path: "sign-in.lock")
  static let hosts = support.appending(path: "hosts")
}
