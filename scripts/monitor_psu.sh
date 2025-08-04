#!/bin/bash

# Usage info
usage() {
    echo "Usage: $0 <log_file.csv> <interval_in_seconds>"
    echo "Example: $0 /home/user/psu.csv 10"
    exit 1
}

# Input validation
if [ $# -ne 2 ]; then
    usage
fi

# Resolve path
if [[ "$1" = /* ]]; then
    LOG_FILE="$1"
else
    LOG_FILE="$(pwd)/$1"
fi

INTERVAL="$2"
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]]; then
    echo "Error: Interval must be a number"
    exit 2
fi

# Check ipmicfg availability
if ! command -v ipmicfg &> /dev/null; then
    echo "Error: ipmicfg not found in PATH"
    exit 3
fi

# Header
if [ ! -f "$LOG_FILE" ]; then
    echo "Timestamp,PSU1_Voltage(V),PSU1_Temp1(C),PSU1_Temp2(C),PSU1_Fan1(RPM),PSU1_Power(W),PSU2_Voltage(V),PSU2_Temp1(C),PSU2_Temp2(C),PSU2_Fan1(RPM),PSU2_Power(W)" > "$LOG_FILE"
fi

echo "Logging every $INTERVAL seconds to $LOG_FILE"
echo "Press Ctrl+C to stop."

# Monitoring loop
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Extract relevant data from ipmicfg
    DATA=$(ipmicfg -pminfo full)

    extract_values() {
        echo "$1" | awk '
        BEGIN { RS="\n\n"; FS="\n"; OFS=","; }
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /\[Module 2\]/) psu="PSU1";
                else if ($i ~ /\[Module 3\]/) psu="PSU2";

                if ($i ~ /Main Output Voltage/) match($i, /([0-9.]+) V/, v) && (voltage[psu] = v[1]);
                if ($i ~ /Temperature 1/) match($i, /([0-9]+)C/, t1) && (temp1[psu] = t1[1]);
                if ($i ~ /Temperature 2/) match($i, /([0-9]+)C/, t2) && (temp2[psu] = t2[1]);
                if ($i ~ /Fan 1/) match($i, /([0-9]+) RPM/, f1) && (fan1[psu] = f1[1]);
                if ($i ~ /Main Output Power/) match($i, /([0-9.]+) W/, pwr) && (power[psu] = pwr[1]);
            }
        }
        END {
            printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", 
                "'"$TIMESTAMP"'",
                voltage["PSU1"], temp1["PSU1"], temp2["PSU1"], fan1["PSU1"], power["PSU1"],
                voltage["PSU2"], temp1["PSU2"], temp2["PSU2"], fan1["PSU2"], power["PSU2"];
        }
        '
    }

    extract_values "$DATA" >> "$LOG_FILE"
    sleep "$INTERVAL"
done

