using Toybox.Lang;
using Toybox.Test;
using Toybox.Activity;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.Math;
using Toybox.System;
using Toybox.Application;

// Feature tests: lap sync, custom distance, high scores, indoor mode,
// hills in the coach, and full-stack replays of a real run through the view.

// ---------------------------------------------------------------- lap sync

(:test)
function testLapSyncSnapsToMarkerAndScales(logger as Test.Logger) as Lang.Boolean {
  var c = new DistanceCalibrator();
  // GPS says 10.15 km at the official 10 km sign
  var ratio = c.onLap(10150.0d, 1000.0d);
  Test.assert(ratio > 0.0d);
  Test.assert((c.apply(10150.0d) - 10000.0d).abs() < 0.5d);
  // The same 1.5% keeps being corrected: raw 20.30 km -> 20.00 km
  Test.assert((c.apply(20300.0d) - 20000.0d).abs() < 0.5d);
  return true;
}

(:test)
function testLapSyncIgnoresAutoLapAndFarLaps(logger as Test.Logger) as Lang.Boolean {
  var c = new DistanceCalibrator();
  c.onLap(10150.0d, 1000.0d);
  var scale = c.getScale();
  // Auto-lap fires at whole raw km: must not undo the sync
  Test.assertEqual(c.onLap(11000.0d, 1000.0d), 0.0d);
  Test.assertEqual(c.getScale(), scale);
  // Lap mid-kilometre (interval, drink): not near a marker
  Test.assertEqual(c.onLap(12650.0d, 1000.0d), 0.0d);
  Test.assertEqual(c.getScale(), scale);
  return true;
}

(:test)
function testLapSyncMiles(logger as Test.Logger) as Lang.Boolean {
  var c = new DistanceCalibrator();
  var mile = 1609.344d;
  Test.assert(c.onLap(5 * mile + 60.0d, mile) > 0.0d);
  Test.assert((c.apply(5 * mile + 60.0d) - 5 * mile).abs() < 0.5d);
  return true;
}

// ---------------------------------------------------------- custom distance

(:test)
function testCustomDistanceInsertedInOrder(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  m.checkAndMarkCompletions(500000.0d, 1500000, 500); // 5K done
  m.configure(1500000); // 15K
  Test.assertEqual(m.getMilestoneCount(), 10);
  Test.assertEqual(m.getMilestoneLabel(4), "15K");
  Test.assertEqual(m.indexOfDistance(1500000), 4);
  Test.assertEqual(m.getMilestoneLabel(5), "10 MI");
  Test.assert(m.getMilestoneFinishTime(0) == 1500000); // kept
  // Back to standard: 5K still recorded
  m.configure(0);
  Test.assertEqual(m.getMilestoneCount(), 9);
  Test.assert(m.getMilestoneFinishTime(0) == 1500000);
  return true;
}

(:test)
function testCustomDistanceLabelsAndDedupe(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  m.configure(4220000); // 42.2 km = the marathon
  Test.assertEqual(m.getMilestoneCount(), 9);
  Test.assertEqual(m.indexOfDistance(4220000), 7);
  m.configure(10000000); // 100 km ultra: appended
  Test.assertEqual(m.getMilestoneCount(), 10);
  Test.assertEqual(m.getMilestoneLabel(9), "100K");
  m.configure(1550000);
  Test.assertEqual(m.getMilestoneLabel(4), "15.5K");
  return true;
}

// Auto fuel follows the target distance, not its index
(:test)
function testFuelAutoUsesDistanceWithCustomTarget(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  m.configure(3000000); // 30K target, inserted before the marathon
  var c = new CoachManager(m, false);
  var idx = m.indexOfDistance(3000000);
  var msgs = PaceTestHelper.coachRun(m, c, idx, 16000.0d, 300.0d); // 80 min
  Test.assert(msgs.indexOf("POWER-UP: FUEL NOW") >= 0);
  return true;
}

// -------------------------------------------------------------- high scores

