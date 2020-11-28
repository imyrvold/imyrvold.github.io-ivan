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
        .package(name: "Publish", url: "https://github.com/johnsundell/publish.git", from: "0.7.0")
    ],
    targets: [
        .target(
            name: "Ivan",
            dependencies: ["Publish"]
        )
    ]
)
