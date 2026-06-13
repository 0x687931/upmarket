import Foundation

enum ConversionPostProcessor {
    static func process(_ output: ConversionOutput) async -> ConversionOutput {
        let intelligence = DocumentIntelligence.extractMetadata(from: output.markdown)
        let nlInput = TextStructurer.Input(
            rawMarkdown: output.markdown,
            detectedLanguage: intelligence.language
        )
        let nlResult = TextStructurer.refine(nlInput)

        let wtOutput = await WritingToolsService.refineMarkdown(
            nlResult.markdown,
            language: nlResult.detectedLanguage
        )
        let fmResult = await FoundationModelEnhancer.enhance(
            markdown: wtOutput.markdown,
            documentType: intelligence.documentType.rawValue
        )

        let title = fmResult.extractedTitle ?? intelligence.title ?? output.title
        return ConversionOutput(
            markdown: fmResult.refinedMarkdown,
            pages: output.pages,
            format: output.format,
            title: title,
            pipeline: output.pipeline,
            selectedPathway: output.selectedPathway
        )
    }
}
