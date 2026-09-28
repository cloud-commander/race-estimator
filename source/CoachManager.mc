using Toybox.Lang;

// Race coach: short, event-driven messages for the context line, built on
// race segmentation (micro-goals, race thirds) and on what the runner is
// actually doing (pace trend, split streak, time on feet).
//
// Rules, highest priority first:
//   critical (ignore the quiet gap)
//     FINAL PUSH      last 400 m of a stage
//     ONE UNIT LEFT   1 km / 1 mi to go in the final stage (>= 4 units); on
//                     other stages FINAL PUSH alone marks the end
//     STAGE START     after each celebration: next goal, stage count, boss
//   paced (need MIN_GAP_SEC since the last message)
//     PHASE           entering each third of the target race, then a tip
//     RACE BEATS      race halfway, boss in sight
//     TIME CHUNK      "10K IN 11 MIN" early in each stage (time, not distance)
//     SLOWING, CLOSE  pace fading and the next milestone <= 6 min away:
//                     reframe as a tiny goal, "ONLY 4 MIN TO 10K"
//     BOSS HP         final stage >= 8 km: "BOSS HP 75%" at each quarter
//     STAGE HALFWAY   other stages >= 4 km
//     GOAL            with a goal time set: once per stage, projected finish
//                     vs goal ("1:20 UNDER GOAL"); banking time in the first
//                     third is flagged as a mistake ("TOO FAST FOR GOAL")
//     HILL            entering a climb / descent (grade over ~60 s): run by
//                     effort. Slowing cues are held back on climbs and kick
//                     cues on descents
//     FUEL            fuel interval setting; Auto = 40 min on half+ targets
//     PACE            once per stage (every 20 min on long stages), phase-aware: surge/fade early, locked in or fading mid,
//                     kick or grit late. Compares grade-adjusted recent pace
//                     with the run average, so it sees changes of effort; a
//                     start that is uniformly too fast is caught by GOAL
//
// Phrases rotate by stage so the same cue doesn't read the same twice in a
// row. Every string fits MAX_COLUMNS of the pixel font: phrases built from a
// milestone name fall back to a shorter form when the name is long.
class CoachManager {
  public static const MAX_COLUMNS = 101; // "ONE STAGE AT A TIME"
  private const MESSAGE_SEC = 8.0d;
  private const MIN_GAP_SEC = 45.0d;
  private const PACE_COOLDOWN_SEC = 300.0d;
  // Pace cues are once per stage, but a long stage (a marathon's 16 km boss
  // stage) gets another every 20 min: that's where support matters most
  private const PACE_REPEAT_SEC = 1200.0d;
  public static const FUEL_AUTO = -1; // fuelInterval setting value
  private const FUEL_AUTO_INTERVAL_SEC = 2400.0d; // 40 min
  private const FUEL_AUTO_MIN_TARGET_CM = 2100000; // HALF and longer
  private const GOAL_MIN_STAGE_PROGRESS = 0.25d;
  private const GOAL_ON_PACE_MS = 30000; // within 30 s = on goal
  private const GOAL_TOO_FAST_RATIO = 0.98d; // projected < 98% of goal early
  private const TIME_CHUNK_DELAY_SEC = 25.0d; // after the stage-start message
  private const FINAL_PUSH_M = 400.0d;
  private const HALFWAY_MIN_SEGMENT_M = 4000.0d; // short stages: no mid cues
  private const ONE_UNIT_MIN_STAGE_UNITS = 4.0d;
  private const PACE_MIN_DISTANCE_M = 2000.0d;
  private const BOSS_HP_MIN_STAGE_M = 8000.0d;
  private const METERS_PER_MILE = 1609.344d;
  // Hills: enter at 4% over ~60 s, leave below 2%; cues at most every 5 min
  private const HILL_ENTER_GRADE = 0.04d;
  private const HILL_EXIT_GRADE = 0.02d;
  private const HILL_COOLDOWN_SEC = 300.0d;

