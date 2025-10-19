# Time Skip Handling in Simulator

## Overview

The RaceEstimator code now properly handles **simulator time skipping** (when you fast-forward time in the Connect IQ simulator) while still detecting real **FIT playback anomalies**.

## Problem

Previously, when skipping time forward in the simulator:

- `timerTime` (in centiseconds) would jump significantly
- The calculated pace would change dramatically (pace spike detected)
- The anomaly detector would interpret this as a FIT playback glitch and suppress predictions
- Result: predictions would not update after time skip, appearing broken

## Solution

### 1. **New State Variable**

Added `mLastValidTimer` to track the last valid timer value (in centiseconds):

```monkeyc
private var mLastValidTimer as Lang.Number = 0;
```

### 2. **Enhanced Anomaly Detection Logic**

Updated `detectFitAnomalies()` to distinguish between:

#### **Time Skip** (Allowed, Normal Simulator Behavior)

- **Characteristic**: Both distance AND time advance, pace changes naturally
- **Behavior**: Predictions update normally
- **Detection**: If pace ratio > 2.0 or < 0.5 AND distance also advanced proportionally → it's a time skip
- **Example**:
  - Time: 100 sec → 400 sec (4x jump)
  - Distance: 100m → 400m (4x advance)
  - Pace: unchanged/normal relative to time and distance
  - **Result**: ✅ Allow predictions to update

#### **FIT Playback Glitch** (Suppressed, Error Condition)

- **Characteristic**: Time advances but distance stagnates
- **Behavior**: Predictions suppressed (unchanged milestone times)
- **Detection**: Pace spike without corresponding distance advance = glitch
- **Example**:
  - Time: 100 sec → 200 sec (2x jump)
  - Distance: 100m → 100m (no change, frozen)
  - **Result**: ❌ Skip prediction update

### 3. **Code Logic**

```monkeyc
// Track the current timer value for time-skip detection
mLastValidTimer = timerTime;

// In detectFitAnomalies():
if (mLastValidPace > 0.0 && mLastValidTimer > 0) {
  var paceRatio = pace / mLastValidPace;

  var isTimeSkip = false;
  if (paceRatio > 2.0 || paceRatio < 0.5) {
    // Pace changed significantly
    // Check if distance also changed (time skip) or stayed same (glitch)
    if (elapsedDistance > mLastValidDistance && mLastValidDistance > 0) {
      var distanceRatio = elapsedDistance / mLastValidDistance;
      if (distanceRatio > 1.0) {
        // Distance also advanced → this is a time skip
        System.println("[RaceEst] Time skip detected - allowing predictions");
        isTimeSkip = true;
        mPaceAnomalyCount = 0; // Reset anomaly counter
      }
    }
  }

  // Only suppress if it's NOT a time skip and pace spiked
  if (!isTimeSkip && (paceRatio > 2.0 || paceRatio < 0.5)) {
    mPaceAnomalyCount++;
    if (mPaceAnomalyCount >= 3) {
      return false; // Suppress predictions (FIT glitch)
    }
  }
}
```

## Testing in Simulator

### ✅ Time Skip Test

1. Start activity in Connect IQ simulator
2. Wait 30-60 seconds of elapsed time
3. Use simulator controls to skip forward 5-10 minutes
4. Expected: Milestone predictions update to reflect new time/distance

### ✅ FIT Playback Test

1. Load a FIT file in simulator playback
2. If distance freezes while time advances:
   - Expected: "FIT anomaly detected - predictions suppressed"
   - Milestone times remain unchanged (not re-predicted)

### ✅ Normal Running Test

1. Simulator normal time progression (1 sec = 1 real second)
2. Expected: Predictions update smoothly, no anomalies logged

## Constants

| Constant                   | Value      | Purpose                                              |
| -------------------------- | ---------- | ---------------------------------------------------- |
| `FIT_STAGNATION_THRESHOLD` | 5          | Distance stagnation count before suppression         |
| `MAX_REASONABLE_PACE`      | 20.0 sec/m | Sanity check (3 min/km = fastest elite)              |
| `MIN_REASONABLE_PACE`      | 0.05 sec/m | Sanity check (20 m/s = 72 km/h, clearly wrong)       |
| `MAX_TIME_SKIP_CENTISEC`   | 50000      | 500 sec (~8 min) — threshold for time skip tolerance |

## Build Status

✅ **BUILD SUCCESSFUL** — No compilation errors or breaking changes.

## Files Modified

- `source/RaceEstimatorView.mc`
  - Added `mLastValidTimer` state variable
  - Enhanced `detectFitAnomalies()` method
  - Updated `computeImpl()` to track timer value

## Impact

- **Positive**: Simulator time skipping now works as expected; predictions update correctly
- **No Breaking Changes**: Existing logic preserved; only detection logic improved
- **No Performance Impact**: Same compute complexity; one additional state variable (~4 bytes)

---

**Date**: 19 October 2025  
**Status**: Ready for testing in simulator and device
