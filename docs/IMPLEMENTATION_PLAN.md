# Upmarket — Implementation Plan

## Overview

Upmarket converts documents to Markdown using on-device AI. Fully offline on Apple Silicon after first model download. Sold on the Mac App Store with a 7-day free trial, Basic ($4.99) and Pro ($9.99) tiers.

---

## Current Status

| Component | Status |
|---|---|
| SwiftUI app shell | ✅ Done |
| BeeWare CPython 3.12 embedded | ✅ Done |
| Docling + PyTorch/MPS conversion | ✅ Done |
| MPS float32 patch | ✅ Done |
| PythonBridge service | ✅ Done |
| ConversionService | ✅ Done |
| StoreKit 2 (trial + Basic + Pro) | ✅ Done |
| ModelManager + download onboarding | ✅ Done |
| Basic drop zone + output UI | ✅ Done (prototype quality) |

---

## Phase 1 — App Store Technical Requirements
*Blocks submission. Must be done before anything else.*

### 1.1 Privacy & Signing
- [ ] Create `PrivacyInfo.xcprivacy` — declare network usage (model download), file access, no tracking
- [ ] Create `Upmarket.entitlements` — app sandbox, network client, user-selected files read-write
- [ ] Register bundle ID `com.upmarket.app` in App Store Connect
- [ ] Set Team ID in Xcode project settings
- [ ] Register app record in App Store Connect (name, category, age rating)

### 1.2 Bundle Size
- [ ] Run `strip_stdlib.sh` on bundled Python framework
- [ ] Audit `site-packages` — remove unused packages (test suites, dev tools)
- [ ] Measure final app bundle size (target: <200MB without models)
- [ ] Verify models download correctly to Application Support (not bundled)

### 1.3 In-App Purchase Setup
- [ ] Create IAP products in App Store Connect (`com.upmarket.app.basic`, `com.upmarket.app.pro`)
- [ ] Configure pricing tiers ($4.99, $9.99)
- [ ] Test purchase flow end-to-end with StoreKit sandbox

---

## Phase 2 — UI & Design
*App needs to look and feel like a premium product.*

### 2.1 App Icon
- [ ] Design app icon — concept: document + markdown arrow, clean and minimal
- [ ] Export all required sizes (16, 32, 64, 128, 256, 512, 1024px @1x and @2x)
- [ ] Add to `Assets.xcassets/AppIcon.appiconset`
- [ ] Design matches "upmarket" brand — premium, not cutesy

### 2.2 Visual Design System
- [ ] Choose accent colour (suggest: deep indigo or teal — professional, not generic blue)
- [ ] Set accent colour in `Assets.xcassets/AccentColor`
- [ ] Typography: system font (SF Pro) is fine — ensure consistent sizing hierarchy
- [ ] Light and dark mode tested and correct throughout

### 2.3 Drop Zone (Main Screen)
- [ ] Replace placeholder globe icon with document drop illustration or SF Symbol composition
- [ ] Animated drop zone border on hover (subtle pulse or glow)
- [ ] File type chips shown below drop zone (PDF · DOCX · PPTX · HTML · Images)
- [ ] Keyboard shortcut hint: Cmd+O shown subtly in corner
- [ ] App name / logo in toolbar

### 2.4 Conversion Progress Screen
- [ ] Indeterminate progress bar with animated shimmer
- [ ] Show filename being converted
- [ ] Show estimated time ("Usually takes 5–30 seconds")
- [ ] Cancel button (wire up Task cancellation)
- [ ] Smooth transition from drop zone → progress → result

### 2.5 Output / Result Screen
- [ ] Toolbar: filename, page count, format badge
- [ ] Markdown preview — monospaced, readable, syntax highlighted (basic)
- [ ] Toggle: Raw Markdown ↔ Rendered preview (use `AttributedString` or WebKit)
- [ ] Copy button (Cmd+C)
- [ ] Save As button (Cmd+S) — saves .md file
- [ ] Share button — macOS share sheet
- [ ] Convert Another button (Cmd+N)
- [ ] Word count / character count shown in footer

