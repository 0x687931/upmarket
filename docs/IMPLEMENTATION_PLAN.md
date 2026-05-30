# Upmarket — Implementation Plan

## Overview

Upmarket converts documents to Markdown using on-device AI. Fully offline on Apple Silicon after first model download. Sold on the Mac App Store with 3 free conversions, then Basic ($4.99), 5-doc pack ($0.99), and Pro + AI ($9.99).

---

## Architecture

```
SwiftUI (animation-first UI, 400px portrait → 640px output)
    ↓
Tiered Python pipeline:
  Fast path  — PyMuPDF4LLM, bundled, zero download
  Enhanced   — Layout models, 172MB on demand
  Upmarket AI — SmolDocling MLX, 500MB on demand, Pro only
    ↓
Models cached in ~/Library/Application Support/Upmarket/models/
    ↓
100% offline after first model download
```

---

## What's Done ✅

### Core
- [x] SwiftUI app shell with MenuBarExtra (liquid glass popover)
- [x] BeeWare CPython 3.12 embedded and running (Python 3.12.10)
- [x] PythonBridge service — PYTHONHOME/PYTHONPATH/HF_HUB_CACHE configured
- [x] Tiered conversion pipeline (fast/enhanced/AI)
- [x] PyMuPDF4LLM bundled — zero download for clean digital docs
- [x] Docling + PyTorch/MPS for Enhanced pipeline (on-demand)
- [x] MPS float32 patch for Apple Silicon compatibility
- [x] Document complexity analyser — detects scanned, complex, multi-column
- [x] Language detection — Unicode block analysis, warns on low-quality langs
- [x] Sandbox file access — copy to temp dir before Python conversion
- [x] Password-protected PDF detection and prompt

### Monetisation
- [x] StoreKit 2 — trial (3 free docs), Basic $4.99, Pro $9.99, 5-doc pack $0.99
- [x] Smart upgrade nudge — escalates after 1/2/3+ packs purchased
- [x] Paywall — Pro as hero, Basic secondary, pack as last resort
- [x] AI credit / pack consumption tracking in UserDefaults
- [x] Trial banner showing remaining free conversions

### Models & Download
- [x] ModelManager — check, download, offline mode, delete/offload
- [x] ModelDownloadView — shows model sizes, progress, Pro-gated AI models
- [x] No download on first launch — app works immediately with fast path
- [x] Enhanced models prompted only when complexity detected
- [x] Model deletion / offloading support (user and OS)

### Device & Feature Intelligence
- [x] DeviceCapability — Apple Silicon detection, Tahoe detection
- [x] FeatureFlags — remote JSON config for AI language gating
- [x] Language-aware AI gating — CJK/Arabic/Hebrew excluded from AI
- [x] Language quality warning shown for low-support languages
- [x] Intel Mac — AI hidden, clear explanation shown

