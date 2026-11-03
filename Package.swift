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
        .executable(name: "ErrorRateHarness", targets: ["ErrorRateHarness"]),
        .executable(name: "ProviderBench", targets: ["ProviderBench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "SignoffCore",
            dependencies: [],
            path: "Sources/SignoffCore",
            exclude: ["Resources"],
            resources: [
                .process("Resources/Prompts"),
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
        .executableTarget(
            name: "ErrorRateHarness",
            dependencies: ["SignoffCore"],
            path: "Harness"
        ),
        .executableTarget(
            name: "ProviderBench",
            dependencies: ["SignoffCore"],
            path: "Bench"
        ),

        .testTarget(
            name: "SignoffCoreTests",
            dependencies: ["SignoffCore", .product(name: "Testing", package: "swift-testing")],
            path: "Tests/SignoffCoreTests"
        ),
    ]
)
