// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GitHubPRBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GitHubPRBar",
            path: "Sources"
        )
    ]
)
