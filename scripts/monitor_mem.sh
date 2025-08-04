#!/bin/bash

# === Memory Monitoring Script ===
# Monitors memory usage at specified intervals

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <output_file> <interval>"
    exit 1
fi

OUTPUT_FILE="$1"
INTERVAL="$2"

# Create header if file doesn't exist
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Timestamp,Total_Memory_MB,Used_Memory_MB,Free_Memory_MB,Shared_Memory_MB,Buffer_Cache_MB,Available_Memory_MB" > "$OUTPUT_FILE"
fi

# Main monitoring loop
while true; do
    # Get current timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get memory stats using free command
    mem_stats=$(free -m | awk 'NR==2 {print $2 "," $3 "," $4 "," $5 "," $6 "," $7}')
    
    # Write to file
    echo "$timestamp,$mem_stats" >> "$OUTPUT_FILE"
    
    # Sleep for the specified interval
    sleep "$INTERVAL"
done 