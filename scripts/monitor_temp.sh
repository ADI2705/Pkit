#!/bin/bash
# === Dynamic Temperature Monitoring Script ===
# Monitors disk temperatures for all available disks using saved state

# Source configuration and disk utilities
SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "${SCRIPT_DIR}/config/servertest.conf" 2>/dev/null || true
source "${SCRIPT_DIR}/scripts/common.sh" 2>/dev/null || true

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <output_file> <interval>"
    echo "Example: $0 disk_temps.csv 30"
    exit 1
fi

OUTPUT_FILE="$1"
INTERVAL="$2"
STATE_FILE="${DISK_STATE_FILE:-${SCRIPT_DIR}/.disk_state}"

# Function to log messages
log_msg() {
    local level="$1"
    local msg="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg"
}

# Function to get all available disks from state file
get_available_disks() {
    local disks=()
    
    if [ ! -f "$STATE_FILE" ]; then
        log_msg "ERROR" "Disk state file not found: $STATE_FILE"
        # Fallback: detect disks dynamically
        log_msg "INFO" "Using fallback disk detection..."
        
        # Find all SATA drives
        for dev in $(find /dev -name "sd*" -type b | grep -E '/dev/sd[a-z]+$' | sort); do
            if [ -b "$dev" ]; then
                disks+=("$dev")
            fi
        done
        
        # Find all NVMe drives
        for dev in /dev/nvme[0-9]n[0-9]; do
            if [ -b "$dev" ]; then
                disks+=("$dev")
            fi
        done
    else
        # Read from state file
        while IFS=: read -r device size is_os_disk is_safe mount_point model; do
            if [ -z "$device" ]; then
                continue
            fi
            
            # Check if device still exists
            if [ -b "$device" ]; then
                disks+=("$device")
            fi
        done < "$STATE_FILE"
    fi
    
    printf '%s\n' "${disks[@]}"
}

# Function to create CSV header
create_csv_header() {
    local disks=("$@")
    local header="timestamp"
    
    for disk in "${disks[@]}"; do
        # Convert /dev/sda to sda_temp, /dev/nvme0n1 to nvme0n1_temp
        local disk_name=$(basename "$disk")
        header="${header},${disk_name}_temp"
    done
    
    echo "$header"
}

# Function to get disk temperature
get_disk_temp() {
    local disk="$1"
    local temp="NA"
    
    # Check if disk exists
    if [ ! -b "$disk" ]; then
        echo "NA"
        return
    fi
    
    # Try multiple methods to get temperature
    if [[ "$disk" == *"nvme"* ]]; then
        # NVMe temperature detection
        temp=$(smartctl -A "$disk" 2>/dev/null | grep -E "Temperature:|Temperature Sensor 1:" | grep -o '[0-9]\+' | head -1)
        if [ -z "$temp" ]; then
            temp=$(smartctl -x "$disk" 2>/dev/null | grep "Temperature:" | grep -o '[0-9]\+' | head -1)
        fi
    else
        # SATA/SAS drive temperature detection
        temp=$(smartctl -A "$disk" 2>/dev/null | grep -i "Temperature_Celsius" | awk '{print $10}')
        if [ -z "$temp" ]; then
            temp=$(smartctl -A "$disk" 2>/dev/null | grep -i "Current Drive Temperature" | grep -o '[0-9]\+' | head -1)
        fi
        if [ -z "$temp" ]; then
            temp=$(smartctl -A "$disk" 2>/dev/null | grep -i "Airflow_Temperature_Cel" | awk '{print $10}')
        fi
        if [ -z "$temp" ]; then
            temp=$(smartctl -A "$disk" 2>/dev/null | grep -i "temperature" | grep -o '[0-9]\+' | head -1)
        fi
    fi
    
    # Validate temperature (should be between 0-100°C typically)
    if [ -z "$temp" ] || [ "$temp" = "0" ] || ! [[ "$temp" =~ ^[0-9]+$ ]] || [ "$temp" -gt 150 ]; then
        echo "NA"
    else
        echo "$temp"
    fi
}

# Function to check if smartctl is available
check_smartctl() {
    if ! command -v smartctl >/dev/null 2>&1; then
        log_msg "ERROR" "smartctl not found. Please install smartmontools package."
        log_msg "INFO" "On Ubuntu/Debian: sudo apt-get install smartmontools"
        log_msg "INFO" "On RHEL/CentOS: sudo yum install smartmontools"
        exit 1
    fi
}

# Main script starts here
log_msg "INFO" "Starting dynamic temperature monitoring..."
log_msg "INFO" "Output file: $OUTPUT_FILE"
log_msg "INFO" "Monitoring interval: $INTERVAL seconds"

# Check dependencies
check_smartctl

# Get available disks
log_msg "INFO" "Detecting available disks..."
mapfile -t AVAILABLE_DISKS < <(get_available_disks)

if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
    log_msg "ERROR" "No disks found for monitoring"
    exit 1
fi

log_msg "INFO" "Found ${#AVAILABLE_DISKS[@]} disk(s) to monitor:"
for disk in "${AVAILABLE_DISKS[@]}"; do
    log_msg "INFO" "  - $disk"
done

# Create header if file doesn't exist
if [ ! -f "$OUTPUT_FILE" ]; then
    log_msg "INFO" "Creating new CSV file with header..."
    header=$(create_csv_header "${AVAILABLE_DISKS[@]}")
    echo "$header" > "$OUTPUT_FILE"
    log_msg "INFO" "Header: $header"
else
    log_msg "INFO" "Using existing CSV file: $OUTPUT_FILE"
fi

# Set up signal handling for clean exit
trap 'log_msg "INFO" "Temperature monitoring stopped."; exit 0' INT TERM

log_msg "INFO" "Starting temperature monitoring loop..."
log_msg "INFO" "Press Ctrl+C to stop monitoring"

# Main monitoring loop
while true; do
    # Get current timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Initialize temperature array
    declare -a temps=()
    
    # Get temperatures for all available disks
    for disk in "${AVAILABLE_DISKS[@]}"; do
        temp=$(get_disk_temp "$disk")
        temps+=("${temp}")
    done
    
    # Create CSV row
    row="$timestamp"
    for temp in "${temps[@]}"; do
        row="${row},${temp}"
    done
    
    # Write to file
    echo "$row" >> "$OUTPUT_FILE"
    
    # Optional: Print current readings to console (comment out if not needed)
    echo "$(date '+%H:%M:%S'): $row"
    
    # Clear temps array for next iteration
    unset temps
    
    # Sleep for the specified interval
    sleep "$INTERVAL"
done