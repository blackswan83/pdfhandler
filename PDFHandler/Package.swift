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
            // Non-Swift files that SwiftPM should not attempt to process.
            // The asset catalog is compiled directly by scripts/build-dmg.sh
            // via actool when real icon PNGs are present; Info.plist and
            // entitlements are copied into the .app by the build script.
            exclude: [
                "Resources/Info.plist",
                "Resources/PDFHandler.entitlements",
                "Resources/Assets.xcassets"
            ]
        ),
        .testTarget(
            name: "PDFHandlerTests",
            dependencies: ["PDFHandler"],
            path: "PDFHandlerTests"
        )
    ]
)
