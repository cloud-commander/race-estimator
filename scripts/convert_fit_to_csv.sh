#!/bin/bash
# Convert FIT file to CSV using Garmin FIT SDK
# Download SDK from: https://developer.garmin.com/fit/download/

FIT_FILE="$1"

if [ -z "$FIT_FILE" ]; then
    echo "Usage: ./convert_fit_to_csv.sh path/to/activity.fit"
    exit 1
fi

if [ ! -f "$FIT_FILE" ]; then
    echo "ERROR: File not found: $FIT_FILE"
    exit 1
fi

# Check if FitCSVTool.jar exists
if [ ! -f "FitCSVTool.jar" ]; then
    echo "ERROR: FitCSVTool.jar not found in current directory"
    echo ""
    echo "Download from: https://developer.garmin.com/fit/download/"
    echo "Extract FitCSVTool.jar to this directory"
    exit 1
fi

echo "Converting FIT file to CSV..."
java -jar FitCSVTool.jar "$FIT_FILE"

# Find the generated CSV
BASENAME=$(basename "$FIT_FILE" .fit)
CSV_FILE="${BASENAME}_records.csv"

if [ -f "$CSV_FILE" ]; then
    echo ""
    echo "✅ Conversion successful!"
    echo "Output: $CSV_FILE"
    echo ""
    echo "Showing first 20 rows with timer_time and distance columns:"
    echo "------------------------------------------------------------"
    head -20 "$CSV_FILE" | awk -F',' 'NR==1 {for(i=1;i<=NF;i++) if($i~/timer_time/ || $i~/distance/) print i":"$i} NR>1 {print}'
else
    echo "❌ Conversion failed - CSV file not found"
fi
