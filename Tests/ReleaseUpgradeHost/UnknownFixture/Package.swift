// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UpgradeUnknownFixture",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "Riftlet", path: "../../..")],
    targets: [.executableTarget(name: "SeedUnknown", dependencies: [.product(name: "RiftletCore", package: "Riftlet")])]
)
