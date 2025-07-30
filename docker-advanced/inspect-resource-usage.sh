#!/bin/bash
# ==============================================================================
# Docker Advanced: Inspect Resource Usage
# ==============================================================================
#
# Description:
#   This script provides a detailed report of real-time Docker resource usage.
#   It captures a snapshot of container statistics (CPU, Memory, Network I/O)
#   and presents it in a sorted, human-readable format, making it easy to
#   identify resource-intensive containers.
#
# Usage:
#   ./inspect-resource-usage.sh [options]
#
# Options:
#   --sort-by <cpu|mem>   Sort the output by CPU or Memory usage. (Default: cpu)
#   --top <n>             Show only the top N containers. (Default: all)
#
# Examples:
#   - Show all containers, sorted by CPU usage:
#     ./inspect-resource-usage.sh
#
#   - Show the top 5 memory-consuming containers:
#     ./inspect-resource-usage.sh --sort-by mem --top 5
#
# Variables from config.env:
#   - None.
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Default Flags ---
SORT_BY="cpu"
TOP_N=""

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --sort-by) SORT_BY="$2"; shift ;;
        --top) TOP_N="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Validate Inputs ---
if [ "$SORT_BY" != "cpu" ] && [ "$SORT_BY" != "mem" ]; then
    echo "Error: --sort-by must be either 'cpu' or 'mem'." >&2
    exit 1
fi

echo "Fetching Docker container stats... (this may take a moment)"

# Get a single snapshot of stats for all running containers
STATS_DATA=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}")

# Determine which column to sort by
# CPU is column 2, Memory is column 4 (due to " / " in MemUsage)
SORT_COLUMN=2
if [ "$SORT_BY" = "mem" ]; then
    SORT_COLUMN=4
fi

# Process the data
# - `tail -n +2`: Skip the header row
# - `sed 's/%//g'`: Remove percentage signs for sorting
# - `sort -k${SORT_COLUMN} -hr`: Sort numerically in reverse order by the chosen column
# - `head -n $TOP_N`: If --top is used, get the top N lines
# - `column -t`: Format the output into a clean table
PROCESSED_DATA=$(echo "$STATS_DATA" | tail -n +2 | sed 's/%//g' | sort -k${SORT_COLUMN} -hr)

if [ -n "$TOP_N" ]; then
    PROCESSED_DATA=$(echo "$PROCESSED_DATA" | head -n "$TOP_N")
fi

# Re-add the header for the final output
HEADER=$(echo "$STATS_DATA" | head -n 1)

echo "--- Docker Resource Usage Report (Sorted by ${SORT_BY^^}) ---"
(echo "$HEADER" && echo "$PROCESSED_DATA") | column -t
echo "--------------------------------------------------------"
