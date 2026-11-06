// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VietIME",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TelexEngine"),
        .executableTarget(name: "VietIME", dependencies: ["TelexEngine"]),
        .testTarget(name: "TelexEngineTests", dependencies: ["TelexEngine"]),
    ]
)
