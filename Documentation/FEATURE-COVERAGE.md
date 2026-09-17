# NotchNook research → Nexa 0.2.0

Checked 16 September 2026. Nexa implements its own interface and behavior; no NotchNook source, branding, screenshots or packaged assets are embedded in the app.

## What the research established

The [ScreenCastsONLINE walkthrough](https://www.screencastsonline.com/tutorials/utilities/notchnook) documents media, Shortcuts, Mirror, Calendar, Notes, Tray and settings, including preview/open/AirDrop file actions. [Macworld's review](https://www.macworld.com/article/2406934/notfhnook-macbook-dynamic-island-widgets-files-tray.html) describes the horizontal widget arrangement and webcam mirror. These corroborate the supplied visual references.

A [July 2026 public update post](https://www.reddit.com/r/MacOSApps/comments/1upcyfk/notchnook_just_got_one_of_its_biggest_updates_yet/) additionally describes timers, favorite/completed/archived to-dos, multiple media sources, a scrubber, battery/Bluetooth activities, persistent multi-file staging and Option-drag moves. The author's identity was not independently verified; this is supplemental feature evidence, not a verified official release specification.

The [developer website](https://lo.cafe/notchnook) returned `DEPLOYMENT_DISABLED` during this research. Therefore a complete current official feature inventory could not be verified. No unofficial software download or license site was used. Feature coverage below distinguishes working implementation from remaining differences.

## Coverage

| Feature | Nexa 0.2.0 |
| --- | --- |
| Notch-aligned, shallow horizontal dashboard | Implemented: concave top shoulders, rounded lower corners, 3 sizes, reserved camera gap, Home/Tray navigation |
| Smooth opening/collapse, hover, click, gestures | Implemented: coordinated resizing/fades, configurable timing, optional haptics, local swipe/scroll gestures, Reduce Motion support |
| Media across native apps and websites | Implemented for players that publish macOS Now Playing; automatic active-source selection plus Music/Spotify selection/fallback |
| Media artwork, controls, position | Implemented: local system artwork, previous/play/pause/next, draggable seek bar, volume, decorative playing indicator |
| Browser movie replacing a paused Music track | Live-verified with Brave; the native Nexa panel rendered the browser's current media |
| Camera mirror | Implemented: circular preview, click to start/stop, camera selection, auto-stop when hidden; actual live capture awaits user Camera permission |
| Calendar | Implemented: Home week strip/upcoming event, EventKit list, event opening and upcoming-event alerts |
| Apple Shortcuts | Implemented: list, favorite, click to run/stop, two favorite buttons on Home |
| Notes | Implemented: local editor, autosave, multiple notes, pin/delete |
| To-dos | Implemented: create, favorite, complete, restore, delete; completed items automatically appear in Archive after 24 hours |
| Timer | Implemented: presets/custom timer, stopwatch, pause/reset, Home timer and completion banner |
| Persistent Tray and multi-file drop | Implemented: local bookmarks, original-file references, deduplication, expiry, selected-file copy and AirDrop |
| File preview, sharing, paste and AirDrop area | Implemented: Quick Look preview, Finder reveal, copy/paste files, native sharing, direct AirDrop drop area |
| Drag out / Option-drag move | Individual drag-out implemented. Special Option-drag moving and multi-item drag-out sessions are not implemented |
| Battery/Bluetooth activities | Implemented: low battery/power connection changes and optional Bluetooth connect/disconnect banners |
| Display/layout customization | Implemented: display selection, non-notch fallback, accent/size/corners/opacity/shadow, center widget selection, module toggles |
| Additional Nexa modules | Clipboard history, Reminders integration, quick controls, system stats, optional Weather and user-key AI remain available |

This is coverage of the documented feature families, not a claim of complete commercial-app parity. Differences also include lack of full month-calendar navigation, arbitrary browser-tab source enumeration, proprietary workflows, and bespoke gestures from every NotchNook version. Hardware-specific behaviors, AirDrop delivery and user Shortcuts need their corresponding devices/permissions to validate.

## Platform implementation sources

- [MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter): BSD 3-Clause local bridge for modern macOS system Now Playing, included from a pinned source revision. Uses private Apple media APIs; OS updates can affect support. The source/license are under `ThirdParty/` and the license ships inside the app.
- [Apple: AVFoundation camera sample](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app): native capture sessions and user-authorized camera access.
- [Apple: running Shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac): local listing and explicit execution.

See [validation](VALIDATION.md), [privacy](PRIVACY.md) and [limitations](LIMITATIONS.md) for the exact testing and permission boundaries.
