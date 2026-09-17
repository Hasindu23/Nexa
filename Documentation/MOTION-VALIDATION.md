# Motion validation — Nexa 0.3.0

Tested 17 September 2026 on the same Apple Silicon Mac, macOS 26.5.1, using optimized Release builds before and after the animation changes.

## Changes

- Persistent expanded and compact widget layouts replace continuous native window resizing. Core Animation morphs the notch mask and fades its content layers with an ease-out curve.
- Interrupted transitions start at their current visible shape. A generation check prevents an old completion from snapping a newer transition shut.
- Hover deadlines recheck the pointer against the live window, avoiding false collapse when tracking rectangles change.
- Appearance adjustments preserve the hosting tree, focus and local view state.
- Device/calendar/file refreshes wait for expansion to settle. Appearance-only settings no longer restart integrations.
- Playback bars animate as compositor layers instead of rebuilding a SwiftUI view on a recurring timer. App icons are cached per media source; unchanged media snapshots are not republished.
- Buttons have brief press feedback. Reduce Motion disables decorative movement.

## Repeatable interaction benchmark

Run the built executable with `--qa-motion /tmp/nexa-motion.txt`. It uses isolated settings, sample media, no camera, no clipboard capture and no playback commands. After warm-up, it performs eight full open/close cycles, 24 rapid reversals and 12 Home/Tray changes. It verifies the actual final native window size, camera-gap center and top edge.

| Measurement | Original animation | 0.2.1 | 0.3.0 |
| --- | ---: | ---: | ---: |
| Native window resize notifications | 285 | 19 | 19 |
| Main-loop heartbeat p95 interval | 32.87 ms | 9.26 ms | 8.89 ms |
| Heartbeat intervals over 33.3 ms | 45 | 1 | 1 |
| Longest heartbeat interval | 69.12 ms | 84.20 ms | 60.75 ms |
| Final collapsed frame | Pass | Pass | Pass |

The heartbeat is a 120 Hz main-run-loop timer, not a display frame counter. These numbers show much less repeated main-thread disruption; they do not establish rendered FPS or guarantee the absence of every hitch. The 0.3.0 run still had one 60.75 ms outlier. Each column is one local run, with other desktop apps running. Raw reports are in `motion-before.txt`, `motion-after-0.2.1.txt` and `motion-after.txt`.

## Regression checks

All 31 XCTest checks passed. Motion checks exercise rapid reversal completion, stable widget widths during animation, preservation of the hosting tree after appearance changes, false versus actual pointer exits, menu opening, inactive hit targets, immediate Reduce Motion, banner/size retargeting and preference migration. Background device reads, media cache behavior, hardware alignment, privacy, data preservation and media routing checks also passed.

The native smoke-check mode additionally exercises real navigation/button clicks, timer start/pause, file preservation, collapsed hit area, settings, camera-off state and Home sizing. See `Screenshots/smoke-check.txt` for the release result.

The final panel still shrinks to its physical collapsed window bounds; the larger animation canvas exists only during a transition. Live camera use, every browser/player, Intel Macs and other macOS versions are outside this animation test.
