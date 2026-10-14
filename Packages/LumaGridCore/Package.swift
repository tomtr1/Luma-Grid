// swift-tools-version:6.0
//
// LumaGridCore contains everything in LumaGrid that does not depend on Apple UI,
// StoreKit, or the Google Mobile Ads SDK. Keeping it Foundation-only means the
// game rules and monetization policies can be compiled and unit tested with
// `swift test` on any machine with a Swift toolchain (macOS or Linux).

import PackageDescription

let package = Package(
    name: "LumaGridCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LumaGridEngine", targets: ["LumaGridEngine"]),
        .library(name: "LumaGridServices", targets: ["LumaGridServices"]),
    ],
    targets: [
        // Pure game rules: board, pieces, scoring, Lumen Pulse, game over.
        .target(name: "LumaGridEngine"),
        // Persistence model, economy, ad pacing, purchase ledger. No UI, no SDKs.
        .target(name: "LumaGridServices", dependencies: ["LumaGridEngine"]),
        .testTarget(name: "LumaGridEngineTests", dependencies: ["LumaGridEngine"]),
        .testTarget(
            name: "LumaGridServicesTests",
            dependencies: ["LumaGridServices", "LumaGridEngine"]
        ),
    ]
)
