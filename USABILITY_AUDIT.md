# Upmarket Usability Audit

## CRITICAL ISSUES (Block usage)

### 1. Preferences → File Types buttons unresponsive ✓ FIXED
**Location:** PreferencesView.swift, Automation tab, File Types section
**Issue:** Was using SegButtonAction (action-based) instead of direct buttons
**Impact:** Users couldn't change watched file type filters
**Fix:** Converted to direct Button pattern with inline state calculation

### 2. Missing affordance: AI Models "Manage Models…" discovery ✓ FIXED
**Location:** PreferencesView.swift, Conversion tab
**Issue:** Was small and followed the model list - users may not see it
**Better pattern:** Moved to prominent header action at top of section
**Impact:** Users can now easily discover the model download interface

### 3. Preferences window size mismatch  
**Location:** PreferencesView body .frame(width: 600)
**Issue:** Window is 600pt but some content may be cut off on smaller displays
**Example:** The Shelf Widget Left/Right buttons take full width
**Fix:** Consider dynamic sizing or ensure min window size is enforced

### 4. Missing validation feedback on password sheet ✓ FIXED
**Location:** ContentView.swift, passwordSheet
**Issue:** SecureField didn't show error if password is wrong
**Impact:** Users got silent failure, unclear why conversion doesn't proceed
**Fix:** Added error message display + auto-focus on sheet appear with @FocusState

---

## HIGH PRIORITY (Degrade UX)

### 5. Drop zone doesn't show clear feedback while dropping
**Location:** ContentView.swift, dropZoneView
**Issue:** isTargeted shows visual change but no text feedback changes
**Expected:** Text should change to "Release to convert" 
**Status:** Actually present! (line 106) ✓

### 6. File row action buttons appear only on hover ✓ FIXED
**Location:** ContentView.swift, FileRowView
**Issue:** Copy/Reveal/Delete/Retry buttons hide until hover - hidden affordance
**Impact:** New users didn't know actions exist
**Fix:** Primary action always visible (Copy/Retry/Stop), secondary actions on hover

### 7. Status banner disappears for Pro/Max users ✓ FIXED
**Location:** ContentView.swift, statusBanner
**Issue:** Only showed for Basic tier users
**Impact:** No clear visual indication of current tier
**Fix:** Now shows plan tier for all users (Pro shows "Enhanced conversion", Max shows "AI-powered")

### 8. Model status row doesn't show download progress percentage ✓ FIXED
**Location:** PreferencesView.swift, ModelStatusRow
**Issue:** Was showing "Downloading…" but not actual progress (45%, etc.)
**Impact:** User couldn't tell if download was stalled
**Fix:** Now displays "Downloading X%" using modelManager.downloadProgress

### 9. "Manage Models…" button doesn't match button styling
**Location:** PreferencesView.swift, AI Models section
**Issue:** Uses .buttonStyle(.bordered) inconsistently with other section buttons
**Better:** Use consistent SegButton or action button pattern

### 10. Menu bar dropdown missing keyboard shortcuts
**Location:** MenuBarDropdown.swift
**Issue:** Shows "⌘," for Preferences but no actual keyboard shortcut wired
**Impact:** Keyboard shortcuts displayed but don't work
**Status check:** Need to verify if shortcuts are actually registered

---

## MEDIUM PRIORITY (Confusing)

### 11. Shelf widget selection unclear ✓ FIXED
**Location:** PreferencesView.swift, Shelf Widget section
**Issue:** "Auto-hide when inactive" toggle didn't clarify what happens
**Better description:** Now labeled "Hide shelf when idle" with subtitle explaining 10-second behavior

### 12. Save Location picker styling
**Location:** PreferencesView.swift, Save Location section
**Issue:** Uses .menu picker style - looks like a dropdown but is actually clicking to open
**Better:** Could use segmented buttons or clearer picker presentation

### 13. Watched Folders empty state unclear ✓ FIXED
**Location:** PreferencesView.swift, Automation tab
**Issue:** Empty state showed only "No folders watched yet" with no guidance
**Better:** Now includes subtitle "Click \"Add Folder…\" to start watching folders"

### 14. About tab layout inconsistent ✓ FIXED
**Location:** PreferencesView.swift, About tab
**Issue:** App icon was 40×40 while section icons use 28×28 — visual inconsistency
**Impact:** Visual hierarchy felt off
**Fix:** Standardized app icon to 32×32 with cornerRadius 8 for consistency

