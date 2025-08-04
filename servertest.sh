#!/bin/bash

# === Main Server Test Script ===
# Entry point for storage performance testing (HDDs and NVMEs)

# Source configuration and scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config/servertest.conf"
source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/disk_size.sh"

# Initialize arrays
declare -a ALL_HDDS=()
declare -a ALL_NVMES=()
declare -a SAFE_HDDS=()
declare -a SAFE_NVMES=()

# Export arrays
declare -x ALL_HDDS
declare -x ALL_NVMES
declare -x SAFE_HDDS
declare -x SAFE_NVMES

# Function to check dependencies
check_dependencies() {
    log "INFO" "Checking dependencies..."
    local deps=("fio" "parallel" "df" "blkid" "lsblk" "findmnt" "jq" "cpu-x")
    local sbin_deps=("mkfs.ext4")
    local nvme_deps=("nvme")  # Add nvme-cli for NVME support
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "ERROR" "$cmd not installed"
            return 1
        fi
    done

    for cmd in "${sbin_deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1 && ! [ -f "/usr/sbin/$cmd" ]; then
            log "ERROR" "$cmd not installed"
            return 1
        fi
    done
    
    # Check NVME dependencies
    for cmd in "${nvme_deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "WARN" "$cmd not installed - NVME tests will have limited functionality"
        fi
    done
    
    log "INFO" "All dependencies satisfied"
    return 0
}

