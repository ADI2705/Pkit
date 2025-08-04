#!/bin/bash

# Script to detect, format, and mount disks based on test type

NC='\033[0m'
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[0;33m'

# Filesystem type for formatting (default: ext4)
FS_TYPE="ext4"

# Function to check if script is run as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Function to get OS drive with multiple verification methods
get_os_drive() {
    local os_drive=""
    local root_dev=""
    
    # Method 1: Using findmnt for root mount
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null)
    if [ -n "$root_dev" ]; then
        os_drive=$(lsblk -no PKNAME "$root_dev" 2>/dev/null)
        if [ -z "$os_drive" ]; then
            os_drive=$(basename "$root_dev")
        fi
    fi
    
    # Method 2: Check mounted system partitions
    if [ -z "$os_drive" ]; then
        for mount in /boot /boot/efi /home /var /usr; do
            if [ -d "$mount" ]; then
                local mount_dev=$(findmnt -n -o SOURCE "$mount" 2>/dev/null)
                if [ -n "$mount_dev" ]; then
                    local parent_dev=$(lsblk -no PKNAME "$mount_dev" 2>/dev/null)
                    if [ -n "$parent_dev" ]; then
                        os_drive="$parent_dev"
                        break
                    fi
                fi
            fi
        done
    fi
    
    # Method 3: Check /etc/fstab
    if [ -z "$os_drive" ]; then
        os_drive=$(grep -E '^[^#].*\s/\s' /etc/fstab | awk '{print $1}' | sed 's/[0-9]*$//')
    fi
    
    # Remove partition numbers if present
    os_drive=${os_drive%%[0-9]*}
    
    if [ -z "$os_drive" ]; then
        echo -e "${RED}Error: Could not determine OS drive. Aborting for safety.${NC}"
        exit 1
    fi
    
    # Verify the OS drive exists
    if [ ! -b "/dev/$os_drive" ]; then
        echo -e "${RED}Error: Detected OS drive /dev/$os_drive does not exist. Aborting for safety.${NC}"
        exit 1
    fi
    
    echo "$os_drive"
}

# Function to verify disk is safe to format
verify_disk_safety() {
    local disk_name="$1"
    local os_drive="$2"
    
    # Check if it's the OS drive
    if [ "$disk_name" = "$os_drive" ]; then
        echo -e "${RED}ERROR: Attempted to format OS drive /dev/$disk_name. This should never happen.${NC}"
        return 1
    fi
    
    # Check if any system partitions are on this disk
    local system_mounts=$(mount | grep -E '^/dev/'"$disk_name" | awk '{print $3}')
    if [ -n "$system_mounts" ]; then
        echo -e "${RED}ERROR: Disk /dev/$disk_name contains system mounts:${NC}"
        echo "$system_mounts"
        return 1
    fi
    
    # Check if disk is part of any RAID or LVM
    if pvs 2>/dev/null | grep -q "/dev/$disk_name"; then
        echo -e "${RED}ERROR: Disk /dev/$disk_name is part of LVM. Skipping for safety.${NC}"
        return 1
    fi
    
    if mdadm --detail --scan 2>/dev/null | grep -q "/dev/$disk_name"; then
        echo -e "${RED}ERROR: Disk /dev/$disk_name is part of RAID. Skipping for safety.${NC}"
        return 1
    fi
    
    return 0
}