(:test)
function testHighScoresKeepBestAndGhost(logger as Test.Logger) as Lang.Boolean {
  var h = new HighScores(false);
  Test.assert(h.getBest(500000) == null);
  Test.assert(h.record(500000, 1500000)); // first time
  Test.assert(!h.record(500000, 1600000)); // slower
  Test.assert(h.record(500000, 1450000)); // faster
  Test.assert(h.getBest(500000) == 1450000);

  var splits = { 500000 => 1450000, 1000000 => 2950000 } as Lang.Dictionary<Lang.Number, Lang.Number>;
  h.setGhost(1000000, splits);
  Test.assert(h.getGhost(1000000, 500000) == 1450000);
  Test.assert(h.getGhost(4219500, 500000) == null); // other target: no ghost
  h.clear();
  Test.assert(h.getBest(500000) == null);
  return true;
}

// ------------------------------------------------------------------ indoor

(:test)
function testIndoorSkipsGpsGate(logger as Test.Logger) as Lang.Boolean {
  var v = new ActivityDataValidator(100, false);
  Test.assert(!v.validateAccuracy(Position.QUALITY_POOR));
  Test.assert(!v.validateAccuracy(Position.QUALITY_LAST_KNOWN));
  Test.assert(v.validateAccuracy(Position.QUALITY_GOOD));
  v.setIndoor(true);
  Test.assert(v.validateAccuracy(Position.QUALITY_LAST_KNOWN));
  return true;
}

// ------------------------------------------------------------ coach: hills

(:test)
function testCoachHillCueAndNoFadeOnClimb(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  var p = new PaceEstimator(false);
  var c = new CoachManager(m, false);
  var t = 0.0d;
  var d = 0.0d;
  var alt = 50.0d;
  var sawHill = false;
  while (d < 7500.0d) {
    // 5:00 flat; 5.5% climb from 5.0-6.5 km at a much slower pace
    var up = d >= 5000.0d && d < 6500.0d;
    var secPerKm = up ? 380.0d : 300.0d;
    var step = 1000.0d / secPerKm;
    t += 1.0d;
    d += step;
    if (up) {
      alt += step * 0.055d;
    }
    p.setAltitude(alt);
    p.update(t, d);
    m.checkAndMarkCompletions(d * 100.0d, (t * 1000.0d).toNumber(), 500);
    if (d < 100.0d || !p.isWarmedUp()) {
      continue;
    }
    var next = m.getNextMilestoneIdx();
    var nextM = m.getMilestoneDistanceCm(next) / 100.0d;
    var prevM = next > 0 ? m.getMilestoneDistanceCm(next - 1) / 100.0d : 0.0d;
    c.update(t, d, 2, d / 10000.0d, (d - prevM) / (nextM - prevM), p);
    var msg = c.getMessage();
    if (msg.length() == 0) {
      continue;
    }
    if (up) {
      logger.debug((d / 1000).format("%.2f") + " km  " + msg);
      if (msg.find("HILL") != null || msg.find("CLIMB") != null || msg.find("EFFORT") != null) {
        sawHill = true;
      }
      // Slower on a climb is correct: no fading cues
      Test.assert(msg.find("ONLY ") == null);
      Test.assert(!msg.equals("RELAX, STAY SMOOTH") && !msg.equals("FIND YOUR FEET"));
    }
  }
  Test.assert(sawHill);
  return true;
}

// ------------------------------------------------------------------ replay

(:test)
class ReplayHelper {
  private static var sTime as Lang.Array<Lang.Number>? = null;
  private static var sDist as Lang.Array<Lang.Number>? = null;
  private static var sAlt as Lang.Array<Lang.Number>? = null;

  // Parses the packed fixture once
  static function load() as Void {
    if (sTime == null) {
      sTime = parse(ReplayData.TIMER_SEC);
      sDist = parse(ReplayData.DISTANCE_DM);
      sAlt = parse(ReplayData.ALTITUDE_DM);
    }
  }

