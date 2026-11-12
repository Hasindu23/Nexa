# Nexa 3.1 upgrade plan

This is an incremental upgrade of the existing 0.6.0 source to the requested Nexa 3.1 Fluid Motion & Electric Blue release. Work is isolated on `codex/nexa-3.1-fluid-blue`, based on `77f43ec`.

## Existing architecture inspected

- Entry point: `AppDelegate` / `NexaMain`; `AppModel` owns module services.
- Window lifecycle: `NotchWindowController`, a nonactivating AppKit panel, cancellable hover work, display/Space notifications and single-instance reopen support.
- Rendering: `NotchSurfaceView` retains compact and expanded hosting trees and final widget layouts; shape masks and opacity animate in Core Animation.
- Media: `NowPlayingService` and `SystemMediaBridge`, with Music/Spotify AppleScript fallback. Existing system-wide support uses the vendored BSD MediaRemote Adapter.
- Preferences: typed Codable preferences merged over defaults in the existing `preferences.v1` key. Saved notes, tasks, shelf and other user data retain their current paths.
- Existing storage, memory, privacy, media, geometry and interaction tests remain in the project.

## Upgrade sequence

1. Add centralized motion policy, presets, speed, app-level Reduce Motion and energy saving; preserve old preferences.
2. Add velocity-preserving spring trajectories to existing native masks, with exact resting geometry and no per-frame window resizing.
3. Add Electric Blue bars, wave and minimal decoration using compositor layers, optional royal-blue glow, no audio capture and no misleading audio-analysis claims.
4. Add Appearance & Motion settings and matched module selection feedback; preserve working modules and transports.
5. Improve detached-display placement and display selection; run automated, native UI, idle-resource and packaging checks.

## Explicit user decision

The brief's public-API-only rule conflicts with existing system-wide media functionality. The user chose: **“Keep existing system-wide integration; accept the private-API exception.”** The existing MediaRemote bridge is retained. No new private APIs or audio-capture mechanism are added.

The pasted attachment contained no reference screenshots. The implementation uses its explicit hex palette and motion ranges, with original native components.

## Preservation and release contract

Keep bundle ID `app.nexa.mac`, existing local signing configuration, entitlements, permissions, module preferences and user data. Store new settings in the existing preference record. Keep Storage Cleaner confirmation/protection rules unchanged. Build and test locally; do not publish a new GitHub release as part of this request.

Never claim measured FPS from a main-loop heartbeat. Physical multi-display transitions, full-screen Spaces, older macOS and Intel execution, real player integrations, and Apple notarization are separate verification gates.
