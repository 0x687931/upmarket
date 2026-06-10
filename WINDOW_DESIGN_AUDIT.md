# Upmarket Window Design System Audit

## Current Windows

### 1. **Main Window** (ContentView)
- **Size:** 420×600 (fixed)
- **Current Structure:**
  - Status banner (variable height)
  - Divider
  - Drop zone (160pt fixed height)
  - Divider  
  - Queue list (fills remaining)
- **Padding Issues:**
  - Drop zone: 24pt horizontal, 16pt vertical (outer)
  - Drop zone content: 32pt vertical internal padding (TOO MUCH)
  - Queue list: 12pt padding inside ScrollView
  - Status banner: No consistent padding defined
  - No buffer between sections

### 2. **Paywall Window** (PaywallView)
- **Size:** 480×600
- **Current Structure:**
  - Header with close button
  - Divider
  - ScrollView with cards (Pro, Basic)
  - Product status
  - Purchase status
  - Buttons
- **Padding Issues:**
  - Uses `windowSize.contentPadding` (12pt for modal)
  - Inconsistent padding in different sections
  - No visual separation buffer between cards

### 3. **Preferences Window** (PreferencesView)
- **Size:** 600×680
- **Current Structure:**
  - TabView with 4 tabs (General, Conversion, Automation, About)
  - Form style (.grouped)
  - Various sections
- **Padding Issues:**
  - Relies on Form's default spacing
  - No consistent region-based padding
  - Sections are tightly packed

### 4. **Report Problem Window** (ReportProblemView)
- **Size:** 480×600
- **Current Structure:**
  - Problem type picker
  - Summary input
  - Toggle for diagnostics
  - Preview section
  - Buttons
- **Padding Issues:**
  - Hardcoded padding (windowSize.contentPadding)
  - Form-based layout
  - No buffer zones

### 5. **Shelf Window** (ShelfView)
- **Size:** 217×132 (floating widget)
- **Current Structure:**
  - Minimal layout for quick access
  - Job list
- **Padding Issues:**
  - Very compact, different rules apply

### 6. **Modal Dialogs** (Sheets)
- AISuggestionView (not using standard window system)
- WelcomeView (not using standard window system)
- Password prompt (modal)

### 7. **Window Controllers**
- MainWindowController: 420×600, no resizing
- PaywallWindowController: 480×600, floating panel
- PreferencesWindowController: 600×680, resizable
- ShelfWindowController: Custom floating position
- ReportProblemWindowController: 480×600

---

## Design Problems Identified

1. **No Standard Region Structure** - Each window defines its own layout
2. **Inconsistent Padding** - Values range from 12pt to 32pt with no pattern
3. **Missing Buffer Zones** - Content touches dividers/edges
4. **No Semantic Naming** - Hard to understand "why" elements are spaced as they are
5. **Form vs VStack Inconsistency** - Some use Form, others manual VStack
6. **Inconsistent Divider Usage** - Dividers appear without consistent spacing rules
7. **No Baseline Alignment** - Components don't align vertically across windows

---

## Proposed Unified Design System

### Core Concept: Named Regions with Standard Padding

**Every window should consist of:**

```
┌─────────────────────────────────┐
│ [HEADER REGION]                 │ 16pt h-padding, 12pt v-padding
├─────────────────────────────────┤ (divider)
│                                 │
│ [PRIMARY CONTENT REGION]        │ 24pt h-padding, 16pt v-padding
│                                 │
│                                 │
├─────────────────────────────────┤ (divider, if secondary exists)
│                                 │
│ [SECONDARY CONTENT REGION]      │ 24pt h-padding, 12pt v-padding (optional)
│                                 │
└─────────────────────────────────┘
[Optional Footer Region]           16pt h-padding, 16pt v-padding
```

### Standard Spacing Values

| Element | H-Padding | V-Padding | Buffer Between |
|---------|-----------|-----------|-----------------|
| Header | 16pt | 12pt (top+bottom) | 8pt to divider |
| Primary Content | 24pt | 16pt | 12pt between sections |
| Secondary Content | 24pt | 12pt | 8pt to divider |
| Footer | 24pt | 16pt | 12pt from content |
| Internal (rows/items) | 16pt | 8pt | 4pt between |
| Sections within Region | — | 12pt | — |

### Per-Window Layout Spec

#### Main Window (420×600)
- **Header:** Status banner 
  - Padding: 16pt h, 12pt v
- **Primary:** Drop zone (140pt) + Queue list (fills remaining)
  - Drop zone outer: 24pt h, 16pt v
  - Drop zone internal: 16pt vertical (not 32pt)
  - Queue items: 16pt h, 8pt v padding
- **Secondary:** History section (if exists)
  - History rows: 16pt h, 8pt v padding

#### Paywall Window (480×600)
- **Header:** "Unlock Upmarket" title
  - Padding: 16pt h, 12pt v
- **Primary:** Scrollable content
  - Cards: 24pt h, 16pt v padding
  - Buttons: 24pt h, 16pt v padding
  - Status messages: 24pt h, 8pt v padding

#### Preferences Window (600×680)
- **Header:** None (TabView acts as header)
- **Primary:** Tab content
  - Form sections: 24pt h, 12pt v padding
  - Section items: 16pt h, 8pt v padding
  - Each tab treated as own region

#### Report Problem Window (480×600)
- **Header:** Title section
  - Padding: 16pt h, 12pt v
- **Primary:** Form content
  - Fields: 24pt h, 12pt v padding
  - Preview: 24pt h, 12pt v padding
- **Footer:** Buttons
  - Padding: 24pt h, 16pt v

#### Shelf Window (217×132)
- **Compact Mode:** 
  - H-padding: 8pt
  - V-padding: 4pt
  - Exception to standard rules due to space constraints

---

## Implementation Steps (When Approved)

1. Create `WindowLayout.swift` with:
   - `WindowRegion` enum with standard padding values
   - Container views: `WindowHeader`, `WindowPrimaryContent`, `WindowSecondaryContent`, `WindowFooter`
   - `WindowLayoutContainer` wrapper

2. Create `LayoutConstants.swift` with:
   - All padding values as named constants
   - Per-window layout specifications

3. Refactor each window:
   - Main Window → Use region containers
   - Paywall Window → Use region containers
   - Preferences Window → Standardize tab padding
   - Report Problem → Standardize form padding
   - Shelf Window → Compact variant

4. Validation Rules:
   - No element should have <8pt padding (except compact shelf)
   - All dividers should have 8pt buffer on both sides
   - Sections should have 12pt vertical separation
   - Headers and footers must use consistent padding

---

## Questions for Approval

1. ✓ Do the proposed spacing values feel right?
2. ✓ Should Shelf use different (8pt/4pt) rules?
3. ✓ Should modal dialogs (sheets) follow the same system?
4. ✓ Any adjustments needed to the padding amounts?
5. ✓ Should all windows be locked to fixed sizes or allow resizing?
