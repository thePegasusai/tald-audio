// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "TALDUnia",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "TALDUnia",
            targets: ["TALDUnia"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/tensorflow/tensorflow.git", exact: "2.13.0"),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "6.5.0")),
        .package(url: "https://github.com/daltoniam/Starscream.git", .upToNextMajor(from: "4.0.4")),
        .package(url: "https://github.com/realm/realm-swift.git", exact: "10.41.0"),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMajor(from: "1.9.5"))
    ],
    targets: [
        .target(
            name: "TALDUnia",
            dependencies: [
                .product(name: "TensorFlowLiteSwift", package: "tensorflow"),
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxCocoa", package: "RxSwift"),
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "RealmSwift", package: "realm-swift"),
                .product(name: "SwiftyBeaver", package: "SwiftyBeaver")
            ],
            path: "Sources",
            exclude: ["Tests", "Resources"]
        ),
        .testTarget(
            name: "TALDUniaTests",
            dependencies: [
                "TALDUnia",
                .product(name: "RxBlocking", package: "RxSwift"),
                .product(name: "RxTest", package: "RxSwift")
            ],
            path: "Tests"
        )
    ],
    swiftLanguageVersions: [.v5]
)