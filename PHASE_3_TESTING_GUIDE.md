# Phase 3: End-to-End Testing (With Generated Packages)

**Status**: Packages being generated via `scripts/build_python_packages.sh --pro --ai`

This guide covers testing the tier system with actual downloadable packages.

---

## Prerequisites

- [ ] `python_runtime_pro.tar.gz` (~350MB) generated
- [ ] `ai_libraries.tar.gz` (~750MB) generated
- [ ] Packages available at local file paths or uploaded to CDN/GitHub
- [ ] App rebuilt and running in DEBUG mode

---

## 3.1 Package Extraction and Validation

### Setup

```bash
# If using local files, configure Info.plist for testing:
mkdir -p /tmp/upmarket_test
cp build/python_packages/*.tar.gz /tmp/upmarket_test/

# Then add to Upmarket/Upmarket/Info.plist:
# <key>UpmarketBAAssetURL_python_runtime_pro</key>
# <string>file:///tmp/upmarket_test/python_runtime_pro.tar.gz</string>
# <key>UpmarketBAAssetURL_ai_libraries</key>
# <string>file:///tmp/upmarket_test/ai_libraries.tar.gz</string>
```

### Verification

- [ ] Delete any existing downloads:
  ```bash
  rm -rf ~/Library/Application\ Support/Upmarket/runtime/
  ```

- [ ] Rebuild and test:
  ```bash
  scripts/dev/run_app.sh --relaunch
  ```

---

## 3.2 Pro Tier End-to-End

**Goal**: Verify Pro tier download, extraction, and Docling conversion

### Steps

1. **Set Tier to Pro**
   - [ ] Open Preferences → About
   - [ ] Click "Pro" button (DEBUG mode)
   - [ ] Verify store.tier shows "Upmarket Pro"

2. **Verify UI State**
   - [ ] Menu bar shows "Add AI (750 MB)…"
   - [ ] Preferences → Conversion shows:
     - [ ] "Enhanced Conversions · 350 MB (one-time download)" with Download button
     - [ ] "AI for Complex Documents" shows locked state

3. **Download Pro Runtime**
   - [ ] Click Download on Enhanced Conversions
   - [ ] Monitor Console.app for progress:
     ```bash
     log stream --predicate 'eventMessage contains "Download"'
     ```
   - [ ] Watch BackgroundAssets progress

4. **Verify Files Extracted**
   ```bash
   ls -la ~/Library/Application\ Support/Upmarket/runtime/python_runtime_pro/
   # Should show:
   # - lib/python3.12/site-packages/
   # - python_runtime_ready (marker file)
   ```

5. **Test Docling Conversion**
   - [ ] Convert a PDF with Enhanced (Docling) pathway
   - [ ] Verify output is valid Markdown
   - [ ] Check logs for no Python import errors

**Success Criteria**:
- [ ] Download completes to 100%
- [ ] Files in correct location with marker file
- [ ] PYTHONPATH includes python_runtime_pro
- [ ] Docling conversion works without errors
- [ ] Output Markdown is valid

---

## 3.3 Max Tier End-to-End

**Goal**: Verify Max tier sequential downloads and MLX conversion

### Steps

1. **Set Tier to Max**
   - [ ] Open Preferences → About
   - [ ] Click "Max" button (DEBUG mode)
   - [ ] Verify store.tier shows "Upmarket Max"

2. **Clean Pro Runtime** (to test full flow)
   ```bash
   rm -rf ~/Library/Application\ Support/Upmarket/runtime/python_runtime_pro/
   ```

3. **Verify UI State**
   - [ ] Menu bar shows "All Features Unlocked"
   - [ ] Preferences → Conversion shows both models available
   - [ ] Click Download on AI model

4. **Verify Sequential Downloads**
   - [ ] First download: python_runtime_pro (~350MB)
   - [ ] Then download: ai_libraries (~750MB)
   - [ ] Then download: granite_docling (~600MB, if configured)
   - [ ] All download in correct order (Pro before AI)

5. **Verify All Files Extracted**
   ```bash
   # Pro runtime
   ls ~/Library/Application\ Support/Upmarket/runtime/python_runtime_pro/
   # Should have lib/ and python_runtime_ready

   # AI libraries
   ls ~/Library/Application\ Support/Upmarket/runtime/ai_libraries/
   # Should have lib/ and ai_libraries_ready

   # Model weights
   ls ~/Library/Application\ Support/Upmarket/models/
   # Should have ibm-granite--granite-docling-258M-mlx/
   ```

6. **Verify PYTHONPATH**
   - [ ] Check logs for PYTHONPATH configuration
   - [ ] Should include all three: bundled + pro + ai

7. **Test MLX Conversion**
   - [ ] Convert same PDF with AI (Granite Docling MLX) pathway
   - [ ] Verify output is valid Markdown
   - [ ] Check quality is better than Enhanced (layout + AI understanding)
   - [ ] Check logs for mlx/transformers imports successful

**Success Criteria**:
- [ ] All three downloads complete sequentially
- [ ] Files in correct locations with marker files
- [ ] PYTHONPATH includes all tiers
- [ ] MLX conversion works without errors
- [ ] Output Markdown shows improved quality

---

## 3.4 Cross-Tier Compatibility

### Scenario A: Pro → Max Upgrade

