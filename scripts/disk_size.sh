#!/bin/bash

# === Disk Size Utility Script ===
# Provides functions for getting disk sizes and managing disk lists

# Source configuration and common functions
SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "${SCRIPT_DIR}/config/servertest.conf"
source "${SCRIPT_DIR}/scripts/common.sh"

# Function to get disk size in GB
get_disk_size() {
    local device="$1"
    if [ ! -b "$device" ]; then
        echo "0"
        return 1
    fi
    
    # Get size in bytes and convert to GB
    local size_bytes
    size_bytes=$(blockdev --getsize64 "$device" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "0"
        return 1
    fi
    
    # Convert to GB (divide by 1024^3)
    local size_gb
    size_gb=$((size_bytes / 1073741824))
    echo "$size_gb"
    return 0
}

# Function to get disk size from state file
get_disk_size_from_state() {
    local device="$1"
    local state_file="${SCRIPT_DIR}/.disk_state"
    
    if [ ! -f "$state_file" ]; then
        log "ERROR" "Disk state file not found"
        return 1
    fi
    
    # Get size from state file
    local size
    size=$(grep "^$device:" "$state_file" | cut -d':' -f2)
    if [ -z "$size" ]; then
        log "ERROR" "Disk $device not found in state file"
        return 1
    fi
    
    echo "$size"
    return 0
}

# Function to get disk mount point
get_disk_mount_point() {
    local device="$1"
    local mount_point
    
    # Check if device is mounted
    mount_point=$(findmnt -n -o TARGET "$device" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$mount_point"
        return 0
    fi
    
    # Check if any partition is mounted
    for part in "${device}"*; do
        if [ -b "$part" ]; then
            mount_point=$(findmnt -n -o TARGET "$part" 2>/dev/null)
            if [ $? -eq 0 ]; then
                echo "$mount_point"
                return 0
            fi
        fi
    done
    
    echo ""
    return 1
}

# Function to get disk model
get_disk_model() {
    local device="$1"
    local model
    
    # Try to get model from sysfs
    if [ -f "/sys/block/$(basename "$device")/device/model" ]; then
        model=$(cat "/sys/block/$(basename "$device")/device/model")
        echo "$model"
        return 0
    fi
    
    # Try to get model from hdparm
    if command -v hdparm >/dev/null 2>&1; then
        model=$(hdparm -I "$device" 2>/dev/null | grep "Model Number" | cut -d':' -f2 | sed 's/^[[:space:]]*//')
        if [ -n "$model" ]; then
            echo "$model"
            return 0
        fi
    fi
    
    echo "Unknown"
    return 1
}

# Function to save disk state to file
save_disk_state() {
    local state_file="$DISK_STATE_FILE"
    local temp_file="${state_file}.tmp"
    
    # Create temporary file
    > "$temp_file"
    
    # Get OS disks
    local os_disks=()
    local root_dev
    root_dev=$(findmnt -n -o SOURCE /)
    if [ -n "$root_dev" ]; then
        root_dev=$(echo "$root_dev" | sed -E 's/p?[0-9]+$//')
        os_disks+=("$root_dev")
    fi
    
    local boot_dev
    boot_dev=$(findmnt -n -o SOURCE /boot)
    if [ -n "$boot_dev" ]; then
        boot_dev=$(echo "$boot_dev" | sed -E 's/p?[0-9]+$//')
        os_disks+=("$boot_dev")
    fi
    
    # Save all HDDs - extended to handle drives beyond sdz
    for dev in $(find /dev -name "sd*" -type b | grep -E '/dev/sd[a-z]+$' | sort); do
        if [ -b "$dev" ]; then
            local size
            size=$(get_disk_size "$dev")
            if [ "$size" != "0" ]; then
                local is_os_disk=false
                local is_safe=true
                local mount_point
                local model
                
                # Check if it's an OS disk
                for os_disk in "${os_disks[@]}"; do
                    if [ "$dev" = "$os_disk" ]; then
                        is_os_disk=true
                        is_safe=false
                        break
                    fi
                done
                
                # Get mount point
                mount_point=$(get_disk_mount_point "$dev")
                if [ -n "$mount_point" ]; then
                    is_safe=false
                fi
                
                # Get model
                model=$(get_disk_model "$dev")
                
                # Save disk info
                echo "$dev:$size:$is_os_disk:$is_safe:$mount_point:$model" >> "$temp_file"
            fi
        fi
    done
    
    # Save all NVMe drives
    for dev in /dev/nvme[0-9]n[0-9]; do
        if [ -b "$dev" ]; then
            local size
            size=$(get_disk_size "$dev")
            if [ "$size" != "0" ]; then
                local is_os_disk=false
                local is_safe=true
                local mount_point
                local model
                
                # Check if it's an OS disk
                for os_disk in "${os_disks[@]}"; do
                    if [ "$dev" = "$os_disk" ]; then
                        is_os_disk=true
                        is_safe=false
                        break
                    fi
                done
                
                # Get mount point
                mount_point=$(get_disk_mount_point "$dev")
                if [ -n "$mount_point" ]; then
                    is_safe=false
                fi
                
                # Get model
                model=$(get_disk_model "$dev")
                
                # Save disk info
                echo "$dev:$size:$is_os_disk:$is_safe:$mount_point:$model" >> "$temp_file"
            fi
        fi
    done
    
    # Replace state file with temporary file
    mv "$temp_file" "$state_file"
    return 0
}

# Function to load disk state from file
load_disk_state() {
    local state_file="$DISK_STATE_FILE"
    
    if [ ! -f "$state_file" ]; then
        log "ERROR" "Disk state file not found"
        return 1
    fi
    
    # Clear existing arrays
    SAFE_HDDS=()
    SAFE_NVMES=()
    
    # Read state file
    while IFS=: read -r device size is_os_disk is_safe mount_point model; do
        if [ -z "$device" ] || [ -z "$size" ] || [ -z "$is_os_disk" ] || [ -z "$is_safe" ]; then
            continue
        fi
        
        # Check if device exists
        if [ ! -b "$device" ]; then
            continue
        fi
        
        # Add to appropriate array if safe
        if [ "$is_safe" = "true" ]; then
            if [[ "$device" =~ ^/dev/sd[a-z]+$ ]]; then
                SAFE_HDDS+=("$device")
            elif [[ "$device" =~ ^/dev/nvme[0-9]n[0-9]$ ]]; then
                SAFE_NVMES+=("$device")
            fi
        fi
    done < "$state_file"
    
    return 0
}

# Function to get disk info from state file
get_disk_info_from_state() {
    local device="$1"
    local state_file="${SCRIPT_DIR}/.disk_state"
    
    if [ ! -f "$state_file" ]; then
        log "ERROR" "Disk state file not found"
        return 1
    fi
    
    # Get info from state file
    local info
    info=$(grep "^$device:" "$state_file")
    if [ -z "$info" ]; then
        log "ERROR" "Disk $device not found in state file"
        return 1
    fi
    
    # Parse info
    IFS=: read -r _ size is_os_disk is_safe mount_point model <<< "$info"
    
    # Only OS disks are not safe
    is_safe="true"
    if [ "$is_os_disk" = "true" ]; then
        is_safe="false"
    fi
    
    # Return info in colon-separated format
    echo "$size:$is_os_disk:$is_safe:$mount_point:$model"
    return 0
}

# Function to display disk info
display_disk_info() {
    local device="$1"
    local info
    info=$(get_disk_info_from_state "$device")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
    
    echo "Disk: $device"
    echo "Model: $model"
    echo "Size: ${size}GB"
    echo "OS Disk: $is_os_disk"
    echo "Safe to Test: $is_safe"
    echo "Mount Point: ${mount_point:-None}"
    return 0
}

# Function to display all disks
display_all_disks() {
    local state_file="$DISK_STATE_FILE"
    
    if [ ! -f "$state_file" ]; then
        log "ERROR" "Disk state file not found"
        return 1
    fi
    
    echo "=== All Available Disks ==="
    while IFS=: read -r device size is_os_disk is_safe mount_point model; do
        echo "------------------------"
        echo "Disk: $device"
        echo "Model: $model"
        echo "Size: ${size}GB"
        echo "OS Disk: $is_os_disk"
        echo "Safe to Test: $is_safe"
        echo "Mount Point: ${mount_point:-None}"
    done < "$state_file"
    echo "------------------------"
    return 0
}

# Function to filter out OS disks
filter_os_disks() {
    local os_disks=()
    
    # Get root filesystem device
    local root_dev
    root_dev=$(findmnt -n -o SOURCE /)
    if [ -n "$root_dev" ]; then
        # Get base device (remove partition number)
        root_dev=$(echo "$root_dev" | sed -E 's/p?[0-9]+$//')
        os_disks+=("$root_dev")
    fi
    
    # Get boot filesystem device
    local boot_dev
    boot_dev=$(findmnt -n -o SOURCE /boot)
    if [ -n "$boot_dev" ]; then
        # Get base device (remove partition number)
        boot_dev=$(echo "$boot_dev" | sed -E 's/p?[0-9]+$//')
        os_disks+=("$boot_dev")
    fi
    
    # Filter out OS disks from arrays
    local filtered_hdds=()
    local filtered_nvmes=()
    
    for hdd in "${SAFE_HDDS[@]}"; do
        local is_os_disk=false
        for os_disk in "${os_disks[@]}"; do
            if [ "$hdd" = "$os_disk" ]; then
                is_os_disk=true
                break
            fi
        done
        if [ "$is_os_disk" = false ]; then
            filtered_hdds+=("$hdd")
        fi
    done
    
    for nvme in "${SAFE_NVMES[@]}"; do
        local is_os_disk=false
        for os_disk in "${os_disks[@]}"; do
            if [ "$nvme" = "$os_disk" ]; then
                is_os_disk=true
                break
            fi
        done
        if [ "$is_os_disk" = false ]; then
            filtered_nvmes+=("$nvme")
        fi
    done
    
    # Update arrays
    SAFE_HDDS=("${filtered_hdds[@]}")
    SAFE_NVMES=("${filtered_nvmes[@]}")
    
    return 0
}

# Function to detect available HDDs
detect_hdds() {
    # Clear existing array
    SAFE_HDDS=()
    
    # Find all HDDs - extended to handle drives beyond sdz
    for dev in $(find /dev -name "sd*" -type b | grep -E '/dev/sd[a-z]+$' | sort); do
        if [ -b "$dev" ]; then
            local size
            size=$(get_disk_size "$dev")
            if [ "$size" != "0" ]; then
                SAFE_HDDS+=("$dev")
            fi
        fi
    done
    
    return 0
}

# Function to detect available NVMe drives
detect_nvmes() {
    # Clear existing array
    SAFE_NVMES=()
    
    # Find all NVMe drives
    for dev in /dev/nvme[0-9]n[0-9]; do
        if [ -b "$dev" ]; then
            local size
            size=$(get_disk_size "$dev")
            if [ "$size" != "0" ]; then
                SAFE_NVMES+=("$dev")
            fi
        fi
    done
    
    return 0
}

# Function to initialize disk arrays
init_disk_arrays() {
    log "INFO" "Initializing disk arrays..."
    
    # Check if state file exists
    if [ ! -f "$DISK_STATE_FILE" ]; then
        log "INFO" "Disk state file not found, creating new one..."
        # Create state file directory if it doesn't exist
        mkdir -p "$(dirname "$DISK_STATE_FILE")"
        # Create empty state file
        echo "{}" > "$DISK_STATE_FILE"
    fi
    
    # Load state file
    if ! load_disk_state; then
        log "ERROR" "Failed to load disk state"
        return 1
    fi
    
    # Detect HDDs
    detect_hdds
    
    # Detect NVMe drives
    detect_nvmes
    
    # Filter out OS disks
    filter_os_disks
    
    # Save updated state
    save_disk_state
    
    log "INFO" "Found ${#SAFE_HDDS[@]} safe HDD(s) and ${#SAFE_NVMES[@]} safe NVMe drive(s)"
    return 0
}

# Initialize arrays if script is sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_disk_arrays
fi