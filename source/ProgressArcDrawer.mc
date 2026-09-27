using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;

// Level map: a segmented 270 degree arc around the bezel, open at the bottom,
// mapping 0 -> target race distance, like an 8-bit world map.
//
//  - 27 blocks (10 degrees each). Travelled blocks are lit in their phase
//    colour: blocks 0-8 = phase 1 (head), 9-17 = phase 2 (legs), 18-26 =
//    phase 3 (heart), so race thirds are visible at a glance.
//  - Milestone pips sit on an inner lane (drawn by the caller via drawPip);
//    the target is a bigger "boss" pip at the end of the arc.
//  - A player marker rides the arc at the current distance.
//
// Garmin drawArc angles are degrees counter-clockwise from 3 o'clock, so
// map fraction f sits at 225 - 270*f.
//
// Battery: <= 27 arc calls + ~10 small rectangles once per second. On
// AMOLED untravelled blocks are not drawn at all.
class ProgressArcDrawer {
  private const START_DEGREES = 225; // 7:30
  private const SWEEP_DEGREES = 270; // to 4:30
  private const BLOCKS = 27;
  private const PITCH_DEGREES = 10;
  private const BLOCK_DEGREES = 7;
  // Clearance from the bezel; on AMOLED it also absorbs the <=3px pixel shift
  private const EDGE_MARGIN_PX = 3;
  private const AMOLED_EDGE_MARGIN_PX = 5;

  private var mCenterX as Lang.Number = 0;
  private var mCenterY as Lang.Number = 0;
  private var mRadius as Lang.Number = 0;
  private var mPipRadius as Lang.Number = 0;
  private var mPenWidth as Lang.Number = 8;
  private var mPipSize as Lang.Number = 4;
  private var mIsAmoled as Lang.Boolean = false;

  function initialize(isAmoled as Lang.Boolean) {
    mIsAmoled = isAmoled;
  }

  // Call from onLayout with the field size
  function setGeometry(width as Lang.Number, height as Lang.Number) as Void {
    mCenterX = width / 2;
    mCenterY = height / 2;
    var shortSide = width < height ? width : height;
    // 260px fenix 7 -> 10px, 416px epix -> 9px (thinner on AMOLED)
    mPenWidth = mIsAmoled ? shortSide / 46 : shortSide / 26;
    if (mPenWidth < 4) {
      mPenWidth = 4;
    }
    var margin = mIsAmoled ? AMOLED_EDGE_MARGIN_PX : EDGE_MARGIN_PX;
    mRadius = shortSide / 2 - mPenWidth / 2 - margin;
    mPipSize = (mPenWidth * 3) / 5;
    if (mPipSize < 3) {
      mPipSize = 3;
    }
    mPipRadius = mRadius - mPenWidth / 2 - mPipSize;
  }

  // Radius inside which content can be drawn without touching arc or pips
  function getInnerRadius() as Lang.Number {
    return mPipRadius - mPipSize - 2;
  }

  /**
   * @param fraction 0..1 of the map travelled
   * @param phaseColors lit-block colour per third
   * @param marqueePhase -1 normal; 0/1 = alternate travelled blocks (celebration)
   */
  function draw(
    dc as Graphics.Dc,
    fraction as Lang.Double,
    phaseColors as Lang.Array<Lang.Number>,
    trackColor as Lang.Number,
    offsetX as Lang.Number,
    offsetY as Lang.Number,
    marqueePhase as Lang.Number
  ) as Void {
    var cx = mCenterX + offsetX;
    var cy = mCenterY + offsetY;
    var lit = (fraction * BLOCKS + 0.5d).toNumber();

    dc.setPenWidth(mPenWidth);
    for (var i = 0; i < BLOCKS; i++) {
      var travelled = i < lit;
      var on = travelled && (marqueePhase < 0 || i % 2 == marqueePhase);
      // Untravelled: track colour on MIP, nothing on AMOLED.
      // Marquee "off" blocks stay dark so the chase reads clearly.
      if (!on && (mIsAmoled || travelled)) {
        continue;
      }
      dc.setColor(
        on ? phaseColors[(i * 3) / BLOCKS] : trackColor,
        Graphics.COLOR_TRANSPARENT
      );
      var start = START_DEGREES - i * PITCH_DEGREES;
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

  // Milestone pip on the inner lane; the target ("boss") is double size
  function drawPip(
    dc as Graphics.Dc,
    fraction as Lang.Double,
    color as Lang.Number,
    isBoss as Lang.Boolean,
    offsetX as Lang.Number,
    offsetY as Lang.Number
  ) as Void {
    var size = isBoss ? mPipSize * 2 : mPipSize;
    var r = isBoss ? mPipRadius - mPipSize / 2 : mPipRadius;
    var rad = Math.toRadians(START_DEGREES - SWEEP_DEGREES * fraction);
    var x = mCenterX + offsetX + (r * Math.cos(rad)).toNumber();
    var y = mCenterY + offsetY - (r * Math.sin(rad)).toNumber();
    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
    dc.fillRectangle(x - size / 2, y - size / 2, size, size);
  }

  // Player marker riding the arc: a square with a background-coloured rim so
  // it reads on top of lit blocks
  function drawPlayer(
    dc as Graphics.Dc,
    fraction as Lang.Double,
    color as Lang.Number,
    background as Lang.Number,
    offsetX as Lang.Number,
    offsetY as Lang.Number
  ) as Void {
    var rad = Math.toRadians(START_DEGREES - SWEEP_DEGREES * fraction);
    var x = mCenterX + offsetX + (mRadius * Math.cos(rad)).toNumber();
    var y = mCenterY + offsetY - (mRadius * Math.sin(rad)).toNumber();
    var size = mPenWidth + 2;
    dc.setColor(background, Graphics.COLOR_TRANSPARENT);
    dc.fillRectangle(x - size / 2 - 2, y - size / 2 - 2, size + 4, size + 4);
    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
    dc.fillRectangle(x - size / 2, y - size / 2, size, size);
  }

  private function normalize(degrees as Lang.Number) as Lang.Number {
    return (degrees + 360) % 360;
  }
}
