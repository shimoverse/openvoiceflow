// swift-tools-version: 5.9
import PackageDescription

// SwiftPM manifest for the OpenVoiceFlow native app.
//
// Platform floor and dependency versions MUST mirror project.yml exactly —
// they diverged once, and a contributor running `swift build` resolved a
// WhisperKit two majors older than the code was written for.
//
// NOTE: A menu-bar/agent app is normally shipped as an .app bundle built by
// Xcode (for Info.plist, entitlements, code signing, and notarization). This
// SwiftPM package builds the same sources as a runnable executable for fast
// iteration (`swift build && swift run`) and CI syntax checks. BUILD_RUNBOOK.md
// covers wrapping it into a signed .app. Keep both paths building the same
// Sources/ so there is a single source of truth.
let package = Package(
    name: "OpenVoiceFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenVoiceFlow", targets: ["OpenVoiceFlow"]),
    ],
    dependencies: [
        // On-device Swift Whisper (CoreML/Metal). Pin to a released tag on the Mac.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.18.0"),
        // In-app updates with an EdDSA-signed appcast.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "OpenVoiceFlow",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/OpenVoiceFlow"
        ),
    ]
)
