#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash run_pa4.sh <INPUT>"
  exit 1
fi

INPUT="$1"

if [[ ! -f "$INPUT" ]]; then
  echo "Error: Input file not found: $INPUT"
  exit 1
fi

chmod -R g+rX "$INPUT"
mkdir -p out logs

echo "Starting PA4 pipeline..." | tee logs/run.log

# Save a small raw sample
head -n 5 "$INPUT" > out/sample_before.tsv

# Example cleaning step with sed
sed -E '
s/^[[:space:]]+//;
s/[[:space:]]+$//;
s/[[:space:]]+/\t/g
' "$INPUT" > out/cleaned.tsv

# Save a small cleaned sample
head -n 5 out/cleaned.tsv > out/sample_after.tsv

# Example filter step with awk
awk -F'\t' 'NR==1 || $1 != ""' out/cleaned.tsv > out/filtered.tsv

echo "PA4 pipeline completed." | tee -a logs/run.log


