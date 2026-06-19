import Foundation
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import HuggingFace   // required: the #huggingFaceLoadModel macro expands to HubClient/HuggingFace symbols
import Tokenizers    // required: the macro expansion references Tokenizers

/// Native LFM2.5-VL (lfm2_vl) page→Markdown conversion via mlx-swift-lm — the larger,
/// general-purpose alternative to `GraniteDoclingEngine`. The pinned mlx-swift-lm registers
/// `lfm2_vl` → `LFM2VL.init` and `Lfm2VlProcessor` natively, so unlike Granite there is **no**
/// processor-routing workaround. The model emits plain Markdown directly — there is **no**
/// DocTags parsing step. Load is lazy and the context is reused across pages.
public actor LFM2VLEngine {
    public static let generationParameters = GenerateParameters(
        maxTokens: 4096,
        temperature: 0.1,
        minP: 0.15,
        repetitionPenalty: 1.05,
        repetitionContextSize: 64
    )

    public enum Source: Sendable {
        case modelDirectory(URL)     // the app's downloaded `lfm25_vl` weights
        case huggingFaceID(String)   // e.g. "mlx-community/LFM2.5-VL-1.6B-8bit" (dev/eval only)
    }

    private let configuration: ModelConfiguration
    private var context: ModelContext?

    public init(source: Source) {
        switch source {
        case .modelDirectory(let url): configuration = ModelConfiguration(directory: url)
        case .huggingFaceID(let id):   configuration = ModelConfiguration(id: id)
        }
    }

    private static func routeReferenceProcessor() async {
        await VLMProcessorTypeRegistry.shared.registerProcessorType("Lfm2VlProcessor") {
            data, tokenizer in
            let config = try JSONDecoder().decode(
                LFM2VLReferenceProcessorConfiguration.self,
                from: data
            )
            return LFM2VLReferenceProcessor(config, tokenizer: tokenizer)
        }
    }

    /// Convert one page image to Markdown. LFM2.5-VL has no default conversion prompt, so an
    /// explicit Markdown instruction is required. The model is loaded lazily and reused.
    public func convertToMarkdown(
        imageURL: URL,
        prompt: String = "Convert this document page to Markdown. Preserve headings, lists, and tables."
    ) async throws -> String {
        if context == nil {
            await Self.routeReferenceProcessor()
            context = try await #huggingFaceLoadModel(configuration: configuration)
        }
        let session = ChatSession(
            context!,
            instructions: "You are a helpful multimodal assistant by Liquid AI.",
            generateParameters: Self.generationParameters,
            processing: .init(resize: nil)
        )
        return try VLMOutputValidator.validate(
            try await session.respond(to: prompt, image: .url(imageURL))
        )
    }
}
