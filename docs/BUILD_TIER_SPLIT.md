# Build System: Tier Split Implementation

**Goal**: Build three separate Python environments instead of one bundled-everything approach.

---

## Current State

```
build_python_env.sh → Python.xcframework bundled in app
  └─ requirements.txt (1.3GB with all dependencies including torch/mlx)
```

**Problem**: Pro users download all ML frameworks even if they don't buy Max tier.

---

## Target State

```
App Bundle (Upmarket.app):
  └─ Python.xcframework (~50MB)
      └─ requirements-basic.txt
          ├─ ocrmac (Vision framework)
          ├─ pillow, numpy, pydantic (utilities)

User Downloads:
  ├─ python_runtime_pro (~350MB)
  │   └─ requirements-pro.txt
  │       ├─ Docling + docling-core, parse
  │       ├─ Office handlers (pypdfium2, mammoth, pptx, openpyxl)
  │       └─ utilities
  │
  └─ ai_libraries (~750MB) [Max tier only]
      └─ requirements-ai.txt
          ├─ torch, torchvision
          ├─ mlx, mlx-metal, mlx-vlm
          └─ transformers, huggingface_hub
```

---

## Requirements Files

### ✅ Already Created
- `requirements-basic.txt` — App bundle (~50MB)
- `requirements-pro.txt` — Pro download (~350MB)  
- `requirements-ai.txt` — Max download (~750MB)

All verified to match original `requirements.txt` exactly.

---

## Build Script Changes

### Step 1: Modify `build_python_env.sh`

**Current behavior** (line 71):
```bash
--requirement requirements.txt
```

**Change to**:
```bash
--requirement requirements-basic.txt
```

This bundles ONLY Basic tier libraries in the app.

**Location**: `scripts/build_python_env.sh` line 71

### Step 2: Create Build Commands for Downloadable Packages

Add new functions to `build_python_env.sh` or create `scripts/build_python_downloads.sh`:

```bash
# Build Pro runtime (~350MB download package)
build_pro_runtime() {
  local output_dir="$1"
  mkdir -p "$output_dir/lib/python3.12/site-packages"
  pip install --target "$output_dir/lib/python3.12/site-packages" \
    --requirement requirements-pro.txt
  # Compress into: python_runtime_pro.tar.gz
}

# Build AI libraries (~750MB download package)
build_ai_libraries() {
  local output_dir="$1"
  mkdir -p "$output_dir/lib/python3.12/site-packages"
  pip install --target "$output_dir/lib/python3.12/site-packages" \
    --requirement requirements-ai.txt
  # Compress into: ai_libraries.tar.gz
}
```

---

## Integration Points

### App Store / Background Assets

Currently, models download via:
- App Store Background Assets (on App Store)
- GitHub CDN (in DEBUG builds)

The **python_runtime_pro** and **ai_libraries** packages need the same delivery mechanism:
- `ModelAsset.pythonRuntime` → `python_runtime_pro.tar.gz` (~350MB)
- `ModelAsset.aiLibraries` → `ai_libraries.tar.gz` (~750MB)

These are extracted to:
```
~/Library/Application Support/Upmarket/models/
  ├── python_runtime_pro/
  ├── ai_libraries/
  └── upmarket_ai/ (model weights)
```

### Runtime Loading

`UpmarketRuntimeHelper` needs to add both directories to PYTHONPATH:
```bash
export PYTHONPATH=\
  ~/Library/Application Support/Upmarket/models/python_runtime_pro/lib/python3.12/site-packages:\
  ~/Library/Application Support/Upmarket/models/ai_libraries/lib/python3.12/site-packages:$PYTHONPATH
```

---

## Validation Checklist

Before deploying:

- [ ] `build_python_env.sh` uses `requirements-basic.txt` for bundled framework
- [ ] App bundle Python framework is ~50MB (verify with `du -sh`)
- [ ] Build command for `python_runtime_pro` exists and produces ~350MB archive
- [ ] Build command for `ai_libraries` exists and produces ~750MB archive
- [ ] `UpmarketRuntimeHelper` correctly adds both directories to PYTHONPATH
- [ ] Pro users: Can convert with Basic + Pro (Docling)
- [ ] Max users: Can convert with Basic + Pro + Max (Granite Docling MLX)
- [ ] Tier validation: Max users without aiLibraries cannot use AI pipeline
- [ ] Tests pass: `gate.sh quick` and `gate.sh minor`

---

## Size Targets (Post-Build Verification)

| Component | Target | How to Measure |
|-----------|--------|---|
| App bundle Python | ~50MB | `du -sh Upmarket/Python` |
| python_runtime_pro | ~350MB | `du -sh <output>/lib/python3.12/site-packages` |
| ai_libraries | ~750MB | `du -sh <output>/lib/python3.12/site-packages` |

If actual sizes differ significantly:
1. Update `AppTier.swift` `sizeMB` values
2. Update UI copy in `PreferencesView.stateDescription`
3. Update menu bar sizes in `MenuBarDropdown`

---

## Timeline

1. **Phase 1 (Now)**: ✅ Contract defined, requirements split validated
2. **Phase 2 (Build)**: Modify `build_python_env.sh` to use requirements-basic.txt
3. **Phase 3 (Download)**: Create build commands for Pro & Max packages
4. **Phase 4 (Integration)**: Wire into App Store Background Assets
5. **Phase 5 (Validation)**: Measure actual sizes, update contract if needed
6. **Phase 6 (Testing)**: Full tier validation across all three tiers
7. **Phase 7 (Release)**: Updated docs + commit to main
