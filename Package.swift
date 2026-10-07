// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PnPOMatic",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "PnPCore", targets: ["PnPCore"]),
        .executable(name: "PnPOMaticApp", targets: ["PnPOMaticApp"]),
    ],
    targets: [
        .target(name: "PnPCore"),
        .executableTarget(
            name: "PnPOMaticApp",
            dependencies: ["PnPCore"]
        ),
        .testTarget(
            name: "PnPCoreTests",
            dependencies: ["PnPCore"]
        ),
    ]
)
