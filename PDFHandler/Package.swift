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
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PDFHandlerTests",
            dependencies: ["PDFHandler"],
            path: "Tests"
        )
    ]
)
