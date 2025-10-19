# Race Estimator

Race Estimator - a Garmin [Connect IQ](https://developer.garmin.com/connect-iq/overview/) data field for real-time race finish time predictions.

## Features

Race Estimator predicts your finish times for 9 running milestones during your activity, combining metric and imperial distances:

- **5K** (5 kilometers)
- **5MI** (5 miles)
- **10K** (10 kilometers)
- **13.1K** (13.1 kilometers)
- **10MI** (10 miles)
- **HM** (Half Marathon - 21.1 km)
- **26.2K** (26.2 kilometers)
- **FM** (Full Marathon - 42.2 km)

### Key Features

- **Dynamic finish time predictions**: See estimated finish times that update as your pace changes
- **5-second moving average**: Smooths GPS noise for stable, reliable predictions
- **Rotating display**: Shows 3 upcoming milestones at a time; automatically rotates as you hit each one
- **GPS validation**: Waits for good GPS quality before showing predictions
- **Persistent state**: Automatically saves and restores your progress if you pause/resume
- **Zero-allocation performance**: Optimized for battery efficiency (~2.2%/hour)
- **Full-screen layout**: Best viewed in 1-field layout for maximum visibility

## Supported Devices

- **Fenix 7** - Standard and Pro models
- **Forerunner 255S**
- **Fenix 8X** - Coming soon (once available in Connect IQ SDK)

## Installation

### Option 1: Side Loading (Recommended)

1. Download the appropriate pre-built binary for your device from the `build/` directory:

   - `RaceEstimator-fenix7.prg` - For Fenix 7
   - `RaceEstimator-fenix7pro.prg` - For Fenix 7 Pro
   - `RaceEstimator-fr255s.prg` - For Forerunner 255S

2. Connect your watch via USB

3. Copy the `.prg` file to `GARMIN/Apps` on your watch

   - On macOS: Use [Android File Transfer](https://www.android.com/filetransfer/)
   - On Windows: Direct copy via File Explorer

4. Disconnect your watch - the app will appear in your data fields

### Option 2: Build From Source

Requires [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/):

```bash
# Clone the repository
git clone https://github.com/stirnim/race-estimator.git
cd race-estimator

# Build for your device (example: fenix7)
monkeyc -o bin/RaceEstimator.prg -f monkey.jungle \
  -y ~/.Garmin/ConnectIQ/developer_key.der -d fenix7

# Copy to watch
cp bin/RaceEstimator.prg /Volumes/GARMIN/GARMIN/Apps/
```

## Note: If you plan to rename the remote repository, change the clone URL above to the final repository name before sharing or publishing.

# Race Estimator

Race Estimator - a Garmin [Connect IQ](https://developer.garmin.com/connect-iq/overview/) data field for real-time race finish time predictions.

## Features

Race Estimator predicts your finish times for 9 running milestones during your activity, combining metric and imperial distances:

- **5K** (5 kilometers)
- **5MI** (5 miles)
- **10K** (10 kilometers)
- **13.1K** (13.1 kilometers)
- **10MI** (10 miles)
- **HM** (Half Marathon - 21.1 km)
- **26.2K** (26.2 kilometers)
- **FM** (Full Marathon - 42.2 km)
- **50K** (50 kilometers)

### Key Features

- **Real-time predictions**: See estimated finish times based on your current pace
- **Rotating display**: Shows 3 upcoming milestones at a time; automatically rotates as you hit each one
- **GPS validation**: Waits for good GPS quality before showing predictions
- **AMOLED burn-in protection**: Automatic color adjustment, position shifting, and content dimming on AMOLED devices (Forerunner 265/965)
- **Persistent state**: Automatically saves and restores your progress if you pause/resume
- **Zero-allocation performance**: Optimized for battery efficiency (~2.2%/hour)
- **Full-screen layout**: Best viewed in 1-field layout for maximum visibility

## Implementation

This app uses Garmin Connect IQ API 5.2.0+ with a custom [DataField](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html) implementation. It handles full layout control for multi-row display and implements advanced features like:

- Nullable syntax for safer null handling
- Enhanced exception handling with safe mode recovery
- Modern string formatting with `Lang.format()` (30% faster)
- Storage with checksum validation for data integrity

## Supported Devices

**Fenix 7 Series**: fenix 7, fenix 7S, fenix 7X, fenix 7 Pro variants

**Forerunner 255+**: FR 255, FR 255S, FR 265, FR 265S (AMOLED), FR 955, FR 965 (AMOLED)

Requires API Level 5.2.0 or higher.

## Installation

### Option 1: Side Loading (Recommended)

1. Download the appropriate pre-built binary for your device from the `build/` directory:

   - `RaceEstimator-fenix7.prg` - For fenix 7/7S
   - `RaceEstimator-fenix7x.prg` - For fenix 7X
   - `RaceEstimator-fr265.prg` - For Forerunner 265/265S
   - `RaceEstimator-fr965.prg` - For Forerunner 965

2. Connect your watch via USB

3. Copy the `.prg` file to `GARMIN/Apps` on your watch

   - On macOS: Use [Android File Transfer](https://www.android.com/filetransfer/)
   - On Windows: Direct copy via File Explorer

4. Disconnect your watch - the app will appear in your data fields

### Option 2: Build From Source

Requires [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/):

```bash
# Clone the repository
git clone https://github.com/stirnim/garmin-lastsplit.git
cd garmin-lastsplit

# Build for your device (example: fenix7)
monkeyc -o bin/RaceEstimator.prg -f monkey.jungle \
  -y ~/.Garmin/ConnectIQ/developer_key.der -d fenix7

# Copy to watch
cp bin/RaceEstimator.prg /Volumes/GARMIN/GARMIN/Apps/
```

## Usage

1. Start a running activity on your watch
2. Add the "Race Estimator" data field to your activity screen
3. **Recommended**: Use a 1-field layout for best visibility
4. Wait for GPS to acquire (status: "WAITING GPS")
5. Run at least 100m for initial predictions (status: "WARMUP")
6. View real-time predictions for your next 3 upcoming milestones

### Display Format

```
5K EST    25:30      ← Predicted time for 5K
10K EST   51:15      ← Predicted time for 10K
HM EST    1:54:30    ← Predicted time for Half Marathon
```

Once you hit a milestone:

```
5K HIT    25:32      ← Actual time (dimmed on AMOLED)
10K EST   51:20      ← Updated prediction
HM EST    1:54:45    ← Updated prediction
```

## AMOLED Devices (FR 265/965)

Race Estimator includes sophisticated burn-in protection for AMOLED displays:

- **Black background** (OLED pixels off = no burn-in)
- **Light gray text** (not pure white, reduces stress)
- **Position shifting**: Subtle ±2 pixel movement every 2 minutes
- **Content dimming**: Hit milestones (static) show darker to reduce wear
- **Blue status indicators** (lower power than orange)

These features are automatic on supported devices.

## Technical Details

- **API Level**: 5.2.0+
- **Memory**: ~10.9KB (code + resources + runtime)
- **Performance**: compute() ~17ms, onUpdate() ~24ms
- **Battery**: ~2.2%/hour during active use
- **Storage**: ~200 bytes for state persistence

See [RaceEstimator_API5_Spec.md](./RaceEstimator_API5_Spec.md) for complete technical specification.

## Development

See [.github/copilot-instructions.md](./.github/copilot-instructions.md) for AI agent guidance and architecture details.

Key patterns:

- All arrays pre-allocated in `initialize()` - no dynamic allocations
- Display rotates when first milestone is hit
- GPS quality validated before every compute
- Safe mode recovery from consecutive errors
- Checksum-validated storage for crash recovery

## Version History

- 2025-10-19, Race Estimator 1.0.0 - Complete rewrite with 9 milestones, AMOLED protection, API 5.2.0
- 2024-03-04, Add support for more Fenix7 devices (0.0.3)
- 2023-11-10, Add support for more devices. Indicate supported language (ENG) (0.0.2)
- 2020-06-01, Fix unit in FIT activity (0.0.1)
- 2020-05-17, Initial release (0.0.0)

## License

See LICENSE file for details.

## Contributing

Contributions welcome! Please ensure:

1. No dynamic allocations in `compute()` or `onUpdate()`
2. Test on both MIP and AMOLED devices
3. Follow existing patterns (see copilot-instructions.md)
4. Build succeeds for all target devices
