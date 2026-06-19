import CoreGraphics
import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM

/// Reference-compatible image plan for LFM2.5-VL.
///
/// A single variable-resolution frame used by the model's thumbnail path.
public struct LFM2VLImagePlan: Equatable, Sendable {
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let resizedWidth: Int
    public let resizedHeight: Int
    public let patchRows: Int
    public let patchColumns: Int
    public let validPatchCount: Int
    public let paddedPatchCount: Int
    public let imageTokenCount: Int

    public static func reference(
        width: Int,
        height: Int,
        patchSize: Int = 16,
        maxPatches: Int = 1024,
        downsampleFactor: Int = 2
    ) -> LFM2VLImagePlan {
        precondition(width > 0 && height > 0)
        precondition(patchSize > 0 && maxPatches > 0 && downsampleFactor > 0)

        func scaledSize(_ scale: Double, _ size: Int) -> Int {
            max(patchSize, Int(ceil(Double(size) * scale / Double(patchSize))) * patchSize)
        }

        // Exact port of Transformers' get_image_size_for_max_num_patches().
        let epsilon = 1e-5
        var scaleMin = epsilon / 10
        var scaleMax = 100.0
        while scaleMax - scaleMin >= epsilon {
            let scale = (scaleMin + scaleMax) / 2
            let targetHeight = scaledSize(scale, height)
            let targetWidth = scaledSize(scale, width)
            let patches = (targetHeight / patchSize) * (targetWidth / patchSize)
            if patches <= maxPatches {
                scaleMin = scale
            } else {
                scaleMax = scale
            }
        }

        let resizedHeight = scaledSize(scaleMin, height)
        let resizedWidth = scaledSize(scaleMin, width)
        let rows = resizedHeight / patchSize
        let columns = resizedWidth / patchSize
        let validPatches = rows * columns
        let imageTokens =
            ((rows + downsampleFactor - 1) / downsampleFactor)
            * ((columns + downsampleFactor - 1) / downsampleFactor)

        return LFM2VLImagePlan(
            sourceWidth: width,
            sourceHeight: height,
            resizedWidth: resizedWidth,
            resizedHeight: resizedHeight,
            patchRows: rows,
            patchColumns: columns,
            validPatchCount: validPatches,
            paddedPatchCount: maxPatches,
            imageTokenCount: imageTokens
        )
    }
}

public struct LFM2VLTilePlan: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public static func reference(
        width: Int,
        height: Int,
        minTiles: Int = 2,
        maxTiles: Int = 10
    ) -> LFM2VLTilePlan {
        let aspectRatio = Double(width) / Double(height)
        let area = width * height
        var candidates = Set<[Int]>()
        for count in minTiles...maxTiles {
            for columns in 1...count {
                for rows in 1...count where (minTiles...maxTiles).contains(columns * rows) {
                    candidates.insert([columns, rows])
                }
            }
        }
        let sorted = candidates.sorted { $0[0] * $0[1] < $1[0] * $1[1] }
        var best = sorted.first ?? [1, 1]
        var bestDifference = Double.greatestFiniteMagnitude
        for candidate in sorted {
            let difference = abs(aspectRatio - Double(candidate[0]) / Double(candidate[1]))
            if difference < bestDifference
                || (difference == bestDifference
                    && area > (512 * 512 * candidate[0] * candidate[1]) / 2) {
                bestDifference = difference
                best = candidate
            }
        }
        return LFM2VLTilePlan(columns: best[0], rows: best[1])
    }
}

public enum LFM2VLPromptPlan {
    public static func specialTokens(
        tileLayout: LFM2VLTilePlan?,
        includeThumbnail: Bool
    ) -> [String] {
        var tokens = ["<|image_start|>"]
        if let tiles = tileLayout {
            for row in 0..<tiles.rows {
                for column in 0..<tiles.columns {
                    tokens.append("<|img_row_\(row + 1)_col_\(column + 1)|>")
                }
            }
            if includeThumbnail {
                tokens.append("<|img_thumbnail|>")
            }
        }
        tokens.append("<|image_end|>")
        return tokens
    }
}

