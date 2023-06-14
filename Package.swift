// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "grpc-health-probe",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.21.0"),
        .package(url: "https://github.com/grpc/grpc-swift", from: "1.16.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.2"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.2"),
    ],
    targets: [
        .executableTarget(
            name: "grpc-health-probe",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ],
            exclude: [
                "grpc-swift-config.json",
                "swift-protobuf-config.json"
            ],
            plugins: [
                .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf"),
                .plugin(name: "GRPCSwiftPlugin", package: "grpc-swift")
            ]
        ),
        .testTarget(
            name: "grpc-health-probeTests",
            dependencies: [
                "grpc-health-probe"
            ]
        )
    ]
)
