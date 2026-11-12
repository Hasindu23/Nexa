# Architecture

Nexa is one native macOS application target and one XCTest target. The UI and services use native system frameworks. A vendored BSD MediaRemote Adapter builds into a framework, used by a local helper while media is connected. There is no background daemon, server, browser runtime, package manager dependency or license service.

## Composition and state

`AppDelegate` owns `AppModel`, a notch window controller and lazily created Settings/Welcome windows. `AppModel` composes independent services rather than making views own permission, persistence or network logic. Services publish narrowly scoped state through Combine; module views observe only the services they render. `PreferencesStore` holds a typed Codable value persisted in UserDefaults.

`ModuleID` is the module registry. Enabling/disabling a module changes navigation and activates/stops its background work. `ModuleLifecycle` defines start/stop for monitoring services. Timers use a deadline, not accumulated tick counts, to remain accurate when the main loop is delayed or the Mac sleeps. Disabling Timers suspends them. Pause Notch suspends capture/media/Bluetooth/calendar monitoring and hides the panel; an already running timer can still finish without a banner while paused.

## Overlay and focus

The borderless `NSPanel` uses `.nonactivatingPanel`. Hover calls `orderFront` and resizes without taking keyboard focus; clicking inputs can make it key. The panel physically shrinks when collapsed, avoiding a transparent expanded window intercepting clicks. Screen changes recalculate geometry from the hardware safe area and auxiliary top rectangles. The panel overrides normal window-frame constraints, uses status-bar level after setting its floating flag, and disables automatic hosting-view safe-area/sizing adjustments. Its center is the actual camera-gap center, with frame-width parity preserving centering after AppKit coordinate rounding. The header reserves the camera gap explicitly. Hardware-notch displays are preferred; otherwise the main display gets an adjustable pill. One overlay is shown, not one per display.

`NotchSurfaceView` keeps persistent expanded and compact hosting views at their final layout sizes. Core Animation morphs a shape mask and fades the content layers; the native window grows once at the start and shrinks once at the end instead of forcing layout on every animation frame. Interrupted shape transitions sample the same analytic spring trajectory used by Core Animation, preserving position and velocity. Opacity retargets from presentation layers; generation checks reject obsolete completion callbacks. Spring paths are sampled once at 120 Hz per transition, without a main-thread redraw timer. The top edge and hardware center remain fixed. Appearance changes update the existing surface without rebuilding its hosting views. Home uses a shallow 192–230 point height; detailed modules expand vertically. Motion and button feedback honor Reduce Motion.

Hover work is cancellable and checks the actual pointer position before acting, so tracking-area changes during expansion do not cause false exits. Menu tracking and attached sheets prevent unwanted collapse. Device, shelf and calendar refresh work is deferred until the opening animation settles; calendar reads on Home are throttled to 30 seconds. A local event monitor handles Escape, local swipe gestures and optional scroll navigation only for Nexa's window; no global input recording is used.

Widget crossfades are scoped to fixed-height content containers. Native inactive hosting views return no hit target, and only the expanded view owns the share picker. OS and app-level Reduce Motion settle in-flight native animations immediately. NexaMotion centralizes preset, speed, transition and feedback timings. Display choices use public ColorSync display identifiers, retaining compatibility with older display-name preferences. Detached islands reserve the menu-bar area. Controller teardown removes all screen/workspace observers and the local input monitor.

The compact and expanded masks retain the same path segment structure, following Apple's [CAShapeLayer path interpolation requirement](https://developer.apple.com/documentation/quartzcore/cashapelayer/path).

## Storage

- `UserDefaults`: configuration and onboarding completion.
- `~/Library/Application Support/Nexa/clipboard.json`: bounded local clipboard history.
- `~/Library/Application Support/Nexa/shelf.json`: file references, bookmarks and timestamps.
- `notes.json`, `tasks.json`, `shortcuts.json`: local notes, to-dos and pinned shortcut names.
- Keychain, service `app.nexa.api-key`: the user-provided OpenAI API key.

