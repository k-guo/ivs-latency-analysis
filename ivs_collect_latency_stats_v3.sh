#!/bin/sh

TMP_LATENCY=""
TMP_STATS=""
TMP_SLABS=""

cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaning up temporary files and exiting."
    [ -n "$TMP_LATENCY" ] && rm -f "$TMP_LATENCY" 2>/dev/null || true
    [ -n "$TMP_STATS" ] && rm -f "$TMP_STATS" 2>/dev/null || true
    [ -n "$TMP_SLABS" ] && rm -f "$TMP_SLABS" 2>/dev/null || true
    exit 0
}
# Respond to common termination signals
trap cleanup INT TERM
trap '' HUP

# Configuration
OUTPUT_DIR="/tmp/nsx_stats"
mkdir -p "$OUTPUT_DIR"

# Duration: 3 Days in seconds (3 * 24 * 60 * 60)
MAX_DURATION=259200
START_TIME=$(date +%s)

echo "Starting NSX Stats Monitor."
echo " - Collection: Immediate, then every 60s (Drift-corrected)"
echo " - Clearance:  Every 180s"
echo " - Duration:   Stops automatically after 3 days"
echo "Files saved to: $OUTPUT_DIR"
echo "----------------------------------------"

ITERATION=0

while true; do
    # 1. Check if 3 days have passed (also acts as loop start time for drift correction)
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $MAX_DURATION ]; then
        echo "Time limit of 3 days reached. Stopping script."
        exit 0
    fi

    # 2. Setup Timestamps
    TIMESTAMP_FILE=$(date +%Y%m%d_%H%M%S)
    TIMESTAMP_READABLE=$(date "+%Y-%m-%d %H:%M:%S")

    FINAL_FILE="${OUTPUT_DIR}/nsx_combined_${TIMESTAMP_FILE}.txt"
    TMP_LATENCY="/tmp/temp_latency_${TIMESTAMP_FILE}.txt"
    TMP_STATS="/tmp/temp_stats_${TIMESTAMP_FILE}.txt"
    TMP_SLABS="/tmp/temp_slabs_${TIMESTAMP_FILE}.txt"

    # 3. Run Commands Simultaneously
    timeout -t 60 nsxdp-cli ens latency system dump -s 0 > "$TMP_LATENCY" 2>&1 &
    PID1=$!

    timeout -t 60 nsxdp-cli ens prp stats lcore list -a 0 -s 0 > "$TMP_STATS" 2>&1 &
    PID2=$!

    # Dynamically check if the histogram node exists before getting it (GA vs Debug build fix)
    timeout -t 60 sh -c 'for slab in $(vsish -e ls /system/fastslab/fastslabs 2>/dev/null | grep EnsSlab); do
        if vsish -e ls /system/fastslab/fastslabs/${slab} 2>/dev/null | grep -q deallocTimeHisto; then
            echo "Slab: $slab"
            vsish -e get /system/fastslab/fastslabs/${slab}deallocTimeHisto
        fi
    done' > "$TMP_SLABS" 2>&1 &
    PID3=$!

    wait $PID1; STATUS1=$?
    wait $PID2; STATUS2=$?
    wait $PID3; STATUS3=$?

    # ---- Error handling ----
    if [ $STATUS1 -ne 0 ]; then
        echo "[$TIMESTAMP_READABLE][WARN] latency dump command failed or timed out (exit $STATUS1)"
    fi

    if [ $STATUS2 -ne 0 ]; then
        echo "[$TIMESTAMP_READABLE][WARN] stats command failed or timed out (exit $STATUS2)"
    fi

    if [ $STATUS3 -ne 0 ]; then
        echo "[$TIMESTAMP_READABLE][WARN] EnsSlab command failed or timed out (exit $STATUS3)"
    fi

    # Skip this iteration ONLY if core commands (Latency/Stats) fail.
    if [ $STATUS1 -ne 0 ] || [ $STATUS2 -ne 0 ]; then
        rm -f "$TMP_LATENCY" "$TMP_STATS" "$TMP_SLABS"
        sleep 60
        continue
    fi

    # 4. Combine Output
    {
        echo "========================================"
        echo "CAPTURE TIME: ${TIMESTAMP_READABLE}"
        echo "========================================"
        echo ""
        echo "COMMAND 1: nsxdp-cli ens latency system dump -s 0"
        echo "----------------------------------------"
        cat "$TMP_LATENCY"
        echo ""
        echo "========================================"
        echo ""
        echo "COMMAND 2: nsxdp-cli ens prp stats lcore list -a 0 -s 0"
        echo "----------------------------------------"
        cat "$TMP_STATS"
        echo ""
        echo "========================================"
        echo ""
        echo "COMMAND 3: EnsSlab deallocTimeHisto"
        echo "----------------------------------------"
        # If the file has data, print it. If it's empty, print a fallback message.
        if [ -s "$TMP_SLABS" ]; then
            cat "$TMP_SLABS"
        else
            echo "No deallocTimeHisto data available on this host build (Skipped)."
        fi
        echo ""
        echo "========================================"
        echo "End of Capture"
    } > "$FINAL_FILE"

    rm -f "$TMP_LATENCY" "$TMP_STATS" "$TMP_SLABS"

    # 5. Clearance Logic (Every 3rd run)
    ITERATION=$((ITERATION + 1))

    if [ $((ITERATION % 3)) -eq 0 ]; then
        CLEARANCE_LOG="${OUTPUT_DIR}/clearance_events.log"
        {
            echo "----------------------------------------"
            echo "[$TIMESTAMP_READABLE] [INFO] Scheduled clearance triggered (Iteration $ITERATION)"
            nsxdp-cli ens latency system clear -s 0
            nsxdp-cli ens latency system clear -s 1
            nsxdp-cli ens prp stats lcore clear -s 0
            nsxdp-cli ens prp stats lcore clear -s 1
            echo "[$TIMESTAMP_READABLE] [INFO] Clearance finished."
            echo "----------------------------------------"
        } 2>&1 | tee -a "$CLEARANCE_LOG"
    fi

    # 6. Self-Correcting Timer (Drift Correction)
    LOOP_END=$(date +%s)
    EXECUTION_TIME=$((LOOP_END - CURRENT_TIME))
    SLEEP_TIME=$((60 - EXECUTION_TIME))

    if [ "$SLEEP_TIME" -gt 0 ]; then
        sleep "$SLEEP_TIME"
    else
        sleep 1
    fi
done