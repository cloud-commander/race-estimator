using Toybox.Lang;
using Toybox.Math;

// Finish-time model.
//
// projected(D) = elapsed + blendedPace * (remaining + wallFade * wallKm)
//
// - blendedPace = 60% recent pace (rolling ~10 min window) + 40% whole-run
//   average pace. Recent pace reacts when you slow down late in a long run;
//   the average keeps a single fast downhill from swinging the projection.
// - Recent pace is grade adjusted (GAP): a climb in the window is converted
//   to its flat-ground equivalent, so hills don't read as fading (and
//   descents don't read as a surge). Needs altitude; flat otherwise.
// - Wall fade: running evenly, pace holds to ~30 km; past that most runners
//   slow ~8%. Distance still ahead beyond WALL_M is costed WALL_FADE slower,
//   minus whatever fade the recent pace already shows (so a runner who has
//   hit the wall is not charged twice). Nothing is added below 30 km, so a
//   steady 10K or half runner sees their even-pace time.
//   (An earlier Riegel (D/d)^0.06 factor assumed the distance so far was an
//   all-out effort and projected a paced runner 5-17% slow early on.)
//
// Memory: three 61-slot arrays. CPU: one sample every 10 s, O(1) per query.
class PaceEstimator {
  private const SAMPLE_INTERVAL_SEC = 10.0d;
  private const WINDOW_SLOTS = 61; // 60 intervals = 10 minutes
  private const GRADE_SLOTS = 6; // ~60 s for the "on a hill now" grade
  private const MIN_RECENT_DISTANCE_M = 200.0d; // need this much for a recent pace
  private const MIN_GRADE_DISTANCE_M = 50.0d;
  private const RECENT_WEIGHT = 0.6d;
  private const WALL_M = 30000.0d;
  private const WALL_FADE = 0.08d;
  private const WARMUP_SEC = 5.0d;

  // Grade-adjusted pace: cost per unit grade (fraction) up and down.
  // ~3% slower per 1% up; downhill helps less and stops helping past -10%.
  private const GAP_UP = 3.0d;
  private const GAP_DOWN = 1.8d;
  private const MAX_GRADE = 0.10d;

  // Sanity bounds (sec per metre)
  private const PACE_MIN_SEC_PER_M = 0.05d; // 0:50/km, faster than any human
  private const PACE_MAX_SEC_PER_M = 20.0d; // 5.5 h/km

  // Ring buffer of (timer seconds, distance metres, altitude metres)
  private var mTimes as Lang.Array<Lang.Double>;
  private var mDists as Lang.Array<Lang.Double>;
  private var mAlts as Lang.Array<Lang.Double>;
  private var mHead as Lang.Number = 0; // next write slot
  private var mCount as Lang.Number = 0;
  private var mLastSampleSec as Lang.Double = -1.0d;

  private var mAveragePace as Lang.Double = 0.0d;
  private var mBlendedPace as Lang.Double = 0.0d;
  private var mElapsedSec as Lang.Double = 0.0d;
  private var mDistanceM as Lang.Double = 0.0d;
  private var mAltitude as Lang.Double = 0.0d;
  private var mHasAltitude as Lang.Boolean = false;
  private var mUseAltitude as Lang.Boolean = true;

  function initialize(debugLogging as Lang.Boolean) {
    mTimes = new Lang.Array<Lang.Double>[WINDOW_SLOTS];
    mDists = new Lang.Array<Lang.Double>[WINDOW_SLOTS];
    mAlts = new Lang.Array<Lang.Double>[WINDOW_SLOTS];
    reset();
  }

  public function reset() as Void {
    for (var i = 0; i < WINDOW_SLOTS; i++) {
      mTimes[i] = 0.0d;
      mDists[i] = 0.0d;
      mAlts[i] = 0.0d;
    }
    mHead = 0;
    mCount = 0;
    mLastSampleSec = -1.0d;
    mAveragePace = 0.0d;
    mBlendedPace = 0.0d;
    mElapsedSec = 0.0d;
    mDistanceM = 0.0d;
    mAltitude = 0.0d;
    mHasAltitude = false;
  }

