#!/bin/bash

# === CPU Monitoring Script ===
# Monitors CPU usage at specified intervals

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <output_file> <interval_in_seconds>"
    exit 1
fi

OUTPUT_FILE="$1"
INTERVAL="$2"

# Create header if file doesn't exist
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Timestamp,User%,System%,Idle%" > "$OUTPUT_FILE"
fi

# Main monitoring loop
while true; do
    # Get current timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get CPU usage (user, system, idle) from mpstat
    cpu_stats=$(mpstat 1 1 | awk '/all/ {print $4 "," $6 "," $13; exit}')
    
    # Write timestamped CPU stats to the output file
    echo "$timestamp,$cpu_stats" >> "$OUTPUT_FILE"
    
    # Wait for the specified interval
    sleep "$INTERVAL"
done

