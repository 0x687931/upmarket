import Foundation
import AppKit
import UniformTypeIdentifiers

/// Manages where converted .md files are saved.
/// Prompts on first use, remembers preference, silently saves thereafter.
final class SavePreference {

    static let shared = SavePreference()
    private init() {}

    enum Destination: Int, CaseIterable {
        case sameFolder = 0     // next to the original file (default)
        case askEachTime = 1    // NSSavePanel every time
        case chosenFolder = 2   // a specific folder the user picked
    }

    var destination: Destination {
        get { Destination(rawValue: UserDefaults.standard.integer(forKey: "upmarket.saveDestination")) ?? .sameFolder }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "upmarket.saveDestination") }
    }

    var chosenFolderURL: URL? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "upmarket.saveFolder") else { return nil }
            var isStale = false
            return try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                            relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
        set {
            guard let url = newValue,
                  let data = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) else { return }
            UserDefaults.standard.set(data, forKey: "upmarket.saveFolder")
        }
    }

    private var hasPrompted: Bool {
        get { UserDefaults.standard.bool(forKey: "upmarket.savePreferenceSet") }
        set { UserDefaults.standard.set(newValue, forKey: "upmarket.savePreferenceSet") }
    }

    // MARK: - Main save function

    /// Save markdown, respecting the user's preference.
    /// Shows the first-use prompt if not yet configured.
    /// Returns the URL where the file was saved (nil if user cancelled).
    @discardableResult
    @MainActor
    func save(markdown: String, title: String, sourceURL: URL?) -> URL? {
        // First use — prompt once
        if !hasPrompted {
            let chosen = promptFirstUse(sourceURL: sourceURL)
            if !chosen { return nil }
        }

        return performSave(markdown: markdown, title: title, sourceURL: sourceURL)
    }

    // MARK: - Perform save based on preference

    @MainActor
    private func performSave(markdown: String, title: String, sourceURL: URL?) -> URL? {
        let fileName = (title.isEmpty ? "converted" : title.sanitisedForFilename) + ".md"

        switch destination {
        case .sameFolder:
            guard let sourceURL else {
                // No source URL (e.g. dragged from elsewhere) — fall back to ask
                return showSavePanel(defaultName: fileName, markdown: markdown)
            }
            let saveURL = sourceURL.deletingLastPathComponent().appendingPathComponent(fileName)
            let folder = sourceURL.deletingLastPathComponent()
            let scoped = folder.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    folder.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try markdown.write(to: saveURL, atomically: true, encoding: .utf8)
                return saveURL
            } catch {
                // Permission denied on sandboxed path — fall back to panel
                return showSavePanel(defaultName: fileName, markdown: markdown)
            }

        case .askEachTime:
            return showSavePanel(defaultName: fileName, markdown: markdown)

        case .chosenFolder:
            guard let folder = chosenFolderURL else {
                return showSavePanel(defaultName: fileName, markdown: markdown)
            }
            _ = folder.startAccessingSecurityScopedResource()
            defer { folder.stopAccessingSecurityScopedResource() }
            let saveURL = folder.appendingPathComponent(fileName)
            do {
                try markdown.write(to: saveURL, atomically: true, encoding: .utf8)
                return saveURL
            } catch {
                return showSavePanel(defaultName: fileName, markdown: markdown)
            }
        }
    }

    @MainActor
    private func showSavePanel(defaultName: String, markdown: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = defaultName
        panel.orderFrontRegardless()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - First-use prompt

    @MainActor
    private func promptFirstUse(sourceURL: URL?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Where should Upmarket save converted files?"
        alert.informativeText = "You can change this later in Preferences."
        alert.addButton(withTitle: "Same folder as original")  // .alertFirstButtonReturn
        alert.addButton(withTitle: "Ask each time")
        alert.addButton(withTitle: "Choose a folder…")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            destination = .sameFolder
            hasPrompted = true
            return true
        case .alertSecondButtonReturn:
            destination = .askEachTime
            hasPrompted = true
            return true
        case .alertThirdButtonReturn:
            // Let user pick a folder
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Upmarket will save all converted files here."
            panel.orderFrontRegardless()
            if panel.runModal() == .OK, let url = panel.url {
                chosenFolderURL = url
                destination = .chosenFolder
                hasPrompted = true
                return true
            }
            return false
        default:
            return false
        }
    }
}

extension String {
    var sanitisedForFilename: String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return components(separatedBy: invalid).joined(separator: "-")
    }
}