struct LFM2VLReferenceProcessorConfiguration: Decodable, Sendable {
    struct ImageProcessor: Decodable, Sendable {
        let imageMean: [CGFloat]
        let imageStd: [CGFloat]
        let encoderPatchSize: Int
        let maxNumPatches: Int
        let downsampleFactor: Int
        let minTiles: Int
        let maxTiles: Int
        let tileSize: Int
        let minImageTokens: Int
        let maxImageTokens: Int
        let maxPixelsTolerance: Double
        let useThumbnail: Bool

        enum CodingKeys: String, CodingKey {
            case imageMean = "image_mean"
            case imageStd = "image_std"
            case encoderPatchSize = "encoder_patch_size"
            case maxNumPatches = "max_num_patches"
            case downsampleFactor = "downsample_factor"
            case minTiles = "min_tiles"
            case maxTiles = "max_tiles"
            case tileSize = "tile_size"
            case minImageTokens = "min_image_tokens"
            case maxImageTokens = "max_image_tokens"
            case maxPixelsTolerance = "max_pixels_tolerance"
            case useThumbnail = "use_thumbnail"
        }
    }

    let imageProcessor: ImageProcessor

    enum CodingKeys: String, CodingKey {
        case imageProcessor = "image_processor"
    }
}

/// Local compatibility processor matching the mlx-vlm 0.3.10/SigLIP2 path used to create
/// mlx-community/LFM2.5-VL-1.6B-8bit.
struct LFM2VLReferenceProcessor: UserInputProcessor {
    private let config: LFM2VLReferenceProcessorConfiguration.ImageProcessor
    private let tokenizer: any MLXLMCommon.Tokenizer

    init(
        _ config: LFM2VLReferenceProcessorConfiguration,
        tokenizer: any MLXLMCommon.Tokenizer
    ) {
        self.config = config.imageProcessor
        self.tokenizer = tokenizer
    }

