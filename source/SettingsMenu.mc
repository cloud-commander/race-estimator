using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.WatchUi;

// On-watch settings: activity menu > Data Screens > this field > Settings.
// Target race, custom distance and goal time, written to the same
// properties as the Garmin Connect settings (so either place works).
class SettingsMenu extends WatchUi.Menu2 {
  static const RACE_NAMES = [
    Rez.Strings.Race5K,
    Rez.Strings.Race5Mi,
    Rez.Strings.Race10K,
    Rez.Strings.Race131K,
    Rez.Strings.Race10Mi,
    Rez.Strings.RaceHalf,
    Rez.Strings.Race262K,
    Rez.Strings.RaceMarathon,
    Rez.Strings.Race50K,
    Rez.Strings.RaceCustom,
  ];

  function initialize() {
    Menu2.initialize({ :title => Rez.Strings.AppName });
    addItem(new WatchUi.MenuItem(Rez.Strings.TargetRaceTitle, raceSub(), :target, null));
    addItem(new WatchUi.MenuItem(Rez.Strings.CustomDistanceTitle, customSub(), :custom, null));
    addItem(new WatchUi.MenuItem(Rez.Strings.GoalTitle, goalSub(), :goal, null));
  }

  // Sub-labels show the current values; refreshed after each change
  function refresh() as Void {
    setSub(:target, raceSub());
    setSub(:custom, customSub());
    setSub(:goal, goalSub());
    WatchUi.requestUpdate();
  }

  private function setSub(id as Lang.Symbol, text as Lang.String) as Void {
    var i = findItemById(id);
    if (i >= 0) {
      var item = getItem(i);
      if (item != null) {
        item.setSubLabel(text);
      }
    }
  }

  private function raceSub() as Lang.String {
    var idx = SettingsStore.getNumber("targetRace", 7);
    if (idx < 0 || idx >= RACE_NAMES.size()) {
      idx = 7;
    }
    return WatchUi.loadResource(RACE_NAMES[idx] as Lang.ResourceId) as Lang.String;
  }

  private function customSub() as Lang.String {
    return SettingsStore.getCustomKm() + " km";
  }

  private function goalSub() as Lang.String {
    var h = SettingsStore.getNumber("goalHours", 0);
    var m = SettingsStore.getNumber("goalMinutes", 0);
    if (h <= 0 && m <= 0) {
      return WatchUi.loadResource(Rez.Strings.GoalOff) as Lang.String;
    }
    return h + ":" + m.format("%02d");
  }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
  private var mMenu as SettingsMenu;

  function initialize(menu as SettingsMenu) {
    Menu2InputDelegate.initialize();
    mMenu = menu;
  }

  function onSelect(item as WatchUi.MenuItem) as Void {
    var id = item.getId();
    if (id == :target) {
      var races = new WatchUi.Menu2({ :title => Rez.Strings.TargetRaceTitle });
      for (var i = 0; i < SettingsMenu.RACE_NAMES.size(); i++) {
        races.addItem(new WatchUi.MenuItem(SettingsMenu.RACE_NAMES[i] as Lang.ResourceId, null, i, null));
      }
      races.setFocus(SettingsStore.getNumber("targetRace", 7));
      WatchUi.pushView(races, new RaceListDelegate(mMenu), WatchUi.SLIDE_LEFT);
    } else if (id == :custom) {
      var km = new NumberFactory(1, 250, "%d");
      WatchUi.pushView(
        new WatchUi.Picker({
          :title => SettingsStore.pickerTitle(Rez.Strings.CustomDistanceTitle),
          :pattern => [km],
          :defaults => [km.getIndex(SettingsStore.getCustomKm())],
        }),
        new SettingsPickerDelegate(mMenu, :custom),
        WatchUi.SLIDE_LEFT
      );
    } else if (id == :goal) {
      var hours = new NumberFactory(0, 23, "%d");
      var minutes = new NumberFactory(0, 59, "%02d");
      WatchUi.pushView(
        new WatchUi.Picker({
          :title => SettingsStore.pickerTitle(Rez.Strings.GoalTitle),
          :pattern => [hours, new WatchUi.Text({ :text => ":", :font => Graphics.FONT_NUMBER_MEDIUM, :color => Graphics.COLOR_WHITE }), minutes],
          :defaults => [
            hours.getIndex(SettingsStore.getNumber("goalHours", 0)),
            0,
            minutes.getIndex(SettingsStore.getNumber("goalMinutes", 0)),
          ],
        }),
        new SettingsPickerDelegate(mMenu, :goal),
        WatchUi.SLIDE_LEFT
      );
    }
  }
}

