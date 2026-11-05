// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GPTMonitorBar",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(
            name: "GPTMonitorBar",
            dependencies: ["QuotaCore"],
            resources: [.copy("Resources/ChatGPTMark.png")]
        ),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
        .testTarget(name: "GPTMonitorBarTests", dependencies: ["GPTMonitorBar"])
    ]
)
