import Foundation
import OSLog

enum ConversionPostProcessor {
    static func process(_ output: ConversionOutput) async -> ConversionOutput {
        let originalMarkdown = output.markdown

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
        let finalMarkdown = fmResult.refinedMarkdown

        // Validate output against input to detect data loss or extraction failures
        let validation = ConversionValidator.validate(
            originalMarkdown: originalMarkdown,
            convertedMarkdown: finalMarkdown,
            tablesDetected: 0,  // Would be populated from extraction context
            listsDetected: 0,   // Would be populated from extraction context
            pagesProcessed: output.pages
        )

        if !validation.passed {
            let logger = Logger(subsystem: "com.upmarket.app", category: "conversion-validation")
            for warning in validation.warnings {
                logger.warning("Conversion quality issue: \(warning, privacy: .public)")
            }
            let retention = Int(validation.metrics.retentionRatio * 100)
            logger.debug("Retention: \(validation.metrics.outputWordCount)/\(validation.metrics.inputWordCount) words (\(retention)%)")
        }

        return ConversionOutput(
            markdown: finalMarkdown,
            pages: output.pages,
            format: output.format,
            title: title,
            pipeline: output.pipeline,
            selectedPathway: output.selectedPathway
        )
    }
}
