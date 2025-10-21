using Toybox.Lang;
using Toybox.Activity;
using Toybox.System;
using Toybox.Position;
using Toybox.Graphics;
using Toybox.WatchUi;

class RaceEstimatorView extends WatchUi.DataField {
  // Constants
  private const MILESTONE_COUNT = 9;
  private const DISPLAY_ROW_COUNT = 3;
  private const TOLERANCE_CM = 500;
  private const MIN_PREDICTION_DISTANCE = 100;
  private const POSITION_SHIFT_INTERVAL = 120;

  // DEBUG: Ignore storage and always start fresh (automatically disabled in release builds)
  (:debug)
  private const DEBUG_IGNORE_STORAGE = true; // SIMULATOR: Always start fresh
  (:release)
  private const DEBUG_IGNORE_STORAGE = false; // PRODUCTION: Storage enabled

  // DEBUG: Enable verbose logging (automatically disabled in release builds)
  (:debug)
  private const DEBUG_LOGGING = true;
  (:release)
  private const DEBUG_LOGGING = false;

  // Heart icon display constants
  private const HEART_ICON_SIZE = 4;
  private const HEART_ICON_OFFSET_Y = 3; // Vertical offset for heart icon alignment
  private const HEART_RATE_TOP_PADDING = 10; // Additional top padding for HR display
  private const HR_TEXT_WIDTH_ESTIMATE = 30; // Conservative estimate for 3-digit HR (Issue #2)
  private const HR_ICON_TEXT_SPACING = 5; // Space between heart icon and text

  private const BOTTOM_TEXT_POSITION_PERCENT = 0.8;

  // Core business logic (refactored to separate classes)
  private var mMilestones as MilestoneManager;
  private var mPaceEstimator as PaceEstimator;
  private var mPersistence as PersistenceManager;
  private var mDisplayCache as DisplayTextCache;
  private var mBurnInProtection as AmoledBurnInManager;
  private var mDataValidator as ActivityDataValidator;
  private var mColorScheme as ColorSchemeManager;
  private var mStateDirty as Lang.Boolean = false;
  private var mErrorState as Lang.Number = 0;
  private var mConsecutiveErrors as Lang.Number = 0;
  private var mSafeModeCycles as Lang.Number = 0;

  // Display properties
  private var mIsAmoled as Lang.Boolean = false;

  // Validation thresholds (Issue #16 - Extract magic numbers)
  private const MAX_CONSECUTIVE_ERRORS = 3;
  private const SAFE_MODE_RECOVERY_CYCLES = 10;
  private const HR_SANITY_MIN = 0;
  private const HR_SANITY_MAX = 250;
  private const MIN_DISTANCE_EPSILON = 0.1; // 10cm minimum distance
  private const MAX_TIME_REMAINING_MS = 360000000; // 100 hours max
  private const FULLSCREEN_THRESHOLD_PERCENT = 0.6; // 60% = 3/5

  // Remaining distance display
  private var mRemainingDistanceKm as Lang.String = "";

  // Layout
  private var mCenterX as Lang.Number = 0;
  private var mRow1Y as Lang.Number = 0;
  private var mRow2Y as Lang.Number = 0;
  private var mRow3Y as Lang.Number = 0;
  private var mStatusY as Lang.Number = 0;
  private var mBottomY as Lang.Number = 0;
  private var mFieldHeight as Lang.Number = 0;

  // Heart rate display
  private var mCurrentHR as Lang.Number? = null;

  // Caching to reduce allocations in hot path
  private var mLastRemainingKm as Lang.Double = -1.0d;

  // Screen height cache to avoid repeated system calls
  private var mScreenHeight as Lang.Number = 100; // Safe default to prevent division issues

  // Heart icon triangle cache (reusable to avoid allocations)
  private var mHeartTriangle as Lang.Array<Lang.Array<Lang.Number> >?;

  // Optimization tracking (Issue #8, #13, #17)
  private var mLastKnownBackground as Lang.Number = Graphics.COLOR_BLACK;
  private var mStorageErrorCount as Lang.Number = 0;

