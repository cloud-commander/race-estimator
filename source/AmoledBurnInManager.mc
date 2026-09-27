using Toybox.Lang;
using Toybox.System;

// Manages AMOLED burn-in protection through pixel shifting.
// Everything drawn is shifted by (x, y) around a small orbit so no pixel of
// static text/icons stays lit in the same place for more than a minute.
class AmoledBurnInManager {

  // Orbit of (dx, dy) offsets, stepped once per shift interval. Radius is
  // kept at <= 3px so the move is invisible mid-run but spreads wear.
  private const OFFSETS_X = [0, 3, 1, -2, -3, -1, 2] as Lang.Array<Lang.Number>;
  private const OFFSETS_Y = [0, 1, 3, 2, -1, -3, -2] as Lang.Array<Lang.Number>;

  // State tracking
  private var mUpdateCount as Lang.Number = 0;
  private var mOffsetIndex as Lang.Number = 0;
  private var mShiftInterval as Lang.Number;
  private var mEnabled as Lang.Boolean = false;
  private var mDebugLogging as Lang.Boolean = false;

  /**
   * Initialize burn-in protection manager
   * @param shiftInterval Number of updates between position shifts (onUpdate runs ~1/s)
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
  }

  /**
   * Update pixel shift state (call once per onUpdate)
   * @return true if position offset changed this update
   */
  public function update() as Lang.Boolean {
    if (!mEnabled) {
      return false;
    }

    mUpdateCount++;
    if (mUpdateCount >= mShiftInterval) {
      mUpdateCount = 0;
      mOffsetIndex = (mOffsetIndex + 1) % OFFSETS_X.size();

      if (mDebugLogging) {
        System.println("AmoledBurnInManager: shift to (" + getOffsetX() + ", " + getOffsetY() + ")");
      }
      return true;
    }
    return false;
  }

  public function getOffsetX() as Lang.Number {
    return mEnabled ? OFFSETS_X[mOffsetIndex] : 0;
  }

  public function getOffsetY() as Lang.Number {
    return mEnabled ? OFFSETS_Y[mOffsetIndex] : 0;
  }

  public function isEnabled() as Lang.Boolean {
    return mEnabled;
  }

  public function reset() as Void {
    mUpdateCount = 0;
    mOffsetIndex = 0;
  }
}
