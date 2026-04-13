// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoralCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "CoralCore", targets: ["CoralCore"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "CoralCore",
            dependencies: [
                .product(name: "AMSMB2", package: "AMSMB2"),
            ],
            path: "Sources/CoralCore"
        ),
        .target(
            name: "TestSupport",
            dependencies: ["CoralCore"],
            path: "Sources/TestSupport"
        ),
        .testTarget(
            name: "CoralCoreTests",
            dependencies: ["CoralCore", "TestSupport"],
            path: "Tests/CoralCoreTests",
            resources: [.copy("Resources/Fixtures")]
        ),
    ]
)
