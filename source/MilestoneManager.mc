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
  private const CELEBRATION_DURATION_MS = 5000; // 5 seconds
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
      ["5K", "5MI", "10K", "13.1K", "10MI", "HM", "26.2K", "FM", "50K"] as
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

    // Check each displayed milestone for completion
    for (var i = 0; i < mDisplayRowCount; i++) {
      var idx = mDisplayIndices[i];

      // Comprehensive array bounds validation
      if (
        idx != null &&
        idx >= 0 &&
        idx < mMilestoneCount &&
        idx < mDistancesCm.size() &&
        idx < mFinishTimesMs.size() &&
        mFinishTimesMs[idx] == null &&
        currentDistanceCm >= mDistancesCm[idx].toDouble() - toleranceCm
      ) {
        // Milestone completed!
        mFinishTimesMs[idx] = timerTimeMs;

        // Vibrate to celebrate milestone completion
        vibrateForMilestone();

        if (mDebugLogging) {
          System.println(
            "MilestoneManager: Milestone " +
              idx +
              " (" +
              mLabels[idx] +
              ") completed at " +
              timerTimeMs +
              "ms"
          );
        }

        if (i == 0) {
          // First display row completed - start celebration
          mCelebrationStartTimeMs = timerTimeMs;
          mCelebrationMilestoneIdx = idx;
          needsRotation = true;

          if (mDebugLogging) {
            System.println(
              "MilestoneManager: Starting celebration for milestone " + idx
            );
          }
        }
      }
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
    if (mDebugLogging) {
      System.println("MilestoneManager: Rebuilding display");
    }

    var writeIdx = 0;
    var newDisplayIndices = new Lang.Array<Lang.Number?>[mDisplayRowCount];

    // If celebrating, keep completed milestone in first row temporarily
    if (mCelebrationStartTimeMs != null && mCelebrationMilestoneIdx != null) {
      // Check if this is the last milestone
      var isLastMilestone = mCelebrationMilestoneIdx == mMilestoneCount - 1;

      if (isLastMilestone) {
        // Last milestone - keep showing it permanently, end celebration
        mCelebrationStartTimeMs = null;
        mCelebrationMilestoneIdx = null;

        if (mDebugLogging) {
          System.println(
            "MilestoneManager: Last milestone reached, ending celebration"
          );
        }
      } else {
        // Show completed milestone in first row during celebration
        newDisplayIndices[writeIdx] = mCelebrationMilestoneIdx;
        writeIdx++;
      }
    }

    // Fill remaining rows with uncompleted milestones
    for (var i = 0; i < mMilestoneCount && writeIdx < mDisplayRowCount; i++) {
      if (mFinishTimesMs[i] == null) {
        newDisplayIndices[writeIdx] = i;
        writeIdx++;
      }
    }

    mDisplayIndices = newDisplayIndices;

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
   * Vibrate to celebrate milestone completion
   * Gracefully handles devices that don't support vibration
   */
  private function vibrateForMilestone() as Void {
    if (Attention has :vibrate) {
      // Single vibration pulse: 50ms vibration
      var profile = [new Attention.VibeProfile(50, 50)];
      Attention.vibrate(profile);
    }
  }
}