# Function to detect available disks based on test type
detect_disks() {
    local test_type="$1"
    local available_disks=()
    local os_drive=$(get_os_drive)
    
    echo -e "${GRN}OS drive detected as: ${os_drive}${NC}"
    echo -e "${YEL}WARNING: The following drive will be skipped to protect the OS: /dev/${os_drive}${NC}"
    
    case "$test_type" in
        nvme)
            # Detect NVMe drives
            for disk in /dev/nvme[0-9]n1; do
                if [ -b "$disk" ]; then
                    disk_name=$(basename "$disk")
                    # Skip if this is the OS drive
                    if [ "$disk_name" = "$os_drive" ]; then
                        echo -e "${YEL}Skipping OS drive: $disk_name${NC}"
                        continue
                    fi
                    # Verify disk is safe to format
                    if verify_disk_safety "$disk_name" "$os_drive"; then
                        available_disks+=("$disk_name")
                    fi
                fi
            done
            ;;
        *)
            # Detect HDDs (sda-sdz and sdaa-sdaz)
            for disk in /dev/sd[a-z] /dev/sd[a-z][a-z]; do
                if [ -b "$disk" ]; then
                    disk_name=$(basename "$disk")
                    # Skip if this is the OS drive
                    if [ "$disk_name" = "$os_drive" ]; then
                        echo -e "${YEL}Skipping OS drive: $disk_name${NC}"
                        continue
                    fi
                    # Verify disk is safe to format
                    if verify_disk_safety "$disk_name" "$os_drive"; then
                        available_disks+=("$disk_name")
                    fi
                fi
            done
            ;;
    esac
    
    echo "${available_disks[@]}"
}

# Function to get mount point for a disk
get_mount_point() {
    local disk_name="$1"
    local test_type="$2"
    
    case "$test_type" in
        nvme)
            echo "/mnt/test_${disk_name}"
            ;;
        *)
            # For HDDs, use the existing mount point logic
            local base_index
            if [[ $disk_name =~ ^sd([a-z])$ ]]; then
                letter=${BASH_REMATCH[1]}
                base_index=$(( $(printf "%d" "'$letter") - 97 ))
            elif [[ $disk_name =~ ^sd([a-z])([a-z])$ ]]; then
                first_letter=${BASH_REMATCH[1]}
                second_letter=${BASH_REMATCH[2]}
                first_index=$(( $(printf "%d" "'$first_letter") - 97 ))
                second_index=$(( $(printf "%d" "'$second_letter") - 97 ))
                base_index=$(( (first_index + 1) * 26 + second_index ))
            else
                echo -1
                return 1
            fi
            echo "/mnt/disk$((base_index + 1))"
            ;;
    esac
}

# Function to check if disk is mounted
is_mounted() {
    local disk_name="$1"
    lsblk -n -o MOUNTPOINT "/dev/$disk_name" | grep -q .
}

# Function to format and mount a disk
format_and_mount_disk() {
    local disk_name="$1"
    local test_type="$2"
    local mount_dir=$(get_mount_point "$disk_name" "$test_type")

    echo -e "${GRN}Processing disk /dev/${disk_name} (mount point: ${mount_dir})...${NC}"

    # Check if disk is mounted
    if is_mounted "$disk_name"; then
        echo -e "${RED}Warning: /dev/${disk_name} is mounted. Skipping to avoid data loss.${NC}"
        return 0  # Treat as non-failure
    fi

    # Create mount directory
    mkdir -p "$mount_dir" || {
        echo -e "${RED}Error: Failed to create mount directory ${mount_dir}${NC}"
        return 1
    }

    # Format disk with ext4 (no partitioning, whole disk)
    echo -e "${GRN}Formatting /dev/${disk_name} with ${FS_TYPE}...${NC}"
    mkfs.${FS_TYPE} -F "/dev/${disk_name}" >/dev/null 2>&1 || {
        echo -e "${RED}Error: Failed to format /dev/${disk_name}${NC}"
        return 1
    }

    # Mount disk
    echo -e "${GRN}Mounting /dev/${disk_name} to ${mount_dir}...${NC}"
    mount "/dev/${disk_name}" "$mount_dir" || {
        echo -e "${RED}Error: Failed to mount /dev/${disk_name} to ${mount_dir}${NC}"
        return 1
    }

    echo -e "${GRN}Successfully formatted and mounted /dev/${disk_name} to ${mount_dir}${NC}"
    return 0
}

