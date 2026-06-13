# Accessibility Testing Guide for Upmarket

Complete manual testing guide using Apple's official accessibility tools and WCAG 2.1 standards.

## Part 1: Using Apple Accessibility Inspector

Apple provides **Accessibility Inspector** — a free tool to audit accessibility of macOS apps.

### How to Open Accessibility Inspector

```bash
# Open from Terminal
open /Applications/Utilities/Accessibility\ Inspector.app

# Or press ⌘-F5 in most apps (if enabled in System Settings)
```

### Step 1: Identify Inaccessible Elements

1. Launch Upmarket app
2. Open Accessibility Inspector
3. Click the target icon (crosshair) to inspect elements
4. Hover over each UI element and click to inspect
5. Check the Inspector panel for:
   - ✅ **Description**: Should not be empty
   - ✅ **Title**: Should not be empty or generic ("Button")
   - ✅ **Role**: Should be correct (Button, Checkbox, TextField, etc.)
   - ✅ **Help**: Should explain complex elements

### Step 2: Check Each Category

**Buttons:**
- [ ] "Choose Document" button has description
- [ ] "Copy" button has description
- [ ] "Save" button has description
- [ ] "Open in Finder" button has description
- [ ] All menu bar buttons have descriptions
- [ ] All shelf control buttons have descriptions

**Toggles/Checkboxes:**
- [ ] "Show Dock Icon" has description
- [ ] "Show Menu Bar Icon" has description
- [ ] "Hide shelf when idle" has description
- [ ] "Include system logs" has description

**Text Fields:**
- [ ] Message field has label
- [ ] Save location picker has label
- [ ] Report category has label

**Status Elements:**
- [ ] Status text is readable (not image-only)
- [ ] Progress bar has accessible name
- [ ] Job count badge is announced

**Icons:**
- [ ] Menubar icon has description
- [ ] Dock icon has description
- [ ] Status icons have descriptions

### Step 3: Check Element Roles

For each element, verify:
- [ ] **Button** elements have role=Button
- [ ] **Toggles** have role=Checkbox
- [ ] **Text inputs** have role=TextField
- [ ] **Lists** have role=List
- [ ] **Menu items** have proper role

---

## Part 2: VoiceOver Testing

VoiceOver is Apple's built-in screen reader. Test with actual screen reader.

### Enable VoiceOver

```bash
# Toggle VoiceOver with: ⌘-F5
# Or: System Settings > Accessibility > VoiceOver > Enable
```

### Test VoiceOver with Upmarket

#### Main Window
- [ ] Launch app - VoiceOver announces "Upmarket Window"
- [ ] Tab to first element - announces "Drop zone" with hint
- [ ] Tab through all elements - each announced with role + description
- [ ] Try drag-drop - VoiceOver announces it worked

#### Menubar
- [ ] Click menu - announces menu title
- [ ] Tab through items - announces each item
- [ ] Each item announces keyboard shortcut (⌘O, ⌘,, ⌘Q)

#### Dock
- [ ] VoiceOver announces "Upmarket, Dock icon"
- [ ] Click dock icon - announces window activation
- [ ] Badge announces job count: "Upmarket, 5 items"

#### Preferences Window
- [ ] Open (⌘,) - announces "Preferences Window"
- [ ] Tab to first control - announces "General tab, selected"
- [ ] Tab to next tab - announces "Conversion tab"
- [ ] Each toggle announces: "Show Dock Icon, checkbox, checked"

#### Report Problem Dialog
- [ ] Opens - announces "Report a Problem"
- [ ] Tab to categories - announces each option
- [ ] Select category - announces selection
- [ ] Message field - announces "Describe the problem, text field"
- [ ] Send button - announces "Send Report, button"

#### Shelf Widget
- [ ] Mini icon - announces "Upmarket shelf, 0 items"
- [ ] When jobs exist - announces "Upmarket shelf, 5 items"
- [ ] Click to expand - announces "Conversion queue"
- [ ] Each job - announces filename, progress, status

### VoiceOver Checklist

- [ ] All interactive elements announce their role (Button, Checkbox, etc.)
- [ ] All elements announce their name/label
- [ ] Status changes are announced
- [ ] Errors are announced
- [ ] Progress is announced
- [ ] Navigation is logical (no jumps)

---

## Part 3: Keyboard Navigation Testing

