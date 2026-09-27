using Toybox.Activity;
using Toybox.Application;
using Toybox.FitContributor;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.UserProfile;
using Toybox.WatchUi;

//! Load-adjusted ruck metrics. Add to a copied Hike/Walk activity profile.
//!
//! 80s look, one theme per screen technology, cheap on battery either way:
//! - AMOLED (fenix 8, epix): green-phosphor CRT. Black background, dot-matrix
//!   font with gaps between the dots, mostly green (the most efficient OLED
//!   subpixel), dim labels and outline-only empty bar segments, so few
//!   pixels are lit.
//! - MIP (fenix 7, fenix 8 Solar): LCD handheld (Game & Watch / Game Boy).
//!   Follows the activity's black or white background with full-contrast ink
//!   and solid glyphs; colour only for load warnings, in pure MIP colours.
//! Animation runs on the normal ~1 Hz data field update only (no timers),
//! so it costs no extra wake-ups: before the activity starts the full-screen
//! field plays an arcade "attract mode" (marching rucker on a scrolling
//! ground line, pack bar loading, hi-score, blinking PRESS START); pressing
//! start shows READY then GO! for one update each.
//!
//! Full screen: walking rucker sprite, no-pack pace, calories, load x distance
//! and a segmented pack-load energy bar. Half screen: pace and calories side
//! by side plus the bar. Small fields: the metric chosen in settings.
class RuckView extends WatchUi.DataField {
  (:debug)
  private const DEBUG_LOGGING = true;
  (:release)
  private const DEBUG_LOGGING = false;

  private const DEFAULT_BODY_KG = 75.0;
  private const KG_PER_LB = 0.45359237;
  private const METERS_PER_KM = 1000.0;
  private const METERS_PER_MILE = 1609.344;

  // Grade is measured over this much horizontal distance, then smoothed
  private const GRADE_WINDOW_M = 25.0;
  private const GRADE_MAX_PCT = 45.0;
  private const GRADE_ALPHA = 0.5;
  private const SPEED_ALPHA = 0.3;
  private const MIN_MOVING_SPEED = 0.5; // m/s; slower than this shows "--:--"
  // Pandolf/Santee are walking models (validated below ~2 m/s). Cap GPS
  // speed spikes so one bad fix can't inflate calories through the V^2 term.
  private const MAX_SPEED = 3.0;
  private const MAX_PACE_SEC = 3599;
  private const MAX_STEP_MS = 5000; // larger timer jumps are gaps, not effort

  private const STORAGE_KEY = "ruck";
  private const HI_KEY = "ruckHi"; // best ruck calories, kept across rucks
  private const STORAGE_VERSION = 2;
  private const SAVE_INTERVAL_MS = 30000;

  private const LARGE_FIELD_HEIGHT_PCT = 0.45;
  private const LARGE_FIELD_WIDTH_PCT = 0.6;
  private const FULLSCREEN_PCT = 0.9;

  // AMOLED burn-in protection: nudge all content around a small square once
  // a minute so no pixel stays lit in the same place for a whole ruck
  private const SHIFT_INTERVAL = 60; // updates (~1 s each)
  private const SHIFT_X = [0, 2, 2, -2, -2] as Lang.Array<Lang.Number>;
  private const SHIFT_Y = [0, 2, -2, -2, 2] as Lang.Array<Lang.Number>;

  // AMOLED phosphor palette (channels 00/55/AA/FF, exact MIP colours too)
  private const P_BRIGHT = 0x00ff00;
  private const P_DIM = 0x00aa00;
  private const P_DARK = 0x005500;
  private const P_AMBER = 0xffaa00;
  private const P_RED = 0xff5555;
  // MIP warning colours: pure primaries read best on a reflective screen
  private const M_ORANGE = 0xff5500;
  private const M_RED = 0xff0000;

  // Walking rucker, facing right with the pack on his back.
  // G = body (ink), A = pack (accent). Frame 1 doubles as "standing".
  private const SPRITE_W = 10;
  private const SPRITE_H = 12;
  private const SPRITE_FRAMES = [
    [
      ".....GG...",
      ".....GG...",
      "..AA.G....",
      ".AAAGGG...",
      ".AAAGGGG..",
      ".AAAGG..G.",
      "..AAGG....",
      "....GG....",
      "...G..G...",
      "...G...G..",
      "..G....G..",
      "..G.....G.",
    ],
    [
      ".....GG...",
      ".....GG...",
      "..AA.G....",
      ".AAAGGG...",
      ".AAAGGG...",
      ".AAAGGG...",
      "..AAGG....",
      "....GG....",
      "....GG....",
      "....G.G...",
      "....G.G...",
      "...GG.GG..",
    ],
  ] as Lang.Array<Lang.Array<Lang.String> >;

  // Pack-load energy bar
  private const BAR_SEGMENTS = 10;
  // Full bar = 125% of the warning threshold, so the threshold falls exactly
  // on the boundary after block 8 and blocks 9-10 are the "over" zone
  private const BAR_MAX_OF_WARN = 1.25;
  private const BAR_GREEN_OF_WARN = 0.67; // "ok" colour below 2/3 of threshold

  // Start screen: pack bar loads this many blocks per update; the ground
  // dash pattern repeats every GROUND_STEPS updates so it reads as motion
  private const LOAD_BLOCKS_PER_TICK = 2;
  private const GROUND_STEPS = 4;
  private const INTRO_FRAMES = 2; // READY, GO!

  private const MODE_SINGLE = 0;
  private const MODE_DUO = 1;
  private const MODE_FULL = 2;

  private const METRIC_EQ_PACE = 0;
  private const METRIC_KCAL = 1;
  private const METRIC_LOAD_DIST = 2;
  private const METRIC_LOAD_PCT = 3;

  // Settings
  private var mLoadKg as Lang.Float = 0.0;
  private var mBodyKg as Lang.Float = DEFAULT_BODY_KG;
  private var mEta as Lang.Float = 1.0;
  private var mWarnPct as Lang.Number = 30;
  private var mCompactMetric as Lang.Number = METRIC_EQ_PACE;
  private var mImperialWeight as Lang.Boolean = false;
  private var mStatuteDistance as Lang.Boolean = false;

  // Live state
  private var mSpeed as Lang.Float = 0.0;
  private var mGradePct as Lang.Float = 0.0;
  private var mMetabolicW as Lang.Float = 0.0;
  private var mKcal as Lang.Float = 0.0;
  private var mLoadKgM as Lang.Float = 0.0; // pack kg x metres
  private var mLastTimerMs as Lang.Number? = null;
  private var mLastDistM as Lang.Float? = null;
  private var mGradeAnchorDist as Lang.Float? = null;
  private var mGradeAnchorAlt as Lang.Float? = null;
  private var mRestoreChecked as Lang.Boolean = false;
  private var mStartTime as Lang.Number? = null;
  private var mLastSaveMs as Lang.Number = 0;

