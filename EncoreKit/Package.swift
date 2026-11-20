// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "EncoreKit",
    platforms: [.macOS(.v27), .iOS(.v26)],
    products: [
        .library(name: "EncoreKit", targets: ["EncoreKit"]),
        .executable(name: "encore-validate", targets: ["encore-validate"]),
    ],
    targets: [
        .target(name: "EncoreKit", resources: [.copy("Rendering/Web")]),
        .executableTarget(name: "encore-validate", dependencies: ["EncoreKit"]),
        .testTarget(name: "EncoreKitTests", dependencies: ["EncoreKit"], resources: [.copy("Fixtures")])
    ]
)