### 2.6 Paywall / Upgrade Screen
- [ ] Polish plan comparison cards (currently functional, needs visual refinement)
- [ ] Add "Most Popular" badge to Pro
- [ ] Testimonial or sample output showing Pro vs Basic quality difference
- [ ] Animated checkmarks on feature list
- [ ] Smooth sheet presentation

### 2.7 Model Download Screen
- [ ] Show estimated download time based on connection (if detectable)
- [ ] Animated download progress (not just a bar — show model name animating in)
- [ ] Success state: checkmark animation when complete
- [ ] "Why do I need this?" expandable explanation
- [ ] Skip option for Basic (download layout models only, defer Pro models)

### 2.8 Preferences Window
- [ ] Cmd+, opens preferences
- [ ] General tab: default save location, output format options
- [ ] Models tab: show downloaded models, storage used, delete individual models
- [ ] Account tab: show current plan, upgrade button, restore purchases
- [ ] About tab: version, open source licenses, privacy policy link

### 2.9 Menu Bar
- [ ] File → Open (Cmd+O)
- [ ] File → Save (Cmd+S)
- [ ] File → Convert Another (Cmd+N)
- [ ] Edit → Copy Markdown (Cmd+C)
- [ ] Upmarket → Preferences (Cmd+,)
- [ ] Upmarket → Check for Updates
- [ ] Help → Report an Issue (opens mailto or feedback form)

### 2.10 Onboarding (First Launch)
- [ ] Welcome screen before model download — explains what Upmarket does
- [ ] 3-step flow: Welcome → Download Models → Ready
- [ ] "What Upmarket can do" with 3 example conversions (PDF → clean markdown preview)
- [ ] Only shown once (UserDefaults flag)

---

## Phase 3 — Core Features
*Required for a complete paid product.*

### 3.1 Conversion Quality
- [ ] Test PDF conversion (digital) — verify output quality
- [ ] Test PDF conversion (scanned) — verify OCR works
- [ ] Test DOCX conversion — headings, tables, lists
- [ ] Test PPTX conversion — slide titles, bullet points
- [ ] Test HTML conversion
- [ ] Test image conversion (PNG/JPG with text)
- [ ] Error handling: unsupported file shows friendly message
- [ ] Large file handling: test 100+ page PDF, add timeout (5 min)

### 3.2 Pro Conversion (SmolDocling)
- [ ] Wire SmolDocling option into converter.py
- [ ] UI toggle: "Use AI (Pro)" in drop zone or conversion options
- [ ] Show Pro badge on result when SmolDocling was used
- [ ] Download Pro models prompt if Pro user hasn't downloaded yet

### 3.3 Conversion Options
- [ ] OCR toggle (on by default)
- [ ] Table detection toggle (on by default)
- [ ] Output format: Markdown / JSON / plain text

### 3.4 Batch Conversion (v1.1)
- [ ] Multi-file selection in Open panel
- [ ] Queue UI showing files and status
- [ ] Zip and save all results
- [ ] Progress: "Converting 3 of 7 files"

---

## Phase 4 — Legal & Compliance

### 4.1 Privacy Policy
- [ ] Write privacy policy — emphasise offline, no data collection, no tracking
- [ ] Host on GitHub Pages or simple static site
- [ ] Link in App Store listing
- [ ] Link in app (Preferences → About → Privacy Policy)

### 4.2 Terms of Service
- [ ] Write basic EULA / Terms
- [ ] Host alongside privacy policy
- [ ] Link in App Store listing

### 4.3 Open Source Attribution
- [ ] Generate full license list from pip (`pip-licenses` package)
- [ ] Create `Licenses` view in Preferences → About
- [ ] Key attributions: Docling (MIT, IBM), PyTorch (BSD), BeeWare (MIT)

