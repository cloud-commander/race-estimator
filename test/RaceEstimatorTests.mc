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

(:test)
function testRiegelFatigueOnlyForFarMilestones(logger as Test.Logger) as Lang.Boolean {
  var p = new PaceEstimator(false);
  PaceTestHelper.feedRun(p, 0.0d, 0.0d, 10000.0d, 300.0d);
  // 40 km left at 5:00/km = 12000 s flat; Riegel (50/10)^0.06 ~ 1.101
  var ms = p.estimateRemainingMs(50000.0d);
  logger.debug("remaining to 50K: " + ms);
  Test.assert(ms > 13000000 && ms < 13400000);
  return true;
}
