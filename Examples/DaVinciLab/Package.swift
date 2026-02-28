// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DaVinciLab",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LabCore", targets: ["LabCore"]),
        .library(name: "EngineDaVinci", targets: ["EngineDaVinci"]),
        .library(name: "EngineKingfisher", targets: ["EngineKingfisher"]),
        .library(name: "EnginePINRemoteImage", targets: ["EnginePINRemoteImage"])
    ],
    dependencies: [
        .package(path: "../../"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0"),
        .package(url: "https://github.com/pinterest/PINRemoteImage.git", from: "3.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DaVinciLabApp",
            dependencies: [
                "LabCore",
                "EngineDaVinci",
                "EngineKingfisher",
                "EnginePINRemoteImage"
            ],
            path: "App/Sources/DaVinciLabApp",
            exclude: ["Resources/Info.plist"]
        ),

        .target(
            name: "LabCore",
            dependencies: [],
            path: "Modules/LabCore/Sources/LabCore",
            resources: [.process("Resources")]
        ),

        .target(
            name: "EngineDaVinci",
            dependencies: [
                "LabCore",
                .product(name: "DaVinci", package: "DaVinci")
            ],
            path: "Modules/EngineDaVinci/Sources/EngineDaVinci"
        ),

        .target(
            name: "EngineKingfisher",
            dependencies: [
                "LabCore",
                .product(name: "Kingfisher", package: "Kingfisher")
            ],
            path: "Modules/EngineKingfisher/Sources/EngineKingfisher"
        ),

        .target(
            name: "EnginePINRemoteImage",
            dependencies: [
                "LabCore",
                .product(name: "PINRemoteImage", package: "PINRemoteImage")
            ],
            path: "Modules/EnginePINRemoteImage/Sources/EnginePINRemoteImage"
        )
    ]
)
