// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PubMergeCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PubMergeCore", targets: ["PubMergeCore"]),
        .executable(name: "GenerateFixtures", targets: ["GenerateFixtures"])
    ],
    targets: [
        .target(
            name: "PubMergeCore",
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "GenerateFixtures",
            dependencies: ["PubMergeCore"]
        ),
        .testTarget(
            name: "PubMergeCoreTests",
            dependencies: ["PubMergeCore"]
        )
    ]
)
