using Toybox.Lang;
using Toybox.System;

// Zero-allocation text display cache with hash-based invalidation
// Caches formatted display strings to minimize string allocations during updates
class DisplayTextCache {
  // Pre-allocated cache arrays (zero allocation during updates)
  private var mCachedTimes as Lang.Array<Lang.String>;
  private var mCachedLabels as Lang.Array<Lang.String>;
  private var mCachedDisplayTexts as Lang.Array<Lang.String>;
  private var mLastDisplayTextHash as Lang.Array<Lang.Number>;

  // Configuration
  private var mRowCount as Lang.Number;
  private var mDebugLogging as Lang.Boolean = false;

  /**
   * Initialize display text cache
   * @param rowCount Number of display rows to cache
   * @param debugLogging Enable verbose logging
   */
  function initialize(rowCount as Lang.Number, debugLogging as Lang.Boolean) {
    mRowCount = rowCount;
    mDebugLogging = debugLogging;

    // Pre-allocate all arrays (zero allocation during updates)
    mCachedTimes = new Lang.Array<Lang.String>[rowCount];
    mCachedLabels = new Lang.Array<Lang.String>[rowCount];
    mCachedDisplayTexts = new Lang.Array<Lang.String>[rowCount];
    mLastDisplayTextHash = new Lang.Array<Lang.Number>[rowCount];

    // Initialize with defaults
    for (var i = 0; i < rowCount; i++) {
      mCachedTimes[i] = "";
      mCachedLabels[i] = "";
      mCachedDisplayTexts[i] = "";
      mLastDisplayTextHash[i] = 0;
    }

    if (mDebugLogging) {
      System.println("DisplayTextCache: Initialized (" + rowCount + " rows)");
    }
  }

  /**
   * Update cached text for a completed milestone
   * Only updates if hash changed (milestone just completed)
   * @param rowIndex Display row index (0-based)
   * @param label Milestone label
   * @param finishTime Finish time in milliseconds
   * @return true if cache was updated
   */
  public function updateCompleted(
    rowIndex as Lang.Number,
    label as Lang.String,
    finishTime as Lang.Number
  ) as Lang.Boolean {
    // Use finish time as hash (changes once when milestone completes)
    var currentHash = finishTime;

    // Only update if hash changed (avoids string allocations)
    if (currentHash != mLastDisplayTextHash[rowIndex]) {
      mCachedTimes[rowIndex] = formatTime(finishTime);
      // Add ASCII-safe marker to completed milestone (avoid glyph fallback on device fonts)
      mCachedLabels[rowIndex] = Lang.format("$1$ *", [label]);
      // Combine label and time with double-space separator
      mCachedDisplayTexts[rowIndex] = Lang.format("$1$  $2$", [
        mCachedLabels[rowIndex],
        mCachedTimes[rowIndex],
      ]);
      mLastDisplayTextHash[rowIndex] = currentHash;

      if (mDebugLogging) {
        System.println(
          "DisplayTextCache: Updated completed row " +
            rowIndex +
            " (" +
            label +
            " @ " +
            mCachedTimes[rowIndex] +
            ")"
        );
      }

      return true;
    }

    return false;
  }

  /**
   * Update cached text for an in-progress milestone
   * Only updates when seconds change (reduces allocation frequency)
   * @param rowIndex Display row index (0-based)
   * @param label Milestone label
   * @param remainingTimeMs Remaining time in milliseconds
   * @return true if cache was updated
   */
  public function updateRemaining(
    rowIndex as Lang.Number,
    label as Lang.String,
    remainingTimeMs as Lang.Number
  ) as Lang.Boolean {
    // Hash based on seconds (updates once per second, not per frame)
    var currentHash = (remainingTimeMs / 1000).toNumber();

    // Only update when seconds change
    if (currentHash != mLastDisplayTextHash[rowIndex]) {
      mCachedTimes[rowIndex] = formatTime(remainingTimeMs);
      mCachedLabels[rowIndex] = label;
      mCachedDisplayTexts[rowIndex] = Lang.format("$1$  $2$", [
        mCachedLabels[rowIndex],
        mCachedTimes[rowIndex],
      ]);
      mLastDisplayTextHash[rowIndex] = currentHash;

      return true;
    }

    return false;
  }

