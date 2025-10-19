# FIT File Analysis Guide

This directory contains tools to analyze FIT files and verify the Race Estimator calculations.

## 🎯 Quick Start

### Option 1: Python Script (Recommended)

```bash
# Install fitparse library
pip install fitparse

# Analyze your FIT file
python analyze_fit.py path/to/your_activity.fit
```

**What it does:**

- Extracts timer_time (in centiseconds) and distance from FIT file
- Calculates pace at each data point
- Shows 5K predictions using the SAME formula as RaceEstimatorView.mc
- Highlights key timestamps from your console logs
- Compares expected vs actual values

### Option 2: Garmin FIT SDK (If you have it)

```bash
# Download from: https://developer.garmin.com/fit/download/
# Extract FitCSVTool.jar to this directory

./convert_fit_to_csv.sh path/to/your_activity.fit
```

**What it does:**

- Converts FIT binary to CSV text format
- Creates `activity_records.csv` with all data points
- You can open in Excel/Numbers to analyze

---

## 📊 Understanding the Output

### Python Script Output:

```
SESSION SUMMARY:
Total Time:     361.6s (6.0 min)
Total Distance: 3129.6m (3.13 km)
Avg Speed:      8.65 m/s (1.93 min/km)

DETAILED RECORDS:
Time         Timer(cs)    Dist(m)      Pace(s/m)    5K Est(s)
00:00        0            0.0          0.0000       0
06:01        36155        3129.6       0.1155       216

KEY TIMESTAMPS FROM YOUR LOG:
Time 6:01:
  Timer:        36155 cs = 361550 ms = 361.6 s
  Distance:     3129.6 m
  Pace:         0.115525 sec/m = 115.52 sec/km
  5K Remaining: 1870.4 m
  5K Estimate:  216 s = 3:36
```

**Compare this with your app's console log:**

```
[RaceEst] Timer: 36155 (centisec), Distance: 3129.618164m
[RaceEst] Pace calc: timerMs=361550 elapsedDist=3129.618164 pace=0.115525
[RaceEst] M0: target=5000.000000m rem=1870.381836m*pace=0.115525=216076ms
[RaceEst] Drawing row 0: '5K  3:36'
```

If they match ✅ → Calculations are correct!

---

## 🔍 What to Look For

### 1. Timer Units

- FIT file `timer_time` is in **milliseconds**
- Your app receives it as **centiseconds** (divide by 10)
- The script shows both: `36155 cs = 361550 ms`

### 2. Pace Calculation

Should be: `pace = (timer_ms / 1000) / distance_m`

Example:

- Timer: 361,550 ms = 361.55 seconds
- Distance: 3,129.62 meters
- Pace: 361.55 / 3,129.62 = **0.1155 sec/meter** = 6:57/km ✅

### 3. 5K Prediction

Should be: `time_to_5k = (5000 - distance) × pace`

Example:

- Remaining: 5,000 - 3,129.62 = 1,870.38 meters
- Pace: 0.1155 sec/meter
- Estimate: 1,870.38 × 0.1155 = **216 seconds** = 3:36 ✅

---

## 🐛 Troubleshooting

### Error: "fitparse not installed"

```bash
pip install fitparse
# or
pip3 install fitparse
```

### Error: "FitCSVTool.jar not found"

Download from: https://developer.garmin.com/fit/download/
Extract `FitCSVTool.jar` to this directory

### Error: "No record data found"

Your FIT file might be corrupted or empty. Try:

- Opening it in Garmin Connect
- Exporting a fresh copy
- Using a different activity

---

## 📝 Example Usage

```bash
# Analyze the FIT file you used in simulator
python analyze_fit.py ~/Downloads/my_run.fit

# Convert to CSV for manual inspection
./convert_fit_to_csv.sh ~/Downloads/my_run.fit
open my_run_records.csv  # Opens in default spreadsheet app
```

---

## 🎓 What This Proves

If the script's output **matches** your app's console log:

- ✅ Timer unit conversion is correct (centisec → millisec)
- ✅ Pace calculation is correct
- ✅ 5K prediction formula is correct
- ✅ Your app is working perfectly!

If they **don't match**:

- ❌ Check if FIT file is the same one used in simulator
- ❌ Verify script vs app use same formulas
- ❌ Look for unit conversion bugs

---

## 📧 Need Help?

Share the output of:

```bash
python analyze_fit.py your_activity.fit > fit_analysis.txt
```

Along with your app's console log for comparison.
