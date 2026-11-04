// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Alex",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "alex", targets: ["AlexApp"])],
    targets: [
        .target(name: "AlexCore"),
        .executableTarget(name: "AlexApp", dependencies: ["AlexCore"]),
        .testTarget(name: "AlexCoreTests", dependencies: ["AlexCore"])
    ]
)
