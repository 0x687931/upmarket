# Tier Testing Plan

## Phase 1: Code Verification (NOW - No Packages Needed)

### 1.1 Basic Tier - Native Conversion
**Goal**: Verify Basic tier conversion still works (PDFKit, Vision OCR, etc.)

- [ ] Open app in DEBUG mode (Preferences → About → "Basic")
- [ ] Confirm menu shows "Unlock Enhanced (350 MB)…"
- [ ] Preferences → Conversion shows both models locked
- [ ] Drag PDF to app, convert with native path
- [ ] Verify output works (Basic tier = always available)
- [ ] Check logs for no errors

**Success**: Native conversion works without any downloads

---

### 1.2 Tier Gating Logic
**Goal**: Verify tier system correctly locks/unlocks features

- [ ] Switch to "Pro" in Preferences → About
  - Menu should show "Add AI (750 MB)…"
  - Preferences → Conversion shows "Enhanced Conversions" available, "AI for Complex Documents" locked
  - Try to convert with Docling → Error: "requires python_runtime_pro"

- [ ] Switch to "Max" in Preferences → About
  - Menu should show "All Features Unlocked"
  - Both models show as available
  - Try to convert with MLX → Error: "requires ai_libraries"

- [ ] Switch back to "Basic"
  - Both models locked again
  - Native conversion still works

**Success**: Gating logic correctly enforces tier requirements

---

### 1.3 Code Paths - Import Logic
**Goal**: Verify code can load Pro/Max dependencies when they exist

Test by checking logs:
```bash
# In Terminal, watch for Python import attempts:
log stream --predicate 'process == "UpmarketRuntimeHelper"'

# Then in app, try each conversion:
# - Basic: Should use native APIs only
# - Pro (if runtime exists): Should import docling_bridge
# - Max (if all exist): Should import mlx_vlm
```

**Success**: No import errors, fallback logic works

---

### 1.4 PYTHONPATH Configuration
**Goal**: Verify UpmarketRuntimeHelper sets PYTHONPATH correctly

Check that the runtime helper configures paths for:
- Basic: Bundled Python only
- Pro: Bundled + python_runtime_pro (if present)
- Max: Bundled + python_runtime_pro + ai_libraries (if both present)

**Verify**: 
```bash
# Add debug output to UpmarketRuntimeHelper/main.swift configureRuntime()
# to print final PYTHONPATH value
# Check Console.app logs for correct path concatenation
```

**Success**: PYTHONPATH includes correct directories

---

### 1.5 Download Service Configuration
**Goal**: Verify BackgroundAssetsDownloadService is wired correctly

- [ ] Check download identifiers match enum in code:
  - `com.upmarket.download.python-runtime-pro` ✅
  - `com.upmarket.download.ai-libraries` ✅
  - `com.upmarket.download.upmarket-ai` ✅

- [ ] Verify destinationURL paths are correct:
  - python_runtime_pro → `~/Library/Application Support/Upmarket/runtime/python_runtime_pro/`
  - ai_libraries → `~/Library/Application Support/Upmarket/runtime/ai_libraries/`
  - upmarket_ai → `~/Library/Application Support/Upmarket/models/...`

- [ ] Verify estimatedFileSize values:
  - python_runtime_pro: 350MB ✅
  - ai_libraries: 750MB ✅
  - upmarket_ai: 600MB ✅

**Success**: All download paths and sizes configured correctly

---

## Phase 2: Generate Packages

```bash
chmod +x scripts/build_python_packages.sh
scripts/build_python_packages.sh --pro --ai

# Verify output
ls -lh build/python_packages/
# python_runtime_pro.tar.gz: ~350MB
# ai_libraries.tar.gz: ~750MB
```

---

## Phase 3: End-to-End Testing (With Packages)

### 3.1 Package Extraction and Validation

- [ ] Delete any existing downloads:
  ```bash
  rm -rf ~/Library/Application\ Support/Upmarket/runtime/
  ```

- [ ] Configure local URLs in Info.plist:
  ```xml
  <key>UpmarketBAAssetURL_python_runtime_pro</key>
  <string>file:///path/to/python_runtime_pro.tar.gz</string>
  <key>UpmarketBAAssetURL_ai_libraries</key>
  <string>file:///path/to/ai_libraries.tar.gz</string>
  ```

