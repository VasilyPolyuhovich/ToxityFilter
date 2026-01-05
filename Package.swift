// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ToxityFilter",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ToxityFilter",
            targets: ["ToxityFilter"]
        ),
    ],
    targets: [
        .target(
            name: "ToxityFilter",
            dependencies: [],
            resources: [
                // ML Model - ToxicityDetector (toxic-bert)
                .process("Resources/ToxicityDetector.mlpackage"),

                // Vocabulary and metadata files
                .process("Resources/ToxicityDetector_vocab.txt"),
                .process("Resources/ToxicityDetector_special_tokens.txt"),
                .process("Resources/ToxicityDetector_labels.txt"),

                // Keywords
                .process("Resources/keywords_critical.txt"),
                .process("Resources/keywords_moderate.txt")
            ]
        ),
        .testTarget(
            name: "ToxityFilterTests",
            dependencies: ["ToxityFilter"]
        ),
    ]
)
