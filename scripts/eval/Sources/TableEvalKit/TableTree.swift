import Foundation

/// A node in a normalized HTML table tree, used for TEDS scoring. Tags are limited to
/// `table` / `tr` / `td`: section wrappers (`thead`/`tbody`/`tfoot`) are flattened and `th`
/// is normalized to `td`, applied identically to ground truth and predictions so the two are
/// compared on equal terms (matching the PubTabNet TEDS structural convention).
public final class TableTreeNode {
    public let tag: String
    public let colspan: Int
    public let rowspan: Int
    public let content: String
    public var children: [TableTreeNode]

    public init(tag: String, colspan: Int = 1, rowspan: Int = 1, content: String = "", children: [TableTreeNode] = []) {
        self.tag = tag
        self.colspan = colspan
        self.rowspan = rowspan
        self.content = content
        self.children = children
    }

    /// Total node count (self + descendants) — the TEDS denominator term.
    public var nodeCount: Int {
        1 + children.reduce(0) { $0 + $1.nodeCount }
    }

    // MARK: - Construction

    /// Parse the first `<table>` in an HTML fragment into a normalized tree, or `nil` if none.
    public static func parse(html: String) -> TableTreeNode? {
        // Lenient HTML parse (real-world table HTML is rarely well-formed XML).
        guard let doc = try? XMLDocument(data: Data(html.utf8), options: [.documentTidyHTML]),
              let root = doc.rootElement(),
              let tableEl = firstElement(named: "table", under: root) else {
            return nil
        }
        return node(from: tableEl)
    }

    // MARK: - HTML walking

    private static let structuralTags: Set<String> = ["thead", "tbody", "tfoot"]

    private static func node(from element: XMLElement) -> TableTreeNode {
        let tag = element.name?.lowercased() ?? ""
        switch tag {
        case "td", "th":
            return TableTreeNode(
                tag: "td",
                colspan: intAttr(element, "colspan"),
                rowspan: intAttr(element, "rowspan"),
                content: normalize(element.stringValue ?? "")
            )
        default:
            // table / tr → keep; thead/tbody/tfoot → flatten (splice children up to the parent).
            let node = TableTreeNode(tag: tag)
            for child in element.children ?? [] {
                guard let childEl = child as? XMLElement, let childTag = childEl.name?.lowercased() else { continue }
                if structuralTags.contains(childTag) {
                    node.children.append(contentsOf: (childEl.children ?? []).compactMap { ($0 as? XMLElement).map(self.node(from:)) })
                } else if ["tr", "td", "th", "table"].contains(childTag) {
                    node.children.append(self.node(from: childEl))
                }
            }
            return node
        }
    }

    private static func firstElement(named name: String, under node: XMLNode) -> XMLElement? {
        if let el = node as? XMLElement, el.name?.lowercased() == name { return el }
        for child in node.children ?? [] {
            if let hit = firstElement(named: name, under: child) { return hit }
        }
        return nil
    }

    private static func intAttr(_ element: XMLElement, _ name: String) -> Int {
        guard let raw = element.attribute(forName: name)?.stringValue, let value = Int(raw), value > 0 else { return 1 }
        return value
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t\\n\\r]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
