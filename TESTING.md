# Testing

## Automated (simulator)

```bash
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/<sdk>/bin"
open "$SDK/ConnectIQ.app"
"$SDK/monkeyc" -f monkey.jungle -o /tmp/test.prg -y ~/.Garmin/ConnectIQ/developer_key.der -d fenix7 -t -l 3
"$SDK/monkeydo" /tmp/test.prg fenix7 -t
```

33 tests: the milestone state machine, persistence, the pace model (wall fade, grade adjustment), coach scripts (synthetic marathon, fade, hills, goal, fuel), lap sync, custom distance, high scores, indoor mode, and:

- `testReplayProjectionAccuracy`: projected marathon finish vs the real finish at each checkpoint of a recorded run.
- `testReplayThroughView`: the whole data field (compute + render) through a recorded run, then the results screen.
- `testLayoutsRenderMidRace`: attract mode and mid-race rendering in full, 1/2, 1/3, 1/4 and quarter layouts.

Verified passing on fenix7, fenix7s, fenix7x, epix2pro42mm, epix2pro47mm and fenix847mm.

### Replaying your own run

```bash
python3 tools/fit_to_replay.py path/to/activity.fit
```

This regenerates `test/ReplayData.mc`, keeping only timer time, distance and altitude (no GPS track). Raw `.fit` files are git-ignored.

The simulator can also play a FIT file through the field visually: File → Playback File... (or Simulation → FIT Data).

## On the wrist (before race day)

fenix 7 (MIP) in sunlight and in shade:
- [ ] Attract mode: arc chase, READY blinks, PRESS START legible
- [ ] Hero time and table readable at arm's length while running
- [ ] Caution messages (magenta) are distinguishable from encouragement (yellow)
- [ ] Milestone tone is audible over traffic and vibration is noticeable
- [ ] Coach vibration (warnings) is distinguishable from the milestone buzz

Layouts: add the field to 1-, 2-, 3- and 4-field data screens; nothing clipped.

Lap sync: set it on, press lap at an official km sign, see SYNC N KM; auto-lap doesn't undo it.

Results: finish the target, stop the timer, see the results screen; resume, and the normal view returns.

Treadmill: start an indoor run, no WAITING FOR GPS.

AMOLED (epix / fenix 8): always-on mode dims correctly; no static element sits in the same place for long (pixel shift).
