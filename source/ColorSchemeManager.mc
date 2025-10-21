using Toybox.Lang;
using Toybox.Graphics;
using Toybox.System;

// Manages color schemes for different display types
// Handles AMOLED burn-in mitigation and light/dark themes
class ColorSchemeManager {

  // Current color scheme
  private var mBackgroundColor as Lang.Number = Graphics.COLOR_BLACK;
  private var mForegroundColor as Lang.Number = Graphics.COLOR_WHITE;
  private var mAccentColor as Lang.Number = Graphics.COLOR_ORANGE;
  private var mDimmedColor as Lang.Number = Graphics.COLOR_DK_GRAY;

  // Display type
  private var mIsAmoled as Lang.Boolean = false;

  // Debug logging
  private var mDebugLogging as Lang.Boolean = false;

  /**
   * Initialize color scheme manager
   * @param isAmoled True if display requires burn-in protection
   * @param debugLogging Enable verbose logging
   */
  function initialize(isAmoled as Lang.Boolean, debugLogging as Lang.Boolean) {
    mIsAmoled = isAmoled;
    mDebugLogging = debugLogging;

    if (mDebugLogging) {
      System.println("ColorSchemeManager: Initialized (AMOLED=" + isAmoled + ")");
    }
  }

  /**
   * Update colors based on display type and system background
   * @param systemBackground System background color (ignored for AMOLED)
   */
  public function updateColors(systemBackground as Lang.Number) as Void {
    if (mIsAmoled) {
      // AMOLED burn-in mitigation: Use dimmer colors to reduce pixel wear
      mBackgroundColor = Graphics.COLOR_BLACK;
      mForegroundColor = Graphics.COLOR_LT_GRAY;  // Dimmer than pure white
      mAccentColor = Graphics.COLOR_BLUE;         // Blue has lower OLED power draw than red/orange
      mDimmedColor = Graphics.COLOR_DK_GRAY;      // Very dim for completed milestones

      if (mDebugLogging) {
        System.println("ColorSchemeManager: Using AMOLED color scheme");
      }
    } else {
      // MIP display: Use system background and adjust foreground accordingly
      mBackgroundColor = systemBackground;

      // Detect light vs dark background
      if (
        systemBackground == Graphics.COLOR_WHITE ||
        systemBackground == Graphics.COLOR_LT_GRAY ||
        systemBackground == Graphics.COLOR_TRANSPARENT
      ) {
        // Light background - use dark text
        mForegroundColor = Graphics.COLOR_BLACK;
        mAccentColor = Graphics.COLOR_BLUE;

        if (mDebugLogging) {
          System.println("ColorSchemeManager: Using light theme (bg=" + systemBackground + ")");
        }
      } else {
        // Dark background - use light text
        mForegroundColor = Graphics.COLOR_WHITE;
        mAccentColor = Graphics.COLOR_ORANGE;

        if (mDebugLogging) {
          System.println("ColorSchemeManager: Using dark theme (bg=" + systemBackground + ")");
        }
      }

      // On MIP, dimmed color same as foreground (no burn-in concerns)
      mDimmedColor = mForegroundColor;
    }
  }

  /**
   * Get background color
   * @return Background color
   */
  public function getBackgroundColor() as Lang.Number {
    return mBackgroundColor;
  }

  /**
   * Get foreground color
   * @return Foreground color
   */
  public function getForegroundColor() as Lang.Number {
    return mForegroundColor;
  }

  /**
   * Get accent color
   * @return Accent color
   */
  public function getAccentColor() as Lang.Number {
    return mAccentColor;
  }

  /**
   * Get dimmed color (for completed items)
   * @return Dimmed color
   */
  public function getDimmedColor() as Lang.Number {
    return mDimmedColor;
  }

  /**
   * Check if using AMOLED color scheme
   * @return true if AMOLED
   */
  public function isAmoled() as Lang.Boolean {
    return mIsAmoled;
  }

  /**
   * Get diagnostics for debugging
   * @return Dictionary with current state
   */
  public function getDiagnostics() as Lang.Dictionary {
    return {
      "isAmoled" => mIsAmoled,
      "backgroundColor" => mBackgroundColor,
      "foregroundColor" => mForegroundColor,
      "accentColor" => mAccentColor,
      "dimmedColor" => mDimmedColor
    };
  }
}
