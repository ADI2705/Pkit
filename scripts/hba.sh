#!/bin/bash
# Check arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <output_file> <interval> <controller_list>"
    echo "Example: $0 hba_temps.csv 10 '1,2'"
    echo "         $0 hba_temps.csv 10 '1,3'"
    exit 1
fi

CSV_FILE="$1"
INTERVAL="$2"
CONTROLLERS="$3"

# Convert comma-separated controller list to array
IFS=',' read -ra CONTROLLER_ARRAY <<< "$CONTROLLERS"

# Build CSV header dynamically based on controllers
HEADER="Timestamp"
for controller in "${CONTROLLER_ARRAY[@]}"; do
    HEADER="${HEADER},HBA${controller}_Temperature_C"
done

# Write CSV header if file does not exist
if [[ ! -f "$CSV_FILE" ]]; then
    echo "$HEADER" >> "$CSV_FILE"
fi

echo "Monitoring HBA controllers: ${CONTROLLERS}"
echo "Output file: ${CSV_FILE}"
echo "Interval: ${INTERVAL} seconds"
echo "Press Ctrl+C to stop..."

# Main monitoring loop
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    ROW="$TIMESTAMP"
    
    # Collect temperature from each controller
    for controller in "${CONTROLLER_ARRAY[@]}"; do
        # Extract temperature in Celsius for the specific controller
        TEMP=$(arcconf getconfig "$controller" al 2>/dev/null | grep "Temperature" | head -n 1 | awk '{print $3}')
        
        # Handle case where controller might not be available or temperature not found
        if [[ -z "$TEMP" || "$TEMP" == "" ]]; then
            TEMP="N/A"
        fi
        
        ROW="${ROW},${TEMP}"
    done
    
    # Append row to CSV
    echo "$ROW" >> "$CSV_FILE"
    
    # Optional: Print current readings to console
    echo "$(date '+%H:%M:%S'): $ROW"
    
    # Wait for specified interval
    sleep "$INTERVAL"
done