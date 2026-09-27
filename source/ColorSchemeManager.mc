using Toybox.Lang;
using Toybox.Graphics;

// 8-bit palette, CGA-inspired, tuned per panel type.
//
// MIP (fenix 7) is reflective and low-contrast: mid-tones wash out in
// daylight, so it uses full-intensity primaries (0x00/0xFF channels) plus one
// mid grey for the gauge track. All are native MIP palette colours, so
// nothing is dithered.
//
// AMOLED (fenix 8, epix) is emissive: saturated neon reads well even at half
// intensity, and OLED power/wear scale with brightness, so it uses the
// 0xAA row of the same palette with a near-black track.
class ColorSchemeManager {
  // Dark (MIP)
  private const D_VALUE = 0xFFFFFF;
  private const D_LABEL = 0x00FFFF; // cyan
  private const D_TITLE = 0xFFFF00; // yellow
  private const D_STATUS = 0xFF00FF; // magenta
  private const D_PROGRESS = 0x00FF00; // green
  private const D_TRACK = 0x555555; // visible but quiet in sunlight
  // Light (MIP, white background): yellow/cyan vanish on white, so darker hues
  private const L_VALUE = 0x000000;
  private const L_LABEL = 0x0000FF;
  private const L_TITLE = 0xAA00AA;
  private const L_STATUS = 0xFF0000;
  private const L_PROGRESS = 0x00AA00;
  private const L_TRACK = 0xAAAAAA;
  // AMOLED (always black background, half intensity)
  private const A_VALUE = 0xAAAAAA;
  private const A_LABEL = 0x00AAAA;
  private const A_TITLE = 0xAAAA00;
  private const A_STATUS = 0xAA00AA;
  private const A_PROGRESS = 0x00AA00;
  private const A_TRACK = 0x0000AA; // dim blue: future pips must stay visible

  private var mBackground as Lang.Number = Graphics.COLOR_BLACK;
  private var mValue as Lang.Number = D_VALUE;
  private var mLabel as Lang.Number = D_LABEL;
  private var mTitle as Lang.Number = D_TITLE;
  private var mStatus as Lang.Number = D_STATUS;
  private var mProgress as Lang.Number = D_PROGRESS;
  private var mTrack as Lang.Number = D_TRACK;

  private var mIsAmoled as Lang.Boolean = false;

  function initialize(isAmoled as Lang.Boolean, debugLogging as Lang.Boolean) {
    mIsAmoled = isAmoled;
  }

  /**
   * Pick the palette for the system background (ignored on AMOLED)
   */
  public function updateColors(systemBackground as Lang.Number) as Void {
    if (mIsAmoled) {
      mBackground = Graphics.COLOR_BLACK;
      mValue = A_VALUE;
      mLabel = A_LABEL;
      mTitle = A_TITLE;
      mStatus = A_STATUS;
      mProgress = A_PROGRESS;
      mTrack = A_TRACK;
    } else if (
      systemBackground == Graphics.COLOR_WHITE ||
      systemBackground == Graphics.COLOR_LT_GRAY
    ) {
      mBackground = systemBackground;
      mValue = L_VALUE;
      mLabel = L_LABEL;
      mTitle = L_TITLE;
      mStatus = L_STATUS;
      mProgress = L_PROGRESS;
      mTrack = L_TRACK;
    } else {
      mBackground = Graphics.COLOR_BLACK;
      mValue = D_VALUE;
      mLabel = D_LABEL;
      mTitle = D_TITLE;
      mStatus = D_STATUS;
      mProgress = D_PROGRESS;
      mTrack = D_TRACK;
    }
  }

  public function getBackgroundColor() as Lang.Number {
    return mBackground;
  }

  // Numbers (finish times)
  public function getValueColor() as Lang.Number {
    return mValue;
  }

  // Table labels, context line
  public function getLabelColor() as Lang.Number {
    return mLabel;
  }

  // Name of the milestone in focus
  public function getTitleColor() as Lang.Number {
    return mTitle;
  }

  // Status messages (waiting for GPS, stage clear...)
  public function getStatusColor() as Lang.Number {
    return mStatus;
  }

  // Filled gauge segments, reached ticks
  public function getProgressColor() as Lang.Number {
    return mProgress;
  }

  // Empty gauge segments, dividers
  public function getTrackColor() as Lang.Number {
    return mTrack;
  }
}
