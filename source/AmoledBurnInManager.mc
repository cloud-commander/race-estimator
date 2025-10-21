using Toybox.Lang;
using Toybox.System;

// Manages AMOLED burn-in protection through pixel shifting
// Implements periodic position offsets to prevent pixel wear
class AmoledBurnInManager {

  // Pixel offset pattern (cycles through 4 positions)
  private const PIXEL_OFFSETS = [0, 1, -1, 0] as Lang.Array<Lang.Number>;

  // State tracking
  private var mUpdateCount as Lang.Number = 0;
  private var mOffsetIndex as Lang.Number = 0;
  private var mCurrentOffset as Lang.Number = 0;
  private var mShiftInterval as Lang.Number;
  private var mEnabled as Lang.Boolean = false;
  private var mDebugLogging as Lang.Boolean = false;

  /**
   * Initialize burn-in protection manager
   * @param shiftInterval Number of updates between position shifts
   * @param enabled Enable burn-in protection (typically for AMOLED displays)
   * @param debugLogging Enable verbose logging
   */
  function initialize(
    shiftInterval as Lang.Number,
    enabled as Lang.Boolean,
    debugLogging as Lang.Boolean
  ) {
    mShiftInterval = shiftInterval;
    mEnabled = enabled;
    mDebugLogging = debugLogging;

    if (mDebugLogging) {
      System.println("AmoledBurnInManager: Initialized (interval=" + shiftInterval +
                     ", enabled=" + enabled + ")");
    }
  }

  /**
   * Update pixel shift state (call once per onUpdate)
   * Cycles through position offsets at configured interval
   * @return true if position offset changed this update
   */
  public function update() as Lang.Boolean {
    if (!mEnabled) {
      return false;
    }

    mUpdateCount++;

    if (mUpdateCount >= mShiftInterval) {
      mUpdateCount = 0;
      mOffsetIndex = (mOffsetIndex + 1) % PIXEL_OFFSETS.size();
      mCurrentOffset = PIXEL_OFFSETS[mOffsetIndex];

      if (mDebugLogging) {
        System.println("AmoledBurnInManager: Position shift to " + mCurrentOffset +
                       " (index=" + mOffsetIndex + ")");
      }

      return true;
    }

    return false;
  }

  /**
   * Get current pixel offset for display positioning
   * @return Pixel offset (-1, 0, or 1)
   */
  public function getOffset() as Lang.Number {
    return mCurrentOffset;
  }

  /**
   * Check if burn-in protection is enabled
   * @return true if enabled
   */
  public function isEnabled() as Lang.Boolean {
    return mEnabled;
  }

  /**
   * Reset to initial state
   */
  public function reset() as Void {
    mUpdateCount = 0;
    mOffsetIndex = 0;
    mCurrentOffset = 0;

    if (mDebugLogging) {
      System.println("AmoledBurnInManager: Reset");
    }
  }

  /**
   * Get diagnostics for debugging
   * @return Dictionary with current state
   */
  public function getDiagnostics() as Lang.Dictionary {
    return {
      "enabled" => mEnabled,
      "updateCount" => mUpdateCount,
      "offsetIndex" => mOffsetIndex,
      "currentOffset" => mCurrentOffset,
      "shiftInterval" => mShiftInterval
    };
  }
}
