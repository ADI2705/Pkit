#!/bin/bash

echo "[INFO] Starting software details collection..."

OUTPUT_FILE="sw_summary.txt"
TEMP_FILE="${OUTPUT_FILE}.tmp"

# Initialize temporary file
: > "$TEMP_FILE}"

# Function to safely append to temp file
append_to_file() {
    echo -e "$1" >> "$TEMP_FILE" || {
        echo "[ERROR] Failed to write to $TEMP_FILE" >&2
        exit 1
    }
}

# OS and system info
append_to_file "==== OS & System Info ===="
append_to_file "Hostname      : $(hostname || echo 'Unknown')"
append_to_file "OS Release    : $(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo 'Unknown')"
append_to_file "Kernel        : $(uname -r || echo 'Unknown')"
append_to_file "Uptime        : $(uptime -p 2>/dev/null || echo 'Unknown')"
append_to_file ""

# Tool versions
append_to_file "==== Tool Versions ===="

declare -A tool_commands=(
    [fio]="fio --version || fio -v || /bin/bash -c 'fio --version'"
    [parallel]="parallel --version"
    [ipmitool]="ipmitool -V"
    [smartctl]="smartctl --version"
    [lspci]="lspci --version"
    [arcconf]="arcconf -v 2>&1 | grep -m1 Version"
    [nvme]="nvme version"
    [dmidecode]="dmidecode --version"
)

for tool in "${!tool_commands[@]}"; do
    version_output=$(eval "${tool_commands[$tool]}" 2>/dev/null)
    version=$(echo "$version_output" | grep -m1 -v '^$' | head -n1)
    
    if [ -z "$version" ]; then
        echo "[DEBUG] $tool version output: '$version_output'" >&2
        if [ "$tool" = "fio" ]; then
            echo "[DEBUG] Environment for fio:" >&2
            env >&2
        fi
        version="Not installed"
    fi
    
    printf "%-13s: %s\n" "$tool" "$version" >> "$TEMP_FILE" || {
        echo "[ERROR] Failed to write $tool version to $TEMP_FILE" >&2
        exit 1
    }
done

# Move temp file to final output file
mv "$TEMP_FILE" "$OUTPUT_FILE" || {
    echo "[ERROR] Failed to move $TEMP_FILE to $OUTPUT_FILE" >&2
    exit 1
}

echo "[INFO] Software details collection complete. Output saved to: $OUTPUT_FILE"