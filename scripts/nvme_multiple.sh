#!/bin/bash

# === Multiple NVME Test Script ===
# Runs comprehensive FIO tests on multiple NVMEs in parallel

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
source "${SCRIPT_DIR}/config/servertest.conf"
source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/disk_size.sh"

# FIO parameters for NVME
PRECOND_BLOCK_SIZE_STAGE1="128k"
PRECOND_BLOCK_SIZE_STAGE2="4k"  # Will be set based on test type
PRECOND_IO_DEPTH="128"
PRECOND_NUM_JOBS="1"
PRECOND_LOOPS="2"
FIO_BLOCK_SIZE="4k"
FIO_TEST_FILE="fio_test_file"
FIO_RUNTIME="120"  # NVME tests typically run longer
unset IO_DEPTHS
unset NUM_JOBS
# IO depths and numjobs to test for NVME
IO_DEPTHS=(1 2 4 8 16 32 64 128)
NUM_JOBS=(1 2 4 8 16 32 48 64)
NUM_JOBS_RANDOM=(1 2 4 8 16 32)

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
log "INFO" "Testing NVME devices: ${DEVICES[*]}"

# Verify all devices exist and are safe
for device in "${DEVICES[@]}"; do
    if [ ! -b "$device" ]; then
        log "ERROR" "Device $device does not exist"
        exit 1
    fi
    
    # Get disk info
    info=$(get_disk_info_from_state "$device")
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to get disk info for $device"
        exit 1
    fi
    
    # Parse disk info
    IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
    
    # Check if disk is safe
    if [ "$is_safe" != "true" ]; then
        log "ERROR" "Disk $device is not safe to test"
        exit 1
    fi
    
    log "INFO" "Device $device is safe to test (${size}GB - $model)"
done

# Global array to store monitoring PIDs
declare -a MONITOR_PIDS=()

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up monitoring processes..."
    stop_monitoring
    exit 1
}

# Set up trap for cleanup
trap cleanup SIGINT SIGTERM EXIT

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

# Function to run NVME precondition stage 1 on all devices in parallel
run_precondition_stage1_parallel() {
    local test_name="precondition_stage1"
    local parallel_cmds=()
    
    log "INFO" "Starting precondition stage 1 (128k sequential write)"
    
    # Build parallel commands for each device
    for device in "${DEVICES[@]}"; do
        # Get disk info
        info=$(get_disk_info_from_state "$device")
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to get disk info for $device"
            return 1
        fi
        
        # Parse disk info
        IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
        
        # Create log file
        local log_file="${TEST_DIR}/precondition/fio/${test_name}_${device##*/}_${TAG}.log"
        
        # Build FIO command for raw device - Stage 1
        local fio_cmd="fio --name=\"$test_name\" \
            --filename=\"$device\" \
            --ioengine=libaio \
            --bs=\"$PRECOND_BLOCK_SIZE_STAGE1\" \
            --rw=write \
            --direct=1 \
            --iodepth=\"$PRECOND_IO_DEPTH\" \
            --numjobs=\"$PRECOND_NUM_JOBS\" \
            --size=100% \
            --overwrite=1 \
            --group_reporting >> \"$log_file\" 2>&1"
        
        parallel_cmds+=("$fio_cmd")
    done
    
    # Run all FIO commands in parallel
    printf "%s\n" "${parallel_cmds[@]}" | parallel -j 32 --bar --joblog "${TEST_DIR}/precondition/parallel_stage1.log"
    return $?
}

# Function to run NVME precondition stage 2 on all devices in parallel
run_precondition_stage2_parallel() {
    local block_size="$1"
    local test_name="precondition_stage2_${block_size}"
    local parallel_cmds=()
    
    log "INFO" "Starting precondition stage 2 with block size $block_size"
    
    # Build parallel commands for each device
    for device in "${DEVICES[@]}"; do
        # Get disk info
        info=$(get_disk_info_from_state "$device")
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to get disk info for $device"
            return 1
        fi
        
        # Parse disk info
        IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
        
        # Create log file
        local log_file="${TEST_DIR}/precondition/fio/${test_name}_${device##*/}_${TAG}.log"
        
        # Build FIO command for raw device - Stage 2
        local fio_cmd
        if [[ "$block_size" == "128k" ]]; then
            # Sequential write for 128k
            fio_cmd="fio --name=\"$test_name\" \
                --filename=\"$device\" \
                --ioengine=libaio \
                --bs=\"$block_size\" \
                --rw=write \
                --direct=1 \
                --iodepth=\"$PRECOND_IO_DEPTH\" \
                --numjobs=\"$PRECOND_NUM_JOBS\" \
                --size=100% \
                --loops=\"$PRECOND_LOOPS\" \
                --overwrite=1 \
                --group_reporting >> \"$log_file\" 2>&1"
        else
            # Random write for other block sizes
            fio_cmd="fio --norandommap --randrepeat=0 \
                --name=\"$test_name\" \
                --filename=\"$device\" \
                --ioengine=libaio \
                --bs=\"$block_size\" \
                --rw=randwrite \
                --direct=1 \
                --iodepth=\"$PRECOND_IO_DEPTH\" \
                --numjobs=\"$PRECOND_NUM_JOBS\" \
                --size=100% \
                --loops=\"$PRECOND_LOOPS\" \
                --overwrite=1 \
                --group_reporting >> \"$log_file\" 2>&1"
        fi
        
        parallel_cmds+=("$fio_cmd")
    done
    
    # Run all FIO commands in parallel
    printf "%s\n" "${parallel_cmds[@]}" | parallel -j 32 --bar --joblog "${TEST_DIR}/precondition/parallel_stage2_${block_size}.log"
    return $?
}

