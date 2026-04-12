# Photo App — UI/UX Specification

**Platforms:** macOS, iOS, iPadOS  
**Layout model:** Three-column adaptive shell

---

## Layout overview

```
┌─────────────┬──────────────────────────┬─────────────┐
│  Left panel │      Center (grid)       │ Detail panel│
│  File tree  │  ┌──┐ ┌──┐ ┌──┐ ┌──┐   │             │
│  or         │  └──┘ └──┘ └──┘ └──┘   │  [tabs]     │
│  Filmstrip  │  ┌──┐ ┌──┐ ┌──┐ ┌──┐   │             │
│             │  └──┘ └──┘ └──┘ └──┘   │ ┌──┬──┬──┐ │
│             │                         │ │  │  │  │ │
└─────────────┴──────────────────────────┴─┴──┴──┴──┘
```

Three resizable panels separated by drag handles. All three persist across navigation — only their content changes.

---

## Browse mode (default)

### Left panel — file system tree

Width: 220px default, resizable 160px–320px.

**Sources section**
- Photos library (PhotoKit)
- Local files (filesystem root)

**Albums section** (Photos library)
- All Photos, Favorites, Picks, Rejects
- User albums listed alphabetically
- Smart albums (date range, camera, rating)

**Folders section** (local filesystem)
- Folder tree with expand/collapse chevrons
- Shows folder name + image count badge
- Drag folders to reorder or nest
- Right-click context menu: reveal in Finder/Files, new folder, rename

**Behavior**
- Single-click a source or folder to load its contents into the grid
- Active item highlighted with info-tinted background
- Tree scrolls independently of center and right panels

---

### Center panel — image grid

Fills remaining width between left and right panels.

**Grid**
- Thumbnail size: adjustable via slider in toolbar (small / medium / large, default medium)
- Aspect-ratio-preserved thumbnails with uniform row height (justified grid)
- Single-click: selects image, loads metadata into detail panel; previously selected image deselects
- Double-click: transitions to full-image mode (see below)
- Cmd+click / Shift+click: multi-select
- Selected image: 2px info-colored border inset on thumbnail

**Toolbar (above grid)**
- Left: source breadcrumb (e.g. Local files > 2025 > France trip)
- Center: thumbnail size slider
- Right: sort menu (date, name, rating, flag), filter pill (Picks only, 4+ stars, unedited)

**Empty state**
- Centered message: "No photos" with a folder icon and "Open a folder" CTA

---

## Full-image mode

Triggered by double-clicking a thumbnail. Escape or double-click again returns to browse mode.

```
┌──────────┬────────────────────────────┬─────────────┐
│          │                            │             │
│ Film-    │     Full image view        │ Detail panel│
│ strip    │     (fills center panel)   │  [tabs]     │
│          │                            │             │
│  ┌────┐  │                            │ ┌──┬──┬──┐ │
│  ├────┤  │                            │ │  │  │  │ │
│  ├────┤  │                            │ │  │  │  │ │
└──┴────┴──┴────────────────────────────┴─┴──┴──┴──┘
```

### Left panel — filmstrip

Collapses from tree to filmstrip (80px wide, not resizable).

- Vertical strip of thumbnails from the current folder/album
- Active image highlighted with info-colored border
- Click any thumbnail to switch to that image (no mode change)
- Scroll vertically through the strip
- Arrow keys (up/down on iPad, left/right on Mac) advance through images

### Center panel — full image view

- Image centered and scaled to fit the panel (letterboxed, no crop)
- Pinch to zoom (iPadOS) / scroll to zoom (macOS)
- At 100%+: pan by dragging
- Zoom level indicator in bottom-left corner
- Before/after toggle button in toolbar: splits view with draggable divider

### Toolbar (full-image mode)

Left: back button (returns to browse), filename  
Center: zoom controls (fit, 100%, zoom in/out), before/after toggle  
Right: flag controls (Pick / Reject), star rating, export button

---

## Detail panel

Width: 260px default, resizable 200px–360px. Always visible in both modes.

Content switches based on the active bottom tab. Tabs are icon + label, pinned to the bottom of the panel.

### Tab bar (bottom of detail panel)

```
┌────────┬────────┬────────┬────────┐
│  Info  │ Color  │  Meta  │ Scopes │
└────────┴────────┴────────┴────────┘
```

Active tab: 2px top border in info color, white background.  
Inactive tabs: no border, secondary background.

---

### Tab: Info

