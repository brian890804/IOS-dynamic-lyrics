// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DynamicLyrics",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DynamicLyricsCore",
            targets: ["DynamicLyricsCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DynamicLyricsCore",
            path: "ios-app/DynamicLyrics",
            exclude: ["Info.plist", "AppIcon.svg", "AppIcon-1024.jpg"]
        )
    ]
)
