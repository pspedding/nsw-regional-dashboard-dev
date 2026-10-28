#!/usr/bin/env bash
# refresh_from_dropbox.sh
# Syncs dashboard source files from Dropbox:/Moltbot/Economic-Dashboard/
# then regenerates ALL dashboard components and deploys to GitHub Pages.
#
# Expected files in Dropbox:/Moltbot/Economic-Dashboard/:
#   Output - Mapped SA2 Level Data (Pivot) - All LGAs.xlsx
#   Output  - Indicator Lookup.xlsx
#   Output - Trends.csv
#   Output  - Time-series Trends.xlsx
#
# Components refreshed:
#   1. Sync input files from Dropbox
#   2. data.js + indicator-lookup.js  (map/bar/dropdown)
#   3. correlations.json              (Analytics panel - Pearson correlations)
#   4. clusters.json                  (Analytics panel - k-means)
#   5. outliers.json                  (Analytics panel - Mahalanobis)
#   6. trend_series.json              (sparklines)
#   7. central-coast.md               (source-backed Intelligence Report)
#   8. central-coast.docx/pdf         (downloads from same Markdown)
#   9. index.html cache-bust
#  10. Validate + commit + push dev/gh-pages only
#
# Usage:
#   bash scripts/refresh_from_dropbox.sh
#   bash scripts/refresh_from_dropbox.sh --dry-run    (sync + regenerate, no commit/push)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
INPUTS_DIR="$REPO_DIR/inputs"
DROPBOX_PATH="dropbox:Moltbot/Economic-Dashboard"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

echo "========================================="
echo " Dashboard Full Refresh from Dropbox"
echo " $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "========================================="

# ── 1. Fetch exactly four current sources into a temporary directory ──
echo ""
echo ">> Step 1: Fetching four files from $DROPBOX_PATH ..."
DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
rclone copy "$DROPBOX_PATH" "$DOWNLOAD_DIR" \
  --include "Output - Mapped SA2 Level Data (Pivot) - All LGAs.xlsx" \
  --include "Output  - Indicator Lookup.xlsx" \
  --include "Output  - Time-series Trends.xlsx" \
  --include "Output - Trends.csv"

for f in \
  "Output - Mapped SA2 Level Data (Pivot) - All LGAs.xlsx" \
  "Output  - Indicator Lookup.xlsx" \
  "Output  - Time-series Trends.xlsx" \
  "Output - Trends.csv"; do
  if [[ ! -s "$DOWNLOAD_DIR/$f" ]]; then
    echo "ERROR: Required Dropbox source missing or empty: $f" >&2
    exit 1
  fi
done
# Install only canonical tracked inputs; do not touch any pre-existing raw or
# prior-month file in inputs/ (the latter cannot be inferred from these files).
cp "$DOWNLOAD_DIR/Output - Mapped SA2 Level Data (Pivot) - All LGAs.xlsx" "$INPUTS_DIR/Output-Mapped-SA2-Level-Data-Pivot-All-LGAs.xlsx"
cp "$DOWNLOAD_DIR/Output  - Indicator Lookup.xlsx" "$INPUTS_DIR/Output-Indicator-Lookup.xlsx"
cp "$DOWNLOAD_DIR/Output  - Time-series Trends.xlsx" "$INPUTS_DIR/Output  - Time-series Trends.xlsx"
cp "$DOWNLOAD_DIR/Output - Trends.csv" "$INPUTS_DIR/Output-Trends.csv"

# ── 2. Regenerate data.js + indicator-lookup.js ───────────────────────
echo ""
echo ">> Step 2: Regenerating data.js + indicator-lookup.js ..."
cd "$REPO_DIR"
python3 scripts/import_dashboard_inputs.py

# ── 3. Regenerate analytics JSON files ───────────────────────────────
echo ""
echo ">> Step 3: Recomputing correlations (Analytics panel) ..."
python3 scripts/compute_correlations.py

echo ">> Step 3b: Recomputing outliers (Analytics panel) ..."
python3 scripts/compute_outliers.py

echo ">> Step 3c: Recomputing clusters (Analytics panel) ..."
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 python3 scripts/compute_clusters.py