# Main execution
check_root

# --- Argument Handling ---
if [ $# -lt 1 ]; then
    echo -e "${RED}Usage: $0 <device|test_type>${NC}"
    exit 1
fi

arg1="$1"

# Check if argument is a device (e.g., /dev/sdb or sdb)
if [[ "$arg1" =~ ^/dev/ ]]; then
    disk_name="${arg1##*/}"
    single_disk_mode=1
elif [[ "$arg1" =~ ^sd[a-z]+$ ]]; then
    disk_name="$arg1"
    single_disk_mode=1
else
    test_type="$arg1"
    single_disk_mode=0
fi

if [ "$single_disk_mode" = "1" ]; then
    # --- Single Disk Mode ---
    os_drive=$(get_os_drive)
    if [ "$disk_name" = "$os_drive" ]; then
        echo -e "${RED}ERROR: Attempted to format OS drive /dev/$disk_name. This should never happen.${NC}"
        exit 1
    fi
    if ! verify_disk_safety "$disk_name" "$os_drive"; then
        exit 1
    fi
    echo -e "${YEL}WARNING: The following disk will be formatted:${NC}"
    echo -e "${YEL}  /dev/$disk_name${NC}"
    echo -e "${YEL}ALL DATA ON THIS DISK WILL BE LOST!${NC}"
    read -p "Are you sure you want to continue? (yes/NO): " confirm
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${GRN}Operation cancelled by user${NC}"
        exit 0
    fi
    if format_and_mount_disk "$disk_name" "24hdd"; then
        if is_mounted "$disk_name"; then
            echo -e "${GRN}Successfully processed /dev/$disk_name.${NC}"
        else
            echo -e "${YEL}/dev/$disk_name was not mounted after formatting.${NC}"
        fi
    else
        echo -e "${RED}Failed to process /dev/$disk_name.${NC}"
        exit 1
    fi
    echo -e "${GRN}Disk formatting and mounting completed successfully.${NC}"
    exit 0
fi

# --- Multi-Disk (Test Type) Mode ---
# Get test type from argument (already set above)
echo -e "${GRN}Detecting available disks for $test_type testing...${NC}"
disks=($(detect_disks "$test_type"))
if [ ${#disks[@]} -eq 0 ]; then
    echo -e "${RED}Error: No disks detected in the system for $test_type testing${NC}"
    exit 1
fi

echo -e "${GRN}Found ${#disks[@]} disks: ${disks[*]}${NC}"

echo -e "${YEL}WARNING: The following disks will be formatted:${NC}"
for disk in "${disks[@]}"; do
    echo -e "${YEL}  /dev/$disk${NC}"
done
echo -e "${YEL}ALL DATA ON THESE DISKS WILL BE LOST!${NC}"
read -p "Are you sure you want to continue? (yes/NO): " confirm
if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${GRN}Operation cancelled by user${NC}"
    exit 0
fi

success_count=0
skipped_count=0
failure_count=0
for disk in "${disks[@]}"; do
    if format_and_mount_disk "$disk" "$test_type"; then
        if is_mounted "$disk"; then
            ((success_count++))
        else
            ((skipped_count++))
        fi
    else
        ((failure_count++))
    fi
done

echo -e "${GRN}Processing complete.${NC}"
echo -e "${GRN}Successfully processed ${success_count} disks.${NC}"
if [ $skipped_count -gt 0 ]; then
    echo -e "${GRN}Skipped ${skipped_count} disks (already mounted or not processed).${NC}"
fi
if [ $failure_count -gt 0 ]; then
    echo -e "${RED}Failed to process ${failure_count} disks.${NC}"
fi

if [ $success_count -eq 0 ]; then
    echo -e "${RED}Error: No disks were successfully processed${NC}"
    exit 1
fi

echo -e "${GRN}Disk formatting and mounting completed successfully.${NC}"
exit 0
