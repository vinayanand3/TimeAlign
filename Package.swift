// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimeAlign",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TimeAlign", path: "Sources"),
        .testTarget(name: "TimeAlignTests", dependencies: ["TimeAlign"], path: "Tests"),
    ]
)
