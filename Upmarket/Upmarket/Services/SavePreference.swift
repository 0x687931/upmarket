import Foundation
import AppKit
import OSLog
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

    func configure(destination: Destination, chosenFolderURL: URL? = nil) {
        self.destination = destination
        if destination == .chosenFolder {
            self.chosenFolderURL = chosenFolderURL
        }
        hasPrompted = true
    }

    private var hasPrompted: Bool {
        get { UserDefaults.standard.bool(forKey: "upmarket.savePreferenceSet") }
        set { UserDefaults.standard.set(newValue, forKey: "upmarket.savePreferenceSet") }
    }

    // MARK: - Main save function

    /// Save markdown, respecting the user's preference.
    /// Shows the first-use prompt if not yet configured.
    /// Returns the URL where the file was saved (nil if user cancelled).
    /// Non-blocking: writes happen on background thread.
    @discardableResult
    @MainActor
    func save(markdown: String, title: String, sourceURL: URL?, fileExtension: String = "md") async -> URL? {
        // First use — prompt once
        if !hasPrompted {
            let chosen = promptFirstUse(sourceURL: sourceURL)
            if !chosen { return nil }
        }

        return await performSave(markdown: markdown, title: title, sourceURL: sourceURL, fileExtension: fileExtension)
    }

    // MARK: - Perform save based on preference

    @MainActor
    private func performSave(markdown: String, title: String, sourceURL: URL?, fileExtension: String) async -> URL? {
        let signpost = AppSignpost.conversion.beginInterval("saveOutput")
        defer { AppSignpost.conversion.endInterval("saveOutput", signpost) }

        let normalisedExtension = Self.normalisedFileExtension(fileExtension)
        let fileName = (title.isEmpty ? "converted" : title.sanitisedForFilename) + ".\(normalisedExtension)"

        switch destination {
        case .sameFolder:
            guard let sourceURL else {
                return await showSavePanel(defaultName: fileName, markdown: markdown, fileExtension: normalisedExtension)
            }
            let folder = sourceURL.deletingLastPathComponent()
            let scoped = folder.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    folder.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let saveURL = uniqueMarkdownURL(in: folder, fileName: fileName)
                try await FileWriteService.shared.writeMarkdown(markdown, to: saveURL)
                return saveURL
            } catch {
                return await showSavePanel(defaultName: fileName, markdown: markdown, fileExtension: normalisedExtension)
            }

        case .askEachTime:
            return await showSavePanel(defaultName: fileName, markdown: markdown, fileExtension: normalisedExtension)

        case .chosenFolder:
            guard let folder = chosenFolderURL else {
                return await showSavePanel(defaultName: fileName, markdown: markdown, fileExtension: normalisedExtension)
            }
            _ = folder.startAccessingSecurityScopedResource()
            defer { folder.stopAccessingSecurityScopedResource() }
            do {
                let saveURL = uniqueMarkdownURL(in: folder, fileName: fileName)
                try await FileWriteService.shared.writeMarkdown(markdown, to: saveURL)
                return saveURL
            } catch {
                return await showSavePanel(defaultName: fileName, markdown: markdown, fileExtension: normalisedExtension)
            }
        }
    }

    private func uniqueMarkdownURL(in folder: URL, fileName: String) -> URL {
        let candidate = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        for index in 2...999 {
            let numberedName = "\(baseName) \(index).\(pathExtension)"
            let numberedURL = folder.appendingPathComponent(numberedName)
            if !FileManager.default.fileExists(atPath: numberedURL.path) {
                return numberedURL
            }
        }
        return folder.appendingPathComponent("\(baseName) \(UUID().uuidString).\(pathExtension)")
    }

    @MainActor
    private func showSavePanel(defaultName: String, markdown: String, fileExtension: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: fileExtension) ?? .plainText]
        panel.nameFieldStringValue = defaultName
        panel.orderFrontRegardless()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try await FileWriteService.shared.writeMarkdown(markdown, to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func normalisedFileExtension(_ fileExtension: String) -> String {
        let trimmed = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed.isEmpty ? "md" : trimmed
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
            configure(destination: .sameFolder)
            return true
        case .alertSecondButtonReturn:
            configure(destination: .askEachTime)
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
                configure(destination: .chosenFolder, chosenFolderURL: url)
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
