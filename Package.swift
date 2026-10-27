// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Scotty",
  platforms: [.macOS(.v15)],
  targets: [
    .target(name: "ScottyKit"),
    .executableTarget(name: "ScottyApp", dependencies: ["ScottyKit"]),
    .executableTarget(name: "scotty", dependencies: ["ScottyKit"]),
  ]
)
