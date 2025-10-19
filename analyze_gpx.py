#!/usr/bin/env python3
"""
GPX File Analyzer for Race Estimator Data Field
Extracts timestamps, coordinates, and calculates cumulative distance and pace

Usage:
    python analyze_gpx.py path/to/activity.gpx
"""

import sys
import xml.etree.ElementTree as ET
from datetime import datetime
from math import radians, cos, sin, asin, sqrt


def haversine(lon1, lat1, lon2, lat2):
    """
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees).
    Returns distance in meters.
    """
    # Convert decimal degrees to radians 
    lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
    
    # Haversine formula 
    dlon = lon2 - lon1 
    dlat = lat2 - lat1 
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * asin(sqrt(a)) 
    
    # Radius of earth in meters
    r = 6371000
    return c * r


def parse_gpx(gpx_path):
    """Parse GPX file and extract trackpoints with distance calculation."""
    
    print(f"\n{'='*80}")
    print(f"GPX File Analysis: {gpx_path}")
    print(f"{'='*80}\n")
    
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
    except Exception as e:
        print(f"ERROR: Could not parse GPX file: {e}")
        return
    
    # Define XML namespaces
    ns = {
        'gpx': 'http://www.topografix.com/GPX/1/1',
        'ns3': 'http://www.garmin.com/xmlschemas/TrackPointExtension/v1'
    }
    
    trackpoints = []
    cumulative_distance = 0.0
    prev_lat = None
    prev_lon = None
    start_time = None
    
    # Extract all trackpoints
    for trkpt in root.findall('.//gpx:trkpt', ns):
        lat = float(trkpt.get('lat'))
        lon = float(trkpt.get('lon'))
        
        # Get timestamp
        time_elem = trkpt.find('gpx:time', ns)
        if time_elem is not None:
            timestamp = datetime.fromisoformat(time_elem.text.replace('Z', '+00:00'))
        else:
            timestamp = None
        
        # Get elevation
        ele_elem = trkpt.find('gpx:ele', ns)
        elevation = float(ele_elem.text) if ele_elem is not None else 0.0
        
        # Get heart rate and cadence if available
        hr_elem = trkpt.find('.//ns3:hr', ns)
        cad_elem = trkpt.find('.//ns3:cad', ns)
        heart_rate = int(hr_elem.text) if hr_elem is not None else None
        cadence = int(cad_elem.text) if cad_elem is not None else None
        
        # Calculate distance from previous point
        if prev_lat is not None and prev_lon is not None:
            segment_distance = haversine(prev_lon, prev_lat, lon, lat)
            cumulative_distance += segment_distance
        
        # Calculate elapsed time
        if start_time is None and timestamp is not None:
            start_time = timestamp
        
        elapsed_seconds = (timestamp - start_time).total_seconds() if (timestamp and start_time) else 0
        
        trackpoints.append({
            'timestamp': timestamp,
            'elapsed_sec': elapsed_seconds,
            'elapsed_cs': elapsed_seconds * 100,  # Convert to centiseconds (Garmin format)
            'lat': lat,
            'lon': lon,
            'elevation': elevation,
            'distance_m': cumulative_distance,
            'heart_rate': heart_rate,
            'cadence': cadence
        })
        
        prev_lat = lat
        prev_lon = lon
    
    if not trackpoints:
        print("ERROR: No trackpoints found in GPX file")
        return
    
    # Print summary
    last_point = trackpoints[-1]
    print("ACTIVITY SUMMARY:")
    print("-" * 80)
    print(f"Activity Date:  {trackpoints[0]['timestamp'].strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Total Time:     {last_point['elapsed_sec']:.1f}s ({last_point['elapsed_sec']/60:.1f} min)")
    print(f"Total Distance: {last_point['distance_m']:.1f}m ({last_point['distance_m']/1000:.2f} km)")
    if last_point['distance_m'] > 0:
        avg_pace_sec_per_m = last_point['elapsed_sec'] / last_point['distance_m']
        avg_pace_min_per_km = avg_pace_sec_per_m * 1000 / 60
        print(f"Avg Pace:       {avg_pace_sec_per_m:.6f} sec/m ({avg_pace_min_per_km:.2f} min/km)")
    print(f"Total Points:   {len(trackpoints)}")
    print()
    
    # Print detailed analysis
    print("RACE ESTIMATOR CALCULATIONS:")
    print("-" * 80)
    print(f"{'Time':<10} {'Timer(cs)':<12} {'Dist(m)':<12} {'Pace(s/m)':<12} {'5K Est':<12} {'Disp':<8}")
    print("-" * 80)
    
    # Sample key points throughout the activity
    sample_indices = [0]  # Start
    
    # Add points every 100 meters after 100m warmup
    for i, pt in enumerate(trackpoints):
        if pt['distance_m'] >= 100 and int(pt['distance_m']) % 100 == 0:
            sample_indices.append(i)
    
    # Add last point
    sample_indices.append(len(trackpoints) - 1)
    
    # Remove duplicates and sort
    sample_indices = sorted(set(sample_indices))
    
    for idx in sample_indices:
        pt = trackpoints[idx]
        
        elapsed_min = int(pt['elapsed_sec'] // 60)
        elapsed_sec = int(pt['elapsed_sec'] % 60)
        time_str = f"{elapsed_min:02d}:{elapsed_sec:02d}"
        
        # Calculate current pace (sec/meter) - same as RaceEstimatorView.mc
        if pt['distance_m'] > 0:
            pace_sec_per_m = pt['elapsed_sec'] / pt['distance_m']
        else:
            pace_sec_per_m = 0
        
        # Calculate 5K estimate - EXACT same logic as your app
        min_distance_reached = pt['distance_m'] >= 100  # MIN_PREDICTION_DISTANCE
        pace_is_sane = 0.05 <= pace_sec_per_m <= 20.0
        
        if min_distance_reached and pace_is_sane:
            remaining_5k = 5000 - pt['distance_m']
            if remaining_5k > 0:
                est_5k_sec = remaining_5k * pace_sec_per_m
                est_5k_min = int(est_5k_sec // 60)
                est_5k_sec_part = int(est_5k_sec % 60)
                est_5k_str = f"{est_5k_min}:{est_5k_sec_part:02d}"
                display_status = "✓"
            else:
                est_5k_str = "HIT!"
                display_status = "✓HIT"
        else:
            est_5k_str = "--:--"
            if not min_distance_reached:
                display_status = "WARMUP"
            else:
                display_status = "INSANE"
        
        print(f"{time_str:<10} {pt['elapsed_cs']:<12.0f} {pt['distance_m']:<12.1f} "
              f"{pace_sec_per_m:<12.6f} {est_5k_str:<12} {display_status:<8}")
    
    print("-" * 80)
    print()
    
    # Find and highlight specific key moments
    print("KEY RACE ESTIMATOR MILESTONES:")
    print("=" * 80)
    
    milestones = [
        (100, "Warmup complete (100m)"),
        (5000, "5K milestone"),
        (8046.72, "5 miles milestone"),
        (10000, "10K milestone"),
    ]
    
    for target_dist, description in milestones:
        # Find closest point to this distance
        closest = min(trackpoints, key=lambda p: abs(p['distance_m'] - target_dist))
        
        if closest['distance_m'] > target_dist - 50:  # Within 50m
            elapsed_min = int(closest['elapsed_sec'] // 60)
            elapsed_sec = int(closest['elapsed_sec'] % 60)
            pace_sec_per_m = closest['elapsed_sec'] / closest['distance_m']
            pace_min_per_km = pace_sec_per_m * 1000 / 60
            
            print(f"\n{description}:")
            print(f"  Time:     {elapsed_min:02d}:{elapsed_sec:02d} ({closest['elapsed_sec']:.1f}s)")
            print(f"  Distance: {closest['distance_m']:.1f}m")
            print(f"  Pace:     {pace_sec_per_m:.6f} sec/m = {pace_min_per_km:.2f} min/km")
            
            if target_dist == 5000:
                print(f"  [This is your 5K split time - compare with app display]")
    
    print("\n" + "=" * 80)
    print("VERIFICATION:")
    print("=" * 80)
    print("Compare the '5K Est' column with your app's console output.")
    print("Timer(cs) should match [RaceEst] Timer values.")
    print("Dist(m) should match [RaceEst] Distance values.")
    print("Pace(s/m) should match [RaceEst] pace calculations.")
    print("5K Est should match [RaceEst] Drawing row 0: '5K  X:XX'")
    print("=" * 80 + "\n")
    
    return trackpoints


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python analyze_gpx.py path/to/activity.gpx")
        sys.exit(1)
    
    gpx_path = sys.argv[1]
    parse_gpx(gpx_path)
