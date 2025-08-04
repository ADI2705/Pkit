#!/bin/bash

# === Single HDD Test Script - Fixed Version ===
# Runs comprehensive FIO tests on a single HDD

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
source "${SCRIPT_DIR}/config/servertest.conf"
source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/disk_size.sh"

# FIO parameters
PRECOND_BLOCK_SIZE="1M"
PRECOND_IO_DEPTH="1"
PRECOND_NUM_JOBS="1"
FIO_BLOCK_SIZE="4k"
FIO_TEST_FILE="fio_test_file"
FIO_RUNTIME="60"
FIO_TEST_SIZE="100G"

# IO depths and numjobs to test
unset IO_DEPTHS
unset NUM_JOBS
IO_DEPTHS=(1 2 4 8 16 32)
NUM_JOBS=(1 2 4 8 16 32 48)

# Global variables
declare -a MONITOR_PIDS=()
SCRIPT_EXIT_CODE=0

# Check arguments
if [ $# -ne 3 ]; then
    log "ERROR" "Usage: $0 <test_dir> <tag> <device>"
    exit 1
fi

TEST_DIR="$1"
TAG="$2"
DEVICE="$3"

# Validate inputs
if [ ! -d "$(dirname "$TEST_DIR")" ]; then
    log "ERROR" "Parent directory of test directory does not exist: $(dirname "$TEST_DIR")"
    exit 1
fi

if [ -z "$TAG" ]; then
    log "ERROR" "Tag cannot be empty"
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    log "ERROR" "Device $DEVICE is not a valid block device"
    exit 1
fi

# Check if required scripts exist
required_scripts=(
    "${SCRIPT_DIR}/scripts/monitor_cpu.sh"
    "${SCRIPT_DIR}/scripts/monitor_psu.sh"
    "${SCRIPT_DIR}/scripts/monitor_fan.sh"
    "${SCRIPT_DIR}/scripts/monitor_mem.sh"
    "${SCRIPT_DIR}/scripts/monitor_temp.sh"
    "${SCRIPT_DIR}/scripts/cpu_temp.sh"
    "${SCRIPT_DIR}/scripts/hba.sh"
    "${SCRIPT_DIR}/scripts/dimm_temp.sh"
)

for script in "${required_scripts[@]}"; do
    if [ ! -x "$script" ]; then
        log "ERROR" "Required monitoring script not found or not executable: $script"
        exit 1
    fi
done

# Check if FIO is available
if ! command -v fio >/dev/null 2>&1; then
    log "ERROR" "FIO is not installed or not in PATH"
    exit 1
fi

# Get disk info
info=$(get_disk_info_from_state "$DEVICE")
if [ $? -ne 0 ]; then
    log "ERROR" "Failed to get disk info for $DEVICE"
    exit 1
fi

# Parse disk info
IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"

# Validate parsed info
if [ -z "$size" ] || [ -z "$mount_point" ] || [ -z "$model" ]; then
    log "ERROR" "Invalid disk info returned for $DEVICE"
    exit 1
fi

# Check if disk is safe
if [ "$is_safe" != "true" ]; then
    log "ERROR" "Disk $DEVICE is not safe to test"
    exit 1
fi

# Check if mount point exists and is mounted
if [ ! -d "$mount_point" ]; then
    log "ERROR" "Mount point does not exist: $mount_point"
    exit 1
fi

if ! mountpoint -q "$mount_point" 2>/dev/null; then
    log "ERROR" "Mount point is not mounted: $mount_point"
    exit 1
fi

# Check available disk space (need at least 150GB for 100GB test + overhead)
available_space=$(df -BG "$mount_point" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$available_space" -lt 150 ]; then
    log "ERROR" "Insufficient disk space. Available: ${available_space}GB, Required: 150GB"
    exit 1
fi

log "INFO" "Disk validation passed - Device: $DEVICE, Size: ${size}GB, Model: $model, Mount: $mount_point"

# Create test directory structure
test_dirs=(
    "${TEST_DIR}/precondition/fio"
    "${TEST_DIR}/precondition/HW"
    "${TEST_DIR}/write/fio"
    "${TEST_DIR}/write/HW"
    "${TEST_DIR}/read/fio"
    "${TEST_DIR}/read/HW"
    "${TEST_DIR}/randwrite/fio"
    "${TEST_DIR}/randwrite/HW"
    "${TEST_DIR}/randread/fio"
    "${TEST_DIR}/randread/HW"
    "${TEST_DIR}/randrw/fio"
    "${TEST_DIR}/randrw/HW"
)

for dir in "${test_dirs[@]}"; do
    if ! mkdir -p "$dir"; then
        log "ERROR" "Failed to create directory: $dir"
        exit 1
    fi
done

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up monitoring processes..."
    stop_monitoring
    
    # Clean up test file if it exists
    if [ -f "${mount_point}/${FIO_TEST_FILE}" ]; then
        log "INFO" "Removing test file: ${mount_point}/${FIO_TEST_FILE}"
        rm -f "${mount_point}/${FIO_TEST_FILE}" 2>/dev/null
    fi
}

# Set up trap for cleanup (removed EXIT trap to prevent forced exit 1)
trap cleanup SIGINT SIGTERM

# Function to stop monitoring with timeout
stop_monitoring() {
    if [ ${#MONITOR_PIDS[@]} -eq 0 ]; then
        return 0
    fi
    
    local stop_time=$(date +%s)
    log "INFO" "Stopping monitoring at $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Send TERM signal to all monitoring processes
    for pid in "${MONITOR_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
        fi
    done
    
    # Wait up to 10 seconds for graceful shutdown
    local timeout=10
    local count=0
    while [ $count -lt $timeout ]; do
        local running=0
        for pid in "${MONITOR_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                running=$((running + 1))
            fi
        done
        
        if [ $running -eq 0 ]; then
            break
        fi
        
        sleep 1
        count=$((count + 1))
    done
    
    # Force kill any remaining processes
    for pid in "${MONITOR_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log "WARN" "Force killing monitoring process (PID: $pid)"
            kill -KILL "$pid" 2>/dev/null
        fi
    done
    
    # Wait for all processes to be reaped
    for pid in "${MONITOR_PIDS[@]}"; do
        wait "$pid" 2>/dev/null
    done
    
    # Clear the array
    MONITOR_PIDS=()
    log "INFO" "All monitoring processes stopped"
}

# Function to run monitoring scripts
run_monitoring() {
    local test_dir="$1"
    local cpu_dir="${test_dir}/HW"
    local start_time=$(date +%s)
    
    log "INFO" "Starting monitoring for $test_dir at $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Clear any existing monitoring processes
    stop_monitoring
    
    # Ensure HW directory exists
    mkdir -p "$cpu_dir"
    
    # Create empty CSV files with headers matching the monitoring scripts' output format
    echo "Timestamp,User%,System%,Idle%" > "${cpu_dir}/cpu.csv"
    echo "Timestamp,FAN1_RPM,FAN2_RPM,FAN3_RPM,FAN4_RPM,FANA_RPM" > "${cpu_dir}/fan.csv"
    echo "Timestamp,Total_Memory_MB,Used_Memory_MB,Free_Memory_MB,Shared_Memory_MB,Buffer_Cache_MB,Available_Memory_MB" > "${cpu_dir}/mem.csv"
    
    # Run monitoring scripts in background with correct arguments
    "${SCRIPT_DIR}/scripts/monitor_cpu.sh" "${cpu_dir}/cpu.csv" "10" &
    MONITOR_PIDS+=($!)

    "${SCRIPT_DIR}/scripts/monitor_psu.sh" "${cpu_dir}/psu.csv" "10" &
    MONITOR_PIDS+=($!)
    
    "${SCRIPT_DIR}/scripts/monitor_fan.sh" "${cpu_dir}/fan.csv" "10" &
    MONITOR_PIDS+=($!)
    
    "${SCRIPT_DIR}/scripts/monitor_mem.sh" "${cpu_dir}/mem.csv" "10" &
    MONITOR_PIDS+=($!)
    
    "${SCRIPT_DIR}/scripts/monitor_temp.sh" "${cpu_dir}/temp.csv" "10" &
    MONITOR_PIDS+=($!)


    "${SCRIPT_DIR}/scripts/cpu_temp.sh" "${cpu_dir}/cpu_temp.csv" "10" &
    MONITOR_PIDS+=($!)

   HBA_CONTROLLERS="1,2"  # Adjust this based on your system

# Then use it in the call
"${SCRIPT_DIR}/scripts/hba.sh" "${cpu_dir}/hba_temp.csv" "10" "${HBA_CONTROLLERS}" &
MONITOR_PIDS+=($!)

    "${SCRIPT_DIR}/scripts/dimm_temp.sh" "${cpu_dir}/dimm_temp.csv" "10" &
    MONITOR_PIDS+=($!)
    
    # Wait a moment to ensure all monitors are running
    sleep 1
    
    # Verify all monitors are running
    for pid in "${MONITOR_PIDS[@]}"; do
        if ! kill -0 $pid 2>/dev/null; then
            log "ERROR" "Failed to start monitoring process (PID: $pid)"
            stop_monitoring
            return 1
        fi
    done
    
    log "INFO" "All monitoring processes started successfully for $test_dir"
    return 0
}

# Function to run precondition
#run_precondition() {
    #local test_name="precondition"
    #log "INFO" "Running precondition on $DEVICE"
    
    # Create log file
   # local log_file="${TEST_DIR}/precondition/fio/${test_name}_${TAG}.log"
    
    # Start monitoring
    #if ! run_monitoring "${TEST_DIR}/precondition"; then
       # log "ERROR" "Failed to start monitoring for precondition"
        #return 1
    #fi
    
    # Run FIO precondition
    #log "INFO" "Starting FIO precondition write to entire disk (${size}GB)"
    #fio --name="$test_name" \
     #   --directory="$mount_point" \
      #  --filename="$FIO_TEST_FILE" \
       # --ioengine=libaio \
        #--bs="$PRECOND_BLOCK_SIZE" \
        #--rw=write \
        #--direct=1 \
        #--iodepth="$PRECOND_IO_DEPTH" \
        #--numjobs="$PRECOND_NUM_JOBS" \
       # --size="${size}G" \
        #--overwrite=1 \
        #--allow_mounted_write=1 \
        #--group_reporting >> "$log_file" 2>&1 &
    
   # local fio_pid=$!
    
    # Wait for FIO to complete
    #wait $fio_pid
    #local fio_status=$?
    
    # Stop monitoring
    #stop_monitoring
    
    # Check FIO result
    #if [ $fio_status -ne 0 ]; then
     #   log "ERROR" "Precondition failed on $DEVICE (exit code: $fio_status)"
      #  return 1
    #fi
    
    #log "INFO" "Precondition completed successfully"
   # return 0
#}

# Function to run individual FIO test
run_fio_test() {
    local test_pattern="$1"
    local iodepth="$2"
    local numjobs="$3"
    local log_file="$4"
    
    log "INFO" "Running $test_pattern (iodepth=$iodepth, numjobs=$numjobs) on $DEVICE"
    
    # Build FIO command
    local fio_cmd="fio --name=\"$test_pattern\" \
        --directory=\"$mount_point\" \
        --filename=\"$FIO_TEST_FILE\" \
        --ioengine=libaio \
        --bs=4k \
        --rw=\"$test_pattern\" \
        --direct=1 \
        --iodepth=\"$iodepth\" \
        --numjobs=\"$numjobs\" \
        --size=\"$FIO_TEST_SIZE\" \
        --runtime=\"$FIO_RUNTIME\" \
        --time_based \
        --overwrite=1 \
        --allow_mounted_write=1 \
        --group_reporting"
    
    # Add randrw specific parameters
    if [ "$test_pattern" = "randrw" ]; then
        fio_cmd="$fio_cmd --unified_rw_reporting=1 --rwmixread=70"
    fi
    
    # Run FIO test
    eval "$fio_cmd" >> "$log_file" 2>&1 &
    local fio_pid=$!
    
    # Wait for FIO to complete
    wait $fio_pid
    local fio_status=$?
    
    # Check result
    if [ $fio_status -ne 0 ]; then
        log "ERROR" "FIO test failed: $test_pattern (iodepth=$iodepth, numjobs=$numjobs) - exit code: $fio_status"
        return 1
    fi
    
    log "INFO" "Completed $test_pattern (iodepth=$iodepth, numjobs=$numjobs)"
    return 0
}

# Main execution starts here
log "INFO" "Starting FIO tests on $DEVICE (${size}GB - $model)"

# Run precondition (uncommented and fixed)
#log "INFO" "Starting precondition on $DEVICE (${size}GB - $model)"
#if ! run_precondition; then
  #  log "ERROR" "Precondition failed, aborting tests"
   # cleanup
  #  exit 1
#fi

# Ordered test patterns
TEST_PATTERNS=("write" "read" "randwrite" "randread" "randrw")

# Run all FIO tests
for test_pattern in "${TEST_PATTERNS[@]}"; do
    log "INFO" "Starting $test_pattern tests"
    
    # Start monitoring for this test pattern
    if ! run_monitoring "${TEST_DIR}/$test_pattern"; then
        log "ERROR" "Failed to start monitoring for $test_pattern tests"
        SCRIPT_EXIT_CODE=1
        break
    fi
    
    # Track if any test in this pattern failed
    pattern_failed=false
    
    # Run tests for all combinations of iodepth and numjobs
    for iodepth in "${IO_DEPTHS[@]}"; do
        for numjobs in "${NUM_JOBS[@]}"; do
            log_file="${TEST_DIR}/${test_pattern}/fio/${test_pattern}_iod${iodepth}_jobs${numjobs}_${TAG}.log"
            
            if ! run_fio_test "$test_pattern" "$iodepth" "$numjobs" "$log_file"; then
                log "ERROR" "Test failed: $test_pattern (iodepth=$iodepth, numjobs=$numjobs)"
                pattern_failed=true
                SCRIPT_EXIT_CODE=1
                # Continue with other tests rather than aborting completely
            fi
        done
    done
    
    # Stop monitoring for this pattern
    stop_monitoring
    
    if [ "$pattern_failed" = true ]; then
        log "WARN" "$test_pattern pattern had failures, but continuing with remaining tests"
    else
        log "INFO" "$test_pattern tests completed successfully"
    fi
done

# Final cleanup
cleanup

# Final status
if [ $SCRIPT_EXIT_CODE -eq 0 ]; then
    log "INFO" "All tests completed successfully for $DEVICE"
else
    log "WARN" "Tests completed with some failures for $DEVICE"
fi

exit $SCRIPT_EXIT_CODE