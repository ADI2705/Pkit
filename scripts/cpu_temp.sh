#!/bin/bash

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <output_file> <interval>"
    exit 1
fi

CSV_FILE="$1"
INTERVAL="$2"

if [[ ! -f "$CSV_FILE" ]]; then
    echo "Timestamp,CPU_Temp_C" >> "$CSV_FILE"
fi

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Extract the temperature using a more robust approach
    CPU_TEMP=$(ipmitool sensor | awk -F '|' '/CPU Temp/ {gsub(/ /,"",$2); print $2}')

    echo "$TIMESTAMP,$CPU_TEMP" >> "$CSV_FILE"
    sleep "$INTERVAL"
done

