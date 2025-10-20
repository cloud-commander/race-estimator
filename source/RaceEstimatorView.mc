using Toybox.Lang;
using Toybox.Activity;
using Toybox.System;
using Toybox.Position;
using Toybox.Graphics;
using Toybox.WatchUi;
using Toybox.Application.Storage;

class RaceEstimatorView extends WatchUi.DataField {
  // Constants
  private const MILESTONE_COUNT = 9;
  private const DISPLAY_ROW_COUNT = 3;
  private const TOLERANCE_CM = 500;
  private const MIN_PREDICTION_DISTANCE = 100;
  private const STORAGE_KEY = "raceEstState";
  private const STORAGE_VERSION = 4;
  private const POSITION_SHIFT_INTERVAL = 120;

  // DEBUG: Ignore storage and always start fresh (automatically disabled in release builds)
  (:debug)
  private const DEBUG_IGNORE_STORAGE = true;   // SIMULATOR: Always start fresh
  (:release)
  private const DEBUG_IGNORE_STORAGE = false;  // PRODUCTION: Storage enabled

  // DEBUG: Enable verbose logging (automatically disabled in release builds)
  (:debug)
  private const DEBUG_LOGGING = true;
  (:release)
  private const DEBUG_LOGGING = false;

  // EMA smoothing for stable predictions
  private const SMOOTHING_ALPHA = 0.15d; // Use Double for precision
  private const SMOOTHING_WINDOW_SEC = 5;

  // Heart icon display constants
  private const HEART_ICON_SIZE = 4;
  private const HEART_ICON_OFFSET_Y = 3;  // Vertical offset for heart icon alignment
  private const HEART_RATE_TOP_PADDING = 10;  // Additional top padding for HR display
  private const HR_TEXT_WIDTH_ESTIMATE = 30;  // Conservative estimate for 3-digit HR (Issue #2)
  private const HR_ICON_TEXT_SPACING = 5;  // Space between heart icon and text

  // Arc drawing constants - full circle starting from top (90°) going clockwise
  private const ARC_START_ANGLE = 90;   // Start at top (12 o'clock position)
  private const ARC_SPAN = 360;         // 360 degree span for full circle
  private const ARC_MARGIN_PIXELS = 5;
  private const BOTTOM_TEXT_POSITION_PERCENT = 0.80;

  // Milestone data
  private var mDistancesCm as Lang.Array<Lang.Number>;
  private var mLabels as Lang.Array<Lang.String>;
  private var mFinishTimesMs as Lang.Array<Lang.Number?>;
  private var mDisplayIndices as Lang.Array<Lang.Number?>;
  private var mCachedTimes as Lang.Array<Lang.String>;
  private var mCachedLabels as Lang.Array<Lang.String>;

  // State tracking
  private var mGpsQualityGood as Lang.Boolean = false;
  private var mMinDistanceReached as Lang.Boolean = false;
  private var mSmoothingWindowFull as Lang.Boolean = false;
  private var mStateDirty as Lang.Boolean = false;
  private var mAllComplete as Lang.Boolean = false;
  private var mErrorState as Lang.Number = 0;
  private var mConsecutiveErrors as Lang.Number = 0;
  private var mSafeModeCycles as Lang.Number = 0;

  // Milestone celebration tracking
  private var mCelebrationStartTimeMs as Lang.Number? = null;
  private var mCelebrationMilestoneIdx as Lang.Number? = null;
  private const CELEBRATION_DURATION_MS = 15000;  // 15 seconds

  // Arc red flash celebration when milestone reached
  private var mArcFlashStartTimeMs as Lang.Number? = null;
  private const ARC_FLASH_DURATION_MS = 3000;  // 3 seconds red flash

  // AMOLED dash pattern for burn-in protection
  private const AMOLED_DASH_DEGREES = 12;  // Each dash is 12 degrees
  private const AMOLED_GAP_DEGREES = 18;   // 18 degree gap between dashes for visibility
  private const AMOLED_DASH_ALTERNATE_MS = 200;  // Alternate dash pattern every 200ms (flash only)
  private const AMOLED_MARCH_SPEED_MS = 500;  // Clockwise march speed for normal arc (500ms per step)
  private var mDashAlternate as Lang.Boolean = false;  // Toggle for alternating dash positions (flash)
  private var mDashOffset as Lang.Number = 0;  // Clockwise marching offset in degrees (normal arc)

  // EMA smoothing state
  private var mSmoothedPaceSecPerM as Lang.Double = 0.0d;
  private var mLastComputeTimeSec as Lang.Double = 0.0d;

  // Display properties
  private var mBackgroundColor as Lang.Number = Graphics.COLOR_BLACK;
  private var mForegroundColor as Lang.Number = Graphics.COLOR_WHITE;
  private var mAccentColor as Lang.Number = Graphics.COLOR_ORANGE;
  private var mDimmedColor as Lang.Number = Graphics.COLOR_DK_GRAY;
  private var mIsAmoled as Lang.Boolean = false;

  // AMOLED burn-in prevention
  private var mPositionOffset as Lang.Number = 0;
  private var mUpdateCount as Lang.Number = 0;

  // Cached display strings (zero-allocation hot path)
  private var mCachedDisplayTexts as Lang.Array<Lang.String>;

  // FIT anomaly detection (simulator/playback edge cases)
  private var mLastValidDistance as Lang.Double = 0.0d;
  private var mDistanceStagnationCount as Lang.Number = 0;
  private var mLastValidPace as Lang.Double = 0.0d;
  private var mPaceAnomalyCount as Lang.Number = 0;
  private var mFirstPaceReadingDone as Lang.Boolean = false;
  private const FIT_STAGNATION_THRESHOLD = 5;
  private const MAX_DELTA_TIME_SEC = 5.0d;

  // Validation thresholds (Issue #16 - Extract magic numbers)
  private const PACE_SPIKE_RATIO_MAX = 2.0;
  private const PACE_SPIKE_RATIO_MIN = 0.5;
  private const PACE_SPIKE_THRESHOLD = 3;
  private const MAX_CONSECUTIVE_ERRORS = 3;
  private const SAFE_MODE_RECOVERY_CYCLES = 10;
  private const HR_SANITY_MIN = 0;
  private const HR_SANITY_MAX = 250;
  private const PACE_MIN_SEC_PER_M = 0.05;
  private const PACE_MAX_SEC_PER_M = 20.0;
  private const MIN_DISTANCE_EPSILON = 0.1;  // 10cm minimum distance
  private const MAX_TIME_REMAINING_MS = 360000000;  // 100 hours max
  private const MAX_TIME_DISPLAY_SEC = 359999;  // 99:59:59
  private const FULLSCREEN_THRESHOLD_PERCENT = 0.60;  // 60% = 3/5
  private const ARC_ANGLE_OVERFLOW_LIMIT = 10000;  // Sanity check for corrupted data
  private const CELEBRATION_TIMEOUT_MS = 60000;  // 1 minute max celebration (safety)

