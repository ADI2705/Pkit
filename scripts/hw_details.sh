#!/bin/bash

echo "[HW DETAILS] Starting hardware details collection..."

OUTPUT_FILE="hw_summary.txt"
echo -e "==== CPU ====" > "$OUTPUT_FILE"

# CPU info using CPU-X
CPU_INFO=$(cpu-x --dump 2>/dev/null)
CPU_NAME=$(echo "$CPU_INFO" | grep -m1 'Specification:' | cut -d':' -f2- | xargs || echo "Unknown")
CPU_VENDOR=$(echo "$CPU_INFO" | grep -m1 'Vendor:' | cut -d':' -f2- | xargs || echo "Unknown")
CPU_CORES=$(echo "$CPU_INFO" | grep -m1 'Cores:' | awk -F':' '{print $2}' | xargs || echo "Unknown")
CPU_THREADS=$(echo "$CPU_INFO" | grep -m1 'Threads:' | awk -F':' '{print $2}' | xargs || echo "Unknown")
CPU_SPEED=$(echo "$CPU_INFO" | grep -m1 'Core Speed:' | cut -d':' -f2- | xargs || echo "Unknown")
CPU_MULT=$(echo "$CPU_INFO" | grep -m1 'Multiplier:' | cut -d':' -f2- | xargs || echo "Unknown")
BUS_SPEED=$(echo "$CPU_INFO" | grep -m1 'Bus Speed:' | cut -d':' -f2- | xargs || echo "Unknown")
CPU_TEMP=$(echo "$CPU_INFO" | grep -m1 'Temp.:' | cut -d':' -f2- | xargs || echo "Unknown")

echo -e "\tVendor       : $CPU_VENDOR" >> "$OUTPUT_FILE"
echo -e "\tModel        : $CPU_NAME" >> "$OUTPUT_FILE"
echo -e "\tCores        : $CPU_CORES" >> "$OUTPUT_FILE"
echo -e "\tThreads      : $CPU_THREADS" >> "$OUTPUT_FILE"
echo -e "\tCore Speed   : $CPU_SPEED" >> "$OUTPUT_FILE"
echo -e "\tMultiplier   : $CPU_MULT" >> "$OUTPUT_FILE"
echo -e "\tBus Speed    : $BUS_SPEED" >> "$OUTPUT_FILE"
echo -e "\tTemperature  : $CPU_TEMP" >> "$OUTPUT_FILE"

echo -e "\n==== Motherboard ====" >> "$OUTPUT_FILE"
MB_VENDOR=$(dmidecode -s baseboard-manufacturer 2>/dev/null || echo "Unknown")
MB_MODEL=$(dmidecode -s baseboard-product-name 2>/dev/null || echo "Unknown")
MB_SERIAL=$(dmidecode -s baseboard-serial-number 2>/dev/null || echo "Unknown")
echo -e "\tVendor       : $MB_VENDOR" >> "$OUTPUT_FILE"
echo -e "\tModel        : $MB_MODEL" >> "$OUTPUT_FILE"
echo -e "\tSerial       : $MB_SERIAL" >> "$OUTPUT_FILE"

echo -e "\n==== HBA ====" >> "$OUTPUT_FILE"
HBA_PCI=$(lspci | grep -i 'SAS\|RAID\|SCSI' | grep -i 'Adaptec' | head -n1 || echo "None")
ARC_CTRL=$(arcconf GETCONFIG 1 AL 2>/dev/null | grep -m1 'Controller Model' | cut -d':' -f2- | xargs || echo "Unknown")
ARC_SERIAL=$(arcconf GETCONFIG 1 AL 2>/dev/null | grep -m1 'Controller Serial Number' | cut -d':' -f2- | xargs || echo "Unknown")
echo -e "\tPCI Device   : $HBA_PCI" >> "$OUTPUT_FILE"
echo -e "\tModel        : $ARC_CTRL" >> "$OUTPUT_FILE"
echo -e "\tSerial       : $ARC_SERIAL" >> "$OUTPUT_FILE"

echo -e "\n==== PSU ====" >> "$OUTPUT_FILE"
# Get PSU information using ipmicfg
PSU_INFO=$(ipmicfg -pminfo full 2>/dev/null)
if [ -z "$PSU_INFO" ]; then
    echo -e "\tError: ipmicfg not available or no PSU information found" >> "$OUTPUT_FILE"
