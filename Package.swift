// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "Ivan",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Ivan",
            targets: ["Ivan"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/johnsundell/publish.git", from: "0.7.0"),
        .package(url: "https://github.com/johnsundell/splashpublishplugin", from: "0.1.0"),
        .package(url: "https://github.com/imyrvold/IvanPublishTheme.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Ivan",
            dependencies: ["Publish", "SplashPublishPlugin", "IvanPublishTheme"]
        )
    ]
)
