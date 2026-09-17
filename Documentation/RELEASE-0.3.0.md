# Nexa 0.3.0 — final polish release

17 September 2026

## What changed

- Continuous notch-shape animation with a small content lift, smooth fades and reliable reversal when the pointer moves quickly.
- Faster default hover response: 140 ms to open, 420 ms before closing. Existing custom delays remain unchanged; only the previous defaults migrate.
- The waveform menu's Open action preserves the opening animation.
- Opening expanded at launch waits briefly for the first display pass. Native screenshot checks activate the isolated test window so AppKit captures all hosted text layers.
- Displays without a notch, including a Mac mini's display, use a rounded floating panel with adjustable horizontal position.
- Widgets and the Home center panel crossfade without fading the entire header. Navigation, media and Mirror buttons have subtle press feedback; unavailable buttons appear dimmed.
- Inactive native hosting views cannot steal clicks. A single share-picker owner prevents duplicate presentations.
- Changing Reduce Motion settles any active native transition immediately. No decorative playback animation runs when disabled or hidden.
- Audio-device, Wi-Fi and login-status reads run on a background queue. Stale reads cannot overwrite newer actions or shutdown state.
- Media JSON/base64 decoding is off the main loop. Artwork and source labels are reused when unchanged. Delayed results are rejected after source changes or disconnection, and browser playback rates are retained for elapsed-time display.
- Animation appearance changes keep the hosting tree intact. Observer cleanup prevents old controllers from retaining input monitors.

## Verification

All 31 XCTest checks passed on Apple Silicon running macOS 26.5.1. Tests cover the motion and pointer cases above, Reduce Motion, timing migration, background query cancellation, media decoding/routing, artwork reuse, data preservation, privacy defaults, camera-off initialization and the notch-free panel used on a Mac mini's display.

The optimized native release passed button/navigation smoke checks and the motion stress sequence. See [validation](VALIDATION.md), [motion measurements](MOTION-VALIDATION.md), `Screenshots/smoke-check.txt`, `package-verification.txt` for the final records.

## Boundaries

The package contains arm64 and x86_64 code; only Apple Silicon was run here. It is locally signed, not Apple-notarized. Camera capture still needs an explicit Mirror click and permission; live camera capture was not forced during QA. Media support requires the source to publish macOS Now Playing data and the private MediaRemote interface to remain compatible. Every app/site, external monitor, personal Shortcut, AirDrop destination and older macOS version has not been individually tested.

These checks support the fixes described above; they are not a guarantee that all possible interactions are bug-free or a measurement of rendered display FPS.
