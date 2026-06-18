// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UpmarketVLM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UpmarketVLM", targets: ["UpmarketVLM"]),
        .executable(name: "granite-run", targets: ["granite-run"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(name: "UpmarketVLM", dependencies: [
            .product(name: "MLXVLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
            .product(name: "HuggingFace", package: "swift-huggingface"),
            .product(name: "Transformers", package: "swift-transformers"),
        ]),
        .executableTarget(name: "granite-run", dependencies: ["UpmarketVLM"]),
        .testTarget(name: "UpmarketVLMTests", dependencies: ["UpmarketVLM"]),
    ]
)
