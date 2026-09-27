using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi;

//! On-watch settings (activity menu > Ruck Load): pack weight, weight and
//! distance units,
//! terrain and load warning. Values are Application.Properties, so they are
//! the same settings the phone app edits and they persist between rucks.
module RuckSettings {
  const ITEM_PACK = :pack;
  const ITEM_WEIGHT_UNIT = :weightUnit;
  const ITEM_DISTANCE_UNIT = :distanceUnit;
  const ITEM_TERRAIN = :terrain;
  const ITEM_WARN = :warn;

  const KG_PER_LB = 0.45359237;
  const MAX_PACK_KG = 100;
  const MAX_PACK_LB = 220;
  const WARN_CHOICES = [20, 25, 30, 35, 40] as Lang.Array<Lang.Number>;

  function str(id as Lang.ResourceId) as Lang.String {
    return WatchUi.loadResource(id) as Lang.String;
  }

  function getNumber(key as Lang.String, fallback as Lang.Number) as Lang.Number {
    var v = Application.Properties.getValue(key);
    return v instanceof Lang.Number ? v : fallback;
  }

  function getFloat(key as Lang.String, fallback as Lang.Float) as Lang.Float {
    var v = Application.Properties.getValue(key);
    if (v instanceof Lang.Float || v instanceof Lang.Number || v instanceof Lang.Double) {
      return v.toFloat();
    }
    return fallback;
  }

  function isImperialWeight() as Lang.Boolean {
    return getNumber("weightUnit", 0) == 1;
  }

  function weightLabels() as Lang.Array<Lang.String> {
    return [str(Rez.Strings.UnitKg), str(Rez.Strings.UnitLbs)] as Lang.Array<Lang.String>;
  }

  function distanceLabels() as Lang.Array<Lang.String> {
    return [str(Rez.Strings.UnitKm), str(Rez.Strings.UnitMi)] as Lang.Array<Lang.String>;
  }

  function terrainLabels() as Lang.Array<Lang.String> {
    return [
      str(Rez.Strings.TerrainPaved),
      str(Rez.Strings.TerrainDirt),
      str(Rez.Strings.TerrainLightBrush),
      str(Rez.Strings.TerrainHeavyBrush),
      str(Rez.Strings.TerrainSwamp),
      str(Rez.Strings.TerrainSand),
    ] as Lang.Array<Lang.String>;
  }

  function packSubLabel() as Lang.String {
    var w = getFloat("packWeight", 15.0);
    var text = w == w.toNumber() ? w.toNumber().format("%d") : w.format("%.1f");
    return text + (isImperialWeight() ? " lbs" : " kg");
  }

  function choiceLabel(labels as Lang.Array<Lang.String>, index as Lang.Number) as Lang.String {
    return index >= 0 && index < labels.size() ? labels[index] : labels[0];
  }

  //! Apply a change: persist it and refresh the running data field
  function commit(key as Lang.String, value as Lang.Number or Lang.Float) as Void {
    Application.Properties.setValue(key, value);
    var app = Application.getApp();
    if (app instanceof RuckApp) {
      app.onSettingsChanged();
    }
  }

  //! Change the weight unit, keeping the same physical pack: the stored
  //! weight is converted between kg and lbs, rounded to the editor's step
  //! (0.5 kg / 1 lb). The phone settings can't do this, so their title tells
  //! the user to re-enter the weight.
  function setWeightUnit(unit as Lang.Number) as Void {
    var toImperial = unit == 1;
    if (toImperial != isImperialWeight()) {
      var w = getFloat("packWeight", 15.0);
      var converted = toImperial
        ? Math.round(w / KG_PER_LB)
        : Math.round(w * KG_PER_LB * 2.0) / 2.0;
      Application.Properties.setValue("packWeight", converted.toFloat());
    }
    commit("weightUnit", unit);
  }

  function buildMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => str(Rez.Strings.AppName) });
    menu.addItem(
      new WatchUi.MenuItem(str(Rez.Strings.MenuPack), packSubLabel(), ITEM_PACK, null)
    );
    menu.addItem(
      new WatchUi.MenuItem(
        str(Rez.Strings.MenuWeightUnit),
        choiceLabel(weightLabels(), getNumber("weightUnit", 0)),
        ITEM_WEIGHT_UNIT,
        null
      )
    );
    menu.addItem(
      new WatchUi.MenuItem(
        str(Rez.Strings.MenuDistanceUnit),
        choiceLabel(distanceLabels(), getNumber("distanceUnit", 0)),
        ITEM_DISTANCE_UNIT,
        null
      )
    );
    menu.addItem(
      new WatchUi.MenuItem(
        str(Rez.Strings.MenuTerrain),
        choiceLabel(terrainLabels(), getNumber("terrain", 0)),
        ITEM_TERRAIN,
        null
      )
    );
    menu.addItem(
      new WatchUi.MenuItem(
        str(Rez.Strings.MenuWarn),
        getNumber("loadWarnPct", 30).format("%d") + "%",
        ITEM_WARN,
        null
      )
    );
    return menu;
  }
}