  // Indoor runs: altitude is meaningless, keep everything flat
  public function setUseAltitude(use as Lang.Boolean) as Void {
    mUseAltitude = use;
  }

  // Feed the current altitude (call before update; skip when unknown)
  public function setAltitude(altitudeM as Lang.Double) as Void {
    if (!mUseAltitude) {
      return;
    }
    if (!mHasAltitude) {
      // First fix: backfill so the window doesn't see a jump from 0
      for (var i = 0; i < WINDOW_SLOTS; i++) {
        mAlts[i] = altitudeM;
      }
    }
    mAltitude = altitudeM;
    mHasAltitude = true;
  }

  // Distance correction applied (lap sync): rescale history so the pace
  // window doesn't see a jump
  public function rescaleDistance(ratio as Lang.Double) as Void {
    for (var i = 0; i < WINDOW_SLOTS; i++) {
      mDists[i] = mDists[i] * ratio;
    }
    mDistanceM = mDistanceM * ratio;
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
      mAlts[mHead] = mAltitude;
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

  // Grade-adjusted pace over the rolling window (oldest sample -> now), or
  // 0 if the window hasn't covered enough distance yet
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
    var pace = dt / dd / gradeCost((mAltitude - mAlts[oldest]) / dd);
    if (pace < PACE_MIN_SEC_PER_M || pace > PACE_MAX_SEC_PER_M) {
      return 0.0d;
    }
    return pace;
  }

  // Grade over the last ~60 s (fraction, + = uphill), 0 if unknown
  public function getCurrentGrade() as Lang.Double {
    if (!mHasAltitude || mCount < 2) {
      return 0.0d;
    }
    var back = mCount - 1 < GRADE_SLOTS ? mCount - 1 : GRADE_SLOTS;
    var idx = (mHead - 1 - back + 2 * WINDOW_SLOTS) % WINDOW_SLOTS;
    var dd = mDistanceM - mDists[idx];
    if (dd < MIN_GRADE_DISTANCE_M) {
      return 0.0d;
    }
    return clampGrade((mAltitude - mAlts[idx]) / dd);
  }

  // Time multiplier of running at `grade` vs flat
  private function gradeCost(grade as Lang.Double) as Lang.Double {
    if (!mHasAltitude) {
      return 1.0d;
    }
    var g = clampGrade(grade);
    return g >= 0.0d ? 1.0d + GAP_UP * g : 1.0d + GAP_DOWN * g;
  }

  private function clampGrade(g as Lang.Double) as Lang.Double {
    return g > MAX_GRADE ? MAX_GRADE : g < -MAX_GRADE ? -MAX_GRADE : g;
  }

  public function getAveragePace() as Lang.Double {
    return mAveragePace;
  }

  public function getBlendedPace() as Lang.Double {
    return mBlendedPace;
  }

  public function getDistanceM() as Lang.Double {
    return mDistanceM;
  }

  public function isWarmedUp() as Lang.Boolean {
    return mElapsedSec >= WARMUP_SEC && mBlendedPace > 0.0d;
  }

  /**
   * Projected time (ms) to cover the rest of the way to targetM from the
   * current distance, including the wall fade past 30 km
   */
  public function estimateRemainingMs(targetM as Lang.Double) as Lang.Number {
    var remaining = targetM - mDistanceM;
    if (remaining <= 0.0d || mBlendedPace <= 0.0d) {
      return 0;
    }
    var effective = remaining;
    var from = mDistanceM > WALL_M ? mDistanceM : WALL_M;
    if (targetM > from) {
      var recent = getRecentPace();
      var observed =
        recent > 0.0d && mAveragePace > 0.0d ? recent / mAveragePace - 1.0d : 0.0d;
      var fade = WALL_FADE - (observed > 0.0d ? observed : 0.0d);
      if (fade > 0.0d) {
        effective += fade * (targetM - from);
      }
    }
    return (effective * mBlendedPace * 1000.0d).toNumber();
  }
}
