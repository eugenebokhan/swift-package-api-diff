// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "swift-package-api-diff",
    products: [
        Product.executable(name: "swift-package-api-diff",
                           targets: ["swift-package-api-diff"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser",
                 from: "0.3.1"),
        .package(url: "https://github.com/JohnSundell/Files",
                 from: "4.0.2")
    ],
    targets: [
        .target(name: "swift-package-api-diff",
                dependencies: [
                    .product(name: "ArgumentParser",
                             package: "swift-argument-parser"),
                    .product(name: "Files",
                             package: "Files")
                ],
                resources: [.copy("Utils/swift-macosx-x86_64/")])
    ]
)