//! Top-level settings menu
class RuckMenuDelegate extends WatchUi.Menu2InputDelegate {
  function initialize() {
    Menu2InputDelegate.initialize();
  }

  function onSelect(item as WatchUi.MenuItem) as Void {
    var id = item.getId();
    if (id == RuckSettings.ITEM_PACK) {
      var view = new RuckWeightView(
        RuckSettings.isImperialWeight(),
        RuckSettings.getFloat("packWeight", 15.0)
      );
      WatchUi.pushView(view, new RuckWeightInput(view, item), WatchUi.SLIDE_LEFT);
    } else if (id == RuckSettings.ITEM_WEIGHT_UNIT) {
      pushChoices(item, "weightUnit", RuckSettings.weightLabels(), null);
    } else if (id == RuckSettings.ITEM_DISTANCE_UNIT) {
      pushChoices(item, "distanceUnit", RuckSettings.distanceLabels(), null);
    } else if (id == RuckSettings.ITEM_TERRAIN) {
      pushChoices(item, "terrain", RuckSettings.terrainLabels(), null);
    } else if (id == RuckSettings.ITEM_WARN) {
      var labels = [] as Lang.Array<Lang.String>;
      for (var i = 0; i < RuckSettings.WARN_CHOICES.size(); i++) {
        labels.add(RuckSettings.WARN_CHOICES[i].format("%d") + "%");
      }
      pushChoices(item, "loadWarnPct", labels, RuckSettings.WARN_CHOICES);
    }
  }

  //! List of options; `values` maps rows to stored values (null = row index)
  private function pushChoices(
    parent as WatchUi.MenuItem,
    key as Lang.String,
    labels as Lang.Array<Lang.String>,
    values as Lang.Array<Lang.Number>?
  ) as Void {
    var menu = new WatchUi.Menu2({ :title => parent.getLabel() });
    for (var i = 0; i < labels.size(); i++) {
      menu.addItem(new WatchUi.MenuItem(labels[i], null, i, null));
    }
    var current = RuckSettings.getNumber(key, 0);
    var focus = values != null ? values.indexOf(current) : current;
    if (focus >= 0 && focus < labels.size()) {
      menu.setFocus(focus);
    }
    WatchUi.pushView(
      menu,
      new RuckChoiceDelegate(parent, key, labels, values),
      WatchUi.SLIDE_LEFT
    );
  }
}

//! Picks one option, stores it and updates the parent row's sub-label
class RuckChoiceDelegate extends WatchUi.Menu2InputDelegate {
  private var mParent as WatchUi.MenuItem;
  private var mKey as Lang.String;
  private var mLabels as Lang.Array<Lang.String>;
  private var mValues as Lang.Array<Lang.Number>?;

  function initialize(
    parent as WatchUi.MenuItem,
    key as Lang.String,
    labels as Lang.Array<Lang.String>,
    values as Lang.Array<Lang.Number>?
  ) {
    Menu2InputDelegate.initialize();
    mParent = parent;
    mKey = key;
    mLabels = labels;
    mValues = values;
  }

  function onSelect(item as WatchUi.MenuItem) as Void {
    var row = item.getId() as Lang.Number;
    var values = mValues;
    if (mKey.equals("weightUnit")) {
      RuckSettings.setWeightUnit(row);
    } else {
      RuckSettings.commit(mKey, values != null ? values[row] : row);
    }
    mParent.setSubLabel(mLabels[row]);
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
  }

}

//! Pack weight editor in the field's own pixel style (the system Picker
//! can't be themed, and on MIP watches draws white text on white).
//! UP/DOWN or swipe: change (quick repeated presses speed up to 5 steps);
//! START/tap: save; BACK: cancel. 0-100 kg in 0.5 kg steps, 0-220 lb in 1 lb.
class RuckWeightView extends WatchUi.View {
  private const FAST_PRESS_MS = 400;
  private const FAST_AFTER = 4; // quick presses before stepping x5

