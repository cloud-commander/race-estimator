using Toybox.Lang;
using Toybox.Test;

// Unit tests (compiled only with `monkeyc -t`; stripped from app builds).
// Run: connectiq & monkeydo bin/test.prg fenix7 -t

(:test)
function testDisplayWindowAdvancesAndClampsAtEnd(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  // 5K reached: celebration keeps 5K in row 0
  m.checkAndMarkCompletions(500000.0d, 1500000, 500);
  m.rebuildDisplay();
  var d = m.getDisplayIndices();
  Test.assert(d[0] == 0);
  Test.assert(d[1] == 1);
  // Celebration over: window starts at next milestone
  m.checkAndMarkCompletions(500100.0d, 1511000, 500);
  m.rebuildDisplay();
  d = m.getDisplayIndices();
  Test.assert(d[0] == 1);
  // Everything done: last three rows still shown, none blank
  m.checkAndMarkCompletions(5000000.0d, 18000000, 500);
  m.rebuildDisplay();
  d = m.getDisplayIndices();
  Test.assert(d[0] == 6);
  Test.assert(d[1] == 7);
  Test.assert(d[2] == 8);
  Test.assert(m.isAllComplete());
  return true;
}

(:test)
function testFmOnlyRemainingKeepsThreeRows(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  m.checkAndMarkCompletions(4219500.0d, 14000000, 500); // through FM
  m.checkAndMarkCompletions(4219600.0d, 14010000, 500); // celebration ends
  m.rebuildDisplay();
  var d = m.getDisplayIndices();
  Test.assertEqual(m.getNextMilestoneIdx(), 8);
  Test.assert(d[0] != null && d[1] != null && d[2] != null);
  Test.assert(d[2] == 8);
  return true;
}

(:test)
function testTimeFormatHasSecondsOverAnHour(logger as Test.Logger) as Lang.Boolean {
  var c = new DisplayTextCache(9);
  c.setTime(7, 3 * 3600000 + 25 * 60000 + 9000);
  Test.assertEqual(c.getTime(7), "3:25:09");
  c.setTime(7, 65000);
  Test.assertEqual(c.getTime(7), "1:05");
  return true;
}

(:test)
function testPendingAndReset(logger as Test.Logger) as Lang.Boolean {
  var c = new DisplayTextCache(9);
  Test.assertEqual(c.getTime(0), "--:--");
  c.setTime(0, 1500000);
  Test.assertEqual(c.getTime(0), "25:00");
  c.setPending(0);
  Test.assertEqual(c.getTime(0), "--:--");
  c.setTime(0, 1500000);
  c.reset();
  Test.assertEqual(c.getTime(0), "--:--");
  return true;
}

(:test)
function testFocusFollowsCelebrationThenNext(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  Test.assertEqual(m.getFocusIdx(), 0);
  m.checkAndMarkCompletions(500000.0d, 1500000, 500);
  Test.assertEqual(m.getFocusIdx(), 0); // celebrating 5K
  m.checkAndMarkCompletions(500100.0d, 1511000, 500);
  Test.assertEqual(m.getFocusIdx(), 1); // next: 5 MI
  m.checkAndMarkCompletions(5000000.0d, 18000000, 500);
  m.checkAndMarkCompletions(5000100.0d, 18011000, 500);
  Test.assertEqual(m.getFocusIdx(), 8); // all done: last
  return true;
}

(:test)
function testPersistenceRoundTripWithoutThrottle(logger as Test.Logger) as Lang.Boolean {
  var p = new PersistenceManager(false);
  var times = [1500000, null, null, null, null, null, null, null, null] as Lang.Array<Lang.Number?>;
  // Two immediate saves must both succeed (no throttle)
  Test.assert(p.saveFinishTimes(times));
  times[1] = 2400000;
  Test.assert(p.saveFinishTimes(times));
  var loaded = p.loadFinishTimes(9);
  Test.assert(loaded != null);
  Test.assert((loaded as Lang.Array<Lang.Number?>)[1] == 2400000);
  p.clearStorage();
  return true;
}

