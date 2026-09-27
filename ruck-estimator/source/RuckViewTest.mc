using Toybox.Activity;
using Toybox.Application;
using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// Drives the real RuckView through scripted activities (no simulator input
// needed): moving/stopped, grades, pause, lap, reset, restart-restore, units,
// GPS drift, timer gaps, warning thresholds and session stats.
(:test)
module RuckViewTest {
  const START = 1700000000;

  // Deterministic settings: 80 kg body, 20 kg pack, kg + km, paved, warn 30%
  // units: 0 kg+km, 1 kg+mi, 2 lbs+mi, 3 lbs+km (both settings at once)
  function setup(pack as Lang.Float, units as Lang.Number) as RuckView {
    Application.Properties.setValue("bodyWeightKg", 80.0);
    Application.Properties.setValue("packWeight", pack);
    Application.Properties.setValue("weightUnit", units == 2 || units == 3 ? 1 : 0);
    Application.Properties.setValue("distanceUnit", units == 1 || units == 2 ? 1 : 0);
    Application.Properties.setValue("terrain", 0);
    Application.Properties.setValue("loadWarnPct", 30);
    Application.Storage.clearValues();
    var view = (Application.getApp() as RuckApp).testView();
    view.onTimerReset();
    view.loadSettings();
    return view;
  }

  function newInfo() as Activity.Info {
    var info = new Activity.Info();
    info.timerTime = 0;
    info.elapsedDistance = 0.0;
    info.currentSpeed = 0.0;
    info.altitude = 100.0;
    info.startTime = new Time.Moment(START);
    return info;
  }

  // Advance `secs` one-second ticks at `speed` m/s on `grade` %
  function run(
    view as RuckView,
    info as Activity.Info,
    secs as Lang.Number,
    speed as Lang.Float,
    grade as Lang.Float
  ) as Void {
    for (var i = 0; i < secs; i++) {
      info.timerTime = (info.timerTime as Lang.Number) + 1000;
      info.elapsedDistance = (info.elapsedDistance as Lang.Float) + speed;
      info.altitude = (info.altitude as Lang.Float) + (speed * grade) / 100.0;
      info.currentSpeed = speed;
      view.compute(info);
    }
  }

  function f(state as Lang.Dictionary<Lang.String, Lang.Object?>, key as Lang.String) as Lang.Float {
    return (state[key] as Lang.Numeric).toFloat();
  }

  function near(a as Lang.Float, b as Lang.Float, tol as Lang.Float) as Lang.Boolean {
    return (a - b).abs() <= tol;
  }

