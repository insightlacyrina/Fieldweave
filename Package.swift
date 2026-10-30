// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FieldWeave",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FieldWeave", targets: ["FieldWeave"]), .library(name: "FieldWeaveCore", targets: ["FieldWeaveCore"]), .library(name: "FieldWeaveAudio", targets: ["FieldWeaveAudio"]), .executable(name: "fieldweave-cli", targets: ["FieldWeaveCLI"]), .executable(name: "fieldweave-audio", targets: ["FieldWeaveAudioCLI"])],
    targets: [
        .target(name: "FieldWeaveCore", resources: [.copy("Resources")]),
        .target(name: "FieldWeaveAudio", dependencies: ["FieldWeaveCore"]),
        .executableTarget(name: "FieldWeaveCLI", dependencies: ["FieldWeaveCore"]),
        .executableTarget(name: "FieldWeaveAudioCLI", dependencies: ["FieldWeaveAudio", "FieldWeaveCore"]),
        .executableTarget(name: "FieldWeave", dependencies: ["FieldWeaveCore", "FieldWeaveAudio"], resources: [.copy("Resources")]),
        .testTarget(name: "FieldWeaveAudioTests", dependencies: ["FieldWeaveAudio", "FieldWeaveCore"]),
        .testTarget(name: "FieldWeaveCoreTests", dependencies: ["FieldWeaveCore"]),
        .testTarget(name: "FieldWeaveAppTests", dependencies: ["FieldWeave", "FieldWeaveCore"])
    ],
    swiftLanguageModes: [.v5]
)