(:test)
function testLateStartEstimatesSplitsWithoutCelebrating(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  // Field first sees the run at 12 km / 60 min: 5K, 5 MI, 10K were not
  // crossed live, so splits are estimated at average pace, no celebration
  m.checkAndMarkCompletions(1200000.0d, 3600000, 500);
  Test.assert(m.getMilestoneFinishTime(0) == 1500000); // 5/12 of 60 min
  Test.assert(m.getMilestoneFinishTime(2) == 3000000);
  Test.assert(!m.isCelebrating());
  Test.assertEqual(m.getNextMilestoneIdx(), 3);
  return true;
}

(:test)
function testCrossingLiveCelebratesOnce(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  m.checkAndMarkCompletions(499600.0d, 1500000, 500); // within tolerance
  Test.assert(m.isCelebrating());
  Test.assert(m.getCelebrationMilestoneIdx() == 0);
  m.checkAndMarkCompletions(505000.0d, 1509000, 500);
  Test.assert(m.isCelebrating()); // still within 10 s
  m.checkAndMarkCompletions(510000.0d, 1510000, 500);
  Test.assert(!m.isCelebrating());
  return true;
}

// Test-only helpers (class-level (:test) keeps them out of app builds
// without the runner executing them as tests)
(:test)
class PaceTestHelper {
  // Feeds a run at `secPerKm` from `fromM` to `toM`, one sample per second
  static function feedRun(
    p as PaceEstimator,
    startSec as Lang.Double,
    fromM as Lang.Double,
    toM as Lang.Double,
    secPerKm as Lang.Double
  ) as Lang.Double {
    var t = startSec;
    var d = fromM;
    var step = 1000.0d / secPerKm; // metres per second
    while (d < toM) {
      t += 1.0d;
      d += step;
      p.update(t, d);
    }
    return t;
  }

  // Steady run through the coach up to `toM`; returns every distinct
  // message in order
  static function coachRun(
    m as MilestoneManager,
    c as CoachManager,
    targetIdx as Lang.Number,
    toM as Lang.Double,
    secPerKm as Lang.Double
  ) as Lang.Array<Lang.String> {
    var p = new PaceEstimator(false);
    var targetM = m.getMilestoneDistanceCm(targetIdx) / 100.0d;
    var out = [] as Lang.Array<Lang.String>;
    var last = "";
    var t = 0.0d;
    var d = 0.0d;
    while (d < toM) {
      t += 1.0d;
      d += 1000.0d / secPerKm;
      p.update(t, d);
      m.checkAndMarkCompletions(d * 100.0d, (t * 1000.0d).toNumber(), 500);
      if (d < 100.0d || !p.isWarmedUp()) {
        continue;
      }
      var next = m.getNextMilestoneIdx();
      var nextM = m.getMilestoneDistanceCm(next) / 100.0d;
      var prevM = next > 0 ? m.getMilestoneDistanceCm(next - 1) / 100.0d : 0.0d;
      c.update(t, d, targetIdx, d / targetM, (d - prevM) / (nextM - prevM), p);
      var msg = c.getMessage();
      if (msg.length() > 0 && !msg.equals(last)) {
        out.add(msg);
        Test.assert(pixelColumns(msg) <= CoachManager.MAX_COLUMNS);
      }
      last = msg;
    }
    return out;
  }
}

(:test)
function testSteadyPaceProjectsNextMilestoneExactly(logger as Test.Logger) as Lang.Boolean {
  var p = new PaceEstimator(false);
  var t = PaceTestHelper.feedRun(p, 0.0d, 0.0d, 4000.0d, 300.0d); // 5:00/km
  // Next km at 5:00/km; fatigue ~1 for 4 km -> 5 km
  var ms = p.estimateRemainingMs(5000.0d);
  logger.debug("remaining to 5K: " + ms);
  Test.assert(ms > 295000 && ms < 310000);
  Test.assert(t > 1190.0d && t < 1210.0d);
  return true;
}