class RaceListDelegate extends WatchUi.Menu2InputDelegate {
  private var mMenu as SettingsMenu;

  function initialize(menu as SettingsMenu) {
    Menu2InputDelegate.initialize();
    mMenu = menu;
  }

  function onSelect(item as WatchUi.MenuItem) as Void {
    SettingsStore.set("targetRace", item.getId() as Lang.Number);
    mMenu.refresh();
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
  }
}

class SettingsPickerDelegate extends WatchUi.PickerDelegate {
  private var mMenu as SettingsMenu;
  private var mWhat as Lang.Symbol;

  function initialize(menu as SettingsMenu, what as Lang.Symbol) {
    PickerDelegate.initialize();
    mMenu = menu;
    mWhat = what;
  }

  function onAccept(values as Lang.Array) as Lang.Boolean {
    if (mWhat == :custom) {
      SettingsStore.set("customDistanceKm", (values[0] as Lang.Number).toFloat());
    } else {
      // 0:00 turns the goal off (the high score becomes the goal)
      SettingsStore.set("goalHours", values[0] as Lang.Number);
      SettingsStore.set("goalMinutes", values[2] as Lang.Number);
    }
    mMenu.refresh();
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    return true;
  }

  function onCancel() as Lang.Boolean {
    WatchUi.popView(WatchUi.SLIDE_RIGHT);
    return true;
  }
}

// Whole numbers start..stop for a picker column
class NumberFactory extends WatchUi.PickerFactory {
  private var mStart as Lang.Number;
  private var mStop as Lang.Number;
  private var mFormat as Lang.String;

  function initialize(start as Lang.Number, stop as Lang.Number, format as Lang.String) {
    PickerFactory.initialize();
    mStart = start;
    mStop = stop;
    mFormat = format;
  }

  function getIndex(value as Lang.Number) as Lang.Number {
    if (value < mStart) {
      return 0;
    } else if (value > mStop) {
      return mStop - mStart;
    }
    return value - mStart;
  }

  function getSize() as Lang.Number {
    return mStop - mStart + 1;
  }

  function getValue(index as Lang.Number) as Lang.Object? {
    return mStart + index;
  }

  function getDrawable(index as Lang.Number, selected as Lang.Boolean) as WatchUi.Drawable? {
    return new WatchUi.Text({
      :text => (mStart + index).format(mFormat),
      :color => Graphics.COLOR_WHITE,
      :font => Graphics.FONT_NUMBER_MEDIUM,
      :locX => WatchUi.LAYOUT_HALIGN_CENTER,
      :locY => WatchUi.LAYOUT_VALIGN_CENTER,
    });
  }
}

// Property reads/writes for the settings screens. Writing tells the app so
// the running field picks the change up straight away.
module SettingsStore {
  function getNumber(key as Lang.String, fallback as Lang.Number) as Lang.Number {
    try {
      var v = Application.Properties.getValue(key);
      if (v instanceof Lang.Number) {
        return v;
      }
    } catch (ex) {}
    return fallback;
  }

  function getCustomKm() as Lang.Number {
    try {
      var v = Application.Properties.getValue("customDistanceKm");
      if (v instanceof Lang.Float || v instanceof Lang.Double || v instanceof Lang.Number) {
        var km = v.toNumber();
        return km < 1 ? 1 : km > 250 ? 250 : km;
      }
    } catch (ex) {}
    return 15;
  }

  function set(key as Lang.String, value as Application.PropertyValueType) as Void {
    try {
      Application.Properties.setValue(key, value);
    } catch (ex) {
      return;
    }
    var app = Application.getApp();
    if (app instanceof RaceEstimatorApp) {
      app.onSettingsChanged();
    }
  }

  function pickerTitle(id as Lang.ResourceId) as WatchUi.Text {
    return new WatchUi.Text({
      :text => WatchUi.loadResource(id) as Lang.String,
      :color => Graphics.COLOR_WHITE,
      :font => Graphics.FONT_SMALL,
      :locX => WatchUi.LAYOUT_HALIGN_CENTER,
      :locY => WatchUi.LAYOUT_VALIGN_BOTTOM,
    });
  }
}
