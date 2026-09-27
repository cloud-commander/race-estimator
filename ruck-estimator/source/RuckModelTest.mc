using Toybox.Lang;
using Toybox.Test;

// Run with: monkeyc -t ... then monkeydo <prg> <device> -t
(:test)
module RuckModelTest {
  function near(a as Lang.Float, b as Lang.Float, tol as Lang.Float) as Lang.Boolean {
    var d = a - b;
    return d < tol && d > -tol;
  }

  // 80 kg walker, 20 kg pack, 1.5 m/s, flat, paved:
  // 1.5*80 + 2*100*(0.25^2) + 100*(1.5*2.25) = 120 + 12.5 + 337.5 = 470 W
  (:test)
  function flatLoaded(logger as Test.Logger) as Lang.Boolean {
    var m = RuckModel.metabolicRate(80.0, 20.0, 1.5, 0.0, 1.0);
    logger.debug("flat loaded = " + m);
    return near(m, 470.0, 0.01);
  }

  // With no load the equivalent unloaded speed must equal the real speed
  (:test)
  function unloadedRoundTrip(logger as Test.Logger) as Lang.Boolean {
    var m = RuckModel.metabolicRate(80.0, 0.0, 1.5, 0.0, 1.0);
    var v = RuckModel.equivalentUnloadedSpeed(m, 80.0);
    logger.debug("unloaded eq speed = " + v);
    return near(v, 1.5, 0.001);
  }

  // A pack makes the equivalent unloaded pace faster than the real one
  (:test)
  function loadRaisesEquivalentSpeed(logger as Test.Logger) as Lang.Boolean {
    var m = RuckModel.metabolicRate(80.0, 20.0, 1.5, 0.0, 1.0);
    var v = RuckModel.equivalentUnloadedSpeed(m, 80.0);
    logger.debug("loaded eq speed = " + v);
    return near(v, 1.7078, 0.001);
  }

  (:test)
  function uphillCostsMore(logger as Test.Logger) as Lang.Boolean {
    var flat = RuckModel.metabolicRate(80.0, 20.0, 1.2, 0.0, 1.0);
    var up = RuckModel.metabolicRate(80.0, 20.0, 1.2, 10.0, 1.0);
    return up > flat;
  }

  // Santee correction keeps steep descents well above the standing cost
  (:test)
  function steepDownhillCorrected(logger as Test.Logger) as Lang.Boolean {
    var m = RuckModel.metabolicRate(80.0, 20.0, 1.2, -20.0, 1.0);
    logger.debug("-20% downhill = " + m);
    return near(m, 415.5, 1.0);
  }

  (:test)
  function stationaryIsStandingCost(logger as Test.Logger) as Lang.Boolean {
    var m = RuckModel.metabolicRate(80.0, 20.0, 0.0, 0.0, 1.0);
    return near(m, 132.5, 0.01) &&
      RuckModel.equivalentUnloadedSpeed(120.0, 80.0) == 0.0;
  }

  // Review finding 1: no downhill surcharge while standing on a slope
  (:test)
  function stationaryOnDescentIsStandingCost(logger as Test.Logger) as Lang.Boolean {
    var m = RuckModel.metabolicRate(80.0, 20.0, 0.0, -20.0, 1.0);
    logger.debug("standing on -20% = " + m);
    return near(m, 132.5, 0.01);
  }

  // Review finding 2: no jump in cost as grade crosses zero
  (:test)
  function continuousAtZeroGrade(logger as Test.Logger) as Lang.Boolean {
    var flat = RuckModel.metabolicRate(80.0, 20.0, 1.5, 0.0, 1.0);
    var down = RuckModel.metabolicRate(80.0, 20.0, 1.5, -0.01, 1.0);
    var up = RuckModel.metabolicRate(80.0, 20.0, 1.5, 0.01, 1.0);
    logger.debug("flat=" + flat + " -0.01%=" + down + " +0.01%=" + up);
    // Only Pandolf's own 0.35*V*G slope term moves (+/-0.5 W at 0.01%)
    return near(down, flat, 1.0) && near(up, flat, 1.0);
  }

  // Review finding 3: grades beyond the model's range are clamped
  (:test)
  function steepGradesClamped(logger as Test.Logger) as Lang.Boolean {
    var m20 = RuckModel.metabolicRate(80.0, 20.0, 1.5, -20.0, 1.0);
    var m45 = RuckModel.metabolicRate(80.0, 20.0, 1.5, -45.0, 1.0);
    var u25 = RuckModel.metabolicRate(80.0, 20.0, 1.5, 25.0, 1.0);
    var u45 = RuckModel.metabolicRate(80.0, 20.0, 1.5, 45.0, 1.0);
    return m45 == m20 && u45 == u25;
  }

  (:test)
  function sandCostsMoreThanPavement(logger as Test.Logger) as Lang.Boolean {
    var paved = RuckModel.metabolicRate(80.0, 20.0, 1.5, 0.0, 1.0);
    var sand = RuckModel.metabolicRate(80.0, 20.0, 1.5, 0.0, 2.1);
    return sand > paved;
  }
}
