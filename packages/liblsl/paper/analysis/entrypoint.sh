#!/bin/bash
set -e

# Extract TSV data files on first run (zip is baked into the image)
if [ ! -f /data/ipad1_lsl_events_1759406662174.tsv ]; then
    echo "Extracting raw_latency_logs.zip to /data..."
    unzip -j /scripts/raw_latency_logs.zip "*.tsv" -d /data
fi

exec Rscript /scripts/latency_analysis.R
