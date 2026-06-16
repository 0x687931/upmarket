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

    /// Convert one page image to Markdown. The model is loaded lazily and reused.
    public func convertToMarkdown(
        imageURL: URL,
        prompt: String = "Convert this page to docling."
    ) async throws -> String {
        if context == nil {
            context = try await #huggingFaceLoadModel(configuration: configuration)
        }
        let session = ChatSession(context!)
        let doctags = try await session.respond(to: prompt, image: .url(imageURL))
        return DocTags.toMarkdown(doctags)
    }
}
