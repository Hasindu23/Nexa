# Nexa 0.3.0 validation

Tested on Apple Silicon, macOS 26.5.1, with Xcode 26.6 on 17 September 2026.

- **31 XCTest checks passed, zero failures.** Coverage includes privacy, data preservation, timers, media routing, playback rates, artwork reuse, animation interruptions, hover behavior, Reduce Motion, preference migration and notch-free geometry.
- Optimized native release smoke checks passed navigation, timer Start/Pause, file preservation, Settings, camera-off initialization and all three Home sizes.
- The same native smoke sequence passed with simulated notch-free display geometry. Mac mini preview images are in `Mac-mini-preview/`; this is not a physical Mac mini hardware test.
- Normal and notch-free Home layouts, the Timer screen and the collapsed floating pill were visually inspected.
- A read-only live browser media check passed. No playback commands were sent. Personal playback screenshots are not included in the repository.
- The repeated motion check passed eight open/close cycles, 24 rapid reversals and 12 widget changes, settling into the exact collapsed frame. See [motion measurements](MOTION-VALIDATION.md).
- Universal arm64 and x86_64 application and media-helper binaries were built. Only arm64 was executed here.
- Code-signature and disk-image checksum verification passed; this is local ad-hoc signing, not Apple notarization.

Native UI checks: [notched display](Screenshots/smoke-check.txt), [notch-free simulation](Mac-mini-preview/smoke-check.txt).

The built-in test display has a 209-point camera gap centered at X=855.5. The expanded panel is X=485, Y=0, width=741, height=208 points. Its compact state has equal 32-point side wings. The notch-free panel uses a 6-point top inset and a 170-by-30-point compact pill.

AppKit bitmap captures of inactive SwiftUI hosting views can omit text layers. Live-media screenshot QA activates its isolated test window before capture; no Screen Recording permission is requested.

Live camera capture, every media app/site, personal Shortcuts, AirDrop delivery, external monitors, Intel hardware and older macOS runtimes were not individually validated. See [limitations](LIMITATIONS.md).
