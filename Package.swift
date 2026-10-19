// swift-tools-version: 6.2
import PackageDescription

// 這是一個 UI App，所有程式碼預設都在 main actor 上執行。
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "Islet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Islet", targets: ["Islet"]),
    ],
    targets: [
        .target(
            name: "IsletKit",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "Islet",
            dependencies: ["IsletKit"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "IsletKitTests",
            dependencies: ["IsletKit"],
            swiftSettings: swiftSettings
        ),
    ]
)
