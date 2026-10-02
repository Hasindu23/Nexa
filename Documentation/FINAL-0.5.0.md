# Nexa 0.5.0

Verified October 2, 2026. Requires macOS 15 or later. The app contains Apple Silicon and Intel binaries; runtime checks were performed on Apple Silicon.

## Disk Space Explorer

Storage Cleaner now includes a native disk map for hidden SSD storage. Analyze Home, the startup data volume, or a chosen folder or drive. Drill into the circular map, inspect Library and dot folders, filter hidden entries, and find the largest files beneath the current folder. Analysis reads metadata only, stays local, and supports cancellation.

Allocated file estimates are shown separately from total volume use and free space. Permission restrictions, links, cloud placeholders and scan limits are visible. A prominent warning identifies a limited scan; **Analyze this folder** starts a fresh measurement of a smaller folder. Snapshots can be inventoried without deleting them or claiming their space is reclaimable.

Recognized cache locations open a fresh Storage Cleaner scan with no selected items. Exact-item review and confirmation remain required. npm's content cache, pip's cache and Homebrew download caches now have narrow cleanup rules. Application support, app containers, credentials, Git metadata, raw Docker/Ollama data and system swap have additional protection against generic file cleanup.

The update also corrects notch-window rounding at fractional display scaling. App-icon launch and reopen behavior remain verified.

See the [Disk Space Explorer guide](DISK-EXPLORER.md) for use, scope and measurement limits.

## Installation

The supplied installer is **Nexa-Final-0.5.0.dmg**, with **Nexa-Final-0.5.0.dmg.sha256** alongside it. Quit Nexa, drag the app to Applications, then open `/Applications/Nexa.app`. Existing settings are preserved. On this Mac the app has already been installed, and the previous version was archived first.

Open **Disk space explorer** in the Storage Cleaner sidebar, or **Disk Space Explorer…** from Nexa's menu bar menu. Start with **Analyze Home**. No personal files are deleted by installing or analyzing.

## Validation

- **71 automated tests passed, zero failures:** 12 explorer tests, 32 existing app tests and 27 cleaner tests. These cover hidden-folder totals, symlinks, hard links, unreadable files/directories, cancellation, bounded scans, cache rules, snapshot parsing, protected paths, duplicates, cleanup failures and read-only mounted volumes.
- Universal Release build succeeded and passed strict signature verification.
- Native fixture checks passed for rendering, folder navigation, cleanup review, the separate permanent-delete confirmation and closed/minimized/off-screen window restoration.
- Full native app smoke checks passed on the current display and with simulated geometry for a display without a notch.
- Installed fresh, repeated and duplicate-instance launches passed. The mounted installer app matches the installed executable and metadata; disk-image integrity and SHA-256 were checked.
- A read-only scan of this Mac's Home folder confirmed live hidden-folder results. Its entry limit was reached and reported; the totals are partial, not a complete SSD inventory. The new **Analyze this folder** action successfully measured Library caches separately. The snapshot action returned the startup volumes' snapshot metadata without modifying it.

Evidence: [storage and explorer checks](Explorer-QA/storage-smoke-check.txt), [app checks](Explorer-QA/app-smoke-check.txt), [display-without-a-notch checks](Explorer-QA/no-notch-smoke-check.txt), [installed launch checks](Explorer-QA/installed-launch-checks.json), and [package verification](Explorer-QA/release-verification.json). Shared screenshots contain generated QA fixtures, not personal folder inventories.

## Limits

This is a locally signed development build, not Apple-notarized. macOS permission restrictions still apply. The explorer does not grant itself Full Disk Access and cannot promise to account for every byte of System Data, snapshots, shared APFS blocks or inaccessible storage. It cannot delete snapshots or arbitrary hidden folders.

Existing limitations remain: system-Trash Undo needs validation after access is granted on this Mac; live Docker/Ollama removal and Windows/remote cleanup are not validated or implemented as described in the [Storage Cleaner scope guide](STORAGE-CLEANER.md). Physical Intel hardware, physical displays without a notch and older supported macOS versions require separate device checks.

This local update does not change the published 0.4.2 update feed or GitHub release.
