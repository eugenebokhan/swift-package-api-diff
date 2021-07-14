// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "swift-package-api-diff",
    platforms: [.macOS(.v10_15)],
    products: [
        Product.executable(name: "swift-package-api-diff",
                           targets: ["swift-package-api-diff"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git",
                 .exact("0.3.2")),
        .package(name: "SwiftPM",
                 url: "https://github.com/apple/swift-package-manager.git",
                 .revision("swift-5.4.2-RELEASE")),
        .package(url: "https://github.com/JohnSundell/Files",
                 from: "4.0.2")
    ],
    targets: [
        .target(name: "swift-package-api-diff",
                dependencies: [
                    .product(name: "ArgumentParser",
                             package: "swift-argument-parser"),
                    .product(name: "Files",
                             package: "Files"),
                    .product(name: "SwiftPM-auto",
                             package: "SwiftPM"),
                ])
    ]
)