(:test)
function testSlowdownPullsProjectionUp(logger as Test.Logger) as Lang.Boolean {
  var p = new PaceEstimator(false);
  var t = PaceTestHelper.feedRun(p, 0.0d, 0.0d, 20000.0d, 300.0d); // 20 km at 5:00/km
  PaceTestHelper.feedRun(p, t, 20000.0d, 23000.0d, 420.0d); // then 3 km at 7:00/km
  var avg = p.getAveragePace() * 1000.0d; // sec/km
  var blended = p.getBlendedPace() * 1000.0d;
  logger.debug("avg " + avg + " blended " + blended);
  // Average barely moves (~5:15); blended reacts toward 7:00
  Test.assert(avg < 330.0d);
  Test.assert(blended > 360.0d && blended < 420.0d);
  return true;
}

// Even pacing below 30 km projects exactly: no early-race pessimism
(:test)
function testNoFadeBelowTheWall(logger as Test.Logger) as Lang.Boolean {
  var p = new PaceEstimator(false);
  PaceTestHelper.feedRun(p, 0.0d, 0.0d, 2000.0d, 300.0d);
  var ms = p.estimateRemainingMs(10000.0d); // 8 km at 5:00/km = 2400 s
  logger.debug("remaining to 10K at 2 km: " + ms);
  Test.assert(ms > 2380000 && ms < 2420000);
  ms = p.estimateRemainingMs(21097.5d); // half: still flat
  Test.assert(ms > 5680000 && ms < 5780000);
  return true;
}

// Past 30 km the remaining distance is costed 8% slower (the wall)
(:test)
function testWallFadeOnlyPast30k(logger as Test.Logger) as Lang.Boolean {
  var p = new PaceEstimator(false);
  PaceTestHelper.feedRun(p, 0.0d, 0.0d, 10000.0d, 300.0d);
  // 40 km at 5:00 = 12000 s, + 8% of the 20 km past 30 km = +480 s
  var ms = p.estimateRemainingMs(50000.0d);
  logger.debug("remaining to 50K: " + ms);
  Test.assert(ms > 12400000 && ms < 12560000);
  return true;
}

// A runner already fading 10% is not charged the wall fade again
(:test)
function testWallFadeNotDoubleCounted(logger as Test.Logger) as Lang.Boolean {
  var p = new PaceEstimator(false);
  var t = PaceTestHelper.feedRun(p, 0.0d, 0.0d, 32000.0d, 300.0d);
  PaceTestHelper.feedRun(p, t, 32000.0d, 35000.0d, 345.0d); // +15% for 3 km
  var blended = p.getBlendedPace();
  var ms = p.estimateRemainingMs(42195.0d);
  var flat = (42195.0d - 35000.0d) * blended * 1000.0d;
  logger.debug("remaining " + ms + " flat " + flat);
  Test.assert(ms.toDouble() < flat * 1.001d);
  return true;
}

// A climb at constant effort is not a slowdown (grade-adjusted pace)
(:test)
function testHillIsNotASlowdown(logger as Test.Logger) as Lang.Boolean {
  var p = new PaceEstimator(false);
  var t = 0.0d;
  var d = 0.0d;
  var alt = 100.0d;
  while (d < 5000.0d) {
    var up = d >= 3000.0d; // 4% climb from 3 km, same effort
    var secPerKm = up ? 300.0d * 1.12d : 300.0d;
    var step = 1000.0d / secPerKm;
    t += 1.0d;
    d += step;
    if (up) {
      alt += step * 0.04d;
    }
    p.setAltitude(alt);
    p.update(t, d);
  }
  var recent = p.getRecentPace() * 1000.0d;
  logger.debug("recent GAP " + recent + " grade " + p.getCurrentGrade());
  Test.assert(recent > 290.0d && recent < 310.0d);
  Test.assert(p.getCurrentGrade() > 0.035d && p.getCurrentGrade() < 0.045d);
  return true;
}

