import Foundation
import SwiftOfficeMarkdown

/// In-process EPUB → Markdown conversion. No Python, no network, no download.
///
/// An EPUB is a ZIP of XHTML content files. We read the container to find the OPF
/// package document, walk its `<spine>` to recover reading order, and convert each
/// XHTML part with the native HTML walker. ZIP reading reuses SwiftOfficeMarkdown's
/// `ZipReader` (the same reader used for OOXML), and content conversion reuses
/// `NativeHTMLConverter` (libxml2).
enum NativeEPUBConverter {
    enum EPUBError: Error { case unreadable, noContent }

    static func convert(fileURL: URL) throws -> String {
        let zip = try ZipReader(url: fileURL)

        guard let containerData = try zip.data(for: "META-INF/container.xml"),
              let opfPath = opfPath(fromContainer: containerData),
              let opfData = try zip.data(for: opfPath) else {
            throw EPUBError.unreadable
        }

        let contentPaths = orderedContentPaths(opfXML: opfData, opfPath: opfPath)
        guard !contentPaths.isEmpty else { throw EPUBError.noContent }

        var parts: [String] = []
        for path in contentPaths {
            guard let data = try zip.data(for: path),
                  let markdown = try? NativeHTMLConverter.convert(data: data) else { continue }
            let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        guard !parts.isEmpty else { throw EPUBError.noContent }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - OPF parsing (pure, testable)

    /// The OPF package path referenced by `META-INF/container.xml`'s first rootfile.
    static func opfPath(fromContainer data: Data) -> String? {
        guard let doc = try? XMLDocument(data: data, options: [.documentTidyXML]),
              let root = doc.rootElement(),
              let rootfile = firstElement(in: root, localName: "rootfile"),
              let fullPath = rootfile.attribute(forName: "full-path")?.stringValue,
              !fullPath.isEmpty else { return nil }
        return normalize(fullPath)
    }

    /// Spine reading order resolved to ZIP entry paths (relative to the OPF's directory).
    /// Falls back to manifest order if the spine is missing.
    static func orderedContentPaths(opfXML data: Data, opfPath: String) -> [String] {
        guard let doc = try? XMLDocument(data: data, options: [.documentTidyXML]),
              let root = doc.rootElement() else { return [] }

        // manifest: id -> (href, mediaType)
        var manifest: [String: (href: String, type: String)] = [:]
        if let manifestEl = firstElement(in: root, localName: "manifest") {
            for item in childElements(of: manifestEl, localName: "item") {
                guard let id = item.attribute(forName: "id")?.stringValue,
                      let href = item.attribute(forName: "href")?.stringValue else { continue }
                let type = item.attribute(forName: "media-type")?.stringValue ?? ""
                manifest[id] = (href, type)
            }
        }

        let opfDir = (opfPath as NSString).deletingLastPathComponent

        func isContent(_ type: String, _ href: String) -> Bool {
            if type.contains("xhtml") || type.contains("html") { return true }
            if type.isEmpty {
                let ext = (href as NSString).pathExtension.lowercased()
                return ext == "xhtml" || ext == "html" || ext == "htm"
            }
            return false
        }

        var orderedIDs: [String] = []
        if let spine = firstElement(in: root, localName: "spine") {
            for ref in childElements(of: spine, localName: "itemref") {
                if let idref = ref.attribute(forName: "idref")?.stringValue { orderedIDs.append(idref) }
            }
        }
        if orderedIDs.isEmpty { orderedIDs = Array(manifest.keys) }

        var paths: [String] = []
        for id in orderedIDs {
            guard let item = manifest[id], isContent(item.type, item.href) else { continue }
            paths.append(resolve(href: item.href, relativeTo: opfDir))
        }
        return paths
    }

    // MARK: - Helpers

    /// Resolve a manifest href (relative to the OPF dir), strip fragments, percent-decode,
    /// and normalize `..`/`.` segments to a ZIP entry path.
    private static func resolve(href: String, relativeTo opfDir: String) -> String {
        var h = href
        if let hashIndex = h.firstIndex(of: "#") { h = String(h[..<hashIndex]) }
        h = h.removingPercentEncoding ?? h
        let combined = opfDir.isEmpty ? h : "\(opfDir)/\(h)"
        return normalize(combined)
    }

    /// Collapse `.`/`..` segments and leading slashes into a clean ZIP entry path.
    private static func normalize(_ path: String) -> String {
        var stack: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".": continue
            case "..": _ = stack.popLast()
            default: stack.append(String(segment))
            }
        }
        return stack.joined(separator: "/")
    }

    private static func firstElement(in element: XMLElement, localName: String) -> XMLElement? {
        for child in element.children ?? [] {
            guard let el = child as? XMLElement else { continue }
            if el.localName == localName { return el }
            if let found = firstElement(in: el, localName: localName) { return found }
        }
        return nil
    }

    private static func childElements(of element: XMLElement, localName: String) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == localName }
    }
}