- [ ] Rebuild and test:
  ```bash
  scripts/dev/run_app.sh --relaunch
  ```

### 3.2 Pro Tier End-to-End

- [ ] Set to "Pro" tier (Preferences → About)
- [ ] Preferences → Conversion → Click "Download" on Enhanced
- [ ] Verify:
  - Download starts (BackgroundAssets)
  - File extracts to correct location
  - Validation manifest created
  - PYTHONPATH includes python_runtime_pro
- [ ] Try Docling conversion:
  - Should work without errors
  - Should produce correct output

**Success Criteria**:
- Download completes without errors
- Files extracted to `~/Library/Application Support/Upmarket/runtime/python_runtime_pro/`
- `python_runtime_ready` marker file exists
- Docling conversion produces valid Markdown

### 3.3 Max Tier End-to-End

- [ ] Set to "Max" tier (Preferences → About)
- [ ] Delete pro runtime (to test full flow):
  ```bash
  rm -rf ~/Library/Application\ Support/Upmarket/runtime/python_runtime_pro/
  ```
- [ ] Preferences → Conversion → Click "Download" on AI Model
- [ ] Verify sequential downloads:
  1. python_runtime_pro downloads first (~350MB)
  2. ai_libraries downloads second (~750MB)
  3. upmarket_ai downloads (if configured)
- [ ] All extract to correct locations
- [ ] PYTHONPATH includes both directories in correct order
- [ ] Try Granite MLX conversion:
  - Should work without errors
  - Should produce correct output

**Success Criteria**:
- All three downloads complete successfully
- Files extracted to correct locations
- Marker files exist (python_runtime_ready, ai_libraries_ready)
- MLX conversion produces valid Markdown with better quality

### 3.4 Cross-Tier Compatibility

- [ ] Download as Pro, then upgrade to Max
  - Should reuse existing python_runtime_pro
  - Should only download ai_libraries (not re-download pro)

- [ ] Download as Max, then downgrade to Pro
  - Pro conversion still works (ignores ai_libraries)
  - Max conversion disabled with clear error

### 3.5 Error Handling

- [ ] Delete python_runtime_pro mid-conversion
  - Should error gracefully: "Enhanced conversion unavailable"
  - Basic tier still works

- [ ] Corrupt ai_libraries validation manifest
  - Should error during validation
  - Clear message about corrupted package
  - Option to re-download

---

## Checklist: Before Release

### Code Quality
- [ ] Basic tier native conversion works ✅
- [ ] Pro tier available when python_runtime_pro present ✅
- [ ] Max tier available when all packages present ✅
- [ ] Clear error messages when tier unavailable ✅
- [ ] PYTHONPATH correctly constructed ✅

### Packages
- [ ] python_runtime_pro.tar.gz generated (~350MB)
- [ ] ai_libraries.tar.gz generated (~750MB)
- [ ] Both contain correct files (no ML in pro, no docling in ai)
- [ ] Validation manifests correct
- [ ] Ready marker files present

### Download Service
- [ ] BackgroundAssetsDownloadService downloads correctly
- [ ] Files extract to correct locations
- [ ] PYTHONPATH includes downloaded packages
- [ ] Sequential downloads work (pro before ai)

### User Experience
- [ ] Download progress shown
- [ ] Clear tier locks/unlocks
- [ ] Helpful error messages
- [ ] Conversions work for all available tiers

### Rollback
- [ ] Can quickly revert to bundled 1.3GB if needed
- [ ] No data loss if rollback occurs

---

## Test Matrix

| Tier | Has Pro? | Has AI Libs? | Has Model? | Should Work |
|------|----------|-------------|-----------|------------|
| Basic | ❌ | ❌ | ❌ | Native only ✅ |
| Pro | ✅ | ❌ | ❌ | Native + Docling ✅ |
| Max (incomplete) | ❌ | ✅ | ❌ | Should fail (needs pro) |
| Max (incomplete) | ✅ | ❌ | ❌ | Should fail (needs ai libs) |
| Max (complete) | ✅ | ✅ | ✅ | All pathways ✅ |

---

## Sign-Off

When all tests pass:
- [ ] Code is solid (Phase 1)
- [ ] Packages work (Phase 3)
- [ ] Ready for App Store deployment

**Phase 1 Target**: 30 minutes
**Phase 3 Target**: 1 hour
**Total**: ~1.5 hours before production release
