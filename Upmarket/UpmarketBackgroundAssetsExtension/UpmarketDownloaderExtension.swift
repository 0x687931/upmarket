import BackgroundAssets
import ExtensionFoundation
import StoreKit

/// Apple-hosted, **Managed** Background Assets downloader extension.
///
/// Both model packs (com.upmarket.app.models.granite, com.upmarket.app.models.lfm25-vl) use an
/// `onDemand` download policy, so there is no install/update scheduling work here — the app
/// requests availability at runtime via `AssetPackManager`. This extension only establishes the
/// required Apple-hosted managed-assets contract and approves the downloads the app asks for.
///
/// Target wiring (one-time, in Xcode — see PR notes):
///   - Target type: Background Download Extension → Apple-Hosted, Managed.
///   - Bundle ID: com.upmarket.app.background-assets; embedded in Upmarket.app.
///   - Entitlement: com.apple.developer.background-assets-downloader.
@main
struct UpmarketDownloaderExtension: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool {
        true
    }
}
