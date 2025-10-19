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

  // Milestone data
  private var mDistancesCm as Lang.Array<Lang.Number>;
  private var mLabels as Lang.Array<Lang.String>;
  private var mFinishTimesMs as Lang.Array<Lang.Number?>;
  private var mDisplayIndices as Lang.Array<Lang.Number>;
  private var mCachedTimes as Lang.Array<Lang.String>;
  private var mCachedLabels as Lang.Array<Lang.String>;
  private var mNextMilestonePtr as Lang.Number = 0;

  // State tracking
  private var mGpsQualityGood as Lang.Boolean = false;
  private var mMinDistanceReached as Lang.Boolean = false;
  private var mStateDirty as Lang.Boolean = false;
  private var mAllComplete as Lang.Boolean = false;
  private var mErrorState as Lang.Number = 0;
  private var mConsecutiveErrors as Lang.Number = 0;
  private var mSafeModeCycles as Lang.Number = 0;

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
  private var mLastValidDistance as Lang.Float = 0.0;
  private var mDistanceStagnationCount as Lang.Number = 0;
  private var mLastValidPace as Lang.Float = 0.0;
  private var mPaceAnomalyCount as Lang.Number = 0;
  private var mLastValidTimer as Lang.Number = 0; // Track last timer value to detect time skips
  private const FIT_STAGNATION_THRESHOLD = 5; // 5 consecutive updates without distance change
  private const MAX_REASONABLE_PACE = 20.0; // sec/m (3 min/km minimum = fastest elite)
  private const MIN_REASONABLE_PACE = 0.05; // sec/m (20 m/s = 72 km/h, clearly wrong)
  private const MAX_TIME_SKIP_CENTISEC = 50000; // 500 seconds = ~8 min. Larger jumps allow time skipping in simulator

  // Progress arc state (distance-based progress toward next milestone)
  private var mCurrentDistance as Lang.Float = 0.0; // Current distance in meters (from Activity.Info.elapsedDistance)
  private var mArcProgress as Lang.Float = 0.0; // Progress ratio [0.0, 1.0] cached from compute()
  private var mArcColor as Lang.Number = Graphics.COLOR_GREEN; // Arc color cached from compute()

  // Layout
  private var mCenterX as Lang.Number = 0;
  private var mRow1Y as Lang.Number = 0;
  private var mRow2Y as Lang.Number = 0;
  private var mRow3Y as Lang.Number = 0;
  private var mStatusY as Lang.Number = 0;
  private var mFieldHeight as Lang.Number = 0;

  function initialize() {
    DataField.initialize();

    // Detect AMOLED
    var settings = System.getDeviceSettings();
    if (settings has :requiresBurnInProtection) {
      mIsAmoled = settings.requiresBurnInProtection;
    }

    // Initialize milestones
    mDistancesCm =
      [
        500000, 804672, 1000000, 1310000, 1609344, 2109750, 2620000, 4219500,
        5000000,
      ] as Lang.Array<Lang.Number>;
    mLabels =
      ["5K", "5MI", "10K", "13.1K", "10MI", "HM", "26.2K", "FM", "50K"] as
      Lang.Array<Lang.String>;

    mFinishTimesMs = new Lang.Array<Lang.Number?>[MILESTONE_COUNT];
    for (var i = 0; i < MILESTONE_COUNT; i++) {
      mFinishTimesMs[i] = null;
    }

    mDisplayIndices = [0, 1, 2] as Lang.Array<Lang.Number>;

    // Cache
    mCachedTimes = new Lang.Array<Lang.String>[DISPLAY_ROW_COUNT];
    mCachedLabels = new Lang.Array<Lang.String>[DISPLAY_ROW_COUNT];
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      mCachedLabels[i] = mLabels[i];
    }

    updateColors();
    loadFromStorage();
  }

  private function updateColors() as Void {
    if (mIsAmoled) {
      // AMOLED: Always use dark background to prevent burn-in
      mBackgroundColor = Graphics.COLOR_BLACK;

      // Use light gray instead of pure white (reduces burn-in risk)
      mForegroundColor = Graphics.COLOR_LT_GRAY;

      // Accent colors for status
      mAccentColor = Graphics.COLOR_BLUE;
      mDimmedColor = Graphics.COLOR_DK_GRAY;

      System.println("[RaceEst] AMOLED mode: BG=BLACK FG=LT_GRAY");
    } else {
      // MIP displays: Use system theme background
      var systemBg = getBackgroundColor();
      mBackgroundColor = systemBg;

      System.println("[RaceEst] MIP mode: systemBg=" + systemBg);

      // Defensive: Calculate contrasting foreground color
      // If background is light (white), use dark text
      // If background is dark (black), use light text
      if (
        systemBg == Graphics.COLOR_WHITE ||
        systemBg == Graphics.COLOR_LT_GRAY ||
        systemBg == Graphics.COLOR_TRANSPARENT
      ) {
        mForegroundColor = Graphics.COLOR_BLACK;
        mAccentColor = Graphics.COLOR_BLUE;
        System.println("[RaceEst] Light background -> BLACK text");
      } else {
        mForegroundColor = Graphics.COLOR_WHITE;
        mAccentColor = Graphics.COLOR_ORANGE;
        System.println("[RaceEst] Dark background -> WHITE text");
      }

      mDimmedColor = mForegroundColor;
    }
  }

  private function validateGpsData(info as Activity.Info) as Lang.Boolean {
    var accuracy = info.currentLocationAccuracy;
    System.println(
      "[RaceEst] GPS accuracy: " +
        accuracy +
        " QUALITY_USABLE=" +
        Position.QUALITY_USABLE
    );

    // CRITICAL: FIT file playback may not populate GPS properly
    // Only fail if accuracy is explicitly BAD (not just null or missing)
    // Position.QUALITY_USABLE = 3
    // null or > 3 = poor quality

    if (accuracy == null) {
      System.println(
        "[RaceEst] GPS accuracy is null - treating as usable for FIT playback"
      );
      mGpsQualityGood = true;
      return true; // Allow predictions during FIT playback even without GPS
    }

    if (accuracy > Position.QUALITY_USABLE) {
      System.println(
        "[RaceEst] GPS accuracy poor: " +
          accuracy +
          " > " +
          Position.QUALITY_USABLE
      );
      mGpsQualityGood = false;
      return false;
    }

    mGpsQualityGood = true;
    return true;
  }

  private function validateMinimumDistance(
    elapsedDistance as Lang.Float?
  ) as Lang.Boolean {
    if (elapsedDistance == null || elapsedDistance < MIN_PREDICTION_DISTANCE) {
      mMinDistanceReached = false;
      return false;
    }
    mMinDistanceReached = true;
    return true;
  }

  private function detectFitAnomalies(
    elapsedDistance as Lang.Float,
    pace as Lang.Float
  ) as Lang.Boolean {
    // ANOMALY 1: Distance stagnation (FIT file replay bug where distance freezes)
    // If distance hasn't changed for 5+ consecutive updates, skip predictions
    if (elapsedDistance == mLastValidDistance) {
      mDistanceStagnationCount++;
      System.println(
        "[RaceEst] Distance stagnation: " +
          mDistanceStagnationCount +
          "/" +
          FIT_STAGNATION_THRESHOLD
      );

      if (mDistanceStagnationCount >= FIT_STAGNATION_THRESHOLD) {
        System.println(
          "[RaceEst] FIT ANOMALY: Distance frozen for " +
            mDistanceStagnationCount +
            " updates (likely FIT playback glitch) - SKIPPING"
        );
        return false;
      }
    } else {
      // Distance advanced normally, reset counter
      mDistanceStagnationCount = 0;
      mLastValidDistance = elapsedDistance;
    }

    // ANOMALY 2: Pace consistency check with time-skip awareness
    // Time skips in the simulator are OK (allow them), but FIT playback glitches are not
    // If distance AND time both advanced significantly, it's a time skip - allow it
    if (mLastValidPace > 0.0 && mLastValidTimer > 0) {
      var paceRatio = pace / mLastValidPace;

      // Check if this looks like a simulator time skip:
      // Time skip = both distance and time jumped, but distance is consistent with the pace
      // FIT glitch = time jumped but distance didn't
      var isTimeSkip = false;
      if (paceRatio > 2.0 || paceRatio < 0.5) {
        // Pace changed significantly. Check if distance also changed significantly.
        // If distance advanced while time jumped, it's likely a time skip in simulator.
        if (elapsedDistance > mLastValidDistance && mLastValidDistance > 0) {
          var distanceRatio = elapsedDistance / mLastValidDistance;
          if (distanceRatio > 1.0) {
            // Distance also advanced. This is consistent with a time skip.
            System.println(
              "[RaceEst] Time skip detected: pace ratio=" +
                paceRatio +
                " dist ratio=" +
                distanceRatio +
                " - allowing predictions to update"
            );
            isTimeSkip = true;
            mPaceAnomalyCount = 0; // Reset anomaly counter for time skips
          }
        }
      }

      // Only treat as anomaly if pace spike WITHOUT distance advance (FIT glitch)
      if (!isTimeSkip && (paceRatio > 2.0 || paceRatio < 0.5)) {
        mPaceAnomalyCount++;
        System.println(
          "[RaceEst] Pace anomaly: ratio=" +
            paceRatio +
            " (prev=" +
            mLastValidPace +
            " now=" +
            pace +
            ") count=" +
            mPaceAnomalyCount
        );

        // Skip predictions if pace spikes detected too often
        if (mPaceAnomalyCount >= 3) {
          System.println(
            "[RaceEst] FIT ANOMALY: Multiple pace spikes detected - SKIPPING"
          );
          return false;
        }
      } else if (isTimeSkip) {
        // Allow the prediction update
        System.println("[RaceEst] Time skip allowed - predictions will update");
      } else {
        // Normal pace progression, reset counter
        mPaceAnomalyCount = 0;
      }
    }

    mLastValidPace = pace;
    return true;
  }

  function compute(info as Activity.Info) as Void {
    // Safe mode recovery
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
    } catch (ex instanceof Lang.UnexpectedTypeException) {
      System.println("[RaceEst] Type error: " + ex.getErrorMessage());
      mConsecutiveErrors++;
      if (mConsecutiveErrors > 3) {
        enterSafeMode();
      }
    } catch (ex) {
      System.println("[RaceEst] Error in compute: " + ex.toString());
      mConsecutiveErrors++;
      if (mConsecutiveErrors > 3) {
        enterSafeMode();
      }
    }
  }

  private function computeImpl(info as Activity.Info) as Void {
    System.println("[RaceEst] computeImpl called");

    if (!validateGpsData(info)) {
      System.println("[RaceEst] GPS validation failed");
      return;
    }

    // Defensive: Read and validate critical fields BEFORE use
    var timerTime = info.timerTime;
    var elapsedDistance = info.elapsedDistance;

    // Defensive: Null and range validation
    if (timerTime == null || timerTime <= 0) {
      System.println("[RaceEst] Invalid timerTime: " + timerTime);
      return;
    }

    if (elapsedDistance == null || elapsedDistance <= 0) {
      System.println("[RaceEst] Invalid elapsedDistance: " + elapsedDistance);
      return;
    }

    if (!validateMinimumDistance(elapsedDistance)) {
      System.println(
        "[RaceEst] Minimum distance not reached: " + elapsedDistance
      );
      return;
    }

    System.println(
      "[RaceEst] Timer: " +
        timerTime +
        " (centisec), Distance: " +
        elapsedDistance +
        "m"
    );

    // CRITICAL FIX: timerTime is in CENTISECONDS, not milliseconds!
    // Convert to milliseconds for calculations and storage
    var timerTimeMs = timerTime * 10;

    var distanceCm = (elapsedDistance * 100.0).toNumber();

    // Track timer for time-skip detection in anomaly detection
    mLastValidTimer = timerTime;

    // Track current distance in meters for arc progress calculation
    mCurrentDistance = elapsedDistance;

    // Check milestone hits
    var needsRotation = false;
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];
      if (
        mFinishTimesMs[idx] == null &&
        distanceCm >= mDistancesCm[idx] - TOLERANCE_CM
      ) {
        mFinishTimesMs[idx] = timerTimeMs; // Store as milliseconds
        mStateDirty = true;
        if (i == 0) {
          needsRotation = true;
        }
      }
    }

    // Rotate display
    if (needsRotation) {
      mDisplayIndices[0] = mDisplayIndices[1];
      mDisplayIndices[1] = mDisplayIndices[2];

      while (
        mNextMilestonePtr < MILESTONE_COUNT &&
        mFinishTimesMs[mNextMilestonePtr] != null
      ) {
        mNextMilestonePtr++;
      }

      if (mNextMilestonePtr < MILESTONE_COUNT) {
        mDisplayIndices[2] = mNextMilestonePtr;
      } else {
        mAllComplete = true;
      }
    }

    // Defensive: Division by zero protection
    // elapsedDistance guaranteed > MIN_PREDICTION_DISTANCE (100m) by validation above
    var avgPaceSecPerMeter = timerTimeMs / 1000.0 / elapsedDistance;

    System.println(
      "[RaceEst] Pace calc: timerMs=" +
        timerTimeMs +
        " elapsedDist=" +
        elapsedDistance +
        " pace=" +
        avgPaceSecPerMeter
    );

    // Defensive: Sanity check pace (must be between 0.05 and 20 sec/m = 50 sec/km to 20 m/s)
    if (avgPaceSecPerMeter < 0.05 || avgPaceSecPerMeter > 20.0) {
      System.println(
        "[RaceEst] Insane pace: " + avgPaceSecPerMeter + " sec/m - SKIPPING"
      );
      return;
    }

    // CRITICAL: Detect FIT anomalies (simulator/playback edge cases)
    // Catches distance freezing and pace spike glitches during FIT file replay
    if (!detectFitAnomalies(elapsedDistance, avgPaceSecPerMeter)) {
      System.println("[RaceEst] FIT anomaly detected - predictions suppressed");
      return;
    }

    // Update cache (reuses arrays)
    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];

      // Defensive: Bounds check
      if (idx < 0 || idx >= MILESTONE_COUNT) {
        System.println("[RaceEst] Invalid display index: " + idx);
        continue;
      }

      if (mFinishTimesMs[idx] != null) {
        // Show actual hit time
        mCachedTimes[i] = formatTime(mFinishTimesMs[idx]);
        System.println(
          "[RaceEst] M" + idx + " HIT at " + mFinishTimesMs[idx] + "ms"
        );
      } else {
        // Calculate remaining distance to this milestone
        var remainingDistanceMeters =
          mDistancesCm[idx] / 100.0 - elapsedDistance;

        // Defensive: Skip if already past milestone (negative remaining)
        if (remainingDistanceMeters < 0) {
          mCachedTimes[i] = "0:00";
          System.println("[RaceEst] M" + idx + " PASSED");
          continue;
        }

        // Calculate time remaining to reach milestone (this is the countdown!)
        var timeRemainingMs = (
          remainingDistanceMeters *
          avgPaceSecPerMeter *
          1000.0
        ).toNumber();

        System.println(
          "[RaceEst] M" +
            idx +
            ": target=" +
            mDistancesCm[idx] / 100.0 +
            "m curr=" +
            elapsedDistance +
            "m rem=" +
            remainingDistanceMeters +
            "m*pace=" +
            avgPaceSecPerMeter +
            "=" +
            timeRemainingMs +
            "ms"
        );

        // Defensive: Overflow protection (Integer.MAX_VALUE ≈ 2.1 billion)
        // Max sane time: 100 hours = 360,000,000 ms
        if (timeRemainingMs < 0 || timeRemainingMs > 360000000) {
          System.println("[RaceEst] Time overflow: " + timeRemainingMs);
          mCachedTimes[i] = "99:59:59";
        } else {
          // Show time remaining (countdown)
          mCachedTimes[i] = formatTime(timeRemainingMs);
        }
      }

      mCachedLabels[i] =
        mLabels[idx] + (mFinishTimesMs[idx] != null ? " ✓" : "");
    }

    // Update arc progress and color for rendering in onUpdate()
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
    System.println("[RaceEst] Entered safe mode");
  }

  private function formatTime(ms as Lang.Number?) as Lang.String {
    if (ms == null || ms <= 0) {
      return "--:--";
    }

    // Force float division to avoid truncation, then convert to integer
    var sec = (ms / 1000.0).toNumber();
    if (sec > 359999) {
      return "99:59:59";
    }

    var h = sec / 3600;
    var m = (sec % 3600) / 60;
    var s = sec % 60;

    if (h > 0) {
      return Lang.format("$1$:$2$:$3$", [
        h,
        m.format("%02d"),
        s.format("%02d"),
      ]);
    }
    return Lang.format("$1$:$2$", [m, s.format("%02d")]);
  }

  function onLayout(dc as Graphics.Dc) as Void {
    var width = dc.getWidth();
    var height = dc.getHeight();

    mFieldHeight = height;
    mCenterX = width / 2;

    // Position text centered horizontally, slightly reduced vertical spacing
    // For circular display, balanced spacing that's not too tight or too loose
    mStatusY = 15; // Status at TOP
    mRow1Y = (height * 0.25).toNumber(); // 25% down (was 20%)
    mRow2Y = (height * 0.45).toNumber(); // 45% down (was 50%)
    mRow3Y = (height * 0.65).toNumber(); // 65% down (was 80%)
  }

  function onUpdate(dc as Graphics.Dc) as Void {
    System.println("[RaceEst] onUpdate called");
    System.println("[RaceEst] mFieldHeight: " + mFieldHeight);
    System.println("[RaceEst] mCenterX: " + mCenterX);

    updateColors();

    dc.setColor(mForegroundColor, mBackgroundColor);
    dc.clear();

    System.println(
      "[RaceEst] Screen cleared with FG:" +
        mForegroundColor +
        " BG:" +
        mBackgroundColor
    );

    // AMOLED burn-in prevention: subtle position shift
    if (mIsAmoled) {
      mUpdateCount++;
      if (mUpdateCount >= POSITION_SHIFT_INTERVAL) {
        mUpdateCount = 0;
        // Cycle: 0→1→2→1→0→-1→-2→-1→0...
        var cycle = mPositionOffset + MAX_OFFSET;
        cycle = (cycle + 1) % (MAX_OFFSET * 4);
        mPositionOffset = cycle - MAX_OFFSET;
      }
    }

    var screenHeight = System.getDeviceSettings().screenHeight;
    var isFullScreen = (mFieldHeight * 100) / screenHeight > 60;

    System.println(
      "[RaceEst] screenHeight: " +
        screenHeight +
        " isFullScreen: " +
        isFullScreen
    );

    if (isFullScreen) {
      System.println("[RaceEst] Calling drawProgressArc");
      drawProgressArc(dc);
      System.println("[RaceEst] Calling drawFullScreen");
      drawFullScreen(dc);
    } else {
      System.println("[RaceEst] Calling drawCompact");
      drawCompact(dc);
    }

    System.println("[RaceEst] onUpdate complete");
  }

  private function drawFullScreen(dc as Graphics.Dc) as Void {
    System.println(
      "[RaceEst] drawFullScreen: GPS=" +
        mGpsQualityGood +
        " MinDist=" +
        mMinDistanceReached
    );

    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      var idx = mDisplayIndices[i];
      var yPos = getYPosition(i) + mPositionOffset;

      // Check if this milestone is hit (static content)
      var isHit = mFinishTimesMs[idx] != null;

      if (mIsAmoled && isHit) {
        // Dim static content on AMOLED to reduce burn-in
        dc.setColor(mDimmedColor, Graphics.COLOR_TRANSPARENT);
      } else {
        dc.setColor(mForegroundColor, Graphics.COLOR_TRANSPARENT);
      }

      var text = mCachedLabels[i] + "  " + mCachedTimes[i];
      System.println(
        "[RaceEst] Drawing row " + i + ": '" + text + "' at Y=" + yPos
      );
      // Center-aligned for circular watch display
      dc.drawText(
        mCenterX,
        yPos,
        Graphics.FONT_MEDIUM,
        text,
        Graphics.TEXT_JUSTIFY_CENTER
      );
    }

    drawStatus(dc);
  }

  private function drawCompact(dc as Graphics.Dc) as Void {
    var text = mCachedLabels[0] + "  " + mCachedTimes[0];
    System.println("[RaceEst] drawCompact: '" + text + "' at Y=" + mRow1Y);
    dc.setColor(mForegroundColor, Graphics.COLOR_TRANSPARENT);
    // Position at top center for circular display
    dc.drawText(
      mCenterX,
      mRow1Y,
      Graphics.FONT_MEDIUM,
      text,
      Graphics.TEXT_JUSTIFY_CENTER
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

  private function drawStatus(dc as Graphics.Dc) as Void {
    var statusText = null;
    var statusColor = mForegroundColor;

    if (!mGpsQualityGood) {
      statusText = "WAITING GPS";
      statusColor = mIsAmoled ? mAccentColor : mAccentColor;
    } else if (!mMinDistanceReached) {
      statusText = "WARMUP";
      statusColor = mIsAmoled ? mAccentColor : mAccentColor;
    } else if (mAllComplete) {
      statusText = "COMPLETE";
      statusColor = mForegroundColor;
    } else if (mErrorState == 1) {
      statusText = "SAFE MODE";
      statusColor = Graphics.COLOR_RED;
    }

    System.println("[RaceEst] drawStatus: '" + statusText + "'");

    if (statusText != null) {
      dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
      // Draw status text centered horizontally but with sufficient space
      dc.drawText(
        mCenterX,
        mStatusY + mPositionOffset,
        Graphics.FONT_XTINY,
        statusText,
        Graphics.TEXT_JUSTIFY_CENTER
      );
    }
  }

  private function saveToStorage() as Void {
    try {
      var data = {
        "v" => STORAGE_VERSION,
        "times" => mFinishTimesMs,
        "ptr" => mNextMilestonePtr,
        "checksum" => calculateChecksum(mFinishTimesMs),
      };

      Storage.setValue(STORAGE_KEY, data);
    } catch (ex) {
      System.println("[RaceEst] Save failed: " + ex.toString());
    }
  }

  private function loadFromStorage() as Void {
    try {
      var data = Storage.getValue(STORAGE_KEY);

      // Defensive: Validate storage structure
      if (data == null) {
        System.println("[RaceEst] No storage data");
        return;
      }

      if (!(data instanceof Lang.Dictionary)) {
        throw new Lang.InvalidValueException("Not a dictionary");
      }

      var version = data.get("v");
      var times = data.get("times");
      var ptr = data.get("ptr");
      var checksum = data.get("checksum");

      // Defensive: Validate all fields exist and have correct types
      if (version == null || times == null || ptr == null || checksum == null) {
        throw new Lang.InvalidValueException("Missing fields");
      }

      if (!(times instanceof Lang.Array)) {
        throw new Lang.InvalidValueException("times not an array");
      }

      if (version != STORAGE_VERSION || times.size() != MILESTONE_COUNT) {
        throw new Lang.InvalidValueException("Version/size mismatch");
      }

      if (calculateChecksum(times) != checksum) {
        throw new Lang.InvalidValueException("Checksum failed");
      }

      mFinishTimesMs = times;
      mNextMilestonePtr = ptr;
      rebuildDisplay();
    } catch (ex instanceof Lang.InvalidValueException) {
      System.println("[RaceEst] Invalid storage: " + ex.getErrorMessage());
      clearAllData();
    } catch (ex) {
      System.println("[RaceEst] Load error: " + ex.toString());
      clearAllData();
    }
  }

  private function calculateChecksum(
    arr as Lang.Array<Lang.Number?>
  ) as Lang.Number {
    var sum = 0;
    for (var i = 0; i < arr.size(); i++) {
      var val = arr[i];
      if (val != null) {
        sum = (sum + val) % 1000000;
      }
    }
    return sum;
  }

  private function rebuildDisplay() as Void {
    var writeIdx = 0;
    for (var i = 0; i < MILESTONE_COUNT && writeIdx < DISPLAY_ROW_COUNT; i++) {
      if (mFinishTimesMs[i] == null) {
        mDisplayIndices[writeIdx] = i;
        writeIdx++;
      }
    }

    // Defensive: Fill remaining display slots if we ran out of milestones
    while (writeIdx < DISPLAY_ROW_COUNT) {
      // Use last valid milestone or default to 0
      mDisplayIndices[writeIdx] = writeIdx < MILESTONE_COUNT ? writeIdx : 0;
      writeIdx++;
      mAllComplete = true;
    }
  }

  private function clearAllData() as Void {
    for (var i = 0; i < MILESTONE_COUNT; i++) {
      mFinishTimesMs[i] = null;
    }
    mDisplayIndices = [0, 1, 2] as Lang.Array<Lang.Number>;
    mNextMilestonePtr = 0;
    mAllComplete = false;
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

    for (var i = 0; i < DISPLAY_ROW_COUNT; i++) {
      mCachedTimes[i] = "--:--";
      mCachedLabels[i] = mLabels[i];
    }
  }

  // ✅ PRODUCTION-SAFE: Calculate distance-based progress toward next milestone
  // Precondition: mDisplayIndices populated, mDistancesCm valid, mCurrentDistance ≥ 0
  // Postcondition: Returns Float in range [0.0, 1.0], no allocations
  private function calculateArcProgress() as Lang.Float {
    // Defensive: Array bounds checking
    if (
      mDisplayIndices == null ||
      mDisplayIndices.size() == 0 ||
      mCurrentDistance < 0
    ) {
      return 0.0; // Display not initialized
    }

    // Get target milestone index (first item in 3-row display)
    var nextMilestoneIdx = mDisplayIndices[0];

    // Bounds check: Ensure index is valid
    if (nextMilestoneIdx < 0 || nextMilestoneIdx >= MILESTONE_COUNT) {
      return 0.0; // Invalid milestone index
    }

    // Bounds check: Ensure distance array has this index
    if (mDistancesCm == null || mDistancesCm.size() <= nextMilestoneIdx) {
      return 0.0; // Distance array corrupted or uninitialized
    }

    // Get next milestone distance in centimeters
    var nextMilestoneDistanceCm = mDistancesCm[nextMilestoneIdx];

    // Get previous milestone distance (0 if first milestone)
    var prevMilestoneDistanceCm = 0;
    if (nextMilestoneIdx > 0) {
      prevMilestoneDistanceCm = mDistancesCm[nextMilestoneIdx - 1];
    }

    // Convert current distance from meters to centimeters
    var currentDistanceCm = (mCurrentDistance * 100.0).toNumber();

    // Calculate segment size (distance between previous and next milestone)
    var segmentDistanceCm = nextMilestoneDistanceCm - prevMilestoneDistanceCm;

    // Safety: Prevent division by zero
    if (segmentDistanceCm <= 0) {
      return 0.0; // Malformed milestone range
    }

    // Calculate distance into current segment
    var distanceIntoSegmentCm = currentDistanceCm - prevMilestoneDistanceCm;

    // Clamp progress to [0.0, 1.0]
    var progress =
      distanceIntoSegmentCm.toFloat() / segmentDistanceCm.toFloat();
    if (progress < 0.0) {
      progress = 0.0;
    }
    if (progress > 1.0) {
      progress = 1.0;
    }

    return progress;
  }

  // ✅ PRODUCTION-SAFE: Color selection for arc based on progress ratio
  // Precondition: progress is Float in range [0.0, 1.0+]
  // Postcondition: Returns valid Garmin color constant (never null)
  private function getArcColor(progress as Lang.Float) as Lang.Number {
    // Defensive: Handle invalid or null progress
    if (progress == null || progress < 0.0) {
      return Graphics.COLOR_GREEN; // Fallback: not started
    }

    // Color thresholds: Stepped transitions (not gradients)
    if (progress < 0.5) {
      return Graphics.COLOR_GREEN; // 0-50%: Good pace, plenty of time
    } else if (progress < 0.8) {
      return Graphics.COLOR_YELLOW; // 50-80%: Approaching finish
    } else {
      return Graphics.COLOR_RED; // 80%+: Close to finish or overdue
    }
  }

  // ✅ PRODUCTION-SAFE: Draw progress arc as bottom half-circle spanning display
  // Precondition: dc is valid Dc; mArcProgress and mArcColor cached from compute()
  // Postcondition: Arc drawn with start/end circles, no allocations, graceful skip on error
  private function drawProgressArc(dc as Graphics.Dc) as Void {
    // Defensive: Verify input validity
    if (dc == null || mArcProgress < 0.0 || mArcProgress > 1.0) {
      return; // Silently skip if invalid state
    }

    // Device-aware positioning: half-circle spans horizontally from left to right
    var displayWidth = dc.getWidth();
    var displayHeight = dc.getHeight();

    // Center X: horizontal middle of display
    var centerX = displayWidth / 2;

    // Center Y: position at horizontal midline so arc curves around bottom half
    // This creates a semicircle from 9 o'clock (left) to 3 o'clock (right) going down
    var centerY = displayHeight / 2;

    // Radius: use half the display width so arc spans from left edge to right edge
    var radius = displayWidth / 2;

    var penWidth = 8; // pixels (visible but not too thick)

    // STEP 1: Draw background arc (full bottom semicircle, light gray)
    // Degrees: 180° (top/12 o'clock) → 0°/360° (top/12 o'clock) going clockwise = bottom half
    dc.setPenWidth(penWidth);
    dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
    dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, 180, 0);

    // STEP 2: Draw progress arc (colored, grows left→right around bottom)
    // Start: 180° (12 o'clock/top), progress clockwise to 0° (360°)
    // Formula: endDegree = 180 - (180 * progress) gives us counterclockwise from top
    // But we want clockwise, so: 180 + (180 * progress) wraps to negative, use modulo
    var endDegree = 180 - (180 * mArcProgress).toNumber();
    if (endDegree < 0) {
      endDegree = 360 + endDegree; // Wrap negative to 360 range
    }
    if (endDegree > 360) {
      endDegree = 0; // Wrap to 0 if we hit full circle
    }

    dc.setColor(mArcColor, Graphics.COLOR_TRANSPARENT);
    dc.drawArc(
      centerX,
      centerY,
      radius,
      Graphics.ARC_CLOCKWISE,
      180,
      endDegree
    );

    // STEP 3: Draw endpoint circles (visual stoppers)
    drawArcEndpoints(dc, centerX, centerY, radius, 180, endDegree, mArcColor);
  }

  // ✅ PRODUCTION-SAFE: Draw endpoint circles for arc (trigonometry with error handling)
  // Precondition: centerX/Y, radius, startDegree, endDegree are valid numbers; dc is valid
  // Postcondition: Two circles drawn, or silently skipped if error occurs
  private function drawArcEndpoints(
    dc as Graphics.Dc,
    centerX as Lang.Number,
    centerY as Lang.Number,
    radius as Lang.Number,
    startDegree as Lang.Number,
    endDegree as Lang.Number,
    color as Lang.Number
  ) as Void {
    if (dc == null) {
      return;
    } // Defensive null check

    try {
      // START POINT: Calculate from startDegree parameter
      var startRadians = (startDegree.toFloat() * Math.PI) / 180.0;
      var startX = (centerX + radius * Math.cos(startRadians)).toNumber();
      var startY = (centerY + radius * Math.sin(startRadians)).toNumber();

      // END POINT: Current progress degree
      var endRadians = (endDegree.toFloat() * Math.PI) / 180.0;
      var endX = (centerX + radius * Math.cos(endRadians)).toNumber();
      var endY = (centerY + radius * Math.sin(endRadians)).toNumber();

      // Circle sizing: 4px radius = 8px diameter (small but visible)
      var circleRadius = 4;

      // START CIRCLE: Always gray (static reference point)
      dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
      dc.fillCircle(startX, startY, circleRadius);

      // END CIRCLE: Colored (indicates current progress)
      dc.setColor(color, Graphics.COLOR_TRANSPARENT);
      dc.fillCircle(endX, endY, circleRadius);
    } catch (ex) {
      // Catch-all for math/rendering errors
      System.println("[RaceEst Arc] Endpoint error: " + ex.toString());
    }
  }
}
