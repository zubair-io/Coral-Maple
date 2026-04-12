---
name: Architecture decisions from Phase 0 planning
description: Key technical decisions made during the implementation planning session before any code was written — XMP conflicts, pipeline topology, FileProvider scope, deployment targets, SwiftData removal, namespace URI
type: project
---

Decisions made 2026-04-11 during the Phase 0 → Phase 1 planning session. All six open questions resolved with their recommended approach:

1. **XMP conflict resolution (Phases 1–4):** Detect iCloud conflict copies (filename pattern matching), surface a warning badge in UI, let user manually pick which to keep. Automatic per-field merging deferred to Phase 5.

2. **Metal pipeline topology:** Flat ordered array of `AdjustmentNode`s in Phase 2. The `AdjustmentNode` protocol is designed to be DAG-compatible (input texture → output texture). Refactor to a real DAG in Phase 4 when masking introduces pipeline branching.

3. **FileProvider extension scope:** Read-only in Phase 1. The app reads from user-selected folders but does not appear as a writable location in Files.app. Read-write deferred to Phase 4/5.

4. **Deployment targets:** iOS 26.4 / macOS 26.3. Intentional bet on cutting-edge SwiftUI APIs. No backwards-compatibility shims.

5. **SwiftData dropped.** Bookmarks persist to `UserDefaults`. XMP sidecars are the single source of truth for image metadata. Thumbnail cache index (if needed) is a simple `Codable` plist. No SwiftData migration surface.

6. **Custom XMP namespace URI:** `http://ns.justmaple.com/coral-maple/1.0/` (replaces placeholder `http://ns.yourapp.com/1.0/` from the spec).

**Why:** These decisions were made to minimize complexity in early phases while keeping extension points for later phases. Each deferred item has a clear phase where it will be addressed.

**How to apply:** Enforce these in code review. If a PR introduces SwiftData, DAG topology, or read-write FileProvider before the designated phase, flag it.
