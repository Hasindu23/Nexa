# Nexa 0.4.2

Verified September 20, 2026. macOS 15 or later; Apple Silicon and Intel binaries included. Runtime checks were performed on Apple Silicon.

## Changes

Storage Cleaner adds categorized, on-demand scans, exact-item review, protected paths, SHA-256 duplicate verification, confirmed cleanup, local history and recoverable Trash actions. Irreversible cleanup requires an additional typed confirmation. Scheduled mode only scans.

Opening the Nexa icon now presents a visible window. Reopening restores closed, minimized and off-screen windows; duplicate launches activate the existing instance. A battery-observer lifecycle fault found during regression testing is fixed.

This release also preserves the existing GitHub version's rounded floating panel for displays without a notch, native preview checks and repository/update links. These were missing from the earlier local 0.4.1 copy and were restored during the GitHub comparison. QA screenshots use a generic test device name, and single-item counts use the correct label.

## Installation

Download **Nexa-Final-0.4.2.dmg** from the [release](https://github.com/Hasindu23/Nexa/releases/tag/v0.4.2), quit the old copy, drag Nexa into Applications, then open **`/Applications/Nexa.app`**. Existing settings are preserved. The download includes a SHA-256 checksum file.

The local installation was updated and checked directly from Applications. The previous installed version was archived first. See [installed launch checks](GitHub-QA/installed-launch-checks.json).

## Validation

- **58 automated tests passed, zero failures:** 31 existing app tests and 27 Storage Cleaner tests.
- Release build succeeded; the app passed strict signature verification and contains arm64 and x86_64 executable slices.
- Native Storage Cleaner checks passed for fixture scanning, duplicate verification, navigation, review, the separate permanent-delete confirmation and window restoration.
- Full native app checks passed on the current display and with simulated display-without-a-notch geometry.
- Fresh, repeated and duplicate-instance launches passed from the installed Applications location.
- The final disk image passed integrity verification.
- Source changes were compared with the existing GitHub release to preserve its features and history. New screenshots contain generated fixture files; no personal file was cleaned or uploaded.

See the [Storage Cleaner validation report](STORAGE-VALIDATION.md), [native app report](GitHub-QA/app-smoke-check.txt), and [display-without-a-notch report](GitHub-QA/no-notch-smoke-check.txt).

## Known limits

This is a locally signed development release, not an Apple-notarized commercial build. Downloaded apps may require macOS approval; building from source is also supported. System security settings were not disabled.

The test Mac denies access to system Trash. Nexa preserves originals and reports that permission error; successful Trash movement and Undo were tested with isolated adapters. Successful system-Trash Undo still needs validation after access is granted.

Windows and paired-device cleanup are not implemented. Live Docker/Ollama removal was not tested. Browser cookies, site data and history use browser settings; archives and simulator bundles use Xcode guidance. Intel hardware, physical displays without a notch and older supported macOS versions need separate device validation. The [scope guide](STORAGE-CLEANER.md) distinguishes supported actions from inventory and guidance.