// Full simulated marathon through the coach: goes out too fast, settles,
// fades late, kicks at the end. Every message must fit the context line and
// the key segmentation cues must fire, without spamming.
(:test)
function testCoachMarathonScript(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  var p = new PaceEstimator(false);
  var c = new CoachManager(m, false);
  var target = 7; // marathon
  var targetM = 42195.0d;
  var seen = {} as Lang.Dictionary<Lang.String, Lang.Number>;
  var count = 0;
  var last = "";
  var t = 0.0d;
  var d = 0.0d;

  while (d < targetM + 50.0d) {
    // sec/km: 5:00, then an early surge to 4:30 at 3-6 km, 5:00 steady,
    // 5:45 fade from 30 km, 4:50 kick for the last 2 km
    var secPerKm =
      d < 3000.0d ? 300.0d
      : d < 6000.0d ? 270.0d
      : d < 30000.0d ? 300.0d
      : d < 40000.0d ? 345.0d
      : 290.0d;
    t += 1.0d;
    d += 1000.0d / secPerKm;
    p.update(t, d);
    m.checkAndMarkCompletions(d * 100.0d, (t * 1000.0d).toNumber(), 500);
    if (d < 100.0d || !p.isWarmedUp()) {
      continue;
    }
    var next = m.getNextMilestoneIdx();
    var seg = 1.0d;
    if (next < 9) {
      var nextM = m.getMilestoneDistanceCm(next) / 100.0d;
      var prevM = next > 0 ? m.getMilestoneDistanceCm(next - 1) / 100.0d : 0.0d;
      seg = (d - prevM) / (nextM - prevM);
    }
    c.update(t, d, target, d / targetM, seg, p);
    var msg = c.getMessage();
    if (msg.length() > 0 && !msg.equals(last)) {
      count++;
      seen[msg] = (t / 60).toNumber();
      logger.debug((d / 1000).format("%.1f") + " km  " + msg);
      Test.assert(pixelColumns(msg) <= CoachManager.MAX_COLUMNS);
    }
    last = msg;
  }

  Test.assert(seen.hasKey("PHASE 1: HEAD"));
  Test.assert(seen.hasKey("FIND YOUR RHYTHM"));
  Test.assert(seen.hasKey("EMPTY THE TANK"));
  Test.assert(seen.hasKey("HALF THE RACE DONE"));
  Test.assert(seen.hasKey("BOSS STAGE!"));
  Test.assert(seen.hasKey("1 KM TO MARATHON"));
  Test.assert(seen.hasKey("BOSS HP 50%"));
  Test.assert(seen.hasKey("POWER-UP: FUEL NOW"));
  Test.assert(seen.hasKey("EASY, TIGER") || seen.hasKey("TOO HOT: EASE OFF") || seen.hasKey("SAVE IT FOR LATER"));
  // ~3.5 h run: plenty of support, but not a message every minute
  // (~1 per 4 min, denser in the last third where fade cues repeat)
  logger.debug("messages: " + count);
  Test.assert(count >= 20 && count <= 52);
  return true;
}

(:test)
function testCoachComboNeedsTwoAheadSplits(logger as Test.Logger) as Lang.Boolean {
  var c = new CoachManager(new MilestoneManager(9, 3, false), false);
  c.onSplit(true);
  Test.assertEqual(c.getComboText(), "");
  c.onSplit(true);
  Test.assertEqual(c.getComboText(), "COMBO X2!");
  c.onSplit(false);
  Test.assertEqual(c.getComboText(), "");
  return true;
}

// Fading close to a milestone gets the time-boxed reframe
(:test)
function testCoachSlowingNearMilestone(logger as Test.Logger) as Lang.Boolean {
  var m = new MilestoneManager(9, 3, false);
  var p = new PaceEstimator(false);
  var c = new CoachManager(m, false);
  var t = 0.0d;
  var d = 0.0d;
  var found = "";
  while (d < 9900.0d) {
    var secPerKm = d < 7000.0d ? 300.0d : 390.0d; // fades from 7 km
    t += 1.0d;
    d += 1000.0d / secPerKm;
    p.update(t, d);
    m.checkAndMarkCompletions(d * 100.0d, (t * 1000.0d).toNumber(), 500);
    if (d < 100.0d) {
      continue;
    }
    var next = m.getNextMilestoneIdx();
    var nextM = m.getMilestoneDistanceCm(next) / 100.0d;
    var prevM = next > 0 ? m.getMilestoneDistanceCm(next - 1) / 100.0d : 0.0d;
    c.update(t, d, 7, d / 42195.0d, (d - prevM) / (nextM - prevM), p);
    var msg = c.getMessage();
    if (msg.find("ONLY ") == 0) {
      found = msg;
      logger.debug((d / 1000).format("%.2f") + " km  " + msg);
      break;
    }
  }
  // Fade starts at 7 km; the next milestone is 5 MI (8.05 km)
  Test.assert(found.find(" TO 5 MI") != null);
  return true;
}

