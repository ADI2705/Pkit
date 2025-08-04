#!/bin/bash

# === Common Functions Script ===
# Contains shared functions used across all scripts

# Source configuration
SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "${SCRIPT_DIR}/config/servertest.conf"

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Set color based on level
    case "$level" in
        "INFO")
            color="$GRN"
            ;;
        "WARNING")
            color="$YEL"
            ;;
        "ERROR")
            color="$RED"
            ;;
        "DEBUG")
            color="$BLU"
            ;;
        *)
            color="$NC"
            ;;
    esac
    
    # Print to console with color
    echo -e "${color}[$timestamp] [$level] $message${NC}"
    
    # Write to log file
    if [ -n "$LOGS_DIR" ]; then
        mkdir -p "$LOGS_DIR"
        echo "[$timestamp] [$level] $message" >> "${LOGS_DIR}/servertest.log"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a file exists
file_exists() {
    [ -f "$1" ]
}

# Function to check if a directory exists
dir_exists() {
    [ -d "$1" ]
}

# Function to check if a device exists
device_exists() {
    [ -b "$1" ]
}

# Function to check if a process is running
process_running() {
    pgrep -f "$1" >/dev/null 2>&1
}

# Function to kill a process
kill_process() {
    local pid="$1"
    if process_running "$pid"; then
        kill "$pid" 2>/dev/null
        sleep 1
        if process_running "$pid"; then
            kill -9 "$pid" 2>/dev/null
        fi
    fi
}

# Function to clean up test environment
cleanup_test_env() {
    local test_dir="$1"
    
    log "INFO" "Cleaning up test environment in $test_dir"
    
    # Kill any running processes
    for pid in $(pgrep -f "fio.*$test_dir"); do
        kill_process "$pid"
    done
    
    # Remove temporary files
    find "$test_dir" -type f -name "*.tmp" -delete
    
    log "INFO" "Cleanup completed"
}

# Function to check disk health
check_disk_health() {
    local device="$1"
    
    log "INFO" "Checking health of $device"
    
    if [[ "$device" =~ ^/dev/nvme ]]; then
        # Check NVMe health
        if ! nvme smart-log "$device" >/dev/null 2>&1; then
            log "ERROR" "Failed to get NVMe health status for $device"
            return 1
        fi
    else
        # Check HDD health
        if ! smartctl -H "$device" >/dev/null 2>&1; then
            log "ERROR" "Failed to get HDD health status for $device"
            return 1
        fi
    fi
    
    log "INFO" "Disk health check passed for $device"
    return 0
}

# Function to check disk temperature
check_disk_temp() {
    local device="$1"
    local max_temp="$2"
    local temp
    
    if [[ "$device" =~ ^/dev/nvme ]]; then
        temp=$(nvme smart-log "$device" 2>/dev/null | grep "temperature" | awk '{print $3}')
    else
        temp=$(smartctl -A "$device" 2>/dev/null | grep "Temperature_Celsius" | awk '{print $10}')
    fi
    
    if [ -n "$temp" ] && [ "$temp" -gt "$max_temp" ]; then
        log "WARNING" "Temperature of $device is too high: $temp°C (max: $max_temp°C)"
        return 1
    fi
    
    return 0
}

# Function to check disk space
check_disk_space() {
    local device="$1"
    local min_space="$2"
    local available_space
    
    available_space=$(df -B1 "$device" | awk 'NR==2 {print $4}')
    
    if [ "$available_space" -lt "$min_space" ]; then
        log "WARNING" "Insufficient space on $device: $(numfmt --to=iec-i --suffix=B $available_space) (min: $(numfmt --to=iec-i --suffix=B $min_space))"
        return 1
    fi
    
    return 0
}

# Function to check disk mount status
check_disk_mount() {
    local device="$1"
    
    if mount | grep -q "$device"; then
        log "WARNING" "$device is mounted"
        return 1
    fi
    
    return 0
}

# Function to check disk in use
check_disk_in_use() {
    local device="$1"
    
    if lsof "$device" >/dev/null 2>&1; then
        log "WARNING" "$device is in use"
        return 1
    fi
    
    return 0
}

# Function to check disk status
check_disk_status() {
    local device="$1"
    local max_temp="$2"
    local min_space="$3"
    
    # Check if device exists
    if ! device_exists "$device"; then
        log "ERROR" "Device $device does not exist"
        return 1
    fi
    
    # Check disk health
    if ! check_disk_health "$device"; then
        return 1
    fi
    
    # Check disk temperature
    if ! check_disk_temp "$device" "$max_temp"; then
        return 1
    fi
    
    # Check disk space
    if ! check_disk_space "$device" "$min_space"; then
        return 1
    fi
    
    # Check disk mount status
    if ! check_disk_mount "$device"; then
        return 1
    fi
    
    # Check disk in use
    if ! check_disk_in_use "$device"; then
        return 1
    fi
    
    log "INFO" "All disk checks passed for $device"
    return 0
}

# Function to get disk model
get_disk_model() {
    local device="$1"
    local model
    
    if [[ "$device" =~ ^/dev/nvme ]]; then
        model=$(nvme id-ctrl "$device" -H | grep "mn" | cut -d':' -f2 | xargs)
    else
        model=$(hdparm -I "$device" 2>/dev/null | grep "Model Number" | cut -d':' -f2 | xargs)
    fi
    
    echo "$model"
}

# Function to get disk size
get_disk_size() {
    local device="$1"
    local size
    
    size=$(lsblk -b -d -o SIZE "$device" | tail -n1)
    echo "$size"
}

# Function to print disk information
print_disk_info() {
    local device="$1"
    local model
    local size
    
    model=$(get_disk_model "$device")
    size=$(get_disk_size "$device")
    
    # Convert size to human readable
    if [ "$size" -ge 1099511627776 ]; then
        size=$(echo "scale=2; $size/1099511627776" | bc)" TB"
    elif [ "$size" -ge 1073741824 ]; then
        size=$(echo "scale=2; $size/1073741824" | bc)" GB"
    elif [ "$size" -ge 1048576 ]; then
        size=$(echo "scale=2; $size/1048576" | bc)" MB"
    else
        size=$(echo "scale=2; $size/1024" | bc)" KB"
    fi
    
    echo "Device: $device"
    echo "Model: $model"
    echo "Size: $size"
    echo "---"
} 