# Nexa 3.1 — Fluid Motion & Electric Blue

Version 3.1.0, build 11. Native Swift, SwiftUI, AppKit and Core Animation; macOS 15 or later.

## Changes

- Central motion presets: Subtle, Balanced (default), and Playful, with adjustable speed.
- Width, height, corner radius and shoulders use continuous spring trajectories. Interruptions retain position and velocity; final geometry settles exactly. Native windows resize only at transition boundaries.
- Module content crossfades and selection indicators use matched geometry within their hosting tree. Hover/button feedback shares the motion policy.
- Electric Blue visualizer with Bars, Wave and Minimal styles, brightness, optional subtle royal-blue glow and intensity. It is explicitly decorative playback animation, not frequency or amplitude analysis. No audio capture is introduced.
- Repeating visualizer animations stop on pause, disabled/hidden/occluded views, Reduce Motion and energy saving. Energy saving also avoids the island's backdrop blur.
- Appearance & Motion settings preserve existing saved choices. macOS Reduce Motion overrides app-level motion choices.
- Detached displays reserve menu-bar space; small-display bounds are clamped. Display selections use display identifiers while accepting previous name-based choices.
- Storage Cleaner, memory management, the existing modules, data paths, bundle identifier and signing configuration remain included.

## Compatibility decision

At the user's explicit request, the existing system-wide MediaRemote integration is retained as an exception to the brief's public-API-only requirement. It uses a private Apple framework and may be affected by macOS changes. Music/Spotify fallback remains. The new motion and visualizer code uses public native APIs.

## Verification

Final validation on November 12, 2026:

- **95 XCTest tests passed, zero failures.**
- Five release-binary native runs passed: storage/memory, app navigation, simulated notch-free display, motion stress, and the new fluid/visualizer workflows.
- All 17 module views were rendered and reviewed. Native timer start/pause, shelf preservation, cleanup confirmations, generated-cache removal/rescan, and normal quitting of an isolated test helper passed.
- Rapid motion checks covered 8 full open/close cycles, 24 rapid reversals and 12 module changes, plus interruptions under each new preset. Final geometry settled exactly.
- Actual native visualizer layers stopped on pause, reduced motion, energy saving and hidden/occluded views. Appearance settings and old-preference migration passed.
- A visual review caught a lingering Mirror transition. Camera discovery moved off the main thread; the final screenshot is clean and a regression test checks the background discovery path.
- The isolated paused/collapsed test app used **0.127% of one CPU core over 61.1 seconds**. Its physical footprint went from 93,226,040 to 66,700,320 bytes. These are measurements of this test process, not a general performance guarantee or RAM-cleaning claim.
- The universal release, strict/deep signatures, DMG integrity and every regular file in the mounted installer were verified. The installed app launched visibly and its stored preference record was unchanged.

Evidence: [`verification.json`](Fluid-3.1-QA/verification.json), [native motion](Fluid-3.1-QA/motion-smoke-check.txt), [native fluid/idle report](Fluid-3.1-QA/Fluid/fluid-smoke-check.txt), [installed launch](Fluid-3.1-QA/installed-launch-checks.json).

Installer SHA-256: `cc1e750e5fa99cf459cd1dd0ea160117c0540362bda274ff4e0d74b29ae39349`.

Testing uses disposable preferences, generated files and explicitly labeled sample media. It does not capture audio, start the camera, send player commands, delete personal files, or close unrelated applications.

## Limits

This is a locally ad-hoc signed build, not Apple-notarized. The retained private media integration is not a public-API-only implementation. The visualizer does not analyze real audio. Rendering targets smooth native compositor animation; no measured 60/120 FPS guarantee is made. Physical multiple monitors, full-screen Spaces, a separate Mac mini, Intel execution, older macOS versions, and all permissioned live integrations require their respective environments.
