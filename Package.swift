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
        .package(
            url: "https://github.com/nodal-ide/tree-sitter-dotenv.git",
            revision: "28a07b76b0e1d7f192a819cce1a2b444b609581b"
        ),
        .package(
            url: "https://github.com/nodal-ide/tree-sitter-gitignore.git",
            revision: "3e81ac0449a025fea02282063f127b540b088ebe"
        ),
        .package(
            url: "https://github.com/nodal-ide/tree-sitter-apacheconf.git",
            revision: "62447ac088bc86464538fe9ee98c9e7dcd8a9da7"
        ),
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
