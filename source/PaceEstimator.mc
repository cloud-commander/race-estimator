using Toybox.Lang;
using Toybox.Math;

// Finish-time model.
//
// projected(D) = elapsed + (D - d) * blendedPace * fatigue(D, d)
//
// - blendedPace = 60% recent pace (rolling ~10 min window) + 40% whole-run
//   average pace. Recent pace reacts when you slow down late in a long run;
//   the average keeps a single fast downhill from swinging the projection.
// - fatigue(D, d) = (D / d)^0.06, Riegel's endurance exponent (T2 = T1 *
//   (D2/D1)^1.06) applied to the remaining distance. ~1.00 for the next
//   milestone, ~1.10 for 50K when you are at 10K. d is floored at
//   RIEGEL_MIN_DISTANCE_M so the first kilometre can't inflate it.
//
// Memory: two 61-slot arrays. CPU: one sample every 10 s, O(1) per query.
class PaceEstimator {
  private const SAMPLE_INTERVAL_SEC = 10.0d;
  private const WINDOW_SLOTS = 61; // 60 intervals = 10 minutes
  private const MIN_RECENT_DISTANCE_M = 200.0d; // need this much for a recent pace
  private const RECENT_WEIGHT = 0.6d;
  private const RIEGEL_EXPONENT = 0.06d;
  private const RIEGEL_MIN_DISTANCE_M = 3000.0d;
  private const WARMUP_SEC = 5.0d;

  // Sanity bounds (sec per metre)
  private const PACE_MIN_SEC_PER_M = 0.05d; // 0:50/km, faster than any human
  private const PACE_MAX_SEC_PER_M = 20.0d; // 5.5 h/km

  // Ring buffer of (timer seconds, distance metres)
  private var mTimes as Lang.Array<Lang.Double>;
  private var mDists as Lang.Array<Lang.Double>;
  private var mHead as Lang.Number = 0; // next write slot
  private var mCount as Lang.Number = 0;
  private var mLastSampleSec as Lang.Double = -1.0d;

  private var mAveragePace as Lang.Double = 0.0d;
  private var mBlendedPace as Lang.Double = 0.0d;
  private var mElapsedSec as Lang.Double = 0.0d;
  private var mDistanceM as Lang.Double = 0.0d;

  function initialize(debugLogging as Lang.Boolean) {
    mTimes = new Lang.Array<Lang.Double>[WINDOW_SLOTS];
    mDists = new Lang.Array<Lang.Double>[WINDOW_SLOTS];
    reset();
  }

  public function reset() as Void {
    for (var i = 0; i < WINDOW_SLOTS; i++) {
      mTimes[i] = 0.0d;
      mDists[i] = 0.0d;
    }
    mHead = 0;
    mCount = 0;
    mLastSampleSec = -1.0d;
    mAveragePace = 0.0d;
    mBlendedPace = 0.0d;
    mElapsedSec = 0.0d;
    mDistanceM = 0.0d;
  }

  /**
   * Feed the current activity totals (call once per compute)
   * @return true if a usable pace is available
   */
  public function update(
    timerTimeSec as Lang.Double,
    elapsedDistanceM as Lang.Double
  ) as Lang.Boolean {
    if (elapsedDistanceM <= 0.0d || timerTimeSec <= 0.0d) {
      return false;
    }

    // Timer went backwards (activity reset without onTimerReset): start over
    if (timerTimeSec < mLastSampleSec) {
      reset();
    }

    mElapsedSec = timerTimeSec;
    mDistanceM = elapsedDistanceM;

    if (
      mLastSampleSec < 0.0d ||
      timerTimeSec - mLastSampleSec >= SAMPLE_INTERVAL_SEC
    ) {
      mTimes[mHead] = timerTimeSec;
      mDists[mHead] = elapsedDistanceM;
      mHead = (mHead + 1) % WINDOW_SLOTS;
      if (mCount < WINDOW_SLOTS) {
        mCount++;
      }
      mLastSampleSec = timerTimeSec;
    }

    var average = timerTimeSec / elapsedDistanceM;
    if (average < PACE_MIN_SEC_PER_M || average > PACE_MAX_SEC_PER_M) {
      return mBlendedPace > 0.0d; // keep the last good estimate
    }
    mAveragePace = average;

    var recent = getRecentPace();
    mBlendedPace = recent > 0.0d
      ? RECENT_WEIGHT * recent + (1.0d - RECENT_WEIGHT) * average
      : average;
    return true;
  }

  // Pace over the rolling window (oldest sample -> now), or 0 if the window
  // hasn't covered enough distance yet
  public function getRecentPace() as Lang.Double {
    if (mCount < 2) {
      return 0.0d;
    }
    var oldest = mCount < WINDOW_SLOTS ? 0 : mHead;
    var dt = mElapsedSec - mTimes[oldest];
    var dd = mDistanceM - mDists[oldest];
    if (dd < MIN_RECENT_DISTANCE_M || dt <= 0.0d) {
      return 0.0d;
    }
    var pace = dt / dd;
    if (pace < PACE_MIN_SEC_PER_M || pace > PACE_MAX_SEC_PER_M) {
      return 0.0d;
    }
    return pace;
  }

  public function getAveragePace() as Lang.Double {
    return mAveragePace;
  }

  public function getBlendedPace() as Lang.Double {
    return mBlendedPace;
  }

  public function isWarmedUp() as Lang.Boolean {
    return mElapsedSec >= WARMUP_SEC && mBlendedPace > 0.0d;
  }

  /**
   * Projected time (ms) to cover the rest of the way to targetM from the
   * current distance, including the Riegel fatigue factor
   */
  public function estimateRemainingMs(targetM as Lang.Double) as Lang.Number {
    var remaining = targetM - mDistanceM;
    if (remaining <= 0.0d || mBlendedPace <= 0.0d) {
      return 0;
    }
    var from = mDistanceM > RIEGEL_MIN_DISTANCE_M ? mDistanceM : RIEGEL_MIN_DISTANCE_M;
    var fatigue = targetM > from
      ? Math.pow(targetM / from, RIEGEL_EXPONENT).toDouble()
      : 1.0d;
    return (remaining * mBlendedPace * fatigue * 1000.0d).toNumber();
  }
}
