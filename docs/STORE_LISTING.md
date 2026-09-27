# Connect IQ Store listing (draft)

**Name:** Race Estimator

**Type:** Data field

**Short description:** Projected race finish times with an 80s arcade level map, coach and high scores.

**Description:**

Race Estimator shows when you will reach every standard race distance (5K, 5 mi, 10K, half, marathon, 50K, or your own custom distance) while you run.

- Projected finish from your recent, grade-adjusted pace, so hills don't throw it off
- An 80s arcade level map of your target race: race thirds, milestones, and a boss stage
- A coach that segments the race: next goal, time to it, halfway, boss HP, fuel reminders, hill and pace cues
- Goal time: see whether you are over or under, and get warned when you go out too fast
- High scores and a ghost of your best race
- Stage clear fanfare, split scoring, combos and a results screen
- Lap button sync to course markers corrects GPS distance
- Projected finish charted in Garmin Connect
- Battery-aware: 1 Hz redraw, dark pixels on AMOLED, pixel shift

**Devices:** fenix 7 / 7S / 7X (and Pro), fenix 8 (AMOLED and Solar), epix Gen 2, epix Pro Gen 2 (42/47mm).

**Permissions:** FitContributor (writes projected finish to the activity).

**Privacy:** No data leaves the watch except the FIT fields in your own activity. High scores are stored on the watch.

## Still needed before submission

- [ ] Screenshots per display family (fenix 7 MIP 260/280, epix/fenix 8 AMOLED 416/454): use the simulator's File → Save Screenshot during a FIT playback
- [ ] Hero image (1440x720) and store icon
- [ ] fenix 9: install the device in SDK Manager, add it to manifest.xml, and build
- [ ] Real-device test pass (TESTING.md)
