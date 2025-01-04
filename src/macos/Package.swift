// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "TALDUnia",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TALDUnia",
            targets: ["TALDUnia"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/tensorflow/tensorflow.git", exact: "2.13.0"),
        .package(url: "https://github.com/AudioKit/AudioKit.git", exact: "5.6.0"),
        .package(url: "https://github.com/AudioKit/SoundpipeAudioKit.git", exact: "5.6.0"),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", exact: "6.5.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.25.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.62.0"),
        .package(url: "https://github.com/daltoniam/Starscream.git", exact: "4.0.6"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", exact: "4.2.2"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "TALDUnia",
            dependencies: [
                .product(name: "TensorFlowLiteSwift", package: "tensorflow"),
                .product(name: "AudioKit", package: "AudioKit"),
                .product(name: "SoundpipeAudioKit", package: "SoundpipeAudioKit"),
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxCocoa", package: "RxSwift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "TALDUnia",
            exclude: ["Tests", "Resources"],
            swiftSettings: [
                .define("ENABLE_METAL"),
                .define("ENABLE_TESTABILITY"),
                .unsafeFlags(["-O"])
            ]
        ),
        .testTarget(
            name: "TALDUniaTests",
            dependencies: ["TALDUnia"],
            path: "TALDUniaTests",
            swiftSettings: [
                .define("ENABLE_TESTABILITY")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)