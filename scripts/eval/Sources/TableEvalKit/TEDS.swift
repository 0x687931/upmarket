import Foundation

/// Tree-Edit-Distance Similarity for tables (Zhong et al., PubTabNet). Both inputs become
/// normalized HTML table trees; `TEDS = 1 − TreeEditDistance / max(|pred|, |gt|)`.
///
/// - `structural: true`  → ignores cell text (structure only).
/// - `structural: false` → "total" TEDS: structure + normalized cell-content edit distance.
public enum TEDS {

    /// Score predicted HTML against ground-truth HTML (e.g. comparing two engines' HTML output).
    public static func score(predictedHTML: String, groundTruthHTML: String, structural: Bool) -> Double {
        score(TableTreeNode.parse(html: predictedHTML), TableTreeNode.parse(html: groundTruthHTML), structural: structural)
    }

    /// Score pre-parsed trees (lets a caller parse once and reuse across structural/total).
    public static func score(_ predicted: TableTreeNode?, _ groundTruth: TableTreeNode?, structural: Bool) -> Double {
        guard let groundTruth else { return predicted == nil ? 1.0 : 0.0 }
        guard let predicted else { return 0.0 }
        let distance = ZhangShasha(structural: structural).distance(predicted, groundTruth)
        let denominator = Double(max(predicted.nodeCount, groundTruth.nodeCount))
        guard denominator > 0 else { return 1.0 }
        return max(0.0, 1.0 - distance / denominator)
    }
}
