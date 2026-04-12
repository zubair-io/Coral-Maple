# Coral Maple

A professional, non-destructive photo editor for macOS, iPadOS, and iOS. Built by Just Maple.

The app is in **Phase 0**: scaffolding only. Current source is the Xcode SwiftUI + SwiftData template (`ContentView.swift`, `Item.swift`) and has no app-specific code yet. The product vision lives in `photo-app-feature-spec.md`, the UI contract in `photo-app-ui-spec.md`, and an interactive layout reference in `photo_app_mockup_v2.html`.

## Product summary

Three-column shell (sources tree / image grid / detail inspector) on Mac and iPad, single-column on iPhone. Two modes: **Browse** (grid) and **Full image** (large preview with filmstrip). All edits are non-destructive and persist to **XMP sidecars** — never to the original file.

Read the full feature spec and UI spec before making product decisions. They are the source of truth, not this file.

## iOS Simulator Testing

When asked to test a feature or verify a UI change:

1. **Build**: Run xcodebuild for the simulator target
2. **Launch**: Use launch_app with the bundle ID
3. **Screenshot**: Take a screenshot to verify current state
4. **Inspect**: Use get_ui_hierarchy to find elements
5. **Interact**: Use tap/type to exercise the UI
6. **Verify**: Screenshot again to confirm the result

## macOS App Testing

When asked to test a feature or verify a UI change on macOS:

1. **Build**: Use `xcodebuildmcp` to build for macOS (not simulator target)
2. **Run**: Launch the built `.app` directly via `open` or xcodebuildmcp's launch tool
3. **Screenshot**: Use `simulator/screenshot` — XcodeBuildMCP can capture the Mac screen too
4. **Accessibility tree**: Use `ui-automation` tools to inspect elements by label/role instead of coordinates
5. **Interact**: Never use coordinate taps; if an element has no accessibility label, add one before automating it."
6. **Verify**: Screenshot after each interaction to confirm state
7. **Logs**: Use `capture_logs` to catch any runtime errors

## Notes

- macOS builds use the `My Mac` destination, not a simulator UDID
- If the app requires permissions (camera, files, etc.), handle those manually first —
  automation cannot click system permission dialogs
- For menu bar items or system-level UI, fall back to `osascript` via Bash

## Architecture principles (from the spec — enforce these)

- **Non-destructive only.** Originals are never modified. All edits go to `.xmp` sidecars using the standard `crs:` namespace plus a custom `papp:` namespace for app-specific data (masks, snapshots, panorama refs). See `photo-app-feature-spec.md` § "Sidecar schema (v1)".
- **Two first-class data sources:** Apple Photos (PhotoKit) and the filesystem (Files via FileProvider + Security-Scoped Bookmarks). Treat them symmetrically in the UI; the storage path for sidecars differs (see spec).
- **Metal-backed pipeline end-to-end.** Decode → adjust → display all on GPU. Tile-based for >50MP RAW.
- **Shared Swift code via SPM modules**, with thin SwiftUI layers per platform. Avoid platform `#if` sprawl in business logic — keep it in the view layer.
- **Uniform edit model across platforms.** An edit made on iPad must roam to Mac with no conversion.
- **Wide gamut throughout.** Display P3 in the pipeline; ProPhoto RGB headroom for RAW; soft-proof to sRGB/Print.

## Build phases

Work is organized into 5 phases. Don't pull features forward across phase boundaries without an explicit decision — each phase has a deliberate "this is what makes the app usable next" framing.

1. **Phase 1 — Foundation:** library browsing (PhotoKit + filesystem), culling (rating/flag/label), XMP sidecar infrastructure. No editing yet.
2. **Phase 2 — RAW Develop & Export:** Core Image RAW pipeline, tone/WB/presence adjustments, Metal shader pipeline, export to JPEG/HEIC/TIFF/PNG.
3. **Phase 3 — Color Engine:** curves, HSL, color wheels, scopes (histogram/waveform/parade/vectorscope), LUT support, presets.
4. **Phase 4 — Advanced Editing:** panorama stitching (Vision + vImage), masking (subject/sky/luma/color/gradient/brush), healing, geometry, batch.
5. **Phase 5 — Polish & Sync:** iCloud sidecar sync, Pencil, ProRes RAW, plugin API, collaboration, accessibility, macOS native polish.

## UI contract — invariants

