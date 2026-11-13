# Native interaction review

The running 3.2 development app was inspected through macOS accessibility and a native window screenshot. Real clicks selected Files, selected Timers, started the timer (25:00, Pause timer shown) and paused it (24:57, Start timer shown). The review used an isolated QA store and did not activate calendar, camera, media transport or AI connections.

The in-process legacy click fixture depended on the 3.1 layout and could not reliably reach the new SwiftUI rail. Its service-driven navigation/render checks are retained and labeled accordingly; they are not reported as real mouse clicks. The external native interaction above verifies the actual controls.

The native screenshot showed translucent graphite material and a persistent floating rail. View-only PNG exports use an opaque backing and cannot prove wallpaper diffusion. Reference screenshots described in the brief were not attached.

## Installed release

After replacing `/Applications/Nexa.app`, normal icon launch and repeat launch showed one running 3.2.0/build 12 instance. Existing preference values, notes, tasks and storage records were preserved. The installed app was then inspected through native accessibility and a compositor screenshot: real rail clicks opened Files and Calendar and returned to Home. The floating rail remained visible, selected Files correctly and the charcoal material diffused its background. Calendar stayed disconnected; no permissions or media playback commands were triggered. The app was left running on Home. The installed UI screenshot was not added to the source archive because the live Home can show personal task/media metadata.
