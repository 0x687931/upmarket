import Foundation
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Native Granite-Docling (idefics3) conversion via mlx-swift-lm — the no-Python replacement
/// for the Docling enhanced pipeline. Loads the granite-docling-258M MLX weights, runs page
/// inference on Apple Silicon (Metal/ANE), and parses the DocTags output to Markdown.
public actor GraniteDoclingEngine {
    public enum Source: Sendable {
        case modelDirectory(URL)     // the app's downloaded `upmarket_ai` weights
        case huggingFaceID(String)   // e.g. "ibm-granite/granite-docling-258M-mlx"
    }

    private let configuration: ModelConfiguration
    private var context: ModelContext?

    public init(source: Source) {
        switch source {
        case .modelDirectory(let url): configuration = ModelConfiguration(directory: url)
        case .huggingFaceID(let id):   configuration = ModelConfiguration(id: id)
        }
    }

    /// granite-docling's `preprocessor_config.json` names `Idefics3Processor`, but mlx-swift-lm's
    /// implementation of that name is a non-tiling SmolVLM stub: it crops the whole page to a
    /// single 512² square, which is illegible on a full document and makes the model hallucinate
    /// or emit `<picture>`. Granite-docling needs idefics3 image *splitting* — which the library's
    /// `SmolVLMProcessor` provides (SmolVLM is the same idefics3 family). Route the processor here,
    /// mirroring mlx-swift-lm's own `model_type → processor` overrides (e.g. mistral3→Mistral3Processor),
    /// so we neither edit the vendored model config nor fork the dependency. `video_sampling` is
    /// injected because granite's image config omits it (irrelevant for still pages; `image_seq_len`
    /// defaults to 64 in the processor config).
    private static func routeToTilingProcessor() async {
        await VLMProcessorTypeRegistry.shared.registerProcessorType("Idefics3Processor") { data, tokenizer in
            var obj = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if obj["video_sampling"] == nil { obj["video_sampling"] = ["fps": 1, "max_frames": 20] }
            let patched = try JSONSerialization.data(withJSONObject: obj)
            let config = try JSONDecoder().decode(SmolVLMProcessorConfiguration.self, from: patched)
            return SmolVLMProcessor(config, tokenizer: tokenizer)
        }
    }

    /// Convert one page image to Markdown. The model is loaded lazily and reused.
    public func convertToMarkdown(
        imageURL: URL,
        prompt: String = "Convert this page to docling."
    ) async throws -> String {
        if context == nil {
            await Self.routeToTilingProcessor()
            context = try await #huggingFaceLoadModel(configuration: configuration)
        }
        let session = ChatSession(context!)
        let doctags = try await session.respond(to: prompt, image: .url(imageURL))
        return DocTags.toMarkdown(doctags)
    }
}