  // Per-stage flags
  private const F_FINAL_PUSH = 1;
  private const F_ONE_UNIT = 2;
  private const F_HALFWAY = 4;
  private const F_TIME_CHUNK = 8;
  private const F_PACE = 16; // at most one pace cue per stage
  private const F_NEAR_SLOW = 32;
  private const F_GOAL = 64;

  // Pace trend thresholds: recent pace / whole-run average (> 1 = slower)
  private const SLOWING_RATIO = 1.05d;
  private const NEAR_MILESTONE_MS = 360000; // 6 min

  // Race-level flags
  private const R_RACE_HALF = 1;
  private const R_BOSS_SIGHT = 2;
  private const R_BONUS = 4;
  private const R_LOCKED_IN = 8;

  private var mMilestones as MilestoneManager;
  private var mUseStatute as Lang.Boolean;

  private var mMessage as Lang.String = "";
  private var mIsCaution as Lang.Boolean = false;
  private var mUntilSec as Lang.Double = 0.0d;
  private var mLastShownSec as Lang.Double = -1000.0d;
  private var mPending as Lang.String = "";

  private var mStage as Lang.Number = -1;
  private var mStageStartSec as Lang.Double = 0.0d;
  private var mStageFlags as Lang.Number = 0;
  private var mRaceFlags as Lang.Number = 0;
  private var mPhaseAnnounced as Lang.Number = 0;
  private var mLastPaceSec as Lang.Double = -1000.0d;
  private var mLastFuelSec as Lang.Double = 0.0d;
  private var mFuelSetting as Lang.Number = FUEL_AUTO; // minutes, 0 off
  private var mGoalMs as Lang.Number = 0; // target race goal, 0 = none
  private var mGoalIsBest as Lang.Boolean = false; // goal is the high score
  private var mStreak as Lang.Number = 0;
  private var mPaceCount as Lang.Number = 0; // rotates pace phrasing
  private var mBossQuarter as Lang.Number = 0; // boss HP quarters announced
  private var mMaxStreak as Lang.Number = 0;
  private var mSeq as Lang.Number = 0; // bumps on every new message
  private var mHill as Lang.Number = 0; // 1 climbing, -1 descending, 0 flat
  private var mHillPending as Lang.Boolean = false; // cue owed for this hill
  private var mLastHillSec as Lang.Double = -1000.0d;
  private var mHillCount as Lang.Number = 0;

  function initialize(milestones as MilestoneManager, useStatute as Lang.Boolean) {
    mMilestones = milestones;
    mUseStatute = useStatute;
  }

  public function reset() as Void {
    mMessage = "";
    mIsCaution = false;
    mUntilSec = 0.0d;
    mLastShownSec = -1000.0d;
    mPending = "";
    mStage = -1;
    mStageStartSec = 0.0d;
    mStageFlags = 0;
    mRaceFlags = 0;
    mPhaseAnnounced = 0;
    mLastPaceSec = -1000.0d;
    mLastFuelSec = 0.0d;
    mStreak = 0;
    mPaceCount = 0;
    mBossQuarter = 0;
    mMaxStreak = 0;
    mHill = 0;
    mHillPending = false;
    mLastHillSec = -1000.0d;
    mHillCount = 0;
  }

  // Goal finish time for the target race in ms (0 = no goal)
  public function setGoalMs(goalMs as Lang.Number) as Void {
    setGoal(goalMs, false);
  }

  // isBest: the goal is the high score (no goal set), so messages say BEST
  public function setGoal(goalMs as Lang.Number, isBest as Lang.Boolean) as Void {
    mGoalMs = goalMs > 0 ? goalMs : 0;
    mGoalIsBest = isBest;
  }

  // Fuel reminder interval in minutes: FUEL_AUTO, 0 = off, else every N min
  public function setFuelInterval(minutes as Lang.Number) as Void {
    mFuelSetting = minutes;
  }

