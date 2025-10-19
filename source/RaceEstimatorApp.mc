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

  //! Return the initial view of your application here
  function getInitialView() {
    mView = new RaceEstimatorView();
    return [mView];
  }
}