  private static function parse(text as Lang.String) as Lang.Array<Lang.Number> {
    var out = [] as Lang.Array<Lang.Number>;
    var chars = text.toCharArray();
    var value = 0;
    var negative = false;
    var inNumber = false;
    for (var i = 0; i <= chars.size(); i++) {
      var c = i < chars.size() ? chars[i] : ' ';
      if (c == '-') {
        negative = true;
      } else if (c >= '0' && c <= '9') {
        value = value * 10 + (c.toNumber() - 48);
        inNumber = true;
      } else if (inNumber) {
        out.add(negative ? -value : value);
        value = 0;
        negative = false;
        inNumber = false;
      }
    }
    return out;
  }

  static function size() as Lang.Number {
    load();
    return (sTime as Lang.Array<Lang.Number>).size();
  }

  static function timeSec(i as Lang.Number) as Lang.Double {
    load();
    return (sTime as Lang.Array<Lang.Number>)[i].toDouble();
  }

  static function distM(i as Lang.Number) as Lang.Double {
    load();
    return (sDist as Lang.Array<Lang.Number>)[i] / 10.0d;
  }

  static function altM(i as Lang.Number) as Lang.Double {
    load();
    return (sAlt as Lang.Array<Lang.Number>)[i] / 10.0d;
  }

  // Activity.Info for replay sample i (timer running, good GPS)
  static function info(i as Lang.Number, scale as Lang.Double) as Activity.Info {
    var info = new Activity.Info();
    info.timerTime = (timeSec(i) * 1000).toNumber();
    info.elapsedDistance = (distM(i) * scale).toFloat();
    info.altitude = altM(i).toFloat();
    info.timerState = Activity.TIMER_STATE_ON;
    info.currentLocationAccuracy = Position.QUALITY_GOOD;
    return info;
  }

  // Timer seconds when the replay first reaches distanceM (interpolated)
  static function timeAt(distanceM as Lang.Double) as Lang.Double {
    var n = size();
    for (var i = 1; i < n; i++) {
      var d1 = distM(i);
      if (d1 >= distanceM) {
        var d0 = distM(i - 1);
        var t0 = timeSec(i - 1);
        var t1 = timeSec(i);
        return t0 + (t1 - t0) * (distanceM - d0) / (d1 - d0);
      }
    }
    return -1.0d;
  }
}

// The real marathon through the pace model: how far off is the projected
// finish at each checkpoint? (Old Riegel model logged for comparison.)
(:test)
function testReplayProjectionAccuracy(logger as Test.Logger) as Lang.Boolean {
  var p = new PaceEstimator(false);
  var target = 42195.0d;
  var actual = ReplayHelper.timeAt(target);
  var checkpoints = [5000.0d, 10000.0d, 21097.5d, 30000.0d, 35000.0d, 40000.0d];
  // Allowed error (fraction of the finish) at each checkpoint
  var limits = [0.12d, 0.10d, 0.08d, 0.06d, 0.04d, 0.015d];
  var next = 0;
  var n = ReplayHelper.size();
  for (var i = 0; i < n && next < checkpoints.size(); i++) {
    var d = ReplayHelper.distM(i);
    var t = ReplayHelper.timeSec(i);
    p.setAltitude(ReplayHelper.altM(i));
    p.update(t, d);
    if (d < checkpoints[next]) {
      continue;
    }
    var projected = t + p.estimateRemainingMs(target) / 1000.0d;
    var from = d > 3000.0d ? d : 3000.0d;
    var riegel =
      t + (target - d) * p.getBlendedPace() * Math.pow(target / from, 0.06).toDouble();
    var err = (projected - actual) / actual;
    logger.debug(
      (d / 1000).format("%5.1f") + " km  new " + formatDuration((projected * 1000).toNumber()) +
        " (" + (err * 100).format("%+.1f") + "%)  old " + formatDuration((riegel * 1000).toNumber()) +
        " (" + ((riegel - actual) / actual * 100).format("%+.1f") + "%)  actual " +
        formatDuration((actual * 1000).toNumber())
    );
    Test.assert(err.abs() <= limits[next]);
    next++;
  }
  Test.assertEqual(next, checkpoints.size());
  return true;
}