  function initialize() {
    DataField.initialize();

    var settings = System.getDeviceSettings();
    if (settings has :requiresBurnInProtection) {
      mIsAmoled = settings.requiresBurnInProtection;
    }

    // Initialize core business logic classes
    mMilestones = new MilestoneManager(
      MILESTONE_COUNT,
      DISPLAY_ROW_COUNT,
      DEBUG_LOGGING
    );
    mPaceEstimator = new PaceEstimator(DEBUG_LOGGING);
    mPersistence = new PersistenceManager(5000, DEBUG_LOGGING); // 5 second save throttle
    mDisplayCache = new DisplayTextCache(DISPLAY_ROW_COUNT, DEBUG_LOGGING);
    mBurnInProtection = new AmoledBurnInManager(
      POSITION_SHIFT_INTERVAL,
      mIsAmoled,
      DEBUG_LOGGING
    );
    mDataValidator = new ActivityDataValidator(
      MIN_PREDICTION_DISTANCE,
      DEBUG_LOGGING
    );
    mColorScheme = new ColorSchemeManager(mIsAmoled, DEBUG_LOGGING);

    // Load saved state from storage (will override defaults if valid data exists)
    loadFromStorage();

    if (DEBUG_LOGGING) {
      System.println("=== AFTER STORAGE LOAD ===");
      var displayIndices = mMilestones.getDisplayIndices();
      System.println(
        "Display indices: [" +
          displayIndices[0] +
          ", " +
          displayIndices[1] +
          ", " +
          displayIndices[2] +
          "]"
      );
      System.println(
        "Labels: [" +
          mDisplayCache.getLabel(0) +
          ", " +
          mDisplayCache.getLabel(1) +
          ", " +
          mDisplayCache.getLabel(2) +
          "]"
      );
    }

    // Initialize color scheme
    mColorScheme.updateColors(getBackgroundColor());
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
        System.println(
          "Compute error #" + mConsecutiveErrors + ": " + ex.getErrorMessage()
        );
      }
      // FIX Issue #16: Use constant for max errors
      if (mConsecutiveErrors > MAX_CONSECUTIVE_ERRORS) {
        if (DEBUG_LOGGING) {
          System.println(
            "CRITICAL: Entering safe mode after " +
              MAX_CONSECUTIVE_ERRORS +
              " consecutive errors"
          );
        }
        enterSafeMode();
      }
    }
  }

  private function computeImpl(info as Activity.Info) as Void {
    // Validate GPS data quality
    if (!mDataValidator.validateGpsData(info)) {
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
    if (
      timerTime == null ||
      timerTime <= 0 ||
      elapsedDistance == null ||
      elapsedDistance < MIN_DISTANCE_EPSILON
    ) {
      return;
    }

    // Validate minimum distance threshold
    if (!mDataValidator.validateMinimumDistance(elapsedDistance)) {
      return;
    }

    var timerTimeMs = timerTime;
    var timerTimeSec = timerTimeMs / 1000.0d;
    // Keep distance as Double to prevent overflow for ultramarathons (50K+)
    var distanceCm = elapsedDistance * 100.0d;

    // Check milestone completions and handle celebration state
    var needsRotation = mMilestones.checkAndMarkCompletions(
      distanceCm,
      timerTimeMs,
      TOLERANCE_CM
    );
    if (needsRotation) {
      mMilestones.rebuildDisplay();
      mStateDirty = true;
    }

    // Update pace estimation with anomaly detection
    var currentPaceSecPerMeter = timerTimeSec / elapsedDistance;
    if (
      !mPaceEstimator.updatePace(
        currentPaceSecPerMeter,
        elapsedDistance,
        timerTimeSec
      )
    ) {
      // Pace rejected due to anomaly - skip this update
      return;
    }

    var smoothedPace = mPaceEstimator.getSmoothedPace();

    var displayIndices = mMilestones.getDisplayIndices();
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = displayIndices[i];
      // Defensive: Check array bounds before access
      if (idx == null || idx < 0 || idx >= MILESTONE_COUNT) {
        continue;
      }

      var finishTime = mMilestones.getMilestoneFinishTime(idx);

      if (finishTime != null) {
        // Update cache for completed milestone
        mDisplayCache.updateCompleted(
          i,
          mMilestones.getMilestoneLabel(idx),
          finishTime
        );

        // Clear remaining distance when first milestone is completed
        if (i == 0) {
          mRemainingDistanceKm = "";
        }
      } else {
        var remainingDistanceMeters =
          mMilestones.getMilestoneDistanceCm(idx) / 100.0d - elapsedDistance;
        if (remainingDistanceMeters < 0) {
          // Update cache for zero state (distance reached but not marked complete)
          mDisplayCache.updateZero(i, mMilestones.getMilestoneLabel(idx));
          if (i == 0) {
            mRemainingDistanceKm = "";
          }
          continue;
        }

        var timeRemainingMs = (
          remainingDistanceMeters *
          smoothedPace *
          1000.0d
        ).toNumber();
        // FIX Issue #16: Use constant
        if (timeRemainingMs < 0 || timeRemainingMs > MAX_TIME_REMAINING_MS) {
          timeRemainingMs = MAX_TIME_REMAINING_MS;
        }

        // Update cache for in-progress milestone
        mDisplayCache.updateRemaining(
          i,
          mMilestones.getMilestoneLabel(idx),
          timeRemainingMs
        );

        // Calculate remaining distance for the first (next) milestone
        // Only update when value changes significantly (>0.01 km)
        if (i == 0) {
          var remainingKm = remainingDistanceMeters / 1000.0d;
          var kmDiff = remainingKm - mLastRemainingKm;
          if (kmDiff < -0.01 || kmDiff > 0.01) {
            mLastRemainingKm = remainingKm;
            mRemainingDistanceKm = Lang.format("$1$ km", [
              remainingKm.format("%.2f"),
            ]);
          }
        }
      }
    }

    if (mStateDirty) {
      saveToStorage(timerTimeMs);
      mStateDirty = false;
    }
  }

  private function enterSafeMode() as Void {
    mErrorState = 1;
    mSafeModeCycles = 0;
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mDisplayCache.setInitial(i, "ERROR", "--:--");
    }
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

    // Cache screen height to avoid repeated system calls
    mScreenHeight = height;
  }

  function onUpdate(dc as Graphics.Dc) as Void {
    // Only update colors when background actually changes (more efficient)
    var currentBg = getBackgroundColor();
    if (currentBg != mLastKnownBackground) {
      mLastKnownBackground = currentBg;
      mColorScheme.updateColors(currentBg);
    }

    dc.setColor(
      mColorScheme.getForegroundColor(),
      mColorScheme.getBackgroundColor()
    );
    dc.clear();

    // Update AMOLED burn-in protection (pixel shifting)
    mBurnInProtection.update();

    // Use cached screen height instead of system call
    // FIX Issue #16: Use constant
    var isFullScreen =
      mFieldHeight > mScreenHeight * FULLSCREEN_THRESHOLD_PERCENT;

    if (isFullScreen) {
      drawFullScreen(dc);
    } else {
      drawCompact(dc);
    }
  }

  private function drawFullScreen(dc as Graphics.Dc) as Void {
    var displayIndices = mMilestones.getDisplayIndices();
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = displayIndices[i];
      // Defensive: Check array bounds before access
      if (idx == null || idx < 0 || idx >= MILESTONE_COUNT) {
        continue;
      }

      var offset = mBurnInProtection.getOffset();
      var yPos = getYPosition(i) + offset;
      var isHit = mMilestones.getMilestoneFinishTime(idx) != null;
      if (mIsAmoled && isHit) {
        dc.setColor(mColorScheme.getDimmedColor(), Graphics.COLOR_TRANSPARENT);
      } else {
        dc.setColor(
          mColorScheme.getForegroundColor(),
          Graphics.COLOR_TRANSPARENT
        );
      }

      // Draw label and time with proper visual hierarchy
      var label = mDisplayCache.getLabel(i);
      var time = mDisplayCache.getTime(i);

      // P0 Fix: All labels now FONT_SMALL (readable), all times FONT_MEDIUM (prominent)
      var labelFont = Graphics.FONT_SMALL;
      var timeFont = Graphics.FONT_MEDIUM;

      // P0 Fix: Dynamically center label+time pair based on display width
      // Calculate approximate widths for label and time (using proportional spacing)
      // Scale estimates based on field height so larger screens get larger spacing
      var scale = (mFieldHeight / 200.0).toNumber(); // 200 is base height reference
      if (scale < 0.75) {
        scale = 0.75;
      } // lower bound
      if (scale > 2.0) {
        scale = 2.0;
      } // upper bound to avoid runaway sizes
      var labelCharPx = (7 * scale).toNumber();
      var timeCharPx = (10 * scale).toNumber();
      var labelWidth = (label.length() * labelCharPx).toNumber();
      var timeWidth = (time.length() * timeCharPx).toNumber();
      var spacing = (30 * scale).toNumber(); // Space between label and time
      var totalWidth = labelWidth + spacing + timeWidth;

      // Center the entire label+time group within the screen
      var startX = mCenterX - totalWidth / 2;
      var labelX = startX;
      var timeX = labelX + labelWidth + spacing;

      dc.drawText(
        labelX + offset,
        yPos,
        labelFont,
        label,
        Graphics.TEXT_JUSTIFY_LEFT
      );
      dc.drawText(
        timeX + offset,
        yPos,
        timeFont,
        time,
        Graphics.TEXT_JUSTIFY_LEFT
      );
    }

    drawStatus(dc);
    drawRemainingDistance(dc);
  }

  private function drawCompact(dc as Graphics.Dc) as Void {
    // Match full-screen layout improvements: separate label and time with proper hierarchy
    var label = mDisplayCache.getLabel(0);
    var time = mDisplayCache.getTime(0);

    dc.setColor(mColorScheme.getForegroundColor(), Graphics.COLOR_TRANSPARENT);

    // Dynamically center label+time pair based on display width
    // Use same scaling strategy as full-screen to avoid overlap on large displays
    var scale = (mFieldHeight / 200.0).toNumber();
    if (scale < 0.75) {
      scale = 0.75;
    }
    if (scale > 2.0) {
      scale = 2.0;
    }
    var labelCharPx = (7 * scale).toNumber();
    var timeCharPx = (10 * scale).toNumber();
    var labelWidth = (label.length() * labelCharPx).toNumber();
    var timeWidth = (time.length() * timeCharPx).toNumber();
    var spacing = (30 * scale).toNumber(); // Space between label and time
    var totalWidth = labelWidth + spacing + timeWidth;

    // Center the entire label+time group within the screen
    var startX = mCenterX - totalWidth / 2;
    var labelX = startX;
    var timeX = labelX + labelWidth + spacing;

    dc.drawText(
      labelX,
      mRow1Y,
      Graphics.FONT_SMALL,
      label,
      Graphics.TEXT_JUSTIFY_LEFT
    );
    dc.drawText(
      timeX,
      mRow1Y,
      Graphics.FONT_MEDIUM,
      time,
      Graphics.TEXT_JUSTIFY_LEFT
    );
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
    var statusColor = mColorScheme.getForegroundColor();
    var statusFont = Graphics.FONT_XTINY;
    var showHeartRate = false;

    if (!mDataValidator.isGpsQualityGood()) {
      statusText = "WAITING GPS";
      statusColor = mColorScheme.getAccentColor();
    } else if (
      !mDataValidator.isMinDistanceReached() ||
      !mPaceEstimator.isWarmedUp()
    ) {
      statusText = "WARMING UP";
      statusColor = mColorScheme.getAccentColor();
      statusFont = Graphics.FONT_XTINY; // Smallest font
    } else if (mMilestones.isAllComplete()) {
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
      var offset = mBurnInProtection.getOffset();
      var xPos = mCenterX + offset; // AMOLED: shift X
      var yPos = mStatusY + offset;

      // Add extra padding for warming up text
      if (statusText.equals("WARMING UP")) {
        yPos += 5; // Additional 5 pixels padding
      }

      dc.drawText(
        xPos,
        yPos,
        statusFont,
        statusText,
        Graphics.TEXT_JUSTIFY_CENTER
      );
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
    if (hr == null) {
      return;
    }

    // Apply top padding for better spacing
    var offset = mBurnInProtection.getOffset();
    var yPos = mStatusY + offset + HEART_RATE_TOP_PADDING;
    var hrText = hr.format("%d");

    // Calculate text width to center the entire display (icon + text)
    // FIX Issue #2: Use cached width estimate instead of getTextDimensions (zero allocation)
    var textWidth = HR_TEXT_WIDTH_ESTIMATE;
    var heartIconWidth = HEART_ICON_SIZE * 2; // Heart is 2x the icon size wide
    var totalWidth = heartIconWidth + HR_ICON_TEXT_SPACING + textWidth;

    // Center the entire group (heart icon + text)
    var startX = mCenterX - totalWidth / 2;
    var heartX = startX + heartIconWidth / 2;
    var textX = startX + heartIconWidth + HR_ICON_TEXT_SPACING;

    // Apply pixel shifting on AMOLED to prevent burn-in
    if (mIsAmoled) {
      heartX += offset;
      textX += offset;
    }

    var heartY = yPos + HEART_ICON_OFFSET_Y;
    if (mIsAmoled) {
      heartY += offset;
    }

    // Use green on AMOLED for better burn-in protection (lower OLED power draw)
    var heartColor = mIsAmoled ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;
    dc.setColor(heartColor, Graphics.COLOR_TRANSPARENT);

    // Draw simple heart using two circles and a triangle
    dc.fillCircle(heartX - HEART_ICON_SIZE / 2, heartY, HEART_ICON_SIZE);
    dc.fillCircle(heartX + HEART_ICON_SIZE / 2, heartY, HEART_ICON_SIZE);

    // Initialize triangle cache on first use
    if (mHeartTriangle == null) {
      mHeartTriangle = [
        [0, 0],
        [0, 0],
        [0, 0],
      ];
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
    dc.setColor(mColorScheme.getForegroundColor(), Graphics.COLOR_TRANSPARENT);
    dc.drawText(
      textX,
      yPos,
      Graphics.FONT_SMALL,
      hrText,
      Graphics.TEXT_JUSTIFY_LEFT
    );
  }

  private function drawRemainingDistance(dc as Graphics.Dc) as Void {
    // FIX Issue #15: Optimize string check - mRemainingDistanceKm is always non-null String
    // Empty check is more efficient than .length() call
    if (!mRemainingDistanceKm.equals("")) {
      dc.setColor(mColorScheme.getAccentColor(), Graphics.COLOR_TRANSPARENT);
      var offset = mBurnInProtection.getOffset();
      var xPos = mCenterX + offset; // AMOLED: shift X
      dc.drawText(
        xPos,
        mBottomY + offset,
        Graphics.FONT_SMALL,
        mRemainingDistanceKm,
        Graphics.TEXT_JUSTIFY_CENTER
      );
    }
  }

  private function saveToStorage(timerTimeMs as Lang.Number?) as Void {
    var finishTimes = mMilestones.getFinishTimesMs();
    // Use 0 if timerTimeMs not provided (pause/stop) - bypasses throttle
    var timeMs = timerTimeMs != null ? timerTimeMs : 0;

    if (mPersistence.saveFinishTimes(finishTimes, timeMs)) {
      // FIX Issue #8: Reset error count on successful save
      mStorageErrorCount = 0;
    } else {
      // FIX Issue #8: Track storage errors for diagnostics
      mStorageErrorCount++;

      // After MAX_CONSECUTIVE_ERRORS failures, user should be aware storage is failing
      if (mStorageErrorCount >= MAX_CONSECUTIVE_ERRORS) {
        if (DEBUG_LOGGING) {
          System.println(
            "WARNING: Storage persistently failing - progress may be lost on restart"
          );
        }
      }
    }
  }

  private function loadFromStorage() as Void {
    // DEBUG: Skip storage loading for testing (always start fresh)
    if (DEBUG_IGNORE_STORAGE) {
      if (DEBUG_LOGGING) {
        System.println("DEBUG: Storage ignored, starting fresh");
      }
      clearAllData();
      return;
    }

    var loadedTimes = mPersistence.loadFinishTimes(MILESTONE_COUNT);
    if (loadedTimes != null) {
      if (DEBUG_LOGGING) {
        System.println("Storage loaded successfully");
      }
      mMilestones.setFinishTimesMs(loadedTimes);
      mMilestones.rebuildDisplay();
    } else {
      if (DEBUG_LOGGING) {
        System.println("No valid storage found, starting fresh");
      }
      clearAllData();
    }
  }

  private function clearAllData() as Void {
    if (DEBUG_LOGGING) {
      System.println("=== CLEAR ALL DATA CALLED ===");
    }

    // Reset milestone manager
    mMilestones.reset();

    // Initialize cached display arrays
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mDisplayCache.setInitial(i, mMilestones.getMilestoneLabel(i), "--:--");
    }

    mPersistence.clearStorage();
  }

  function onTimerStart() as Void {}

  function onTimerPause() as Void {
    if (mStateDirty) {
      saveToStorage(null); // Force save on pause (bypass throttle)
      mStateDirty = false;
    }
  }

  function onTimerStop() as Void {
    if (mStateDirty) {
      saveToStorage(null); // Force save on stop (bypass throttle)
      mStateDirty = false;
    }
  }

  function onTimerResume() as Void {}

  function onTimerLap() as Void {}

  function onTimerReset() as Void {
    clearAllData();
    mBurnInProtection.reset();

    // Reset pace estimator
    mPaceEstimator.reset();

    // Reset distance state
    mRemainingDistanceKm = "";
    mLastRemainingKm = -1.0d;

    // Reset current heart rate
    mCurrentHR = null;

    // Reset milestones
    mMilestones.reset();

    // Reset cached display arrays
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mDisplayCache.setInitial(i, mMilestones.getMilestoneLabel(i), "--:--");
    }
  }
}
