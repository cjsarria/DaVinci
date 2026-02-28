// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DaVinci",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "DaVinci", targets: ["DaVinci"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.3.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
        .package(url: "https://github.com/pinterest/PINRemoteImage.git", from: "3.0.2")
    ],
    targets: [
        .target(
            name: "DaVinci",
            dependencies: []
        ),
        .testTarget(
            name: "DaVinciTests",
            dependencies: ["DaVinci"]
        ),
        .testTarget(
            name: "DaVinciBenchmarksTests",
            dependencies: [
                "DaVinci",
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "PINRemoteImage", package: "PINRemoteImage")
            ],
            path: "Tests/DaVinciBenchmarksTests",
            resources: [.process("Resources")]
        )
    ]
)
