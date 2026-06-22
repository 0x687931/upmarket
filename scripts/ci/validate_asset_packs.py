#!/usr/bin/env python3
"""Validate the managed Background Assets contract before release.

Apple-hosted managed asset packs replace the old self-hosted URL downloads. This guard fails
if production code regresses to the URL API, keeps a placeholder URL, or if the asset-pack
identifiers / directory selectors drift out of sync between the manifests and Swift.

It does NOT inspect .aar contents — that's package_asset_packs.py's job (which reuses the single
expected-files catalog in stage_model_assets.MODELS).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP_TIER = ROOT / "Upmarket" / "Shared" / "AppTier.swift"
MANIFEST_DIR = ROOT / "resources" / "asset-packs"
EXTENSION = ROOT / "Upmarket" / "UpmarketBackgroundAssetsExtension" / "UpmarketDownloaderExtension.swift"
EXTENSION_INFO = ROOT / "Upmarket" / "UpmarketBackgroundAssetsExtension" / "Info.plist"
EXTENSION_ENTITLEMENTS = (
    ROOT
    / "Upmarket"
    / "UpmarketBackgroundAssetsExtension"
    / "UpmarketBackgroundAssetsExtension.entitlements"
)
PROJECT = ROOT / "Upmarket" / "Upmarket.xcodeproj" / "project.pbxproj"
INFO_PLIST = ROOT / "Upmarket" / "Upmarket" / "Info.plist"

# Production Swift (app + shared + extension) must not use the legacy URL API or placeholders.
PROD_SWIFT_DIRS = [
    ROOT / "Upmarket" / "Upmarket",
    ROOT / "Upmarket" / "Shared",
    ROOT / "Upmarket" / "UpmarketBackgroundAssetsExtension",
]
FORBIDDEN = ["BAURLDownload", "BADownloadManager", "BAApplicationExtensionProtocol", "placeholder.apple.cdn"]


def fail(msg: str) -> int:
    print(f"error: {msg}", file=sys.stderr)
    return 1


def main() -> int:
    tier = APP_TIER.read_text(encoding="utf-8")
    # Model keys (ModelAsset string raw values) and asset-pack IDs declared in Swift.
    swift_keys = set(re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', tier))
    swift_pack_ids = set(re.findall(r'"(com\.upmarket\.app\.models\.[\w.-]+)"', tier))
    if not swift_pack_ids:
        return fail("no asset-pack IDs found in AppTier.swift")

    # Manifests: assetPackID + directory selectors.
    manifest_ids, manifest_dirs = set(), set()
    for path in sorted(MANIFEST_DIR.glob("*.json")):
        m = json.loads(path.read_text(encoding="utf-8"))
        manifest_ids.add(m.get("assetPackID"))
        manifest_dirs.update(s.get("directory") for s in m.get("fileSelectors", []))
        if m.get("downloadPolicy", {}).get("onDemand") is None:
            return fail(f"{path.name}: expected onDemand downloadPolicy")

    if swift_pack_ids != manifest_ids:
        return fail(f"asset-pack ID mismatch: Swift {sorted(swift_pack_ids)} != manifests {sorted(manifest_ids)}")
    if not manifest_dirs <= swift_keys:
        return fail(f"manifest selectors {sorted(manifest_dirs)} not all model keys {sorted(swift_keys)}")

    # Extension target must be embedded and configured as the managed downloader.
    if not EXTENSION.exists():
        return fail(f"missing extension entry point: {EXTENSION}")
    extension = EXTENSION.read_text(encoding="utf-8")
    if "@main" not in extension or "StoreDownloaderExtension" not in extension:
        return fail("extension entry point must be @main and conform to StoreDownloaderExtension")

    project = PROJECT.read_text(encoding="utf-8")
    required_project_tokens = [
        "UpmarketBackgroundAssetsExtension.appex in Embed ExtensionKit Extensions",
        "PRODUCT_BUNDLE_IDENTIFIER = com.upmarket.app.background-assets;",
        (
            "CODE_SIGN_ENTITLEMENTS = "
            "UpmarketBackgroundAssetsExtension/UpmarketBackgroundAssetsExtension.entitlements;"
        ),
    ]
    for token in required_project_tokens:
        if token not in project:
            return fail(f"Xcode project missing managed extension wiring: {token}")

    if "com.apple.background-asset-downloader-extension" not in EXTENSION_INFO.read_text(
        encoding="utf-8"
    ):
        return fail("extension Info.plist has the wrong extension-point identifier")
    if "com.apple.developer.background-assets-downloader" not in EXTENSION_ENTITLEMENTS.read_text(
        encoding="utf-8"
    ):
        return fail("extension is missing the background-assets-downloader entitlement")

    # No leftover self-hosting Info.plist keys.
    if "UpmarketBAAssetURL" in INFO_PLIST.read_text(encoding="utf-8"):
        return fail("Info.plist still contains self-hosted UpmarketBAAssetURL keys")

    # No legacy URL API or placeholders in production Swift.
    for directory in PROD_SWIFT_DIRS:
        for swift in directory.rglob("*.swift"):
            text = swift.read_text(encoding="utf-8")
            for token in FORBIDDEN:
                if token in text:
                    return fail(f"{swift.relative_to(ROOT)} contains forbidden token {token!r}")

    print(f"ok: managed asset packs valid ({', '.join(sorted(manifest_ids))})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
