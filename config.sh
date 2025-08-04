#!/bin/bash

# === Server Test Configuration ===
# Contains configuration variables used across all scripts

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log directory
LOGS_DIR="${SCRIPT_DIR}/logs"

# Test directories
TEST_DIRS=(
    "${SCRIPT_DIR}/tests/single_hdd"
    "${SCRIPT_DIR}/tests/multiple_hdd"
    "${SCRIPT_DIR}/tests/single_nvme"
    "${SCRIPT_DIR}/tests/multiple_nvme"
    "${SCRIPT_DIR}/tests/combined"
)

# FIO configuration
FIO_RUNTIME=300
FIO_LOOPS=1
FIO_BLOCK_SIZES="4k 8k 16k 32k 64k 128k 256k 512k 1m"
FIO_IO_DEPTHS="1 4 8 16 32 64 128"
FIO_NUM_JOBS="1 2 4 8 16"

# Temperature monitoring
TEMP_MONITOR_INTERVAL=60
WARNING_TEMP=45
CRITICAL_TEMP=55

# Disk space requirements
MIN_DISK_SPACE=$((100 * 1024 * 1024 * 1024))  # 100GB in bytes

# Colors for output
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'  # No Color

# Export variables
export SCRIPT_DIR
export LOGS_DIR
export TEST_DIRS
export FIO_RUNTIME
export FIO_LOOPS
export FIO_BLOCK_SIZES
export FIO_IO_DEPTHS
export FIO_NUM_JOBS
export TEMP_MONITOR_INTERVAL
export WARNING_TEMP
export CRITICAL_TEMP
export MIN_DISK_SPACE
export RED
export GRN
export YEL
export BLU
export NC 