  // Progress arc state
  private var mCurrentDistance as Lang.Double = 0.0d;
  private var mArcProgress as Lang.Double = 1.0d;  // Now inverted: 1.0 at start, 0.0 at finish
  private var mArcColor as Lang.Number = Graphics.COLOR_GREEN;
  private var mRemainingDistanceKm as Lang.String = "";
  private var mRemainingDistanceMeters as Lang.Double = 0.0d;  // For color threshold logic

  // Layout
  private var mCenterX as Lang.Number = 0;
  private var mRow1Y as Lang.Number = 0;
  private var mRow2Y as Lang.Number = 0;
  private var mRow3Y as Lang.Number = 0;
  private var mStatusY as Lang.Number = 0;
  private var mBottomY as Lang.Number = 0;
  private var mFieldHeight as Lang.Number = 0;

  // Arc geometry cache (computed once in onLayout)
  private var mArcCenterX as Lang.Number = 0;
  private var mArcCenterY as Lang.Number = 0;
  private var mArcRadius as Lang.Number = 0;
  private var mArcPenWidth as Lang.Number = 8;

  // Heart rate display
  private var mCurrentHR as Lang.Number? = null;

  // Caching to reduce allocations in hot path
  private var mLastRemainingKm as Lang.Double = -1.0d;
  private var mLastDisplayTextHash as Lang.Array<Lang.Number>;

  // Screen height cache to avoid repeated system calls
  private var mScreenHeight as Lang.Number = 100;  // Safe default to prevent division issues

  // Heart icon triangle cache (reusable to avoid allocations)
  private var mHeartTriangle as Lang.Array<Lang.Array<Lang.Number> >?;

  // Optimization tracking (Issue #8, #13, #17)
  private var mLastSuccessfulSave as Lang.Number = 0;  // Reserved for UI indication of storage health
  private var mLastKnownBackground as Lang.Number = Graphics.COLOR_BLACK;
  private var mStorageErrorCount as Lang.Number = 0;

  // Pixel shift optimization (Issue #9)
  private const PIXEL_OFFSETS = [-4, -3, -2, -1, 0, 1, 2, 3, 4] as Lang.Array<Lang.Number>;
  private var mOffsetIndex as Lang.Number = 4;  // Start at 0 offset

  function initialize() {
    DataField.initialize();

    var settings = System.getDeviceSettings();
    if (settings has :requiresBurnInProtection) {
      mIsAmoled = settings.requiresBurnInProtection;
    }

    mDistancesCm =
      [
        500000, 804672, 1000000, 1310000, 1609344, 2109750, 2620000, 4219500,
        5000000,
      ] as Lang.Array<Lang.Number>;
    mLabels =
      ["5K", "5MI", "10K", "13.1K", "10MI", "HM", "26.2K", "FM", "50K"] as
      Lang.Array<Lang.String>;

    mFinishTimesMs = new Lang.Array<Lang.Number?>[MILESTONE_COUNT];
    mDisplayIndices = new Lang.Array<Lang.Number?>[DISPLAY_ROW_COUNT];
    mCachedTimes = new Lang.Array<Lang.String>[DISPLAY_ROW_COUNT];
    mCachedLabels = new Lang.Array<Lang.String>[DISPLAY_ROW_COUNT];
    mCachedDisplayTexts = new Lang.Array<Lang.String>[DISPLAY_ROW_COUNT];
    mLastDisplayTextHash = new Lang.Array<Lang.Number>[DISPLAY_ROW_COUNT];

    // Initialize arrays with default values before attempting storage load
    for (var i = 0; i < MILESTONE_COUNT; i++) {
      mFinishTimesMs[i] = null;
    }
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mDisplayIndices[i] = i;  // Default: show first 3 milestones (0, 1, 2)
      mCachedDisplayTexts[i] = "";
      mLastDisplayTextHash[i] = 0;
    }

    if (DEBUG_LOGGING) {
      System.println("=== INIT: Default indices set to [0, 1, 2] ===");
      System.println("Display indices: [" + mDisplayIndices[0] + ", " + mDisplayIndices[1] + ", " + mDisplayIndices[2] + "]");
    }

    // Load saved state from storage (will override defaults if valid data exists)
    loadFromStorage();

    if (DEBUG_LOGGING) {
      System.println("=== AFTER STORAGE LOAD ===");
      System.println("Display indices: [" + mDisplayIndices[0] + ", " + mDisplayIndices[1] + ", " + mDisplayIndices[2] + "]");
      System.println("Labels: [" + mCachedLabels[0] + ", " + mCachedLabels[1] + ", " + mCachedLabels[2] + "]");
    }