  // Seconds between fuel reminders for this target race, 0 = none
  private function fuelIntervalSec(targetIdx as Lang.Number) as Lang.Double {
    if (mFuelSetting == FUEL_AUTO) {
      return mMilestones.getMilestoneDistanceCm(targetIdx) >= FUEL_AUTO_MIN_TARGET_CM
        ? FUEL_AUTO_INTERVAL_SEC
        : 0.0d;
    }
    return mFuelSetting > 0 ? mFuelSetting * 60.0d : 0.0d;
  }

  // Current message ("" when none)
  public function getMessage() as Lang.String {
    return mMessage;
  }

  // Caution messages (ease off, dig deep) use the status colour; the rest
  // use the celebratory title colour
  public function isCaution() as Lang.Boolean {
    return mIsCaution;
  }

  // Bumps each time a new message appears (the view uses it to buzz)
  public function getMessageSeq() as Lang.Number {
    return mSeq;
  }

  // Record a stage result: true = ahead of its halfway projection
  public function onSplit(ahead as Lang.Boolean) as Void {
    mStreak = ahead ? mStreak + 1 : 0;
    if (mStreak > mMaxStreak) {
      mMaxStreak = mStreak;
    }
  }

  // Longest run of stages that beat their projection (results screen)
  public function getMaxCombo() as Lang.Number {
    return mMaxStreak;
  }

  // "COMBO X3!" once two or more stages in a row beat their projection
  public function getComboText() as Lang.String {
    return mStreak >= 2 ? "COMBO X" + mStreak + "!" : "";
  }