### Test Without Mouse - Use Keyboard Only

**Requirement:** Complete all major tasks using ONLY keyboard.

#### Task 1: Convert a Document
- [ ] Press ⌘O → file picker opens
- [ ] Tab to file → Enter selects
- [ ] Conversion starts
- [ ] ✓ Task complete without mouse

#### Task 2: Open Preferences
- [ ] Press ⌘, → Preferences opens
- [ ] Tab through tabs: General → Conversion → Models → About
- [ ] Toggle a setting with Space
- [ ] Press Escape → closes
- [ ] ✓ Task complete without mouse

#### Task 3: Report a Problem
- [ ] Tab to Preferences button → Enter
- [ ] Tab to "Report a Problem" → Enter
- [ ] Tab to categories → arrow keys select
- [ ] Tab to message field → type message
- [ ] Tab to Send → Enter
- [ ] ✓ Task complete without mouse

#### Task 4: Manage Shelf
- [ ] Tab to shelf icon → Enter (expand)
- [ ] Tab through control buttons (Close, Add, Toggle)
- [ ] Each button activates with Enter
- [ ] ✓ Task complete without mouse

### Keyboard Navigation Checklist

- [ ] Tab moves forward through all elements
- [ ] Shift+Tab moves backward
- [ ] Tab order is logical (top-to-bottom, left-to-right)
- [ ] Focus is always visible
- [ ] No elements are keyboard-trapped (except modals)
- [ ] All buttons activate with Enter or Space
- [ ] All toggles toggle with Space
- [ ] All pickers navigate with arrow keys
- [ ] Escape closes dialogs
- [ ] No keyboard shortcuts are hidden or undocumented

---

## Part 4: Color & Contrast Testing

### Measure Contrast Ratios

Use **Color Contrast Analyzer** or similar tool:
- Download: https://www.tpgi.com/color-contrast-checker/

### Contrast Requirements (WCAG 2.1)

| Element | Ratio | Standard |
|---------|-------|----------|
| Normal text | 4.5:1 | Level AA |
| Large text (18pt+) | 3:1 | Level AA |
| UI components | 3:1 | Level AA |
| Focus indicator | 3:1 | Level AA |

### Elements to Check

- [ ] Black text on white: 21:1 ✓
- [ ] Primary text on background: ≥4.5:1
- [ ] Secondary text on background: ≥4.5:1 (or is gray acceptable?)
- [ ] Status text (green/red) + icon: ≥3:1
- [ ] Focus indicator on all elements: ≥3:1
- [ ] Menu item hover: ≥3:1
- [ ] Button text: ≥4.5:1

### Issue #25 from Usability Audit

**Secondary text contrast** - Verify:
- [ ] Secondary text meets 4.5:1 ratio
- [ ] If not, darken `.secondary` color
- [ ] Test with actual color values, not assumptions

---

## Part 5: Focus Indicator Testing

### Visual Focus Checklist

When you Tab to an element, you should see:

- [ ] Outline or border appears
- [ ] Outline is at least 1px wide, preferably 2px
- [ ] Color contrasts with background (≥3:1)
- [ ] Not just a 1px hairline (too hard to see)
- [ ] Not just color change (colorblind users)
- [ ] Follows element boundaries

### Test Each Element Type

**Buttons:**
- [ ] Clear focus outline or background color change
- [ ] Visible at 100% zoom and 200% zoom
- [ ] Visible in light and dark mode

**Toggles:**
- [ ] Focus ring appears around entire control
- [ ] Not just the checkbox

**Text Fields:**
- [ ] Border or outline changes color
- [ ] Outline is 2px or thicker

**Menu Items:**
- [ ] Background highlight shows focus
- [ ] Text remains readable

---

## Part 6: Dynamic Content Testing

### Test Content Updates

**During Conversion:**
- [ ] Progress bar updates announced
- [ ] Status changes announced (e.g., "Completed")
- [ ] Final result announced

**Shelf Updates:**
- [ ] New jobs added - badge count updated and announced
- [ ] Job removed - count updated
- [ ] Job completion - announced to screen reader

**Error Messages:**
- [ ] Error appears - announced immediately
- [ ] Error text is visible (not hidden)
- [ ] Clear explanation (not just "Error")

---

## Part 7: Complete WCAG 2.1 Checklist

### Level A (Must Have)

