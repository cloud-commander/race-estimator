using Toybox.Lang;
using Toybox.Math;

//! Load-carriage energy model.
//!
//! Pandolf, Givoni & Goldman (1977), "Predicting energy expenditure with loads
//! while standing or walking very slowly", with the downhill correction from
//! Santee et al. (2003). Garmin's own fenix 8 ruck algorithm is not public, so
//! numbers will differ from the native feature. Published field comparisons
//! put these equations within roughly +/-15-30% of measured energy cost.
//! Calories are gross (include resting metabolism), not "active" calories.
//!
//! Guard rails (from an adversarial review of the published equations):
//! - grade is clamped to MIN/MAX_MODEL_GRADE; Santee's (G+6)^2 term explodes
//!   far outside the grades it was derived from
//! - the Santee correction fades in over 0..-3% grade (the published form
//!   jumps ~5% at G=0) and with speed up to 1 m/s (its speed-independent
//!   terms would otherwise charge a downhill rate while standing still)
module RuckModel {
  //! Pandolf terrain factors (eta), indexed by the "terrain" setting:
  //! paved/treadmill, dirt road, light brush, heavy brush, swamp, loose sand
  const TERRAIN_FACTORS = [1.0, 1.1, 1.2, 1.5, 1.8, 2.1] as Lang.Array<Lang.Float>;

  const JOULES_PER_KCAL = 4184.0;
  const MIN_MODEL_GRADE = -20.0;
  const MAX_MODEL_GRADE = 25.0;
  const SANTEE_BLEND_GRADE = 3.0; // % of descent over which Santee fades in
  const SANTEE_FULL_SPEED = 1.0; // m/s at which Santee applies fully

  //! Metabolic rate in watts.
  //! bodyKg: body mass (> 0), loadKg: carried load, speed: m/s,
  //! gradePct: percent grade (positive = uphill), eta: terrain factor
  function metabolicRate(
    bodyKg as Lang.Float,
    loadKg as Lang.Float,
    speed as Lang.Float,
    gradePct as Lang.Float,
    eta as Lang.Float
  ) as Lang.Float {
    if (gradePct < MIN_MODEL_GRADE) {
      gradePct = MIN_MODEL_GRADE;
    } else if (gradePct > MAX_MODEL_GRADE) {
      gradePct = MAX_MODEL_GRADE;
    }
    var total = bodyKg + loadKg;
    var ratio = loadKg / bodyKg;
    var standing = 1.5 * bodyKg + 2.0 * total * ratio * ratio;
    var rate =
      standing + eta * total * (1.5 * speed * speed + 0.35 * speed * gradePct);

    if (gradePct < 0.0) {
      // Santee correction: Pandolf underestimates the cost of walking downhill
      var g6 = gradePct + 6.0;
      var correction =
        eta *
        ((gradePct * total * speed) / 3.5 -
          (total * g6 * g6) / bodyKg +
          (25.0 - speed * speed));
      var gradeBlend = -gradePct / SANTEE_BLEND_GRADE;
      var speedBlend = speed / SANTEE_FULL_SPEED;
      rate -=
        correction *
        (gradeBlend < 1.0 ? gradeBlend : 1.0) *
        (speedBlend < 1.0 ? speedBlend : 1.0);
    }

    // Never report less than the cost of standing still with the load
    return rate > standing ? rate : standing;
  }

  //! Speed (m/s) that costs the same energy walking on flat, paved ground
  //! with no load. Folds load, grade and terrain into one comparable pace.
  function equivalentUnloadedSpeed(
    metabolicW as Lang.Float,
    bodyKg as Lang.Float
  ) as Lang.Float {
    var base = 1.5 * bodyKg;
    if (metabolicW <= base) {
      return 0.0;
    }
    return Math.sqrt((metabolicW - base) / base).toFloat();
  }

  function wattsToKcalPerHour(watts as Lang.Float) as Lang.Float {
    return (watts * 3600.0) / JOULES_PER_KCAL;
  }
}