# Function to display available HDDs
display_hdds() {
    echo "Available HDDs:"
    if [ ${#SAFE_HDDS[@]} -eq 0 ]; then
        echo "No HDDs detected"
        return 1
    fi
    
    local i=1
    for hdd in "${SAFE_HDDS[@]}"; do
        local info
        info=$(get_disk_info_from_state "$hdd")
        if [ $? -eq 0 ]; then
            IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
            echo "$i. $hdd (${size}GB) - $model"
            if [ -n "$mount_point" ]; then
                echo "   Mounted at: $mount_point"
            fi
        else
            echo "$i. $hdd"
        fi
        ((i++))
    done
    return 0
}

# Function to display available NVMEs
display_nvmes() {
    echo "Available NVME devices:"
    if [ ${#SAFE_NVMES[@]} -eq 0 ]; then
        echo "No NVME devices detected"
        return 1
    fi
    
    local i=1
    for nvme in "${SAFE_NVMES[@]}"; do
        local info
        info=$(get_disk_info_from_state "$nvme")
        if [ $? -eq 0 ]; then
            IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
            
            # Try to get NVME-specific info
            local nvme_model=""
            local nvme_serial=""
            if command -v nvme >/dev/null 2>&1; then
                nvme_model=$(nvme id-ctrl "$nvme" 2>/dev/null | grep "^mn" | sed 's/mn.*: //' | xargs)
                nvme_serial=$(nvme id-ctrl "$nvme" 2>/dev/null | grep "^sn" | sed 's/sn.*: //' | xargs)
            fi
            
            if [ -n "$nvme_model" ]; then
                echo "$i. $nvme (${size}GB) - $nvme_model"
                if [ -n "$nvme_serial" ]; then
                    echo "   Serial: $nvme_serial"
                fi
            else
                echo "$i. $nvme (${size}GB) - $model"
            fi
            
            if [ -n "$mount_point" ]; then
                echo "   Mounted at: $mount_point"
            fi
        else
            echo "$i. $nvme"
        fi
        ((i++))
    done
    return 0
}

# Function to run single HDD test
run_single_hdd_test() {
    # Save hardware details before test
    "${SCRIPT_DIR}/scripts/hw_details.sh" > "${SCRIPT_DIR}/hw_details.txt"
    display_hdds
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo -n "Select disk number: "
    read -r choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#SAFE_HDDS[@]} ]; then
        log "ERROR" "Invalid disk selection"
        return 1
    fi
    
    local selected_disk="${SAFE_HDDS[$((choice-1))]}"
    local test_dir="${SCRIPT_DIR}/tests/single_hdd"
    local tag="test_$(date +%Y%m%d_%H%M%S)"
    
    # Create test directory
    mkdir -p "$test_dir"
    
    # Create log file
    local log_file="${test_dir}/test.log"
    touch "$log_file"
    
    # Setup log file
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    
    log "INFO" "Running single HDD test on $selected_disk"
    "${SCRIPT_DIR}/scripts/single_hdd_test.sh" "$test_dir" "$tag" "$selected_disk"
}

# Function to run single NVME test
run_single_nvme_test() {
    # Save hardware details before test
    "${SCRIPT_DIR}/scripts/hw_details.sh" > "${SCRIPT_DIR}/hw_details.txt"
    display_nvmes
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo -n "Select NVME number: "
    read -r choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#SAFE_NVMES[@]} ]; then
        log "ERROR" "Invalid NVME selection"
        return 1
    fi
    
    local selected_nvme="${SAFE_NVMES[$((choice-1))]}"
    local test_dir="${SCRIPT_DIR}/tests/single_nvme"
    local tag="test_$(date +%Y%m%d_%H%M%S)"
    
    # Create test directory
    mkdir -p "$test_dir"
    
    # Create log file
    local log_file="${test_dir}/test.log"
    touch "$log_file"
    
    # Setup log file
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    
    log "INFO" "Running single NVME test on $selected_nvme"
    "${SCRIPT_DIR}/scripts/single_nvme_test.sh" "$test_dir" "$tag" "$selected_nvme"
}

# Function to run multiple HDD test
run_multiple_hdd_test() {
    # Save hardware details before test
    "${SCRIPT_DIR}/scripts/hw_details.sh" > "${SCRIPT_DIR}/hw_details.txt"
    display_hdds
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo -n "Enter disk numbers to test (space-separated) or 'all' for all disks: "
    read -r choices
    
    # Get selected disks
    local selected_disks=()
    
    if [ "$choices" = "all" ]; then
        selected_disks=("${SAFE_HDDS[@]}")
        log "INFO" "Selected all ${#selected_disks[@]} disks for testing"
    else
        # Convert choices to array
        read -ra selected_indices <<< "$choices"
        
        # Validate choices
        for idx in "${selected_indices[@]}"; do
            if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt ${#SAFE_HDDS[@]} ]; then
                log "ERROR" "Invalid disk selection: $idx"
                return 1
            fi
        done
        
        # Get selected disks
        for idx in "${selected_indices[@]}"; do
            selected_disks+=("${SAFE_HDDS[$((idx-1))]}")
        done
    fi
    
    # Create test directory
    local test_dir="${SCRIPT_DIR}/tests/multiple_hdd"
    mkdir -p "$test_dir"
    
    # Create log file
    local log_file="${test_dir}/test.log"
    touch "$log_file"
    
    # Setup log file
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    
    local tag="test_$(date +%Y%m%d_%H%M%S)"
    
    # Export arrays for child scripts
    export SAFE_HDDS
    export SAFE_NVMES
    
    log "INFO" "Running multiple HDD test on ${#selected_disks[@]} disks: ${selected_disks[*]}"
    
    # Run multiple HDD test script with all selected disks
    "${SCRIPT_DIR}/scripts/multiple_hdd_test.sh" "$test_dir" "$tag" "${selected_disks[@]}"
}

# Function to run multiple NVME test
run_multiple_nvme_test() {
    # Save hardware details before test
    "${SCRIPT_DIR}/scripts/hw_details.sh" > "${SCRIPT_DIR}/hw_details.txt"
    display_nvmes
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo -n "Enter NVME numbers to test (space-separated) or 'all' for all NVMEs: "
    read -r choices
    
    # Get selected NVMEs
    local selected_nvmes=()
    
    if [ "$choices" = "all" ]; then
        selected_nvmes=("${SAFE_NVMES[@]}")
        log "INFO" "Selected all ${#selected_nvmes[@]} NVME devices for testing"
    else
        # Convert choices to array
        read -ra selected_indices <<< "$choices"
        
        # Validate choices
        for idx in "${selected_indices[@]}"; do
            if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt ${#SAFE_NVMES[@]} ]; then
                log "ERROR" "Invalid NVME selection: $idx"
                return 1
            fi
        done
        
        # Get selected NVMEs
        for idx in "${selected_indices[@]}"; do
            selected_nvmes+=("${SAFE_NVMES[$((idx-1))]}")
        done
    fi
    
    # Create test directory
    local test_dir="${SCRIPT_DIR}/tests/multiple_nvme"
    mkdir -p "$test_dir"
    
    # Create log file
    local log_file="${test_dir}/test.log"
    touch "$log_file"
    
    # Setup log file
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    
    local tag="test_$(date +%Y%m%d_%H%M%S)"
    
    # Export arrays for child scripts
    export SAFE_HDDS
    export SAFE_NVMES
    
    log "INFO" "Running multiple NVME test on ${#selected_nvmes[@]} devices: ${selected_nvmes[*]}"
    
    # Run multiple NVME test script with all selected devices
    "${SCRIPT_DIR}/scripts/multiple_nvme_test.sh" "$test_dir" "$tag" "${selected_nvmes[@]}"
}

# Function to run continuous HDD test (multiple HDD test, then single disk format+test)
run_continuous_hdd_test() {
    # Save hardware details before test
    "${SCRIPT_DIR}/scripts/hw_details.sh" > "${SCRIPT_DIR}/hw_details.txt"
    # Step 1: Run multiple HDD test
    run_multiple_hdd_test
    
    # Step 2: Prompt for single disk to format and test
    display_hdds
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo -n "Select disk number for single disk format and test: "
    read -r choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#SAFE_HDDS[@]} ]; then
        log "ERROR" "Invalid disk selection"
        return 1
    fi
    local selected_disk="${SAFE_HDDS[$((choice-1))]}"
    
    # Step 3: Format the selected disk using format.sh (format only that disk)
    echo "Formatting $selected_disk using format.sh..."
    sudo bash "$SCRIPT_DIR/format.sh" "$selected_disk"
    
    # Step 4: Run single HDD test on the formatted disk
    local test_dir="${SCRIPT_DIR}/tests/single_hdd"
    local tag="test_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$test_dir"
    local log_file="${test_dir}/test.log"
    touch "$log_file"
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    log "INFO" "Running single HDD test on $selected_disk after format"
    "$SCRIPT_DIR/scripts/single_hdd_test.sh" "$test_dir" "$tag" "$selected_disk"
}

# Function to run continuous NVME test (multiple NVME test, then single device raw test)
run_continuous_nvme_test() {
    # Save hardware details before test
    "${SCRIPT_DIR}/scripts/hw_details.sh" > "${SCRIPT_DIR}/hw_details.txt"
    # Step 1: Run multiple NVME test
    run_multiple_nvme_test
    
    # Step 2: Prompt for single NVME device for additional raw testing
    display_nvmes
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo -n "Select NVME number for single device extended test: "
    read -r choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#SAFE_NVMES[@]} ]; then
        log "ERROR" "Invalid NVME selection"
        return 1
    fi
    local selected_nvme="${SAFE_NVMES[$((choice-1))]}"
    
    # Step 3: Run single NVME test on the selected device
    local test_dir="${SCRIPT_DIR}/tests/single_nvme_extended"
    local tag="test_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$test_dir"
    local log_file="${test_dir}/test.log"
    touch "$log_file"
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    log "INFO" "Running extended single NVME test on $selected_nvme"
    "$SCRIPT_DIR/scripts/single_nvme_test.sh" "$test_dir" "$tag" "$selected_nvme"
}

# Function to show device summary
show_device_summary() {
    echo -e "\n=== Device Summary ==="
    
    echo -e "\nHDD Devices:"
    if [ ${#SAFE_HDDS[@]} -eq 0 ]; then
        echo "  No safe HDDs detected"
    else
        for hdd in "${SAFE_HDDS[@]}"; do
            local info
            info=$(get_disk_info_from_state "$hdd")
            if [ $? -eq 0 ]; then
                IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
                echo "  $hdd (${size}GB) - $model"
            fi
        done
    fi
    
    echo -e "\nNVME Devices:"
    if [ ${#SAFE_NVMES[@]} -eq 0 ]; then
        echo "  No safe NVME devices detected"
    else
        for nvme in "${SAFE_NVMES[@]}"; do
            local info
            info=$(get_disk_info_from_state "$nvme")
            if [ $? -eq 0 ]; then
                IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
                
                # Try to get NVME-specific info
                local nvme_model=""
                if command -v nvme >/dev/null 2>&1; then
                    nvme_model=$(nvme id-ctrl "$nvme" 2>/dev/null | grep "^mn" | sed 's/mn.*: //' | xargs)
                fi
                
                if [ -n "$nvme_model" ]; then
                    echo "  $nvme (${size}GB) - $nvme_model"
                else
                    echo "  $nvme (${size}GB) - $model"
                fi
            fi
        done
    fi
    echo ""
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check dependencies
    if ! check_dependencies; then
        log "ERROR" "Dependency check failed"
        exit 1
    fi

    # Install CPU-X if not present (so logs appear after dependency check)
    if ! command -v cpu-x >/dev/null 2>&1; then
        "${SCRIPT_DIR}/scripts/install_cpu-x.sh"
    fi

    log "INFO" "All dependencies satisfied"

    # Initialize disk arrays
    if ! init_disk_arrays; then
        log "ERROR" "Failed to initialize disk arrays"
        exit 1
    fi

    # Save hardware details before showing menu
    "${SCRIPT_DIR}/scripts/hw_details.sh" > "${SCRIPT_DIR}/hw_details.txt"

    # Save software details before showing menu
    "${SCRIPT_DIR}/scripts/software_details.sh" > "${SCRIPT_DIR}/sw_summary.txt"

    # Main menu loop
    while true; do
        echo -e "\n=== Server Storage Test Menu ==="
        echo "1. Single HDD Test"
        echo "2. Multiple HDD Test"
        echo "3. Continuous HDD Test (Multiple -> Format -> Single)"
        echo "4. Single NVME Test"
        echo "5. Multiple NVME Test"
        echo "6. Continuous NVME Test (Multiple -> Extended Single)"
        echo "7. Show Device Summary"
        echo "8. Exit"
        
        echo -ne "\nEnter your choice (1-8): "
        read -r choice
        
        case $choice in
            1)
                run_single_hdd_test
                ;;
            2)
                run_multiple_hdd_test
                ;;
            3)
                run_continuous_hdd_test
                ;;
            4)
                run_single_nvme_test
                ;;
            5)
                run_multiple_nvme_test
                ;;
            6)
                run_continuous_nvme_test
                ;;
            7)
                show_device_summary
                ;;
            8)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
    done
fi