### UI
- [x] Animation-first drop zone — breathing # symbol, glow, ripple on drop
- [x] AppPhase state machine — idle/analysing/converting/result/error
- [x] Progress ring around # during conversion
- [x] Spring transitions between phases
- [x] Format chips (PDF · DOCX · PPTX · XLSX · HTML)
- [x] Icon-only output toolbar (copy/save/new with tooltips)
- [x] Word count in output
- [x] Cmd+O, Cmd+S, Cmd+N, Cmd+Shift+C keyboard shortcuts
- [x] AI suggestion sheet when complexity detected
- [x] Language warning banner (dismissible, slides from bottom)
- [x] Password prompt sheet
- [x] Accent colour set (#4f46e5 indigo)
- [x] Menu bar with liquid glass popover
- [x] Window resizes: 400px portrait → 640px for output

### App Store Technical
- [x] PrivacyInfo.xcprivacy — Privacy Manifest
- [x] Upmarket.entitlements — App Sandbox, network client, user files
- [x] Bundle stripped to 102MB (was 1.3GB — removed PyTorch/Docling)
- [x] Apple compresses to ~47MB download automatically

### Tooling
- [x] update_dependencies.sh — one-command dependency update + sync
- [x] patch_mps.sh — MPS float32 patch after transformers updates
- [x] strip_stdlib.sh — reduces Python stdlib size
- [x] RELEASING.md — release process documentation
- [x] docs/public/flags.json — remote feature flag file

---

## Outstanding — P0 (Blocks App Store Submission)

### Must be done by you (requires Apple ID / Xcode GUI)
- [ ] Wire `Upmarket.entitlements` in Xcode Build Settings → Code Signing Entitlements
- [ ] Register bundle ID `com.upmarket.app` in App Store Connect
- [ ] Set Team ID in Xcode project settings (General → Signing)
- [ ] Register app record in App Store Connect (name, category, age rating)
- [ ] Create IAP products in App Store Connect:
  - `com.upmarket.app.basic` — $4.99
  - `com.upmarket.app.pro` — $9.99
  - `com.upmarket.app.doc_pack` — $0.99
- [ ] Test purchase flow with StoreKit sandbox

### App Icon (required — App Store rejects without it)
- [ ] Design icon — `#` symbol, indigo on white, Tahoe style (see prompt in docs)
- [ ] Export all sizes (16, 32, 64, 128, 256, 512, 1024px @1x and @2x)
- [ ] Add to `Assets.xcassets/AppIcon.appiconset`

### GitHub Pages (for feature flags)
- [ ] Enable GitHub Pages on `0x687931/upmarket` repo → serve from `/docs/public`
- [ ] Verify `https://0x687931.github.io/upmarket/flags.json` is accessible

---

## Outstanding — P1 (Required for Paid Product)

### Preferences Window
- [ ] Cmd+, opens preferences
- [ ] Models tab — show downloaded models, storage used, delete button
- [ ] Account tab — current plan, upgrade, restore purchases
- [ ] About tab — version, open source licenses, privacy policy link

### Legal
- [ ] Write privacy policy (1 page, host on GitHub Pages)
- [ ] Write EULA / Terms (1 page, host alongside)
- [ ] Open source attribution screen (generate from pip-licenses)
- [ ] Link both in App Store listing and in-app About tab

### App Store Listing
- [ ] App description (4000 chars) — lead with offline + privacy
- [ ] Subtitle (30 chars): "Document to Markdown, On-Device"
- [ ] Keywords (100 chars): pdf markdown, document converter, offline ai
- [ ] 5 screenshots at 1440×900 or 2560×1600
- [ ] Support URL
- [ ] Privacy policy URL

### Quality
- [ ] Friendly error messages — categorise: unsupported format, too large, failed
- [ ] Conversion timeout — 5 min max, show clear error
- [ ] Dark mode — test and fix any contrast issues
- [ ] Test on macOS 13.3, 14.x, 15.x, 26.x

---

## Outstanding — P2 (Polish / Post-Launch)

### UI Polish
- [ ] Rendered Markdown preview toggle (raw ↔ rendered)
- [ ] Share button (macOS share sheet)
- [ ] Onboarding flow — 3-step welcome for first launch
- [ ] Dark mode drop zone and output polish
- [ ] Animated checkmarks in paywall feature list

### Features
- [ ] Batch conversion (multiple files, queue UI)
- [ ] Conversion history (recent files list)
- [ ] Output format options (Markdown / plain text)
- [ ] OCR toggle in drop zone

### Localisation (#10)
- [ ] Localizable.strings — English baseline
- [ ] German, French, Japanese (v1.1)
- [ ] Spanish, Italian, Portuguese, Korean, Chinese (v1.2)
- [ ] App Store listing translated per locale

### Stability
- [ ] Unit tests — ConversionService, StoreManager, ModelManager
- [ ] UI tests — drop zone, conversion flow, paywall
- [ ] Crash reporting (Apple-native or Sentry)
- [ ] Memory monitor — warn if >2GB during conversion

### Launch
- [ ] TestFlight internal beta
- [ ] TestFlight external beta (5-10 testers)
- [ ] ProductHunt submission
- [ ] Reddit r/macapps launch post

---

## Milestone Summary

| Milestone | Scope | Est. |
|---|---|---|
| **M1 — Submittable** | P0 items above + app icon | 1 week |
| **M2 — v1.0 Launch** | P1 items + screenshots + legal | 1 week |
| **M3 — Post-launch** | P2 polish based on user feedback | ongoing |

---

## Open Questions
- [ ] Domain: upmarket.app vs upmarketapp.com — check availability
- [ ] Landing page: before or after App Store submission?
- [ ] Intel Mac: document as "Apple Silicon recommended" in listing?
- [ ] Batch conversion: v1.0 or v1.1?