These come from `photo-app-ui-spec.md`. Treat them as load-bearing:

- **Three resizable panels** that persist across mode changes — only their content swaps. Browse mode: tree | grid | detail. Full-image mode: filmstrip (80px, fixed) | full image | detail.
- **Detail panel tabs** (bottom-pinned): Info, Color, Meta, Scopes. Scopes is grayed in browse mode.
- **All Color tab adjustments write to the sidecar immediately** on slider change. No "save" button.
- **Mode transition** is a 180ms ease-out layout shift; panels stay in place, center crossfades.
- **iPhone collapses to a single column** with a bottom tab bar (Library / Albums / Folders) and a swipe-up detail sheet. iPad portrait hides the left panel as a slide-in drawer.

## Visual design — Just Maple dark theme

The design system is Just Maple's dark theme. Tokens are listed in `photo-app-ui-spec.md` § "Color tokens". Key rules:

- **Never pure black.** Root background is warm charcoal `#1c1917`.
- **Elevation = lighter warm surfaces**, not shadows.
- **Accent `#c4493a` (maple red) is used sparingly** — selected nav, active tab indicator, focus rings, XMP badge border. Never as a fill on large surfaces.
- **Scopes always render on `#141210`** (deeper than root) so RGB waveform colors read clearly.
- **Images are the UI.** Chrome recedes; thumbnails and the full-image view dominate visual weight.
- Font: SF Pro via `-apple-system`. Body 12–13px / 400–500. Section headers: muted, uppercase, `letter-spacing: 0.05em`.

When implementing a new view, pull tokens from a central color/typography source — don't hardcode hex values inline.

## Tech stack

- Swift, SwiftUI, SwiftData (current scaffold)
- Metal, Core Image, Accelerate/vImage for the image pipeline
- PhotoKit for the Apple Photos source; FileProvider for the filesystem source
- Vision for masking and panorama feature detection
- Targets: iOS 26.4, macOS 26.3, visionOS 26.4 (deployment targets per project file)
- SDKROOT `auto`, supports `iphoneos iphonesimulator macosx`. Mac Catalyst is **off**; macOS is a native target.

## Project layout

```
Coral Maple.xcodeproj/        # Generated Info.plist via INFOPLIST_KEY_* build settings (no Info.plist file)
Coral Maple/                  # App sources
  Coral_MapleApp.swift        # @main entry
  ContentView.swift           # Template — to be replaced with the three-column shell
  Item.swift                  # Template SwiftData model — placeholder
  Coral Maple.entitlements    # iCloud (CloudDocuments) only so far
  Assets.xcassets/
Coral MapleTests/             # Unit tests
Coral MapleUITests/           # UI tests
photo-app-feature-spec.md     # Source of truth for features
photo-app-ui-spec.md          # Source of truth for UI/UX
photo_app_mockup_v2.html      # Interactive layout reference (open in a browser)
```

The project uses **generated Info.plist** (`GENERATE_INFOPLIST_FILE = YES`). To set Info.plist keys, add `INFOPLIST_KEY_*` build settings in `project.pbxproj` — do **not** create an Info.plist file. Encryption export compliance is already declared via `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`.

## Conventions

- **Don't keep template code around.** When you replace `ContentView`/`Item` with real models and views, delete the originals — don't leave them as "examples".
- **Prefer SPM modules** over a monolithic app target as soon as a feature has more than ~3 files. The pipeline, sidecar layer, and PhotoKit/filesystem sources should each be their own module.
- **No mocks for the sidecar layer in tests** — round-trip against real `.xmp` files in a temp directory. XMP is the contract; mocks would let bugs through.
- **Bundle ID:** `app.justmaple.Coral-Maple` (Tests / UITests append `Tests` / `UITests`).
- **Team:** `QREP66JW5U` (Just Maple). Public — fine to commit.

## What lives where

| If you need to…                           | Read this                                           |
| ----------------------------------------- | --------------------------------------------------- |
| Decide what a feature should do           | `photo-app-feature-spec.md`                         |
| Decide how a screen should look or behave | `photo-app-ui-spec.md`                              |
| See the layout in motion                  | `photo_app_mockup_v2.html` (open in browser)        |
| Look up a color, font, or spacing token   | `photo-app-ui-spec.md` § "Visual design"            |
| Look up the sidecar XMP schema            | `photo-app-feature-spec.md` § "Sidecar schema (v1)" |