### 15. Plan card uses index-based colors ✓ FIXED
**Location:** PreferencesView.swift, PlanCard
**Issue:** Was using array index lookup `[...][entitlement.rawValue]` for 6 properties
**Risk:** If AppTier enum order changes, colors would break silently
**Fix:** Converted all 6 properties (planName, planDetail, iconName, iconColor, borderColor, bgColor) to switch statements

### 16. File row truncation unclear
**Location:** ContentView.swift, FileRowView
**Issue:** Filename uses .truncationMode(.middle) - "verylong...filename.pdf"
**Better:** .tail would be more intuitive for filenames ("very long file...pdf")

---

## LOW PRIORITY (Polish)

### 17. No visual indication of conversion capability by tier
**Location:** ContentView.swift
**Issue:** UI doesn't show what "Enhanced" vs "AI" conversion means
**Better:** Tooltip on drop zone or status banner explaining current capabilities

### 18. Report a Problem doesn't mention what data is sent
**Location:** ReportProblemView.swift
**Issue:** "Logs don't contain file contents" is reassuring but vague
**Better:** "We'll send: error logs, conversion settings, system info (not your files)"

### 19. ModelStatusRow left icon redundant
**Location:** PreferencesView.swift, ModelStatusRow
**Issue:** Left icon (checkmark, lock, cloud) AND right button both show status
**Better:** One or the other, not both
**Suggest:** Keep right button, remove left icon circle, just show icon inline with status text

### 20. Shelf widget corners don't match main window
**Location:** ShelfView.swift vs ContentView.swift
**Issue:** Both use RoundedRectangle(cornerRadius: 12) but main window uses different radius
**Impact:** Visual inconsistency
**Check:** Verify both are using AppTheme.Radius constants

### 21. No loading state for "Checking models…"
**Location:** ModelDownloadView.swift
**Issue:** When checking installed models, could show spinner or progress
**Better:** Visual feedback that something is happening

### 22. Password prompt doesn't focus on input
**Location:** ContentView.swift, passwordSheet
**Issue:** User sees sheet but cursor isn't in password field
**Fix:** Add .onAppear { /* focus */ } or use @FocusState

---

## ACCESSIBILITY ISSUES

### 23. Color-only status indicators
**Location:** FileRowView - green checkmark, red X
**Issue:** Relying on color alone for status
**Better:** Add icon + text label to each status

### 24. Missing accessibility labels
**Location:** Multiple places
**Issue:** Drop zone, file rows, action buttons lack .accessibilityLabel
**Fix:** Add descriptive labels to all interactive elements

### 25. Contrast on secondary text
**Location:** Throughout
**Issue:** `.secondary` color may not meet WCAG AA standards
**Check:** Verify color contrast ratios

---

## QUICK WINS (Easy fixes, high impact)

- [x] Fix File Types buttons (use direct Button pattern) — DONE
- [x] Add percentage to "Downloading…" status — DONE (shows "Downloading X%")
- [x] Move "Manage Models…" button to section header — DONE (prominent header action)
- [x] Fix password field focus — DONE (auto-focuses on sheet appear)
- [x] Clarify "Auto-hide" toggle description — DONE (now "Hide shelf when idle" with subtitle)
- [x] Standardize icon sizes in About tab — DONE (32×32 with radius 8)
- [ ] Add accessibility labels to all buttons
- [x] Use switch statement in PlanCard instead of array indexing — DONE (all 6 properties now use switch)

---

## VISUAL CONSISTENCY AUDIT

| Component | Issue | Status |
|-----------|-------|--------|
| SegButton variant | Action-based vs Binding-based mix | ⚠️ Needs consolidation |
| Buttons | .plain, .bordered, .borderedProminent mix | ⚠️ Inconsistent |
| Icon sizes | 11px, 13px, 16pt, 20pt scattered | ⚠️ Needs standardization |
| Colors | AppTheme constants used inconsistently | ⚠️ Audit needed |
| Padding | 8, 10, 12, 14, 28 different values | ⚠️ Design system needed |
| Dividers | .stroke vs .fill, colors vary | ⚠️ Normalize |

---

## RECOMMENDATIONS

1. **Create a Button style guide** - consolidate .plain, .bordered, .borderedProminent patterns
2. **Standardize spacing** - use fewer padding values (8, 12, 16, 20)
3. **Fix state-aware components** - ModelStatusRow pattern should be reused
4. **Add confirmation dialogs** - "Delete conversion?" before destructive actions
5. **Improve empty states** - All empty views need clear CTAs
6. **Add help tooltips** - Hover explanations for non-obvious features