  // 10 min flat at 1.5 m/s: ~470 W -> ~67 kcal, 20 kg x 900 m = 18 kg-km
  (:test)
  function flatWalkTotals(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 600, 1.5, 0.0);
    var s = view.testState();
    logger.debug("kcal=" + s["kcal"] + " lkm=" + s["lkm"] + " w=" + s["w"]);
    return near(f(s, "w"), 470.0, 1.0) &&
      near(f(s, "kcal"), 67.4, 1.5) &&
      near(f(s, "lkm"), 18000.0, 400.0);
  }

  // Paused timer (timerTime frozen) accumulates nothing
  (:test)
  function pausedAccumulatesNothing(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 60, 1.5, 0.0);
    var before = f(view.testState(), "kcal");
    view.onTimerPause();
    for (var i = 0; i < 120; i++) {
      info.elapsedDistance = (info.elapsedDistance as Lang.Float) + 1.5;
      view.compute(info);
    }
    var after = f(view.testState(), "kcal");
    logger.debug("before=" + before + " after=" + after);
    return before == after;
  }

  // Stopping at the bottom of a -20% descent costs standing rate, not downhill
  (:test)
  function stoppedAfterDescentIsStanding(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 300, 1.2, -20.0);
    run(view, info, 120, 0.0, 0.0);
    var w = f(view.testState(), "w");
    logger.debug("stopped w=" + w);
    return near(w, 132.5, 1.0);
  }

  // GPS drift while standing doesn't add load x distance
  (:test)
  function driftIgnored(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 60, 0.2, 0.0);
    var lkm = f(view.testState(), "lkm");
    logger.debug("drift lkm=" + lkm);
    return lkm == 0.0;
  }

  // A 20 s timer gap counts 5 s of energy but all of the distance
  (:test)
  function timerGapCapped(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 30, 1.5, 0.0);
    var s0 = view.testState();
    info.timerTime = (info.timerTime as Lang.Number) + 20000;
    info.elapsedDistance = (info.elapsedDistance as Lang.Float) + 30.0;
    view.compute(info);
    var s1 = view.testState();
    var dKcal = f(s1, "kcal") - f(s0, "kcal");
    var dLkm = f(s1, "lkm") - f(s0, "lkm");
    logger.debug("gap dKcal=" + dKcal + " dLkm=" + dLkm);
    return near(dKcal, 470.0 * 5.0 / 4184.0, 0.05) && near(dLkm, 600.0, 0.1);
  }

  // Lap resets the lap count only
  (:test)
  function lapResetsLapOnly(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 120, 1.5, 0.0);
    var total = f(view.testState(), "kcal");
    view.onTimerLap();
    var s = view.testState();
    run(view, info, 60, 1.5, 0.0);
    var s2 = view.testState();
    logger.debug("total=" + total + " lap after=" + s2["lap"]);
    return f(s, "lap") == 0.0 && f(s, "kcal") == total &&
      near(f(s2, "lap"), 470.0 * 60.0 / 4184.0, 0.3);
  }

  (:test)
  function resetClearsEverything(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 120, 1.5, 5.0);
    view.onTimerReset();
    var s = view.testState();
    return f(s, "kcal") == 0.0 && f(s, "lkm") == 0.0 && f(s, "lap") == 0.0 &&
      f(s, "mov") == 0.0 && f(s, "peak") == 0.0 && f(s, "eqd") == 0.0;
  }

  // A restarted data field picks up this activity's saved totals...
  (:test)
  function restoreAfterRestart(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 90, 1.5, 0.0);
    view.onTimerPause(); // saves
    var saved = f(view.testState(), "kcal");
    view.testRestart();
    if (f(view.testState(), "kcal") != 0.0) {
      return false;
    }
    run(view, info, 1, 1.5, 0.0);
    var restored = f(view.testState(), "kcal");
    logger.debug("saved=" + saved + " restored=" + restored);
    return restored >= saved && restored < saved + 0.5;
  }

  // ...but never another activity's
  (:test)
  function noRestoreAcrossActivities(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 90, 1.5, 0.0);
    view.onTimerPause();
    view.testRestart();
    var info2 = newInfo();
    info2.startTime = new Time.Moment(START + 3600);
    info2.timerTime = 200000;
    run(view, info2, 1, 1.5, 0.0);
    var kcal = f(view.testState(), "kcal");
    logger.debug("other activity kcal=" + kcal);
    return kcal < 0.5;
  }

  // lb + mi: 44 lb pack = 19.96 kg; labels and pace per mile
  (:test)
  function imperialUnits(logger as Test.Logger) as Lang.Boolean {
    var view = setup(44.0, 2);
    var info = newInfo();
    run(view, info, 120, 1.5, 0.0);
    var s = view.testState();
    var values = s["values"] as Lang.Array<Lang.String>;
    logger.debug("pack=" + s["packLabel"] + " unit=" + s["loadUnit"] + " pace=" + values[0]);
    return near(f(s, "loadKg"), 19.958, 0.01) &&
      (s["loadUnit"] as Lang.String).equals("LB-MI") &&
      (s["packLabel"] as Lang.String).equals("PACK 44LBS");
  }

  // kg + mi and lb + km combinations
  (:test)
  function mixedUnits(logger as Test.Logger) as Lang.Boolean {
    var a = setup(20.0, 1).testState();
    var aUnit = a["loadUnit"] as Lang.String;
    var aPack = a["packLabel"] as Lang.String;
    var b = setup(44.0, 3).testState();
    logger.debug("kg+mi=" + aUnit + " lb+km=" + b["loadUnit"]);
    return aUnit.equals("KG-MI") &&
      (b["loadUnit"] as Lang.String).equals("LB-KM") &&
      aPack.equals("PACK 20KG");
  }

  // Effort pace equals real pace with no pack on the flat
  (:test)
  function effortPaceNoPack(logger as Test.Logger) as Lang.Boolean {
    var view = setup(0.0, 0);
    var info = newInfo();
    run(view, info, 120, 1.5, 0.0);
    var values = view.testState()["values"] as Lang.Array<Lang.String>;
    logger.debug("pace=" + values[0]);
    return values[0].equals("11:07"); // 1000 m / 1.5 m/s = 666.7 s
  }

  // Warning: 30.4% shows "30%" and no warning; 30.6% shows "31%" and warns
  (:test)
  function warningMatchesLabel(logger as Test.Logger) as Lang.Boolean {
    var a = setup(24.32, 0).testState();
    var aPct = a["pctShown"] as Lang.Number;
    var aWarn = a["warn"] as Lang.Boolean;
    var b = setup(24.48, 0).testState();
    logger.debug("a=" + aPct + "/" + aWarn + " b=" + b["pctShown"] + "/" + b["warn"]);
    return aPct == 30 && !aWarn &&
      (b["pctShown"] as Lang.Number) == 31 && (b["warn"] as Lang.Boolean);
  }

  // Session stats: effort pace average, peak burn only after the first minute
  (:test)
  function sessionStats(logger as Test.Logger) as Lang.Boolean {
    var view = setup(20.0, 0);
    var info = newInfo();
    run(view, info, 30, 1.5, 20.0); // steep start: excluded from peak
    var early = f(view.testState(), "peak");
    run(view, info, 600, 1.5, 0.0);
    var s = view.testState();
    var eqPace = (f(s, "mov") / 60000.0) / (f(s, "eqd") / 1000.0);
    logger.debug("early peak=" + early + " peak=" + s["peak"] + " eq pace min/km=" + eqPace);
    // Flat alone: 470 W -> eq speed 1.708 m/s -> 9.76 min/km. The steep
    // start makes the average effort pace faster, and its tail is still in
    // the 30 s average when the first minute ends, so the peak sits between
    // flat (470 W) and 20%-uphill (~1500 W) cost.
    var peak = f(s, "peak");
    return early == 0.0 && peak > 470.0 && peak < 1500.0 &&
      eqPace < 9.76 && eqPace > 8.5;
  }
}
