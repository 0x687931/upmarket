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
        var finalMarkdown = fmResult.refinedMarkdown

        // Validate output structure against input
        let structureReport = DocumentStructureValidator.validateAndRepair(
            originalMarkdown: originalMarkdown,
            convertedMarkdown: finalMarkdown
        )

        // Use repaired markdown if structure issues detected
        if let repairedMarkdown = structureReport.reformattedMarkdown {
            finalMarkdown = repairedMarkdown
        }

        // Log structure validation issues
        if !structureReport.isValid {
            let logger = Logger(subsystem: "com.upmarket.app", category: "structure-validation")
            for issue in structureReport.issues {
                let severity = issue.severity == .error ? "ERROR" : "WARNING"
                // Log only machine-safe fields; redact user-document-derived text
                logger.warning("[\(severity)] \(issue.description, privacy: .private)")
            }
            let retention = Int(structureReport.metrics.structureRetention * 100)
            logger.debug("Structure retention: \(retention)% (headings: \(structureReport.metrics.outputHeadingCount)/\(structureReport.metrics.inputHeadingCount))")
        }

        // Validate output content against input to detect data loss
        let contentValidation = ConversionValidator.validate(
            originalMarkdown: originalMarkdown,
            convertedMarkdown: finalMarkdown,
            tablesDetected: structureReport.metrics.outputTableCount,
            listsDetected: structureReport.metrics.outputListCount,
            pagesProcessed: output.pages
        )

        if !contentValidation.passed {
            let logger = Logger(subsystem: "com.upmarket.app", category: "content-validation")
            for warning in contentValidation.warnings {
                logger.warning("Conversion quality issue: \(warning, privacy: .public)")
            }
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