echo "   Analytics JSON files updated."

# ── 4. Regenerate auditable Intelligence Report ───────────────────────
echo ""
echo ">> Step 4: Regenerating data-backed Intelligence Report ..."
python3 scripts/generate_verified_report.py
echo "   central-coast.md regenerated with auditable source periods and rankings."

# ── 5. Regenerate Word download ───────────────────────────────────────
echo ""
echo ">> Step 5: Regenerating Word download ..."
if command -v pandoc &>/dev/null; then
  pandoc "$REPO_DIR/reports/central-coast.md" --from markdown --to docx --standalone --output "$REPO_DIR/reports/central-coast.docx"
  echo "   Generated: reports/central-coast.docx"
else
  echo "ERROR: pandoc is required for the report Word download" >&2
  exit 1
fi
if ! command -v wkhtmltopdf &>/dev/null; then
  echo "ERROR: wkhtmltopdf is required for the tracked PDF" >&2
  exit 1
fi
pandoc "$REPO_DIR/reports/central-coast.md" -s -t html5 -M title='Central Coast SA2 Intelligence Report' -o /tmp/sa2-dashboard-report.html
wkhtmltopdf -q /tmp/sa2-dashboard-report.html "$REPO_DIR/reports/central-coast.pdf"

# ── 6. Update cache-buster in index.html ──────────────────────────────
echo ""
echo ">> Step 6: Updating cache-buster in index.html ..."
TS=$(date +%s)
sed -i "s/indicator-lookup\.js?v=[0-9]*/indicator-lookup.js?v=${TS}/g" "$REPO_DIR/index.html"
sed -i "s/data\.js?v=[0-9]*/data.js?v=${TS}/g" "$REPO_DIR/index.html"

# The QA prompt reads indicator-specific periods from indicator-lookup.js;
# never imply all indicators share the newest reference date.
echo "   Cache-buster: $TS"

# ── 7. Validate ───────────────────────────────────────────────────────
echo ""
echo ">> Step 7: Validating ..."
bash "$REPO_DIR/scripts/validate_before_push.sh"

if $DRY_RUN; then
  echo ""
  echo ">> DRY RUN complete. No commit/push performed."
  exit 0
fi

# ── 8. Commit & push ─────────────────────────────────────────────────
echo ""
echo ">> Step 8: Committing and pushing ..."
cd "$REPO_DIR"

git add data.js index.html indicator-lookup.js sa2_kpi_wide.csv \
        public/data/correlations.json public/data/outliers.json \
        public/data/trend_series.json \
        inputs/Output-Mapped-SA2-Level-Data-Pivot-All-LGAs.xlsx \
        inputs/Output-Indicator-Lookup.xlsx \
        inputs/Output-Trends.csv \
        "inputs/Output  - Time-series Trends.xlsx" \
        reports/central-coast.md \
        reports/central-coast.docx reports/central-coast.pdf \
        scripts/generate_verified_report.py scripts/refresh_from_dropbox.sh

# Clusters are mandatory: fail rather than publishing old analytics.
test -s public/data/clusters.json
git add public/data/clusters.json

if git diff --cached --quiet; then
  echo "   No changes detected -- dashboard is already up to date."
else
  PERIOD=$(python3 -c "
import re
from datetime import datetime
src = open('indicator-lookup.js').read()
periods = re.findall(r'\"latestPeriod\"\s*:\s*\"([^\"]+)\"', src)
monthly = sorted(set(p for p in periods if len(p) >= 7), reverse=True)
label = datetime.strptime(monthly[0][:7], '%Y-%m').strftime('%b %Y') if monthly else 'unknown'
print(label)
" 2>/dev/null || echo "unknown")

  git commit -m "chore: full dashboard refresh ($PERIOD) — data, analytics, intelligence report, QA"
  git push dev HEAD:gh-pages
  echo ""
  echo "   Pushed only to dev/gh-pages; origin/main may carry unrelated changes."
  echo "   GitHub Pages will rebuild in ~1-2 minutes."
fi

echo ""
echo "========================================="
echo " Refresh complete!"
echo "========================================="

# Social posts are intentionally outside the dashboard refresh scope.