- [ ] **1.1.1 Non-text Content** — Images have alt text
- [ ] **1.4.1 Use of Color** — Color not the only indicator (use icons too)
- [ ] **2.1.1 Keyboard** — All functionality available via keyboard
- [ ] **2.1.2 No Keyboard Trap** — Focus can move away from any element (except modals)
- [ ] **2.4.1 Bypass Blocks** — Can skip repetitive content
- [ ] **2.4.3 Focus Order** — Tab order is logical
- [ ] **2.4.7 Focus Visible** — Focus indicator is visible
- [ ] **3.1.1 Language of Page** — Language is specified
- [ ] **3.3.1 Error Identification** — Errors clearly identified
- [ ] **3.3.4 Error Prevention** — Can correct before submitting
- [ ] **4.1.2 Name, Role, Value** — All UI components have accessible names

### Level AA (Should Have)

- [ ] **1.4.3 Contrast (Minimum)** — 4.5:1 for normal text, 3:1 for large text
- [ ] **1.4.11 Non-text Contrast** — 3:1 for UI components
- [ ] **2.4.7 Focus Visible** — Focus indicator clearly visible (enhanced)
- [ ] **3.2.4 Consistent Identification** — UI patterns are consistent
- [ ] **3.3.3 Error Suggestion** — Suggestions provided for errors

### Check Against This List

- [ ] All Level A items: ✓ DONE
- [ ] Color contrast: ✓ VERIFY
- [ ] Keyboard shortcuts: ✓ DONE (⌘O, ⌘,, ⌘Q)
- [ ] Focus visible: ✓ VERIFY
- [ ] Screen reader support: ✓ TEST WITH VOICEOVER
- [ ] All dynamic content announced: ✓ VERIFY

---

## Part 8: Testing Checklist - Fill This Out

### Print & Complete This Checklist

```
APP: Upmarket
DATE: ___________
TESTER: ___________

ACCESSIBILITY INSPECTOR AUDIT
[ ] Buttons have descriptions
[ ] Toggles have descriptions  
[ ] Text fields have labels
[ ] Status elements have alt text
[ ] No "unlabeled" elements found

VOICEOVER TESTING
[ ] Elements announce role (Button, Checkbox, etc.)
[ ] Elements announce their name/label
[ ] Status changes announced
[ ] Errors announced
[ ] Progress announced

KEYBOARD NAVIGATION
[ ] All tasks completable without mouse
[ ] Tab moves forward logically
[ ] Shift+Tab moves backward
[ ] Focus always visible
[ ] No keyboard traps (except modals)
[ ] All shortcuts work (⌘O, ⌘,, ⌘Q)

COLOR & CONTRAST
[ ] Text contrast ≥4.5:1
[ ] Large text contrast ≥3:1
[ ] UI components ≥3:1
[ ] Focus indicator visible

WCAG 2.1 LEVEL A
[ ] All items checked
[ ] No failures

WCAG 2.1 LEVEL AA  
[ ] Contrast ratios verified
[ ] Focus indicators enhanced
[ ] Consistency verified

ISSUES FOUND:
_________________________________
_________________________________
_________________________________

PASS / FAIL: __________
```

---

## Commands for Quick Testing

```bash
# Open Accessibility Inspector
open /Applications/Utilities/Accessibility\ Inspector.app

# Enable VoiceOver (toggle)
open -a VoiceOverUtility

# Run accessibility tests
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO \
  -only-testing:UpmarketTests/AccessibilityAuditTests

# Run keyboard tests
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO \
  -only-testing:UpmarketTests/KeyboardInteractionTests
```

---

## Standards Reference

- **WCAG 2.1** - Web Content Accessibility Guidelines (applies to all digital products)
  - https://www.w3.org/WAI/WCAG21/quickref/
  
- **Apple Accessibility Guidelines** - macOS-specific
  - https://www.apple.com/accessibility/macos/

- **ARIA** - Accessible Rich Internet Applications (for labels/hints)
  - https://www.w3.org/WAI/ARIA/apg/

---

## Automated Tests Now Available

Run these to catch accessibility regressions:

```bash
# Comprehensive accessibility audit
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO \
  -only-testing:UpmarketTests/AccessibilityAuditTests

# Keyboard interaction tests
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO \
  -only-testing:UpmarketTests/KeyboardInteractionTests

# All tests
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