  /**
   * Call once per compute while predictions are valid
   * @param pace the pace model, already updated for this tick
   */
  public function update(
    nowSec as Lang.Double,
    elapsedM as Lang.Double,
    targetIdx as Lang.Number,
    mapFraction as Lang.Double,
    segmentProgress as Lang.Double,
    pace as PaceEstimator
  ) as Void {
    var count = mMilestones.getMilestoneCount();
    var next = mMilestones.getNextMilestoneIdx();
    if (mMilestones.isCelebrating() || next >= count) {
      mMessage = "";
      return;
    }
    var recentPace = pace.getRecentPace();
    var averagePace = pace.getAveragePace();
    var grade = pace.getCurrentGrade();
    var nextRemainingMs = pace.estimateRemainingMs(
      mMilestones.getMilestoneDistanceCm(next) / 100.0d
    );
    var targetFinishMs =
      next <= targetIdx
        ? (nowSec * 1000.0d).toNumber() +
          pace.estimateRemainingMs(
            mMilestones.getMilestoneDistanceCm(targetIdx) / 100.0d
          )
        : 0;

    // Hill state with hysteresis, tracked every tick; the cue stays owed
    // until the next quiet moment while still on that hill
    if (mHill == 0 && grade >= HILL_ENTER_GRADE) {
      mHill = 1;
      mHillPending = nowSec - mLastHillSec >= HILL_COOLDOWN_SEC;
    } else if (mHill == 0 && grade <= -HILL_ENTER_GRADE) {
      mHill = -1;
      mHillPending = nowSec - mLastHillSec >= HILL_COOLDOWN_SEC;
    } else if (mHill != 0 && grade < HILL_EXIT_GRADE && grade > -HILL_EXIT_GRADE) {
      mHill = 0;
      mHillPending = false;
    }
    if (nowSec < mUntilSec) {
      return;
    }
    mMessage = "";

    if (mPending.length() > 0) {
      show(mPending, false, nowSec);
      mPending = "";
      return;
    }

    var label = mMilestones.getMilestoneLabel(next);
    var nextM = mMilestones.getMilestoneDistanceCm(next) / 100.0d;
    var prevM =
      next > 0 ? mMilestones.getMilestoneDistanceCm(next - 1) / 100.0d : 0.0d;
    var remainingM = nextM - elapsedM;
    var unitM = mUseStatute ? METERS_PER_MILE : 1000.0d;
    var quietEnough = nowSec - mLastShownSec >= MIN_GAP_SEC;

    // ---- critical ---------------------------------------------------------

    if ((mStageFlags & F_FINAL_PUSH) == 0 && remainingM <= FINAL_PUSH_M) {
      mStageFlags |= F_FINAL_PUSH | F_ONE_UNIT | F_HALFWAY | F_TIME_CHUNK;
      show(pick(["FINAL PUSH!", "BRING IT HOME!", fit("GO GET " + label, "GO GET IT!")], next), false, nowSec);
      return;
    }

    if (
      (mStageFlags & F_ONE_UNIT) == 0 &&
      next == targetIdx &&
      nextM - prevM >= unitM * ONE_UNIT_MIN_STAGE_UNITS &&
      remainingM <= unitM
    ) {
      mStageFlags |= F_ONE_UNIT | F_HALFWAY | F_TIME_CHUNK;
      show((mUseStatute ? "1 MI TO " : "1 KM TO ") + label, false, nowSec);
      return;
    }

    if (next != mStage) {
      var isFirst = mStage < 0;
      mStage = next;
      mStageStartSec = nowSec;
      mStageFlags = 0;
      if (!isFirst) {
        show(stageStartMessage(next, targetIdx, label), false, nowSec);
        return;
      }
    }

    if (!quietEnough) {
      return;
    }

    // ---- paced ------------------------------------------------------------

    // Fading with the next milestone close: the strongest reframe there is
    // (not on a climb: slower there is correct)
    if (
      (mStageFlags & F_NEAR_SLOW) == 0 &&
      grade < HILL_EXIT_GRADE &&
      elapsedM >= PACE_MIN_DISTANCE_M &&
      recentPace > 0.0d &&
      averagePace > 0.0d &&
      recentPace / averagePace > SLOWING_RATIO &&
      nextRemainingMs > 0 &&
      nextRemainingMs <= NEAR_MILESTONE_MS &&
      remainingM > FINAL_PUSH_M
    ) {
      mStageFlags |= F_NEAR_SLOW | F_PACE;
      var min = formatChunk(nextRemainingMs);
      show(fit("ONLY " + min + " TO " + label, "ONLY " + min + " TO GO"), false, nowSec);
      return;
    }

    if (mHillPending) {
      mHillPending = false;
      mLastHillSec = nowSec;
      mHillCount++;
      show(
        mHill > 0
          ? pick(["HILL: HOLD EFFORT", "CLIMB: SHORT STEPS", "EFFORT, NOT PACE"], mHillCount)
          : pick(["DOWNHILL: LET IT ROLL", "QUICK FEET DOWNHILL"], mHillCount),
        false,
        nowSec
      );
      return;
    }

    var phase = mapFraction < 1.0d / 3 ? 0 : mapFraction < 2.0d / 3 ? 1 : 2;
    if (next <= targetIdx && mPhaseAnnounced <= phase) {
      mPhaseAnnounced = phase + 1;
      var titles = ["PHASE 1: HEAD", "PHASE 2: LEGS", "PHASE 3: HEART"];
      var tips = ["SAVE IT FOR LATER", "FIND YOUR RHYTHM", "EMPTY THE TANK"];
      show(titles[phase], false, nowSec);
      mPending = tips[phase];
      return;
    }

    if (next <= targetIdx) {
      if ((mRaceFlags & R_RACE_HALF) == 0 && mapFraction >= 0.5d) {
        mRaceFlags |= R_RACE_HALF;
        show("HALF THE RACE DONE", false, nowSec);
        return;
      }
      // Short final stages only; long ones get the BOSS HP countdown
      if (
        (mRaceFlags & R_BOSS_SIGHT) == 0 &&
        next == targetIdx &&
        nextM - prevM < BOSS_HP_MIN_STAGE_M &&
        mapFraction >= 0.9d
      ) {
        mRaceFlags |= R_BOSS_SIGHT;
        show("BOSS IN SIGHT!", false, nowSec);
        return;
      }
    }

    if (
      (mStageFlags & F_TIME_CHUNK) == 0 &&
      nowSec - mStageStartSec >= TIME_CHUNK_DELAY_SEC &&
      nextRemainingMs > 0
    ) {
      mStageFlags |= F_TIME_CHUNK;
      show(fit(label + " IN " + formatChunk(nextRemainingMs), "NEXT IN " + formatChunk(nextRemainingMs)), false, nowSec);
      return;
    }

    // Long final stage: count the boss down in quarters
    if (next == targetIdx && nextM - prevM >= BOSS_HP_MIN_STAGE_M) {
      var quarter = (segmentProgress * 4.0d).toNumber();
      if (quarter > 3) {
        quarter = 3;
      }
      if (quarter > mBossQuarter) {
        mBossQuarter = quarter;
        mStageFlags |= F_HALFWAY;
        show("BOSS HP " + (100 - quarter * 25) + "%", false, nowSec);
        return;
      }
    }

    if (
      (mStageFlags & F_HALFWAY) == 0 &&
      nextM - prevM >= HALFWAY_MIN_SEGMENT_M &&
      segmentProgress >= 0.5d
    ) {
      mStageFlags |= F_HALFWAY;
      show(
        pick(
          [fit("HALFWAY TO " + label, "HALFWAY THERE"), "OVER THE HUMP", "HALF STAGE DONE"],
          next
        ),
        false,
        nowSec
      );
      return;
    }

    if (
      (mStageFlags & F_GOAL) == 0 &&
      mGoalMs > 0 &&
      targetFinishMs > 0 &&
      next <= targetIdx &&
      elapsedM >= PACE_MIN_DISTANCE_M &&
      segmentProgress >= GOAL_MIN_STAGE_PROGRESS
    ) {
      mStageFlags |= F_GOAL;
      goalMessage(nowSec, phase, targetFinishMs);
      return;
    }

    var fuelSec = fuelIntervalSec(targetIdx);
    if (fuelSec > 0.0d && nowSec - mLastFuelSec >= fuelSec) {
      mLastFuelSec = nowSec;
      show("POWER-UP: FUEL NOW", false, nowSec);
      return;
    }

    // Pace cues judge effort on the flat: a climb reads as slowing and a
    // descent as a kick even after grade adjustment catches up
    if (mHill == 0) {
      paceMessage(nowSec, elapsedM, phase, next > targetIdx, recentPace, averagePace);
    }
  }

