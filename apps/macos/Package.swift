// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VERITYNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VerityDomain", targets: ["VerityDomain"]),
        .library(name: "VerityVault", targets: ["VerityVault"]),
        .library(name: "VerityAI", targets: ["VerityAI"]),
        .library(name: "VerityKit", targets: ["VerityKit"]),
        .library(name: "VerityDesign", targets: ["VerityDesign"]),
        .executable(name: "VERITY", targets: ["VERITY"]),
        .executable(name: "verity-uninstaller", targets: ["VERITYUninstaller"]),
        .executable(name: "verity-vault-snapshot", targets: ["VerityVaultSnapshot"]),
        .executable(name: "verity-native-checks", targets: ["VerityNativeChecks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2"),
    ],
    targets: [
        .target(name: "VerityDomain"),
        .target(name: "VerityVault", dependencies: ["VerityDomain"]),
        .target(name: "VerityAI", dependencies: ["VerityDomain", "VerityVault"]),
        .target(name: "VerityKit", dependencies: ["VerityDomain", "VerityVault", "VerityAI"]),
        .target(
            name: "VerityDesign",
            dependencies: ["VerityDomain"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "VERITY",
            dependencies: [
                "VerityDomain", "VerityVault", "VerityAI", "VerityKit", "VerityDesign",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "VerityNativeChecks",
            dependencies: ["VerityDomain", "VerityVault", "VerityAI", "VerityKit"]
        ),
        .executableTarget(name: "VERITYUninstaller"),
        .executableTarget(
            name: "VerityVaultSnapshot",
            dependencies: ["VerityDomain", "VerityVault"]
        ),
        .testTarget(name: "VerityDomainTests", dependencies: ["VerityDomain"]),
        .testTarget(name: "VerityVaultTests", dependencies: ["VerityDomain", "VerityVault"]),
        .testTarget(name: "VerityAITests", dependencies: ["VerityDomain", "VerityVault", "VerityAI"]),
        .testTarget(name: "VerityKitTests", dependencies: ["VerityDomain", "VerityVault", "VerityAI", "VerityKit"]),
        .testTarget(name: "VerityDesignTests", dependencies: ["VerityDesign"]),
    ]
)
