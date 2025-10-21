using Toybox.Graphics;
using Toybox.Math;
using Toybox.System;
using Toybox.Lang;

// Class to draw progress arcs with AMOLED burn-in protection
// This class handles all circle/arc drawing functionality that was previously in RaceEstimatorView
class ProgressArcDrawer {

  // Arc drawing constants - full circle starting from top (90°) going clockwise
  private const ARC_START_ANGLE = 90;   // Start at top (12 o'clock position)
  private const ARC_SPAN = 360;         // 360 degree span for full circle
  private const ARC_MARGIN_PIXELS = 5;

  // Arc red flash celebration when milestone reached
  private const ARC_FLASH_DURATION_MS = 3000;  // 3 seconds red flash

  // AMOLED dash pattern for burn-in protection
  private const AMOLED_DASH_DEGREES = 12;  // Each dash is 12 degrees
  private const AMOLED_GAP_DEGREES = 18;   // 18 degree gap between dashes for visibility
  private const AMOLED_DASH_ALTERNATE_MS = 200;  // Alternate dash pattern every 200ms (flash only)
  private const AMOLED_MARCH_SPEED_MS = 500;  // Clockwise march speed for normal arc (500ms per step)

  private const ARC_ANGLE_OVERFLOW_LIMIT = 10000;  // Sanity check for corrupted data

  // Arc state
  private var mArcFlashStartTimeMs as Lang.Number? = null;
  private var mDashAlternate as Lang.Boolean = false;  // Toggle for alternating dash positions (flash)
  private var mDashOffset as Lang.Number = 0;  // Clockwise marching offset in degrees (normal arc)

  private var mArcProgress as Lang.Double = 1.0d;  // 1.0 at start, 0.0 at finish
  private var mArcColor as Lang.Number = Graphics.COLOR_GREEN;
  private var mRemainingDistanceMeters as Lang.Double = 0.0d;  // For color threshold logic

  // Arc geometry cache
  private var mArcCenterX as Lang.Number = 0;
  private var mArcCenterY as Lang.Number = 0;
  private var mArcRadius as Lang.Number = 0;
  private var mArcPenWidth as Lang.Number = 8;

  // Display properties
  private var mIsAmoled as Lang.Boolean = false;
  private var mPositionOffset as Lang.Number = 0;

  // Debug logging flag (should match parent view's setting)
  private var mDebugLogging as Lang.Boolean = false;

  function initialize(isAmoled as Lang.Boolean, debugLogging as Lang.Boolean) {
    mIsAmoled = isAmoled;
    mDebugLogging = debugLogging;
    // Adaptive pen width: thinner on AMOLED to save battery
    mArcPenWidth = mIsAmoled ? 5 : 8;
  }

  // Prepare arc geometry - call this in onLayout
  function prepareGeometry(dc as Graphics.Dc, positionOffset as Lang.Number) as Void {
    var width = dc.getWidth();
    var height = dc.getHeight();

    // Arc center at display center to follow circular watch face perimeter
    mArcCenterX = width / 2;
    mArcCenterY = height / 2;
    mArcRadius = (width < height ? width : height) / 2 - ARC_MARGIN_PIXELS;

    // Defensive: Ensure radius is positive
    if (mArcRadius < 10) {
      mArcRadius = 10;
    }

    mPositionOffset = positionOffset;
  }

  // Update arc animation state - call this in compute
  function updateAnimation(timerTimeMs as Lang.Number) as Void {
    // Check if arc flash has ended
    if (mArcFlashStartTimeMs != null && timerTimeMs - mArcFlashStartTimeMs >= ARC_FLASH_DURATION_MS) {
      // Flash ended - reset arc to 0% for next milestone
      mArcFlashStartTimeMs = null;
      mDashAlternate = false;  // Reset dash alternation
    }

    // AMOLED dash animations (burn-in protection)
    if (mIsAmoled) {
      if (mArcFlashStartTimeMs != null) {
        // Flash celebration: Toggle alternating pattern every 200ms
        var flashElapsed = timerTimeMs - mArcFlashStartTimeMs;
        mDashAlternate = ((flashElapsed / AMOLED_DASH_ALTERNATE_MS) % 2) == 1;
      } else {
        // Normal operation: Clockwise marching dashes
        // Calculate offset that increases over time (marches clockwise)
        var marchCycles = (timerTimeMs / AMOLED_MARCH_SPEED_MS) % (AMOLED_DASH_DEGREES + AMOLED_GAP_DEGREES);
        mDashOffset = marchCycles.toNumber();
      }
    }
  }

