// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wookey",
    defaultLocalization: "ko",
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
            resources: [.process("Resources")],
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
            resources: [.process("Resources/Assets.xcassets"), .process("Resources/en.lproj/Localizable.strings"), .process("Resources/ko.lproj/Localizable.strings"), .process("Resources/Fonts")]
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
