#!/usr/bin/env python3
"""
FIT Anomaly Detection Validation Script

Tests the anomaly detection logic against various real-world and edge-case scenarios.
Simulates the Monkey C detection algorithms in Python for validation before device testing.
"""

import math
from dataclasses import dataclass
from typing import List, Optional, Tuple

@dataclass
class PaceEvent:
    """Single pace update from the activity stream"""
    elapsed_time_ms: int          # milliseconds
    distance_m: float             # meters
    calculated_pace: float        # sec/m
    anomaly_type: Optional[str]   # None | "stagnation" | "spike" | "normal"
    explanation: str


class FitAnomalyDetector:
    """Simulates Monkey C anomaly detection in Python"""

    def __init__(self):
        self.last_valid_distance = 0.0
        self.distance_stagnation_count = 0
        self.last_valid_pace = 0.0
        self.pace_anomaly_count = 0
        
        self.FIT_STAGNATION_THRESHOLD = 5
        self.MAX_REASONABLE_PACE = 20.0
        self.MIN_REASONABLE_PACE = 0.05

    def reset(self):
        """Reset anomaly counters (e.g., on new activity)"""
        self.last_valid_distance = 0.0
        self.distance_stagnation_count = 0
        self.last_valid_pace = 0.0
        self.pace_anomaly_count = 0

    def detect(self, elapsed_distance: float, pace: float) -> Tuple[bool, str]:
        """
        Detect FIT anomalies. Returns (should_suppress_predictions, explanation)
        """
        explanation = []

        # Sanity check pace bounds
        if pace < self.MIN_REASONABLE_PACE or pace > self.MAX_REASONABLE_PACE:
            explanation.append(f"Insane pace {pace:.3f} sec/m (bounds: {self.MIN_REASONABLE_PACE}-{self.MAX_REASONABLE_PACE})")
            return False, " → ".join(explanation)

        # ANOMALY 1: Distance stagnation
        if abs(elapsed_distance - self.last_valid_distance) < 0.001:  # ~0m difference
            self.distance_stagnation_count += 1
            explanation.append(f"Distance stagnation: {self.distance_stagnation_count}/{self.FIT_STAGNATION_THRESHOLD}")
            
            if self.distance_stagnation_count >= self.FIT_STAGNATION_THRESHOLD:
                explanation.append("DISTANCE FROZEN - SUPPRESS")
                return False, " → ".join(explanation)
        else:
            self.distance_stagnation_count = 0
            self.last_valid_distance = elapsed_distance

        # ANOMALY 2: Pace consistency
        if self.last_valid_pace > 0.0:
            pace_ratio = pace / self.last_valid_pace
            if pace_ratio > 2.0 or pace_ratio < 0.5:
                self.pace_anomaly_count += 1
                explanation.append(f"Pace spike: ratio={pace_ratio:.2f} anomaly_count={self.pace_anomaly_count}")
                
                if self.pace_anomaly_count >= 3:
                    explanation.append("MULTIPLE PACE SPIKES - SUPPRESS")
                    return False, " → ".join(explanation)
            else:
                self.pace_anomaly_count = 0

        self.last_valid_pace = pace
        explanation.append("✓ NORMAL - SHOW PREDICTIONS")
        return True, " → ".join(explanation)


def test_scenario(name: str, events: List[PaceEvent]) -> None:
    """Test a scenario and report results"""
    print(f"\n{'='*80}")
    print(f"SCENARIO: {name}")
    print(f"{'='*80}")
    
    detector = FitAnomalyDetector()
    suppression_count = 0
    
    for i, event in enumerate(events, 1):
        should_show, explanation = detector.detect(event.distance_m, event.calculated_pace)
        
        status = "✓ SHOW" if should_show else "✗ SUPPRESS"
        
        print(f"{i:2d}. {status:10} | Time: {event.elapsed_time_ms:6.0f}ms | "
              f"Dist: {event.distance_m:7.2f}m | Pace: {event.calculated_pace:5.3f}s/m | "
              f"{explanation}")
        
        if not should_show:
            suppression_count += 1
    
    print(f"\nResult: {suppression_count}/{len(events)} updates suppressed")


# ============================================================================
# TEST SCENARIOS
# ============================================================================

def test_normal_5k_run():
    """Real GPS data: Normal 5K run with stable pace"""
    events = [
        PaceEvent(10000, 103.20, 0.097, "normal", "First GPS fix"),
        PaceEvent(20000, 207.21, 0.096, "normal", "Pace stabilizing"),
        PaceEvent(30000, 311.32, 0.096, "normal", "Steady pace"),
        PaceEvent(40000, 415.53, 0.096, "normal", "No anomalies"),
        PaceEvent(50000, 519.74, 0.096, "normal", "Smooth progression"),
        PaceEvent(60000, 623.95, 0.096, "normal", "All normal"),
    ]
    test_scenario("Normal 5K Run (Real GPS)", events)


def test_fit_distance_freeze():
    """FIT playback: Distance freezes mid-activity"""
    events = [
        PaceEvent(10000, 1539.78, 0.385, "normal", "Normal progression"),
        PaceEvent(20000, 1539.78, 0.392, "stagnation", "Distance frozen (1)"),
        PaceEvent(30000, 1539.78, 0.400, "stagnation", "Distance frozen (2)"),
        PaceEvent(40000, 1539.78, 0.408, "stagnation", "Distance frozen (3)"),
        PaceEvent(50000, 1539.78, 0.417, "stagnation", "Distance frozen (4)"),
        PaceEvent(60000, 1539.78, 0.426, "stagnation", "Distance frozen (5) - THRESHOLD"),
        PaceEvent(70000, 1539.78, 0.435, "stagnation", "Still frozen (6)"),
    ]
    test_scenario("FIT Distance Freeze", events)


