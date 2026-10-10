// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NativeSlicerA1",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/emqx/CocoaMQTT.git", from: "2.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "NativeSlicerA1",
            dependencies: [.product(name: "CocoaMQTT", package: "CocoaMQTT")],
            path: "Sources/NativeSlicerA1",
            resources: [.copy("Resources/Profiles")]
        ),
        .testTarget(
            name: "NativeSlicerA1Tests",
            dependencies: ["NativeSlicerA1"],
            path: "Tests/NativeSlicerA1Tests"
        ),
    ]
)
