// swift-tools-version: 5.9
import PackageDescription

// Standalone table-quality eval harness. Lives outside the app target so it runs via
// `swift test` / `swift run` with no Xcode host. Scores engine HTML table output against
// ground truth using TEDS (tree-edit-distance similarity) over the FinTabNet corpus.
let package = Package(
    name: "TableEval",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TableEvalKit"),
        .executableTarget(name: "table-eval", dependencies: ["TableEvalKit"]),
        .testTarget(name: "TableEvalKitTests", dependencies: ["TableEvalKit"]),
    ]
)
