<!-- Copilot / AI agent instructions for the Race Estimator repository -->

# Quick instructions for AI coding agents

This repository is a Connect IQ "data field" written in Monkey C targeting API 5.2.0+. The project builds a Race Estimator that predicts finish times for 9 running milestones with AMOLED burn-in protection. Use the notes below to be immediately productive when making changes.

- Primary language: Monkey C (files under `source/`, `gen/` contains generated Rez/mir files).
- Entry point: `manifest.xml` -> application `entry="RaceEstimatorApp"` which constructs `RaceEstimatorView` in `source/RaceEstimatorApp.mc` and `source/RaceEstimatorView.mc`.
- API Level: 5.2.0+ (uses nullable syntax, Lang.format, enhanced exception handling)
- Target devices: fenix 7/7S/7X series, Forerunner 255/265/955/965 (includes AMOLED devices)

## Key files to reference when editing or adding features

- `source/RaceEstimatorApp.mc` — application bootstrap; returns the initial DataField view.
- `source/RaceEstimatorView.mc` — core logic: milestone tracking, prediction engine, GPS validation, AMOLED burn-in protection, storage persistence, and rendering. Edit here for behavior changes.
- `manifest.xml` — Connect IQ manifest describing product targets (fenix 7+, FR 255+) and minApiLevel 5.2.0. No FitContributor permission needed.
- `resources/strings/strings.xml` — app name and label strings.
- `resources/drawables/drawables.xml` and `resources/drawables/*.png` — icons (LauncherIcon). Keep PNGs small and follow existing naming.
- `RaceEstimator_API5_Spec.md` — complete technical specification with AMOLED strategies, performance targets, and implementation examples.

## Scripts and test data

- Offline analysis and validation scripts (for example `analyze_fit.py`, `analyze_gpx.py`, and `validate_fit_anomaly_detection.py`) live in the repository root. Use these to validate FIT/GPX files and to reproduce anomaly-detection test cases.
- Example FIT/GPX files used during development are stored alongside the scripts (e.g. `19149997680_ACTIVITY.fit`, `activity_18264498522.gpx`).
- When adding new validation scripts or sample data, place them in a `scripts/` folder at the repo root and update `README.md` to reference them.

## Architecture and important conventions

- **DataField implementation**: Uses `WatchUi.DataField` (not SimpleDataField). Implements full layout control via `onLayout()` and `onUpdate()` for multi-row display.
- **9 unified milestones**: Mixed metric/imperial distances: 5K, 5MI, 10K, 13.1K, 10MI, HM (21.1K), 26.2K, FM (42.2K), 50K. Stored as centimeters in `mDistancesCm` array.
- **Zero-allocation compute()**: All arrays are pre-allocated in `initialize()`. The `compute()` method runs every second and must avoid dynamic allocations for battery efficiency. Cache display strings in `mCachedTimes` and `mCachedLabels`.
- **Rotating display window**: Shows 3 milestones at a time. When the first milestone is hit, the display rotates to show the next upcoming milestones. Controlled by `mDisplayIndices` array.
- **GPS validation**: Checks `currentLocationAccuracy` against `Position.QUALITY_USABLE` before computing predictions. Sets `mGpsQualityGood` flag.
- **Minimum distance check**: Requires 100m of elapsed distance before showing predictions (avoids wildly inaccurate early predictions).

## AMOLED burn-in protection (critical for FR 265/965)

- **Detection**: Check `System.getDeviceSettings().requiresBurnInProtection` to set `mIsAmoled` flag.
- **Color strategy**:
  - AMOLED: Black background, light gray text (not pure white), blue status (lower power than orange)
  - MIP: System theme colors, white text, orange status
- **Position shifting**: Subtle ±2 pixel vertical offset every 2 minutes (`POSITION_SHIFT_INTERVAL = 120`). Applied to all text rendering via `mPositionOffset`.
- **Content dimming**: Hit milestones (static content) rendered in darker gray (`mDimmedColor`) to reduce pixel wear. Predictions (dynamic) use normal brightness.
- **Implementation**: All rendering calls add `mPositionOffset` to Y coordinates and check `mIsAmoled` flag for color/dimming decisions.

## Storage and persistence (API 5.2.0)

- **Storage version 4**: Uses `Storage.setValue()` with dictionary containing version, times array, pointer, and checksum.
- **Checksum validation**: Simple sum-mod algorithm prevents corrupted data from loading.
- **State recovery**: `loadFromStorage()` runs on initialize, validates version/checksum, rebuilds display indices via `rebuildDisplay()`.
- **Clear on reset**: `onTimerReset()` calls `clearAllData()` which deletes storage and resets all state.

