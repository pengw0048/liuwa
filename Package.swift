// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Liuwa",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/mattt/AnyLanguageModel", from: "0.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Liuwa",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ],
            path: "Sources/Liuwa",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Liuwa/Info.plist"]),
            ]
        ),
    ]
)
