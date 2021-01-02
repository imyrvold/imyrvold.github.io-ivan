// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Ivan",
    products: [
        .executable(
            name: "Ivan",
            targets: ["Ivan"]
        )
    ],
    dependencies: [
        .package(name: "Publish", url: "https://github.com/johnsundell/publish.git", from: "0.7.0"),
        .package(name: "SplashPublishPlugin", url: "https://github.com/johnsundell/splashpublishplugin", from: "0.1.0"),
        .package(name: "IvanPublishTheme", url: "https://github.com/imyrvold/IvanPublishTheme.git", from: "1.0.0"),
        .package(name: "BrianPublishTheme", url: "https://github.com/dinsen/brianpublishtheme", from: "0.1.0"),
//        .package(name: "HighlightJSPublishPlugin", url: "https://github.com/alex-ross/highlightjspublishplugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "Ivan",
            dependencies: ["Publish", "SplashPublishPlugin", "IvanPublishTheme", "BrianPublishTheme"/*, "HighlightJSPublishPlugin"*/]
        )
    ]
)
