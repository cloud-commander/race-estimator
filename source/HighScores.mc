using Toybox.Lang;
using Toybox.Application;
using Toybox.Application.Storage;

// Arcade high-score table: best time per milestone distance, plus the
// splits of the run that set the best time for the target race (the
// "ghost" you race next time).
//
// Keyed by distance in cm, so a custom milestone or a different target
// doesn't shuffle the table. Only milestones crossed live count (catch-up
// estimates don't). Saved on change only (a few times per run).
class HighScores {
  private const KEY_BESTS = "hiScores";
  private const KEY_GHOST = "ghostSplits";
  private const KEY_GHOST_TARGET = "ghostTarget";

  private var mBests as Lang.Dictionary<Lang.Number, Lang.Number>;
  private var mGhost as Lang.Dictionary<Lang.Number, Lang.Number>;
  private var mGhostTargetCm as Lang.Number = 0;
  private var mPersist as Lang.Boolean;

  function initialize(persist as Lang.Boolean) {
    mPersist = persist;
    mBests = {} as Lang.Dictionary<Lang.Number, Lang.Number>;
    mGhost = {} as Lang.Dictionary<Lang.Number, Lang.Number>;
    if (persist) {
      load();
    }
  }

  public function getBest(distanceCm as Lang.Number) as Lang.Number? {
    return mBests.get(distanceCm);
  }

  /**
   * A milestone was crossed live at timeMs
   * @return true if it is a new high score (a first time also counts, but
   *         see isFirst to tell the two apart)
   */
  public function record(distanceCm as Lang.Number, timeMs as Lang.Number) as Lang.Boolean {
    var best = mBests.get(distanceCm);
    if (best != null && best <= timeMs) {
      return false;
    }
    mBests.put(distanceCm, timeMs);
    save();
    return true;
  }

  /**
   * The target race was finished as a new high score: keep this run's
   * splits (distance cm -> ms) as the ghost for that target
   */
  public function setGhost(
    targetCm as Lang.Number,
    splits as Lang.Dictionary<Lang.Number, Lang.Number>
  ) as Void {
    mGhostTargetCm = targetCm;
    mGhost = splits;
    save();
  }

  // Ghost split at distanceCm when racing targetCm, or null
  public function getGhost(
    targetCm as Lang.Number,
    distanceCm as Lang.Number
  ) as Lang.Number? {
    if (targetCm != mGhostTargetCm) {
      return null;
    }
    return mGhost.get(distanceCm);
  }

  public function clear() as Void {
    mBests = {} as Lang.Dictionary<Lang.Number, Lang.Number>;
    mGhost = {} as Lang.Dictionary<Lang.Number, Lang.Number>;
    mGhostTargetCm = 0;
    save();
  }

  private function save() as Void {
    if (!mPersist) {
      return;
    }
    try {
      Storage.setValue(KEY_BESTS, mBests as Lang.Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);
      Storage.setValue(KEY_GHOST, mGhost as Lang.Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);
      Storage.setValue(KEY_GHOST_TARGET, mGhostTargetCm);
    } catch (ex) {
      // Storage full or unavailable: the table is a nicety, keep running
    }
  }

  private function load() as Void {
    try {
      mBests = readTable(Storage.getValue(KEY_BESTS));
      mGhost = readTable(Storage.getValue(KEY_GHOST));
      var target = Storage.getValue(KEY_GHOST_TARGET);
      mGhostTargetCm = target instanceof Lang.Number ? target : 0;
    } catch (ex) {
      mBests = {} as Lang.Dictionary<Lang.Number, Lang.Number>;
      mGhost = {} as Lang.Dictionary<Lang.Number, Lang.Number>;
      mGhostTargetCm = 0;
    }
  }

  // Keeps only well-formed positive entries
  private function readTable(
    value as Application.PropertyValueType?
  ) as Lang.Dictionary<Lang.Number, Lang.Number> {
    var out = {} as Lang.Dictionary<Lang.Number, Lang.Number>;
    if (!(value instanceof Lang.Dictionary)) {
      return out;
    }
    var keys = value.keys();
    for (var i = 0; i < keys.size(); i++) {
      var k = keys[i];
      var v = value.get(k);
      if (k instanceof Lang.Number && v instanceof Lang.Number && v > 0) {
        out.put(k, v);
      }
    }
    return out;
  }
}
