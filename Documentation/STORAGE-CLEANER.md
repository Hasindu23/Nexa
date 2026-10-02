# Storage Cleaner · Nexa 0.5.0

This release extends the existing native macOS Nexa app. Open **Nexa** in Applications to show the main window. Storage Cleaner also remains available from the menu bar menu and the Storage Cleaner widget. Quit an older running copy of Nexa before opening the new build.

Version 0.4.2 combines Storage Cleaner and launch fixes with the existing GitHub release’s display-without-a-notch support and repository/update links. The local installation is `/Applications/Nexa.app`; existing settings are preserved.

Disk Space Explorer now measures hidden Library and dot folders, supports folder drill-down and largest-file search, and lists startup snapshots without deleting them. See the [explorer guide](DISK-EXPLORER.md). npm, pip and Homebrew download-cache roots have also been added.

## Cleaning workflow

1. Open the module or press **Scan storage**. Scans do not delete anything. Cached results are reused for ten minutes when reopening the window.
2. Include Downloads, choose extra folders, or connect local Docker/Ollama explicitly. Permission failures and partial coverage appear in scan notices.
3. Review categories and exact files. Filter by age, access date when available, minimum size, and name. Reveal or preview files before selecting them.
4. Choose **Move to Trash**, **Delete Cache**, or **Permanent Delete**. The review lists every selected path/resource, size, risk and consequence. A review expires after five minutes; scans expire for cleanup after thirty minutes.
5. Confirm the review. Both irreversible actions additionally require typing **DELETE** on a second confirmation screen. A file can change between scanning and confirmation; those changes cause it to be skipped.
6. Read the result and refreshed scan. Partial failures are listed individually. History retains local metadata, never file contents.

Moving to Trash reports **0 bytes reclaimed**. Permanent cleanup reports the observed free-space increase, capped at the allocated size of successful removals. Concurrent disk activity, APFS shared blocks/snapshots and Docker disk images prevent exact attribution of every free-space change. Logical file/model sizes are estimates, never reported as automatically reclaimed space.

## Implemented scope

| Area | Behavior |
| --- | --- |
| Downloads | Explicit inclusion; old files, archives, DMG/PKG/ISO/EXE/MSI recognition, custom age/size/access-date filters. Ordinary ZIP/RAR/7z archives are treated as personal downloads, never inferred to be disposable installers. |
| Caches | Narrow recognized user cache roots for Spotify, Discord, Chrome, Edge, Safari and Firefox. Firefox is restricted to cache2. Database extensions are excluded; unknown caches and application support data are not cleaned. Applications must be closed. |
| Temporary files | Regular `.tmp` files older than seven days in the OS-provided user temporary directory. |
| Xcode | DerivedData file inventory and cleanup, excluding SourcePackages checkouts and source extensions. DeviceSupport files can be reviewed. Archive bundles and simulator data are read-only; use Xcode Organizer/Devices to manage them. No blanket simulator or archive deletion. |
| Docker | Explicit opt-in, fixed local Docker Desktop Unix socket. Inventory of containers, images, volumes and build cache. Individually selected stopped containers, unused images and unused volumes are revalidated and removed through non-force Engine API calls. No broad prune command. Build cache is inventory only. |
| Ollama | Explicit opt-in to `127.0.0.1:11434`. Lists models and sizes, compares current digests, rejects running models, and requires permanent confirmation for selected removals. Last-use dates are unavailable and are not fabricated. |
| Browser data | Cache only. Cookies, site data, history and sessions are not modified by Nexa. The UI describes sign-out consequences and opens the relevant browser so the user can explicitly manage those categories. |
| Large files | Selected folder/drive scan, largest files, configurable age and size, scanned folder totals, Reveal, Quick Look, Ignore and custom protection. Protected folders are read-only. External volumes can be inspected; cleanup is blocked when the private recovery area is on another volume. |
| Duplicates | Size grouping, small content sample, full streamed SHA-256 confirmation. Hard links are excluded. Keep at least one copy; selected copies and their keeper are rehashed before cleanup. |
| Screenshots | Filename detection in selected roots; Today / Last 7 days / Last 30 days / Older groups; Quick Look. Desktop remains protected. Localized filenames not matching the recognized patterns may be missed. |
| Trash | Current user Trash regular-file inventory and permanent deletion of reviewed items. Package bundles, empty directories and Trash on other drives are not swept recursively. |
| Leftovers | Possible leftovers only, read-only. Missing bundle identifiers are not proof of uninstall. No support-file deletion or false high-confidence claim. |
| Applications | Explicit inventory of `/Applications` and `~/Applications`, measured sizes, Spotlight last-used dates when available, creation metadata, Reveal/Open and uninstall guidance. No automatic uninstall. |
| Recommendations | Recognized caches/temp/build outputs older than seven days and installer candidates older than thirty days; user must press Review items to select. No documents, photos, videos, cookies, support data, backups, models or volumes are preselected. Trash stays separate because its action is irreversible. |
| Schedule | Off by default. Weekly or monthly scan-only checks while Nexa is running. No unattended cleanup, launch daemon, or wake-from-sleep service. |
| Dashboard | Real startup-disk capacity, circular usage chart, measured category totals and an explicitly partial scanned breakdown. Unmeasured categories and drive health remain labeled unavailable. |

