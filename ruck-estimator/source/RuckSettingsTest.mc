using Toybox.Application;
using Toybox.Lang;
using Toybox.Test;

// What the on-watch settings menu saves (the menu screens themselves are
// checked visually; these cover the values behind them)
(:test)
module RuckSettingsTest {
  function pack() as Lang.Float {
    return RuckSettings.getFloat("packWeight", -1.0);
  }

  // 20 kg -> lbs = 44 lbs (same pack), and back to kg = 20 kg
  (:test)
  function weightUnitSwitchConvertsPack(logger as Test.Logger) as Lang.Boolean {
    Application.Properties.setValue("weightUnit", 0);
    Application.Properties.setValue("packWeight", 20.0);
    RuckSettings.setWeightUnit(1);
    var lb = pack();
    RuckSettings.setWeightUnit(0);
    var kg = pack();
    logger.debug("20 kg -> " + lb + " lbs -> " + kg + " kg");
    return lb == 44.0 && kg == 20.0 &&
      RuckSettings.getNumber("weightUnit", -1) == 0;
  }

  // Re-selecting the current weight unit leaves the pack alone
  (:test)
  function sameWeightUnitKeepsPack(logger as Test.Logger) as Lang.Boolean {
    Application.Properties.setValue("weightUnit", 0);
    Application.Properties.setValue("packWeight", 17.5);
    RuckSettings.setWeightUnit(0);
    var a = pack();
    Application.Properties.setValue("weightUnit", 1);
    Application.Properties.setValue("packWeight", 35.0);
    RuckSettings.setWeightUnit(1);
    var b = pack();
    return a == 17.5 && b == 35.0;
  }

  // lb -> kg rounds to the kg picker's 0.5 step
  (:test)
  function lbToKgRoundsToHalf(logger as Test.Logger) as Lang.Boolean {
    Application.Properties.setValue("weightUnit", 1);
    Application.Properties.setValue("packWeight", 30.0); // 13.6 kg
    RuckSettings.setWeightUnit(0);
    logger.debug("30 lb -> " + pack() + " kg");
    return pack() == 13.5;
  }

  // Weight editor: snaps to its step, clamps to 0..max, accelerates
  (:test)
  function weightEditor(logger as Test.Logger) as Lang.Boolean {
    var kg = new RuckWeightView(false, 20.3); // snaps to 20.5
    var start = kg.getValue();
    kg.adjust(1);
    var up = kg.getValue();
    var lb = new RuckWeightView(true, 500.0); // clamps to 220
    var top = lb.getValue();
    lb.adjust(1);
    var still = lb.getValue();
    var zero = new RuckWeightView(true, 0.0);
    zero.adjust(-1);
    // five quick presses: 1+1+1+1+5 steps
    var fast = new RuckWeightView(false, 10.0);
    for (var i = 0; i < 5; i++) {
      fast.adjust(1);
    }
    logger.debug("start=" + start + " up=" + up + " top=" + top + " fast=" + fast.getValue());
    return start == 20.5 && up == 21.0 && top == 220.0 && still == 220.0 &&
      zero.getValue() == 0.0 && fast.getValue() == 14.5;
  }

  (:test)
  function subLabels(logger as Test.Logger) as Lang.Boolean {
    Application.Properties.setValue("weightUnit", 0);
    Application.Properties.setValue("packWeight", 7.5);
    var a = RuckSettings.packSubLabel();
    Application.Properties.setValue("weightUnit", 1);
    Application.Properties.setValue("packWeight", 44.0);
    var b = RuckSettings.packSubLabel();
    logger.debug(a + " / " + b);
    return a.equals("7.5 kg") && b.equals("44 lbs");
  }
}
