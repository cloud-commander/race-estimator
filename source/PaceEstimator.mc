using Toybox.Lang;
using Toybox.System;

// Exponential Moving Average (EMA) pace estimator with FIT anomaly detection
// Provides smoothed pace predictions with robust outlier filtering
class PaceEstimator {

  // EMA smoothing configuration
  private const SMOOTHING_ALPHA = 0.15d;  // EMA weight for new samples
  private const SMOOTHING_WINDOW_SEC = 5; // Minimum time before predictions are valid

  // FIT anomaly detection thresholds
  private const FIT_STAGNATION_THRESHOLD = 5;     // Consecutive identical distance readings
  private const PACE_SPIKE_RATIO_MAX = 2.0;       // Max pace change ratio (200%)
  private const PACE_SPIKE_RATIO_MIN = 0.5;       // Min pace change ratio (50%)
  private const PACE_SPIKE_THRESHOLD = 3;         // Consecutive spikes before rejection
  private const MAX_DELTA_TIME_SEC = 5.0d;        // Max time gap before reset

  // Pace validation bounds
  private const PACE_MIN_SEC_PER_M = 0.05;  // ~3 min/km (very fast)
  private const PACE_MAX_SEC_PER_M = 20.0;  // ~5.5 hours/km (walking)

  // State tracking
  private var mSmoothedPaceSecPerM as Lang.Double = 0.0d;
  private var mLastComputeTimeSec as Lang.Double = 0.0d;
  private var mSmoothingWindowFull as Lang.Boolean = false;

  // Anomaly detection state
  private var mLastValidDistance as Lang.Double = 0.0d;
  private var mDistanceStagnationCount as Lang.Number = 0;
  private var mLastValidPace as Lang.Double = 0.0d;
  private var mPaceAnomalyCount as Lang.Number = 0;
  private var mFirstPaceReadingDone as Lang.Boolean = false;

  // Debug logging
  private var mDebugLogging as Lang.Boolean = false;

  /**
   * Initialize pace estimator
   * @param debugLogging Enable verbose logging
   */
  function initialize(debugLogging as Lang.Boolean) {
    mDebugLogging = debugLogging;
    reset();

    if (mDebugLogging) {
      System.println("PaceEstimator: Initialized (alpha=" + SMOOTHING_ALPHA + ", window=" + SMOOTHING_WINDOW_SEC + "s)");
    }
  }

  /**
   * Reset all estimator state
   */
  public function reset() as Void {
    mSmoothedPaceSecPerM = 0.0d;
    mLastComputeTimeSec = 0.0d;
    mSmoothingWindowFull = false;
    mLastValidDistance = 0.0d;
    mDistanceStagnationCount = 0;
    mLastValidPace = 0.0d;
    mPaceAnomalyCount = 0;
    mFirstPaceReadingDone = false;

    if (mDebugLogging) {
      System.println("PaceEstimator: Reset");
    }
  }

  /**
   * Update pace estimate with new activity data
   * Performs EMA smoothing and anomaly filtering
   * @param currentPaceSecPerM Current instantaneous pace (sec/meter)
   * @param elapsedDistance Total elapsed distance (meters)
   * @param timerTimeSec Current timer time (seconds)
   * @return true if pace was accepted and updated, false if rejected
   */
  public function updatePace(
    currentPaceSecPerM as Lang.Double,
    elapsedDistance as Lang.Float,
    timerTimeSec as Lang.Double
  ) as Lang.Boolean {

    // Check if smoothing window is satisfied
    if (!mSmoothingWindowFull && timerTimeSec >= SMOOTHING_WINDOW_SEC) {
      mSmoothingWindowFull = true;
      if (mDebugLogging) {
        System.println("PaceEstimator: Smoothing window satisfied");
      }
    }

    // Detect time jumps (pause/resume, simulator glitches)
    var deltaTimeSec = timerTimeSec - mLastComputeTimeSec;
    if (mLastComputeTimeSec > 0.0 && deltaTimeSec.abs() > MAX_DELTA_TIME_SEC) {
      if (mDebugLogging) {
        System.println("PaceEstimator: Time jump detected (" + deltaTimeSec + "s), resetting");
      }
      mSmoothedPaceSecPerM = 0.0d;
      mPaceAnomalyCount = 0;
    }

    mLastComputeTimeSec = timerTimeSec;

    // Validate pace is within reasonable bounds
    if (currentPaceSecPerM < PACE_MIN_SEC_PER_M || currentPaceSecPerM > PACE_MAX_SEC_PER_M) {
      if (mDebugLogging) {
        System.println("PaceEstimator: Pace out of bounds (" + currentPaceSecPerM + "), rejected");
      }
      return false;
    }

    // Detect distance stagnation (FIT file replay, GPS freeze)
    if (!detectDistanceStagnation(elapsedDistance)) {
      if (mDebugLogging) {
        System.println("PaceEstimator: Distance stagnation detected, rejected");
      }
      return false;
    }

    // Detect pace spikes (GPS glitches, sudden speed changes)
    if (!detectPaceSpike(currentPaceSecPerM)) {
      if (mDebugLogging) {
        System.println("PaceEstimator: Pace spike detected, rejected");
      }
      return false;
    }

    // All validations passed - update smoothed pace
    if (mSmoothedPaceSecPerM == 0.0d) {
      // Initialize with first valid reading
      mSmoothedPaceSecPerM = currentPaceSecPerM;
      if (mDebugLogging) {
        System.println("PaceEstimator: Initialized with pace " + currentPaceSecPerM);
      }
    } else {
      // Apply EMA smoothing
      mSmoothedPaceSecPerM =
        SMOOTHING_ALPHA * currentPaceSecPerM +
        (1.0 - SMOOTHING_ALPHA) * mSmoothedPaceSecPerM;
    }

    return true;
  }

