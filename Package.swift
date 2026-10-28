// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Riftlet",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RiftletCore", targets: ["RiftletCore"]),
        .executable(name: "Riftlet", targets: ["RiftletApp"]),
        .executable(name: "RiftletFeedbackDemo", targets: ["RiftletFeedbackDemo"]),
        .executable(name: "RiftletGUIAcceptance", targets: ["RiftletGUIAcceptance"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "RiftletFeedback", dependencies: ["CSQLite"]),
        .target(name: "RiftletFeedbackUI", dependencies: ["RiftletFeedback", "RiftletUI"]),
        .executableTarget(name: "RiftletFeedbackDemo", dependencies: ["RiftletFeedback", "RiftletFeedbackUI"]),
        .testTarget(name: "RiftletFeedbackTests", dependencies: ["RiftletFeedback", "CSQLite"]),
        .testTarget(name: "RiftletFeedbackUITests", dependencies: ["RiftletFeedbackUI", "RiftletFeedback"]),
        .target(name: "RiftletCore", dependencies: ["CSQLite"]),
        .target(name: "RiftletCapture", dependencies: ["RiftletCore"]),
        .target(name: "RiftletUI", dependencies: ["RiftletCore", "RiftletCapture"]),
        .target(name: "RiftletAdapters", dependencies: ["RiftletCore"], resources: [.process("Resources")]),
        .executableTarget(name: "RiftletGUIAcceptance", dependencies: ["RiftletUI", "RiftletCore", "RiftletFeedback", "RiftletFeedbackUI"]),
        .executableTarget(name: "RiftletApp", dependencies: ["RiftletCore", "RiftletCapture", "RiftletUI", "RiftletAdapters", "RiftletFeedback", "RiftletFeedbackUI"]),
        .testTarget(name: "RiftletCoreTests", dependencies: ["RiftletCore", "CSQLite"]),
        .testTarget(name: "RiftletCaptureTests", dependencies: ["RiftletCapture", "RiftletCore", "CSQLite"]),
        .testTarget(name: "RiftletUITests", dependencies: ["RiftletUI", "RiftletCore"]),
        .testTarget(name: "RiftletAppTests", dependencies: ["RiftletApp", "RiftletUI", "RiftletCapture", "RiftletAdapters"]),
        .testTarget(name: "RiftletAdaptersTests", dependencies: ["RiftletAdapters", "RiftletCore"],
                    resources: [.process("Fixtures")])
    ]
)
