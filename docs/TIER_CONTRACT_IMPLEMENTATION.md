# Tier Contract Implementation Status

**See `docs/TIER_CONTRACT.md` for the contract itself. This document tracks implementation.**

---

## ✅ Completed

### Documentation
- [x] Created `docs/TIER_CONTRACT.md` — single source of truth for tier definitions
- [x] Split requirements into `requirements-pro.txt` and `requirements-ai.txt`
- [x] Updated CLAUDE.md references to point to TIER_CONTRACT.md

### Code Updates
- [x] Updated `ModelAsset` enum with new `aiLibraries` asset
- [x] Updated asset sizes to match contract:
  - pythonRuntime: 1300MB → 350MB
  - aiLibraries: NEW, 750MB
  - upmarketAI: 618MB → 600MB
  - layout: 300MB → 20MB
- [x] Updated `ConversionCapability.requiredAssets` to include aiLibraries for AI tier
- [x] Updated `AppTierGate` to handle new asset (exhaustive switch)
- [x] Updated PreferencesView stateDescription with new sizes
- [x] Updated menu bar text to show new download commitments
- [x] Updated display names: "Enhanced Conversions" instead of "Upmarket Runtime"

### Testing Infrastructure
- [x] Added DEBUG tier override controls in Preferences → About tab
- [x] App now builds with updated tier contract

---

## ⚠️ In Progress / Needs Build Changes

### Build System (Next Phase)
- [ ] Split Python runtime build into two packages:
  - `python_runtime_pro` (~350MB) — Python + Docling + office libs
  - `ai_libraries` (~750MB) — torch, mlx, transformers, onnxruntime
- [ ] Update `scripts/ci/gate.sh` to build separate packages
- [ ] Update `scripts/build_python_env.sh` to use requirements-pro.txt vs requirements-ai.txt
- [ ] Verify App Store delivery model handles separate assets

### Runtime Behavior
- [ ] ModelManager needs to download aiLibraries before upmarketAI for Max users
- [ ] Download sequencing: pythonRuntime → aiLibraries → upmarketAI
- [ ] Validate that missing aiLibraries prevents AI pipeline (AppTierGate already enforces)

### Verification
- [ ] Measure actual installed sizes post-build
  - pythonRuntime-pro should be ~350MB (currently 1.3GB includes ML)
  - aiLibraries should be ~750MB
  - Sum should ≈ 1.1GB before compression vs 1.3GB today
- [ ] Update AppTier.swift sizeMB values if actual differs from contract
- [ ] Run tests to verify tier gating enforcement

---

## 🔍 What Changed (User Perspective)

### Pro Tier (before → after)
- **Before**: Download 1.3GB (includes Python + Docling + torch + mlx)
- **After**: Download 350MB (Python + Docling only, no ML frameworks)

### Max Tier (before → after)
- **Before**: Same 1.3GB runtime, plus 600MB model = 1.9GB total
- **After**: 350MB runtime + 750MB AI libraries + 600MB model = 1.7GB total

### User Messaging
- **Menu bar**: Now shows explicit download size commitments
  - "Unlock Enhanced (350 MB)…"
  - "Add AI (750 MB)…"
- **Preferences**: Shows benefit-focused names and actual sizes
  - "Enhanced Conversions · 350 MB (one-time download)"
  - "AI for Complex Documents · 1.35 GB (one-time download)" ← includes 750MB libraries + 600MB model

---

## 📋 Remaining Work

1. **Build infrastructure** — Separate requirements files exist, but build script needs updating
2. **Size validation** — Once Pro runtime is rebuilt without ML, measure and update sizeMB if needed
3. **Download sequencing** — Ensure aiLibraries downloads before upmarketAI for Max users
4. **CI/CD gates** — Update gate.sh to validate new tier contract
5. **Documentation** — Update release notes and user-facing docs

---

## Validation Checklist (Before Release)

- [ ] `requirements-pro.txt` builds to ~350MB (no torch/mlx/transformers)
- [ ] `requirements-ai.txt` builds to ~750MB
- [ ] App bundle does NOT include ML frameworks at all
- [ ] ModelAsset sizes match actual measured sizes
- [ ] Tests pass: `gate.sh quick` and `gate.sh minor`
- [ ] Manual QA: Test all three tier levels with tier override
- [ ] Release notes mention "Pro: 350MB → efficient layout analysis"
