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
  private const MAX_OFFSET = 4;  // ±4 pixels for effective burn-in prevention

  // DEBUG: Set to true to ignore storage and always start fresh (REMOVE FOR RELEASE)
  private const DEBUG_IGNORE_STORAGE = true;

  // EMA smoothing for stable predictions
  private const SMOOTHING_ALPHA = 0.15d; // Use Double for precision
  private const SMOOTHING_WINDOW_SEC = 5;

  // Heart icon display constants
  private const HEART_ICON_SIZE = 4;
  private const HEART_ICON_OFFSET_Y = 3;  // Vertical offset for heart icon alignment
  private const HEART_RATE_TOP_PADDING = 10;  // Additional top padding for HR display

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

  // Progress arc state
  private var mCurrentDistance as Lang.Double = 0.0d;
  private var mArcProgress as Lang.Double = 0.0d;
  private var mArcColor as Lang.Number = Graphics.COLOR_GREEN;
  private var mRemainingDistanceKm as Lang.String = "";

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
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedDisplayTexts[i] = "";
      mLastDisplayTextHash[i] = 0;
    }

    // Load saved state from storage
    loadFromStorage();
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

  private function detectDistanceStagnation(elapsedDistance as Lang.Double) as Lang.Boolean {
    if (elapsedDistance == mLastValidDistance) {
      mDistanceStagnationCount++;
      if (mDistanceStagnationCount >= FIT_STAGNATION_THRESHOLD) {
        return false;
      }
    } else {
      mDistanceStagnationCount = 0;
      mLastValidDistance = elapsedDistance;
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
      if (paceRatio > 2.0 || paceRatio < 0.5) {
        mPaceAnomalyCount++;
        if (mPaceAnomalyCount >= 3) {
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
      if (mSafeModeCycles > 10) {
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
      if (mConsecutiveErrors > 3) {
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
      if (hr > 0 && hr < 250) {  // Sanity check
        mCurrentHR = hr;
      }
    } else {
      mCurrentHR = null;
    }

    var timerTime = info.timerTime;
    var elapsedDistance = info.elapsedDistance;

    if (timerTime == null || timerTime <= 0 || elapsedDistance == null || elapsedDistance <= 0) {
      return;
    }

    if (!validateMinimumDistance(elapsedDistance)) {
      return;
    }

    var timerTimeMs = timerTime;
    var timerTimeSec = timerTimeMs / 1000.0d;
    var distanceCm = (elapsedDistance * 100.0d).toNumber();


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

    var needsRotation = false;
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];
      // Defensive: Check array bounds before access
      if (idx != null && idx >= 0 && idx < MILESTONE_COUNT &&
          mFinishTimesMs[idx] == null && distanceCm >= mDistancesCm[idx] - TOLERANCE_CM) {
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

    if (currentPaceSecPerMeter < 0.05 || currentPaceSecPerMeter > 20.0) {
      return;
    }

    if (!detectDistanceStagnation(elapsedDistance.toDouble()) || !detectPaceSpike(currentPaceSecPerMeter.toDouble())) {
      return;
    }

    if (mSmoothedPaceSecPerM == 0.0d) {
      mSmoothedPaceSecPerM = currentPaceSecPerMeter.toDouble();
    } else {
      mSmoothedPaceSecPerM =
        SMOOTHING_ALPHA * currentPaceSecPerMeter.toDouble() +
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
          mCachedLabels[i] = mLabels[idx] + " ✓";
          mCachedDisplayTexts[i] = mCachedLabels[i] + "  " + mCachedTimes[i];
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
            mCachedDisplayTexts[i] = mCachedLabels[i] + "  " + mCachedTimes[i];
            mLastDisplayTextHash[i] = -1;
          }
          if (i == 0) {
            mRemainingDistanceKm = "";
          }
          continue;
        }

        var timeRemainingMs = (remainingDistanceMeters * mSmoothedPaceSecPerM * 1000.0d).toNumber();
        if (timeRemainingMs < 0 || timeRemainingMs > 360000000) {
          timeRemainingMs = 360000000;
        }

        // Create hash from time in seconds to reduce update frequency
        currentHash = (timeRemainingMs / 1000).toNumber();

        // Only update strings when seconds change
        if (currentHash != mLastDisplayTextHash[i]) {
          mCachedTimes[i] = formatTime(timeRemainingMs);
          mCachedLabels[i] = mLabels[idx];
          mCachedDisplayTexts[i] = mCachedLabels[i] + "  " + mCachedTimes[i];
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

    // Check if arc flash has ended (3 seconds after milestone)
    if (mArcFlashStartTimeMs != null && timerTimeMs - mArcFlashStartTimeMs >= ARC_FLASH_DURATION_MS) {
      // Flash ended - reset arc to 0% for next milestone
      mArcFlashStartTimeMs = null;
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
    if (sec > 359999) {
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
    updateColors();
    dc.setColor(mForegroundColor, mBackgroundColor);
    dc.clear();

    if (mIsAmoled) {
      mUpdateCount++;
      if (mUpdateCount >= POSITION_SHIFT_INTERVAL) {
        mUpdateCount = 0;
        // Cycle through range: -MAX_OFFSET to +MAX_OFFSET (e.g., -4, -3, -2, -1, 0, 1, 2, 3, 4)
        mPositionOffset = (mPositionOffset + 1 - (-MAX_OFFSET)) % (MAX_OFFSET * 2 + 1) + (-MAX_OFFSET);
      }
    }

    // Use cached screen height instead of system call
    var isFullScreen = mFieldHeight > (mScreenHeight * 3 / 5); // 60% = 3/5

    if (isFullScreen) {
      // Draw arc if minimum distance reached (battery optimization inside drawProgressArc)
      if (mMinDistanceReached) {
        drawProgressArc(dc);
      }
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
      var isHit = mFinishTimesMs[idx] != null;
      if (mIsAmoled && isHit) {
        dc.setColor(mDimmedColor, Graphics.COLOR_TRANSPARENT);
      } else {
        dc.setColor(mForegroundColor, Graphics.COLOR_TRANSPARENT);
      }
      // Use pre-computed display text (zero allocation)
      dc.drawText(mCenterX, yPos, Graphics.FONT_MEDIUM, mCachedDisplayTexts[i], Graphics.TEXT_JUSTIFY_CENTER);
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

  private function drawStatus(dc as Graphics.Dc) as Void {
    var statusText = null;
    var statusColor = mForegroundColor;
    var showHeartRate = false;

    if (!mGpsQualityGood) {
      statusText = "WAITING GPS";
      statusColor = mAccentColor;
    } else if (!mMinDistanceReached || !mSmoothingWindowFull) {
      statusText = "WARMING UP";
      statusColor = mAccentColor;
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
      dc.drawText(mCenterX, mStatusY + mPositionOffset, Graphics.FONT_XTINY, statusText, Graphics.TEXT_JUSTIFY_CENTER);
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
    var textDimensions = dc.getTextDimensions(hrText, Graphics.FONT_SMALL);
    var textWidth = textDimensions[0];
    var heartIconWidth = HEART_ICON_SIZE * 2;  // Heart is 2x the icon size wide
    var spacing = 5;  // Space between heart and text
    var totalWidth = heartIconWidth + spacing + textWidth;

    // Center the entire group (heart icon + text)
    var startX = mCenterX - (totalWidth / 2);
    var heartX = startX + heartIconWidth / 2;
    var textX = startX + heartIconWidth + spacing;

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
    if (mRemainingDistanceKm.length() > 0) {
      dc.setColor(mAccentColor, Graphics.COLOR_TRANSPARENT);
      dc.drawText(mCenterX, mBottomY + mPositionOffset, Graphics.FONT_MEDIUM, mRemainingDistanceKm, Graphics.TEXT_JUSTIFY_CENTER);
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
    } catch (ex) {
      // Ignore storage save errors
    }
  }

  private function loadFromStorage() as Void {
    // DEBUG: Skip storage loading for testing (always start fresh)
    if (DEBUG_IGNORE_STORAGE) {
      clearAllData();
      return;
    }

    try {
      var data = Storage.getValue(STORAGE_KEY);
      if (data instanceof Lang.Dictionary) {
        var version = data.get("v");
        if (version == STORAGE_VERSION) {
          mFinishTimesMs = data.get("times");
          if (calculateChecksum() == data.get("checksum")) {
            rebuildDisplay();
            return;
          }
        }
      }
    } catch (ex) {
      // Ignore storage load errors
    }
    clearAllData();
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
    var writeIdx = 0;
    var newDisplayIndices = new Lang.Array<Lang.Number?>[DISPLAY_ROW_COUNT];

    // If celebrating a milestone completion, keep it as first display row
    if (mCelebrationStartTimeMs != null && mCelebrationMilestoneIdx != null) {
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
    for (var i = 0; i < MILESTONE_COUNT; i++) {
      mFinishTimesMs[i] = null;
    }
    mDisplayIndices = [0, 1, 2] as Lang.Array<Lang.Number?>;
    mAllComplete = false;

    // Initialize cached display arrays
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      if (i < mLabels.size()) {
        mCachedLabels[i] = mLabels[i];
        mCachedDisplayTexts[i] = mCachedLabels[i] + "  " + mCachedTimes[i];
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
    mArcProgress = 0.0d;
    mArcColor = Graphics.COLOR_GREEN;
    mRemainingDistanceKm = "";
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
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      mCachedLabels[i] = mLabels[i];
      mCachedDisplayTexts[i] = mCachedLabels[i] + "  " + mCachedTimes[i];
      mLastDisplayTextHash[i] = 0;
    }
  }

  private function calculateArcProgress() as Lang.Double {
    if (mDisplayIndices.size() == 0 || mCurrentDistance < 0) {
      return 0.0d;
    }
    var nextMilestoneIdx = mDisplayIndices[0];
    if (nextMilestoneIdx == null || nextMilestoneIdx < 0 || nextMilestoneIdx >= MILESTONE_COUNT) {
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
    var currentDistanceCm = (mCurrentDistance * 100.0d).toNumber();
    var segmentDistanceCm = nextMilestoneDistanceCm - prevMilestoneDistanceCm;
    if (segmentDistanceCm <= 0) {
      return 0.0d;
    }
    var distanceIntoSegmentCm = currentDistanceCm - prevMilestoneDistanceCm;
    var progress = distanceIntoSegmentCm.toDouble() / segmentDistanceCm.toDouble();
    if (progress < 0.0) {
      progress = 0.0d;
    }
    if (progress > 1.0) {
      progress = 1.0d;
    }
    return progress;
  }

  private function getArcColor(progress as Lang.Double) as Lang.Number {
    if (mIsAmoled) {
      // Use dimmer, battery-friendly colors on AMOLED
      if (progress < 0.7) {
        return Graphics.COLOR_DK_GREEN;
      } else if (progress < 0.9) {
        return 0xAAAA00;  // Dim yellow
      } else {
        return Graphics.COLOR_DK_RED;
      }
    }

    // Full brightness on MIP displays
    if (progress < 0.7) {
      return Graphics.COLOR_GREEN;
    } else if (progress < 0.9) {
      return Graphics.COLOR_YELLOW;
    } else {
      return Graphics.COLOR_RED;
    }
  }

  private function drawProgressArc(dc as Graphics.Dc) as Void {
    // Only draw if there's meaningful progress (battery optimization)
    if (mArcProgress < 0.01) {
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

    // Handle wrap-around for full circle (e.g., 90° + 360° = 450° → wraps to 90°)
    while (currentEndAngle >= 360) {
      currentEndAngle = currentEndAngle - 360;
    }

    dc.setColor(mArcColor, Graphics.COLOR_TRANSPARENT);
    // ARC_CLOCKWISE draws from start to end in increasing angle direction
    dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, ARC_START_ANGLE, currentEndAngle);

    // Reset pen width
    dc.setPenWidth(1);
  }

}