---

## Phase 5 — App Store Listing

### 5.1 Copy
- [ ] App name: Upmarket
- [ ] Subtitle (30 chars): "Document to Markdown Converter"
- [ ] Description (4000 chars max): lead with offline + privacy, explain tiers
- [ ] Keywords (100 chars): pdf markdown, document converter, offline ai, docx markdown
- [ ] Support URL
- [ ] Marketing URL (landing page)

### 5.2 Screenshots (required)
- [ ] Screenshot 1: Drop zone — clean, empty state with a document hovering
- [ ] Screenshot 2: Converting — progress screen with a real document
- [ ] Screenshot 3: Output — Markdown result from a beautiful PDF
- [ ] Screenshot 4: Paywall / pricing — clean tier comparison
- [ ] Screenshot 5: Preferences — model management screen
- [ ] All at 1440×900 (MacBook Pro 13") or 2560×1600 (MacBook Pro 16")

### 5.3 App Preview Video (optional but recommended)
- [ ] 15–30 second screen recording
- [ ] Show: drag PDF → converting → clean Markdown output
- [ ] No voiceover needed — let the product speak

### 5.4 Landing Page (optional for launch)
- [ ] Simple one-pager: hero, features, pricing, App Store badge
- [ ] Domain: upmarket.app (check availability) or upmarketapp.com
- [ ] Host on GitHub Pages or Vercel (free)

---

## Phase 6 — Stability & Quality

### 6.1 Error Handling
- [ ] Replace raw Python tracebacks with friendly error messages
- [ ] Categorise errors: unsupported format, file too large, conversion failed, no models
- [ ] Add "Copy Error Details" for power users to share bug reports
- [ ] Offline detection: warn if models not downloaded and no internet

### 6.2 Crash Reporting
- [ ] Integrate Sentry (free tier) or Apple's built-in crash reporting
- [ ] Capture Python exceptions with context
- [ ] Add "Report Issue" menu item

### 6.3 Performance
- [ ] Conversion timeout: 5 minutes max, show friendly error
- [ ] Memory monitor: warn if >2GB during conversion
- [ ] Test on M1, M2, M3 (Apple Silicon)
- [ ] Test on Intel Mac — verify CPU fallback works

### 6.4 Accessibility
- [ ] VoiceOver labels on all interactive elements
- [ ] Keyboard navigation throughout
- [ ] Minimum contrast ratio 4.5:1 for all text

### 6.5 Testing
- [ ] Unit tests: ConversionService, StoreManager, ModelManager
- [ ] UI tests: drop zone, conversion flow, paywall
- [ ] Test on macOS 13.3, 14.x, 15.x, 26.x

---

## Phase 7 — Launch Prep

- [ ] TestFlight beta (internal) — test full flow end to end
- [ ] TestFlight beta (external) — 5–10 external testers
- [ ] Address all beta feedback
- [ ] Final App Store submission
- [ ] Prepare launch announcement (Twitter/X, Reddit r/macapps, ProductHunt)
- [ ] ProductHunt submission scheduled

---

## Milestone Summary

| Milestone | What's included | Est. effort |
|---|---|---|
| **M1 — Submittable** | Phase 1 + basic Phase 2 UI + Phase 4 legal | 2 weeks |
| **M2 — Polished v1.0** | Full Phase 2 UI + Phase 3 features + Phase 5 listing | 2 weeks |
| **M3 — Launch** | Phase 6 stability + Phase 7 launch prep | 1 week |
| **Total** | | **~5 weeks** |

---

## Open Questions

- [ ] Domain: upmarket.app vs upmarketapp.com — check availability
- [ ] Landing page: build before or after App Store submission?
- [ ] Intel Mac: support or Apple Silicon only for v1?
- [ ] Batch conversion: v1.0 or v1.1?
- [ ] Crash reporting: Sentry or Apple-native only?
