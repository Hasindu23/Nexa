# Disk Space Explorer — Nexa 0.6.0

Open **Nexa → Disk Space Explorer** in the menu bar, choose **Disk space explorer** in Storage Cleaner, or click **Explore hidden SSD storage** on its overview.

Choose **Analyze Home** to measure your home folder, including Library and dot folders. **Analyze startup data** inspects the startup data volume, including system-owned and other user locations that macOS permits you to read. **Choose folder or drive** supports other folders and external volumes. Deep analysis begins only after a click, stays local, can be canceled, and retains results in memory until replaced or invalidated after cleanup.

## Understand the map

- Click a folder's ring segment, legend entry or arrow to drill down. Breadcrumbs return to parent folders.
- Use **Hidden only**, the name search and minimum allocated-size filter to narrow the list.
- **Largest files below here** finds files beneath the current folder, including nested hidden folders. The list shows at most 200 matches at once; narrow the search or folder to inspect more.
- Select an entry for its full path, explanation and **Reveal in Finder** action.
- If a scan reaches its entry or depth limit, a warning appears above the totals. Open a smaller folder and choose **Analyze this folder** to measure it with a fresh scan budget.
- **Review removable files…** scans only known cleanup locations within the selected folder. For a selected file, the review is restricted to that file. Nothing is preselected. Choose individual files and an action in the resulting removal review; the existing exact-item review, confirmation, Trash and recovery rules still apply.

The map uses allocated file blocks, not simply file lengths. Directory totals include inspected regular files. Hard links are counted once across the scan; shared APFS clone blocks may still overlap. Sparse files use the allocation macOS reports. Snapshots, system metadata, inaccessible locations and unscanned volumes are outside these totals. **Measured space is not necessarily reclaimable space.**

## Hidden storage and cleanup boundaries

Library/Application Support, app containers, iPhone backups, Docker disks, Ollama models, repository metadata and credentials are not general cleanup targets. The explorer inspects accessible metadata without reading file contents. Credential-store directories are skipped. Backups and application data include an explanation directing you to their owning application or Finder.

The cleaner now recognizes these additional rebuildable caches:

- `~/.npm/_cacache`
- `~/Library/Caches/pip`
- `~/Library/Caches/Homebrew/downloads`

Only individual regular files inside those exact cache roots can be reviewed. Recommendation age rules and database exclusions still apply. Close the relevant tools before cleaning; detectable active files are rejected. npm configuration, installed toolchains, package sources and arbitrary dot folders are not included in those cache rules.

The protected list also covers user Application Support, Containers, Group Containers, credential/configuration directories, raw Docker and Ollama data, Git metadata and system swap. Docker/Ollama service-managed removal remains a separate explicit action; its prior validation limits still apply.

## Snapshots and System Data

**Check startup snapshots** reads snapshot names from both the System and Data volumes using a fixed, read-only `diskutil` request. It does not delete, thin, rename or mount a snapshot. Unsupported or denied responses are shown as unavailable. No estimated snapshot size is invented or added to reclaimable totals.

Time Machine automatically manages its local snapshots and counts their space as available for other work. See [Apple's local snapshot explanation](https://support.apple.com/en-us/102154). **Open Disk Utility** lets you inspect the system's own snapshot view; Apple's [APFS snapshot guide](https://support.apple.com/guide/disk-utility/view-apfs-snapshots-dskuf82354dc/mac) explains the available information. System boot/update snapshots should not be treated as ordinary temporary files.

## Safety and coverage

The explorer is a separate inventory type with no deletion API. It walks held directory descriptors without following symlinks, rechecks opened-directory identity and stays on the selected volume. Selecting an external volume explicitly allows inspection of that volume. Permission failures, special files, cloud placeholders, shared hard links and scan limits appear as partial or unmeasured entries; they are not silently reported as empty folders.

The default bounds are 250,000 entries and 64 directory levels. Choose a smaller folder after a limit is reached. No Full Disk Access permission is enabled by the app; macOS controls which locations can be inspected. Existing system-Trash permissions, local signing, platform and service-integration limits remain documented in [Storage Cleaner](STORAGE-CLEANER.md).

No personal file is deleted during installation or analysis. Screenshots used for QA are generated fixtures.