    func prepare(input: UserInput) async throws -> LMInput {
        let messages = Qwen2VLMessageGenerator().generate(from: input)
        var promptTokens = try tokenizer.applyChatTemplate(
            messages: messages,
            tools: input.tools,
            additionalContext: input.additionalContext
        )
        guard !input.images.isEmpty else {
            return LMInput(tokens: MLXArray(promptTokens))
        }
        guard input.images.count == 1 else {
            throw VLMError.singleImageAllowed
        }

        let source = try input.images[0].asCIImage().toSRGB()
        let width = Int(source.extent.width.rounded())
        let height = Int(source.extent.height.rounded())
        let totalFactor = config.encoderPatchSize * config.downsampleFactor
        let roundedHeight = max(totalFactor, Int(round(Double(height) / Double(totalFactor))) * totalFactor)
        let roundedWidth = max(totalFactor, Int(round(Double(width) / Double(totalFactor))) * totalFactor)
        let maxPixels = Double(
            config.maxImageTokens
                * config.encoderPatchSize * config.encoderPatchSize
                * config.downsampleFactor * config.downsampleFactor
        ) * config.maxPixelsTolerance
        let isLarge = Double(roundedHeight * roundedWidth) > maxPixels

        var images: [CIImage] = []
        var plans: [LFM2VLImagePlan] = []
        var tileLayout: LFM2VLTilePlan?
        if isLarge {
            let tiles = LFM2VLTilePlan.reference(
                width: width,
                height: height,
                minTiles: config.minTiles,
                maxTiles: config.maxTiles
            )
            tileLayout = tiles
            let tiled = source.resampled(
                to: CGSize(
                    width: tiles.columns * config.tileSize,
                    height: tiles.rows * config.tileSize
                ),
                method: .bicubic
            )
            for row in 0..<tiles.rows {
                for column in 0..<tiles.columns {
                    // Core Image's origin is bottom-left; Transformers emits tiles top-to-bottom.
                    let y = (tiles.rows - row - 1) * config.tileSize
                    let rect = CGRect(
                        x: column * config.tileSize,
                        y: y,
                        width: config.tileSize,
                        height: config.tileSize
                    )
                    images.append(
                        tiled.cropped(to: rect)
                            .transformed(by: .init(
                                translationX: -rect.minX,
                                y: -rect.minY
                            ))
                    )
                    plans.append(LFM2VLImagePlan.reference(
                        width: config.tileSize,
                        height: config.tileSize,
                        patchSize: config.encoderPatchSize,
                        maxPatches: config.maxNumPatches,
                        downsampleFactor: config.downsampleFactor
                    ))
                }
            }
        }

        if !isLarge || config.useThumbnail {
            let thumbnail = LFM2VLImagePlan.reference(
                width: width,
                height: height,
                patchSize: config.encoderPatchSize,
                maxPatches: config.maxNumPatches,
                downsampleFactor: config.downsampleFactor
            )
            images.append(source.resampled(
                to: CGSize(width: thumbnail.resizedWidth, height: thumbnail.resizedHeight),
                method: .bicubic
            ))
            plans.append(thumbnail)
        }

        let encodedFrames = zip(images, plans).map { image, plan in
            patchify(image: image, plan: plan)
        }
        let pixelValues = concatenated(encodedFrames, axis: 0)
        let totalImageTokens = plans.reduce(0) { $0 + $1.imageTokenCount }

        guard let imageTokenID = tokenizer.convertTokenToId("<image>") else {
            throw LFM2VLProcessorError.invalidImageToken
        }
        var replacement: [Int] = []
        guard let start = tokenizer.convertTokenToId("<|image_start|>"),
              let end = tokenizer.convertTokenToId("<|image_end|>") else {
            throw LFM2VLProcessorError.invalidImageToken
        }
        replacement.append(start)
        if let tiles = tileLayout {
            var planIndex = 0
            for row in 0..<tiles.rows {
                for column in 0..<tiles.columns {
                    guard let marker = tokenizer.convertTokenToId(
                        "<|img_row_\(row + 1)_col_\(column + 1)|>"
                    ) else {
                        throw LFM2VLProcessorError.invalidImageToken
                    }
                    replacement.append(marker)
                    replacement.append(
                        contentsOf: repeatElement(
                            imageTokenID,
                            count: plans[planIndex].imageTokenCount
                        )
                    )
                    planIndex += 1
                }
            }
            if config.useThumbnail, planIndex < plans.count {
                guard let thumbnail = tokenizer.convertTokenToId("<|img_thumbnail|>") else {
                    throw LFM2VLProcessorError.invalidImageToken
                }
                replacement.append(thumbnail)
                replacement.append(
                    contentsOf: repeatElement(
                        imageTokenID,
                        count: plans[planIndex].imageTokenCount
                    )
                )
            }
        } else {
            replacement.append(
                contentsOf: repeatElement(imageTokenID, count: totalImageTokens)
            )
        }
        replacement.append(end)

        var expanded: [Int] = []
        expanded.reserveCapacity(promptTokens.count + replacement.count)
        for token in promptTokens {
            if token == imageTokenID {
                expanded.append(contentsOf: replacement)
            } else {
                expanded.append(token)
            }
        }
        promptTokens = expanded

        let prompt = MLXArray(promptTokens).expandedDimensions(axis: 0)
        return LMInput(
            text: .init(tokens: prompt, mask: ones(like: prompt).asType(.int8)),
            image: .init(
                pixels: pixelValues,
                frames: plans.map { THW(1, $0.patchRows, $0.patchColumns) }
            )
        )
    }

    private func patchify(image: CIImage, plan: LFM2VLImagePlan) -> MLXArray {
        let normalized = image.normalized(
            mean: (config.imageMean[0], config.imageMean[1], config.imageMean[2]),
            std: (config.imageStd[0], config.imageStd[1], config.imageStd[2])
        )
        let array = MediaProcessing.asMLXArray(normalized).transposed(0, 2, 3, 1)
        var patches: [MLXArray] = []
        patches.reserveCapacity(plan.paddedPatchCount)
        for row in 0..<plan.patchRows {
            for column in 0..<plan.patchColumns {
                let y = row * config.encoderPatchSize
                let x = column * config.encoderPatchSize
                patches.append(array[
                    0,
                    y..<(y + config.encoderPatchSize),
                    x..<(x + config.encoderPatchSize),
                    0...
                ].flattened())
            }
        }
        let patchWidth = config.encoderPatchSize * config.encoderPatchSize * 3
        while patches.count < plan.paddedPatchCount {
            patches.append(MLXArray.zeros([patchWidth]))
        }
        return stacked(patches, axis: 0).expandedDimensions(axis: 0)
    }
}

enum LFM2VLProcessorError: Error {
    case invalidImageToken
}
