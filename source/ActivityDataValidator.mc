using Toybox.Lang;
using Toybox.Activity;
using Toybox.Position;
using Toybox.System;

// Validates activity data (GPS quality, distance thresholds)
// Tracks warm-up state and provides status information
class ActivityDataValidator {

  // Validation state
  private var mGpsQualityGood as Lang.Boolean = false;
  private var mMinDistanceReached as Lang.Boolean = false;

  // Configuration
  private var mMinPredictionDistance as Lang.Number;
  private var mDebugLogging as Lang.Boolean = false;

  /**
   * Initialize activity data validator
   * @param minPredictionDistance Minimum distance (meters) before predictions are valid
   * @param debugLogging Enable verbose logging
   */
  function initialize(minPredictionDistance as Lang.Number, debugLogging as Lang.Boolean) {
    mMinPredictionDistance = minPredictionDistance;
    mDebugLogging = debugLogging;

    if (mDebugLogging) {
      System.println("ActivityDataValidator: Initialized (minDistance=" +
                     minPredictionDistance + "m)");
    }
  }

  /**
   * Validate GPS data quality
   * Updates internal GPS quality state
   * @param info Activity info with GPS data
   * @return true if GPS quality is acceptable
   */
  public function validateGpsData(info as Activity.Info) as Lang.Boolean {
    var accuracy = info.currentLocationAccuracy;

    // If accuracy is null, assume GPS is good (some devices don't report this)
    if (accuracy == null) {
      mGpsQualityGood = true;
      return true;
    }

    // Check if accuracy is better than QUALITY_USABLE threshold
    if (accuracy > Position.QUALITY_USABLE) {
      if (mGpsQualityGood && mDebugLogging) {
        System.println("ActivityDataValidator: GPS quality degraded (accuracy=" + accuracy + ")");
      }
      mGpsQualityGood = false;
      return false;
    }

    if (!mGpsQualityGood && mDebugLogging) {
      System.println("ActivityDataValidator: GPS quality restored (accuracy=" + accuracy + ")");
    }
    mGpsQualityGood = true;
    return true;
  }

  /**
   * Validate minimum distance threshold
   * Updates internal distance state
   * @param elapsedDistance Elapsed distance in meters
   * @return true if minimum distance has been reached
   */
  public function validateMinimumDistance(elapsedDistance as Lang.Float?) as Lang.Boolean {
    if (elapsedDistance == null || elapsedDistance < mMinPredictionDistance) {
      if (mMinDistanceReached && mDebugLogging) {
        System.println("ActivityDataValidator: Below minimum distance (" +
                       (elapsedDistance != null ? elapsedDistance : 0) + "m < " +
                       mMinPredictionDistance + "m)");
      }
      mMinDistanceReached = false;
      return false;
    }

    if (!mMinDistanceReached && mDebugLogging) {
      System.println("ActivityDataValidator: Minimum distance reached (" +
                     elapsedDistance + "m >= " + mMinPredictionDistance + "m)");
    }
    mMinDistanceReached = true;
    return true;
  }

  /**
   * Check if GPS quality is good
   * @return true if GPS is good
   */
  public function isGpsQualityGood() as Lang.Boolean {
    return mGpsQualityGood;
  }

  /**
   * Check if minimum distance has been reached
   * @return true if minimum distance reached
   */
  public function isMinDistanceReached() as Lang.Boolean {
    return mMinDistanceReached;
  }

  /**
   * Check if validator is warmed up (GPS good AND minimum distance reached)
   * @return true if ready for predictions
   */
  public function isWarmedUp() as Lang.Boolean {
    return mGpsQualityGood && mMinDistanceReached;
  }

  /**
   * Get current validation status as string
   * @return Status string for display
   */
  public function getStatusText() as Lang.String? {
    if (!mGpsQualityGood) {
      return "WAITING GPS";
    } else if (!mMinDistanceReached) {
      return "WARMING UP";
    }
    return null;  // No status message needed (all good)
  }

  /**
   * Reset to initial state
   */
  public function reset() as Void {
    mGpsQualityGood = false;
    mMinDistanceReached = false;

    if (mDebugLogging) {
      System.println("ActivityDataValidator: Reset");
    }
  }

  /**
   * Get diagnostics for debugging
   * @return Dictionary with current state
   */
  public function getDiagnostics() as Lang.Dictionary {
    return {
      "gpsQualityGood" => mGpsQualityGood,
      "minDistanceReached" => mMinDistanceReached,
      "minPredictionDistance" => mMinPredictionDistance,
      "isWarmedUp" => isWarmedUp()
    };
  }
}
