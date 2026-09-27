using Toybox.Lang;
using Toybox.System;
using Toybox.Attention;

// Manages race milestone tracking, completion state, and celebration logic
// Fully encapsulates milestone business logic separate from UI concerns
class MilestoneManager {
  // Milestone configuration
  private var mDistancesCm as Lang.Array<Lang.Number>;
  private var mLabels as Lang.Array<Lang.String>;
  private var mFinishTimesMs as Lang.Array<Lang.Number?>;
  private var mMilestoneCount as Lang.Number;

  // Display rotation state
  private var mDisplayIndices as Lang.Array<Lang.Number?>;
  private var mDisplayRowCount as Lang.Number;

  // Celebration tracking
  private var mCelebrationStartTimeMs as Lang.Number? = null;
  private var mCelebrationMilestoneIdx as Lang.Number? = null;

  // Constants
  private const CELEBRATION_DURATION_MS = 10000; // Long enough to glance at
  // A milestone first seen more than this far behind was not crossed live
  // (field restarted mid-run without saved state): its split is estimated
  // and it is not celebrated
  private const CATCH_UP_DISTANCE_CM = 20000; // 200 m
  private const CELEBRATION_TIMEOUT_MS = 30000; // 30 seconds max (safety)

  // Debug logging
  private var mDebugLogging as Lang.Boolean = false;

  /**
   * Initialize milestone manager with race distance definitions
   * @param milestoneCount Number of milestones to track
   * @param displayRowCount Number of rows to display simultaneously
   * @param debugLogging Enable verbose logging
   */
  function initialize(
    milestoneCount as Lang.Number,
    displayRowCount as Lang.Number,
    debugLogging as Lang.Boolean
  ) {
    mMilestoneCount = milestoneCount;
    mDisplayRowCount = displayRowCount;
    mDebugLogging = debugLogging;

    // Define standard race distances in centimeters
    // 5K, 5MI, 10K, 13.1K, 10MI, HM, 26.2K, FM, 50K
    mDistancesCm =
      [
        500000, // 5K
        804672, // 5 miles
        1000000, // 10K
        1310000, // 13.1K
        1609344, // 10 miles
        2109750, // Half marathon
        2620000, // 26.2K
        4219500, // Full marathon
        5000000, // 50K
      ] as Lang.Array<Lang.Number>;

    mLabels =
      [
        "5K",
        "5 MI",
        "10K",
        "13.1K",
        "10 MI",
        "HALF",
        "26.2K",
        "MARATHON",
        "50K",
      ] as
      Lang.Array<Lang.String>;

    // Initialize completion tracking
    mFinishTimesMs = new Lang.Array<Lang.Number?>[mMilestoneCount];
    for (var i = 0; i < mMilestoneCount; i++) {
      mFinishTimesMs[i] = null;
    }

    // Initialize display to show first N milestones
    mDisplayIndices = new Lang.Array<Lang.Number?>[mDisplayRowCount];
    for (var i = 0; i < mDisplayRowCount; i++) {
      mDisplayIndices[i] = i;
    }

    if (mDebugLogging) {
      System.println(
        "MilestoneManager: Initialized with " + mMilestoneCount + " milestones"
      );
      System.println(
        "Display indices: [" +
          mDisplayIndices[0] +
          ", " +
          mDisplayIndices[1] +
          ", " +
          mDisplayIndices[2] +
          "]"
      );
    }
  }

  /**
   * Get milestone distance in centimeters
   * @param idx Milestone index
   * @return Distance in cm, or 0 if invalid
   */
  public function getMilestoneDistanceCm(idx as Lang.Number) as Lang.Number {
    if (idx >= 0 && idx < mDistancesCm.size()) {
      return mDistancesCm[idx];
    }
    return 0;
  }

  /**
   * Get milestone label
   * @param idx Milestone index
   * @return Label string, or empty if invalid
   */
  public function getMilestoneLabel(idx as Lang.Number) as Lang.String {
    if (idx >= 0 && idx < mLabels.size()) {
      return mLabels[idx];
    }
    return "";
  }

  /**
   * Get milestone finish time
   * @param idx Milestone index
   * @return Finish time in ms, or null if not completed
   */
  public function getMilestoneFinishTime(idx as Lang.Number) as Lang.Number? {
    if (idx >= 0 && idx < mFinishTimesMs.size()) {
      return mFinishTimesMs[idx];
    }
    return null;
  }

  /**
   * Get current display indices for UI rendering
   * @return Array of milestone indices to display
   */
  public function getDisplayIndices() as Lang.Array<Lang.Number?> {
    return mDisplayIndices;
  }

  /**
   * Get milestone count
   * @return Total number of milestones
   */
  public function getMilestoneCount() as Lang.Number {
    return mMilestoneCount;
  }

  /**
   * Get display row count
   * @return Number of display rows
   */
  public function getDisplayRowCount() as Lang.Number {
    return mDisplayRowCount;
  }

