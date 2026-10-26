// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Riftlet",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RiftletCore", targets: ["RiftletCore"]),
        .executable(name: "Riftlet", targets: ["RiftletApp"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "RiftletCore", dependencies: ["CSQLite"]),
        .target(name: "RiftletCapture", dependencies: ["RiftletCore"]),
        .target(name: "RiftletUI", dependencies: ["RiftletCore"]),
        .executableTarget(name: "RiftletApp", dependencies: ["RiftletCore", "RiftletCapture", "RiftletUI"]),
        .testTarget(name: "RiftletCoreTests", dependencies: ["RiftletCore"]),
        .testTarget(name: "RiftletCaptureTests", dependencies: ["RiftletCapture", "RiftletCore"]),
        .testTarget(name: "RiftletUITests", dependencies: ["RiftletUI", "RiftletCore"])
    ]
)