  // Calculate arc progress based on milestone distance
  function calculateProgress(
    currentDistance as Lang.Double,
    distancesCm as Lang.Array<Lang.Number>,
    displayIndices as Lang.Array<Lang.Number?>,
    MILESTONE_COUNT as Lang.Number
  ) as Void {
    if (displayIndices.size() == 0 || currentDistance < 0) {
      if (mDebugLogging) { System.println("CalcArc: Empty indices or negative distance"); }
      mArcProgress = 0.0d;
      return;
    }
    var nextMilestoneIdx = displayIndices[0];
    if (mDebugLogging) { System.println("CalcArc: NextIdx=" + nextMilestoneIdx + ", CurDist=" + currentDistance); }
    if (nextMilestoneIdx == null || nextMilestoneIdx < 0 || nextMilestoneIdx >= MILESTONE_COUNT) {
      if (mDebugLogging) { System.println("CalcArc: Invalid milestone index"); }
      mArcProgress = 0.0d;
      return;
    }
    // Defensive: Ensure index is within array bounds before access
    if (nextMilestoneIdx >= distancesCm.size()) {
      mArcProgress = 0.0d;
      return;
    }
    var nextMilestoneDistanceCm = distancesCm[nextMilestoneIdx];
    var prevMilestoneDistanceCm = 0;
    if (nextMilestoneIdx > 0 && nextMilestoneIdx - 1 < distancesCm.size()) {
      prevMilestoneDistanceCm = distancesCm[nextMilestoneIdx - 1];
    }
    // Keep as Double to prevent integer overflow for ultramarathon distances
    var currentDistanceCm = currentDistance * 100.0d;
    var segmentDistanceCm = nextMilestoneDistanceCm - prevMilestoneDistanceCm;
    if (segmentDistanceCm <= 0) {
      mArcProgress = 0.0d;
      return;
    }
    var distanceIntoSegmentCm = currentDistanceCm - prevMilestoneDistanceCm.toDouble();
    var distanceRemainingCm = segmentDistanceCm.toDouble() - distanceIntoSegmentCm;

    // Store remaining distance for color threshold logic
    mRemainingDistanceMeters = distanceRemainingCm / 100.0d;

    // Progress goes from 1.0 (start) to 0.0 (finish)
    var progress = distanceRemainingCm / segmentDistanceCm.toDouble();
    if (progress < 0.0) {
      progress = 0.0d;
    }
    if (progress > 1.0) {
      progress = 1.0d;
    }
    mArcProgress = progress;

    // Update arc color based on progress
    updateArcColor();

    // Handle flash override
    if (mArcFlashStartTimeMs != null) {
      // During flash: show full red circle
      mArcProgress = 1.0d;
      mArcColor = mIsAmoled ? Graphics.COLOR_DK_RED : Graphics.COLOR_RED;
    }
  }

  // Start celebration flash
  function startFlash(timerTimeMs as Lang.Number) as Void {
    mArcFlashStartTimeMs = timerTimeMs;
  }

  // Reset arc state
  function reset() as Void {
    mArcProgress = 1.0d;  // Arc starts full at beginning
    mArcColor = Graphics.COLOR_GREEN;
    mRemainingDistanceMeters = 0.0d;
    mArcFlashStartTimeMs = null;
    mDashAlternate = false;
    mDashOffset = 0;
  }

