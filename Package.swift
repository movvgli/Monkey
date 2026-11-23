// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wookey",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Wookey", targets: ["Wookey"]),
        .executable(name: "WookeyLoginHelper", targets: ["WookeyLoginHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(
            name: "WookeyCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "Wookey",
            dependencies: [
                "WookeyCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources/Assets.xcassets")]
        ),
        .executableTarget(
            name: "WookeyLoginHelper"
        ),
        .testTarget(
            name: "WookeyCoreTests",
            dependencies: ["WookeyCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
