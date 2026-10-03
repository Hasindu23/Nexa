# Nexa 0.6.0 — storage and memory

Verified on this Mac on October 2, 2026. Requires macOS 15 or later. The app includes Apple Silicon and Intel binaries; runtime checks were performed on Apple Silicon.

## Find and remove hidden storage

Open **Disk space explorer** and choose **Analyze Home**, **Analyze startup data**, or a folder/drive. The map includes hidden Library and dot folders. Open a folder to inspect its largest children, filter hidden entries, or view the largest files below it.

For a supported cache or installer location, choose **Review removable files…**. Nexa scans only the known cleanup locations within that selection. Selecting an individual file limits the resulting review to that file. Unknown app data is excluded, and nothing is preselected. The review shows removable candidates, protected/in-use items, exact paths and an allocated-size estimate.

1. Close the relevant app or development tool and rescan.
2. Select the files you want to remove.
3. Choose **Move to Trash** or **Delete Cache**, then **Review selected…**.
4. Review the exact files and confirm. Delete Cache is permanent, bypasses Trash and requires a second confirmation with the word **DELETE**.
5. Read the result and fresh scan. Only successful removal is reported. Moving items to Trash reports zero reclaimed bytes until Trash is emptied.

Supported rules include npm's content cache, pip and Homebrew download caches, supported application/browser caches, Xcode build data and old installer candidates. The explorer does not infer that every hidden file is disposable. Databases, credentials, app support, source files, personal folders and other protected data remain excluded according to their cleanup rules. See the [full scope guide](STORAGE-CLEANER.md).

Deep scans are bounded and cancellable. A scan-limit warning means totals are partial: open a smaller folder and use **Analyze this folder**. Snapshots are read-only inventory. Measured bytes can differ from recoverable storage because of APFS sharing, snapshots, permissions and other disk activity.

## Memory and running apps

Open **Memory & apps** in Storage Cleaner or **Memory & Apps…** in Nexa's menu. The page shows macOS memory pressure, physical RAM, free pages, compressed RAM, wired RAM and swap usage. Running apps show their main-process physical footprint; helper processes and browser tabs can use additional memory.

**Review quit…** shows a confirmation for the app you choose. **Ask app to quit** sends a normal macOS quit request after checking the same process, launch time, identity and ownership again. Save prompts are left to the app. Nexa never force-quits apps or closes them automatically, and it does not claim that their displayed footprint equals freed RAM.

**Clear Nexa scan results** releases the inventories and cleanup reviews held by Nexa. Files and cleanup history remain on disk. A new scan is required before cleaning again. The result is not represented as a guaranteed amount of free RAM.

macOS uses memory caching and compression itself. Nexa does not purge RAM, delete swap files or make performance-boost claims. See [Apple's memory explanation](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac) and [normal quit versus Force Quit](https://support.apple.com/guide/activity-monitor/quit-a-process-actmntr1002/mac).

## Validation

**83 automated tests passed, zero failures.** Universal build, native storage/memory workflows, app launch/reopen, layout and motion checks, strict code signatures, disk-image integrity and matching installed/packaged executables passed. The Mac locked before the additional interactive check of the installed UI.

The final verification record and native reports are in [Final-0.6-QA](Final-0.6-QA/verification.json). Automated coverage includes hidden-file inventory, focused cleanup scope, database/protected-path exclusions, symlinks, hashes, cancellation, partial failures, read-only volumes, typed deletion confirmation, stale process identities and refusal to quit.

Native QA uses generated files and an isolated disposable helper app. It checks the full storage and memory interfaces, an actual confirmed cache deletion and rescan, canceling an app-quit review, an actual confirmed normal quit of the helper, general app interactions, notch-free layouts and interrupted animations. Personal files and personal apps are not used as destructive test targets.

## Installation and limits

The local app is **/Applications/Nexa.app**. The supplied installer is **Nexa-Final-0.6.0.dmg**, accompanied by **Nexa-Final-0.6.0.dmg.sha256**. Existing settings are preserved, and the previous installed version was archived.

This is a locally signed development build, not Apple-notarized. Permission-restricted locations remain unavailable or partial. Full Disk Access is never enabled automatically. System-Trash Undo still needs validation with access granted on this Mac; the isolated Trash/recovery tests pass. Live Docker/Ollama removal, Windows/remote cleanup, Intel hardware and older supported macOS versions are outside the verified runtime scope.

The published GitHub release/update feed remains 0.4.2; this deliverable is a local update.