  /**
   * Check if all milestones are completed
   * @return true if all milestones finished
   */
  public function isAllComplete() as Lang.Boolean {
    if (mFinishTimesMs[mMilestoneCount - 1] != null) {
      return true;
    }
    return false;
  }

  /**
   * Check if currently celebrating a milestone completion
   * @return true if in celebration period
   */
  public function isCelebrating() as Lang.Boolean {
    return mCelebrationStartTimeMs != null;
  }

  /**
   * Get the milestone index being celebrated
   * @return Milestone index, or null if not celebrating
   */
  public function getCelebrationMilestoneIdx() as Lang.Number? {
    return mCelebrationMilestoneIdx;
  }

  /**
   * Check milestones for completion and update state
   * @param currentDistanceCm Current distance in centimeters
   * @param timerTimeMs Current timer time in milliseconds
   * @param toleranceCm Distance tolerance for completion detection
   * @return true if display needs rotation
   */
  public function checkAndMarkCompletions(
    currentDistanceCm as Lang.Double,
    timerTimeMs as Lang.Number,
    toleranceCm as Lang.Number
  ) as Lang.Boolean {
    var needsRotation = false;

    // Validate celebration state to prevent memory leaks
    if (mCelebrationStartTimeMs != null) {
      if (
        timerTimeMs < mCelebrationStartTimeMs ||
        timerTimeMs - mCelebrationStartTimeMs > CELEBRATION_TIMEOUT_MS
      ) {
        // Invalid or timeout - clear celebration
        if (mDebugLogging) {
          System.println(
            "MilestoneManager: Celebration timeout or invalid state"
          );
        }
        mCelebrationStartTimeMs = null;
        mCelebrationMilestoneIdx = null;
      }
    }

    // Check every milestone (not just displayed rows) so a restored or
    // skipped-ahead state can never leave a reached milestone unmarked
    var celebrateIdx = null;
    for (var idx = 0; idx < mMilestoneCount; idx++) {
      var distanceCm = mDistancesCm[idx].toDouble();
      if (
        mFinishTimesMs[idx] != null ||
        currentDistanceCm < distanceCm - toleranceCm
      ) {
        continue;
      }

      if (currentDistanceCm - distanceCm > CATCH_UP_DISTANCE_CM) {
        // Not crossed live: estimate the split at average pace, no fanfare
        mFinishTimesMs[idx] = (
          timerTimeMs.toDouble() * distanceCm / currentDistanceCm
        ).toNumber();
      } else {
        mFinishTimesMs[idx] = timerTimeMs;
        celebrateIdx = idx;
      }
      needsRotation = true;

      if (mDebugLogging) {
        System.println(
          "MilestoneManager: Milestone " + mLabels[idx] + " at " +
            mFinishTimesMs[idx] + "ms"
        );
      }
    }

    // One celebration per tick, for the furthest milestone crossed live
    if (celebrateIdx != null) {
      mCelebrationStartTimeMs = timerTimeMs;
      mCelebrationMilestoneIdx = celebrateIdx;
      playFeedback(celebrateIdx == mMilestoneCount - 1);
    }

    // Check if celebration period has ended
    if (
      mCelebrationStartTimeMs != null &&
      timerTimeMs - mCelebrationStartTimeMs >= CELEBRATION_DURATION_MS
    ) {
      // Celebration ended - rotate to next milestone
      if (mDebugLogging) {
        System.println("MilestoneManager: Celebration ended, rotating display");
      }
      mCelebrationStartTimeMs = null;
      mCelebrationMilestoneIdx = null;
      needsRotation = true;
    }

    return needsRotation;
  }

  /**
   * Rebuild display indices to show uncompleted milestones
   * Handles celebration state and display rotation logic
   */
  public function rebuildDisplay() as Void {
    // Milestones complete in ascending distance order, so the display is a
    // window of consecutive milestones. It starts at the celebrated milestone
    // (kept in row 0 for CELEBRATION_DURATION_MS) or at the next uncompleted
    // one, and is clamped so the last rows keep showing FM/50K results
    // instead of going blank near the end of an ultra.
    var start = getNextMilestoneIdx();
    if (mCelebrationMilestoneIdx != null) {
      start = mCelebrationMilestoneIdx;
    }
    if (start > mMilestoneCount - mDisplayRowCount) {
      start = mMilestoneCount - mDisplayRowCount;
    }
    if (start < 0) {
      start = 0;
    }

    for (var i = 0; i < mDisplayRowCount; i++) {
      mDisplayIndices[i] = start + i < mMilestoneCount ? start + i : null;
    }

    if (mDebugLogging) {
      System.println(
        "MilestoneManager: Display rebuilt - indices: [" +
          mDisplayIndices[0] +
          ", " +
          mDisplayIndices[1] +
          ", " +
          mDisplayIndices[2] +
          "]"
      );
    }
  }

