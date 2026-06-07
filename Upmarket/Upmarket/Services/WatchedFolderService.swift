import Darwin
import Combine
import Foundation
import OSLog
import UserNotifications

enum WatchedFolderError: Error, Equatable, LocalizedError {
    case tooBroad
    case bookmarkFailed
    case outputBookmarkFailed

    var errorDescription: String? {
        switch self {
        case .tooBroad:
            return "Choose a specific folder, not your entire home folder."
        case .bookmarkFailed:
            return "Upmarket couldn't save access to that folder."
        case .outputBookmarkFailed:
            return "Upmarket couldn't save access to that output folder."
        }
    }
}

enum WatchedFolderOutputDestination: String, CaseIterable, Codable, Identifiable {
    case historyOnly
    case sameFolder
    case chosenFolder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .historyOnly: return "History only"
        case .sameFolder: return "Same folder"
        case .chosenFolder: return "Choose folder"
        }
    }
}

struct WatchedFolder: Codable, Equatable, Identifiable {
    let id: UUID
    var bookmarkData: Data
    var displayName: String
    var outputDestination: WatchedFolderOutputDestination
    var outputBookmarkData: Data?
    var outputDisplayName: String?
    var notificationsEnabled: Bool
}

@MainActor
final class WatchedFolderService: ObservableObject {
    typealias Convert = (URL) async -> ConversionResult
    typealias Notify = (_ title: String, _ body: String) async -> Void

    static let shared = WatchedFolderService()

    @Published private(set) var folders: [WatchedFolder] = []
    @Published var includePatterns: String {
        didSet { savePatterns() }
    }
    @Published var excludePatterns: String {
        didSet { savePatterns() }
    }

    private static let foldersKey = "upmarket.watchedFolders"
    private static let includePatternsKey = "upmarket.watchedFolders.includePatterns"
    private static let excludePatternsKey = "upmarket.watchedFolders.excludePatterns"
    private static let defaultExcludePatterns = "*.md, *.markdown, *.json, *.tmp, *.download, *.part, *.crdownload, ~$*"

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let convert: Convert
    private let notify: Notify
    private let stabilityDelayNanoseconds: UInt64
    private let monitorQueue = DispatchQueue(label: "app.upmarket.watchfolders")