// A uniformly fast start is invisible to the pace trend but not to a goal
(:test)
function testCoachGoalCatchesFastStart(logger as Test.Logger) as Lang.Boolean {
  var cm = new MilestoneManager(9, 3, false);
  var c = new CoachManager(cm, false);
  c.setGoalMs(50 * 60000); // 10K in 50:00 = 5:00/km
  var msgs = PaceTestHelper.coachRun(cm, c, 2, 4000.0d, 270.0d); // 4:30/km
  logger.debug(msgs.toString());
  Test.assert(msgs.indexOf("TOO FAST FOR GOAL") >= 0 || msgs.indexOf("EASE TO GOAL PACE") >= 0);
  return true;
}

(:test)
function testCoachGoalReportsBehindAndStaysQuietWithoutGoal(logger as Test.Logger) as Lang.Boolean {
  var cm = new MilestoneManager(9, 3, false);
  var c = new CoachManager(cm, false);
  c.setGoalMs(45 * 60000); // 10K in 45:00, running 5:00/km
  var behind = PaceTestHelper.coachRun(cm, c, 2, 4000.0d, 300.0d);
  logger.debug(behind.toString());
  var found = false;
  for (var i = 0; i < behind.size(); i++) {
    if (behind[i].find(" OVER GOAL") != null) {
      found = true;
    }
  }
  Test.assert(found);

  // High score as the goal: same cues, worded against the best
  var bm = new MilestoneManager(9, 3, false);
  var bc = new CoachManager(bm, false);
  bc.setGoal(45 * 60000, true);
  var best = PaceTestHelper.coachRun(bm, bc, 2, 4000.0d, 300.0d);
  logger.debug(best.toString());
  var bestFound = false;
  for (var i = 0; i < best.size(); i++) {
    Test.assert(best[i].find("GOAL") == null);
    if (best[i].find(" OVER BEST") != null) {
      bestFound = true;
    }
  }
  Test.assert(bestFound);
  var cues = ["TOO FAST FOR BEST", "EASE TO BEST PACE", "ON RECORD PACE", "HI-SCORE IN SIGHT", "RECORD IN REACH", "4:50 UNDER BEST"];
  for (var i = 0; i < cues.size(); i++) {
    Test.assert(pixelColumns(cues[i]) <= CoachManager.MAX_COLUMNS);
  }

  // No goal: no goal messages at all
  var offm = new MilestoneManager(9, 3, false);
  var off = new CoachManager(offm, false);
  var msgs = PaceTestHelper.coachRun(offm, off, 2, 4000.0d, 300.0d);
  for (var i = 0; i < msgs.size(); i++) {
    Test.assert(msgs[i].find("GOAL") == null);
  }
  return true;
}

(:test)
function testCoachFuelIntervalSetting(logger as Test.Logger) as Lang.Boolean {
  // Off: never, even on a marathon
  var cm = new MilestoneManager(9, 3, false);
  var c = new CoachManager(cm, false);
  c.setFuelInterval(0);
  Test.assert(PaceTestHelper.coachRun(cm, c, 7, 20000.0d, 300.0d).indexOf("POWER-UP: FUEL NOW") < 0);
  // Explicit interval applies to short targets too (auto would skip a 10K)
  var c2m = new MilestoneManager(9, 3, false);
  var c2 = new CoachManager(c2m, false);
  c2.setFuelInterval(20);
  Test.assert(PaceTestHelper.coachRun(c2m, c2, 2, 9000.0d, 300.0d).indexOf("POWER-UP: FUEL NOW") >= 0);
  var c3m = new MilestoneManager(9, 3, false);
  var c3 = new CoachManager(c3m, false);
  Test.assert(PaceTestHelper.coachRun(c3m, c3, 2, 9000.0d, 300.0d).indexOf("POWER-UP: FUEL NOW") < 0);
  return true;
}
