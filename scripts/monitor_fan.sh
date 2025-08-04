#!/bin/bash

# === Fan Monitoring Script ===
# Monitors fan speeds and writes to CSV file

# Source configuration and common functions
SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "${SCRIPT_DIR}/config/servertest.conf"
source "${SCRIPT_DIR}/scripts/common.sh"

# Function to check if ipmitool is available and working
check_ipmitool() {
    if ! command -v ipmitool >/dev/null 2>&1; then
        echo "Error: ipmitool is not installed" >&2
        return 1
    fi
    
    # Test ipmitool
    if ! ipmitool sensor >/dev/null 2>&1; then
        echo "Error: ipmitool sensor command failed. Check if IPMI is enabled and you have proper permissions" >&2
        return 1
    fi
    
    return 0
}

# Function to get fan data (returns name,speed pairs)
get_fan_data() {
    # Check ipmitool first
    if ! check_ipmitool; then
        return 1
    fi
    
    local sensor_output
    sensor_output=$(ipmitool sensor 2>/dev/null)
    
    if [ -z "$sensor_output" ]; then
        echo "Error: No output from ipmitool sensor" >&2
        return 1
    fi
    
    # Process the data directly with awk
    echo "$sensor_output" | awk '
    /^FAN[0-9A]/ {
        # Split the line by |
        split($0, fields, "|")
        # Get the fan name and speed
        name = fields[1]
        speed = fields[2]
        # Remove leading/trailing spaces
        gsub(/^[ \t]+|[ \t]+$/, "", name)
        gsub(/^[ \t]+|[ \t]+$/, "", speed)
        # Print all fans, using "NA" for unavailable ones
        if (speed ~ /^[0-9.]+$/) {
            print name "," speed
        } else {
            print name ",NA"
        }
    }'
}

# Function to monitor fans
monitor_fans() {
    local output_csv="$1"
    local interval="$2"

    # Check ipmitool first
    if ! check_ipmitool; then
        echo "Error: Cannot start fan monitoring due to ipmitool issues" >&2
        return 1
    fi

    # Ensure output directory exists
    local output_dir
    output_dir=$(dirname "$output_csv")
    if [ ! -d "$output_dir" ]; then
        echo "Creating output directory: $output_dir" >&2
        mkdir -p "$output_dir" || {
            echo "Error: Failed to create output directory: $output_dir" >&2
            return 1
        }
    fi

    # Check if we can write to the output file
    if [ -f "$output_csv" ] && [ ! -w "$output_csv" ]; then
        echo "Error: Cannot write to output file: $output_csv" >&2
        return 1
    fi

    declare -a fan_names=()
    
    # CSV header creation
    if [ ! -f "$output_csv" ]; then
        echo "Creating new CSV file: $output_csv" >&2
        while IFS=',' read -r name speed; do
            fan_names+=("$name")
        done < <(get_fan_data)

        if [ ${#fan_names[@]} -eq 0 ]; then
            echo "Error: No fans found to monitor" >&2
            return 1
        fi

        local header="Timestamp"
        for name in "${fan_names[@]}"; do
            header+=",${name}_RPM"
        done
        echo "$header" > "$output_csv" || {
            echo "Error: Failed to write header to CSV file" >&2
            return 1
        }
        echo "CSV header written successfully" >&2
    else
        echo "Using existing CSV file: $output_csv" >&2
        # Read existing header to get fan names
        IFS=',' read -r -a header_fields < "$output_csv"
        for ((i=1; i<${#header_fields[@]}; i++)); do
            fan_names+=("${header_fields[$i]%_RPM}")
        done
    fi

    # Monitoring loop
    while true; do
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        declare -A fan_map=()
        while IFS=',' read -r name speed; do
            fan_map["$name"]="$speed"
        done < <(get_fan_data)

        local row="$timestamp"
        for name in "${fan_names[@]}"; do
            row+=","${fan_map["$name"]:-"NA"}
        done
        
        # Write row to CSV
        echo "$row" >> "$output_csv" || {
            echo "Error: Failed to write data to CSV file" >&2
            return 1
        }
        
        echo "Data written at $timestamp" >&2
        sleep "$interval"
    done
}

# === Entry point ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 <output_csv> <interval_seconds>"
        exit 1
    fi

    monitor_fans "$1" "$2"
fi 