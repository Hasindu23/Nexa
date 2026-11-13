# Nexa 3.2 — Liquid Glass Workspace

Version 3.2.0, build 12. macOS 15 and later. Bundle identifier remains `app.nexa.mac`.

## New in 3.2

- Ambient, Peek and Workspace states share the original continuous spring geometry and persistent native hosts. Hover opens Peek; click opens Workspace. Module changes keep the outer frame and rail stable.
- Native `NSGlassEffectView` on macOS 26+, with `NSVisualEffectView` on macOS 15, Classic Black, tint/style controls, reduced transparency, increased contrast and energy saving.
- Floating navigation rail with one matched selection indicator, drag reorder, hiding, overflow and keyboard navigation.
- Home widgets with Compact, Regular and Wide sizes, reorder, hide, add and reset. Unavailable measurements show a dash.
- Local Tasks due dates, Today/Upcoming/Completed views and a focused task. Existing tasks and notes migrate without losing content.
- Live Activities from Nexa timers, file imports, image exports, storage operations and explicit Assistant requests. No fabricated remote agents or progress percentages. Terminal states expire after five minutes.
- PNG/JPEG image export to a new, user-chosen file. Original and existing destination files are preserved; JPEG flattens transparency onto white. Work runs off the interface thread.
- Optional global shortcuts registered through the public macOS hotkey API. None are assigned by default. Conflicts show an error. No global typing monitor.
- Per-display entry points, with one active workspace moved to the chosen display. Displays without a cutout use a slim handle. Existing display identifiers and names remain accepted.
- File-only drag activation near the top center; ordinary pointer movement is unaffected.

## Redesigned or extended

Music keeps real media controls, artwork, source selection, scrubbing and the decorative Electric Blue Bars/Wave/Minimal visualizer. Calendar adds a month grid and daily schedule; EventKit reads now run on a background queue and return immutable event metadata. Files unifies the existing shelf/Tray as a temporary Pocket of references, adds background metadata and conversion, and never copies large originals just to hold them. Clipboard privacy and pinning remain unchanged. The Assistant shows the real Nexa request state and elapsed time; external Codex/Claude sessions and approvals are **not connected**.

Timer now exposes Focus and Break presets using the existing single timer and stopwatch. A Nexa volume change can show a compact measured status; external brightness keys are not intercepted. Mirror discovery stays off-main, and opening its workspace does not start capture. Storage Cleaner and Memory tools retain their existing operation logic, review, confirmation, protected paths, recovery and history. No RAM boosting or automatic cleanup was added.

## Preserved state and security

Existing bundle identity, signing workflow, data paths, privacy choices, display identifiers and saved content are preserved. New preferences merge over defaults; unknown new enum values do not reset old choices. New functionality uses public APIs. The previously approved private MediaRemote exception remains unchanged. No microphone, Screen Recording, telemetry, clipboard sync or automatic command approval was added.

## Deliberate scope limits

No Terminal replacement, Prompter, lyrics, private browser download scraping, remote agent approvals or unsupported GPU/temperature estimates are shown. The supplied text refers to competitor screenshots but no such images were attached to this 3.2 brief, so direct reference-image comparison is unavailable. Nexa uses original text, SF Symbols and its existing assets.

## Validation

See `Workspace-3.2-QA/verification.json` and the accompanying reports for the final executed checks and actual measurements. Native view exports verify content/layout; they do not capture the desktop compositor's wallpaper diffusion or establish display FPS. Accessibility screenshots use isolated test overrides, leaving system preferences unchanged.

Physical external-display hotplug, fullscreen Spaces on every display, Intel execution, macOS 15/26 runtime, live calendar permissions, camera hardware and connected external media/AI transport require separate environment testing. Simulated geometry, accessibility fallback and isolated session behavior are tested locally.

This build is locally ad-hoc signed, not Apple-notarized. It is not a guarantee of zero defects or a performance multiplier.