  /**
   * Get current smoothed pace estimate
   * @return Smoothed pace in seconds per meter
   */
  public function getSmoothedPace() as Lang.Double {
    return mSmoothedPaceSecPerM;
  }

  /**
   * Check if estimator has warmed up (received enough data)
   * @return true if smoothing window is full
   */
  public function isWarmedUp() as Lang.Boolean {
    return mSmoothingWindowFull;
  }

  /**
   * Detect if distance is stagnating (GPS frozen, FIT replay)
   * @param elapsedDistance Current total distance
   * @return true if distance is changing normally, false if stagnant
   */
  private function detectDistanceStagnation(elapsedDistance as Lang.Float) as Lang.Boolean {
    var distAsDouble = elapsedDistance.toDouble();

    if (distAsDouble == mLastValidDistance) {
      // Distance hasn't changed
      mDistanceStagnationCount++;
      if (mDistanceStagnationCount >= FIT_STAGNATION_THRESHOLD) {
        // Too many consecutive identical readings
        return false;
      }
    } else {
      // Distance changed - reset counter
      mDistanceStagnationCount = 0;
      mLastValidDistance = distAsDouble;
    }

    return true;
  }

  /**
   * Detect sudden pace changes (GPS glitches, sprint/stop)
   * Uses ratio-based detection to handle all pace ranges
   * @param pace Current pace in sec/meter
   * @return true if pace change is reasonable, false if spike detected
   */
  private function detectPaceSpike(pace as Lang.Double) as Lang.Boolean {
    if (!mFirstPaceReadingDone) {
      // First reading - accept and initialize
      mLastValidPace = pace;
      mFirstPaceReadingDone = true;
      return true;
    }

    if (mLastValidPace > 0.0) {
      // Calculate pace change ratio
      var paceRatio = pace / mLastValidPace;

      // Check if ratio is outside acceptable range
      if (paceRatio > PACE_SPIKE_RATIO_MAX || paceRatio < PACE_SPIKE_RATIO_MIN) {
        // Potential spike detected
        mPaceAnomalyCount++;
        if (mPaceAnomalyCount >= PACE_SPIKE_THRESHOLD) {
          // Too many consecutive spikes - reject
          return false;
        }
      } else {
        // Normal pace change - reset anomaly counter
        mPaceAnomalyCount = 0;
      }
    }

    // Update last valid pace
    mLastValidPace = pace;
    return true;
  }

  /**
   * Calculate estimated time to complete remaining distance
   * @param remainingDistanceMeters Distance remaining to target
   * @return Estimated time in milliseconds, or null if not ready
   */
  public function estimateTimeRemaining(remainingDistanceMeters as Lang.Double) as Lang.Number? {
    // Only provide estimates if warmed up and have valid pace
    if (!mSmoothingWindowFull || mSmoothedPaceSecPerM == 0.0d) {
      return null;
    }

    if (remainingDistanceMeters <= 0.0) {
      return 0;
    }

    // Calculate time: distance * pace
    var timeSeconds = remainingDistanceMeters * mSmoothedPaceSecPerM;
    var timeMs = (timeSeconds * 1000.0d).toNumber();

    return timeMs;
  }

  /**
   * Get diagnostics for debugging
   * @return Dictionary with current state
   */
  public function getDiagnostics() as Lang.Dictionary {
    return {
      "smoothedPace" => mSmoothedPaceSecPerM,
      "warmedUp" => mSmoothingWindowFull,
      "stagnationCount" => mDistanceStagnationCount,
      "anomalyCount" => mPaceAnomalyCount,
      "lastPace" => mLastValidPace,
      "lastDistance" => mLastValidDistance
    };
  }
}
