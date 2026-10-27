// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Riftlet",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RiftletCore", targets: ["RiftletCore"]),
        .executable(name: "Riftlet", targets: ["RiftletApp"]),
        .executable(name: "RiftletGUIAcceptance", targets: ["RiftletGUIAcceptance"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "RiftletCore", dependencies: ["CSQLite"]),
        .target(name: "RiftletCapture", dependencies: ["RiftletCore"]),
        .target(name: "RiftletUI", dependencies: ["RiftletCore"]),
        .target(name: "RiftletAdapters", dependencies: ["RiftletCore"], resources: [.process("Resources")]),
        .executableTarget(name: "RiftletGUIAcceptance", dependencies: ["RiftletUI", "RiftletCore"]),
        .executableTarget(name: "RiftletApp", dependencies: ["RiftletCore", "RiftletCapture", "RiftletUI", "RiftletAdapters"]),
        .testTarget(name: "RiftletCoreTests", dependencies: ["RiftletCore"]),
        .testTarget(name: "RiftletCaptureTests", dependencies: ["RiftletCapture", "RiftletCore", "CSQLite"]),
        .testTarget(name: "RiftletUITests", dependencies: ["RiftletUI", "RiftletCore"]),
        .testTarget(name: "RiftletAdaptersTests", dependencies: ["RiftletAdapters", "RiftletCore"],
                    resources: [.process("Fixtures")])
    ]
)
