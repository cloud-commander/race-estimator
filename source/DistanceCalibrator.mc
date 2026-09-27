using Toybox.Lang;
using Toybox.Math;

// Lap-button sync to official course markers.
//
// GPS usually measures a race 1-2% long (corners, weaving, drift), so
// milestones fire before the real 10K sign. Pressing lap at a km / mile
// marker snaps the distance to the nearest whole unit; from then on the
// watch's distance is scaled by marker / raw, so the correction also covers
// the error still to come. Treadmills (belt vs footpod) get the same fix.
//
// A lap only counts as a sync when it is close to a whole unit. Auto-lap
// fires at whole units of *raw* GPS distance; those laps are ignored, or
// they would undo a manual sync.
class DistanceCalibrator {
  private const MAX_OFFSET_FRACTION = 0.025d; // 2.5% of the marker (GPS is ~1-2% long)
  private const MIN_OFFSET_M = 100.0d; // ... but allow at least this near 1 km
  private const MIN_SCALE = 0.94d;
  private const MAX_SCALE = 1.06d;
  private const AUTO_LAP_M = 15.0d; // raw distance this close to a unit = auto-lap

  private var mScale as Lang.Double = 1.0d;
  private var mLastMarkerM as Lang.Double = 0.0d;

  function initialize() {}

  public function reset() as Void {
    mScale = 1.0d;
    mLastMarkerM = 0.0d;
  }

  public function getScale() as Lang.Double {
    return mScale;
  }

  // Restore (persistence); out-of-range values are ignored
  public function setScale(scale as Lang.Double) as Void {
    if (scale >= MIN_SCALE && scale <= MAX_SCALE) {
      mScale = scale;
    }
  }

  public function apply(rawM as Lang.Double) as Lang.Double {
    return rawM * mScale;
  }

  // Marker (metres) the last accepted sync snapped to
  public function getLastMarkerM() as Lang.Double {
    return mLastMarkerM;
  }

  /**
   * Lap pressed at raw watch distance rawM
   * @param unitM 1000 or 1609.344 (the device's distance units)
   * @return the ratio new/old scale when accepted (for rescaling history),
   *         or 0 when the lap was not near a marker
   */
  public function onLap(rawM as Lang.Double, unitM as Lang.Double) as Lang.Double {
    if (rawM <= 0.0d) {
      return 0.0d;
    }
    var rawOffset = rawM - Math.round(rawM / unitM) * unitM;
    if (rawOffset < AUTO_LAP_M && rawOffset > -AUTO_LAP_M) {
      return 0.0d; // auto-lap (or already on a marker): nothing to correct
    }
    var corrected = rawM * mScale;
    var units = Math.round(corrected / unitM);
    if (units < 1.0d) {
      return 0.0d;
    }
    var markerM = units * unitM;
    var offset = corrected - markerM;
    if (offset < 0.0d) {
      offset = -offset;
    }
    var limit = markerM * MAX_OFFSET_FRACTION;
    if (limit < MIN_OFFSET_M) {
      limit = MIN_OFFSET_M;
    }
    if (offset > limit) {
      return 0.0d;
    }
    var scale = markerM / rawM;
    if (scale < MIN_SCALE || scale > MAX_SCALE) {
      return 0.0d;
    }
    var ratio = scale / mScale;
    mScale = scale;
    mLastMarkerM = markerM;
    return ratio;
  }
}
