#!/bin/bash

#
# run-benchmarks.sh
# Tidemark (Swift)
#
# Builds Tidemark in release mode, benchmarks parse+render
# for each Markdown file, and prints results.
#
# Usage:
#   ./run-benchmarks.sh                    # Print results to terminal
#   ./run-benchmarks.sh --update-readme    # Also update README.md
#

set -euo pipefail
cd "$(dirname "$0")"

UPDATE_README=false
if [ "${1:-}" = "--update-readme" ]; then
	UPDATE_README=true
fi

ITERATIONS=10000
RESOURCES="Tests/TidemarkTests/Resources"
README="README.md"
BENCH_BIN=".build/release/Benchmark"

# Build in release mode (includes Benchmark executable).
# SPM skips recompilation when sources haven't changed, so this
# is nearly instant on repeat runs.

echo "Building Tidemark (release)..."
BUILD_OUTPUT=$(swift build -c release 2>&1)
BUILD_TIME=$(echo "$BUILD_OUTPUT" | tail -1 | tr -d '!')
echo "$BUILD_TIME"

# Run benchmarks.

echo "Running benchmarks ($ITERATIONS iterations per file)..."
echo ""

RESULTS=$("$BENCH_BIN" "$ITERATIONS" "$RESOURCES"/*.markdown)

# Parse results and build tables.

total_size=0
total_time=0

# Collect into arrays for sorting by size (descending).
declare -a names sizes times
i=0
while IFS=$'\t' read -r name size time; do
	names[$i]="$name"
	sizes[$i]="$size"
	times[$i]="$time"
	total_size=$((total_size + size))
	total_time=$(echo "$total_time + $time" | bc)
	i=$((i + 1))
done <<< "$RESULTS"

count=$i

# Sort indices by size descending.
sorted_indices=($(for j in $(seq 0 $((count - 1))); do
	echo "${sizes[$j]} $j"
done | sort -rn | awk '{print $2}'))

# Print results to console.
printf "%-42s %6s    %12s\n" "File" "Size" "Time (s)"
printf "%-42s %6s    %12s\n" "---" "----" "--------"
for j in "${sorted_indices[@]}"; do
	display="${names[$j]%.markdown}"
	if [ ${#display} -gt 42 ]; then
		display="${display:0:39}..."
	fi
	kb=$(echo "scale=1; ${sizes[$j]} / 1024" | bc)
	printf "%-42s %6s KB %12s\n" "$display" "$kb" "${times[$j]}"
done
echo ""
total_kb=$((total_size / 1024))
total_time_fmt=$(printf "%.6f" "$total_time")
throughput=$(echo "scale=0; $total_size / $total_time / 1000000" | bc)
printf "Total: %d KB in %s s (%d MB/s)\n" "$total_kb" "$total_time_fmt" "$throughput"
echo ""

# Build the Individual File Performance table.
file_table="| File                        | Size    | Time (s) |\n"
file_table+="|-----------------------------|---------|----------|"
for j in "${sorted_indices[@]}"; do
	raw_name="${names[$j]%.markdown}"
	# Truncate long names
	if [ ${#raw_name} -gt 27 ]; then
		display_name="${raw_name:0:24}..."
	else
		display_name="$raw_name"
	fi
	kb=$(printf "%.1f" "$(echo "scale=1; ${sizes[$j]} / 1024" | bc)")
	file_table+="\n"
	file_table+=$(printf "| %-27s | %4s KB | %s |" "$display_name" "$kb" "${times[$j]}")
done

# Build the Summary table.
summary_table="| Operation      | Size   | Time (s) | Throughput |\n"
summary_table+="|----------------|--------|----------|------------|"
summary_table+="\n"
summary_table+=$(printf "| Parse + Render | %3d KB | %s | %-10s |" "$total_kb" "$total_time_fmt" "${throughput} MB/s")

# Update README.md if --update-readme flag was passed.

if [ "$UPDATE_README" = true ]; then
	echo "Updating $README..."

	python3 << PYEOF
import re

with open("$README", "r") as f:
    content = f.read()

# Replace Summary table
summary = """$summary_table"""
content = re.sub(
    r'(\#\#\#\# Summary\n\n)\|.*?\n\|.*?\n(\|.*?\n)*',
    r'\1' + summary + '\n',
    content
)

# Replace Individual File Performance table
file_perf = """$file_table"""
content = re.sub(
    r'(\#\#\#\# Individual File Performance\n\n)\|.*?\n\|.*?\n(\|.*?\n)*',
    r'\1' + file_perf + '\n',
    content
)

# Update corpus size in methodology line
content = re.sub(
    r'totaling \d+ KB',
    'totaling $total_kb KB',
    content
)

with open("$README", "w") as f:
    f.write(content)

PYEOF
	echo "README.md updated."
fi

echo "Done."
