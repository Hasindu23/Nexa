# Storage Cleaner validation

Reverified on September 20, 2026 for Nexa 0.4.2 with Xcode on the available Apple Silicon Mac. Tests and the native smoke run used generated temporary fixtures; no personal downloads, app caches, developer data, Docker resources or AI models were cleaned.

## Automated results

**58 tests passed, 0 failures** in the final full XCTest run: 31 existing Nexa tests plus 27 Storage Cleaner tests.

The cleaner tests cover protected paths, path boundaries/traversal, leaf and parent symlink replacement, hard links, SHA-256 duplicate detection, different same-size files, duplicate keepers, changed keepers, safe recommendation boundaries, exact-item review, missing confirmation, the extra permanent-deletion phrase, single-use plans, plan expiration, new protection, Trash failure rollback, Undo without overwrite, partial failures, active files, permission failures, canceled scans, scan limits, disconnected/wrong-scope/wrong-device grants, unknown item IDs and Docker inventory semantics.

A generated disk image was mounted read-only for the read-only-volume test. Cleanup was rejected, the file remained, and reclaimed storage stayed zero. The mount was detached afterward.

The real macOS Trash permission test verified that denied Trash access preserves the original and reports zero reclaimed space. This environment does not grant the built app access to Trash. Successful Trash movement and Undo use an injected local fixture Trash adapter in the deterministic tests; successful system-Trash Undo needs separate validation after the app is granted permission.

The full app regression run exposed an existing IOKit battery observer retaining an expired context. `SystemService` now invalidates its notification source during deinitialization. The final full suite passed after that correction.

## Native application verification

The Release app was launched using `--qa-storage`. Its smoke check:

- Created and scanned four isolated files, then verified a two-file duplicate group.
- Opened and rendered the full Storage Cleaner window.
- Opened an exact-item review and confirmed the source file remained untouched.
- Clicked the actual native sidebar and verified the destination changed.
- Clicked through to the separate permanent-deletion confirmation, rendered the typed-confirmation field, and verified no removal occurred.

The final native smoke check additionally verifies closed, minimized and off-screen window recovery after an app-icon reopen. Added regression tests cover maximum-length filenames, failed history writes, retained recovery journals, unverified Trash destinations and bounded whole-group selection.

The installed `/Applications/Nexa.app` also passed normal launch, repeated launch, duplicate-instance activation and fresh relaunch checks. See the [recorded installed-app results](GitHub-QA/installed-launch-checks.json) and [final release notes](FINAL-0.4.2.md).

The full native app and simulated display-without-a-notch smoke checks also passed. The screenshot captures were visually inspected for layout and legibility. See [smoke report](GitHub-QA/storage-smoke-check.txt), [overview](GitHub-QA/storage-overview.png), [Downloads](GitHub-QA/storage-category.png), [review](GitHub-QA/storage-review.png), and [permanent confirmation](GitHub-QA/storage-permanent-confirmation.png).

## Reproduce

```sh
python3 Scripts/generate-project.py
./Scripts/test.sh
./Scripts/build.sh Release
/path/to/Nexa.app/Contents/MacOS/Nexa --qa-storage /path/to/qa-output
```

The build scripts isolate their products in `NexaStorageBuild` under the temporary directory. The supplied disk image uses a Release build. Its app signature passed `codesign --verify --deep --strict`, and the disk image passed `hdiutil verify`. The main executable contains arm64 and x86_64 slices; runtime verification was on Apple Silicon only.

## Remaining validation boundaries

Docker Desktop and Ollama were not running locally, so live API removal, shared-layer recovery and service disconnects during mutation are not proven by these tests. Docker parsing is fixture-tested. Remote transport and Windows are absent from this macOS source project. Intel Macs and older supported macOS releases require their own device tests. No fake integrations or fixture statistics are enabled in a normal launch.