Storage writes are atomic. App-support directories use mode 0700 and data files 0600. File shelf actions never delete originals. Ordinary URL bookmarks improve resilience to file moves; the build is not App Sandbox confined. No temporary copy of shelf originals is created. Clipboard pinning survives deduplication; images are capped at 4 MB each and total payload is trimmed to approximately 32 MB. Unpinned history is evicted first. JSON/base64 overhead may exceed the payload budget.

## Integrations

`SystemMediaBridge` owns one streaming process, reads bounded newline-delimited JSON, decodes full snapshots and base64 artwork on its background reader queue, and applies generation checks to ignore stale callbacks. `NowPlayingService` prioritizes the system-selected player, preventing a paused Music track from replacing an active browser video. A one-second visible-only tick interpolates elapsed time using the reported playback rate; metadata is event-driven. Unchanged artwork and source labels are cached. Source-specific Music/Spotify AppleScript remains available as a fallback. Commands use fixed process argument arrays, not shell interpolation. Native metadata/artwork stay local; optional fallback Spotify artwork URLs obey Local-only mode.

`MirrorService` requests AVFoundation video permission only on an explicit start. A generation token cancels a pending permission/start when the panel closes. Device discovery and capture configuration/start/stop are serialized off the UI thread. Discovery on module entry is coalesced; permissioned starts revalidate the generation after asynchronous discovery. The preview layer is mirrored and has no recording output or microphone input. Module visibility, privacy pause and shutdown stop capture.

`NotebookService` persists notes/to-dos atomically. `ShortcutsService` lists and explicitly runs named Apple Shortcuts with argument arrays. Favorite names persist locally. No shortcut is executed by startup, discovery, or tests.

EventKit provides events and reminders. Calendar's scripting dictionary opens a clicked event by its external UID; a stale/missing match produces a visible message. Permission prompts are user-triggered. Reminder writes occur only on create/complete actions. Event banners are scheduled once per upcoming event rather than polled continuously.

IOKit power sources supply battery changes. Mach host statistics supply CPU/memory only while System is visible. CoreAudio controls the default output where its driver exposes volume/mute. IOPM assertions implement Keep Awake and are released when turned off or on normal termination. IOBluetooth uses connection notifications while enabled.

Quick Controls reads CoreAudio, Wi-Fi and login status on a serial background queue, then publishes changed values on the main actor. Repeated refreshes are coalesced, and generation checks discard reads superseded by user actions or shutdown.

Network calls use an ephemeral URLSession with no cookie jar or disk cache. Weather is manual. AI only sends the reviewable editor content after Send; response parsing walks all output items, including refusals. Changing privacy/module settings cancels optional in-flight work. A manual HTTPS JSON version check never installs code.

## Background cadence

| Work | Cadence |
| --- | --- |
| Idle overlay | No rendering loop or mouse polling |
| Clipboard, only when enabled | 1.5 seconds, 0.5-second tolerance |
| Media metadata | System event stream while connected |
| Playback position, only while visible | 1 second, 0.15-second tolerance; local interpolation |
| Playback pulse, only while playing and visible | Core Animation blue bars/wave/minimal; no per-frame SwiftUI timer; stopped on pause, hidden/occluded views, disabled hosts, Reduce Motion and energy saving |
| Camera | Only during explicit, visible Mirror use |
| System statistics, only while visible | 5 seconds, 2-second tolerance |
| Running timer/stopwatch | 1 second, stopped when idle |
| Shelf expiry | 15 minutes, 60-second tolerance, plus on open |
| Calendar | Event-store change and scheduled banners |
| Battery / Bluetooth | System notifications |
| Weather / AI / updates | Explicit user action |

These choices target low idle use; measured results and the limits of testing belong in VALIDATION.md. Background cadence is not a promise of a fixed resource budget on every Mac.

## 3.1 media compatibility exception

The user explicitly chose to retain the existing private MediaRemote bridge for system-wide media coverage. New appearance and motion code uses public APIs. Electric Blue is playback-state decoration and never reads microphone or system audio samples. Its ambient gradient is local compositor decoration, not a measured music-intensity visualization.