// The real marathon through the whole data field (compute + render every
// minute), then the results screen once the timer stops
(:test)
function testReplayThroughView(logger as Test.Logger) as Lang.Boolean {
  var v = new RaceEstimatorView();
  var bitmap = Graphics.createBufferedBitmap({ :width => 260, :height => 260 }).get() as Graphics.BufferedBitmap;
  var dc = bitmap.getDc();
  v.onLayout(dc);
  var n = ReplayHelper.size();
  var last = "";
  var messages = 0;
  for (var i = 0; i < n; i++) {
    v.compute(ReplayHelper.info(i, 1.0d));
    var sub = v.getSubText();
    if (!sub.equals(last)) {
      last = sub;
      // Skip the live "2.31 KM IN 11:04" / "0.40 MI TO GO" line
      var live = sub.find(".") != null && (sub.find(" KM ") != null || sub.find(" MI ") != null);
      if (!live) {
        messages++;
        logger.debug((ReplayHelper.distM(i) / 1000).format("%.2f") + " km  " + sub);
      }
      Test.assert(pixelColumns(sub) <= CoachManager.MAX_COLUMNS);
    }
    if (i % 60 == 0) {
      v.onUpdate(dc);
    }
  }
  Test.assert(v.getSubText().find("SAFE MODE") == null);
  logger.debug("context-line changes: " + messages);

  // Stop the timer after the finish: results screen
  var info = ReplayHelper.info(n - 1, 1.0d);
  info.timerState = Activity.TIMER_STATE_STOPPED;
  v.compute(info);
  Test.assert(v.isShowingResults());
  v.onUpdate(dc);
  return true;
}

// Every layout the field can be given, on this device, mid-race
(:test)
function testLayoutsRenderMidRace(logger as Test.Logger) as Lang.Boolean {
  var w = System.getDeviceSettings().screenWidth;
  var h = System.getDeviceSettings().screenHeight;
  // full, 2-field half, 3-field middle band, 4-field quarter, 1/3 top
  var sizes = [[w, h], [w, h / 2], [w, h / 3], [w / 2, h / 2], [w, h / 4]];
  for (var s = 0; s < sizes.size(); s++) {
    var v = new RaceEstimatorView();
    var bitmap = Graphics.createBufferedBitmap({ :width => sizes[s][0], :height => sizes[s][1] }).get() as Graphics.BufferedBitmap;
    var dc = bitmap.getDc();
    v.onLayout(dc);
    v.onUpdate(dc); // attract mode (timer not started)
    for (var i = 0; i < 1300; i += 5) { // ~10 km
      v.compute(ReplayHelper.info(i, 1.0d));
    }
    v.onUpdate(dc);
    logger.debug(sizes[s][0] + "x" + sizes[s][1] + " ok: " + v.getSubText());
    Test.assert(v.getSubText().find("SAFE MODE") == null);
  }
  return true;
}

// Settings -> view: custom target distance and lap sync, end to end
(:test)
function testViewCustomTargetAndLapSync(logger as Test.Logger) as Lang.Boolean {
  var keys = ["targetRace", "customDistanceKm", "lapSync"];
  var saved = [] as Lang.Array<Application.PropertyValueType>;
  for (var k = 0; k < keys.size(); k++) {
    saved.add(Application.Properties.getValue(keys[k]));
  }
  try {
    Application.Properties.setValue("targetRace", 9);
    Application.Properties.setValue("customDistanceKm", 30.0f);
    Application.Properties.setValue("lapSync", true);
    var v = new RaceEstimatorView();
    // 30K sits between 26.2K (idx 6) and the marathon
    Test.assertEqual(v.getTargetIdx(), 7);

    // Run to 1.5% past the 4th km / mile marker (GPS long), then lap
    var unit = System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE ? 1609.344d : 1000.0d;
    var lapAt = 4 * unit * 1.015d;
    var i = 0;
    while (ReplayHelper.distM(i) < lapAt) {
      v.compute(ReplayHelper.info(i, 1.0d));
      i++;
    }
    v.onTimerLap();
    v.compute(ReplayHelper.info(i, 1.0d));
    logger.debug("after lap: " + v.getSubText());
    Test.assert(v.getSubText().find("SYNC ") == 0);
  } finally {
    for (var k = 0; k < keys.size(); k++) {
      Application.Properties.setValue(keys[k], saved[k]);
    }
  }
  return true;
}

