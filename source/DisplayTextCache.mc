using Toybox.Lang;

// Per-milestone cache of formatted finish-time strings.
// Each milestone's string is only re-formatted when its displayed second
// changes, so the per-second compute allocates at most a few short strings.
class DisplayTextCache {
  private const PENDING_TEXT = "--:--";
  private const PENDING_HASH = -1;

  private var mTimes as Lang.Array<Lang.String>;
  private var mHashes as Lang.Array<Lang.Number>;
  private var mCount as Lang.Number;

  function initialize(milestoneCount as Lang.Number) {
    mCount = milestoneCount;
    mTimes = new Lang.Array<Lang.String>[milestoneCount];
    mHashes = new Lang.Array<Lang.Number>[milestoneCount];
    reset();
  }

  // Store a finish time (actual or projected) for a milestone
  public function setTime(idx as Lang.Number, timeMs as Lang.Number) as Void {
    var hash = timeMs / 1000;
    if (hash != mHashes[idx]) {
      mHashes[idx] = hash;
      mTimes[idx] = formatDuration(timeMs);
    }
  }

  // No prediction available yet
  public function setPending(idx as Lang.Number) as Void {
    if (mHashes[idx] != PENDING_HASH) {
      mHashes[idx] = PENDING_HASH;
      mTimes[idx] = PENDING_TEXT;
    }
  }

  public function getTime(idx as Lang.Number) as Lang.String {
    return idx >= 0 && idx < mCount ? mTimes[idx] : PENDING_TEXT;
  }

  public function reset() as Void {
    for (var i = 0; i < mCount; i++) {
      mTimes[i] = PENDING_TEXT;
      mHashes[i] = PENDING_HASH;
    }
  }
}

// Garmin-style duration: H:MM:SS at or above an hour, M:SS below
function formatDuration(millis as Lang.Number) as Lang.String {
  var totalSec = millis / 1000;
  var hours = totalSec / 3600;
  var mins = (totalSec % 3600) / 60;
  var secs = totalSec % 60;

  if (hours > 0) {
    return Lang.format("$1$:$2$:$3$", [
      hours.format("%d"),
      mins.format("%02d"),
      secs.format("%02d"),
    ]);
  }
  return Lang.format("$1$:$2$", [mins.format("%d"), secs.format("%02d")]);
}
