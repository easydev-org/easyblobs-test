// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EasyblobsTestHello",
    products: [
        .library(name: "EasyblobsTestHello", targets: ["EasyblobsTestHello"]),
    ],
    targets: [
        .target(name: "EasyblobsTestHello"),
        .testTarget(name: "EasyblobsTestHelloTests", dependencies: ["EasyblobsTestHello"]),
    ]
)