// Goal setting -> finish: the real 4:55:07 marathon against a 5:00 goal
// gets GOAL CLEAR!, the margin and praise; against 4:50 it is a near miss
(:test)
function testGoalPraiseAtFinish(logger as Test.Logger) as Lang.Boolean {
  var keys = ["targetRace", "goalHours", "goalMinutes"];
  var saved = [] as Lang.Array<Application.PropertyValueType>;
  for (var k = 0; k < keys.size(); k++) {
    saved.add(Application.Properties.getValue(keys[k]));
  }
  try {
    Application.Properties.setValue("targetRace", 7); // marathon
    Application.Properties.setValue("goalHours", 5);
    Application.Properties.setValue("goalMinutes", 0);
    var beat = FinishHelper.framesFor(new RaceEstimatorView());
    logger.debug("goal 5:00 -> " + beat.toString());
    Test.assert(beat[0].equals("GOAL CLEAR!"));
    Test.assert(beat[1].find(" UNDER GOAL") != null);
    Test.assert(beat.size() >= 4);
    Test.assert(beat.indexOf("GAME OVER") < 0);

    Application.Properties.setValue("goalMinutes", 50);
    Application.Properties.setValue("goalHours", 4);
    var miss = FinishHelper.framesFor(new RaceEstimatorView());
    logger.debug("goal 4:50 -> " + miss.toString());
    Test.assert(miss[0].find(" OVER GOAL") != null);
    Test.assert(miss.indexOf("SO CLOSE!") >= 0);
    Test.assert(miss.indexOf("GOAL CLEAR!") < 0);

    for (var i = 0; i < beat.size(); i++) {
      Test.assert(pixelColumns(beat[i]) <= CoachManager.MAX_COLUMNS);
    }
  } finally {
    for (var k = 0; k < keys.size(); k++) {
      Application.Properties.setValue(keys[k], saved[k]);
    }
  }
  return true;
}

// Replays the marathon through a fresh view, stops the timer and returns
// the results screen frames
(:test)
class FinishHelper {
static function framesFor(v as RaceEstimatorView) as Lang.Array<Lang.String> {
  var n = ReplayHelper.size();
  for (var i = 0; i < n; i++) {
    v.compute(ReplayHelper.info(i, 1.0d));
  }
  var info = ReplayHelper.info(n - 1, 1.0d);
  info.timerState = Activity.TIMER_STATE_STOPPED;
  v.compute(info);
  Test.assert(v.isShowingResults());
  return v.getResultFrames();
}
}

// No goal set: the high score for the target is the goal. Beating it
// reads NEW HIGH SCORE! (once) with the margin UNDER BEST and praise; the
// next run races the new best.
(:test)
function testHighScoreIsGoalWhenNoneSet(logger as Test.Logger) as Lang.Boolean {
  var saved = GoalProps.save(0, 0);
  try {
    var v = new RaceEstimatorView();
    Test.assert(!v.isGoalFromBest());
    v.recordHighScoreForTest(4219500, 5 * 3600000);
    Test.assert(v.isGoalFromBest());
    Test.assertEqual(v.getGoalMs(), 5 * 3600000);
    var beat = FinishHelper.framesFor(v);
    logger.debug("best 5:00 -> " + beat.toString());
    Test.assert(beat[0].equals("NEW HIGH SCORE!"));
    Test.assert(beat[1].find(" UNDER BEST") != null);
    Test.assert(beat.indexOf("GOAL CLEAR!") < 0);
    Test.assert(beat.slice(1, null).indexOf("NEW HIGH SCORE!") < 0);
    // Next run races the new best (this run's finish)
    v.onTimerReset();
    Test.assert(v.isGoalFromBest());
    Test.assert(v.getGoalMs() < 5 * 3600000);
  } finally {
    GoalProps.restore(saved);
  }
  return true;
}

