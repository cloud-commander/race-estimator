# Simulator Time Skip Testing Guide

## Quick Reference

The RaceEstimator now handles simulator **time skipping** correctly:

- ✅ Skip forward in time → predictions update
- ✅ Normal progression → predictions update smoothly
- ✅ FIT playback glitches (distance freeze) → predictions suppressed safely

## How to Test

### Test 1: Basic Time Skip (Recommended)

```
1. Open Connect IQ Simulator (fenix7 recommended)
2. Start a new activity in RaceEstimator
3. Let it run for ~30 seconds (real time) to collect baseline pace
4. Open Simulator menu → Time Controls
5. Jump forward 5-10 minutes
6. Watch the display:
   - Predictions should update immediately
   - Console log should show: "[RaceEst] Time skip detected - allowing predictions"
   - Milestone times should reflect the new elapsed time
```

### Test 2: Continuous Time Skipping

```
1. Start activity (let run 30 sec)
2. Time skip forward (+5 min)
3. Wait 10 seconds
4. Time skip forward again (+5 min)
5. Expected: Both skips update predictions; no anomaly suppression
```

### Test 3: Normal Progression (Sanity Check)

```
1. Start activity
2. Let run for 2-3 minutes in normal time (not skipped)
3. Expected: Smooth prediction updates, no anomaly logs
4. Console should show: "[RaceEst] Pace calc:" lines but NO "Time skip detected"
```

### Test 4: Mixed Pace Changes (Advanced)

```
1. Start activity
2. Let pace settle (30 sec)
3. Manually change running speed (slow down)
4. Wait 20 seconds
5. Time skip forward 5 minutes
6. Expected: Both pace change and time skip handled correctly
   - Pace change: gradual pace anomaly count, but not suppressed (count resets when corrected)
   - Time skip: predictions update despite pace spike from time skip
```

## Expected Console Output

### ✅ Normal Time Skip

```
[RaceEst] computeImpl called
[RaceEst] Timer: 123456 (centisec), Distance: 500m
[RaceEst] Pace calc: timerMs=1234560 elapsedDist=500 pace=2.469
[RaceEst] Time skip detected: pace ratio=2.1 dist ratio=2.2 - allowing predictions to update
[RaceEst] M0: target=5000m curr=500m rem=4500m pace=2.469 time=11110500ms
[RaceEst] M0 HIT at 1234560ms (or prediction time shown)
```

### ⚠️ FIT Glitch Detection (Distance Frozen)

```
[RaceEst] Distance stagnation: 1/5
[RaceEst] Distance stagnation: 2/5
[RaceEst] Distance stagnation: 3/5
[RaceEst] Distance stagnation: 4/5
[RaceEst] Distance stagnation: 5/5
[RaceEst] FIT ANOMALY: Distance frozen for 5 updates - SKIPPING
[RaceEst] FIT anomaly detected - predictions suppressed
```

## Common Scenarios

| Scenario                   | Console Log            | Predictions     | Expected Result  |
| -------------------------- | ---------------------- | --------------- | ---------------- |
| Time skip +5 min           | "Time skip detected"   | Update          | ✅ Pass          |
| Gradual pace change        | "Pace calc"            | Update smoothly | ✅ Pass          |
| Distance stagnates 5+ sec  | "Distance frozen"      | Suppressed      | ✅ Pass          |
| Normal 1-2 pace spikes     | "Pace anomaly" (1-2x)  | Update          | ✅ Pass          |
| 3+ consecutive pace spikes | "Multiple pace spikes" | Suppressed      | ✅ Pass (safety) |

## Build Status

```
✅ BUILD SUCCESSFUL (fenix7)
```

**Files Modified:**

- `source/RaceEstimatorView.mc`
  - Added: `mLastValidTimer` state variable for time-skip detection
  - Enhanced: `detectFitAnomalies()` method with time-skip logic
  - Updated: `computeImpl()` to track timer for anomaly detection

**Build Artifacts:**

- `bin/RaceEstimator-fenix7-final.prg` (ready for device)

---

## Troubleshooting

**Q: Predictions still don't update after time skip**  
A: Check console for error messages. If "Multiple pace spikes" appears, the anomaly counter needs to reset. Try normal running for 10 sec, then time skip again.

**Q: Too many "[RaceEst]" logs in console**  
A: Normal during debugging. Before release, consider wrapping with a `DEBUG` flag or removing logs (see `RaceEstimator_API5_Spec.md` for guidance).

**Q: Time skip happens but pace says "Insane"**  
A: Pace check happens before time-skip detection. If pace < 0.05 or > 20 sec/m, predictions fail. Verify elapsed distance and timer values are reasonable.

---

**Last Updated:** 19 October 2025  
**Status:** Ready for integration testing