  // Get arc color based on progress and remaining distance
  private function updateArcColor() as Void {
    // Progress is inverted: 1.0 = start (green), 0.0 = finish (red)
    // Distance-aware thresholds:
    // - If remaining > 10km: yellow at 15%, red at 5%
    // - If remaining <= 10km: yellow at 30%, red at 10%

    var yellowThreshold = 0.30d;  // Default: yellow when 30% remains
    var redThreshold = 0.10d;     // Default: red when 10% remains

    if (mRemainingDistanceMeters > 10000.0d) {  // Over 10km remaining
      yellowThreshold = 0.15d;  // Yellow at 15%
      redThreshold = 0.05d;     // Red at 5%
    }

    if (mIsAmoled) {
      // Use visible colors on AMOLED (not too dim)
      if (mArcProgress > yellowThreshold) {
        mArcColor = Graphics.COLOR_GREEN;  // Bright green for visibility
      } else if (mArcProgress > redThreshold) {
        mArcColor = Graphics.COLOR_YELLOW;  // Bright yellow
      } else {
        mArcColor = Graphics.COLOR_RED;  // Bright red
      }
    } else {
      // Full brightness on MIP displays
      if (mArcProgress > yellowThreshold) {
        mArcColor = Graphics.COLOR_GREEN;
      } else if (mArcProgress > redThreshold) {
        mArcColor = Graphics.COLOR_YELLOW;
      } else {
        mArcColor = Graphics.COLOR_RED;
      }
    }
  }

  // Draw the progress arc
  function draw(dc as Graphics.Dc) as Void {
    // Debug: Log arc state
    if (mDebugLogging) {
      System.println("=== DRAW ARC CALLED ===");
      System.println("Arc - Progress: " + mArcProgress + ", Color: " + mArcColor);
      System.println("Arc - RemainingMeters: " + mRemainingDistanceMeters);
      System.println("Arc - Geometry: CenterX=" + mArcCenterX + ", CenterY=" + mArcCenterY + ", Radius=" + mArcRadius);
      System.println("Arc - IsAmoled: " + mIsAmoled);
    }

    // Only draw if there's meaningful distance remaining (battery optimization)
    // Arc is inverted: 1.0 = full (start), 0.0 = empty (finish)
    if (mArcProgress < 0.01) {
      if (mDebugLogging) { System.println("Arc not drawn - less than 1% remaining"); }
      return;
    }

    // Apply pixel shifting on AMOLED to prevent burn-in
    var arcCenterX = mArcCenterX;
    var arcCenterY = mArcCenterY;
    if (mIsAmoled) {
      arcCenterX += mPositionOffset;
      arcCenterY += mPositionOffset;
    }

    // Use cached geometry (zero allocation)
    dc.setPenWidth(mArcPenWidth);

    // Draw progress arc only (no background arc)
    // Starts from 90° (12 o'clock) and fills clockwise based on progress
    var progressDegrees = (ARC_SPAN * mArcProgress).toNumber();
    var currentEndAngle = ARC_START_ANGLE + progressDegrees;

    // Sanity check: If angle is completely out of bounds, clamp it
    if (currentEndAngle < 0 || currentEndAngle > ARC_ANGLE_OVERFLOW_LIMIT) {
      currentEndAngle = ARC_START_ANGLE;  // Failsafe: reset to start
    }

    dc.setColor(mArcColor, Graphics.COLOR_TRANSPARENT);

    if (mDebugLogging) {
      System.println("Arc - Drawing from " + ARC_START_ANGLE + " to " + currentEndAngle + " (progressDeg=" + progressDegrees + ")");
    }

    // AMOLED burn-in protection: Draw dashed arc with different animations
    if (mIsAmoled) {
      drawAmoledDashedArc(dc, arcCenterX, arcCenterY, currentEndAngle);
    } else {
      // MIP display: Normal solid arc (no burn-in risk)
      drawSolidArc(dc, arcCenterX, arcCenterY, currentEndAngle);
    }

    // Reset pen width
    dc.setPenWidth(1);
  }

