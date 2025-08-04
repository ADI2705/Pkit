#!/bin/bash

# === Multiple NVME Test Script ===
# Runs comprehensive FIO tests on multiple NVMEs in parallel
# Safety check relies solely on get_disk_info_from_state

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
source "${SCRIPT_DIR}/config/servertest.conf"
source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/disk_size.sh"

# FIO parameters for NVME
PRECOND_BLOCK_SIZE_STAGE1="128k"
PRECOND_IO_DEPTH="128"
PRECOND_NUM_JOBS="1"
PRECOND_LOOPS="2"
FIO_TEST_FILE="fio_test_file"
FIO_RUNTIME="120"  # NVME tests typically run longer
unset IO_DEPTHS
unset NUM_JOBS
unset BLOCK_SIZES
# Block sizes to test
BLOCK_SIZES=("128k" "4k")
# IO depths and numjobs to test
IO_DEPTHS=(1 2 4 8 16 32 64 128)
NUM_JOBS=(1 2 4 8 16 32 48)
NUM_JOBS_RANDOM=(1 2 4 8 16 32 48)

# Check arguments
if [ $# -lt 3 ]; then
    log "ERROR" "Usage: $0 <test_dir> <tag> <device1> [device2] [device3] ..."
    exit 1
fi

TEST_DIR="$1"
TAG="$2"
shift 2
DEVICES=("$@")

# Log the devices we're testing
log "INFO" "Testing devices: ${DEVICES[*]}"

# Verify all devices are safe using get_disk_info_from_state
for device in "${DEVICES[@]}"; do
    if [ ! -b "$device" ]; then
        log "ERROR" "Device $device does not exist"
        exit 1
    fi
    
    # Get disk info from state (only safety check)
    info=$(get_disk_info_from_state "$device")
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to get disk info for $device"
        exit 1
    fi
    
    # Parse disk info
    IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
    
    # Check if disk is safe
    if [ "$is_safe" != "true" ]; then
        log "ERROR" "Device $device is not safe to test (per get_disk_info_from_state)"
        exit 1
    fi
    
    log "INFO" "Device $device is safe to test (${size}GB - $model)"
done

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
    
    # Create empty CSV files with headers
    echo "Timestamp,User%,System%,Idle%" > "${cpu_dir}/cpu.csv"
    echo "Timestamp,FAN1_RPM,FAN2_RPM,FAN3_RPM,FAN4_RPM,FANA_RPM" > "${cpu_dir}/fan.csv"
    echo "Timestamp,Total_Memory_MB,Used_Memory_MB,Free_Memory_MB,Shared_Memory_MB,Buffer_Cache_MB,Available_Memory_MB" > "${cpu_dir}/mem.csv"
    
    # Run monitoring scripts in background
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
    HBA_CONTROLLERS="1,2"
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

# Function to stop monitoring
stop_monitoring() {
    local stop_time=$(date +%s)
    log "INFO" "Stopping monitoring at $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Kill all monitoring processes
    for pid in "${MONITOR_PIDS[@]}"; do
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            wait $pid 2>/dev/null
        fi
    done
    
    # Clear the array
    MONITOR_PIDS=()
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up monitoring processes..."
    stop_monitoring
    exit 1
}

# Set up trap for cleanup
trap cleanup SIGINT SIGTERM EXIT

# Function to purge drives (remove test files if any)
purge_drives() {
    log "INFO" "Purging test files on all devices..."
    for device in "${DEVICES[@]}"; do
        log "INFO" "Device $device ready for testing"
    done
}

# Function to run NVME precondition on all devices in parallel
run_precondition_parallel() {
    local block_size="$1"
    local test_name="precondition_${block_size}"
    local parallel_cmds=()
    
    log "INFO" "Starting raw block precondition for block size $block_size"
    
    # Build parallel commands for each device
    for device in "${DEVICES[@]}"; do
        # Create log directory
        mkdir -p "${TEST_DIR}/precondition_${block_size}/fio"
        
        # Create log file
        local log_file="${TEST_DIR}/precondition_${block_size}/fio/${test_name}_${device##*/}_${TAG}.log"
        
        # Stage 1: 128k sequential write (raw block device)
        local stage1_cmd="fio --ioengine=libaio \
            --name=precondition_stage1 --filename=\"$device\" \
            --rw=write --bs=128k --iodepth=128 --numjobs=1 \
            --size=100% --direct=1 --group_reporting --overwrite=1"
        
        # Stage 2: Based on block size (raw block device)
        local stage2_cmd
        if [[ "$block_size" == "128k" ]]; then
            stage2_cmd="fio --ioengine=libaio \
                --name=precondition_stage2 --filename=\"$device\" \
                --rw=write --bs=\"$block_size\" --iodepth=128 --numjobs=1 --loops=2 \
                --size=100% --direct=1 --group_reporting --overwrite=1"
        else
            stage2_cmd="fio --norandommap --randrepeat=0 --ioengine=libaio \
                --name=precondition_stage2 --filename=\"$device\" \
                --rw=randwrite --bs=\"$block_size\" --iodepth=128 --numjobs=1 --loops=2 \
                --size=100% --direct=1 --group_reporting --overwrite=1"
        fi
        
        # Combine both stages
        local combined_cmd="($stage1_cmd && $stage2_cmd) >> \"$log_file\" 2>&1"
        parallel_cmds+=("$combined_cmd")
    done
    
    # Run all FIO commands in parallel
    printf "%s\n" "${parallel_cmds[@]}" | parallel -j 32 --bar --joblog "${TEST_DIR}/precondition_${block_size}/parallel.log"
    return $?
}

# Function to run FIO tests in parallel
run_fio_tests_parallel() {
    local test_name="$1"
    local rw="$2"
    local bs="$3"
    local iodepth="$4"
    local numjobs="$5"
    local parallel_cmds=()
    
    # Build parallel commands for each device
    for device in "${DEVICES[@]}"; do
        # Create log file
        local log_file="${TEST_DIR}/${test_name}_${bs}/fio/${test_name}_${device##*/}_${bs}_iod${iodepth}_jobs${numjobs}_${TAG}.log"
        
        # Build FIO command for raw block device
        local fio_cmd="fio --name=\"${test_name}_${device##*/}\" \
            --filename=\"$device\" \
            --ioengine=libaio \
            --bs=\"$bs\" \
            --rw=\"$rw\" \
            --direct=1 \
            --iodepth=\"$iodepth\" \
            --numjobs=\"$numjobs\" \
            --size=100% \
            --runtime=\"$FIO_RUNTIME\" \
            --time_based \
            --overwrite=1 \
            --group_reporting \
            --unified_rw_reporting=1 \
            --status-interval=1"
        
        # Add unified reporting for randrw
        if [ "$rw" = "randrw" ]; then
            fio_cmd="$fio_cmd --rwmixread=70"
        fi
        
        fio_cmd="$fio_cmd >> \"$log_file\" 2>&1"
        parallel_cmds+=("$fio_cmd")
    done
    
    # Run all FIO commands in parallel
    printf "%s\n" "${parallel_cmds[@]}" | parallel -j 32 --bar --joblog "${TEST_DIR}/${test_name}_${bs}/parallel.log"
    return $?
}

# [Monitoring and other functions remain unchanged]

# Create base test directory structure
mkdir -p "${TEST_DIR}"

# Main test loop - for each block size, precondition and test
for bs in "${BLOCK_SIZES[@]}"; do
    log "INFO" "Starting tests for block size: $bs"
    
    # Purge drives
    purge_drives
    
    # Create directory structure for this block size
    mkdir -p "${TEST_DIR}/precondition_${bs}/fio"
    mkdir -p "${TEST_DIR}/precondition_${bs}/HW"
    
    # Run precondition phase for this block size
    log "INFO" "Starting precondition phase for block size $bs"
    if ! run_monitoring "${TEST_DIR}/precondition_${bs}"; then
        exit 1
    fi

    if ! run_precondition_parallel "$bs"; then
        log "ERROR" "Precondition failed for block size $bs"
        stop_monitoring
        exit 1
    fi
    stop_monitoring
    
    # Determine test types based on block size
    if [[ "$bs" == "128k" ]]; then
        test_types=("write" "read")
    else
        test_types=("randwrite" "randread" "randrw")
    fi
    
    # Run tests for this block size
    for tt in "${test_types[@]}"; do
        log "INFO" "Starting $tt tests for block size $bs"
        
        # Create directory structure for this test type and block size
        mkdir -p "${TEST_DIR}/${tt}_${bs}/fio"
        mkdir -p "${TEST_DIR}/${tt}_${bs}/HW"
        
        if ! run_monitoring "${TEST_DIR}/${tt}_${bs}"; then
            exit 1
        fi

        for iodepth in "${IO_DEPTHS[@]}"; do
            # Use different numjobs array for random tests
            if [[ "$tt" =~ ^rand ]]; then
                current_numjobs=("${NUM_JOBS_RANDOM[@]}")
            else
                current_numjobs=("${NUM_JOBS[@]}")
            fi
            
            for numjobs in "${current_numjobs[@]}"; do
                if ! run_fio_tests_parallel "$tt" "$tt" "$bs" "$iodepth" "$numjobs"; then
                    log "ERROR" "$tt test failed for bs=$bs, iodepth=$iodepth, numjobs=$numjobs"
                    stop_monitoring
                    exit 1
                fi
            done
        done
        stop_monitoring
    done
    
    log "INFO" "Completed all tests for block size: $bs"
done

log "INFO" "All tests completed successfully"
exit 0