  // Session summary accumulators (end-of-activity stats in Garmin Connect)
  private var mMovingMs as Lang.Number = 0;
  private var mEqDistM as Lang.Float = 0.0; // no-pack-equivalent distance
  private var mSlowW as Lang.Float = 0.0; // ~30 s average metabolic rate
  private var mPeakW as Lang.Float = 0.0;
  private var mLapKcal as Lang.Float = 0.0;

  // FIT recording (shows up in Garmin Connect)
  private var mFitPower as FitContributor.Field?;
  private var mFitKcal as FitContributor.Field?;
  private var mFitPack as FitContributor.Field?;
  private var mFitLoadKm as FitContributor.Field?;
  private var mFitAvgPace as FitContributor.Field?;
  private var mFitAvgBurn as FitContributor.Field?;
  private var mFitPeakBurn as FitContributor.Field?;
  private var mFitLapKcal as FitContributor.Field?;

  // Display text, formatted once per compute() so onUpdate() only draws
  private var mLabels as Lang.Array<Lang.String> = ["", "", "", ""];
  private var mValues as Lang.Array<Lang.String> = ["--:--", "0", "0.0", "0%"];
  private var mPaceShortLabel as Lang.String = "";
  private var mUseShortLabel as Lang.Boolean = false;
  private var mRateText as Lang.String = "";
  private var mRateSuffix as Lang.String = "";
  private var mLoadUnit as Lang.String = "";
  private var mPackLabel as Lang.String = "";
  private var mPackPrefix as Lang.String = "";
  private var mLoadPct as Lang.Float = 0.0;
  private var mLoadPctShown as Lang.Number = 0; // rounded, as displayed
  private var mLoadWarning as Lang.Boolean = false;

  // Fonts (per resolution and screen type, generated by tools/gen_assets.py)
  private var mFontBig as Graphics.FontType = Graphics.FONT_MEDIUM;
  private var mFontMed as Graphics.FontType = Graphics.FONT_SMALL;
  private var mFontLabel as Graphics.FontType = Graphics.FONT_XTINY;

  private var mSpriteRuns as Lang.Array<Lang.Array<Lang.Number> > =
    [] as Lang.Array<Lang.Array<Lang.Number> >;

  // Theme colours, refreshed each onUpdate (MIP follows the activity theme)
  private var mBg as Lang.Number = Graphics.COLOR_BLACK;
  private var mInk as Lang.Number = P_BRIGHT;
  private var mLabelInk as Lang.Number = P_DIM;
  private var mRule as Lang.Number = P_DARK;
  private var mOk as Lang.Number = P_BRIGHT;
  private var mCaution as Lang.Number = P_AMBER;
  private var mAlert as Lang.Number = P_RED;
  private var mAccent as Lang.Number = P_AMBER;

  // Layout (computed in onLayout)
  private var mMode as Lang.Number = MODE_SINGLE;
  private var mW as Lang.Number = 0;
  private var mH as Lang.Number = 0;
  private var mCenterX as Lang.Number = 0;
  private var mLabelH as Lang.Number = 0;
  private var mGap as Lang.Number = 0;
  private var mValueFont as Graphics.FontType = Graphics.FONT_SMALL;
  // Full-screen stack
  private var mSpriteP as Lang.Number = 2;
  private var mSpriteY as Lang.Number = 0;
  private var mPaceLabelY as Lang.Number = 0;
  private var mPaceValueY as Lang.Number = 0;
  private var mDiv1Y as Lang.Number = 0;
  private var mMidLabelY as Lang.Number = 0;
  private var mMidValueY as Lang.Number = 0;
  private var mMidSubY as Lang.Number = 0;
  private var mDiv2Y as Lang.Number = 0;
  private var mPackLabelY as Lang.Number = 0;
  private var mMidX as Lang.Array<Lang.Number> = [0, 0];
  private var mDivHalf as Lang.Array<Lang.Number> = [0, 0];
  // Half-screen duo
  private var mDuoCellY as Lang.Number = 0;
  // Single
  private var mSingleY as Lang.Number = 0;
  // Energy bar
  private var mBarX as Lang.Number = 0;
  private var mBarY as Lang.Number = 0;
  private var mBarW as Lang.Number = 0;
  private var mBarH as Lang.Number = 0;
  private var mShowBar as Lang.Boolean = false;

  // Animation / burn-in state
  private var mIsAmoled as Lang.Boolean = false;
  private var mFrame as Lang.Number = 0;
  private var mBlinkOn as Lang.Boolean = true;
  private var mShiftCount as Lang.Number = 0;
  private var mShiftIndex as Lang.Number = 0;
  private var mDx as Lang.Number = 0;
  private var mDy as Lang.Number = 0;

  // Start screen / intro
  private var mTimerState as Lang.Number? = null;
  private var mAttractTick as Lang.Number = 0;
  private var mIntroLeft as Lang.Number = 0;
  private var mHiKcal as Lang.Float = 0.0;
  private var mTitle as Lang.String = "";
  private var mPressStart as Lang.String = "";
  private var mHiLabel as Lang.String = "";
  private var mReady as Lang.String = "";
  private var mGo as Lang.String = "";
  // Start-screen layout (computed with the full-screen one)
  private var mAttP as Lang.Number = 0;
  private var mAttSpriteY as Lang.Number = 0;
  private var mAttGroundY as Lang.Number = 0;
  private var mAttGroundHalf as Lang.Number = 0;
  private var mAttTitleY as Lang.Number = 0;
  private var mAttHiY as Lang.Number = 0;
  private var mAttPackY as Lang.Number = 0;
  private var mAttBarY as Lang.Number = 0;
  private var mAttBarX as Lang.Number = 0;
  private var mAttBarW as Lang.Number = 0;
  private var mAttStartY as Lang.Number = 0;

