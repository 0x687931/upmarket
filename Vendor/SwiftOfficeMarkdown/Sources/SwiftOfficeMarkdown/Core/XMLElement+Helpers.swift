import Foundation

/// Namespace-agnostic XML traversal helpers shared by every format parser.
/// OOXML uses many prefixes (w:, a:, r:, x:, p:, …); matching on `localName`
/// lets one set of helpers serve WordprocessingML, SpreadsheetML and
/// PresentationML alike.
extension XMLElement {
    /// First direct child element with the given local name.
    func firstChild(_ localName: String) -> XMLElement? {
        for case let el as XMLElement in children ?? [] where el.localName == localName {
            return el
        }
        return nil
    }

    /// All direct child elements with the given local name.
    func childElements(_ localName: String) -> [XMLElement] {
        var result: [XMLElement] = []
        for case let el as XMLElement in children ?? [] where el.localName == localName {
            result.append(el)
        }
        return result
    }

    /// Depth-first search for the first descendant with the given local name.
    func firstDescendant(_ localName: String) -> XMLElement? {
        var stack = Array((children ?? []).compactMap { $0 as? XMLElement }.reversed())
        while let el = stack.popLast() {
            if el.localName == localName { return el }
            stack.append(contentsOf: (el.children ?? []).compactMap { $0 as? XMLElement }.reversed())
        }
        return nil
    }

    /// All descendants with the given local name, in document order.
    func allDescendants(_ localName: String) -> [XMLElement] {
        var result: [XMLElement] = []
        forEachDescendant(localName) { el in
            result.append(el)
        }
        return result
    }

    /// Visit matching descendants in document order without building an array.
    func forEachDescendant(_ localName: String, _ visit: (XMLElement) -> Void) {
        var stack = Array((children ?? []).compactMap { $0 as? XMLElement }.reversed())
        while let el = stack.popLast() {
            if el.localName == localName { visit(el) }
            stack.append(contentsOf: (el.children ?? []).compactMap { $0 as? XMLElement }.reversed())
        }
    }

    /// Attribute value matched by local name, ignoring namespace prefix
    /// (so "w:val", "r:id", bare "Id" all resolve by their local name).
    func attr(_ localName: String) -> String? {
        for a in attributes ?? [] where a.localName == localName {
            return a.stringValue
        }
        return nil
    }

    /// A relationship-namespace attribute (e.g. `r:id`, `r:embed`). Necessary
    /// because some elements carry BOTH a plain `id` and an `r:id`
    /// (e.g. `<p:sldId id="256" r:id="rId8"/>`) — a local-name match would
    /// return the wrong one. OOXML always binds the relationships namespace to
    /// the `r` prefix.
    func relationshipID(_ localName: String = "id") -> String? {
        if let v = attribute(forName: "r:\(localName)")?.stringValue { return v }
        let ns = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        for a in attributes ?? [] where a.localName == localName && a.uri == ns {
            return a.stringValue
        }
        return nil
    }
}