# Function to run FIO tests in parallel for NVME
run_fio_tests_parallel() {
    local test_name="$1"
    local rw="$2"
    local iodepth="$3"
    local numjobs="$4"
    local parallel_cmds=()
    
    # Build parallel commands for each device
    for device in "${DEVICES[@]}"; do
        # Get disk info
        info=$(get_disk_info_from_state "$device")
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to get disk info for $device"
            return 1
        fi
        
        # Parse disk info
        IFS=: read -r size is_os_disk is_safe mount_point model <<< "$info"
        
        # Create log file
        local log_file="${TEST_DIR}/${test_name}/fio/${test_name}_${device##*/}_iod${iodepth}_jobs${numjobs}_${TAG}.log"
        
        # Build FIO command for raw device
        local fio_cmd="fio --name=\"${test_name}_${device##*/}\" \
            --filename=\"$device\" \
            --ioengine=libaio \
            --bs=\"$FIO_BLOCK_SIZE\" \
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
    printf "%s\n" "${parallel_cmds[@]}" | parallel -j 32 --bar --joblog "${TEST_DIR}/${test_name}/parallel.log"
    return $?
}

# Create test directory structure
mkdir -p "${TEST_DIR}/precondition/fio"
mkdir -p "${TEST_DIR}/precondition/HW"
mkdir -p "${TEST_DIR}/write/fio"
mkdir -p "${TEST_DIR}/write/HW"
mkdir -p "${TEST_DIR}/read/fio"
mkdir -p "${TEST_DIR}/read/HW"
mkdir -p "${TEST_DIR}/randwrite/fio"
mkdir -p "${TEST_DIR}/randwrite/HW"
mkdir -p "${TEST_DIR}/randread/fio"
mkdir -p "${TEST_DIR}/randread/HW"
mkdir -p "${TEST_DIR}/randrw/fio"
mkdir -p "${TEST_DIR}/randrw/HW"

# Run NVME precondition phase
log "INFO" "Starting NVME precondition phase"
if ! run_monitoring "${TEST_DIR}/precondition"; then
    exit 1
fi

# Stage 1: 128k sequential write
if ! run_precondition_stage1_parallel; then
    log "ERROR" "Precondition stage 1 failed"
    stop_monitoring
    exit 1
fi

# Stage 2: Based on block size - for 4k tests, use 4k random write
if ! run_precondition_stage2_parallel "$FIO_BLOCK_SIZE"; then
    log "ERROR" "Precondition stage 2 failed"
    stop_monitoring
    exit 1
fi

stop_monitoring

# Run write tests
log "INFO" "Starting write tests"
if ! run_monitoring "${TEST_DIR}/write"; then
    exit 1
fi

for iodepth in "${IO_DEPTHS[@]}"; do
    for numjobs in "${NUM_JOBS[@]}"; do
        if ! run_fio_tests_parallel "write" "write" "$iodepth" "$numjobs"; then
            log "ERROR" "Write test failed for iodepth=$iodepth, numjobs=$numjobs"
            stop_monitoring
            exit 1
        fi
    done
done
stop_monitoring

# Run read tests
log "INFO" "Starting read tests"
if ! run_monitoring "${TEST_DIR}/read"; then
    exit 1
fi

for iodepth in "${IO_DEPTHS[@]}"; do
    for numjobs in "${NUM_JOBS[@]}"; do
        if ! run_fio_tests_parallel "read" "read" "$iodepth" "$numjobs"; then
            log "ERROR" "Read test failed for iodepth=$iodepth, numjobs=$numjobs"
            stop_monitoring
            exit 1
        fi
    done
done
stop_monitoring

# Run random write tests
log "INFO" "Starting random write tests"
if ! run_monitoring "${TEST_DIR}/randwrite"; then
    exit 1
fi

for iodepth in "${IO_DEPTHS[@]}"; do
    for numjobs in "${NUM_JOBS_RANDOM[@]}"; do
        if ! run_fio_tests_parallel "randwrite" "randwrite" "$iodepth" "$numjobs"; then
            log "ERROR" "Random write test failed for iodepth=$iodepth, numjobs=$numjobs"
            stop_monitoring
            exit 1
        fi
    done
done
stop_monitoring

# Run random read tests
log "INFO" "Starting random read tests"
if ! run_monitoring "${TEST_DIR}/randread"; then
    exit 1
fi

for iodepth in "${IO_DEPTHS[@]}"; do
    for numjobs in "${NUM_JOBS_RANDOM[@]}"; do
        if ! run_fio_tests_parallel "randread" "randread" "$iodepth" "$numjobs"; then
            log "ERROR" "Random read test failed for iodepth=$iodepth, numjobs=$numjobs"
            stop_monitoring
            exit 1
        fi
    done
done
stop_monitoring

# Run random read/write tests
log "INFO" "Starting random read/write tests"
if ! run_monitoring "${TEST_DIR}/randrw"; then
    exit 1
fi

for iodepth in "${IO_DEPTHS[@]}"; do
    for numjobs in "${NUM_JOBS_RANDOM[@]}"; do
        if ! run_fio_tests_parallel "randrw" "randrw" "$iodepth" "$numjobs"; then
            log "ERROR" "Random read/write test failed for iodepth=$iodepth, numjobs=$numjobs"
            stop_monitoring
            exit 1
        fi
    done
done
stop_monitoring

log "INFO" "All NVME tests completed successfully"
exit 0
