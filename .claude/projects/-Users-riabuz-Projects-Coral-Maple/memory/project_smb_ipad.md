---
name: iPadOS SMB browsing requires AMSMB2
description: The built-in smbclientd LiveFiles paths on iPadOS cannot be enumerated by third-party apps. Direct SMB via AMSMB2 library is the solution.
type: project
---

**iPadOS SMB limitation confirmed 2026-04-12**: `smbclientd` LiveFiles paths (`/private/var/mobile/Library/LiveFiles/com.apple.filesystems.smbclientd/...`) cannot be enumerated by third-party apps — FileManager, NSFileCoordinator, and POSIX opendir all return 0 items even with security-scoped access active. This is a hard iOS sandbox restriction.

**Working path type**: `/private/var/mobile/Containers/Shared/AppGroup/.../File Provider Storage/...` — these come from File Provider extensions (third-party SMB apps), not from the built-in SMB client.

**Solution**: Add `AMSMB2` SPM dependency for direct SMB connection. User provides server address + credentials, app connects directly bypassing smbclientd entirely.

**Why:** Apple's built-in SMB in Files app uses private entitlements for directory enumeration. Third-party apps must either use a File Provider extension or implement SMB themselves.

**How to apply:** When implementing the SMB connection feature, add `AMSMB2` (`https://github.com/amosavian/AMSMB2`) as an SPM dependency to CoralCore. Create an `SMBSource` that conforms to `LibrarySource` with its own connection UI (server URL, credentials, share name). This is Phase 1 scope — needed for the "two first-class data sources" architecture principle.
