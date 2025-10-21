# Race Estimator

Race Estimator is a compact Garmin Connect IQ data field that predicts finish times for nine common race milestones in real time and surfaces three concise predictions on-screen. It's designed for accuracy, low CPU/battery use, and safe rendering on both MIP and AMOLED devices.

Why use it

- Provides continuously-updating finish time estimates for milestones (5K, 10K, half, marathon, etc.) while you run.
- Shows only the most relevant information: three milestone predictions at a time with a simple status line.

Highlights — what the data field does

- Inputs: GPS-derived elapsed distance and timestamps (Activity.Info), optional user profile for unit conversions.
- Outputs: up to three milestone predictions formatted as time-to-finish (m:ss or h:mm:ss) and a short status (WAITING GPS, WARMUP, PREDICTING, FINISHED).
- UI: compact 3-row display designed for single-field layouts; AMOLED-safe colors and periodic position shifts to reduce burn-in.
- Behavior: predictions start after a short warmup (requires ≥100 m of distance and a smoothing window). As milestones are hit the display rotates to the next upcoming milestones.
- Constraints: compute() is optimized to avoid dynamic allocations and run every second; avoid heavy work in onUpdate().
- Edge cases handled: GPS accuracy checks, minimum-distance gating to avoid wildly inaccurate early predictions, FIT anomaly detection (distance stagnation and pace spikes), and time-skip mitigations.

Recent changes (2025-10-21)

- Dynamic milestone centering: milestone label+time pairs are now centered as a single group based on the display width (no absolute X offsets). This makes the UI consistent across different screen sizes and resolutions.
- Increased spacing between milestone label and time for improved readability (30px padding between elements).
- Vibration feedback on milestone completion: the watch now emits a short tactile pulse when a milestone is reached. Vibration is implemented inside `MilestoneManager` so the celebration logic and UI remain separated.

Key facts

- Runtime manifest minApiLevel: 5.0.0
- Recommended development SDK: 5.2.0+ (source uses nullable types, Double literals, and modern Monkey C conveniences)
- Storage version in source: `STORAGE_VERSION = 4`

Quick start — install a prebuilt binary

1. Open `build/` and pick the binary that matches your device (e.g., `RaceEstimator-fenix7.prg`, `RaceEstimator-fr255s.prg`).
2. Copy the `.prg` to your watch `GARMIN/Apps` folder (macOS: use Android File Transfer or MTP tool).

Build from source (developer)

- Requirements: Garmin Connect IQ SDK (recommended 5.2.0+), `monkeyc` CLI, and your Connect IQ developer key.
- Example build commands (replace device id where shown):

```bash
# Build for fenix7
monkeyc -o bin/RaceEstimator-fenix7.prg -f monkey.jungle \
  -y ~/.Garmin/ConnectIQ/developer_key.der -d fenix7

# Build for fr255s
monkeyc -o bin/RaceEstimator-fr255s.prg -f monkey.jungle \
  -y ~/.Garmin/ConnectIQ/developer_key.der -d fr255s

# Build for venu2plus
monkeyc -o bin/RaceEstimator-venu2plus.prg -f monkey.jungle \
  -y ~/.Garmin/ConnectIQ/developer_key.der -d venu2plus
```

Developer key (important)

- Never commit your developer key.
- Recommended location: `~/.Garmin/ConnectIQ/developer_key.der` (the `-y` flag accepts a path).
- Secure the key: `chmod 600 ~/.Garmin/ConnectIQ/developer_key.der`
- For CI: store the DER file as a secret and write it into `~/.Garmin/ConnectIQ/` during the job, then remove it.

Usage (on the watch)

1. Add the "Race Estimator" data field to a running activity screen.
2. Use a 1-field or compact layout for best visibility.
3. Wait for GPS lock; the data field requires ≥100 m of recorded distance and a short smoothing window before stable predictions appear.

Supported / tested targets

- See `manifest.xml` for the authoritative product list. Common targets used during development and testing include:
  - Fenix 7 family (fenix7, fenix7pro, fenix7s, fenix7x, ...)
  - Fenix 8 family (selected Pro/solar variants)
  - Forerunner 255 series (fr255, fr255m, fr255s)
  - Venu 2 Plus (AMOLED)

Why 5.2.0+ as recommended SDK?

- The project uses modern Monkey C features (nullable types, Double literals, Lang.format) that are more ergonomic on SDK 5.2.0+. The manifest minApiLevel remains 5.0.0 so runtime compatibility is preserved.

Troubleshooting

- "Unable to load private key: ${workspaceFolder}/developer_key": make sure `monkeyC.developerKeyPath` in your editor points to `~/.Garmin/ConnectIQ/developer_key.der` or pass `-y <path>` to `monkeyc`.
- Permission denied reading the key: ensure `chmod 600` is set and the file is readable by you.
- Build fails for a device: verify the device id passed to `-d` matches an id in `manifest.xml` or change the target in `monkey.jungle`.
- Simulator logs: use `System.println("[RaceEst] ...")` in source to print messages in the simulator/IDE console.

Where to look next (short)

- Core logic and behavior: `source/RaceEstimatorView.mc`
- App bootstrap: `source/RaceEstimatorApp.mc`
- Runtime targets and minApiLevel: `manifest.xml`
- UI/arc design: `docs/race_estimator_arc_specification.md`

Testing & validation

- The project includes validation scripts under `scripts/` (FIT/GPX analysis) and some prebuilt test binaries under `build/`.

Contributing (quick rules)

- Avoid allocations in `compute()` and other hot paths.
- Gate debug logs behind a `DEBUG` flag.
- Test on both MIP and AMOLED devices when changing rendering.
- Bump `STORAGE_VERSION` when you change persistent storage layout and include a migration plan.

License

- This project is licensed under the MIT License — see `LICENSE`.

If you'd like, I can also add a short CONTRIBUTING.md and a CI build example that injects the developer key from secrets.
