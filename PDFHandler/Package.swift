// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PDFHandler",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PDFHandler",
            targets: ["PDFHandler"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PDFHandler",
            dependencies: [],
            path: "PDFHandler",
            exclude: [
                "Resources/Info.plist",
                "Resources/PDFHandler.entitlements",
                "Resources/Assets.xcassets/AppIcon.appiconset/generate_icons.sh"
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "PDFHandlerTests",
            dependencies: ["PDFHandler"],
            path: "PDFHandlerTests"
        )
    ]
)
