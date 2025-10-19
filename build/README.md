# Race Estimator Pre-Built Binaries

Choose the appropriate `.prg` file for your device and copy it to your watch's `GARMIN/Apps` directory.

## Available Binaries

### Fenix 7 Series

- **RaceEstimator-fenix7.prg** (104KB)
  - Fenix 7
  - MIP display

- **RaceEstimator-fenix7pro.prg** (104KB)
  - Fenix 7 Pro
  - MIP display

### Forerunner Series

- **RaceEstimator-fr255s.prg** (104KB)
  - Forerunner 255S
  - MIP display

### Future Support

**Fenix 8X**: Support will be added once the device becomes available in the Connect IQ SDK.

## Installation Instructions

### macOS

1. Install [Android File Transfer](https://www.android.com/filetransfer/)
2. Connect your watch via USB
3. Open Android File Transfer
4. Navigate to `GARMIN/Apps`
5. Copy the appropriate `.prg` file
6. Disconnect your watch

### Windows

1. Connect your watch via USB
2. Open File Explorer
3. Navigate to your watch drive → `GARMIN/Apps`
4. Copy the appropriate `.prg` file
5. Safely eject your watch

## Features

- **Real-time predictions** for 9 running milestones (5K, 5MI, 10K, 13.1K, 10MI, HM, 26.2K, FM, 50K)
- **Dynamic finish time calculation** - updates as your pace changes
- **5-second moving average** - smooths GPS noise for stable predictions
- **GPS validation** - waits for good signal quality before showing estimates
- **Persistent state** - saves progress if you pause/resume
- **Zero-allocation performance** - optimized for battery efficiency

## Usage

1. Add as a data field in any running activity
2. Best viewed in 1-field layout for maximum visibility
3. Wait for GPS lock and 100m distance
4. After 5 seconds, predictions will appear
5. Watch estimates update dynamically as you run!

## Version

Current version: 1.0.0 with moving average smoothing
