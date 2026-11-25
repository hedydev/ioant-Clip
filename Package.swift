// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ClipCore", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "ClipCore", targets: ["ClipCore"])], targets: [.target(name: "ClipCore"), .testTarget(name: "ClipCoreTests", dependencies: ["ClipCore"])])
