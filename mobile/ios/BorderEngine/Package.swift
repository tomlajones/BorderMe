// swift-tools-version: 5.9
import PackageDescription

// The engine's sources are also compiled straight into the Runner app and the
// Share extension. This package exists so the engine can be tested on a Mac
// with `swift test`, without a simulator.
let package = Package(
    name: "BorderEngine",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "BorderEngine", targets: ["BorderEngine"])],
    targets: [
        .target(name: "BorderEngine"),
        .testTarget(name: "BorderEngineTests", dependencies: ["BorderEngine"])
    ]
)