  // Phase-aware pacing cue from recent vs whole-run pace (ratio > 1 = slower)
  private function paceMessage(
    nowSec as Lang.Double,
    elapsedM as Lang.Double,
    phase as Lang.Number,
    isBonus as Lang.Boolean,
    recentPace as Lang.Double,
    averagePace as Lang.Double
  ) as Void {
    if (
      ((mStageFlags & F_PACE) != 0 && nowSec - mLastPaceSec < PACE_REPEAT_SEC) ||
      recentPace <= 0.0d ||
      averagePace <= 0.0d ||
      elapsedM < PACE_MIN_DISTANCE_M ||
      nowSec - mLastPaceSec < PACE_COOLDOWN_SEC
    ) {
      return;
    }
    var ratio = recentPace / averagePace;
    var text = "";
    var caution = false;

    if (isBonus) {
      if (ratio > 1.05d) {
        text = "KEEP MOVING";
      }
    } else if (phase == 0) {
      if (ratio < 0.97d) {
        text = pick(["EASY, TIGER", "TOO HOT: EASE OFF", "SAVE IT FOR LATER"], mPaceCount);
        caution = true;
      } else if (ratio > SLOWING_RATIO) {
        text = pick(["RELAX, STAY SMOOTH", "FIND YOUR FEET", "EASY MILES, KEEP ON"], mPaceCount);
      }
    } else if (phase == 1) {
      if ((mRaceFlags & R_LOCKED_IN) == 0 && ratio > 0.98d && ratio < 1.02d) {
        mRaceFlags |= R_LOCKED_IN;
        text = "RHYTHM LOCKED IN";
      } else if (ratio > SLOWING_RATIO) {
        text = pick(["ONE STAGE AT A TIME", "SHORTEN, QUICKEN", "STAY IN IT"], mPaceCount);
        caution = true;
      }
    } else {
      if (ratio < 0.98d) {
        text = pick(["FINISHING KICK!", "NEGATIVE SPLIT!", "HUNT THEM DOWN"], mPaceCount);
      } else if (ratio > 1.05d) {
        text = pick(["DIG DEEP", "ONE STAGE AT A TIME", "YOU'VE GOT THIS"], mPaceCount);
        caution = true;
      }
    }

    if (text.length() > 0) {
      mLastPaceSec = nowSec;
      mStageFlags |= F_PACE;
      mPaceCount++;
      show(text, caution, nowSec);
    }
  }

