using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

class RuckApp extends Application.AppBase {
  private var mView as RuckView?;

  function initialize() {
    AppBase.initialize();
  }

  function onStart(state as Lang.Dictionary?) as Void {}

  function onStop(state as Lang.Dictionary?) as Void {}

  //! Pack weight / terrain changed in Garmin Connect or Express
  function onSettingsChanged() as Void {
    if (mView != null) {
      mView.loadSettings();
    }
    WatchUi.requestUpdate();
  }

  function getInitialView() {
    mView = new RuckView();
    return [mView];
  }

  //! The single data field instance, for RuckViewTest (debug builds only):
  //! a second RuckView can't register the same FIT fields
  (:debug)
  function testView() as RuckView {
    if (mView == null) {
      mView = new RuckView();
    }
    return mView as RuckView;
  }

  //! On-watch settings, from the activity menu (see RuckSettings)
  function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
    return [RuckSettings.buildMenu(), new RuckMenuDelegate()];
  }
}