// Just missing the best is SO CLOSE!; a goal time set wins over the best
(:test)
function testHighScoreGoalNearMissAndOverride(logger as Test.Logger) as Lang.Boolean {
  var saved = GoalProps.save(0, 0);
  try {
    var w = new RaceEstimatorView();
    w.recordHighScoreForTest(4219500, 4 * 3600000 + 50 * 60000);
    var miss = FinishHelper.framesFor(w);
    logger.debug("best 4:50 -> " + miss.toString());
    Test.assert(miss[0].find(" OVER BEST") != null);
    Test.assert(miss.indexOf("SO CLOSE!") >= 0);
    Test.assert(miss.indexOf("GAME OVER") >= 0);
    Application.Properties.setValue("goalHours", 4);
    w.loadSettings();
    Test.assert(!w.isGoalFromBest());
    Test.assertEqual(w.getGoalMs(), 4 * 3600000);
  } finally {
    GoalProps.restore(saved);
  }
  return true;
}

// Marathon target with the given goal; save() returns the old values
(:test)
class GoalProps {
static const KEYS = ["targetRace", "goalHours", "goalMinutes"];

static function save(hours as Lang.Number, minutes as Lang.Number) as Lang.Array {
  var saved = [];
  for (var k = 0; k < KEYS.size(); k++) {
    saved.add(Application.Properties.getValue(KEYS[k]));
  }
  Application.Properties.setValue("targetRace", 7);
  Application.Properties.setValue("goalHours", hours);
  Application.Properties.setValue("goalMinutes", minutes);
  return saved;
}

static function restore(saved as Lang.Array) as Void {
  for (var k = 0; k < KEYS.size(); k++) {
    Application.Properties.setValue(KEYS[k], saved[k] as Application.PropertyValueType);
  }
}
}

// Target 10K but the run keeps going: every milestone past it is a bonus
// stage with extra praise, and the results screen counts them
(:test)
function testBonusStagesPastTarget(logger as Test.Logger) as Lang.Boolean {
  var saved = Application.Properties.getValue("targetRace");
  try {
    Application.Properties.setValue("targetRace", 2); // 10K
    var v = new RaceEstimatorView();
    Test.assertEqual(v.getTargetIdx(), 2);
    var bonusSeen = 0;
    var lastFrames = null;
    var i = 0;
    while (ReplayHelper.distM(i) < 21300.0d) {
      v.compute(ReplayHelper.info(i, 1.0d));
      var f = v.getCelebFrames();
      if (f != lastFrames && f.size() > 0) {
        lastFrames = f;
        logger.debug((ReplayHelper.distM(i) / 1000).format("%.2f") + " km  " + f.toString());
        for (var k = 0; k < f.size(); k++) {
          Test.assert(pixelColumns(f[k]) <= CoachManager.MAX_COLUMNS);
          if (f[k].find("BONUS X") == 0) {
            bonusSeen++;
          }
        }
      }
      i++;
    }
    // 10 mi (or 15K) and the half at least
    Test.assert(bonusSeen >= 2);
    var info = ReplayHelper.info(i, 1.0d);
    info.timerState = Activity.TIMER_STATE_STOPPED;
    v.compute(info);
    var r = v.getResultFrames();
    logger.debug("results " + r.toString());
    Test.assert(r[0].find("BONUS STAGES X") == 0);
    Test.assert(r.indexOf("GAME OVER") < 0);
  } finally {
    Application.Properties.setValue("targetRace", saved);
  }
  return true;
}
