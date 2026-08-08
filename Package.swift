// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Signoff",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "SignoffCore", targets: ["SignoffCore"]),
        .library(name: "SignoffUI", targets: ["SignoffUI"]),
        .executable(name: "Signoff", targets: ["SignoffApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SignoffCore",
            dependencies: [],
            path: "Sources/SignoffCore",
            exclude: ["Resources"],
            resources: [
                .process("Resources/Prompts"),
                .process("Resources/Corpus"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .target(
            name: "SignoffUI",
            dependencies: ["SignoffCore"],
            path: "Sources/SignoffUI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "SignoffApp",
            dependencies: [
                "SignoffCore",
                "SignoffUI",
            ],
            path: "Sources/SignoffApp",
            exclude: ["Info.plist"],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "SignoffCoreTests",
            dependencies: ["SignoffCore"],
            path: "Tests/SignoffCoreTests",
            resources: [
                .process("Resources/Prompts"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "SignoffUITests",
            dependencies: ["SignoffUI"],
            path: "Tests/SignoffUITests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
