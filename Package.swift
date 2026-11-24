// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocoBlobKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LocoBlobKit",
            targets: ["LocoBlobKit"]
        )
    ],
    targets: [
        .target(
            name: "LocoBlobKit",
            path: "Sources/LocoBlobKit"
        ),
        .testTarget(
            name: "LocoBlobKitTests",
            dependencies: ["LocoBlobKit"],
            path: "Tests/LocoBlobKitTests"
        )
    ]
)
