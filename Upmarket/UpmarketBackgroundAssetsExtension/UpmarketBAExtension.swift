import BackgroundAssets
import Foundation

/// Background Assets extension — schedules AI-tier model downloads on app install/update.
///
/// Apple's CDN delivers the archives automatically before (or shortly after) first launch.
/// The main app's BackgroundAssetsDownloadService receives and extracts them.
///
/// To wire this up:
///   1. In Xcode, add a new "Background Assets" App Extension target named
///      "UpmarketBackgroundAssetsExtension".
///   2. Replace the generated principal class with this file.
///   3. Set the extension's Info.plist NSExtension → NSExtensionPrincipalClass to
///      "UpmarketBackgroundAssetsExtension".
///   4. Add entitlement "com.apple.developer.background-assets-downloader" to the extension.
///   5. Add entitlement "com.apple.developer.background-assets" to the main app.
///   6. Register the asset URLs below in App Store Connect under your app's
///      "App Store" → "Additional Resources" section.
@available(macOS 13.3, *)
@objc(UpmarketBAExtension)
final class UpmarketBAExtension: NSObject, BAApplicationExtensionProtocol {

    private static let appGroup = "group.com.upmarket.app"

    // MARK: - BAApplicationExtensionProtocol

    func applicationDidInstall(_ metadata: BAApplicationExtensionInfo) {
        scheduleAIDownloads(essential: metadata.platformParameters.essentialDownloadsAllowed)
    }

    func applicationDidUpdate(_ metadata: BAApplicationExtensionInfo) {
        scheduleAIDownloads(essential: metadata.platformParameters.essentialDownloadsAllowed)
    }

    func applicationWillUninstall(_ metadata: BAApplicationExtensionInfo) {
        // Nothing to clean up — the OS removes downloads from its CDN cache.
    }

    // MARK: - Private

    private func scheduleAIDownloads(essential: Bool) {
        guard isAppleSilicon else {
            // AI-tier models require Apple Silicon; skip scheduling on Intel.
            return
        }

        for asset in AssetCatalog.aiAssets {
            let download = BAURLDownload(
                identifier: asset.downloadID,
                request: URLRequest(url: asset.url),
                fileSize: asset.fileSize,
                applicationGroupIdentifier: Self.appGroup
            )
            // Essential = downloaded before first launch (ideal for onboarding).
            // Non-essential = downloaded in background after install.
            // The caller passes essential=true only when the system allows it.
            download.isEssential = essential

            do {
                try BADownloadManager.shared.scheduleDownload(download)
            } catch BADownloadError.notPermitted {
                // Will be retried on next launch or update.
                break
            } catch {
                // Already scheduled or another benign error — ignore.
            }
        }
    }

    private var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) { bytes in
            String(cString: bytes.bindMemory(to: CChar.self).baseAddress!)
        }.hasPrefix("arm")
    }
}

// MARK: - Asset catalog

@available(macOS 13.3, *)
private enum AssetCatalog {

    struct Asset {
        let downloadID: String
        let url: URL
        let fileSize: Int
    }

    /// AI-tier assets registered in App Store Connect.
    /// Update these URLs and sizes whenever a new model release is published.
    ///
    /// Workflow:
    ///   1. Run `scripts/build/stage_first_party_model_assets.py` to build manifests.
    ///   2. Upload archives to App Store Connect → Additional Resources.
    ///   3. Update the URLs below to the App Store Connect CDN URLs Apple provides.
    ///   4. Bump the app version so applicationDidUpdate fires for existing installs.
    //
    // Only the default engine (upmarket_ai) is pre-scheduled here so it is ready at first
    // launch. The opt-in alternative (lfm25_vl, ~2.1 GB) is NOT pre-scheduled — it downloads
    // on demand via BackgroundAssetsDownloadService.install(key:) when the user selects it,
    // so users never pay for weights they didn't choose. It must still be registered in
    // App Store Connect for the on-demand BADownloadManager schedule to resolve.
    static let aiAssets: [Asset] = [
        Asset(
            downloadID: "com.upmarket.download.upmarket-ai",
            // Replace with the App Store Connect CDN URL for the AI model archive.
            url: URL(string: "https://placeholder.apple.cdn/upmarket_ai.tar.gz")!,
            fileSize: 700_000_000
        ),
    ]
}
