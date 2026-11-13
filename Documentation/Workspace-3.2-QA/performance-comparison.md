# Measured release UI scenarios

Measured locally on Apple Silicon, macOS 27.0, with release builds from Xcode 27.2. Each scenario settles for two seconds, then samples process CPU and physical memory footprint for roughly 12 seconds. The 3.1 baseline uses the same isolated harness. These are short, single-run observations, not controlled performance guarantees.

| Scenario | 3.1 CPU, % of one core | 3.2 CPU, % of one core | 3.1 end footprint, MiB | 3.2 end footprint, MiB |
| --- | ---: | ---: | ---: | ---: |
| collapsed | 0.025 | 0.098 | 28.6 | 33.8 |
| peek | N/A | 0.005 | N/A | 33.9 |
| workspace | 0.061 | 0.004 | 28.8 | 34.0 |
| music-paused | 0.492 | 0.007 | 34.5 | 38.2 |
| visualizer-playing | 0.192 | 0.023 | 34.5 | 38.2 |
| drag-target | 0.226 | 0.010 | 36.1 | 39.2 |
| ai-workspace | 3.492 | 0.007 | 43.3 | 40.5 |
| calendar | 5.607 | 0.005 | 43.9 | 44.5 |
| switching | 34.258 | 39.437 | 92.9 | 100.0 |

CPU measures this process only. Core Animation can animate on the system compositor, so low process CPU does not mean zero rendering cost. The final 3.2 samples record window visibility and repeating visualizer-layer counts. The visualizer sample uses labeled sample media, not audio capture. Music playback transport, active network/AI requests, actual file dragging and calendar sync are not benchmarked. The drag target and AI workspace are isolated UI states; rapid switching requests ten changes per second. 3.1 has no Peek state.

A separate 60-second closed/paused sample and interruption stress test are recorded below. Main-loop heartbeat timing is not display FPS; rendered 60/120 Hz performance and physical external displays still need hardware validation.

```text
MEASURED: isolated paused/closed island idle CPU 0.099% of one core over 61.0 seconds
MEASURED: physical memory footprint before/after idle 143475768 / 80053304 bytes
LIMIT: resource sample is this isolated test process; live integrations, 120 Hz rendering, full-screen Spaces and physical multiple displays need hardware testing
PASS: 8 full open/close cycles, 24 rapid reversals, 12 widget changes settled into the exact collapsed camera frame.
Native window resize notifications: 36
Main-loop heartbeat samples: 1264
Heartbeat p95 interval: 9.27 ms
Longest main-loop heartbeat interval: 50.12 ms
Heartbeat intervals over 33.3 ms: 2
Measurement is main-loop responsiveness, not rendered display FPS. No private data, camera or playback commands used.
```