  // Draw AMOLED dashed arc with animations
  private function drawAmoledDashedArc(
    dc as Graphics.Dc,
    arcCenterX as Lang.Number,
    arcCenterY as Lang.Number,
    currentEndAngle as Lang.Number
  ) as Void {
    var dashPattern = AMOLED_DASH_DEGREES + AMOLED_GAP_DEGREES;
    var startOffset = 0;
    var maxAngle = currentEndAngle;  // Use unwrapped angle for AMOLED (e.g., 442)

    // Use alternating dashes for full/near-full circle (burn-in protection)
    // Use marching dashes for partial arcs (shows progress direction)
    if (mArcFlashStartTimeMs != null) {
      // FLASH MODE: Alternating pattern with toggle
      startOffset = mDashAlternate ? AMOLED_GAP_DEGREES : 0;
      maxAngle = ARC_START_ANGLE + 360;  // Full circle during flash
    } else if (mArcProgress >= 0.98) {
      // STATIC FULL CIRCLE MODE: Alternating pattern (no animation)
      startOffset = 0;  // Static alternating pattern
    } else {
      // NORMAL MODE: Marching dashes create clockwise motion
      startOffset = mDashOffset;
    }

    if (mDebugLogging) {
      System.println("Arc - AMOLED: maxAngle=" + maxAngle + ", startOffset=" + startOffset);
      System.println("Arc - AMOLED: mArcProgress=" + mArcProgress + ", currentEndAngle=" + currentEndAngle);
    }

    // Calculate the total arc span in degrees
    var arcSpanDegrees = maxAngle - ARC_START_ANGLE;

    // Draw dashes from start to end with the calculated offset
    var currentAngle = ARC_START_ANGLE + startOffset;
    var maxIterations = 40;  // Safety: prevent infinite loops
    var iterations = 0;

    if (mDebugLogging) {
      System.println("Arc - AMOLED Loop: startAngle=" + currentAngle + ", arcSpan=" + arcSpanDegrees + "deg");
    }

    while (currentAngle < maxAngle && iterations < maxIterations) {
      iterations++;
      var dashEnd = currentAngle + AMOLED_DASH_DEGREES;
      if (dashEnd > maxAngle) {
        dashEnd = maxAngle;  // Don't exceed progress point
      }

      // Calculate how far along the arc we are
      var distanceFromStart = currentAngle - ARC_START_ANGLE;

      // Only draw if we haven't exceeded the arc span
      if (distanceFromStart < arcSpanDegrees) {
        // Handle angle wraparound for drawing
        var drawStart = currentAngle % 360;
        var drawEnd = dashEnd % 360;

        if (mDebugLogging && iterations == 1) {
          System.println("Arc - Drawing dash #" + iterations + ": " + drawStart + " to " + drawEnd + " (dist=" + distanceFromStart + ")");
        }

        // Handle case where dash crosses 360° boundary
        if (drawEnd < drawStart && dashEnd >= 360) {
          // Draw in two parts: currentAngle to 360, and 0 to drawEnd
          dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, drawStart, 359);
          dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, 0, drawEnd);
        } else if (drawStart >= 0) {  // Only draw if start angle is valid
          dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, drawStart, drawEnd);
        }
      }

      currentAngle += dashPattern;
    }

    if (mDebugLogging) {
      System.println("Arc - AMOLED: Drew " + iterations + " dashes");
    }
  }

  // Draw solid arc for MIP displays
  private function drawSolidArc(
    dc as Graphics.Dc,
    arcCenterX as Lang.Number,
    arcCenterY as Lang.Number,
    currentEndAngle as Lang.Number
  ) as Void {
    // Wrap angle for MIP (drawArc expects 0-359)
    var mipEndAngle = currentEndAngle % 360;
    // Special case: if wrapped back to start, draw to start-1 for near-full circle
    if (mipEndAngle == ARC_START_ANGLE && currentEndAngle > ARC_START_ANGLE) {
      mipEndAngle = ARC_START_ANGLE - 1;
      if (mipEndAngle < 0) {
        mipEndAngle = 359;
      }
    }
    dc.drawArc(arcCenterX, arcCenterY, mArcRadius, Graphics.ARC_CLOCKWISE, ARC_START_ANGLE, mipEndAngle);
  }
}
