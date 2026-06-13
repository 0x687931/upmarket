# Tier Contract Deployment Checklist

**Use this before marking the PR ready or deploying to production.**

---

## Code Review (Before Commit)

- [x] `docs/TIER_CONTRACT.md` created and accurate
- [x] Requirements files split correctly (verified all deps accounted for)
- [x] ModelAsset enum updated with `aiLibraries`
- [x] AppTierGate handles all asset cases
- [x] PreferencesView displays accurate sizes and descriptions
- [x] Menu bar text updated to show download commitments
- [x] build_python_env.sh uses requirements-basic.txt
- [x] App builds successfully
- [x] No compilation errors

---

## Functional Testing (Before Release)

### Tier Override Testing (Use DEBUG controls in Preferences → About)

- [ ] **Basic Tier**:
  - [ ] Menu bar shows "Unlock Enhanced (350 MB)…"
  - [ ] Preferences → Conversion shows both models locked
  - [ ] Can convert using native APIs only
  - [ ] No downloads available

- [ ] **Pro Tier**:
  - [ ] Menu bar shows "Add AI (750 MB)…"
  - [ ] Preferences → Conversion shows Enhanced available (350 MB), AI locked
  - [ ] Can download Enhanced (if build packages exist)
  - [ ] Can convert with Docling layout analysis (after download)

- [ ] **Max Tier**:
  - [ ] Menu bar shows "All Features Unlocked"
  - [ ] Preferences → Conversion shows both available
  - [ ] Both models show accurate sizes
  - [ ] Can download Pro (350 MB) + AI (750 MB) + model weights (600 MB)

### UI Consistency

- [ ] All pricing removed from Preferences (only feature descriptions)
- [ ] All menu items use benefit-focused language, not tier names
- [ ] Download sizes shown consistently across UI
- [ ] "One-time download" language used everywhere

---

## Build System Validation

- [ ] `requirements-basic.txt` is used for bundled app Python ✅
- [ ] Bundled Python framework is ~136MB (was 1.3GB) ✅
- [ ] No torch/mlx/transformers in bundled framework ✅
- [ ] App still launches and functions ✅

### Size Verification

Run before each build:
```bash
du -sh /Users/am/GitHub/upmarket/build/DerivedData/Build/Products/Debug/Upmarket.app/Contents/Frameworks/Python.framework
```

**Expected**: ~130-150MB (Python + stdlib + ocrmac + utils)
**NOT acceptable**: > 500MB (would indicate ML frameworks bundled)

---

## Documentation Review

- [ ] `docs/TIER_CONTRACT.md` is current and matches code
- [ ] `docs/BUILD_TIER_SPLIT.md` documents the architecture
- [ ] `docs/TIER_CONTRACT_IMPLEMENTATION.md` tracks what's done
- [ ] All comments in code reference TIER_CONTRACT.md where relevant

---

## AppStore Preparation (For Release)

- [ ] Tier descriptions in App Store match TIER_CONTRACT.md
- [ ] Download size estimates updated:
  - Pro: ~350MB (or "varies, typically 300-400MB")
  - Max: +~750MB AI libraries (or "additional 700-800MB")
  - Model: ~600MB for Granite weights
- [ ] Release notes mention bundle size reduction
- [ ] Background Assets delivery configured for new packages (when ready)

---

## Post-Deploy Validation

After release, measure real-world metrics:

- [ ] App download size on App Store reduced
- [ ] Pro users report faster download (~350MB vs 1.3GB)
- [ ] No regressions in Basic tier (native conversion)
- [ ] Pro users can convert with Docling (once packages available)
- [ ] Max users can convert with AI (once packages available)
- [ ] No silent failures - tier violations error clearly

---

## Known Limitations (Document in Release Notes)

- [ ] Pro and Max download packages not yet built/available
  - *Timeline: Post-release, next build sprint*
- [ ] UpmarketRuntimeHelper PYTHONPATH not yet updated for split packages
  - *Needed when packages become available*
- [ ] Basic tier still requires Python (can't be further reduced without breaking native features)
- [ ] Model sizes may vary by compression (update if >10% variance)

---

## Questions Before Shipping?

Ask:
- [ ] Is 136MB acceptable for bundled app size?
- [ ] Are the benefit-focused UI labels clear to users?
- [ ] Should we add a "Why download?" explainer in Preferences?
- [ ] Is the tier contract documentation sufficient for future developers?

---

## Rollback Plan

If issues arise:
1. Revert `build_python_env.sh` line 71 back to `requirements.txt`
2. Rebuild Python framework (will be 1.3GB again)
3. Revert ModelAsset changes if needed
4. Tag as "revert-tier-contract-v1" and investigate

**Estimated rollback time**: 5 minutes

---

## Sign-Off

- [ ] Code review: ✅
- [ ] Functional testing: ✅ (or list blockers)
- [ ] Build validation: ✅
- [ ] Documentation: ✅
- [ ] Ready to commit: YES / NO

**Date**: ______
**By**: ______

---

**Remember**: The tier contract is the source of truth. If something doesn't match `docs/TIER_CONTRACT.md`, update the contract first, then propagate changes.