**File section**
- Filename, file size, format (e.g. Canon RAW / CR3)
- Pixel dimensions
- Sidecar status: shows `.xmp` filename if present, "No sidecar" if not

**Camera section**
- Camera model, lens, focal length, aperture, shutter speed, ISO
- Flash (on/off/not fired)

**Rating & flags section**
- Flag row: Pick (P) / Unflagged / Reject (X) — tappable pills
- Star rating: 1–5 stars, tap to set, tap active star again to clear
- Color label: row of colored dots (Red, Orange, Yellow, Green, Blue), tap to toggle

---

### Tab: Color

All adjustments write to the `.xmp` sidecar immediately on change. Sliders show numeric value on the right.

**Tone section**
- Exposure (−4 to +4 EV)
- Contrast (−100 to +100)
- Highlights, Shadows, Whites, Blacks (−100 to +100 each)

**Presence section**
- Clarity, Texture, Dehaze (−100 to +100)
- Vibrance, Saturation (−100 to +100)

**White balance section**
- Temperature (2000K–12000K)
- Tint (−100 to +100)
- WB preset picker: Auto, Daylight, Cloudy, Shade, Tungsten, Flash, Custom
- Eyedropper tool: tap a neutral area in the image to set WB

**Sharpening section**
- Amount, Radius, Detail, Masking

**Noise reduction section**
- Luminance, Color

**Revert / copy / paste row (bottom of color tab, above tab bar)**
- Revert: discard all edits, restore to original
- Copy: copy all adjustments to clipboard
- Paste: apply clipboard adjustments to current image

---

### Tab: Meta

**Location section**
- GPS coordinates (lat/lon)
- Reverse-geocoded city, region, country
- Map thumbnail (tap to open in Maps)

**Dates section**
- Date captured, date modified
- Date created (file creation)

**IPTC section**
- Title, Caption, Copyright, Creator (editable inline)
- Keywords: tag pills with add/remove

**Edit history section**
- List of named snapshots
- "Add snapshot" button
- Tap snapshot to restore; long-press to rename or delete

---

### Tab: Scopes

Visible only in full-image mode (grayed out and shows "Select an image to view scopes" in browse mode).

**Scope selector**
- Segmented control: Histogram / Waveform / Parade / Vectorscope

**Histogram**
- RGB composite or individual R, G, B channels (toggle)
- Clipping indicators: red overlay on blown highlights, blue on crushed blacks

**Waveform**
- Full-width luma waveform
- 0–100 IRE scale on y-axis

**Parade**
- R, G, B waveforms side by side
- Same IRE scale

**Vectorscope**
- Chroma/hue scatter plot in YCbCr space
- Broadcast-safe circle overlay
- Skin-tone line indicator

All scopes update live as sliders in the Color tab change.

---

## Platform adaptations

### macOS

- Full menu bar with all commands mirrored (File, Edit, Image, View, Window)
- Keyboard shortcuts for all common actions (see below)
- Drag handles on all panel dividers
- Right-click context menus on thumbnails and tree items
- Toolbar customizable via View > Customize Toolbar
- Full-screen mode: left panel collapses to icon rail, center expands

### iPadOS

- Same three-column layout in landscape on 12.9" iPad Pro and M-series iPad
- Portrait on smaller iPads: left panel hidden by default, slide-in drawer on tap
- Toolbar condenses: secondary actions move to a "..." overflow menu
- Apple Pencil: hover shows loupe in grid; tap to select, double-tap to enter full-image mode
- Apple Pencil in full-image mode: draw masks in the Masking tool (Phase 4)
- Stage Manager: app respects arbitrary window size; panels collapse below threshold widths

### iOS (iPhone)

- Single-column layout: bottom tab bar replaces left panel
- Tabs: Library, Albums, Folders
- Grid fills full width
- Tap thumbnail → full screen image with swipe-up detail sheet
- Detail sheet: scrollable, same tabs as iPad but arranged vertically

---

## Key interactions

| Action | macOS | iPadOS |
|--------|-------|--------|
| Select image | Click | Tap |
| Enter full-image | Double-click | Double-tap |
| Return to browse | Escape or double-click | Escape or double-tap |
| Next/prev image | Arrow keys | Arrow keys or swipe filmstrip |
| Set rating | 1–5 keys | Tap stars |
| Pick flag | P key | Tap Pick pill |
| Reject flag | X key | Tap Reject pill |
| Zoom in/out | ⌘+ / ⌘− or scroll | Pinch |
| Fit to window | ⌘0 | Double-tap image |
| 100% zoom | ⌘1 | Double-tap image (second tap) |
| Copy adjustments | ⌘C (in Color tab) | Copy button |
| Paste adjustments | ⌘V (in Color tab) | Paste button |
| Revert to original | ⌘⌥Z | Revert button |
| Export | ⌘⇧E | Export button |

