using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

class RaceEstimatorApp extends Application.AppBase {
  private var mView as RaceEstimatorView?;

  function initialize() {
    AppBase.initialize();
  }

  // onStart() is called on application start up
  function onStart(state as Lang.Dictionary?) as Void {}

  // onStop() is called when your application is exiting
  function onStop(state as Lang.Dictionary?) as Void {}

  // Settings changed in Garmin Connect
  function onSettingsChanged() as Void {
    if (mView != null) {
      mView.loadSettings();
    }
    WatchUi.requestUpdate();
  }

  // On-watch settings (activity menu > Data Screens > this field), see
  // SettingsMenu
  function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
    var menu = new SettingsMenu();
    return [menu, new SettingsMenuDelegate(menu)];
  }

  //! Return the initial view of your application here
  function getInitialView() {
    var view = new RaceEstimatorView();
    view.createFitFields();
    mView = view;
    return [view];
  }
}
