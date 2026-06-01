// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YTTool",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "YTTool", targets: ["YTTool"]),
    ],
    targets: [
        .executableTarget(
            name: "YTTool",
            path: "YTTool",
            exclude: [
                "Views/AppUpdateController.swift",
                "Info.plist",
                "YTTool.entitlements",
            ],
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
