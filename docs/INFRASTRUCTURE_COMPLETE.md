# Tier and Model Delivery Infrastructure

**Status:** Native tier infrastructure is implemented. Production model delivery is wired for
Apple-hosted managed Background Assets and still requires App Store Connect upload plus
TestFlight verification for each release.

## Runtime architecture

- Basic and Pro conversion paths are native Swift and require no downloaded runtime.
- Max adds two local vision-language model choices:
  - `granite_docling` — approximately 600 MB.
  - `lfm25_vl` — approximately 2.0 GB.
- There is no embedded Python runtime, helper process, or downloadable Python package.
- Model inference remains local; only model delivery requires network access.

## Delivery paths

### Debug and local development

`FirstPartyModelDownloadService` downloads checksum-verified archives into:

```text
~/Library/Application Support/Upmarket/models/<model-key>/
```

This path is selected by the existing `#if DEBUG` split in `ModelManager`.

### Release and TestFlight

Apple hosts managed `.aar` packs through App Store Connect:

| Model key | Asset-pack ID |
| --- | --- |
| `granite_docling` | `com.upmarket.app.models.granite` |
| `lfm25_vl` | `com.upmarket.app.models.lfm25-vl` |

The app uses `AssetPackManager` to request, resolve, report progress for, and remove packs.
`UpmarketBackgroundAssetsExtension` is embedded in `Upmarket.app` and conforms to
`StoreDownloaderExtension`.

Resolved managed-pack URLs are process-lifetime values. Engines request the URL from
`ModelManager.resolveModelDirectory(for:)` when needed; the URL is never persisted.

## Packaging

The packager reuses the model file catalog in `stage_model_assets.py`:

```sh
scripts/models/package_asset_packs.py \
  --model granite_docling \
  --model-dir /path/to/granite_docling \
  --out-dir build/asset-packs

scripts/models/package_asset_packs.py \
  --model lfm25_vl \
  --model-dir /path/to/lfm25_vl \
  --out-dir build/asset-packs
```

It validates the required files, stages the expected top-level model directory, and invokes
`xcrun ba-package` to create each `.aar`.

## Release validation

Repository validation:

```sh
scripts/ci/gate.sh quick
scripts/models/package_asset_packs.py --selftest
```

Manual release validation:

1. Upload both `.aar` packs to App Store Connect Background Assets.
2. Associate both packs with the candidate app build.
3. Install through TestFlight on a clean Mac.
4. Download each model, verify progress reporting, convert a representative document, relaunch,
   and verify the model remains available.
5. Delete each model in Preferences and verify its managed pack is removed.

The repository build cannot prove App Store-hosted delivery. TestFlight is the release gate for
that final integration.