    private var monitors: [UUID: FolderMonitor] = [:]
    private var scanTasks: [UUID: Task<Void, Never>] = [:]
    private var processedSignatures: Set<FileSignature> = []
    private var isRunning = false

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        stabilityDelayNanoseconds: UInt64 = 1_000_000_000,
        convert: @escaping Convert = { url in
            await ConversionQueue.shared.convert(url)
        },
        notify: @escaping Notify = WatchedFolderService.deliverNotification
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.stabilityDelayNanoseconds = stabilityDelayNanoseconds
        self.convert = convert
        self.notify = notify
        self.includePatterns = userDefaults.string(forKey: Self.includePatternsKey) ?? ""
        self.excludePatterns = userDefaults.string(forKey: Self.excludePatternsKey) ?? Self.defaultExcludePatterns
        self.folders = Self.loadFolders(from: userDefaults)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        restartMonitors()
    }

    func stop() {
        isRunning = false
        for task in scanTasks.values {
            task.cancel()
        }
        scanTasks.removeAll()
        for monitor in monitors.values {
            monitor.source.cancel()
        }
        monitors.removeAll()
    }

    func addFolder(_ url: URL) throws {
        let standardURL = url.standardizedFileURL
        guard !Self.isOverlyBroadFolder(standardURL) else {
            throw WatchedFolderError.tooBroad
        }
        guard let bookmark = Self.makeBookmark(for: standardURL) else {
            throw WatchedFolderError.bookmarkFailed
        }
        let existingURLs = Set(folders.compactMap { resolveFolderURL($0)?.standardizedFileURL })
        guard !existingURLs.contains(standardURL) else { return }

        folders.append(WatchedFolder(
            id: UUID(),
            bookmarkData: bookmark,
            displayName: standardURL.lastPathComponent.isEmpty ? "Watched Folder" : standardURL.lastPathComponent,
            outputDestination: .historyOnly,
            outputBookmarkData: nil,
            outputDisplayName: nil,
            notificationsEnabled: false
        ))
        saveFolders()
        restartMonitors()
    }

    func removeFolder(id: UUID) {
        scanTasks[id]?.cancel()
        scanTasks.removeValue(forKey: id)
        monitors.removeValue(forKey: id)?.source.cancel()
        folders.removeAll { $0.id == id }
        processedSignatures = processedSignatures.filter { $0.folderID != id }
        saveFolders()
    }

    func folder(id: UUID) -> WatchedFolder? {
        folders.first { $0.id == id }
    }

    func setOutputDestination(_ destination: WatchedFolderOutputDestination, for id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].outputDestination = destination
        if destination != .chosenFolder {
            folders[index].outputBookmarkData = nil
            folders[index].outputDisplayName = nil
        }
        saveFolders()
    }

    func setOutputFolder(_ url: URL, for id: UUID) throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        guard let bookmark = Self.makeBookmark(for: url.standardizedFileURL) else {
            throw WatchedFolderError.outputBookmarkFailed
        }
        folders[index].outputDestination = .chosenFolder
        folders[index].outputBookmarkData = bookmark
        folders[index].outputDisplayName = url.lastPathComponent
        saveFolders()
    }

    func setNotificationsEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].notificationsEnabled = enabled
        saveFolders()
    }

    func scanFolder(id: UUID) async {
        guard let folder = folder(id: id),
              let folderURL = resolveFolderURL(folder) else { return }

        let scoped = folderURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            AppLog.fileAccess.error("Watched folder scan failed: \(error.localizedDescription, privacy: .private)")
            return
        }

        for url in urls {
            guard await shouldProcess(url, folderID: folder.id) else { continue }
            await process(url, folder: folder, folderURL: folderURL)
        }
    }

    private func restartMonitors() {
        guard isRunning else { return }
        for monitor in monitors.values {
            monitor.source.cancel()
        }
        monitors.removeAll()
        for folder in folders {
            startMonitor(for: folder)
        }
    }

    private func startMonitor(for folder: WatchedFolder) {
        guard let url = resolveFolderURL(folder) else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            AppLog.fileAccess.error("Could not monitor watched folder: \(errno, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: monitorQueue
        )
        let folderID = folder.id
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scheduleScan(folderID: folderID)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        monitors[folder.id] = FolderMonitor(source: source)
        source.resume()
    }

    private func scheduleScan(folderID: UUID) {
        guard isRunning, folder(id: folderID) != nil else { return }
        scanTasks[folderID]?.cancel()
        scanTasks[folderID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.scanFolder(id: folderID)
        }
    }

    private func shouldProcess(_ url: URL, folderID: UUID) async -> Bool {
        let name = url.lastPathComponent
        guard matchesIncludeRules(name), !matchesExcludeRules(name) else { return false }
        guard SupportedInputPolicy.supports(url) else { return false }
        guard let signature = fileSignature(for: url, folderID: folderID),
              !processedSignatures.contains(signature) else { return false }
        guard await isStable(url, folderID: folderID, firstSignature: signature) else { return false }
        processedSignatures.insert(signature)
        return true
    }

    private func process(_ url: URL, folder: WatchedFolder, folderURL: URL) async {
        let result = await convert(url)
        guard case .success(let output) = result else { return }

        if let destination = resolveOutputFolder(for: folder, sourceFolder: folderURL) {
            write(output: output, sourceURL: url, destination: destination)
        }

        if folder.notificationsEnabled {
            await notify("Upmarket finished a watched-folder conversion", url.lastPathComponent)
        }
    }

    private func resolveOutputFolder(for folder: WatchedFolder, sourceFolder: URL) -> URL? {
        switch folder.outputDestination {
        case .historyOnly:
            return nil
        case .sameFolder:
            return sourceFolder
        case .chosenFolder:
            guard let data = folder.outputBookmarkData else { return nil }
            return resolveBookmark(data)
        }
    }

    private func write(output: ConversionOutput, sourceURL: URL, destination: URL) {
        let scoped = destination.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                destination.stopAccessingSecurityScopedResource()
            }
        }

        let formatted = OutputFormatter.format(
            output,
            sourceDisplayName: sourceURL.lastPathComponent,
            mode: OutputPreference.shared.mode
        )
        let baseName = output.title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : output.title
        let fileName = "\(baseName.sanitisedForFilename).\(formatted.fileExtension)"
        let outputURL = uniqueURL(in: destination, fileName: fileName)
        do {
            try Data(formatted.text.utf8).write(to: outputURL, options: .atomic)
        } catch {
            AppLog.fileAccess.error("Watched folder output write failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func uniqueURL(in folder: URL, fileName: String) -> URL {
        let candidate = folder.appendingPathComponent(fileName)
        guard !fileManager.fileExists(atPath: candidate.path) else {
            let baseName = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            for index in 2...999 {
                let numbered = folder.appendingPathComponent("\(baseName) \(index).\(ext)")
                if !fileManager.fileExists(atPath: numbered.path) {
                    return numbered
                }
            }
            return folder.appendingPathComponent("\(baseName) \(UUID().uuidString).\(ext)")
        }
        return candidate
    }

    private func isStable(_ url: URL, folderID: UUID, firstSignature: FileSignature) async -> Bool {
        if stabilityDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: stabilityDelayNanoseconds)
        }
        return fileSignature(for: url, folderID: folderID) == firstSignature
    }

    private func fileSignature(for url: URL, folderID: UUID) -> FileSignature? {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]) else { return nil }
        guard values.isDirectory != true, values.isRegularFile != false else { return nil }
        return FileSignature(
            folderID: folderID,
            name: url.lastPathComponent,
            size: values.fileSize ?? 0,
            modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    private func matchesIncludeRules(_ name: String) -> Bool {
        matches(patterns: includePatterns, name: name, defaultValue: true)
    }

    private func matchesExcludeRules(_ name: String) -> Bool {
        matches(patterns: excludePatterns, name: name, defaultValue: false)
    }

    private func matches(patterns: String, name: String, defaultValue: Bool) -> Bool {
        let tokens = patterns
            .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
            .map { String($0).lowercased() }
        guard !tokens.isEmpty else { return defaultValue }
        let lowercasedName = name.lowercased()
        return tokens.contains { token in
            fnmatch(token, lowercasedName, 0) == 0 || lowercasedName.contains(token)
        }
    }

    private func resolveFolderURL(_ folder: WatchedFolder) -> URL? {
        resolveBookmark(folder.bookmarkData)
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        userDefaults.set(data, forKey: Self.foldersKey)
    }

    private func savePatterns() {
        userDefaults.set(includePatterns, forKey: Self.includePatternsKey)
        userDefaults.set(excludePatterns, forKey: Self.excludePatternsKey)
    }

    private static func loadFolders(from userDefaults: UserDefaults) -> [WatchedFolder] {
        guard let data = userDefaults.data(forKey: foldersKey),
              let folders = try? JSONDecoder().decode([WatchedFolder].self, from: data) else {
            return []
        }
        return folders
    }

    private static func makeBookmark(for url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func isOverlyBroadFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return path == "/" || path == home
    }

    private static func deliverNotification(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}

private struct FolderMonitor {
    let source: DispatchSourceFileSystemObject
}

private struct FileSignature: Hashable {
    let folderID: UUID
    let name: String
    let size: Int
    let modified: TimeInterval
}