  function initialize() {
    DataField.initialize();

    var deviceSettings = System.getDeviceSettings();
    if (deviceSettings has :requiresBurnInProtection) {
      mIsAmoled = deviceSettings.requiresBurnInProtection;
    }

    mFitPower = createField(
      "ruck_power",
      0,
      FitContributor.DATA_TYPE_UINT16,
      { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" }
    );
    mFitKcal = createField(
      "ruck_kcal",
      1,
      FitContributor.DATA_TYPE_UINT16,
      { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kcal" }
    );
    mFitPack = createField(
      "pack_weight",
      2,
      FitContributor.DATA_TYPE_FLOAT,
      { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kg" }
    );
    mFitLoadKm = createField(
      "load_km",
      3,
      FitContributor.DATA_TYPE_FLOAT,
      { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kg-km" }
    );
    mFitAvgPace = createField(
      "avg_nopack_pace",
      4,
      FitContributor.DATA_TYPE_FLOAT,
      { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "min/km" }
    );
    mFitAvgBurn = createField(
      "avg_burn",
      5,
      FitContributor.DATA_TYPE_UINT16,
      { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kcal/h" }
    );
    mFitPeakBurn = createField(
      "peak_burn",
      6,
      FitContributor.DATA_TYPE_UINT16,
      { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kcal/h" }
    );
    mFitLapKcal = createField(
      "lap_ruck_kcal",
      7,
      FitContributor.DATA_TYPE_UINT16,
      { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "kcal" }
    );

    mFontBig = WatchUi.loadResource(Rez.Fonts.Big) as Graphics.FontType;
    mFontMed = WatchUi.loadResource(Rez.Fonts.Medium) as Graphics.FontType;
    mFontLabel = WatchUi.loadResource(Rez.Fonts.Label) as Graphics.FontType;
    buildSpriteRuns();

    mTitle = WatchUi.loadResource(Rez.Strings.Title) as Lang.String;
    mPressStart = WatchUi.loadResource(Rez.Strings.PressStart) as Lang.String;
    mHiLabel = WatchUi.loadResource(Rez.Strings.HiScore) as Lang.String;
    mReady = WatchUi.loadResource(Rez.Strings.Ready) as Lang.String;
    mGo = WatchUi.loadResource(Rez.Strings.Go) as Lang.String;
    try {
      var hi = Application.Storage.getValue(HI_KEY);
      if (hi instanceof Lang.Number || hi instanceof Lang.Float) {
        mHiKcal = hi.toFloat();
      }
    } catch (e) {
      // No hi-score yet
    }

    loadSettings();
  }

  //! Re-read settings; called at start and from RuckApp.onSettingsChanged()
  function loadSettings() as Void {
    // Weight: 0 = kg (default), 1 = lbs -> pack entry, load x distance.
    // Distance: 0 = km (default), 1 = mi -> pace, load x distance.
    mImperialWeight = readNumber("weightUnit", 0) == 1;
    mStatuteDistance = readNumber("distanceUnit", 0) == 1;
    var pack = readFloat("packWeight", 15.0);
    mLoadKg = mImperialWeight ? pack * KG_PER_LB : pack;
    if (mLoadKg < 0.0) {
      mLoadKg = 0.0;
    }

    mBodyKg = readFloat("bodyWeightKg", 0.0);
    if (mBodyKg <= 0.0) {
      mBodyKg = profileBodyKg();
    }

    var terrain = readNumber("terrain", 0);
    if (terrain < 0 || terrain >= RuckModel.TERRAIN_FACTORS.size()) {
      terrain = 0;
    }
    mEta = RuckModel.TERRAIN_FACTORS[terrain];
    mWarnPct = readNumber("loadWarnPct", 30);
    mCompactMetric = readNumber("compactMetric", METRIC_EQ_PACE);

    var weightUnit = mImperialWeight ? "LB" : "KG";
    var distUnit = mStatuteDistance ? "MI" : "KM";
    mLabels[METRIC_EQ_PACE] = WatchUi.loadResource(Rez.Strings.LabelEqPace) as Lang.String;
    mPaceShortLabel = WatchUi.loadResource(Rez.Strings.LabelEqPaceShort) as Lang.String;
    mLabels[METRIC_KCAL] = WatchUi.loadResource(Rez.Strings.LabelKcal) as Lang.String;
    mLabels[METRIC_LOAD_DIST] = WatchUi.loadResource(Rez.Strings.LabelLoadDist) as Lang.String;
    mLabels[METRIC_LOAD_PCT] = WatchUi.loadResource(Rez.Strings.LabelPack) as Lang.String;
    mPackPrefix = mLabels[METRIC_LOAD_PCT] + " ";
    mRateSuffix = WatchUi.loadResource(Rez.Strings.UnitPerHour) as Lang.String;
    mLoadUnit = weightUnit + "-" + distUnit;
    var packShown = mImperialWeight ? mLoadKg / KG_PER_LB : mLoadKg;
    // Whole numbers without a decimal ("15KG"), otherwise one place ("7.5KG")
    var packRounded = (packShown + 0.5).toNumber();
    mPackLabel =
      mPackPrefix +
      ((packShown - packRounded).abs() < 0.05
        ? packRounded.format("%d")
        : packShown.format("%.1f")) +
      (mImperialWeight ? "LBS" : "KG");

    if (mFitPack != null) {
      mFitPack.setData(mLoadKg);
    }
    updateDisplayText();

    if (DEBUG_LOGGING) {
      System.println(
        "Ruck settings: load=" + mLoadKg + "kg body=" + mBodyKg + "kg eta=" + mEta
      );
    }
  }

  function compute(info as Activity.Info) as Void {
    var timerMs = info.timerTime;
    mTimerState = info.timerState;
    // The intro plays on this screen's first updates after start; if another
    // data screen was showing then, skip it rather than play it late
    if (timerMs != null && timerMs > (INTRO_FRAMES + 1) * 1000) {
      mIntroLeft = 0;
    }
    var distM = info.elapsedDistance;

    if (!mRestoreChecked && timerMs != null && timerMs > 0) {
      mRestoreChecked = true;
      restoreState(info);
    }

    var rawSpeed = info.currentSpeed;
    var speed = rawSpeed != null ? rawSpeed.toFloat() : 0.0;
    if (speed > MAX_SPEED) {
      speed = MAX_SPEED;
    }
    mSpeed += SPEED_ALPHA * (speed - mSpeed);
    var moving = mSpeed >= MIN_MOVING_SPEED;
    updateGrade(distM, info.altitude);

    mMetabolicW = RuckModel.metabolicRate(
      mBodyKg,
      mLoadKg,
      mSpeed,
      // The grade window only advances with distance; once stopped, the last
      // slope no longer applies
      moving ? mGradePct : 0.0,
      mEta
    );

    // Accumulate only while the timer runs; timerTime stands still when paused.
    // Long gaps are capped, not dropped, so the distance in them still counts.
    if (timerMs != null && mLastTimerMs != null) {
      var dt = timerMs - mLastTimerMs;
      if (dt > MAX_STEP_MS) {
        dt = MAX_STEP_MS;
      }
      if (dt > 0) {
        var kcal = (mMetabolicW * dt) / 1000.0 / RuckModel.JOULES_PER_KCAL;
        mKcal += kcal;
        mLapKcal += kcal;
        updateSummary(dt);
        // Ignore GPS drift while standing
        if (moving && distM != null && mLastDistM != null && distM > mLastDistM) {
          mLoadKgM += mLoadKg * (distM - mLastDistM);
        }
      }
    }
    mLastTimerMs = timerMs;
    mLastDistM = distM;

    if (mFitPower != null) {
      mFitPower.setData(mMetabolicW.toNumber());
    }
    if (mFitKcal != null) {
      mFitKcal.setData(mKcal.toNumber());
    }
    if (mFitLoadKm != null) {
      mFitLoadKm.setData(mLoadKgM / METERS_PER_KM);
    }
    writeSummaryFields(timerMs);

    if (timerMs != null && timerMs - mLastSaveMs >= SAVE_INTERVAL_MS) {
      saveState(timerMs);
    }

    updateDisplayText();
  }

  // Summary stats, fed once per second of running timer
  private function updateSummary(dt as Lang.Number) as Void {
    if (mSpeed >= MIN_MOVING_SPEED) {
      mMovingMs += dt;
      mEqDistM +=
        (RuckModel.equivalentUnloadedSpeed(mMetabolicW, mBodyKg) * dt) / 1000.0;
    }
    // Peak over a ~30 s average, so one GPS blip can't set the record
    mSlowW += (mMetabolicW - mSlowW) * (dt / 30000.0);
    if (mMovingMs > 60000 && mSlowW > mPeakW) {
      mPeakW = mSlowW;
    }
  }

  // Session fields are metric (FIT labels are fixed); the watch display
  // follows the units setting
  private function writeSummaryFields(timerMs as Lang.Number?) as Void {
    if (mFitAvgPace != null) {
      var pace = 0.0;
      if (mEqDistM > 0.0) {
        pace = (mMovingMs / 60000.0) / (mEqDistM / METERS_PER_KM);
      }
      mFitAvgPace.setData(pace);
    }
    if (mFitAvgBurn != null && timerMs != null && timerMs > 0) {
      mFitAvgBurn.setData((mKcal * 3600000.0 / timerMs).toNumber());
    }
    if (mFitPeakBurn != null) {
      mFitPeakBurn.setData(RuckModel.wattsToKcalPerHour(mPeakW).toNumber());
    }
    if (mFitLapKcal != null) {
      mFitLapKcal.setData(mLapKcal.toNumber());
    }
  }

  // The lap record has been written by now; start counting the next lap
  function onTimerLap() as Void {
    mLapKcal = 0.0;
  }

  function onTimerReset() as Void {
    mKcal = 0.0;
    mLoadKgM = 0.0;
    mMovingMs = 0;
    mEqDistM = 0.0;
    mSlowW = 0.0;
    mPeakW = 0.0;
    mLapKcal = 0.0;
    mSpeed = 0.0;
    mGradePct = 0.0;
    mLastTimerMs = null;
    mLastDistM = null;
    mGradeAnchorDist = null;
    mGradeAnchorAlt = null;
    mStartTime = null;
    mLastSaveMs = 0;
    mRestoreChecked = false;
    // Back to the start screen for the next ruck
    mTimerState = Activity.TIMER_STATE_OFF;
    mAttractTick = 0;
    mIntroLeft = 0;
    try {
      Application.Storage.deleteValue(STORAGE_KEY);
    } catch (e) {
      // Nothing to clear
    }
    updateDisplayText();
  }

  function onTimerPause() as Void {
    if (mLastTimerMs != null) {
      saveState(mLastTimerMs);
    }
  }

  function onTimerStop() as Void {
    onTimerPause();
  }

  // Altitude keeps changing while paused (lift, vehicle); start a fresh grade
  // window rather than folding that climb into the next 25 m
  function onTimerResume() as Void {
    mGradeAnchorDist = null;
    mGradeAnchorAlt = null;
  }

  function onTimerStart() as Void {
    // READY / GO! only for a fresh start, not after a stop
    if (mLastTimerMs == null || mLastTimerMs <= 0) {
      mIntroLeft = INTRO_FRAMES;
    }
    mTimerState = Activity.TIMER_STATE_ON;
    onTimerResume();
  }

  function onLayout(dc as Graphics.Dc) as Void {
    var w = dc.getWidth();
    var h = dc.getHeight();
    var screenW = System.getDeviceSettings().screenWidth;
    var screenH = System.getDeviceSettings().screenHeight;
    mW = w;
    mH = h;
    mCenterX = w / 2;
    mLabelH = dc.getFontHeight(mFontLabel);
    mGap = mLabelH / 3;
    mBarH = mLabelH;

    if (h >= screenH * FULLSCREEN_PCT && w >= screenW * FULLSCREEN_PCT) {
      mMode = MODE_FULL;
      layoutFull(dc);
    } else if (
      h >= screenH * LARGE_FIELD_HEIGHT_PCT &&
      w >= screenW * LARGE_FIELD_WIDTH_PCT
    ) {
      mMode = MODE_DUO;
      layoutDuo(dc);
    } else {
      mMode = MODE_SINGLE;
      layoutSingle(dc);
    }
  }

  // Vertical stack filling the round screen:
  // sprite / pace / -- / calories | load / -- / pack bar
  private function layoutFull(dc as Graphics.Dc) as Void {
    var big = dc.getFontHeight(mFontBig);
    var med = dc.getFontHeight(mFontMed);
    var budget = mH * 0.88;
    var minGaps = 13 * (mLabelH / 3);
    var fixed = 5 * mLabelH + big + med; // 4 label rows + bar
    // Sprite one dot bigger than the labels if it fits, else same size,
    // else left out on the tightest screens
    var labelP = mLabelH / 7; // label font is 7 dots tall
    mSpriteP = labelP + 1;
    if (fixed + SPRITE_H * mSpriteP + minGaps > budget) {
      mSpriteP = labelP;
    }
    if (fixed + SPRITE_H * mSpriteP + minGaps > budget) {
      mSpriteP = 0;
    }
    var spriteH = SPRITE_H * mSpriteP;
    var content = fixed + spriteH;

    // 13 gap units in the stack; share out the spare height between them
    var g = (budget - content) / 13;
    if (g < mLabelH / 3) {
      g = mLabelH / 3;
    } else if (g > mLabelH) {
      g = mLabelH;
    }
    mGap = g.toNumber();
    g = mGap;
    var y = (mH - (content + 13 * g)) / 2;

    mSpriteY = y;
    y += spriteH + g;
    mPaceLabelY = y;
    y += mLabelH + g;
    mPaceValueY = y;
    y += big + 2 * g;
    mDiv1Y = y;
    y += 2 * g;
    mMidLabelY = y;
    y += mLabelH + g;
    mMidValueY = y;
    y += med + g;
    mMidSubY = y;
    y += mLabelH + 2 * g;
    mDiv2Y = y;
    y += 2 * g;
    mPackLabelY = y;
    y += mLabelH + g;
    mBarY = y;

    mMidX[0] = (mW * 0.27).toNumber();
    mMidX[1] = (mW * 0.73).toNumber();
    mDivHalf[0] = chordHalf(mDiv1Y) - mW / 12;
    mDivHalf[1] = chordHalf(mDiv2Y) - mW / 12;
    mBarW = min(mW * 0.6, (chordHalf(mBarY + mBarH) - mW / 14) * 2);
    mBarX = mCenterX - mBarW / 2;
    mShowBar = true;
    layoutAttract(dc, labelP);
  }

  // Start screen stack: big sprite on a ground line / title / hi-score /
  // pack label / pack bar / PRESS START. Sprite shrinks until it fits.
  private function layoutAttract(dc as Graphics.Dc, labelP as Lang.Number) as Void {
    var big = dc.getFontHeight(mFontBig);
    var g = mLabelH / 2;
    var rest = 2 * g + big + 2 * g + 3 * (mLabelH + g) + mBarH + g;
    var budget = mH * 0.86;
    var p = mSpriteP > 0 ? mSpriteP * 2 : labelP;
    while (p > 1 && SPRITE_H * p + g / 2 + rest > budget) {
      p--;
    }
    mAttP = p;
    var y = ((mH - (SPRITE_H * p + g / 2 + rest)) / 2).toNumber();
    mAttSpriteY = y;
    y += SPRITE_H * p + g / 2;
    mAttGroundY = y;
    mAttGroundHalf = min(chordHalf(y) - mW / 10, SPRITE_W * p * 2);
    y += 2 * g;
    mAttTitleY = y;
    y += big + 2 * g;
    mAttHiY = y;
    y += mLabelH + g;
    mAttPackY = y;
    y += mLabelH + g;
    mAttBarY = y;
    mAttBarW = min(mW * 0.5, (chordHalf(y + mBarH) - mW / 12) * 2);
    mAttBarX = mCenterX - mAttBarW / 2;
    y += mBarH + g;
    mAttStartY = y;
  }

  // Half screen: pace | calories, plus the pack bar. The wide row sits on
  // the field's flat edge, the narrower bar towards the curved one.
  private function layoutDuo(dc as Graphics.Dc) as Void {
    var flags = getObscurityFlags();
    var curvedTop = (flags & OBSCURE_TOP) != 0;
    var top = curvedTop ? (mH * 0.2).toNumber() : mGap;
    var bottom =
      (flags & OBSCURE_BOTTOM) != 0 ? (mH * 0.8).toNumber() : mH - mGap;
    var packBlock = mLabelH + mGap + mBarH;

    mValueFont = pickFont(
      dc,
      bottom - top - packBlock - 2 * mGap - mLabelH,
      (mW * 0.44).toNumber(),
      "88:88"
    );
    var cellBlock = mLabelH + mGap + dc.getFontHeight(mValueFont);
    var spare = (bottom - top - packBlock - cellBlock) / 3;
    var packY = curvedTop ? top + spare : top + 2 * spare + cellBlock;
    mDuoCellY = curvedTop ? top + 2 * spare + packBlock : top + spare;

    mPackLabelY = packY;
    mBarY = packY + mLabelH + mGap;
    mBarW = (mW * 0.5).toNumber();
    mBarX = mCenterX - mBarW / 2;
    mMidX[0] = (mW * 0.27).toNumber();
    mMidX[1] = (mW * 0.73).toNumber();
    mUseShortLabel =
      dc.getTextWidthInPixels(mLabels[METRIC_EQ_PACE], mFontLabel) > mW * 0.44;
    mShowBar = true;
  }

  // One metric, kept clear of any curved (obscured) edge of the field
  private function layoutSingle(dc as Graphics.Dc) as Void {
    var flags = getObscurityFlags();
    var top = (flags & OBSCURE_TOP) != 0 ? (mH * 0.22).toNumber() : mGap;
    var bottom =
      (flags & OBSCURE_BOTTOM) != 0 ? (mH * 0.85).toNumber() : mH - mGap;
    // A curved side narrows the usable width near that edge
    var sides = 0;
    if ((flags & OBSCURE_LEFT) != 0) {
      sides++;
    }
    if ((flags & OBSCURE_RIGHT) != 0) {
      sides++;
    }
    var width = mW - 2 * mGap - sides * (mW / 10);
    var avail = bottom - top;

    mValueFont = pickFont(dc, avail - mLabelH - mGap, width, "88:88");
    mUseShortLabel =
      dc.getTextWidthInPixels(mLabels[METRIC_EQ_PACE], mFontLabel) > width;
    var blockH = mLabelH + mGap + dc.getFontHeight(mValueFont);
    mShowBar =
      mCompactMetric == METRIC_LOAD_PCT && avail - blockH >= mBarH + 2 * mGap;
    if (mShowBar) {
      blockH += mGap + mBarH;
    }
    mSingleY = top + (avail - blockH) / 2;
    mBarW = min(width, mW * 0.6);
    mBarX = mCenterX - mBarW / 2;
    mBarY = mSingleY + blockH - mBarH;
  }

  function onUpdate(dc as Graphics.Dc) as Void {
    mBlinkOn = !mBlinkOn;
    updateColors();
    if (mIsAmoled) {
      updatePixelShift();
    }
    dc.setColor(mInk, mBg);
    dc.clear();

    if (mMode == MODE_FULL) {
      if (mTimerState != null && mTimerState == Activity.TIMER_STATE_OFF) {
        drawAttract(dc);
      } else if (mIntroLeft > 0) {
        drawIntro(dc);
        mIntroLeft--;
      } else {
        drawFull(dc);
      }
    } else if (mMode == MODE_DUO) {
      drawDuo(dc);
    } else {
      var metric = mCompactMetric;
      if (metric < 0 || metric > METRIC_LOAD_PCT) {
        metric = METRIC_EQ_PACE;
      }
      drawCell(dc, metric, mCenterX + mDx, mSingleY + mDy, mValueFont);
      if (mShowBar) {
        drawBar(dc, mBarX + mDx, mBarY + mDy, mBarW, BAR_SEGMENTS);
      }
    }
  }

  private function updateColors() as Void {
    if (mIsAmoled) {
      mBg = Graphics.COLOR_BLACK;
      mInk = P_BRIGHT;
      mLabelInk = P_DIM;
      mRule = P_DARK;
      mOk = P_BRIGHT;
      mCaution = P_AMBER;
      mAlert = P_RED;
      mAccent = P_AMBER;
      return;
    }
    // MIP: no dim tones, they vanish on a reflective screen
    mBg = getBackgroundColor();
    var dark = mBg == Graphics.COLOR_BLACK;
    mInk = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
    mLabelInk = mInk;
    mRule = mInk;
    mOk = mInk;
    mCaution = M_ORANGE;
    mAlert = M_RED;
    mAccent = M_ORANGE;
  }

  private function drawFull(dc as Graphics.Dc) as Void {
    var dx = mDx;
    var dy = mDy;

    // Rucker walks while moving, stands still otherwise
    mFrame = mSpeed >= MIN_MOVING_SPEED ? 1 - mFrame : 1;
    if (mSpriteP > 0) {
      drawSprite(
        dc,
        mCenterX - (SPRITE_W * mSpriteP) / 2 + dx,
        mSpriteY + dy,
        mSpriteP,
        mFrame
      );
    }

    drawText(dc, mCenterX + dx, mPaceLabelY + dy, mFontLabel, mLabelInk, mLabels[METRIC_EQ_PACE]);
    drawText(dc, mCenterX + dx, mPaceValueY + dy, mFontBig, mInk, mValues[METRIC_EQ_PACE]);

    drawDashedH(dc, mCenterX + dx, mDiv1Y + dy, mDivHalf[0]);
    drawDashedV(dc, mCenterX + dx, mDiv1Y + mGap + dy, mDiv2Y - mGap + dy);

    drawText(dc, mMidX[0] + dx, mMidLabelY + dy, mFontLabel, mLabelInk, mLabels[METRIC_KCAL]);
    drawText(dc, mMidX[0] + dx, mMidValueY + dy, mFontMed, mInk, mValues[METRIC_KCAL]);
    drawText(dc, mMidX[0] + dx, mMidSubY + dy, mFontLabel, mLabelInk, mRateText);

    drawText(dc, mMidX[1] + dx, mMidLabelY + dy, mFontLabel, mLabelInk, mLabels[METRIC_LOAD_DIST]);
    drawText(dc, mMidX[1] + dx, mMidValueY + dy, mFontMed, mInk, mValues[METRIC_LOAD_DIST]);
    drawText(dc, mMidX[1] + dx, mMidSubY + dy, mFontLabel, mLabelInk, mLoadUnit);

    drawDashedH(dc, mCenterX + dx, mDiv2Y + dy, mDivHalf[1]);
    drawPackLabel(dc, mCenterX + dx, mPackLabelY + dy);
    drawBar(dc, mBarX + dx, mBarY + dy, mBarW, BAR_SEGMENTS);
  }

  // Arcade attract mode, one frame per update
  private function drawAttract(dc as Graphics.Dc) as Void {
    var dx = mDx;
    var dy = mDy;
    mAttractTick++;
    mFrame = 1 - mFrame; // marching in place...
    drawSprite(
      dc,
      mCenterX - (SPRITE_W * mAttP) / 2 + dx,
      mAttSpriteY + dy,
      mAttP,
      mFrame
    );
    // ...while the ground scrolls past
    drawGround(dc, mCenterX + dx, mAttGroundY + dy, mAttGroundHalf, mAttractTick);

    drawTitle(dc, mCenterX + dx, mAttTitleY + dy, mFontBig, mTitle);
    drawText(
      dc,
      mCenterX + dx,
      mAttHiY + dy,
      mFontLabel,
      mLabelInk,
      mHiLabel + " " + (mHiKcal + 0.5).toNumber().format("%04d")
    );
    drawPackLabel(dc, mCenterX + dx, mAttPackY + dy);
    // "Loading" the pack: the bar fills up to the real load over a few frames
    drawBar(dc, mAttBarX + dx, mAttBarY + dy, mAttBarW, mAttractTick * LOAD_BLOCKS_PER_TICK);
    if (mBlinkOn) {
      drawText(dc, mCenterX + dx, mAttStartY + dy, mFontLabel, mAccent, mPressStart);
    }
  }

  // After start: READY, then GO!, one update each
  private function drawIntro(dc as Graphics.Dc) as Void {
    var dx = mDx;
    var dy = mDy;
    if (mSpriteP > 0) {
      drawSprite(
        dc,
        mCenterX - (SPRITE_W * mSpriteP) / 2 + dx,
        mSpriteY + dy,
        mSpriteP,
        mIntroLeft % 2
      );
    }
    var go = mIntroLeft == 1;
    var font = go ? mFontBig : mFontMed;
    var y = (mH - dc.getFontHeight(font)) / 2 + dy;
    if (go) {
      drawTitle(dc, mCenterX + dx, y, font, mGo);
    } else {
      drawText(dc, mCenterX + dx, y, font, mAccent, mReady);
    }
  }

  // Arcade title: ink over a one-dot accent drop shadow
  private function drawTitle(
    dc as Graphics.Dc,
    x as Lang.Number,
    y as Lang.Number,
    font as Graphics.FontType,
    text as Lang.String
  ) as Void {
    var dot = dc.getFontHeight(font) / 7;
    drawText(dc, x + dot, y + dot, font, mAccent, text);
    drawText(dc, x, y, font, mInk, text);
  }

  // Dashed ground line whose dashes step left one quarter-period per update
  private function drawGround(
    dc as Graphics.Dc,
    cx as Lang.Number,
    y as Lang.Number,
    half as Lang.Number,
    tick as Lang.Number
  ) as Void {
    var dash = mLabelH / 4 > 2 ? mLabelH / 4 : 2;
    var period = dash * GROUND_STEPS;
    var x0 = cx - half;
    var x1 = cx + half;
    dc.setColor(mRule, Graphics.COLOR_TRANSPARENT);
    for (var x = x0 - (tick % GROUND_STEPS) * dash; x < x1; x += period) {
      var a = x < x0 ? x0 : x;
      var b = x + 2 * dash > x1 ? x1 : x + 2 * dash;
      if (b > a) {
        dc.fillRectangle(a, y, b - a, dash / 2 > 1 ? dash / 2 : 1);
      }
    }
  }

  private function drawDuo(dc as Graphics.Dc) as Void {
    var dx = mDx;
    var dy = mDy;
    drawCell(dc, METRIC_EQ_PACE, mMidX[0] + dx, mDuoCellY + dy, mValueFont);
    drawCell(dc, METRIC_KCAL, mMidX[1] + dx, mDuoCellY + dy, mValueFont);
    drawDashedV(
      dc,
      mCenterX + dx,
      mDuoCellY + dy,
      mDuoCellY + mLabelH + mGap + dc.getFontHeight(mValueFont) + dy
    );
    drawPackLabel(dc, mCenterX + dx, mPackLabelY + dy);
    drawBar(dc, mBarX + dx, mBarY + dy, mBarW, BAR_SEGMENTS);
  }

  private function drawPackLabel(
    dc as Graphics.Dc,
    x as Lang.Number,
    y as Lang.Number
  ) as Void {
    drawText(
      dc,
      x,
      y,
      mFontLabel,
      mLoadWarning ? mAlert : mLabelInk,
      mPackLabel + " " + mValues[METRIC_LOAD_PCT]
    );
  }

  // Label above value, centred on x
  private function drawCell(
    dc as Graphics.Dc,
    metric as Lang.Number,
    x as Lang.Number,
    y as Lang.Number,
    font as Graphics.FontType
  ) as Void {
    var warn = metric == METRIC_LOAD_PCT && mLoadWarning;
    var label =
      metric == METRIC_EQ_PACE && mUseShortLabel ? mPaceShortLabel : mLabels[metric];
    drawText(dc, x, y, mFontLabel, warn ? mAlert : mLabelInk, label);
    drawText(dc, x, y + mLabelH + mGap, font, warn ? mAlert : mInk, mValues[metric]);
  }

  private function drawText(
    dc as Graphics.Dc,
    x as Lang.Number,
    y as Lang.Number,
    font as Graphics.FontType,
    color as Lang.Number,
    text as Lang.String
  ) as Void {
    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
    dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
  }

  // Sprite drawn from runs pre-computed in buildSpriteRuns(): a few dozen
  // rectangles once a second, no string work in the draw path
  private function drawSprite(
    dc as Graphics.Dc,
    x as Lang.Number,
    y as Lang.Number,
    p as Lang.Number,
    frame as Lang.Number
  ) as Void {
    var runs = mSpriteRuns[frame];
    for (var i = 0; i < runs.size(); i += 4) {
      dc.setColor(runs[i + 3] == 1 ? mAccent : mInk, Graphics.COLOR_TRANSPARENT);
      dc.fillRectangle(x + runs[i + 1] * p, y + runs[i] * p, runs[i + 2] * p, p);
    }
  }

  // Flatten each frame into [row, col, length, isAccent, ...] runs
  private function buildSpriteRuns() as Void {
    mSpriteRuns = [] as Lang.Array<Lang.Array<Lang.Number> >;
    for (var f = 0; f < SPRITE_FRAMES.size(); f++) {
      var runs = [] as Lang.Array<Lang.Number>;
      var rows = SPRITE_FRAMES[f];
      for (var ry = 0; ry < SPRITE_H; ry++) {
        var chars = rows[ry].toCharArray();
        var rx = 0;
        while (rx < SPRITE_W) {
          var c = chars[rx];
          var run = 1;
          while (rx + run < SPRITE_W && chars[rx + run] == c) {
            run++;
          }
          if (c != '.') {
            runs.addAll([ry, rx, run, c == 'A' ? 1 : 0]);
          }
          rx += run;
        }
      }
      mSpriteRuns.add(runs);
    }
  }

  // Energy bar: ok / caution / alert blocks by share of the warning
  // threshold. Empty blocks are outlines only; over the limit, the alert
  // blocks blink (free: we redraw once a second anyway).
  private function drawBar(
    dc as Graphics.Dc,
    x as Lang.Number,
    y as Lang.Number,
    width as Lang.Number,
    maxFilled as Lang.Number
  ) as Void {
    var gap = mBarH / 4 > 2 ? mBarH / 4 : 2;
    var segW = (width - (BAR_SEGMENTS - 1) * gap) / BAR_SEGMENTS;
    var maxPct = mWarnPct * BAR_MAX_OF_WARN;
    // Same rounded % as the label, so the first red block lights exactly
    // when the label turns red
    var filled = Math.ceil((mLoadPctShown * BAR_SEGMENTS) / maxPct).toNumber();
    if (filled > maxFilled) {
      filled = maxFilled;
    }
    for (var i = 0; i < BAR_SEGMENTS; i++) {
      var segStart = (i * maxPct) / BAR_SEGMENTS;
      var alert = segStart >= mWarnPct;
      var color = alert
        ? mAlert
        : segStart < mWarnPct * BAR_GREEN_OF_WARN ? mOk : mCaution;
      var sx = x + i * (segW + gap);
      if (i < filled && (!alert || mBlinkOn)) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(sx, y, segW, mBarH);
      } else {
        dc.setColor(mRule, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(sx, y, segW, mBarH);
      }
    }
  }

  private function drawDashedH(
    dc as Graphics.Dc,
    cx as Lang.Number,
    y as Lang.Number,
    half as Lang.Number
  ) as Void {
    var dash = mLabelH / 4 > 2 ? mLabelH / 4 : 2;
    dc.setColor(mRule, Graphics.COLOR_TRANSPARENT);
    for (var x = cx - half; x < cx + half; x += dash * 2) {
      dc.drawLine(x, y, x + dash, y);
    }
  }

  private function drawDashedV(
    dc as Graphics.Dc,
    x as Lang.Number,
    y0 as Lang.Number,
    y1 as Lang.Number
  ) as Void {
    var dash = mLabelH / 4 > 2 ? mLabelH / 4 : 2;
    dc.setColor(mRule, Graphics.COLOR_TRANSPARENT);
    for (var y = y0; y < y1; y += dash * 2) {
      dc.drawLine(x, y, x, y + dash);
    }
  }

  private function updatePixelShift() as Void {
    mShiftCount++;
    if (mShiftCount < SHIFT_INTERVAL) {
      return;
    }
    mShiftCount = 0;
    mShiftIndex = (mShiftIndex + 1) % SHIFT_X.size();
    mDx = SHIFT_X[mShiftIndex];
    mDy = SHIFT_Y[mShiftIndex];
  }

  // Half-width of the round screen at row y
  private function chordHalf(y as Lang.Number) as Lang.Number {
    var r = mW / 2;
    var d = y - mH / 2;
    var sq = r * r - d * d;
    return sq > 0 ? Math.sqrt(sq).toNumber() : 0;
  }

  private function min(a as Lang.Numeric, b as Lang.Numeric) as Lang.Number {
    return (a < b ? a : b).toNumber();
  }

  // Largest value font whose height and sample width fit the box. Walks
  // the V0..V8 ladder (one rung per dot size, largest first) loading one
  // rung at a time, so only the chosen font stays in memory.
  private function pickFont(
    dc as Graphics.Dc,
    maxHeight as Lang.Numeric,
    maxWidth as Lang.Numeric,
    sample as Lang.String
  ) as Graphics.FontType {
    var ids = [
      Rez.Fonts.V0, Rez.Fonts.V1, Rez.Fonts.V2, Rez.Fonts.V3, Rez.Fonts.V4,
      Rez.Fonts.V5, Rez.Fonts.V6, Rez.Fonts.V7, Rez.Fonts.V8,
    ];
    for (var i = 0; i < ids.size(); i++) {
      var font = WatchUi.loadResource(ids[i]) as Graphics.FontType;
      if (
        dc.getFontHeight(font) <= maxHeight &&
        dc.getTextWidthInPixels(sample, font) <= maxWidth
      ) {
        return font;
      }
    }
    return mFontLabel;
  }

  // Grade over a GRADE_WINDOW_M distance window, smoothed; 0 without altitude
  private function updateGrade(distM as Lang.Float?, altM as Lang.Float?) as Void {
    if (distM == null || altM == null) {
      return;
    }
    if (mGradeAnchorDist == null || mGradeAnchorAlt == null) {
      mGradeAnchorDist = distM;
      mGradeAnchorAlt = altM;
      return;
    }
    var run = distM - mGradeAnchorDist;
    if (run < GRADE_WINDOW_M) {
      return;
    }
    var grade = ((altM - mGradeAnchorAlt) / run) * 100.0;
    if (grade > GRADE_MAX_PCT) {
      grade = GRADE_MAX_PCT;
    } else if (grade < -GRADE_MAX_PCT) {
      grade = -GRADE_MAX_PCT;
    }
    mGradePct += GRADE_ALPHA * (grade - mGradePct);
    mGradeAnchorDist = distM;
    mGradeAnchorAlt = altM;
  }

  private function updateDisplayText() as Void {
    var unitM = mStatuteDistance ? METERS_PER_MILE : METERS_PER_KM;

    var eqSpeed = RuckModel.equivalentUnloadedSpeed(mMetabolicW, mBodyKg);
    if (mSpeed >= MIN_MOVING_SPEED && eqSpeed > 0.0) {
      var sec = (unitM / eqSpeed + 0.5).toNumber();
      mValues[METRIC_EQ_PACE] =
        sec > MAX_PACE_SEC
          ? "--:--"
          : (sec / 60).format("%d") + ":" + (sec % 60).format("%02d");
    } else {
      mValues[METRIC_EQ_PACE] = "--:--";
    }

    mValues[METRIC_KCAL] = (mKcal + 0.5).toNumber().format("%d");

    var loadDist =
      (mImperialWeight ? mLoadKgM / KG_PER_LB : mLoadKgM) / unitM;
    // Keep it to 4 characters so it fits the pixel font's cell
    mValues[METRIC_LOAD_DIST] =
      loadDist < 99.95
        ? loadDist.format("%.1f")
        : (loadDist + 0.5).toNumber().format("%d");

    mLoadPct = (mLoadKg / mBodyKg) * 100.0;
    mLoadPctShown = (mLoadPct + 0.5).toNumber();
    mValues[METRIC_LOAD_PCT] = mLoadPctShown.format("%d") + "%";
    mLoadWarning = mLoadPctShown > mWarnPct;

    mRateText =
      (RuckModel.wattsToKcalPerHour(mMetabolicW) + 0.5).toNumber().format("%d") +
      mRateSuffix;
  }

  //! Simulates the data field being restarted mid-activity: in-memory state
  //! is lost, Storage is kept (RuckViewTest only; debug builds)
  (:debug)
  function testRestart() as Void {
    mKcal = 0.0;
    mLoadKgM = 0.0;
    mMovingMs = 0;
    mEqDistM = 0.0;
    mSlowW = 0.0;
    mPeakW = 0.0;
    mLapKcal = 0.0;
    mSpeed = 0.0;
    mGradePct = 0.0;
    mLastTimerMs = null;
    mLastDistM = null;
    mGradeAnchorDist = null;
    mGradeAnchorAlt = null;
    mStartTime = null;
    mLastSaveMs = 0;
    mRestoreChecked = false;
  }

  //! Snapshot of internal state for RuckViewTest (debug builds only)
  (:debug)
  function testState() as Lang.Dictionary<Lang.String, Lang.Object?> {
    return {
      "kcal" => mKcal,
      "lkm" => mLoadKgM,
      "lap" => mLapKcal,
      "mov" => mMovingMs,
      "eqd" => mEqDistM,
      "peak" => mPeakW,
      "w" => mMetabolicW,
      "loadKg" => mLoadKg,
      "values" => mValues,
      "labels" => mLabels,
      "loadUnit" => mLoadUnit,
      "packLabel" => mPackLabel,
      "warn" => mLoadWarning,
      "pctShown" => mLoadPctShown,
      "attract" => mTimerState != null && mTimerState == Activity.TIMER_STATE_OFF,
      "intro" => mIntroLeft,
      "hi" => mHiKcal,
    };
  }

  // Totals survive the data field being restarted mid-activity (settings
  // change, crash); startTime ties them to this activity only
  private function saveState(timerMs as Lang.Number) as Void {
    mLastSaveMs = timerMs;
    if (mKcal > mHiKcal + 0.5) {
      mHiKcal = mKcal;
      try {
        Application.Storage.setValue(HI_KEY, mHiKcal);
      } catch (e) {
        // Keep it for this session only
      }
    }
    if (mStartTime == null) {
      return;
    }
    try {
      Application.Storage.setValue(STORAGE_KEY, {
        "v" => STORAGE_VERSION,
        "start" => mStartTime,
        "t" => timerMs,
        "kcal" => mKcal,
        "lkm" => mLoadKgM,
        "mov" => mMovingMs,
        "eqd" => mEqDistM,
        "slow" => mSlowW,
        "peak" => mPeakW,
        "lap" => mLapKcal,
      });
    } catch (e) {
      if (DEBUG_LOGGING) {
        System.println("Ruck save failed: " + e.getErrorMessage());
      }
    }
  }

  private function restoreState(info as Activity.Info) as Void {
    var start = info.startTime;
    mStartTime = start != null ? start.value() : null;
    if (mStartTime == null) {
      return;
    }
    var saved = null;
    try {
      saved = Application.Storage.getValue(STORAGE_KEY);
    } catch (e) {
      return;
    }
    if (!(saved instanceof Lang.Dictionary)) {
      return;
    }
    var state = saved as Lang.Dictionary<Lang.String, Lang.Numeric>;
    var savedTimer = state["t"];
    var timerMs = info.timerTime;
    if (
      state["v"] == STORAGE_VERSION &&
      state["start"] == mStartTime &&
      savedTimer != null &&
      timerMs != null &&
      savedTimer <= timerMs
    ) {
      mKcal = (state["kcal"] as Lang.Numeric).toFloat();
      mLoadKgM = (state["lkm"] as Lang.Numeric).toFloat();
      mMovingMs = (state["mov"] as Lang.Numeric).toNumber();
      mEqDistM = (state["eqd"] as Lang.Numeric).toFloat();
      mSlowW = (state["slow"] as Lang.Numeric).toFloat();
      mPeakW = (state["peak"] as Lang.Numeric).toFloat();
      mLapKcal = (state["lap"] as Lang.Numeric).toFloat();
      if (DEBUG_LOGGING) {
        System.println("Ruck restored: kcal=" + mKcal + " load-m=" + mLoadKgM);
      }
    }
  }

  private function profileBodyKg() as Lang.Float {
    var profile = UserProfile.getProfile();
    var grams = profile != null ? profile.weight : null;
    if (grams != null && grams > 0) {
      return grams / 1000.0;
    }
    return DEFAULT_BODY_KG;
  }

  private function readFloat(key as Lang.String, fallback as Lang.Float) as Lang.Float {
    try {
      var v = Application.Properties.getValue(key);
      if (v instanceof Lang.Number || v instanceof Lang.Float || v instanceof Lang.Double) {
        return v.toFloat();
      }
    } catch (e) {
      // Fall through to default
    }
    return fallback;
  }

  private function readNumber(key as Lang.String, fallback as Lang.Number) as Lang.Number {
    try {
      var v = Application.Properties.getValue(key);
      if (v instanceof Lang.Number || v instanceof Lang.Float || v instanceof Lang.Double) {
        return v.toNumber();
      }
    } catch (e) {
      // Fall through to default
    }
    return fallback;
  }
}