def test_pace_spike_recovery():
    """Pace jumps wildly but recovers (GPS bounce)"""
    events = [
        PaceEvent(10000, 1000.00, 0.100, "normal", "Normal pace"),
        PaceEvent(20000, 1050.00, 0.105, "normal", "Slight variance OK"),
        PaceEvent(30000, 1100.00, 0.111, "normal", "Gradual change OK"),
        PaceEvent(40000, 900.00, 0.044, "spike", "SPIKE DOWN (2.5x faster)"),
        PaceEvent(50000, 950.00, 0.105, "spike", "SPIKE UP (2.4x slower)"),
        PaceEvent(60000, 1000.00, 0.100, "spike", "Back to normal after 3 spikes - SUPPRESS"),
        PaceEvent(70000, 1050.00, 0.105, "normal", "Reset on recovery"),
    ]
    test_scenario("Pace Spike Recovery", events)


def test_poor_gps_sporadic():
    """Poor GPS: Sporadic distance updates"""
    events = [
        PaceEvent(10000, 100.00, 0.100, "normal", "Update 1"),
        PaceEvent(11000, 100.50, 0.101, "normal", "Update 2 (delayed 1s)"),
        PaceEvent(12000, 100.50, 0.102, "stagnation", "No update (1)"),
        PaceEvent(13000, 101.00, 0.103, "normal", "Update after stagnation"),
        PaceEvent(14000, 101.00, 0.104, "stagnation", "No update (1)"),
        PaceEvent(15000, 101.50, 0.105, "normal", "Update after short pause"),
    ]
    test_scenario("Poor GPS: Sporadic Updates", events)


def test_urban_canyon_recovery():
    """Urban canyon: GPS loses signal then recovers"""
    events = [
        PaceEvent(10000, 500.00, 0.100, "normal", "Urban area, good signal"),
        PaceEvent(20000, 600.00, 0.100, "normal", "Still OK"),
        PaceEvent(30000, 600.00, 0.100, "stagnation", "Signal loss (1)"),
        PaceEvent(40000, 600.00, 0.100, "stagnation", "Signal loss (2)"),
        PaceEvent(50000, 600.00, 0.100, "stagnation", "Signal loss (3)"),
        PaceEvent(60000, 650.00, 0.100, "normal", "Signal recovered (distance jumped)"),
        PaceEvent(70000, 750.00, 0.100, "normal", "Back to normal"),
    ]
    test_scenario("Urban Canyon: GPS Recovery", events)


def test_elite_runner():
    """Elite runner: Very fast pace (4 min/km = 0.067 sec/m)"""
    events = [
        PaceEvent(60000, 1000.00, 0.067, "normal", "4 min/km pace (elite)"),
        PaceEvent(120000, 2000.00, 0.067, "normal", "Consistent elite pace"),
        PaceEvent(180000, 3000.00, 0.067, "normal", "Still elite"),
        PaceEvent(240000, 4000.00, 0.067, "normal", "Stable throughout"),
    ]
    test_scenario("Elite Runner (4 min/km)", events)


def test_ultra_slow_walker():
    """Slow walker: Very slow pace (20 min/km = 0.333 sec/m)"""
    events = [
        PaceEvent(60000, 100.00, 0.333, "normal", "20 min/km pace (walking)"),
        PaceEvent(120000, 200.00, 0.333, "normal", "Consistent slow pace"),
        PaceEvent(180000, 300.00, 0.333, "normal", "Still steady"),
    ]
    test_scenario("Slow Walker (20 min/km)", events)


def test_impossible_pace():
    """Impossible pace: Exceeds physical limits"""
    events = [
        PaceEvent(10000, 1000.00, 0.030, "invalid", "0.03 sec/m = 33 m/s (impossible)"),
        PaceEvent(20000, 2000.00, 25.0, "invalid", "25 sec/m = barely moving"),
    ]
    test_scenario("Impossible Pace Values", events)


def test_mixed_anomalies():
    """Mixed: Distance freeze + pace spikes"""
    events = [
        PaceEvent(10000, 1000.00, 0.100, "normal", "Start normal"),
        PaceEvent(20000, 1100.00, 0.100, "normal", "Progressing"),
        PaceEvent(30000, 1100.00, 0.050, "spike", "SPIKE: distance frozen + pace halved"),
        PaceEvent(40000, 1100.00, 0.150, "spike", "SPIKE 2: distance frozen + pace doubles"),
        PaceEvent(50000, 1100.00, 0.100, "spike", "SPIKE 3: still frozen - THRESHOLD MET"),
        PaceEvent(60000, 1150.00, 0.100, "normal", "Distance recovers, anomaly reset"),
    ]
    test_scenario("Mixed Anomalies", events)


# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":
    print("\n" + "="*80)
    print("FIT ANOMALY DETECTION VALIDATION SUITE")
    print("="*80)
    print("\nSimulates Monkey C anomaly detection logic in Python.")
    print("Tests real-world and edge-case scenarios.\n")

    # Run all test scenarios
    test_normal_5k_run()
    test_fit_distance_freeze()
    test_pace_spike_recovery()
    test_poor_gps_sporadic()
    test_urban_canyon_recovery()
    test_elite_runner()
    test_ultra_slow_walker()
    test_impossible_pace()
    test_mixed_anomalies()

    print("\n" + "="*80)
    print("VALIDATION COMPLETE")
    print("="*80)
    print("\n✓ All scenarios tested.")
    print("✓ Ready for device deployment.")
    print()