  // Projected target finish vs goal. Early in the race being well ahead is
  // the classic banked-time mistake, so it is a caution, not praise
  private function goalMessage(
    nowSec as Lang.Double,
    phase as Lang.Number,
    targetFinishMs as Lang.Number
  ) as Void {
    var delta = targetFinishMs - mGoalMs; // > 0 = behind
    var word = mGoalIsBest ? "BEST" : "GOAL";
    if (phase == 0 && targetFinishMs < mGoalMs * GOAL_TOO_FAST_RATIO) {
      mStageFlags |= F_PACE;
      show(
        pick(["TOO FAST FOR " + word, mGoalIsBest ? "EASE TO BEST PACE" : "EASE TO GOAL PACE"], mPaceCount),
        true,
        nowSec
      );
      return;
    }
    if (delta <= GOAL_ON_PACE_MS && delta >= -GOAL_ON_PACE_MS) {
      show(
        pick(
          mGoalIsBest
            ? ["ON RECORD PACE", "HI-SCORE IN SIGHT", "RECORD IN REACH"]
            : ["ON GOAL PACE", "RIGHT ON GOAL", "GOAL LOCKED IN"],
          mStage
        ),
        false,
        nowSec
      );
    } else if (delta < 0) {
      show(fit(formatDuration(-delta) + " UNDER " + word, "UNDER " + word), false, nowSec);
    } else {
      show(fit(formatDuration(delta) + " OVER " + word, "OVER " + word), true, nowSec);
    }
  }

  private function stageStartMessage(
    next as Lang.Number,
    targetIdx as Lang.Number,
    label as Lang.String
  ) as Lang.String {
    if (next > targetIdx) {
      if ((mRaceFlags & R_BONUS) == 0) {
        mRaceFlags |= R_BONUS;
        return "BONUS STAGE!";
      }
      return "BONUS: " + label;
    }
    if (next == targetIdx) {
      return fit("BOSS STAGE: " + label, "BOSS STAGE!");
    }
    return pick(
      [
        "NEXT UP: " + label,
        "STAGE " + (next + 1) + " OF " + (targetIdx + 1),
        fit("JUST GET TO " + label, "NEXT UP: " + label),
      ],
      next
    );
  }

  // "11 MIN" under an hour, "1H 05M" above
  private function formatChunk(ms as Lang.Number) as Lang.String {
    var min = (ms + 30000) / 60000;
    if (min < 1) {
      min = 1;
    }
    if (min < 100) {
      return min + " MIN";
    }
    return (min / 60) + "H " + (min % 60).format("%02d") + "M";
  }

  // Use `text` if it fits the context line, else the shorter fallback
  private function fit(text as Lang.String, fallback as Lang.String) as Lang.String {
    return pixelColumns(text) <= MAX_COLUMNS ? text : fallback;
  }

  private function pick(options as Lang.Array<Lang.String>, seed as Lang.Number) as Lang.String {
    return options[(seed < 0 ? 0 : seed) % options.size()];
  }

  private function show(text as Lang.String, caution as Lang.Boolean, nowSec as Lang.Double) as Void {
    mMessage = text;
    mIsCaution = caution;
    mSeq++;
    mUntilSec = nowSec + MESSAGE_SEC;
    mLastShownSec = nowSec;
  }
}
