#!/bin/bash

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <output_file> <interval>"
    exit 1
fi

CSV_FILE="$1"
INTERVAL="$2"

# Write CSV header if file does not exist
if [[ ! -f "$CSV_FILE" ]]; then
    # Dynamically get all DIMM sensor names for header
    HEADER="Timestamp"
    DIMM_LABELS=$(ipmitool sensor | awk -F '|' '/DIMM/ {gsub(/ /, "", $1); print $1}')
    for label in $DIMM_LABELS; do
        HEADER+="${HEADER:+,}$label"
    done
    echo "$HEADER" >> "$CSV_FILE"
fi

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    LINE="$TIMESTAMP"
    # Get all DIMM temperatures
    DIMM_TEMPS=$(ipmitool sensor | awk -F '|' '/DIMM/ {gsub(/ /, "", $2); print $2}')
    for temp in $DIMM_TEMPS; do
        LINE+="${LINE:+,}$temp"
    done
    echo "$LINE" >> "$CSV_FILE"
    sleep "$INTERVAL"
done 