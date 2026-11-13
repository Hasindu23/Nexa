# Visual review

Reviewed native view exports for Ambient, Peek, Home, all 18 workspaces, Storage Cleaner and Memory, Settings, all three Electric Blue visualizers, Classic Black, Liquid Glass styles, Energy Saving, Reduced Motion, simulated Reduce Transparency/Increase Contrast, and notched/notch-free geometry. The Light appearance review caught a washed-out material; the containing native panel now explicitly retains Dark Aqua, with a regression test and refreshed captures in both system appearances.

| Brief review question | Observed result and limit |
| --- | --- |
| Coherent large workspace | Shared header, content margins and persistent dimensions across workspaces; Home uses four default cards. |
| Connected to the notch | Notched geometry uses continuous shoulders and a flush top; the detached layout uses fully rounded top corners below the menu bar. |
| Spatially attached rail | Small consistent gap, capsule navigation and one blue selected item. Native clicks were verified separately. |
| Smooth workspace changes | Outer frame stays stable and the regression test observes no window resize on module switches. No claim of superiority to a competitor or guaranteed FPS. |
| Useful Home density | Default music/system/calendar/tasks fit in the standard workspace. Compact and edited layouts scroll; Wide uses three columns. |
| Calendar use of space | Daily schedule and month grid share the workspace; missing Calendar permission has an explicit connect state. |
| AI clarity | Nexa Assistant shows its real request lifecycle. External agents are explicitly disconnected, with no fabricated approvals. |
| Wallpaper contribution | The native app was visually inspected with translucent graphite material. View-only PNG exports have an opaque backing and sometimes omit native glass compositing, including parts of the rail after appearance changes; they cannot establish wallpaper diffusion. |
| Nexa identity | Original wording, existing waveform brand and SF Symbols; charcoal with restrained Electric Blue selection/status accents. |
| Blue vs reference purple | Blue is concentrated on controls and status. No competitor screenshots were attached, so a direct reference comparison or claim of a better result is unavailable. |

Native screenshot review is a layout check, not proof that every transition frame is artifact-free. Physical multiple displays, full-screen Spaces and refresh-rate comparisons remain separate hardware checks. No camera, microphone or private-data connection was enabled for the visual fixtures.
