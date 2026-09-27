using Toybox.Graphics;
using Toybox.Lang;

// Segmented 270 degree gauge around the bezel, open at the bottom, like an
// arcade energy meter. Shows distance covered in the current segment
// (previous -> next milestone); fills clockwise from 7:30 over 12 to 4:30.
//
// Garmin drawArc angles are degrees counter-clockwise from 3 o'clock, so
// block i spans [225 - i*PITCH, 225 - i*PITCH - BLOCK].
//
// Battery: at most SEGMENTS arc calls once per second. On AMOLED empty blocks
// are not drawn at all (and lit blocks have gaps), keeping lit pixels low.
class ProgressArcDrawer {
  private const GAUGE_START_DEGREES = 225; // 7:30
  private const SEGMENTS = 18;
  private const PITCH_DEGREES = 15; // 18 x 15 = 270
  private const BLOCK_DEGREES = 11; // lit part of each segment
  // Clearance from the bezel; on AMOLED it also absorbs the <=3px pixel shift
  private const EDGE_MARGIN_PX = 3;
  private const AMOLED_EDGE_MARGIN_PX = 5;

  private var mCenterX as Lang.Number = 0;
  private var mCenterY as Lang.Number = 0;
  private var mRadius as Lang.Number = 0;
  private var mPenWidth as Lang.Number = 8;
  private var mIsAmoled as Lang.Boolean = false;

  function initialize(isAmoled as Lang.Boolean) {
    mIsAmoled = isAmoled;
  }

  // Call from onLayout with the field size
  function setGeometry(width as Lang.Number, height as Lang.Number) as Void {
    mCenterX = width / 2;
    mCenterY = height / 2;
    var shortSide = width < height ? width : height;
    // 260px fenix 7 -> 10px, 416px epix -> 10px (thinner on AMOLED)
    mPenWidth = mIsAmoled ? shortSide / 42 : shortSide / 26;
    if (mPenWidth < 4) {
      mPenWidth = 4;
    }
    var margin = mIsAmoled ? AMOLED_EDGE_MARGIN_PX : EDGE_MARGIN_PX;
    mRadius = shortSide / 2 - mPenWidth / 2 - margin;
  }

  // Radius inside which content can be drawn without touching the gauge
  function getInnerRadius() as Lang.Number {
    return mRadius - mPenWidth / 2;
  }

  // progress: 0.0 (just passed previous milestone) .. 1.0 (at next milestone)
  // marqueePhase: -1 for normal, 0/1 to light alternate segments (arcade
  // chase lights while celebrating; flipped once a second by the caller)
  function draw(
    dc as Graphics.Dc,
    progress as Lang.Double,
    progressColor as Lang.Number,
    trackColor as Lang.Number,
    offsetX as Lang.Number,
    offsetY as Lang.Number,
    marqueePhase as Lang.Number
  ) as Void {
    var cx = mCenterX + offsetX;
    var cy = mCenterY + offsetY;
    var lit = (progress * SEGMENTS).toNumber();

    dc.setPenWidth(mPenWidth);
    for (var i = 0; i < SEGMENTS; i++) {
      var on = marqueePhase >= 0 ? i % 2 == marqueePhase : i < lit;
      // AMOLED: unlit segments are not drawn at all
      if (!on && mIsAmoled) {
        continue;
      }
      dc.setColor(on ? progressColor : trackColor, Graphics.COLOR_TRANSPARENT);
      var start = GAUGE_START_DEGREES - i * PITCH_DEGREES;
      dc.drawArc(
        cx,
        cy,
        mRadius,
        Graphics.ARC_CLOCKWISE,
        normalize(start),
        normalize(start - BLOCK_DEGREES)
      );
    }
    dc.setPenWidth(1);
  }

  private function normalize(degrees as Lang.Number) as Lang.Number {
    return (degrees + 360) % 360;
  }
}