  /**
   * Index of the first uncompleted milestone
   * @return Milestone index, or milestoneCount if all are complete
   */
  public function getNextMilestoneIdx() as Lang.Number {
    for (var i = 0; i < mMilestoneCount; i++) {
      if (mFinishTimesMs[i] == null) {
        return i;
      }
    }
    return mMilestoneCount;
  }

  /**
   * Milestone the UI should focus on: the one being celebrated, else the
   * next uncompleted one, else the last one (all complete)
   */
  public function getFocusIdx() as Lang.Number {
    if (mCelebrationMilestoneIdx != null) {
      return mCelebrationMilestoneIdx;
    }
    var next = getNextMilestoneIdx();
    return next < mMilestoneCount ? next : mMilestoneCount - 1;
  }

  /**
   * Reset all milestone completion state
   */
  public function reset() as Void {
    if (mDebugLogging) {
      System.println("MilestoneManager: Resetting all milestone data");
    }

    // Clear all completion times
    for (var i = 0; i < mMilestoneCount; i++) {
      mFinishTimesMs[i] = null;
    }

    // Reset display to first N milestones
    for (var i = 0; i < mDisplayRowCount; i++) {
      mDisplayIndices[i] = i;
    }

    // Clear celebration state
    mCelebrationStartTimeMs = null;
    mCelebrationMilestoneIdx = null;
  }

  /**
   * Get all finish times (for persistence)
   * @return Array of finish times
   */
  public function getFinishTimesMs() as Lang.Array<Lang.Number?> {
    return mFinishTimesMs;
  }

  /**
   * Set all finish times (from persistence)
   * @param times Array of finish times to restore
   * @return true if successfully set
   */
  public function setFinishTimesMs(
    times as Lang.Array<Lang.Number?>
  ) as Lang.Boolean {
    // Validate array size
    if (times.size() != mMilestoneCount) {
      if (mDebugLogging) {
        System.println(
          "MilestoneManager: Cannot restore finish times - size mismatch"
        );
      }
      return false;
    }

    mFinishTimesMs = times;

    if (mDebugLogging) {
      System.println("MilestoneManager: Finish times restored from storage");
    }

    return true;
  }

  /**
   * Programmatically mark a milestone as complete and start celebration if needed
   * @param idx Milestone index
   * @param timeMs Finish time in milliseconds
   * @return true if successfully marked, false if invalid or already completed
   */
  public function markMilestoneComplete(
    idx as Lang.Number,
    timeMs as Lang.Number
  ) as Lang.Boolean {
    // Validate index
    if (idx < 0 || idx >= mMilestoneCount) {
      if (mDebugLogging) {
        System.println(
          "MilestoneManager: markMilestoneComplete invalid idx " + idx
        );
      }
      return false;
    }

    // Already completed?
    if (mFinishTimesMs[idx] != null) {
      if (mDebugLogging) {
        System.println(
          "MilestoneManager: markMilestoneComplete idx " +
            idx +
            " already completed"
        );
      }
      return false;
    }

    // Mark completion
    mFinishTimesMs[idx] = timeMs;

    playFeedback(idx == mMilestoneCount - 1);

    if (mDebugLogging) {
      System.println(
        "MilestoneManager: markMilestoneComplete marked " +
          idx +
          " at " +
          timeMs
      );
    }

    mCelebrationStartTimeMs = timeMs;
    mCelebrationMilestoneIdx = idx;

    // Rebuild display to reflect completed milestone and celebration state
    rebuildDisplay();

    return true;
  }

  /**
   * Milestone feedback: vibration plus an 8-bit arpeggio (a longer fanfare
   * for the final milestone). Both honour the watch's vibration/tone
   * settings. These fire even when this data screen is not the one showing.
   */
  private function playFeedback(isFinal as Lang.Boolean) as Void {
    var settings = System.getDeviceSettings();

    if ((Attention has :vibrate) && settings.vibrateOn) {
      Attention.vibrate(
        isFinal
          ? [
              new Attention.VibeProfile(100, 300),
              new Attention.VibeProfile(0, 150),
              new Attention.VibeProfile(100, 300),
              new Attention.VibeProfile(0, 150),
              new Attention.VibeProfile(100, 600),
            ]
          : [
              new Attention.VibeProfile(100, 300),
              new Attention.VibeProfile(0, 150),
              new Attention.VibeProfile(100, 300),
            ]
      );
    }

    if ((Attention has :playTone) && (Attention has :ToneProfile) && settings.tonesOn) {
      // C5-E5-G5-C6 "stage clear"; final adds E6-G6 and a held C7
      var notes = isFinal
        ? [523, 659, 784, 1047, 1319, 1568, 2093]
        : [523, 659, 784, 1047];
      var profile = new Lang.Array<Attention.ToneProfile>[notes.size()];
      for (var i = 0; i < notes.size(); i++) {
        var last = i == notes.size() - 1;
        profile[i] = new Attention.ToneProfile(notes[i], last ? 300 : 90);
      }
      Attention.playTone({ :toneProfile => profile });
    }
  }
}
