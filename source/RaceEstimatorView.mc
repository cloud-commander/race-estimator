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
  private const MAX_OFFSET = 2;

  // EMA smoothing for stable predictions
  private const SMOOTHING_ALPHA = 0.15d; // Use Double for precision
  private const SMOOTHING_WINDOW_SEC = 5;

  // Milestone data
  private var mDistancesCm as Lang.Array<Lang.Number>;
  private var mLabels as Lang.Array<Lang.String>;
  private var mFinishTimesMs as Lang.Array<Lang.Number?>;
  private var mDisplayIndices as Lang.Array<Lang.Number?>;
  private var mCachedTimes as Lang.Array<Lang.String>;
  private var mCachedLabels as Lang.Array<Lang.String>;
  private var mNextMilestonePtr as Lang.Number = 0;

  // State tracking
  private var mGpsQualityGood as Lang.Boolean = false;
  private var mMinDistanceReached as Lang.Boolean = false;
  private var mSmoothingWindowFull as Lang.Boolean = false;
  private var mStateDirty as Lang.Boolean = false;
  private var mAllComplete as Lang.Boolean = false;
  private var mErrorState as Lang.Number = 0;
  private var mConsecutiveErrors as Lang.Number = 0;
  private var mSafeModeCycles as Lang.Number = 0;

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

    // Always start fresh in the simulator
    clearAllData();
    loadFromStorage();
    updateColors();
  }

  private function updateColors() as Void {
    if (mIsAmoled) {
      mBackgroundColor = Graphics.COLOR_BLACK;
      mForegroundColor = Graphics.COLOR_LT_GRAY;
      mAccentColor = Graphics.COLOR_BLUE;
      mDimmedColor = Graphics.COLOR_DK_GRAY;
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
      if (idx != null && mFinishTimesMs[idx] == null && distanceCm >= mDistancesCm[idx] - TOLERANCE_CM) {
        mFinishTimesMs[idx] = timerTimeMs;
        mStateDirty = true;
        if (i == 0) {
          needsRotation = true;
        }
      }
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
      if (idx == null) { continue; }

      if (mFinishTimesMs[idx] != null) {
        mCachedTimes[i] = formatTime(mFinishTimesMs[idx]);
        // Clear remaining distance when first milestone is completed
        if (i == 0) {
          mRemainingDistanceKm = "";
        }
      } else {
        var remainingDistanceMeters = mDistancesCm[idx] / 100.0d - elapsedDistance;
        if (remainingDistanceMeters < 0) {
          mCachedTimes[i] = "0:00";
          if (i == 0) {
            mRemainingDistanceKm = "";
          }
          continue;
        }
        var timeRemainingMs = (remainingDistanceMeters * mSmoothedPaceSecPerM * 1000.0d).toNumber();
        if (timeRemainingMs < 0 || timeRemainingMs > 360000000) {
          mCachedTimes[i] = "99:59:59";
        } else {
          mCachedTimes[i] = formatTime(timeRemainingMs);
        }

        // Calculate remaining distance for the first (next) milestone
        if (i == 0) {
          var remainingKm = remainingDistanceMeters / 1000.0d;
          mRemainingDistanceKm = Lang.format("$1$ km", [remainingKm.format("%.2f")]);
        }
      }
      mCachedLabels[i] = mLabels[idx] + (mFinishTimesMs[idx] != null ? " ✓" : "");
    }

    mArcProgress = calculateArcProgress();
    mArcColor = getArcColor(mArcProgress);

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
    mFieldHeight = height;
    mCenterX = width / 2;
    mStatusY = 15;
    mRow1Y = (height * 0.25).toNumber();
    mRow2Y = (height * 0.45).toNumber();
    mRow3Y = (height * 0.65).toNumber();
    mBottomY = (height * 0.85).toNumber();  // Position at 85% to avoid circular edge
  }

  function onUpdate(dc as Graphics.Dc) as Void {
    updateColors();
    dc.setColor(mForegroundColor, mBackgroundColor);
    dc.clear();

    if (mIsAmoled) {
      mUpdateCount++;
      if (mUpdateCount >= POSITION_SHIFT_INTERVAL) {
        mUpdateCount = 0;
        var cycle = mPositionOffset + MAX_OFFSET;
        cycle = (cycle + 1) % (MAX_OFFSET * 4);
        mPositionOffset = cycle - MAX_OFFSET;
      }
    }

    var screenHeight = System.getDeviceSettings().screenHeight;
    var isFullScreen = (mFieldHeight * 100) / screenHeight > 60;

    if (isFullScreen) {
      drawProgressArc(dc);
      drawFullScreen(dc);
    } else {
      drawCompact(dc);
    }
  }

  private function drawFullScreen(dc as Graphics.Dc) as Void {
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];
      if (idx == null) { continue; }

      var yPos = getYPosition(i) + mPositionOffset;
      var isHit = mFinishTimesMs[idx] != null;
      if (mIsAmoled && isHit) {
        dc.setColor(mDimmedColor, Graphics.COLOR_TRANSPARENT);
      } else {
        dc.setColor(mForegroundColor, Graphics.COLOR_TRANSPARENT);
      }
      var text = mCachedLabels[i] + "  " + mCachedTimes[i];
      dc.drawText(mCenterX, yPos, Graphics.FONT_MEDIUM, text, Graphics.TEXT_JUSTIFY_CENTER);
    }
    drawStatus(dc);
    drawRemainingDistance(dc);
  }

  private function drawCompact(dc as Graphics.Dc) as Void {
    var text = mCachedLabels[0] + "  " + mCachedTimes[0];
    dc.setColor(mForegroundColor, Graphics.COLOR_TRANSPARENT);
    dc.drawText(mCenterX, mRow1Y, Graphics.FONT_MEDIUM, text, Graphics.TEXT_JUSTIFY_CENTER);
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

    if (!mGpsQualityGood) {
      statusText = "WAITING GPS";
      statusColor = mIsAmoled ? mAccentColor : mAccentColor;
    } else if (!mMinDistanceReached || !mSmoothingWindowFull) {
      statusText = "WARMING UP";
      statusColor = mIsAmoled ? mAccentColor : mAccentColor;
    } else if (mAllComplete) {
      statusText = "COMPLETE";
    } else if (mErrorState == 1) {
      statusText = "SAFE MODE";
      statusColor = Graphics.COLOR_RED;
    }

    if (statusText != null) {
      dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
      dc.drawText(mCenterX, mStatusY + mPositionOffset, Graphics.FONT_XTINY, statusText, Graphics.TEXT_JUSTIFY_CENTER);
    }
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
        "ptr" => mNextMilestonePtr,
        "checksum" => calculateChecksum(),
      };
      Storage.setValue(STORAGE_KEY, data);
    } catch (ex) {
      // Ignore storage save errors
    }
  }

  private function loadFromStorage() as Void {
    try {
      var data = Storage.getValue(STORAGE_KEY);
      if (data instanceof Lang.Dictionary) {
        var version = data.get("v");
        if (version == STORAGE_VERSION) {
          mFinishTimesMs = data.get("times");
          mNextMilestonePtr = data.get("ptr");
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
        sum = (sum + val) % 1000000;
      }
    }
    return sum;
  }

  private function rebuildDisplay() as Void {
    var writeIdx = 0;
    var newDisplayIndices = new Lang.Array<Lang.Number?>[DISPLAY_ROW_COUNT];
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
      if (idx != null && idx < mLabels.size()) {
        mCachedLabels[i] = mLabels[idx];
        mCachedTimes[i] = "--:--";
      } else {
        mCachedLabels[i] = "";
        mCachedTimes[i] = "--:--";
      }
    }
  }

  private function clearAllData() as Void {
    for (var i = 0; i < MILESTONE_COUNT; i++) {
      mFinishTimesMs[i] = null;
    }
    mDisplayIndices = [0, 1, 2] as Lang.Array<Lang.Number?>;
    mNextMilestonePtr = 0;
    mAllComplete = false;

    // Initialize cached display arrays
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      if (i < mLabels.size()) {
        mCachedLabels[i] = mLabels[i];
      } else {
        mCachedLabels[i] = "";
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
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      mCachedLabels[i] = mLabels[i];
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
    var nextMilestoneDistanceCm = mDistancesCm[nextMilestoneIdx];
    var prevMilestoneDistanceCm = 0;
    if (nextMilestoneIdx > 0) {
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
    if (progress < 0.7) {
      return Graphics.COLOR_GREEN;
    } else if (progress < 0.9) {
      return Graphics.COLOR_YELLOW;
    } else {
      return Graphics.COLOR_RED;
    }
  }

  private function drawProgressArc(dc as Graphics.Dc) as Void {
    var displayWidth = dc.getWidth();
    var displayHeight = dc.getHeight();
    var centerX = displayWidth / 2;
    var centerY = displayHeight / 2;
    var radius = displayWidth / 2 - 5;
    var penWidth = 8;

    dc.setPenWidth(penWidth);
    dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
    dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, 180, 0);

    // Only draw progress arc if there's actual progress
    if (mArcProgress > 0.0) {
      var endDegree = 180 - (180 * mArcProgress).toNumber();
      if (endDegree < 0) {
        endDegree = 0;
      }

      dc.setColor(mArcColor, Graphics.COLOR_TRANSPARENT);
      dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, 180, endDegree);

      drawArcEndpoints(dc, centerX, centerY, radius, 180, endDegree, mArcColor);
    }
  }

  private function drawArcEndpoints(
    dc as Graphics.Dc,
    centerX as Lang.Number,
    centerY as Lang.Number,
    radius as Lang.Number,
    startDegree as Lang.Number,
    endDegree as Lang.Number,
    color as Lang.Number
  ) as Void {
    try {
      var startRadians = (startDegree.toFloat() * Math.PI) / 180.0;
      var startX = (centerX + radius * Math.cos(startRadians)).toNumber();
      var startY = (centerY + radius * Math.sin(startRadians)).toNumber();

      var endRadians = (endDegree.toFloat() * Math.PI) / 180.0;
      var endX = (centerX + radius * Math.cos(endRadians)).toNumber();
      var endY = (centerY + radius * Math.sin(endRadians)).toNumber();

      var circleRadius = 4;

      dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
      dc.fillCircle(startX, startY, circleRadius);

      dc.setColor(color, Graphics.COLOR_TRANSPARENT);
      dc.fillCircle(endX, endY, circleRadius);
    } catch (ex) {
      // Ignore
    }
  }
}
