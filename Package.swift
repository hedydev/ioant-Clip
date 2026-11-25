// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "NoteCore", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "NoteCore", targets: ["NoteCore"])], targets: [.target(name: "NoteCore"), .testTarget(name: "NoteCoreTests", dependencies: ["NoteCore"])])
