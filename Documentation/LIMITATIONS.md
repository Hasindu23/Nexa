# Known limitations and release boundaries

This is a runnable first version with original source and a modular implementation. It is not feature-equivalent to every commercial notch utility.

- **System-wide Now Playing:** Nexa now follows macOS Now Playing through a local, BSD-licensed MediaRemote Adapter. Brave browser media was detected and rendered in the running app on this Mac. Other browsers/native apps are supported when they publish Now Playing metadata; a website or player that does not publish it cannot be detected universally. Some players do not support seek/next/previous or provide artwork. The helper uses private APIs and can break after an OS update; Music/Spotify automation is the fallback. Automatic selection follows the system source; the source menu also allows running Music/Spotify. It is not an inventory of every media tab in every browser. The animated playback indicator is decorative, not an audio-level meter.
- **Camera:** AVFoundation video preview only, no recording or microphone. It starts on an explicit click, requires Camera permission, and stops on collapse, pause, module disable/exit and quit. Device discovery includes built-in, external and Continuity cameras where available. Permission-free lifecycle/idle behavior was tested; actual live camera frames and external cameras need the user's permission/hardware validation.
- **Shortcuts:** Listing uses Apple's local CLI, execution occurs only on Run/Home shortcut clicks. Shortcuts may require their own permissions or foreground input. Listing is bounded by a timeout; no personal shortcut was executed during QA.
- **Tray movement:** Multi-file staging, selection, copy/paste, Quick Look, AirDrop and individual drag-out are implemented. There is no special Option-drag move operation or multi-item drag session; original files are never deleted by Nexa. AirDrop peer delivery needs another device and was not sent during testing.

- **Bluetooth batteries:** Names and connection state work through IOBluetooth. AirPods left/right/case battery levels and generic headset battery telemetry are not implemented. This build never substitutes fabricated values. Actual accessory reconnection still needs hardware validation.
- **Display brightness and Focus:** These tiles open the appropriate Settings pane. There is no hidden brightness driver or unsupported Focus toggle. Wi-Fi and Bluetooth toggles likewise open native Settings; Wi-Fi power status is read without requesting location/SSID access.
- **Lock screen:** Direct lock needs Accessibility permission. Otherwise the control explains the standard Control-Command-Q shortcut. Nexa does not trigger an Accessibility permission prompt during startup.
- **Calendar:** Upcoming list and relative countdown are implemented; month-grid calendar is not. Click-to-open uses Calendar automation and can fail for changed/recurring provider UIDs. Permission denial and missing/default Reminders lists are handled. Live account data and remote sync were not used in automated tests.
- **Weather:** Open-Meteo-compatible provider (configurable HTTPS endpoint), manual coordinate entry/refresh, current conditions plus high/low. No WeatherKit entitlement, background geolocation or hourly graph. The free hosted service has non-commercial-use terms; configure a suitable licensed service before commercial distribution.
- **Assistant:** Optional, disabled by default, OpenAI only. Text must be pasted/typed and reviewed. No automatic selected-text capture, streaming, agent tools or local model. Actual API completion requires the user's own valid key and model access; no billed API call was made during validation.
- **Sharing:** Uses available native share services. AirDrop/Messages/Mail may not all appear for every content type or system configuration. A sharing action opens the system UI; the user chooses its destination.
- **Banners:** Timer, file added, copy-again, low battery, power connection changes, Bluetooth connect/disconnect and upcoming event banners are implemented. Download-complete detection is not implemented; there is no Downloads-folder watcher.
- **Displays and Spaces:** One overlay on the selected display, defaulting to a hardware-notch screen. Non-notch placement and multi-display origins have deterministic tests. All-Spaces/full-screen behavior uses public window collection flags; actual behavior depends on macOS, display arrangement and exclusive full-screen apps. Every arrangement was not physically tested. Small displays/layouts scroll module content.
- **Style:** Intentionally dark-only to blend with the notch. Five accent choices, opacity/blur, corner radius, border/shadow and three sizes are present. There is no separate light theme.
- **Persistence:** Notes, to-dos and favorite shortcuts persist locally; clipboard/shelf survive relaunch when configured. Timers/stopwatch and AI text are session-only. The shelf references originals; inaccessible or externally deleted files are labeled unavailable. Expiry removes references within the 15-minute housekeeping interval or on next open.
- **Updates:** User-configured, manual JSON release-feed check and release-page link. The public GitHub repository includes a release feed; no automatic binary replacement is implemented. Notarization, installer signing, automatic updater trust/signature infrastructure and App Store distribution are outside this local build.
- **OS/architecture validation:** Built and launched on Apple Silicon macOS 26.5.1 with a macOS 15 deployment target. The release can be built universal; Intel and macOS 15 need hardware/OS validation. CPU and memory measurements are a local sample, not guaranteed budgets.

## References used for platform choices

- [Apple: NSScreen auxiliary top areas](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc)
- [Apple: MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [Apple: EventKit access migration](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels)
- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
- [Apple: IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice)
- [OpenAI: text generation / Responses API](https://developers.openai.com/api/docs/guides/text)
- [Open-Meteo: forecast API and usage terms](https://open-meteo.com/en/docs)

Music/Spotify/Calendar commands were checked against locally installed scripting dictionaries where available. No commercial competitor source code or proprietary assets were used. MediaRemote Adapter is included with its BSD license and pinned source revision.
