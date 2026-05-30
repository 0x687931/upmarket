# Upmarket — Release Process

## Before Every Release

### 1. Check upstream dependencies for updates
```bash
./scripts/update_dependencies.sh --check-only
```

Key repos to watch:
- **Docling**: https://github.com/docling-project/docling/releases
- **PyMuPDF**: https://github.com/pymupdf/PyMuPDF/releases  
- **BeeWare Python**: https://github.com/beeware/Python-Apple-support/releases
- **Feature flags**: `docs/public/flags.json` (language support changes)

### 2. Apply updates
```bash
./scripts/update_dependencies.sh
```

### 3. Test conversion quality
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

### 4. Build and test in Xcode
- Cmd+Shift+K (clean)
- Cmd+B (build)
- Cmd+R (run) — test with real documents

### 5. Update version number
In Xcode: Upmarket target → General → Version (MARKETING_VERSION)
Bump: patch for bug fixes (1.0.1), minor for features (1.1.0), major for breaking (2.0.0)

### 6. Archive and submit
- Product → Archive
- Distribute App → App Store Connect
- Upload

---

## Enabling New Languages for Upmarket AI

When Docling improves support for a language (e.g. Japanese):

1. Test conversion quality manually
2. Edit `docs/public/flags.json`:
   - Move language code from `ai_experimental_locales` to `ai_supported_locales`
   - Bump `version` number
3. Push to `main` — GitHub Pages serves the updated file instantly
4. No app update needed — users get AI for that language immediately

---

## Dependency Version History

| Version | Docling | PyMuPDF | PyTorch | Notes |
|---|---|---|---|---|
| 1.0.0 | 2.96.0 | 1.27.2 | 2.12.0 | Initial release |

---

## Known Issues Per Dependency Version

### Docling
- All versions: RT-DETRv2 uses float64 — apply `scripts/patch_mps.sh` after any transformers update
- v2.96.0: `num_pages()` must be called as a method, not accessed as attribute

### PyTorch
- 2.x on Apple Silicon: MPS backend auto-enabled, no code changes needed
- Intel Mac: falls back to CPU automatically