    updateColors();
  }

  private function updateColors() as Void {
    if (mIsAmoled) {
      // AMOLED burn-in mitigation: Use dimmer colors to reduce pixel wear
      mBackgroundColor = Graphics.COLOR_BLACK;
      mForegroundColor = Graphics.COLOR_LT_GRAY;  // Dimmer than pure white
      mAccentColor = Graphics.COLOR_BLUE;         // Blue has lower OLED power draw than red/orange
      mDimmedColor = Graphics.COLOR_DK_GRAY;      // Very dim for completed milestones
    } else {
      var systemBg = getBackgroundColor();
      mBackgroundColor = systemBg;

      if (
        systemBg == Graphics.COLOR_WHITE ||
        systemBg == Graphics.COLOR_LT_GRAY ||
        systemBg == Graphics.COLOR_TRANSPARENT
      ) {
        mForegroundColor = Graphics.COLOR_BLACK;
        mAccentColor = Graphics.COLOR_BLUE;
      } else {
        mForegroundColor = Graphics.COLOR_WHITE;
        mAccentColor = Graphics.COLOR_ORANGE;
      }
      mDimmedColor = mForegroundColor;
    }
  }

  private function validateGpsData(info as Activity.Info) as Lang.Boolean {
    var accuracy = info.currentLocationAccuracy;
    if (accuracy == null) {
      mGpsQualityGood = true;
      return true;
    }
    if (accuracy > Position.QUALITY_USABLE) {
      mGpsQualityGood = false;
      return false;
    }
    mGpsQualityGood = true;
    return true;
  }

  private function validateMinimumDistance(elapsedDistance as Lang.Float?) as Lang.Boolean {
    if (elapsedDistance == null || elapsedDistance < MIN_PREDICTION_DISTANCE) {
      mMinDistanceReached = false;
      return false;
    }
    mMinDistanceReached = true;
    return true;
  }

  private function detectDistanceStagnation(elapsedDistance as Lang.Float) as Lang.Boolean {
    var distAsDouble = elapsedDistance.toDouble();
    if (distAsDouble == mLastValidDistance) {
      mDistanceStagnationCount++;
      if (mDistanceStagnationCount >= FIT_STAGNATION_THRESHOLD) {
        return false;
      }
    } else {
      mDistanceStagnationCount = 0;
      mLastValidDistance = distAsDouble;
    }
    return true;
  }

  private function detectPaceSpike(pace as Lang.Double) as Lang.Boolean {
    if (!mFirstPaceReadingDone) {
      mLastValidPace = pace;
      mFirstPaceReadingDone = true;
      return true;
    }

    if (mLastValidPace > 0.0) {
      var paceRatio = pace / mLastValidPace;
      // FIX Issue #16: Use extracted constants
      if (paceRatio > PACE_SPIKE_RATIO_MAX || paceRatio < PACE_SPIKE_RATIO_MIN) {
        mPaceAnomalyCount++;
        if (mPaceAnomalyCount >= PACE_SPIKE_THRESHOLD) {
          return false;
        }
      } else {
        mPaceAnomalyCount = 0;
      }
    }

    mLastValidPace = pace;
    return true;
  }

  function compute(info as Activity.Info) as Void {
    if (mErrorState == 1) {
      mSafeModeCycles++;
      // FIX Issue #16: Use constant
      if (mSafeModeCycles > SAFE_MODE_RECOVERY_CYCLES) {
        mErrorState = 0;
        mConsecutiveErrors = 0;
        mSafeModeCycles = 0;
      } else {
        return;
      }
    }

    try {
      computeImpl(info);
      mConsecutiveErrors = 0;
    } catch (ex) {
      mConsecutiveErrors++;
      // FIX Issue #17: Consistent error logging
      if (DEBUG_LOGGING) {
        System.println("Compute error #" + mConsecutiveErrors + ": " + ex.getErrorMessage());
      }
      // FIX Issue #16: Use constant for max errors
      if (mConsecutiveErrors > MAX_CONSECUTIVE_ERRORS) {
        if (DEBUG_LOGGING) {
          System.println("CRITICAL: Entering safe mode after " + MAX_CONSECUTIVE_ERRORS + " consecutive errors");
        }
        enterSafeMode();
      }
    }
  }

  private function computeImpl(info as Activity.Info) as Void {
    if (!validateGpsData(info)) {
      return;
    }

    // Update heart rate (zero allocation hot path)
    if (info has :currentHeartRate && info.currentHeartRate != null) {
      var hr = info.currentHeartRate as Lang.Number;
      // FIX Issue #16: Use constants for sanity check
      if (hr > HR_SANITY_MIN && hr < HR_SANITY_MAX) {
        mCurrentHR = hr;
      }
    } else {
      mCurrentHR = null;
    }

    var timerTime = info.timerTime;
    var elapsedDistance = info.elapsedDistance;

    // FIX Issue #6: Add epsilon check to prevent division issues
    if (timerTime == null || timerTime <= 0 || elapsedDistance == null || elapsedDistance < MIN_DISTANCE_EPSILON) {
      return;
    }

    if (!validateMinimumDistance(elapsedDistance)) {
      return;
    }

    var timerTimeMs = timerTime;
    var timerTimeSec = timerTimeMs / 1000.0d;
    // Keep distance as Double to prevent overflow for ultramarathons (50K+)
    var distanceCm = elapsedDistance * 100.0d;

    mCurrentDistance = elapsedDistance.toDouble();

    if (!mSmoothingWindowFull && timerTimeSec >= SMOOTHING_WINDOW_SEC) {
      mSmoothingWindowFull = true;
    }

    var deltaTimeSec = timerTimeSec - mLastComputeTimeSec;
    if (mLastComputeTimeSec > 0.0 && deltaTimeSec.abs() > MAX_DELTA_TIME_SEC) {
      mSmoothedPaceSecPerM = 0.0d;
      mPaceAnomalyCount = 0;
    }

    mLastComputeTimeSec = timerTimeSec;

    // FIX Issue #11: Validate celebration state to prevent memory leaks
    if (mCelebrationStartTimeMs != null &&
        (timerTimeMs < mCelebrationStartTimeMs ||
         timerTimeMs - mCelebrationStartTimeMs > CELEBRATION_TIMEOUT_MS)) {
      // Invalid or timeout - clear celebration
      mCelebrationStartTimeMs = null;
      mCelebrationMilestoneIdx = null;
    }

    var needsRotation = false;
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];
      // FIX Issue #12: Complete array bounds validation
      if (idx != null && idx >= 0 && idx < MILESTONE_COUNT &&
          idx < mDistancesCm.size() && idx < mFinishTimesMs.size() &&
          mFinishTimesMs[idx] == null &&
          distanceCm >= mDistancesCm[idx].toDouble() - TOLERANCE_CM) {  // Use Double comparison
        mFinishTimesMs[idx] = timerTimeMs;
        mStateDirty = true;
        if (i == 0) {
          // Start celebration period - show completion time for 15 seconds
          mCelebrationStartTimeMs = timerTimeMs;
          mCelebrationMilestoneIdx = idx;
          // Start 3-second red flash for arc
          mArcFlashStartTimeMs = timerTimeMs;
          needsRotation = true;
        }
      }
    }

    // Check if celebration period has ended
    if (mCelebrationStartTimeMs != null && timerTimeMs - mCelebrationStartTimeMs >= CELEBRATION_DURATION_MS) {
      // Celebration ended - rotate to next milestone (unless it's the last one)
      mCelebrationStartTimeMs = null;
      mCelebrationMilestoneIdx = null;
      needsRotation = true;
    }

    if (needsRotation) {
      rebuildDisplay();
    }

    var currentPaceSecPerMeter = timerTimeSec / elapsedDistance;

    // FIX Issue #16: Use constants for pace validation
    if (currentPaceSecPerMeter < PACE_MIN_SEC_PER_M || currentPaceSecPerMeter > PACE_MAX_SEC_PER_M) {
      return;
    }

    if (!detectDistanceStagnation(elapsedDistance) || !detectPaceSpike(currentPaceSecPerMeter)) {
      return;
    }

    if (mSmoothedPaceSecPerM == 0.0d) {
      mSmoothedPaceSecPerM = currentPaceSecPerMeter;
    } else {
      mSmoothedPaceSecPerM =
        SMOOTHING_ALPHA * currentPaceSecPerMeter +
        (1.0 - SMOOTHING_ALPHA) * mSmoothedPaceSecPerM;
    }

    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];
      // Defensive: Check array bounds before access
      if (idx == null || idx < 0 || idx >= MILESTONE_COUNT) { continue; }

      var currentHash = 0;
      if (mFinishTimesMs[idx] != null) {
        var finishTime = mFinishTimesMs[idx];
        currentHash = finishTime != null ? finishTime : 0;

        // Only update strings if hash changed (milestone just completed)
        if (currentHash != mLastDisplayTextHash[i]) {
          mCachedTimes[i] = formatTime(finishTime);
          // FIX Issue #3: Use Lang.format to avoid string concatenation allocations
          mCachedLabels[i] = Lang.format("$1$ ✓", [mLabels[idx]]);
          mCachedDisplayTexts[i] = Lang.format("$1$  $2$", [mCachedLabels[i], mCachedTimes[i]]);
          mLastDisplayTextHash[i] = currentHash;
        }

        // Clear remaining distance when first milestone is completed
        if (i == 0) {
          mRemainingDistanceKm = "";
        }
      } else {
        var remainingDistanceMeters = mDistancesCm[idx] / 100.0d - elapsedDistance;
        if (remainingDistanceMeters < 0) {
          // Only update if hash changed
          if (mLastDisplayTextHash[i] != -1) {
            mCachedTimes[i] = "0:00";
            mCachedLabels[i] = mLabels[idx];
            // FIX Issue #3: Use Lang.format
            mCachedDisplayTexts[i] = Lang.format("$1$  $2$", [mCachedLabels[i], mCachedTimes[i]]);
            mLastDisplayTextHash[i] = -1;
          }
          if (i == 0) {
            mRemainingDistanceKm = "";
          }
          continue;
        }

        var timeRemainingMs = (remainingDistanceMeters * mSmoothedPaceSecPerM * 1000.0d).toNumber();
        // FIX Issue #16: Use constant
        if (timeRemainingMs < 0 || timeRemainingMs > MAX_TIME_REMAINING_MS) {
          timeRemainingMs = MAX_TIME_REMAINING_MS;
        }

        // Create hash from time in seconds to reduce update frequency
        currentHash = (timeRemainingMs / 1000).toNumber();

        // Only update strings when seconds change
        if (currentHash != mLastDisplayTextHash[i]) {
          mCachedTimes[i] = formatTime(timeRemainingMs);
          mCachedLabels[i] = mLabels[idx];
          // FIX Issue #3: Use Lang.format
          mCachedDisplayTexts[i] = Lang.format("$1$  $2$", [mCachedLabels[i], mCachedTimes[i]]);
          mLastDisplayTextHash[i] = currentHash;
        }

        // Calculate remaining distance for the first (next) milestone
        // Only update when value changes significantly (>0.01 km)
        if (i == 0) {
          var remainingKm = remainingDistanceMeters / 1000.0d;
          var kmDiff = remainingKm - mLastRemainingKm;
          if (kmDiff < -0.01 || kmDiff > 0.01) {
            mLastRemainingKm = remainingKm;
            mRemainingDistanceKm = Lang.format("$1$ km", [remainingKm.format("%.2f")]);
          }
        }
      }
    }

    // Check if arc flash has ended (3 seconds for both - AMOLED uses dashed pattern for protection)
    if (mArcFlashStartTimeMs != null && timerTimeMs - mArcFlashStartTimeMs >= ARC_FLASH_DURATION_MS) {
      // Flash ended - reset arc to 0% for next milestone
      mArcFlashStartTimeMs = null;
      mDashAlternate = false;  // Reset dash alternation
    }

    // AMOLED dash animations (burn-in protection)
    if (mIsAmoled) {
      if (mArcFlashStartTimeMs != null) {
        // Flash celebration: Toggle alternating pattern every 200ms
        var flashElapsed = timerTimeMs - mArcFlashStartTimeMs;
        mDashAlternate = ((flashElapsed / AMOLED_DASH_ALTERNATE_MS) % 2) == 1;
      } else {
        // Normal operation: Clockwise marching dashes
        // Calculate offset that increases over time (marches clockwise)
        var marchCycles = (timerTimeMs / AMOLED_MARCH_SPEED_MS) % (AMOLED_DASH_DEGREES + AMOLED_GAP_DEGREES);
        mDashOffset = marchCycles.toNumber();
      }
    }

    // Calculate arc progress (override to 100% during flash)
    if (mArcFlashStartTimeMs != null) {
      // During flash: show full red circle
      mArcProgress = 1.0d;
      mArcColor = mIsAmoled ? Graphics.COLOR_DK_RED : Graphics.COLOR_RED;
    } else {
      // Normal operation: calculate progress toward next milestone
      mArcProgress = calculateArcProgress();
      mArcColor = getArcColor(mArcProgress);
    }

    if (mStateDirty) {
      saveToStorage();
      mStateDirty = false;
    }
  }

  private function enterSafeMode() as Void {
    mErrorState = 1;
    mSafeModeCycles = 0;
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      mCachedLabels[i] = "ERROR";
      mCachedDisplayTexts[i] = "ERROR  --:--";
    }
  }

  private function formatTime(ms as Lang.Number?) as Lang.String {
    if (ms == null || ms <= 0) {
      return "--:--";
    }
    var sec = (ms / 1000.0d).toNumber();
    // FIX Issue #16: Use constant
    if (sec > MAX_TIME_DISPLAY_SEC) {
      return "99:59:59";
    }
    var h = sec / 3600;
    var m = (sec % 3600) / 60;
    var s = sec % 60;
    if (h > 0) {
      return Lang.format("$1$:$2$:$3$", [h, m.format("%02d"), s.format("%02d")]);
    }
    return Lang.format("$1$:$2$", [m, s.format("%02d")]);
  }

  function onLayout(dc as Graphics.Dc) as Void {
    var width = dc.getWidth();
    var height = dc.getHeight();

    // Defensive: Ensure sane dimensions
    if (width <= 0 || height <= 0) {
      width = 100;
      height = 100;
    }

    mFieldHeight = height;
    mCenterX = width / 2;
    mStatusY = 15;
    mRow1Y = (height * 0.25).toNumber();
    mRow2Y = (height * 0.45).toNumber();
    mRow3Y = (height * 0.65).toNumber();
    mBottomY = (height * BOTTOM_TEXT_POSITION_PERCENT).toNumber();

    // Pre-compute arc geometry (zero allocation in onUpdate)
    // Arc center at display center to follow circular watch face perimeter
    mArcCenterX = width / 2;
    mArcCenterY = height / 2;
    mArcRadius = (width < height ? width : height) / 2 - ARC_MARGIN_PIXELS;

    // Defensive: Ensure radius is positive
    if (mArcRadius < 10) {
      mArcRadius = 10;
    }

    // Adaptive pen width: thinner on AMOLED to save battery
    mArcPenWidth = mIsAmoled ? 5 : 8;

    // Cache screen height to avoid repeated system calls
    mScreenHeight = height;
  }

  function onUpdate(dc as Graphics.Dc) as Void {
    // Only update colors when background actually changes (more efficient)
    var currentBg = getBackgroundColor();
    if (currentBg != mLastKnownBackground) {
      mLastKnownBackground = currentBg;
      updateColors();
    }

    dc.setColor(mForegroundColor, mBackgroundColor);
    dc.clear();

    if (mIsAmoled) {
      mUpdateCount++;
      if (mUpdateCount >= POSITION_SHIFT_INTERVAL) {
        mUpdateCount = 0;
        // FIX Issue #9: Use pre-computed lookup table instead of complex modulo
        mOffsetIndex = (mOffsetIndex + 1) % PIXEL_OFFSETS.size();
        mPositionOffset = PIXEL_OFFSETS[mOffsetIndex];
      }
    }

    // Use cached screen height instead of system call
    // FIX Issue #16: Use constant
    var isFullScreen = mFieldHeight > (mScreenHeight * FULLSCREEN_THRESHOLD_PERCENT);

    if (isFullScreen) {
      // Always draw arc since it now shows remaining distance (starts full)
      // Battery optimization still applies inside drawProgressArc (skips when <1% remains)
      drawProgressArc(dc);
      drawFullScreen(dc);
    } else {
      drawCompact(dc);
    }
  }

  private function drawFullScreen(dc as Graphics.Dc) as Void {
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];
      // Defensive: Check array bounds before access
      if (idx == null || idx < 0 || idx >= MILESTONE_COUNT) { continue; }

      var yPos = getYPosition(i) + mPositionOffset;
      var xPos = mCenterX + mPositionOffset;  // AMOLED: shift both X and Y
      var isHit = mFinishTimesMs[idx] != null;
      if (mIsAmoled && isHit) {
        dc.setColor(mDimmedColor, Graphics.COLOR_TRANSPARENT);
      } else {
        dc.setColor(mForegroundColor, Graphics.COLOR_TRANSPARENT);
      }
      // Use pre-computed display text (zero allocation)
      dc.drawText(xPos, yPos, Graphics.FONT_MEDIUM, mCachedDisplayTexts[i], Graphics.TEXT_JUSTIFY_CENTER);
    }
    drawStatus(dc);
    drawRemainingDistance(dc);
  }

  private function drawCompact(dc as Graphics.Dc) as Void {
    // Use pre-computed display text (zero allocation)
    dc.setColor(mForegroundColor, Graphics.COLOR_TRANSPARENT);
    dc.drawText(mCenterX, mRow1Y, Graphics.FONT_MEDIUM, mCachedDisplayTexts[0], Graphics.TEXT_JUSTIFY_CENTER);
  }

  private function getYPosition(rowIndex as Lang.Number) as Lang.Number {
    if (rowIndex == 0) {
      return mRow1Y;
    } else if (rowIndex == 1) {
      return mRow2Y;
    } else {
      return mRow3Y;
    }
  }

  // FIX Issue #14: Helper function to avoid duplicate bounds checks
  private function isValidDisplayIndex(idx as Lang.Number?) as Lang.Boolean {
    return idx != null && idx >= 0 && idx < MILESTONE_COUNT;
  }

  private function drawStatus(dc as Graphics.Dc) as Void {
    var statusText = null;
    var statusColor = mForegroundColor;
    var statusFont = Graphics.FONT_XTINY;
    var showHeartRate = false;

    if (!mGpsQualityGood) {
      statusText = "WAITING GPS";
      statusColor = mAccentColor;
    } else if (!mMinDistanceReached || !mSmoothingWindowFull) {
      statusText = "WARMING UP";
      statusColor = mAccentColor;
      statusFont = Graphics.FONT_XTINY;  // Smallest font
    } else if (mAllComplete) {
      statusText = "COMPLETE";
    } else if (mErrorState == 1) {
      statusText = "SAFE MODE";
      statusColor = Graphics.COLOR_RED;
    } else {
      // Warmed up and running normally - show heart rate
      showHeartRate = true;
    }

    if (statusText != null) {
      dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
      var xPos = mCenterX + mPositionOffset;  // AMOLED: shift X
      var yPos = mStatusY + mPositionOffset;

      // Add extra padding for warming up text
      if (statusText.equals("WARMING UP")) {
        yPos += 5;  // Additional 5 pixels padding
      }

      dc.drawText(xPos, yPos, statusFont, statusText, Graphics.TEXT_JUSTIFY_CENTER);
    } else if (showHeartRate && mCurrentHR != null) {
      drawHeartRate(dc);
    }
  }

  //
  // Draw heart rate with heart icon (shown after warming up)
  //
  private function drawHeartRate(dc as Graphics.Dc) as Void {
    // Capture to local variable to prevent race condition
    var hr = mCurrentHR;
    if (hr == null) { return; }

    // Apply top padding for better spacing
    var yPos = mStatusY + mPositionOffset + HEART_RATE_TOP_PADDING;
    var hrText = hr.format("%d");

    // Calculate text width to center the entire display (icon + text)
    // FIX Issue #2: Use cached width estimate instead of getTextDimensions (zero allocation)
    var textWidth = HR_TEXT_WIDTH_ESTIMATE;
    var heartIconWidth = HEART_ICON_SIZE * 2;  // Heart is 2x the icon size wide
    var totalWidth = heartIconWidth + HR_ICON_TEXT_SPACING + textWidth;

    // Center the entire group (heart icon + text)
    var startX = mCenterX - (totalWidth / 2);
    var heartX = startX + heartIconWidth / 2;
    var textX = startX + heartIconWidth + HR_ICON_TEXT_SPACING;

    // Apply pixel shifting on AMOLED to prevent burn-in
    if (mIsAmoled) {
        heartX += mPositionOffset;
        textX += mPositionOffset;
    }

    var heartY = yPos + HEART_ICON_OFFSET_Y;
    if (mIsAmoled) {
        heartY += mPositionOffset;
    }

    // Use green on AMOLED for better burn-in protection (lower OLED power draw)
    var heartColor = mIsAmoled ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;
    dc.setColor(heartColor, Graphics.COLOR_TRANSPARENT);

    // Draw simple heart using two circles and a triangle
    dc.fillCircle(heartX - HEART_ICON_SIZE/2, heartY, HEART_ICON_SIZE);
    dc.fillCircle(heartX + HEART_ICON_SIZE/2, heartY, HEART_ICON_SIZE);

    // Initialize triangle cache on first use
    if (mHeartTriangle == null) {
      mHeartTriangle = [[0, 0], [0, 0], [0, 0]];
    }

    // Update triangle vertices in place (no allocation)
    mHeartTriangle[0][0] = heartX - HEART_ICON_SIZE;
    mHeartTriangle[0][1] = heartY;
    mHeartTriangle[1][0] = heartX + HEART_ICON_SIZE;
    mHeartTriangle[1][1] = heartY;
    mHeartTriangle[2][0] = heartX;
    mHeartTriangle[2][1] = heartY + HEART_ICON_SIZE * 2;

    dc.fillPolygon(mHeartTriangle);

    // Draw HR value to the right of heart with larger font
    dc.setColor(mForegroundColor, Graphics.COLOR_TRANSPARENT);
    dc.drawText(textX, yPos, Graphics.FONT_SMALL, hrText, Graphics.TEXT_JUSTIFY_LEFT);
  }

  private function drawRemainingDistance(dc as Graphics.Dc) as Void {
    // FIX Issue #15: Optimize string check - mRemainingDistanceKm is always non-null String
    // Empty check is more efficient than .length() call
    if (!mRemainingDistanceKm.equals("")) {
      dc.setColor(mAccentColor, Graphics.COLOR_TRANSPARENT);
      var xPos = mCenterX + mPositionOffset;  // AMOLED: shift X
      dc.drawText(xPos, mBottomY + mPositionOffset, Graphics.FONT_MEDIUM, mRemainingDistanceKm, Graphics.TEXT_JUSTIFY_CENTER);
    }
  }

  private function saveToStorage() as Void {
    try {
      var data = {
        "v" => STORAGE_VERSION,
        "times" => mFinishTimesMs,
        "checksum" => calculateChecksum(),
      };
      Storage.setValue(STORAGE_KEY, data);
      // FIX Issue #8: Track successful saves and reset error count
      mLastSuccessfulSave = System.getTimer();
      mStorageErrorCount = 0;
    } catch (ex) {
      // FIX Issue #8: Track storage errors for diagnostics
      mStorageErrorCount++;
      if (DEBUG_LOGGING) {
        System.println("Storage save error #" + mStorageErrorCount + ": " + ex.getErrorMessage());
      }

      // After MAX_CONSECUTIVE_ERRORS failures, user should be aware storage is failing
      // Could add UI indication here if needed
      if (mStorageErrorCount >= MAX_CONSECUTIVE_ERRORS) {
        if (DEBUG_LOGGING) {
          System.println("WARNING: Storage persistently failing - progress may be lost on restart");
        }
      }
    }
  }

  private function loadFromStorage() as Void {
    // DEBUG: Skip storage loading for testing (always start fresh)
    if (DEBUG_IGNORE_STORAGE) {
      if (DEBUG_LOGGING) { System.println("DEBUG: Storage ignored, starting fresh"); }
      clearAllData();
      return;
    }

    try {
      var data = Storage.getValue(STORAGE_KEY);
      if (data instanceof Lang.Dictionary) {
        var version = data.get("v");
        if (version == STORAGE_VERSION) {
          var times = data.get("times");
          // FIX Issue #4: Deep validation of storage data before loading
          if (validateStorageData(times, data.get("checksum"))) {
            if (DEBUG_LOGGING) { System.println("Storage loaded successfully"); }
            mFinishTimesMs = times;
            rebuildDisplay();
            return;
          } else {
            if (DEBUG_LOGGING) { System.println("Storage validation failed, clearing data"); }
          }
        } else {
          if (DEBUG_LOGGING) { System.println("Storage version mismatch, clearing data"); }
        }
      } else {
        if (DEBUG_LOGGING) { System.println("No valid storage found, starting fresh"); }
      }
    } catch (ex) {
      // FIX Issue #17: Consistent error handling
      if (DEBUG_LOGGING) { System.println("Storage load error: " + ex.getErrorMessage()); }
    }
    clearAllData();
  }

  // FIX Issue #4: Validate storage data for corruption
  private function validateStorageData(times as Lang.Object?, checksum as Lang.Object?) as Lang.Boolean {
    // Validate times is an array
    if (!(times instanceof Lang.Array)) {
      return false;
    }

    // Validate array size matches milestone count
    if (times.size() != MILESTONE_COUNT) {
      return false;
    }

    // Validate checksum is a number
    if (!(checksum instanceof Lang.Number)) {
      return false;
    }

    // Temporarily store times to validate checksum
    var savedTimes = mFinishTimesMs;
    mFinishTimesMs = times;

    var lastTime = 0;
    var foundNull = false;

    // Validate each element with enhanced checks
    for (var i = 0; i < MILESTONE_COUNT; i++) {
      var val = times[i];

      if (val == null) {
        foundNull = true;
        continue;
      }

      // If we found a null, subsequent milestones can't be complete
      if (foundNull) {
        mFinishTimesMs = savedTimes;
        return false;  // Data corruption: later milestone completed before earlier one
      }

      if (!(val instanceof Lang.Number) || val < 0 || val > MAX_TIME_REMAINING_MS) {
        mFinishTimesMs = savedTimes;
        return false;
      }

      // Monotonicity check: times must be increasing
      if (val < lastTime) {
        mFinishTimesMs = savedTimes;
        return false;
      }

      // Sanity check: single milestone can't take >100 hours
      if (i > 0 && (val - lastTime) > 360000000) {
        mFinishTimesMs = savedTimes;
        return false;
      }

      lastTime = val;
    }

    // Validate checksum matches
    var calculatedChecksum = calculateChecksum();
    mFinishTimesMs = savedTimes;  // Restore

    return calculatedChecksum == checksum;
  }

  private function calculateChecksum() as Lang.Number {
    var sum = 0;
    for (var i = 0; i < MILESTONE_COUNT; i++) {
      var val = mFinishTimesMs[i];
      if (val != null) {
        // Apply modulo to val first to prevent overflow
        // Prime-based hash to detect position changes
        sum = (sum * 31) % 2147483647;
        sum = (sum + (val % 2147483647)) % 2147483647;
      } else {
        // Different prime for null slots
        sum = (sum * 31 + 7919) % 2147483647;
      }
    }
    return sum;
  }

  private function rebuildDisplay() as Void {
    if (DEBUG_LOGGING) { System.println("=== REBUILD DISPLAY CALLED ==="); }
    var writeIdx = 0;
    var newDisplayIndices = new Lang.Array<Lang.Number?>[DISPLAY_ROW_COUNT];

    // If celebrating a milestone completion, keep it as first display row
    if (mCelebrationStartTimeMs != null && mCelebrationMilestoneIdx != null) {
      if (DEBUG_LOGGING) { System.println("Celebration active for milestone: " + mCelebrationMilestoneIdx); }
      // Check if this is the last milestone (50K)
      var isLastMilestone = (mCelebrationMilestoneIdx == MILESTONE_COUNT - 1);

      if (isLastMilestone) {
        // Last milestone - keep showing it permanently, end celebration
        mCelebrationStartTimeMs = null;
        mCelebrationMilestoneIdx = null;
      } else {
        // Show completed milestone in first row during celebration
        newDisplayIndices[writeIdx] = mCelebrationMilestoneIdx;
        writeIdx++;
      }
    }

    // Fill remaining rows with uncompleted milestones
    for (var i = 0; i < MILESTONE_COUNT && writeIdx < DISPLAY_ROW_COUNT; i++) {
      if (mFinishTimesMs[i] == null) {
        newDisplayIndices[writeIdx] = i;
        writeIdx++;
      }
    }
    mDisplayIndices = newDisplayIndices;
    if (DEBUG_LOGGING) {
      System.println("Rebuilt display indices: [" + mDisplayIndices[0] + ", " + mDisplayIndices[1] + ", " + mDisplayIndices[2] + "]");
    }

    if (writeIdx == 0 && mFinishTimesMs[MILESTONE_COUNT - 1] != null) {
      mAllComplete = true;
    }

    // Initialize cached display arrays for the current display indices
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];
      if (idx != null && idx >= 0 && idx < MILESTONE_COUNT) {
        mCachedLabels[i] = mLabels[idx];
        mCachedTimes[i] = "--:--";
        mCachedDisplayTexts[i] = mCachedLabels[i] + "  " + mCachedTimes[i];
      } else {
        mCachedLabels[i] = "";
        mCachedTimes[i] = "--:--";
        mCachedDisplayTexts[i] = "";
      }
    }
  }

  private function clearAllData() as Void {
    if (DEBUG_LOGGING) { System.println("=== CLEAR ALL DATA CALLED ==="); }
    for (var i = 0; i < MILESTONE_COUNT; i++) {
      mFinishTimesMs[i] = null;
    }
    mDisplayIndices = [0, 1, 2] as Lang.Array<Lang.Number?>;
    mAllComplete = false;
    if (DEBUG_LOGGING) { System.println("Display indices reset to: [0, 1, 2]"); }

    // FIX Issue #10: Add null check for mLabels before accessing
    // Initialize cached display arrays
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      if (mLabels != null && i < mLabels.size()) {
        mCachedLabels[i] = mLabels[i];
        // FIX Issue #3: Use Lang.format to avoid string concatenation
        mCachedDisplayTexts[i] = Lang.format("$1$  $2$", [mCachedLabels[i], mCachedTimes[i]]);
      } else {
        mCachedLabels[i] = "";
        mCachedDisplayTexts[i] = "";
      }
    }

    Storage.deleteValue(STORAGE_KEY);
  }

  function onTimerStart() as Void {}

  function onTimerPause() as Void {
    if (mStateDirty) {
      saveToStorage();
      mStateDirty = false;
    }
  }

  function onTimerStop() as Void {
    if (mStateDirty) {
      saveToStorage();
      mStateDirty = false;
    }
  }

  function onTimerResume() as Void {}

  function onTimerLap() as Void {}

  function onTimerReset() as Void {
    clearAllData();
    mUpdateCount = 0;
    mPositionOffset = 0;
    mSmoothedPaceSecPerM = 0.0d;
    mLastComputeTimeSec = 0.0d;
    mSmoothingWindowFull = false;
    mFirstPaceReadingDone = false;

    // Reset distance and arc state
    mCurrentDistance = 0.0d;
    mArcProgress = 1.0d;  // Arc now inverted: starts full (1.0) at beginning
    mArcColor = Graphics.COLOR_GREEN;
    mRemainingDistanceKm = "";
    mRemainingDistanceMeters = 0.0d;
    mLastRemainingKm = -1.0d;

    // Reset anomaly detection counters
    mLastValidDistance = 0.0d;
    mDistanceStagnationCount = 0;
    mLastValidPace = 0.0d;
    mPaceAnomalyCount = 0;

    // Reset current heart rate
    mCurrentHR = null;

    // Reset celebration state
    mCelebrationStartTimeMs = null;
    mCelebrationMilestoneIdx = null;

    // Reset arc flash state
    mArcFlashStartTimeMs = null;

    // Reset cached display arrays including hash tracking
    // FIX Issue #10: Add null check for mLabels before accessing
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      if (mLabels != null && i < mLabels.size()) {
        mCachedLabels[i] = mLabels[i];
        // FIX Issue #3: Use Lang.format to avoid string concatenation
        mCachedDisplayTexts[i] = Lang.format("$1$  $2$", [mCachedLabels[i], mCachedTimes[i]]);
      } else {
        mCachedLabels[i] = "";
        mCachedDisplayTexts[i] = "";
      }
      mLastDisplayTextHash[i] = 0;
    }
  }

  private function calculateArcProgress() as Lang.Double {
    if (mDisplayIndices.size() == 0 || mCurrentDistance < 0) {
      if (DEBUG_LOGGING) { System.println("CalcArc: Empty indices or negative distance"); }
      return 0.0d;
    }
    var nextMilestoneIdx = mDisplayIndices[0];
    if (DEBUG_LOGGING) { System.println("CalcArc: NextIdx=" + nextMilestoneIdx + ", CurDist=" + mCurrentDistance); }
    if (nextMilestoneIdx == null || nextMilestoneIdx < 0 || nextMilestoneIdx >= MILESTONE_COUNT) {
      if (DEBUG_LOGGING) { System.println("CalcArc: Invalid milestone index"); }
      return 0.0d;
    }
    // Defensive: Ensure index is within array bounds before access
    if (nextMilestoneIdx >= mDistancesCm.size()) {
      return 0.0d;
    }
    var nextMilestoneDistanceCm = mDistancesCm[nextMilestoneIdx];
    var prevMilestoneDistanceCm = 0;
    if (nextMilestoneIdx > 0 && nextMilestoneIdx - 1 < mDistancesCm.size()) {
      prevMilestoneDistanceCm = mDistancesCm[nextMilestoneIdx - 1];
    }
    // FIX Issue #5: Keep as Double to prevent integer overflow for ultramarathon distances
    // Converting 100+ km to cm can exceed Number range (2^31)
    var currentDistanceCm = mCurrentDistance * 100.0d;
    var segmentDistanceCm = nextMilestoneDistanceCm - prevMilestoneDistanceCm;
    if (segmentDistanceCm <= 0) {
      return 0.0d;
    }
    // FIX Issue #5: Work with Double throughout to avoid overflow
    var distanceIntoSegmentCm = currentDistanceCm - prevMilestoneDistanceCm.toDouble();
    var distanceRemainingCm = segmentDistanceCm.toDouble() - distanceIntoSegmentCm;

    // Store remaining distance for color threshold logic
    mRemainingDistanceMeters = distanceRemainingCm / 100.0d;

    // Invert: progress now goes from 1.0 (start) to 0.0 (finish)
    var progress = distanceRemainingCm / segmentDistanceCm.toDouble();
    if (progress < 0.0) {
      progress = 0.0d;
    }
    if (progress > 1.0) {
      progress = 1.0d;
    }
    return progress;
  }

  private function getArcColor(progress as Lang.Double) as Lang.Number {
    // Progress is inverted: 1.0 = start (green), 0.0 = finish (red)
    // Distance-aware thresholds:
    // - If remaining > 10km: yellow at 15%, red at 5%
    // - If remaining <= 10km: yellow at 30%, red at 10%

    var yellowThreshold = 0.30d;  // Default: yellow when 30% remains
    var redThreshold = 0.10d;     // Default: red when 10% remains

    if (mRemainingDistanceMeters > 10000.0d) {  // Over 10km remaining
      yellowThreshold = 0.15d;  // Yellow at 15%
      redThreshold = 0.05d;     // Red at 5%
    }

    if (mIsAmoled) {
      // Use visible colors on AMOLED (not too dim)
      if (progress > yellowThreshold) {
        return Graphics.COLOR_GREEN;  // Bright green for visibility
      } else if (progress > redThreshold) {
        return Graphics.COLOR_YELLOW;  // Bright yellow
      } else {
        return Graphics.COLOR_RED;  // Bright red
      }
    }

    // Full brightness on MIP displays
    if (progress > yellowThreshold) {
      return Graphics.COLOR_GREEN;
    } else if (progress > redThreshold) {
      return Graphics.COLOR_YELLOW;
    } else {
      return Graphics.COLOR_RED;
    }
  }

  private function drawProgressArc(dc as Graphics.Dc) as Void {
    // Debug: Log arc state
    if (DEBUG_LOGGING) {
      System.println("=== DRAW ARC CALLED ===");
      System.println("Arc - Progress: " + mArcProgress + ", Color: " + mArcColor);
      System.println("Arc - NextIdx: " + mDisplayIndices[0] + ", CurDist: " + mCurrentDistance);
      System.println("Arc - RemainingMeters: " + mRemainingDistanceMeters);
      System.println("Arc - Geometry: CenterX=" + mArcCenterX + ", CenterY=" + mArcCenterY + ", Radius=" + mArcRadius);
      System.println("Arc - IsAmoled: " + mIsAmoled);
    }

    // Only draw if there's meaningful distance remaining (battery optimization)
    // Arc is inverted: 1.0 = full (start), 0.0 = empty (finish)
    if (mArcProgress < 0.01) {
      if (DEBUG_LOGGING) { System.println("Arc not drawn - less than 1% remaining"); }
      return;
    }

    // Apply pixel shifting on AMOLED to prevent burn-in
    var arcCenterX = mArcCenterX;
    var arcCenterY = mArcCenterY;
    if (mIsAmoled) {
      arcCenterX += mPositionOffset;
      arcCenterY += mPositionOffset;
    }

    // Use cached geometry (zero allocation)
    dc.setPenWidth(mArcPenWidth);

    // Draw progress arc only (no background arc)
    // Starts from 90° (12 o'clock) and fills clockwise based on progress
    // Clockwise means: 90° → 180° → 270° → 0° (increasing angle values)
    var progressDegrees = (ARC_SPAN * mArcProgress).toNumber();
    var currentEndAngle = ARC_START_ANGLE + progressDegrees;

    // FIX Issue #7: Add bounds check to prevent infinite loop with corrupted data
    // Sanity check: If angle is completely out of bounds, clamp it
    if (currentEndAngle < 0 || currentEndAngle > ARC_ANGLE_OVERFLOW_LIMIT) {
      currentEndAngle = ARC_START_ANGLE;  // Failsafe: reset to start
    }

    dc.setColor(mArcColor, Graphics.COLOR_TRANSPARENT);

    if (DEBUG_LOGGING) {
      System.println("Arc - Drawing from " + ARC_START_ANGLE + " to " + currentEndAngle + " (progressDeg=" + progressDegrees + ")");
    }

    // AMOLED burn-in protection: Draw dashed arc with different animations
    if (mIsAmoled) {
      var dashPattern = AMOLED_DASH_DEGREES + AMOLED_GAP_DEGREES;  // 25 degrees per dash+gap
      var startOffset = 0;
      var maxAngle = currentEndAngle;  // Use unwrapped angle for AMOLED (e.g., 442)

      // Use alternating dashes for full/near-full circle (burn-in protection)
      // Use marching dashes for partial arcs (shows progress direction)
      if (mArcFlashStartTimeMs != null) {
        // FLASH MODE: Alternating pattern with toggle
        startOffset = mDashAlternate ? AMOLED_GAP_DEGREES : 0;
        maxAngle = ARC_START_ANGLE + 360;  // Full circle during flash
      } else if (mArcProgress >= 0.98) {
        // STATIC FULL CIRCLE MODE: Alternating pattern (no animation)
        // Prevents burn-in when showing full circle during warmup
        startOffset = 0;  // Static alternating pattern
        // maxAngle already set to currentEndAngle
      } else {
        // NORMAL MODE: Marching dashes create clockwise motion
        // Offset increases over time, shifting dash pattern clockwise
        // This creates visual effect of dashes marching towards the endpoint
        startOffset = mDashOffset;
        // maxAngle already set to currentEndAngle
      }

      if (DEBUG_LOGGING) {
        System.println("Arc - AMOLED: maxAngle=" + maxAngle + ", startOffset=" + startOffset);
        System.println("Arc - AMOLED: mArcProgress=" + mArcProgress + ", currentEndAngle=" + currentEndAngle);
      }

      // Calculate the total arc span in degrees
      var arcSpanDegrees = maxAngle - ARC_START_ANGLE;

      // Draw dashes from start to end with the calculated offset
      // The offset shifts the entire dash pattern, creating marching effect
      var currentAngle = ARC_START_ANGLE + startOffset;
      var maxIterations = 20;  // Safety: 360°/15° = 24 max dashes
      var iterations = 0;

      if (DEBUG_LOGGING) {
        System.println("Arc - AMOLED Loop: startAngle=" + currentAngle + ", arcSpan=" + arcSpanDegrees + "deg");
      }

      while (currentAngle < maxAngle && iterations < maxIterations) {
        iterations++;
        var dashEnd = currentAngle + AMOLED_DASH_DEGREES;
        if (dashEnd > maxAngle) {
          dashEnd = maxAngle;  // Don't exceed progress point
        }

        // Calculate how far along the arc we are
        var distanceFromStart = currentAngle - ARC_START_ANGLE;

        // Only draw if we haven't exceeded the arc span
        if (distanceFromStart < arcSpanDegrees) {
          // Handle angle wraparound for drawing
          var drawStart = currentAngle % 360;
          var drawEnd = dashEnd % 360;

          if (DEBUG_LOGGING && iterations == 1) {
            System.println("Arc - Drawing dash #" + iterations + ": " + drawStart + " to " + drawEnd + " (dist=" + distanceFromStart + ")");
          }

          // Handle case where dash crosses 360° boundary
          if (drawEnd < drawStart && dashEnd >= 360) {
            // Draw in two parts: currentAngle to 360, and 0 to drawEnd
            dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, drawStart, 359);
            dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, 0, drawEnd);
          } else if (drawStart >= 0) {  // Only draw if start angle is valid
            dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, drawStart, drawEnd);
          }
        }

        currentAngle += dashPattern;
      }

      if (DEBUG_LOGGING) {
        System.println("Arc - AMOLED: Drew " + iterations + " dashes");
      }
    } else {
      // MIP display: Normal solid arc (no burn-in risk)
      // Wrap angle for MIP (drawArc expects 0-359)
      var mipEndAngle = currentEndAngle % 360;
      // Special case: if wrapped back to start, draw to start-1 for near-full circle
      if (mipEndAngle == ARC_START_ANGLE && currentEndAngle > ARC_START_ANGLE) {
        mipEndAngle = ARC_START_ANGLE - 1;
        if (mipEndAngle < 0) {
          mipEndAngle = 359;
        }
      }
      dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, ARC_START_ANGLE, mipEndAngle);
    }

    // Reset pen width
    dc.setPenWidth(1);
  }

}
