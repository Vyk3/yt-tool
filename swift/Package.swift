// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YTTool",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "YTTool", targets: ["YTTool"]),
    ],
    targets: [
        .executableTarget(
            name: "YTTool",
            path: "YTTool",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "YTToolTests",
            dependencies: ["YTTool"],
            path: "Tests/YTToolTests"
        ),
    ]
)