## Protection and recovery

The policy protects the system roots, installed app bundles, photo libraries, backup bundles, personal Documents/Desktop/Pictures/Movies/Music, Keychains, Mail, Messages, browser profile locations and Nexa’s own state. `/`, the home directory and Downloads directory itself are never deletion targets. Users can add protection and ignored paths. Default protection cannot be removed in the UI.

Cleanup accepts IDs from an agent-owned scan, not arbitrary paths. It rechecks ownership, device/inode, size, modification and change timestamps, hard-link count, write permission, active app state and detectable open files. Paths are traversed through directory descriptors with `O_NOFOLLOW`; final operations use descriptor-relative rename/unlink. Only individual regular files are cleaned. Scan recursion does not cross mounts or follow symlinks. Cloud placeholders and packages are skipped.

Each reviewed file is first moved into a private same-volume recovery area. A scan manifest, per-file recovery journal and operation progress are saved before/during cleanup. Recovery folders preserve the full original filename. Completed file journals are removed only after the operation receipt is saved. Interrupted operation receipts are recovered into local history on the next launch. A Trash failure restores the original without overwriting a replacement. Failed restoration preserves the file in that recovery area and reports its path. No permanent-deletion fallback occurs.

**macOS permission boundary:** Nexa must be able to access user Trash before using the verified Trash/Undo workflow. If macOS denies it, cleanup preserves the original and explains how to allow Nexa in **System Settings → Privacy & Security → Full Disk Access**. No permission is enabled by the app. The test Mac denied this permission, so successful system-Trash recovery was not live-verified; injected Trash recovery and real permission-denial behavior were verified.

Undo is available for successful Trash moves while the file remains unchanged and accessible. An existing file at the original path is never overwritten. Because Nexa stages files first, use **Undo move to Trash** in Nexa for the original location; Finder’s Put Back metadata can refer to the staging location. Permanent deletion and service-managed Docker/Ollama removal have no Undo.

State lives under `~/Library/Application Support/Nexa/`: `storage-settings.json`, `storage-history.json`, `storage-pending.json`, `storage-last-operation.json`, and `StorageRecovery/`. The retained history is limited to 200 operations. Recovery metadata is intentionally private and contains paths, not file contents. Interrupted files in StorageRecovery are never swept automatically.

## Platform and integration limits

This source project is a **macOS app**, not an existing cross-platform Nexa Hub/Agent repository. **Windows scanning/Recycle Bin handling and paired-device transport are not implemented.** No remote device is represented as connected, and no remote command endpoint was created.

The included `StorageAgentGrant` boundary rejects disconnected devices, expired grants, wrong device IDs and missing `CLEAN_STORAGE`. A future authenticated Agent must own its scan and review state, verify pairing and the current grant again for every operation, support revocation and reconnect semantics, and accept only approved scanned item IDs. The local grant structure alone is not an authentication system.

Docker/Ollama services were unavailable on this test Mac. Their adapters compile, Docker response parsing has fixture coverage, and unavailable connections report errors. Live service removals remain unverified; no real containers, volumes or models were removed during development. Windows device validation, live service validation and a security review remain prerequisites for cross-platform distribution.

The package is locally signed for development, not Developer ID notarized. It contains the prior Nexa notch features as well as Storage Cleaner.

## Primary API references

- [Apple FileManager](https://developer.apple.com/documentation/foundation/filemanager): file operations, Trash and filesystem attributes.
- [Docker Engine API v1.47](https://docs.docker.com/reference/api/engine/version/v1.47/): storage inventory and individual resource removals.
- [Docker disk usage](https://docs.docker.com/reference/cli/docker/system/df/): shared-size and reclaimability semantics.
- [Ollama model listing](https://docs.ollama.com/api/tags), [running models](https://docs.ollama.com/api/ps), and [model deletion](https://docs.ollama.com/api/delete).
