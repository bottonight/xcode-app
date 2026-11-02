// swift-tools-version: 5.9
// Placeholder so Xcode Cloud can resolve this local package before Flutter generates it.
// ci_post_clone.sh replaces this directory when it runs `flutter build ios --config-only`.

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .iOS("15.0"),
    ],
    products: [
        .library(
            name: "FlutterGeneratedPluginSwiftPackage",
            type: .static,
            targets: ["FlutterGeneratedPluginSwiftPackage"]
        ),
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage"
        ),
    ]
)
