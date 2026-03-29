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
mkdir -p out logs scripts

LOG_FILE="logs/run_pa4.log"
: > "$LOG_FILE"

echo "Starting PA4 pipeline on $INPUT" | tee -a "$LOG_FILE"

# Small raw sample
head -n 5 "$INPUT" > out/sample_before.tsv

# 1. Clean and normalize with sed
# - trim leading/trailing whitespace
# - normalize comma spacing
# - remove time part from Date so 2018-11-29 00:00:00-05:00 -> 2018-11-29
sed -E '
s/^[[:space:]]+//;
s/[[:space:]]+$//;
s/[[:space:]]*,[[:space:]]*/,/g;
s/^([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]][^,]*/\1/
' "$INPUT" > out/cleaned.csv

head -n 5 out/cleaned.csv > out/sample_after.tsv
echo "Created cleaned sample files" | tee -a "$LOG_FILE"

# 2. Quality filters with awk
# Keep header plus rows where:
# - date exists
# - company exists
# - open/high/low/close > 0
# - volume >= 0
awk -F',' 'BEGIN {OFS="\t"}
NR==1 {
  print $1,$2,$3,$4,$5,$6,$7,$8,$9
  next
}
$1 != "" && $9 != "" && $2 > 0 && $3 > 0 && $4 > 0 && $5 > 0 && $6 >= 0 {
  print $1,$2,$3,$4,$5,$6,$7,$8,$9
}' out/cleaned.csv > out/filtered.tsv

head -n 5 out/filtered.tsv > out/filtered_sample.tsv
echo "Created filtered outputs" | tee -a "$LOG_FILE"

# 3. Ratios, buckets, per-row derived metrics
# ratio = Close/Open
# intraday_range = High-Low
# bucket = GAIN / FLAT / LOSS
awk -F'\t' 'BEGIN {OFS="\t"}
NR==1 {
  print $0,"close_open_ratio","intraday_range","bucket"
  next
}
{
  ratio = ($2 == 0 ? 0 : $5 / $2)
  range = $3 - $4

  if (ratio > 1.01) bucket = "GAIN"
  else if (ratio < 0.99) bucket = "LOSS"
  else bucket = "FLAT"

  printf "%s\t%.6f\t%.6f\t%.6f\t%.6f\t%d\t%s\t%s\t%s\t%.6f\t%.6f\t%s\n",
    $1,$2,$3,$4,$5,$6,$7,$8,$9,ratio,range,bucket
}' out/filtered.tsv > out/enriched.tsv

echo "Created enriched.tsv" | tee -a "$LOG_FILE"

# Bucket counts
awk -F'\t' 'NR>1 {count[$12]++}
END {
  print "bucket\tcount"
  for (b in count) print b "\t" count[b]
}' out/enriched.tsv | sort > out/bucket_counts.tsv

# 4. Per-company summary
awk -F'\t' 'BEGIN {OFS="\t"}
NR>1 {
  c = $9
  days[c]++
  sum_ratio[c] += $10
  sum_range[c] += $11
  sum_vol[c] += $6

  if (!(c in min_close) || $5 < min_close[c]) min_close[c] = $5
  if (!(c in max_close) || $5 > max_close[c]) max_close[c] = $5
}
END {
  print "company","days","avg_close_open_ratio","avg_intraday_range","avg_volume","min_close","max_close"
  for (c in days) {
    printf "%s\t%d\t%.6f\t%.6f\t%.2f\t%.6f\t%.6f\n",
      c, days[c], sum_ratio[c]/days[c], sum_range[c]/days[c], sum_vol[c]/days[c], min_close[c], max_close[c]
  }
}' out/enriched.tsv | sort > out/company_summary.tsv

echo "Created company_summary.tsv" | tee -a "$LOG_FILE"

# 5. Temporal summary by month
awk -F'\t' 'BEGIN {OFS="\t"}
NR>1 {
  month = substr($1,1,7)
  count[month]++
  sum_ratio[month] += $10
  sum_vol[month] += $6
}
END {
  print "month","count","avg_close_open_ratio","avg_volume"
  for (m in count) {
    printf "%s\t%d\t%.6f\t%.2f\n", m, count[m], sum_ratio[m]/count[m], sum_vol[m]/count[m]
  }
}' out/enriched.tsv | sort > out/month_summary.tsv

echo "Created month_summary.tsv" | tee -a "$LOG_FILE"

# 6. Signals table: ranked company signals
awk -F'\t' 'BEGIN {OFS="\t"}
NR>1 {
  c = $9
  days[c]++
  sum_range[c] += $11
  sum_vol[c] += $6
  if ($12 == "GAIN") gain[c]++
  if ($12 == "LOSS") loss[c]++
}
END {
  print "company","days","avg_intraday_range","avg_volume","gain_share","loss_share"
  for (c in days) {
    printf "%s\t%d\t%.6f\t%.2f\t%.6f\t%.6f\n",
      c, days[c], sum_range[c]/days[c], sum_vol[c]/days[c], gain[c]/days[c], loss[c]/days[c]
  }
}' out/enriched.tsv | sort -k3,3nr -k4,4nr > out/signals.tsv

echo "Created signals.tsv" | tee -a "$LOG_FILE"

echo "PA4 pipeline completed successfully." | tee -a "$LOG_FILE"
