// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeEditLanguages",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "CodeEditLanguages",
            targets: ["CodeEditLanguages"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ChimeHQ/SwiftTreeSitter.git",
            from: "0.9.0"
        ),
        .package(path: "../tree-sitter-dotenv"),
        .package(path: "../tree-sitter-gitignore"),
        .package(path: "../tree-sitter-apacheconf"),
    ],
    targets: [
        .target(
            name: "CodeEditLanguages",
            dependencies: [
                "CodeLanguagesContainer",
                "SwiftTreeSitter",
                .product(name: "TreeSitterDotenv", package: "tree-sitter-dotenv"),
                .product(name: "TreeSitterGitignore", package: "tree-sitter-gitignore"),
                .product(name: "TreeSitterApacheconf", package: "tree-sitter-apacheconf"),
            ],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [.linkedLibrary("c++")]
        ),

        .binaryTarget(
            name: "CodeLanguagesContainer",
            path: "CodeLanguagesContainer.xcframework.zip"
        ),

        .testTarget(
            name: "CodeEditLanguagesTests",
            dependencies: ["CodeEditLanguages"]
        ),
    ]
)
