# Next Steps: From Infrastructure to Packages

**All infrastructure is in place. Here's what to do next.**

---

## Step 1: Generate the Packages (5 minutes)

```bash
# Make the script executable
chmod +x scripts/build_python_packages.sh

# Generate both Pro and AI packages
scripts/build_python_packages.sh --pro --ai

# Verify they were created
ls -lh build/python_packages/
```

**Expected output:**
```
-rw-r--r--  python_runtime_pro.tar.gz   ~350MB
-rw-r--r--  ai_libraries.tar.gz         ~750MB
```

---

## Step 2: Test Locally (Optional, 10 minutes)

### Quick Local Test (Without Uploading)

1. Move packages to a test directory:
```bash
mkdir -p /tmp/upmarket_test
cp build/python_packages/*.tar.gz /tmp/upmarket_test/
```

2. Add to Info.plist for local testing:
```bash
# In Upmarket/Upmarket/Info.plist, add:
<key>UpmarketBAAssetURL_python_runtime_pro</key>
<string>file:///tmp/upmarket_test/python_runtime_pro.tar.gz</string>
<key>UpmarketBAAssetURL_ai_libraries</key>
<string>file:///tmp/upmarket_test/ai_libraries.tar.gz</string>
```

3. Rebuild and test:
```bash
scripts/dev/run_app.sh --relaunch
# Use DEBUG tier controls to test downloads
```

4. Verify PYTHONPATH includes all tiers:
```bash
# Inside app, check logs for PYTHONPATH configuration
# Should see paths added for python_runtime_pro and ai_libraries
```

---

## Step 3: Upload to CDN/GitHub (5-10 minutes)

### Option A: GitHub Releases (Recommended for Now)

```bash
# Create a release tag
git tag v1.0-tier-infrastructure
git push origin v1.0-tier-infrastructure

# Upload packages to GitHub Release
# Using gh CLI:
gh release create v1.0-tier-infrastructure \
  build/python_packages/python_runtime_pro.tar.gz \
  build/python_packages/ai_libraries.tar.gz

# Get the download URLs (they'll be in the release)
# Example: https://github.com/yourusername/upmarket/releases/download/v1.0-tier-infrastructure/python_runtime_pro.tar.gz
```

### Option B: Your CDN
```bash
# Upload to your CDN/storage
# Example with S3:
aws s3 cp build/python_packages/python_runtime_pro.tar.gz s3://your-bucket/models/
aws s3 cp build/python_packages/ai_libraries.tar.gz s3://your-bucket/models/

# Get public URLs
# Example: https://your-cdn.example.com/models/python_runtime_pro.tar.gz
```

---

## Step 4: Configure in App Store Connect

1. Go to **App Store Connect → Your App → Distribution → Background Assets**

2. Add three assets:

   **Asset 1: Pro Runtime**
   - Identifier: `com.upmarket.download.python-runtime-pro`
   - URL: `https://your-cdn.com/python_runtime_pro.tar.gz`
   - Size: ~350 MB
   - Bundle ID: `com.upmarket.app`

   **Asset 2: AI Libraries**
   - Identifier: `com.upmarket.download.ai-libraries`
   - URL: `https://your-cdn.com/ai_libraries.tar.gz`
   - Size: ~750 MB
   - Bundle ID: `com.upmarket.app`

   **Asset 3: Model Weights (Existing)**
   - Identifier: `com.upmarket.download.upmarket-ai`
   - URL: `<existing>`
   - Size: ~600 MB
   - Bundle ID: `com.upmarket.app`

3. Save and wait for Apple to validate the assets

---

## Step 5: Test in Beta/Staging (15 minutes)

Before releasing publicly:

1. **TestFlight with new config:**
   - Build and submit to TestFlight
   - Download app on test device
   - Open Preferences → Conversion

2. **Pro Tier Test:**
   - Use DEBUG tier override: Preferences → About → "Pro"
   - Click Download on Enhanced
   - Verify it downloads 350MB
   - Try converting with Docling

3. **Max Tier Test:**
   - Use DEBUG tier override: Preferences → About → "Max"
   - Click Download on AI Model
   - Should download Pro runtime (if not already) + AI libraries + model
   - Try converting with Granite Docling MLX

4. **Verify No Errors:**
   - Check logs for any PYTHONPATH issues
   - Confirm all tiers work (Basic, Pro, Max)

---

## Step 6: Release (Documentation + Deploy)

```bash
# 1. Update release notes mentioning:
#    - "App bundle reduced by 90% (~136MB vs 1.3GB)"
#    - "Pro tier downloads are 350MB (was bundled)"
#    - "Max tier adds 750MB AI libraries + 600MB model weights"
#    - Link to TIER_CONTRACT.md in docs

# 2. Commit all changes:
git add -A
git commit -m "Implement tier-based architecture with split Python packages

- App bundle: 136MB (down from 1.3GB) 
- Pro runtime: 350MB download (Docling + office libs)
- AI libraries: 750MB download (torch, mlx, transformers)
- UpmarketRuntimeHelper: PYTHONPATH includes downloaded packages
- BackgroundAssetsDownloadService: Handles Pro and Max tiers

Closes #XXX"

# 3. Tag version
git tag v2.0-tiers-launched
git push origin --all --tags

# 4. Submit to App Store
#    (Use normal App Store Connect process)
```

---

## Troubleshooting

### Package Not Downloading
- Check URL is publicly accessible
- Verify Content-Type is `application/gzip`
- Check file size matches (±5%)
- Look for BackgroundAssets logs in Console.app

### PYTHONPATH Missing Package
- Check file extracted correctly:
  ```bash
  ls ~/Library/Application\ Support/Upmarket/runtime/
  ```
- Check validation manifest exists:
  ```bash
  ls ~/Library/Application\ Support/Upmarket/runtime/python_runtime_pro/
  # Should have: python_runtime_ready file
  ```

### Docling/MLX Not Found
- Rebuild app with latest UpmarketRuntimeHelper
- Verify package extracted to correct location
- Check console logs for PYTHONPATH configuration

---

## Rollback Plan (If Needed)

If issues arise before release:

1. Revert `build_python_env.sh` to use `requirements.txt`:
   ```bash
   git checkout HEAD~ -- scripts/build_python_env.sh
   scripts/ci/ensure_python_runtime.sh  # Rebuilds 1.3GB bundle
   scripts/dev/run_app.sh --relaunch
   ```

2. Disable Background Assets in AppStore Connect
3. Release as hotfix

**Rollback time: ~5-10 minutes**

---

## What You Have Now

✅ **Build scripts** — Generate packages with one command
✅ **Infrastructure** — App knows how to download and load them
✅ **Documentation** — Clear what each tier provides
✅ **Testing harness** — DEBUG controls to test all tiers
✅ **Rollback plan** — Safe if something goes wrong

---

## Timeline

- **Now**: Run `scripts/build_python_packages.sh` (5 min)
- **Today**: Optional local testing (10 min)
- **Tomorrow**: Upload to CDN and configure App Store Connect (15 min)
- **Next week**: TestFlight beta testing (1 day)
- **Launch**: Submit to App Store

**Total effort: ~1 hour**

---

**Everything is ready. You can start generating packages immediately.**
