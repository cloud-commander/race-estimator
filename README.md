# Race Estimator

Race Estimator is a Garmin Connect IQ data field that predicts finish times for nine running milestones in real time. The manifest declares minApiLevel 5.0.0, and the source uses newer Monkey C language features (nullable types, Double literals, Lang.format). Recommended development SDK: 5.2.0+ to match the language features used by the source and simplify contributor workflows. The project is optimized for battery, memory, and AMOLED safety.

## Highlights

- Predicts 9 unified milestones: 5K, 5MI, 10K, 13.1K, 10MI, HM, 26.2K, FM, 50K
- Shows 3 milestones at a time and rotates as you hit them
- Exponential smoothing (EMA, α=0.15) for stable predictions
- FIT anomaly detection (distance freeze + pace spike) and time-skip handling
- AMOLED burn-in protection: black background, dimmed static content, subtle position shifts
- Zero-allocation compute() hot path and defensive storage (STORAGE_VERSION = 5)
 - Zero-allocation compute() hot path and defensive storage (STORAGE_VERSION = 4)

## Quick Install (side-load)

1. Build artifacts are available in the `build/` directory. Choose the binary matching your device:

   - `build/RaceEstimator-fenix7.prg`
   - `build/RaceEstimator-fenix7pro.prg`
   - `build/RaceEstimator-fr255s.prg`

2. Copy the `.prg` file to your watch `GARMIN/Apps` folder (use Android File Transfer on macOS)

## Build from source

Requires the Garmin Connect IQ SDK and your developer key (see below):

```bash
# Clone the repository (use the current repo URL or your fork)
git clone https://github.com/stirnim/garmin-lastsplit.git
cd garmin-lastsplit

# Example: build for fenix7
monkeyc -o bin/RaceEstimator.prg -f monkey.jungle \
  -y ~/.Garmin/ConnectIQ/developer_key.der -d fenix7

# Copy to watch
cp bin/RaceEstimator.prg /Volumes/GARMIN/GARMIN/Apps/
```

## Developer Key (Required)

- **Never commit your developer key.**
- Store your Connect IQ developer key at `~/.Garmin/ConnectIQ/developer_key.der` (or .pem if required).
- Restrict permissions:
  ```bash
  chmod 600 ~/.Garmin/ConnectIQ/developer_key.der
  ```
- Add any local or test keys to `.gitignore`.
- The build commands above reference only the global key path.

For CI/CD: inject the key at build time using your CI provider's secret store, and clean up after the build.

## Usage

1. Add the "Race Estimator" data field to a running activity screen
2. Use a 1-field layout for best visibility
3. Wait for GPS lock (status: "WAITING GPS") and run ≥100m (status: "WARMUP")
4. Predictions appear once the smoothing window (5s) and minimum distance (100m) are met

## Supported Devices

Manifest minApiLevel: 5.0.0 (see `manifest.xml`). Recommended development SDK: 5.2.0+.

Devices declared in the manifest (explicit product ids):

- Fenix 7 series: `fenix7`, `fenix7s`, `fenix7x`, `fenix7pro`, `fenix7spro`, `fenix7xpro`
- Fenix 8 family: `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm`
- Forerunner 255 series: `fr255`, `fr255m`, `fr255s`
- Venu 2 Plus: `venu2plus`

Note: AMOLED-specific rendering and burn-in mitigations apply to AMOLED devices in the manifest (for example, Venu 2 Plus and some Fenix 8 Pro variants).

## Technical notes

- Manifest minApiLevel: 5.0.0
- Recommended development SDK: 5.2.0+ (source uses nullable and Double features)
- Storage version in source: `STORAGE_VERSION = 4`
- Smoothing: EMA α=0.15 (recommended)
- Warmup: 5s smoothing window + 100m minimum distance (~40-80s before predictions)
- Performance: compute() ≈ 17ms, onUpdate() ≈ 24ms, memory ≈ 11KB

## Files of interest

- `manifest.xml` — authoritative product list and minApiLevel used by the runtime
- `source/RaceEstimatorView.mc` — core logic: smoothing, anomaly detection, rendering, storage
- `source/RaceEstimatorApp.mc` — application bootstrap and entry point
- `monkey.jungle` — `monkeyc` build descriptor used by the SDK/CLI
- `resources/` — drawables and strings used by the data field
- `docs/race_estimator_arc_specification.md` — UI/arc integration spec
- `Garmin_DataField_RaceEstimator_prompt.md` — design notes and internal prompt/spec
- `.github/copilot-instructions.md` — contributor-focused guidance and project notes
- `build/` — pre-built binaries for some target devices (`RaceEstimator-fenix7.prg`, `RaceEstimator-fr255s.prg`, etc.)
- `validate_fit_anomaly_detection.py` — validation suite (9 scenarios)
- `SIMULATOR_TIME_SKIP_TESTING.md` and `TIME_SKIP_FIX.md` — time-skip handling docs

## Testing & Validation

- 9/9 validation scenarios passing (normal GPS, FIT freeze, pace spikes, mixed anomalies)
- Real activity validated: `activity_18264498522.csv` (28.01 km, 3:14:30)

## Contributing

Please follow project conventions:

1. Avoid dynamic allocations in `compute()` and `onUpdate()`
2. Gate debug `System.println()` logs behind a `DEBUG` flag
3. Test changes on both MIP and AMOLED devices
4. Keep `STORAGE_VERSION` in sync when changing storage schema

## License

See `LICENSE` for details.
