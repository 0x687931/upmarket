# Upmarket — Release Process

The canonical build, shipping, and deployment process is `docs/BUILD_SHIP_DEPLOY.md`. Use that document for release commands, UI automation, archive verification, TestFlight, App Store submission, and deployment evidence.

This file keeps dependency-specific notes that are still useful during release preparation.

## Before Every Release

### 1. Check upstream dependencies for updates
```bash
./scripts/update_dependencies.sh --check-only
```

Key repos to watch:
- **Docling**: https://github.com/docling-project/docling/releases
- **pypdfium2**: https://github.com/pypdfium2-team/pypdfium2/releases
- **BeeWare Python**: https://github.com/beeware/Python-Apple-support/releases
- **Feature flags**: CloudKit public record `FeatureFlags/global` in `iCloud.com.upmarket.app` (language support changes; see `docs/release/FEATURE_FLAG_LANGUAGE_POLICY.md`)

### 2. Stage candidate updates

Edit `requirements-candidate.txt` with exact pins only. Do not edit `requirements.txt` until the candidate has passed validation and human review.

```bash
./scripts/update_dependencies.sh --install-candidate
```

If accepted, promote by copying the exact candidate pins to `requirements.txt` in the same reviewed change.

### 3. Stage first-party model assets

Before TestFlight or App Store packaging, stage model manifests and files from a manifest-validated local cache, then upload the output directory to the Apple-hosted model location:

```bash
scripts/build/stage_first_party_model_assets.py --output build/first-party-model-assets
```

The app's default download path uses `FirstPartyModelDownloadService`. The Python/Hugging Face snapshot downloader is developer intake tooling only, is disabled unless `UPMARKET_ENABLE_DEVELOPER_MODEL_INTAKE=1`, and must not be the packaged customer download path.

### 4. Test conversion quality
```bash
# Test fast path (no models)
.venv/bin/python3 -c "
from docling_bridge.converter import convert
r = convert('path/to/test.pdf', {'use_enhanced': False})
print(r['success'], r['pipeline'], r['metadata'])
"

# Test enhanced path (requires layout models downloaded)
.venv/bin/python3 -c "
from docling_bridge.converter import convert
r = convert('path/to/complex.pdf', {'use_enhanced': True})
print(r['success'], r['pipeline'])
"
```

### 5. Build and test in Xcode
- Cmd+Shift+K (clean)
- Cmd+B (build)
- Cmd+R (run) — test with real documents

### 6. Update version number
In Xcode: Upmarket target → General → Version (MARKETING_VERSION)
Bump: patch for bug fixes (1.0.1), minor for features (1.1.0), major for breaking (2.0.0)

### 7. Archive and submit
- Product → Archive
- Distribute App → App Store Connect
- Upload

---

## Enabling New Languages for Upmarket AI

Feature flags describe Upmarket's shipped app behavior, not every upstream Docling or Granite Docling capability claim. Use `docs/release/cloudkit_feature_flags_seed.json` as the initial beta record.

When Docling or Granite Docling improves support for a language:

1. Confirm the upstream claim from a primary source and record it in `docs/release/FEATURE_FLAG_LANGUAGE_POLICY.md`
2. Add or identify representative fixtures for that language
3. Test Upmarket AI conversion quality on Apple Silicon with the pinned release runtime/model
4. Keep the language in `ai_experimental_locales` while the evidence is upstream-explicit early support only
5. Move the language to `ai_supported_locales` only after the shipped Upmarket path meets beta quality
6. Bump the CloudKit record `version`
7. Deploy the CloudKit schema/record change to production before release users need it
8. Verify the signed release build has `com.apple.developer.icloud-container-environment=Production`
9. No app update needed — users get AI for that language after the next feature availability check

---

## Dependency Version History

| Version | Docling | pypdfium2 | PyTorch | Notes |
|---|---|---|---|---|
| 1.0.0 | 2.96.0 | 5.8.0 | 2.12.0 | Initial release; PyMuPDF/pymupdf4llm excluded |

---

## Known Issues Per Dependency Version

### Docling
- All versions: RT-DETRv2 uses float64 — apply `scripts/patch_mps.sh` after any transformers update
- v2.96.0: `num_pages()` must be called as a method, not accessed as attribute

### PyTorch
- 2.x on Apple Silicon: MPS backend auto-enabled, no code changes needed
- Intel Mac: falls back to CPU automatically
