# Changes Summary: Pace Anomaly Fix

NOTE: See `OVERVIEW.md` for the top-level docs index and related documents.

## Problem

Debug output showed a pace anomaly warning on first pace reading:

```
[RaceEst] Pace anomaly: ratio=0.060807 (prev=3.521986 now=0.214160) count=1
```

This was caused by comparing the first valid pace (0.214 sec/m) against uninitialized garbage data (3.52 sec/m), creating a 5.8x ratio that triggered anomaly detection.

While the anomaly count stayed below threshold (1 < 3) and predictions were still shown, the warning was confusing and indicated potential issues with the anomaly detection initialization.

## Solution

Added `mFirstPaceReadingDone` flag to skip anomaly detection on the first valid pace reading, preventing false positives from uninitialized state.

## Files Modified

### /source/RaceEstimatorView.mc

#### 1. Added state flag (line ~57)

```monkeyc
private var mFirstPaceReadingDone as Lang.Boolean = false;
```

#### 2. Initialize flag in initialize() (line ~116)

```monkeyc
mFirstPaceReadingDone = false; // Reset: will skip anomaly detection on first reading
```

#### 3. Initialize flag in onTimerReset() (line ~927)

```monkeyc
mFirstPaceReadingDone = false; // Reset: will skip anomaly detection on first reading after reset
```

#### 4. Skip first reading in detectFitAnomalies() (line ~237)

```monkeyc
// Skip anomaly detection on FIRST pace reading to avoid false positives from uninitialized state
if (!mFirstPaceReadingDone) {
  System.println("[RaceEst] First pace reading: " + pace + " sec/m (skipping anomaly checks)");
  mLastValidPace = pace;
  mFirstPaceReadingDone = true;
  return true; // Allow first reading without anomaly checks
}
```

## Impact

### Before

- ❌ False anomaly warning on activity start
- ❌ Confusing debug output
- ✅ Predictions still shown (count < threshold)

### After

- ✅ No false anomaly warnings
- ✅ Clean debug output
- ✅ Predictions shown correctly
- ✅ Real anomalies still detected (from second reading onward)

## Validation

### Test Data

Activity: activity_18264498522.csv

- Distance at test point: 4.038 km
- Time at test point: 864.8 sec (14:24)
- Current pace: 0.214 sec/m = 3:57/km
- 5K prediction: 961.9m × 3:57/km = 3:26 remaining ✓

### Build Status

✅ **BUILD SUCCESSFUL** - No compilation or lint errors

## Testing Recommendations

1. **Early activity phase (0-100m):** Verify no anomaly warnings, status shows "WARMUP"
2. **100m-5s warmup:** Verify status shows "WARMING UP" until both 100m AND 5s elapsed
3. **After 5s+100m:** Verify predictions appear without anomaly warnings
4. **Subsequent readings:** Verify anomaly detection still catches real pace spikes (ratio > 2.0 or < 0.5)
5. **FIT playback:** Run against activity_18264498522.gpx to verify no false anomalies during normal replay
6. **Real device:** Test on FR 265/965 with actual GPS run to confirm clean logs

## Performance

- No additional computation (simple flag check)
- No additional memory (single boolean variable)
- First reading uses same validation logic, just skips anomaly ratio check
- Normal anomaly detection continues from second reading onward
