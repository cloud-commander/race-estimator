#!/usr/bin/env python3
"""
FIT File Analyzer for Race Estimator Data Field
Extracts timer_time and distance to verify calculations

Usage:
    pip install fitparse
    python analyze_fit.py path/to/activity.fit
"""

import sys
from datetime import datetime

try:
    from fitparse import FitFile
except ImportError:
    print("ERROR: fitparse not installed")
    print("Install with: pip install fitparse")
    sys.exit(1)


def analyze_fit_file(fit_path):
    """Analyze FIT file and extract timer_time, distance, and speed data."""
    
    print(f"\n{'='*80}")
    print(f"FIT File Analysis: {fit_path}")
    print(f"{'='*80}\n")
    
    try:
        fitfile = FitFile(fit_path)
    except Exception as e:
        print(f"ERROR: Could not open FIT file: {e}")
        return
    
    records = []
    session_data = {}
    
    # Extract record messages (data points during activity)
    for record in fitfile.get_messages('record'):
        data_point = {}
        
        for field in record:
            if field.name == 'timestamp':
                data_point['timestamp'] = field.value
            elif field.name == 'timer_time':
                # timer_time is in milliseconds in FIT files (converted from seconds)
                data_point['timer_time_ms'] = field.value
                data_point['timer_time_cs'] = field.value / 10 if field.value else 0
            elif field.name == 'distance':
                data_point['distance_m'] = field.value
            elif field.name == 'speed':
                data_point['speed_mps'] = field.value
            elif field.name == 'position_lat':
                data_point['lat'] = field.value
            elif field.name == 'position_long':
                data_point['lon'] = field.value
        
        if 'timer_time_ms' in data_point and 'distance_m' in data_point:
            records.append(data_point)
    
    # Extract session summary
    for session in fitfile.get_messages('session'):
        for field in session:
            if field.name == 'total_timer_time':
                session_data['total_timer_time_s'] = field.value
            elif field.name == 'total_distance':
                session_data['total_distance_m'] = field.value
            elif field.name == 'avg_speed':
                session_data['avg_speed_mps'] = field.value
    
    if not records:
        print("ERROR: No record data found in FIT file")
        return
    
    # Print session summary
    print("SESSION SUMMARY:")
    print("-" * 80)
    if session_data:
        if 'total_timer_time_s' in session_data:
            total_time = session_data['total_timer_time_s']
            print(f"Total Time:     {total_time:.1f}s ({total_time/60:.1f} min)")
        if 'total_distance_m' in session_data:
            total_dist = session_data['total_distance_m']
            print(f"Total Distance: {total_dist:.1f}m ({total_dist/1000:.2f} km)")
        if 'avg_speed_mps' in session_data:
            avg_speed = session_data['avg_speed_mps']
            pace_min_per_km = (1000.0 / avg_speed / 60.0) if avg_speed > 0 else 0
            print(f"Avg Speed:      {avg_speed:.2f} m/s ({pace_min_per_km:.2f} min/km)")
    print()
    
    # Print detailed records
    print("DETAILED RECORDS:")
    print("-" * 80)
    print(f"{'Time':<12} {'Timer(cs)':<12} {'Dist(m)':<12} {'Pace(s/m)':<12} {'5K Est(s)':<12}")
    print("-" * 80)
    
    start_time = records[0]['timestamp'] if records else None
    
    for i, rec in enumerate(records):
        timer_cs = rec.get('timer_time_cs', 0)
        timer_ms = rec.get('timer_time_ms', 0)
        distance_m = rec.get('distance_m', 0)
        
        # Calculate current pace (sec/meter)
        if distance_m > 0:
            pace_sec_per_m = (timer_ms / 1000.0) / distance_m
        else:
            pace_sec_per_m = 0
        
        # Calculate 5K estimate (same formula as RaceEstimatorView.mc)
        if distance_m > 100 and 0.05 <= pace_sec_per_m <= 20.0:
            remaining_5k = 5000 - distance_m
            if remaining_5k > 0:
                est_5k_sec = remaining_5k * pace_sec_per_m
            else:
                est_5k_sec = 0
        else:
            est_5k_sec = 0
        
        # Format timestamp
        if start_time and 'timestamp' in rec:
            elapsed = (rec['timestamp'] - start_time).total_seconds()
            time_str = f"{int(elapsed//60):02d}:{int(elapsed%60):02d}"
        else:
            time_str = "??:??"
        
        # Print every 10th record (or first/last) to avoid spam
        if i == 0 or i == len(records) - 1 or i % 10 == 0 or timer_cs in [22964, 23964, 24963, 36155]:
            print(f"{time_str:<12} {timer_cs:<12.0f} {distance_m:<12.1f} {pace_sec_per_m:<12.4f} {est_5k_sec:<12.0f}")
    
    print("-" * 80)
    print(f"Total records: {len(records)}")
    
    # Highlight key timestamps from your log
    print("\n" + "="*80)
    print("KEY TIMESTAMPS FROM YOUR LOG:")
    print("="*80)
    
    key_times = [22964, 23964, 24963, 36155]
    for key_time in key_times:
        matching = [r for r in records if abs(r.get('timer_time_cs', 0) - key_time) < 50]
        if matching:
            rec = matching[0]
            timer_cs = rec.get('timer_time_cs', 0)
            timer_ms = rec.get('timer_time_ms', 0)
            distance_m = rec.get('distance_m', 0)
            
            if distance_m > 0:
                pace_sec_per_m = (timer_ms / 1000.0) / distance_m
                remaining_5k = 5000 - distance_m
                est_5k_sec = remaining_5k * pace_sec_per_m if remaining_5k > 0 else 0
                est_5k_min = est_5k_sec / 60.0
                
                print(f"\nTime {int(timer_cs/100)}:{int((timer_cs%100)/10):02d}:")
                print(f"  Timer:        {timer_cs:.0f} cs = {timer_ms:.0f} ms = {timer_ms/1000:.1f} s")
                print(f"  Distance:     {distance_m:.1f} m")
                print(f"  Pace:         {pace_sec_per_m:.6f} sec/m = {pace_sec_per_m*1000:.2f} sec/km")
                print(f"  5K Remaining: {remaining_5k:.1f} m")
                print(f"  5K Estimate:  {est_5k_sec:.0f} s = {int(est_5k_min)}:{int((est_5k_sec%60))}")
    
    print("\n" + "="*80)
    print("VERIFICATION:")
    print("="*80)
    print("Compare the '5K Estimate' values above with your app's console output.")
    print("They should match if the calculations are correct.")
    print("="*80 + "\n")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python analyze_fit.py path/to/activity.fit")
        sys.exit(1)
    
    fit_path = sys.argv[1]
    analyze_fit_file(fit_path)
