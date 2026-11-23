// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Monkey",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Monkey", targets: ["Monkey"]),
        .executable(name: "MonkeyLoginHelper", targets: ["MonkeyLoginHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(
            name: "MonkeyCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "Monkey",
            dependencies: [
                "MonkeyCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources/Assets.xcassets")]
        ),
        .executableTarget(
            name: "MonkeyLoginHelper"
        ),
        .testTarget(
            name: "MonkeyCoreTests",
            dependencies: ["MonkeyCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