## Build, test and deploy notes (developer workflows)

- Building locally: this project targets the Garmin Connect IQ toolchain (Eclipse/Connect IQ or the standalone CLI). Typical flows:
  - Use Garmin Connect IQ SDK (via Eclipse or the `connectiq` CLI) to build a `.prg` from the workspace root. The `manifest.xml` and `source/` are required inputs.
  - Build command: `monkeyc -o bin/RaceEstimator.prg -f monkey.jungle -y ~/.Garmin/ConnectIQ/developer_key.der -d fenix7`
  - The repository contains pre-built binaries in `build/` for convenience.
- Side-loading: copy the generated `.prg` into the watch's `GARMIN/Apps` directory. On macOS use Android File Transfer or an MTP tool.
- Debugging: use `System.println("[RaceEst] ...")` lines in the code (see `compute()`, `saveToStorage()`, exception handlers) — the Connect IQ runtime shows these in the simulator/IDE console. When adding diagnostics, use the `[RaceEst]` prefix and avoid excessive logs inside tight loops.

## Project-specific patterns and gotchas

- **Avoid dynamic allocations**: All arrays (`mDistancesCm`, `mLabels`, `mFinishTimesMs`, `mDisplayIndices`, `mCachedTimes`, `mCachedLabels`) are allocated once in `initialize()`. Never use `.add()` or resize arrays at runtime.
- **compute() performance**: Called once per second by the platform. Keep logic O(DISPLAY_ROW_COUNT) = O(3). Heavy work affects battery and responsiveness.
- **Safe mode recovery**: If exceptions occur 3+ times consecutively, `enterSafeMode()` displays "ERROR" and pauses computation for 10 cycles to prevent crash loops.
- **Nullable types**: API 5.2.0 uses `Lang.Number?` syntax. Always null-check `info.timerTime`, `info.elapsedDistance`, `mFinishTimesMs[i]` before use.
- **Time formatting**: Use `Lang.format()` for strings (30% faster than concatenation). Format as "m:ss" for < 1 hour, "h:mm:ss" for ≥ 1 hour.

## When editing or adding files

- Reference existing naming patterns: class names end with App/View and resources use `Rez.Strings.*` mapping (see generated `gen/*/source/Rez.mcgen`).
- Keep resource IDs and string IDs stable — changing IDs will require updating generated Rez and manifest entries.
- Follow the existing exception handling pattern with specific catches for `Lang.UnexpectedTypeException` and a generic catch-all.

## Examples (copy these patterns when changing behavior)

- **Check AMOLED and update colors**:

  ```monkeyc
  var settings = System.getDeviceSettings();
  if (settings has :requiresBurnInProtection) {
      mIsAmoled = settings.requiresBurnInProtection;
  }

  if (mIsAmoled) {
      mBackgroundColor = Graphics.COLOR_BLACK;
      mForegroundColor = Graphics.COLOR_LT_GRAY;  // Not pure white
      mAccentColor = Graphics.COLOR_BLUE;
  }
  ```

- **Apply position offset for burn-in prevention**:

  ```monkeyc
  dc.drawText(mCenterX, yPos + mPositionOffset, Graphics.FONT_SMALL, text, ...);
  ```

- **Validate GPS before computing**:

  ```monkeyc
  if (!validateGpsData(info) || !validateMinimumDistance(info.elapsedDistance)) {
      return;
  }
  ```

- **Save state with checksum**:

  ```monkeyc
  var data = {
      "v" => STORAGE_VERSION,
      "times" => mFinishTimesMs,
      "checksum" => calculateChecksum(mFinishTimesMs)
  };
  Storage.setValue(STORAGE_KEY, data);
  ```

## Editing existing content

- `gen/` and `bin/` contain generated and build artifacts; don't edit them directly. Edit `source/` and `resources/*`.
- Legacy implementation removed: historical legacy sources were removed from `source/`. Use `source/RaceEstimatorApp.mc` and `source/RaceEstimatorView.mc` for the current implementation.

## Performance targets (API 5.2.0)

- Memory: ~10.9KB total (code + resources + runtime data)
- compute(): ~17ms per call (runs every second)
- onUpdate(): ~24ms per call (rendering)
- Battery: ~2.2%/hour during active use
- Storage: ~200 bytes used of 16KB available

## Documentation
- All documentation should reside in the `docs` folder.

If anything in these notes is unclear or you need CI/build commands, tell me what environment (Eclipse vs connectiq CLI) you use and I will add exact commands and examples for building and running the simulator.