else
    # Extract PSU information for each module
    PSU_COUNT=0
    echo "$PSU_INFO" | awk -v outfile="$OUTPUT_FILE" '
    BEGIN { 
        in_module = 0; 
        module_name = ""; 
        model = ""; 
        serial = ""; 
        status = "";
        psu_counter = 0
    }
    /^\s*\[SlaveAddress.*\[Module [0-9]+\]/ {
        # If we have data from previous module, print it
        if (in_module && model != "" && serial != "") {
            print "\t" module_name >> outfile
            print "\t\tModel       : " model >> outfile
            print "\t\tSerial      : " serial >> outfile
            print "\t\tStatus      : " status >> outfile
        }
        # Start new module
        in_module = 1
        psu_counter++
        module_name = "PSU " psu_counter
        model = ""
        serial = ""
        status = ""
    }
    /^\s*Status\s*\|/ && in_module {
        split($0, parts, "|")
        gsub(/^[ \t]+|[ \t]+$/, "", parts[2])
        status = parts[2]
    }
    /^\s*PWS Module Number\s*\|/ && in_module {
        split($0, parts, "|")
        gsub(/^[ \t]+|[ \t]+$/, "", parts[2])
        model = parts[2]
    }
    /^\s*PWS Serial Number\s*\|/ && in_module {
        split($0, parts, "|")
        gsub(/^[ \t]+|[ \t]+$/, "", parts[2])
        serial = parts[2]
    }
    END {
        # Print last module if we have data
        if (in_module && model != "" && serial != "") {
            print "\t" module_name >> outfile
            print "\t\tModel       : " model >> outfile
            print "\t\tSerial      : " serial >> outfile
            print "\t\tStatus      : " status >> outfile
        }
    }'
fi

echo -e "\n==== RAM ====" >> "$OUTPUT_FILE"
DMIDECODE_OUT=$(dmidecode -t memory 2>/dev/null)
if [ -z "$DMIDECODE_OUT" ]; then
    echo "Error: dmidecode failed or no memory information available" >> "$OUTPUT_FILE"
else
    echo "$DMIDECODE_OUT" | awk -v outfile="$OUTPUT_FILE" -v RS="\n\n" -v OFS="\t" '/Memory Device/ && /Size: [0-9]+.*[GM]B/ {
        size=""; slot=""; speed=""; serial=""; vendor=""; type=""
        for (i = 1; i <= NF; i++) {
            if ($i == "Size:" && $(i+1) ~ /^[0-9]+$/ && $(i+2) ~ /^(MB|GB)$/) {size=$(i+1) " " $(i+2)}
            if ($i == "Locator:" && $(i+1) ~ /^DIMM/) {slot=$(i+1) ? $(i+1) : "Unknown"}
            if ($i == "Speed:" && $(i+1) ~ /^[0-9]+$/ && $(i+2) == "MT/s") {speed=$(i+1) " " $(i+2)}
            if ($i == "Serial" && $(i+1) == "Number:") {serial=$(i+2) ? $(i+2) : "Unknown"}
            if ($i == "Manufacturer:") {
                vendor=""
                j=i+1
                while (j <= NF && $j !~ /^[A-Z][a-z]*:$|^Serial$/) {vendor=(vendor ? vendor " " : "") $j; j++}
                if (vendor == "") vendor="Unknown"
            }
            if ($i == "Type:") {type=$(i+1) ? $(i+1) : "Unknown"}
        }
        print "\tSlot         :", slot ? slot : "Unknown" >> outfile
        print "\t\tSize        :", size ? size : "Unknown" >> outfile
        print "\t\tType        :", type ? type : "Unknown" >> outfile
        print "\t\tSpeed       :", speed ? speed : "Unknown" >> outfile
        print "\t\tSerial      :", serial ? serial : "Unknown" >> outfile
        print "\t\tManufacturer:", vendor ? vendor : "Unknown" >> outfile
    }'
fi

echo "[HW DETAILS] Hardware details collection complete. Output saved to: $OUTPUT_FILE (or specify output file if redirected)"