  private var mImperial as Lang.Boolean;
  private var mStep as Lang.Float;
  private var mMax as Lang.Float;
  private var mValue as Lang.Float;
  private var mLastPressMs as Lang.Number = 0;
  private var mQuickPresses as Lang.Number = 0;
  private var mIsAmoled as Lang.Boolean = false;
  private var mFontBig as Graphics.FontType = Graphics.FONT_LARGE;
  private var mFontLabel as Graphics.FontType = Graphics.FONT_XTINY;

  function initialize(imperial as Lang.Boolean, value as Lang.Float) {
    View.initialize();
    mImperial = imperial;
    mStep = imperial ? 1.0 : 0.5;
    mMax = (imperial ? RuckSettings.MAX_PACK_LB : RuckSettings.MAX_PACK_KG).toFloat();
    mValue = clamp((Math.round(value / mStep) * mStep).toFloat());
    var settings = System.getDeviceSettings();
    if (settings has :requiresBurnInProtection) {
      mIsAmoled = settings.requiresBurnInProtection;
    }
  }

  function onLayout(dc as Graphics.Dc) as Void {
    mFontBig = WatchUi.loadResource(Rez.Fonts.Big) as Graphics.FontType;
    mFontLabel = WatchUi.loadResource(Rez.Fonts.Label) as Graphics.FontType;
  }

  function getValue() as Lang.Float {
    return mValue;
  }

  //! +1 = heavier, -1 = lighter
  function adjust(direction as Lang.Number) as Void {
    var now = System.getTimer();
    mQuickPresses = now - mLastPressMs < FAST_PRESS_MS ? mQuickPresses + 1 : 0;
    mLastPressMs = now;
    var steps = mQuickPresses >= FAST_AFTER ? 5 : 1;
    mValue = clamp(mValue + direction * steps * mStep);
    WatchUi.requestUpdate();
  }

  function onUpdate(dc as Graphics.Dc) as Void {
    var ink = mIsAmoled ? 0x00ff00 : Graphics.COLOR_WHITE;
    var dim = mIsAmoled ? 0x00aa00 : Graphics.COLOR_WHITE;
    var w = dc.getWidth();
    var h = dc.getHeight();
    var cx = w / 2;
    var labelH = dc.getFontHeight(mFontLabel);
    var bigH = dc.getFontHeight(mFontBig);
    var arrow = labelH;

    dc.setColor(ink, Graphics.COLOR_BLACK);
    dc.clear();

    var valueY = (h - bigH) / 2;
    dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
    dc.drawText(cx, valueY - 3 * arrow - labelH, mFontLabel, "PACK WEIGHT", Graphics.TEXT_JUSTIFY_CENTER);

    // Arcade-style up/down arrows, one arrow-height clear of the digits
    var upY = valueY - 2 * arrow;
    dc.setColor(mValue < mMax ? ink : dim, Graphics.COLOR_TRANSPARENT);
    dc.fillPolygon([[cx, upY], [cx - arrow, upY + arrow], [cx + arrow, upY + arrow]]);
    var downY = valueY + bigH + arrow;
    dc.setColor(mValue > 0.0 ? ink : dim, Graphics.COLOR_TRANSPARENT);
    dc.fillPolygon([[cx - arrow, downY], [cx + arrow, downY], [cx, downY + arrow]]);

    var text = mValue == mValue.toNumber()
      ? mValue.toNumber().format("%d")
      : mValue.format("%.1f");
    dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
    dc.drawText(cx, valueY, mFontBig, text, Graphics.TEXT_JUSTIFY_CENTER);
    dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
    dc.drawText(
      cx,
      downY + arrow + labelH,
      mFontLabel,
      (mImperial ? "LBS" : "KG") + " - START SAVES",
      Graphics.TEXT_JUSTIFY_CENTER
    );
  }

  private function clamp(v as Lang.Float) as Lang.Float {
    return v < 0.0 ? 0.0 : v > mMax ? mMax : v;
  }
}

class RuckWeightInput extends WatchUi.BehaviorDelegate {
  private var mView as RuckWeightView;
  private var mParent as WatchUi.MenuItem;

  function initialize(view as RuckWeightView, parent as WatchUi.MenuItem) {
    BehaviorDelegate.initialize();
    mView = view;
    mParent = parent;
  }

  function onPreviousPage() as Lang.Boolean {
    mView.adjust(1);
    return true;
  }

  function onNextPage() as Lang.Boolean {
    mView.adjust(-1);
    return true;
  }

  function onSelect() as Lang.Boolean {
    RuckSettings.commit("packWeight", mView.getValue());
    mParent.setSubLabel(RuckSettings.packSubLabel());
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    return true;
  }

  function onBack() as Lang.Boolean {
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    return true;
  }
}
