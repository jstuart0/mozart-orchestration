#!/usr/bin/env bash
# mozart-metrics.sh — pipeline-economics aggregator for mozart campaign artifacts.
#
# Sweeps campaign state files and aggregates their `## Findings ledger` tables
# and `## Escapes` blocks into the pipeline-economics table: confirmed catches
# by stage / lens / severity, false-positive rate per lens, escapes,
# defect-removal efficiency (DRE), and catches-per-campaign by tier.
#
# The ledger rows answer "what did each gate catch that would otherwise have
# shipped?"; the escape links answer "what shipped anyway?". Together they are
# the evidence base for EVAL's gate-tuning decisions (see docs/EVAL.md →
# Pipeline economics). This script produces numbers, not judgment — a lens
# with zero catches might have a bad trigger, or might guard a path this
# repo never exercises. Analysts decide; the script counts.
#
# Usage: mozart-metrics.sh [repo-root]     (default: current directory)
# Exit:  0 = table printed, 2 = no state files / no ledger data found
#
# Covers the current subdir convention (plans/active/, plans/finished/) and
# the legacy prefix + prefixless flat layouts.

set -u

ROOT="${1:-.}"
PLANS="$ROOT/thoughts/shared/plans"

if [ ! -d "$PLANS" ]; then
  echo "mozart-metrics: no $PLANS — nothing to aggregate"
  exit 2
fi

# Union of all state-file layouts (same probes as mozart-lint.sh / intake).
FILES=$( { ls "$PLANS"/active/*.state.md 2>/dev/null
           ls "$PLANS"/finished/*.state.md 2>/dev/null
           ls "$PLANS"/aborted/*.state.md 2>/dev/null
           ls "$PLANS"/active-*.state.md 2>/dev/null
           ls "$PLANS"/finished-*.state.md 2>/dev/null
           ls "$PLANS"/[0-9]*.state.md 2>/dev/null; } | sort -u )

if [ -z "$FILES" ]; then
  echo "mozart-metrics: no state files under $PLANS — nothing to aggregate"
  exit 2
fi

# shellcheck disable=SC2086
awk '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

FNR == 1 {
  campaigns++
  tier[FILENAME] = "UNTIERED"
  section = ""
}

/^\*\*Tier\*\*:/ {
  t = trim($0); sub(/^\*\*Tier\*\*:[ \t]*/, "", t)
  # Template files list all tiers pipe-separated; real files pick one.
  if (t !~ /\|/) tier[FILENAME] = t
}

/^## /      { section = trim($0) }

# --- Findings ledger rows -------------------------------------------------
section == "## Findings ledger" && /^\|/ {
  line = $0
  if (line ~ /\| *id *\|/) next          # header
  if (line ~ /^\|[- |]+\|$/) next        # separator
  if (line ~ /</) next                   # template placeholder row
  n = split(line, c, "|")
  if (n < 7) next
  stage = trim(c[3]); lens = trim(c[4]); sev = trim(c[5]); disp = trim(c[6])
  if (stage == "" || sev == "") next
  findings++
  by_lens_total[lens]++
  if (disp ~ /^fixed/) {
    fixed_all++
    if (sev == "Critical" || sev == "High") {
      catches++                          # confirmed Critical/High catch
      by_stage[stage]++
      by_lens[lens]++
      by_sev[sev]++
      catch_in[FILENAME]++
    }
  } else if (disp ~ /^rejected/) {
    rejected++
    by_lens_rejected[lens]++
  } else if (disp ~ /^accepted-risk/) {
    accepted++
  } else {
    undispositioned++
  }
}

# --- Escapes ---------------------------------------------------------------
section == "## Escapes" && /Traces-to:/ {
  if ($0 ~ /</ || $0 ~ /none yet/) next
  escapes++
}

END {
  if (findings == 0 && escapes == 0) {
    printf "mozart-metrics: %d campaign(s) found, but no findings-ledger data yet.\n", campaigns
    printf "Ledgers populate as campaigns disposition findings (state-file format: ## Findings ledger).\n"
    exit 2
  }

  printf "== mozart pipeline economics ==\n"
  # Campaigns by tier, with confirmed-catch averages.
  for (f in tier) { n_tier[tier[f]]++; c_tier[tier[f]] += catch_in[f] }
  printf "Campaigns: %d (", campaigns
  first = 1
  for (t in n_tier) {
    printf "%s%d %s", (first ? "" : " | "), n_tier[t], t
    first = 0
  }
  printf ")\n\n"

  printf "Confirmed catches (Critical/High, disposition=fixed): %d\n", catches
  printf "  by stage:"
  for (s in by_stage) printf " %s=%d", s, by_stage[s]
  printf "\n  by lens: "
  for (l in by_lens) printf " %s=%d", l, by_lens[l]
  printf "\n  by severity:"
  for (v in by_sev) printf " %s=%d", v, by_sev[v]
  printf "\n\n"

  printf "All dispositioned findings: %d fixed, %d rejected, %d accepted-risk", fixed_all, rejected, accepted
  if (undispositioned > 0) printf ", %d UNDISPOSITIONED (closeout failure on terminal campaigns)", undispositioned
  printf "\n"
  if (findings > 0)
    printf "False-positive rate: %.0f%% (%d of %d findings rejected)\n", 100 * rejected / findings, rejected, findings
  printf "  rejected by lens:"
  any = 0
  for (l in by_lens_rejected) { printf " %s=%d/%d", l, by_lens_rejected[l], by_lens_total[l]; any = 1 }
  if (!any) printf " (none)"
  printf "\n\n"

  printf "Escapes (Traces-to links): %d\n", escapes
  if (catches + escapes > 0)
    printf "Defect-removal efficiency: %d/%d = %.0f%%\n", catches, catches + escapes, 100 * catches / (catches + escapes)
  printf "\n"

  printf "Catches per campaign by tier:"
  for (t in n_tier) printf " %s=%.1f", t, (n_tier[t] ? c_tier[t] / n_tier[t] : 0)
  printf "\n"
}
' $FILES
