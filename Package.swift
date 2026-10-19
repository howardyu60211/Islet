// swift-tools-version: 6.2
import PackageDescription

// 這是一個 UI App，所有程式碼預設都在 main actor 上執行。
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "DynamicIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"]),
    ],
    targets: [
        .target(
            name: "DynamicIslandKit",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "DynamicIsland",
            dependencies: ["DynamicIslandKit"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DynamicIslandKitTests",
            dependencies: ["DynamicIslandKit"],
            swiftSettings: swiftSettings
        ),
    ]
)