---

## Visual design — Just Maple dark theme

The app uses the Just Maple dark theme as its design system. Warm charcoal surfaces, never pure black. Maple red accent. All tokens are sourced directly from the Just Maple SCSS token set.

### Design principles

- Never pure black — root background is warm charcoal `#1c1917`, not `#000000`
- Elevation through surface lightness — higher layers use progressively lighter warm surfaces
- Accent (`#c4493a`) is used sparingly: selected nav items, active tab indicator, focus rings, the XMP badge border
- Images are the UI — chrome recedes, thumbnails and the full-image view dominate visual weight
- Scopes always render on `#141210` (deeper than root bg) so R/G/B waveform colors read clearly regardless of surrounding theme
- Transitions: browse ↔ full-image is a 180ms ease-out layout shift; panels stay in place, center content crossfades

### Color tokens (dark)

```scss
--color-bg:           #1c1917   /* root / page background */
--color-surface:      #262524   /* panels, right detail pane */
--color-surface-alt:  #2e2c2a   /* tab bar, grouped backgrounds */
--color-surface-hover:#3a3836   /* hover state on surfaces */
--color-sidebar:      #292524   /* left nav panel */
--color-input-bg:     #1c1917   /* text inputs, range tracks */
--color-text-main:    #e7e5e4   /* primary text */
--color-text-muted:   #a8a29e   /* secondary labels, timestamps */
--color-border:       #44403c   /* dividers, panel borders, outlines */
--color-primary:      #c4493a   /* accent — maple red (brightened for dark) */
--color-primary-light:#422016   /* accent tinted bg — selected nav item fill */
--color-bg-hover:     rgba(255,255,255,0.06)  /* hover on nav items */
--color-bg-active:    rgba(255,255,255,0.10)  /* pressed / active states */
--color-bg-secondary: #292524   /* sidebar, secondary surfaces */
```

### Semantic colors (dark)

```scss
--color-success-bg:   rgba(34,197,94,0.15)   /* XMP badge, pick flag bg */
--color-success-text: #4ade80                 /* XMP badge text, pick flag */
--color-error-bg:     rgba(239,68,68,0.15)   /* reject flag bg */
--color-error-text:   #f87171                 /* reject flag text */
--color-star:         #EF9F27                 /* active star rating */
```

### Surface hierarchy (dark, light → dark)

| Layer | Token | Hex |
|-------|-------|-----|
| Image canvas | — | `#141210` |
| Root / page | `--color-bg` | `#1c1917` |
| Sidebar | `--color-sidebar` | `#292524` |
| Panels (detail, toolbar) | `--color-surface` | `#262524` |
| Grouped backgrounds | `--color-surface-alt` | `#2e2c2a` |
| Hover | `--color-surface-hover` | `#3a3836` |

### Typography

- Font: `-apple-system, BlinkMacSystemFont` (maps to SF Pro on Apple platforms)
- Primary text: `--color-text-main` / `#e7e5e4` / 12–13px / weight 400–500
- Secondary labels: `--color-text-muted` / `#a8a29e` / 10–11px
- Section headers: muted + uppercase + `letter-spacing: 0.05em`
- Nav selected: accent `#c4493a` on accent-dim `#422016` fill

### Component patterns

**Nav section headers** — flex row: chevron (rotates on collapse) + label + optional `+` icon right-aligned. Hover: `--color-bg-hover`. No border.

**Nav items** — 22px padding-left indent under section header. Selected: `background: #422016; color: #c4493a`. Hover: `rgba(255,255,255,0.06)`.

**Empty state (Folders)** — muted body copy + accent-colored "Add one" link. No icon, no border, no card.

**Detail panel tabs** — pinned to bottom of right panel. Active: 2px top border in accent, `--color-surface` bg. Inactive: `--color-surface-alt` bg, muted text.

**Range sliders** — `accent-color: #c4493a` (native browser/SwiftUI tint). Label row: name left, current value right in primary text weight.

**XMP badge** — `success-bg` fill + `success-text` color + checkmark icon. Inline below filename in Info tab.