1. **Start as Pro user** (Pro runtime already downloaded)
   - [ ] Preferences → About: Set to "Pro"
   - [ ] Verify python_runtime_pro exists

2. **Upgrade to Max**
   - [ ] Preferences → About: Set to "Max"
   - [ ] Download AI
   - [ ] Should NOT re-download Pro (already exists)
   - [ ] Only downloads ai_libraries (~750MB) + granite_docling (~600MB)

**Verify**:
- [ ] Pro runtime NOT re-downloaded
- [ ] Both pathways work (Enhanced + AI)

### Scenario B: Max → Pro Downgrade

1. **Start as Max user** (all packages downloaded)
   - [ ] Preferences → About: Set to "Max"
   - [ ] Verify all three packages present

2. **Downgrade to Pro**
   - [ ] Preferences → About: Set to "Pro"
   - [ ] Enhanced conversion still works
   - [ ] AI conversion shows locked (requires Max)
   - [ ] ai_libraries and granite_docling still on disk (can be cleaned up)

**Verify**:
- [ ] Enhanced pathway works without error
- [ ] Clear error message when trying AI: "Upmarket AI requires Upmarket Max"

---

## 3.5 Error Handling

### Scenario A: Delete Package Mid-Conversion

1. **With Pro downloaded, start conversion**:
   ```bash
   # Start a Pro/Enhanced conversion in the app
   # Simultaneously delete the Pro runtime
   rm -rf ~/Library/Application\ Support/Upmarket/runtime/python_runtime_pro/
   ```

2. **Verify graceful error**:
   - [ ] Conversion fails with clear message (not silent failure)
   - [ ] Error suggests re-downloading: "Download Enhanced Conversions to use Enhanced conversion"
   - [ ] Basic tier still works (native conversion available)

### Scenario B: Corrupt Package Validation

1. **Corrupt the ai_libraries_ready marker**:
   ```bash
   echo "corrupted" > ~/Library/Application\ Support/Upmarket/runtime/ai_libraries/ai_libraries_ready
   ```

2. **Try to use Max tier**:
   - [ ] Validation detects corruption
   - [ ] Error message displayed: "Enhanced Conversions package is corrupted"
   - [ ] Option to re-download

---

## 3.6 PYTHONPATH Verification

### Check Runtime Configuration

During any conversion, verify PYTHONPATH is set correctly:

```bash
# Option 1: Monitor UpmarketRuntimeHelper logs
log stream --predicate 'eventMessage contains "PYTHONPATH"'

# Option 2: Add debug output to configureRuntime() temporarily
# Print: setenv("PYTHONPATH", pythonPath, 1)
# Check Console.app for final value
```

**Expected PYTHONPATH order**:
- Basic: `/path/to/bundled/lib/python3.12:/path/to/bundled/lib/python3.12/site-packages`
- Pro: `^:~/Library/Application Support/Upmarket/runtime/python_runtime_pro/lib/python3.12/site-packages`
- Max: `^:~/Library/Application Support/Upmarket/runtime/ai_libraries/lib/python3.12/site-packages`

---

## Checklist: Before Release

### Code Quality ✅
- [ ] Basic tier native conversion works
- [ ] Pro tier available when python_runtime_pro present
- [ ] Max tier available when all packages present
- [ ] Clear error messages when tier unavailable
- [ ] PYTHONPATH correctly constructed

### Packages ✅
- [ ] python_runtime_pro.tar.gz generated (~350MB)
- [ ] ai_libraries.tar.gz generated (~750MB)
- [ ] Both contain correct files (no ML in pro, no docling in ai)
- [ ] Validation manifests correct (python_runtime_ready, ai_libraries_ready)

### Download Service ✅
- [ ] BackgroundAssetsDownloadService downloads correctly
- [ ] Files extract to correct locations
- [ ] PYTHONPATH includes downloaded packages
- [ ] Sequential downloads work (pro before ai)

### User Experience ✅
- [ ] Download progress shown in UI
- [ ] Clear tier locks/unlocks
- [ ] Helpful error messages
- [ ] Conversions work for all available tiers
- [ ] Menu shows correct download sizes

### Rollback ✅
- [ ] Can quickly revert to bundled 1.3GB if needed
- [ ] No data loss if rollback occurs

---

## Troubleshooting

### Package Not Downloading

- Check URL is publicly accessible
- Verify Content-Type is `application/gzip`
- Check file size matches estimate (±5%)
- Look for BackgroundAssets logs: `log stream --predicate 'process == "BackgroundAssets"'`

### PYTHONPATH Missing Package

```bash
# Check file extracted correctly
ls ~/Library/Application\ Support/Upmarket/runtime/

# Check marker files exist
ls ~/Library/Application\ Support/Upmarket/runtime/python_runtime_pro/python_runtime_ready
ls ~/Library/Application\ Support/Upmarket/runtime/ai_libraries/ai_libraries_ready

# Rebuild app to ensure latest UpmarketRuntimeHelper
scripts/dev/run_app.sh --relaunch
```

### Docling/MLX Not Found

- Rebuild app
- Verify packages extracted to correct location
- Check logs for PYTHONPATH configuration
- Ensure marker files present (validation passed)

---

## Timeline

- **Package build**: 30-60 minutes
- **Local testing** (3.1-3.5): 30 minutes
- **Total before release**: ~1.5 hours

---

**Ready for Phase 3 when packages are available.**