  /**
   * Update cached text for milestone at zero (distance reached but not marked complete)
   * @param rowIndex Display row index (0-based)
   * @param label Milestone label
   * @return true if cache was updated
   */
  public function updateZero(
    rowIndex as Lang.Number,
    label as Lang.String
  ) as Lang.Boolean {
    // Only update if hash changed (use -1 as special marker for zero state)
    if (mLastDisplayTextHash[rowIndex] != -1) {
      mCachedTimes[rowIndex] = "0:00";
      mCachedLabels[rowIndex] = label;
      mCachedDisplayTexts[rowIndex] = Lang.format("$1$  $2$", [
        mCachedLabels[rowIndex],
        mCachedTimes[rowIndex],
      ]);
      mLastDisplayTextHash[rowIndex] = -1;

      if (mDebugLogging) {
        System.println(
          "DisplayTextCache: Updated zero row " + rowIndex + " (" + label + ")"
        );
      }

      return true;
    }

    return false;
  }

  /**
   * Get cached display text for a row
   * @param rowIndex Display row index (0-based)
   * @return Formatted display text (label + time)
   */
  public function getDisplayText(rowIndex as Lang.Number) as Lang.String {
    if (rowIndex >= 0 && rowIndex < mRowCount) {
      return mCachedDisplayTexts[rowIndex];
    }
    return "";
  }

  /**
   * Get cached label for a row
   * @param rowIndex Display row index (0-based)
   * @return Cached label
   */
  public function getLabel(rowIndex as Lang.Number) as Lang.String {
    if (rowIndex >= 0 && rowIndex < mRowCount) {
      return mCachedLabels[rowIndex];
    }
    return "";
  }

  /**
   * Get cached time for a row
   * @param rowIndex Display row index (0-based)
   * @return Cached formatted time
   */
  public function getTime(rowIndex as Lang.Number) as Lang.String {
    if (rowIndex >= 0 && rowIndex < mRowCount) {
      return mCachedTimes[rowIndex];
    }
    return "";
  }

  /**
   * Reset cache to initial state
   * @param defaultLabel Default label to use for all rows
   */
  public function reset(defaultLabel as Lang.String) as Void {
    for (var i = 0; i < mRowCount; i++) {
      mCachedTimes[i] = "--:--";
      mCachedLabels[i] = defaultLabel;
      mCachedDisplayTexts[i] = Lang.format("$1$  $2$", [defaultLabel, "--:--"]);
      mLastDisplayTextHash[i] = 0;
    }

    if (mDebugLogging) {
      System.println("DisplayTextCache: Reset to defaults");
    }
  }

  /**
   * Set initial cache values (typically during initialization)
   * @param rowIndex Display row index
   * @param label Initial label
   * @param time Initial time string
   */
  public function setInitial(
    rowIndex as Lang.Number,
    label as Lang.String,
    time as Lang.String
  ) as Void {
    if (rowIndex >= 0 && rowIndex < mRowCount) {
      mCachedTimes[rowIndex] = time;
      mCachedLabels[rowIndex] = label;
      mCachedDisplayTexts[rowIndex] = Lang.format("$1$  $2$", [label, time]);
      mLastDisplayTextHash[rowIndex] = 0;
    }
  }

  /**
   * Format milliseconds as HH:MM or MM:SS
   * @param millis Time in milliseconds
   * @return Formatted time string
   */
  private function formatTime(millis as Lang.Number) as Lang.String {
    var totalSec = millis / 1000;
    var hours = totalSec / 3600;
    var mins = (totalSec % 3600) / 60;
    var secs = totalSec % 60;

    if (hours > 0) {
      // HH:MM format for times over an hour
      return Lang.format("$1$:$2$", [hours.format("%d"), mins.format("%02d")]);
    } else {
      // MM:SS format for times under an hour
      return Lang.format("$1$:$2$", [mins.format("%d"), secs.format("%02d")]);
    }
  }

  /**
   * Get diagnostics for debugging
   * @return Dictionary with cache state
   */
  public function getDiagnostics() as Lang.Dictionary {
    return {
      "rowCount" => mRowCount,
      "displayTexts" => mCachedDisplayTexts,
      "hashes" => mLastDisplayTextHash,
    };
  }
}
