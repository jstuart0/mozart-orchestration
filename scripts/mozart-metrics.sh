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
# Covers both artifact roots — .mozart/ (current) and thoughts/shared/ (legacy)
# — and within each, the current subdir convention (plans/active/,
# plans/finished/) plus the legacy prefix + prefixless flat layouts.

set -u

ROOT="${1:-.}"

ROOTS=""
for candidate in "$ROOT/.mozart/plans" "$ROOT/thoughts/shared/plans"; do
  [ -d "$candidate" ] && ROOTS="$ROOTS $candidate"
done

if [ -z "$ROOTS" ]; then
  echo "mozart-metrics: no $ROOT/.mozart/plans (or legacy $ROOT/thoughts/shared/plans) — nothing to aggregate"
  exit 2
fi

# Union of all state-file layouts across both roots (same probes as
# mozart-lint.sh / intake).
FILES=$(for PLANS in $ROOTS; do
          ls "$PLANS"/active/*.state.md 2>/dev/null
          ls "$PLANS"/finished/*.state.md 2>/dev/null
          ls "$PLANS"/aborted/*.state.md 2>/dev/null
          ls "$PLANS"/active-*.state.md 2>/dev/null
          ls "$PLANS"/finished-*.state.md 2>/dev/null
          ls "$PLANS"/[0-9]*.state.md 2>/dev/null
        done | sort -u )

if [ -z "$FILES" ]; then
  echo "mozart-metrics: no state files under$ROOTS — nothing to aggregate"
  exit 2
fi

# shellcheck disable=SC2086
awk '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function normhdr(s,   t) { t = s; gsub(/\r/, "", t); gsub(/\*/, "", t); gsub(/`/, "", t); t = trim(t); t = tolower(t); return t }
function is_placeholder(s,   t) { t = trim(s); return (t ~ /^<.*>$/) }

FNR == 1 {
  campaigns++
  tier[FILENAME] = "UNTIERED"
  section = ""
}

# F40: the Tier field is not always the whole line -- a combined header
# ("**Shape**: ... | **Tier**: HEAVY | **Mode**: ... | **Flow**: ...") puts
# it after other fields on the same line, and a real tier value there is
# ALSO followed by more fields on the same line -- the same shape as the
# templates own "TINY | STANDARD | HEAVY" placeholder list this rule has
# always had to reject. Distinguish them by what follows the first pipe:
# another bold field name means a combined header (take the value before
# it); anything else means the templates pipe-listed options (skip, stays
# UNTIERED, as before).
/\*\*Tier\*\*:/ {
  t = $0; sub(/^.*\*\*Tier\*\*:[ \t]*/, "", t)
  if (t ~ /\|/) {
    rest = t; sub(/^[^|]*\|[ \t]*/, "", rest)
    if (rest ~ /^\*\*[A-Za-z]/) {
      sub(/[ \t]*\|.*$/, "", t)
      tier[FILENAME] = trim(t)
    }
  } else {
    tier[FILENAME] = trim(t)
  }
}

/^## /      { section = trim($0) }

# --- Findings ledger rows: stored per (file, id) for PD13 reversal
# accounting, which needs to resolve a reversing note against its target
# WITHIN THE SAME FILE before any totals are tallied -- so all aggregation
# moves to END, after every file has been read. ----------------------------
section == "## Findings ledger" && /^\|/ {
  line = $0
  if (line ~ /\| *id *\|/) next          # header
  if (line ~ /^\|[- |]+\|$/) next        # separator
  n = split(line, c, "|")
  if (n < 7) next
  note = trim(c[7])
  if (note ~ /^<[^<>]*>$/) next          # template placeholder row: note cell wholly <...>
  fid = trim(c[2]); stage = trim(c[3]); lens = trim(c[4]); sev = trim(c[5]); disp = trim(c[6])
  if (stage == "" || sev == "") next
  key = FILENAME SUBSEP fid
  f_stage[key] = stage; f_lens[key] = lens; f_sev[key] = sev; f_disp[key] = disp; f_note[key] = note
  f_file[key] = FILENAME
  f_order[++f_n] = key
}

# --- Escapes ---------------------------------------------------------------
section == "## Escapes" && /Traces-to:/ {
  if ($0 ~ /none yet/) next
  target = $0
  sub(/^.*Traces-to:[ \t]*/, "", target)
  if (target ~ /^</) next              # placeholder target, e.g. <DIAGNOSE/audit slug>
  escapes++
}

# --- Conductor record rows (PD9/PD11), parsed by header name so a bold or
# backtick-quoted header still resolves -------------------------------------
section == "## Conductor record" {
  has_conductor[FILENAME] = 1
}
section == "## Conductor record" && /^- exempt:/ {
  if (trim($0) == "- exempt: pre-adoption persona") exempt[FILENAME] = 1
}
section == "## Conductor record" && /^\|/ {
  line = $0
  if (line ~ /^\|[- |]+\|$/) next
  n = split(line, c, "|")
  if (!(FILENAME in cr_hdr_seen)) {
    for (i = 1; i <= n; i++) {
      h = normhdr(c[i])
      if (h == "kind") idx_kind[FILENAME] = i
      else if (h == "source") idx_source[FILENAME] = i
      else if (h ~ /^control/) idx_control[FILENAME] = i
    }
    cr_hdr_seen[FILENAME] = 1
    next
  }
  if (!(FILENAME in idx_kind) || !(FILENAME in idx_control) || !(FILENAME in idx_source)) next
  kind = trim(c[idx_kind[FILENAME]])
  ctl = trim(c[idx_control[FILENAME]])
  src = trim(c[idx_source[FILENAME]])
  if (kind == "check" || kind == "adjudication") {
    ca_total++
    if (kind == "check") kind_check++; else kind_adj++
    if (ctl != "" && !is_placeholder(ctl)) ca_controlled++
  } else if (kind == "fact") {
    fact_total++
    if (ctl == "" && tolower(src) ~ /unverified/) fact_unverified++
  }
}

END {
  # ---- PD13 reversal accounting: resolve targets before any tally --------
  for (i = 1; i <= f_n; i++) {
    key = f_order[i]
    if (match(f_note[key], /^reverses F[0-9]+/)) {
      tgt = substr(f_note[key], RSTART, RLENGTH)
      sub(/reverses /, "", tgt)
      tgtkey = f_file[key] SUBSEP tgt
      if (tgtkey in f_disp) reversed_target[tgtkey] = 1
    }
  }

  # ---- d/j/wrong-override-rate: raw disposition, independent of the
  # reversed-target exclusion below (the reversal IS what this measures) ---
  for (i = 1; i <= f_n; i++) {
    key = f_order[i]
    if (!(f_file[key] in has_conductor)) continue
    disp = f_disp[key]
    if (disp !~ /^rejected/ || disp == "rejected (user)") continue
    d++
    if (disp == "rejected (judgment)") j++
    if (key in reversed_target) wrong_override++
  }

  # ---- standard findings/lens totals: a reversed target is excluded, as
  # if the wrongly-rejected row never counted (PD13) --------------------
  for (i = 1; i <= f_n; i++) {
    key = f_order[i]
    stage = f_stage[key]; lens = f_lens[key]; sev = f_sev[key]; disp = f_disp[key]
    if (disp ~ /^fixed/) {
      fixed_all++
      if (sev == "Critical" || sev == "High") {
        catches++
        by_stage[stage]++
        by_lens[lens]++
        by_sev[sev]++
        catch_in[f_file[key]]++
      }
    } else if (disp ~ /^accepted-risk/) {
      accepted++
    } else if (disp !~ /^rejected/) {
      undispositioned++
    }
    if (key in reversed_target) continue
    findings++
    by_lens_total[lens]++
    if (disp ~ /^rejected/) {
      rejected++
      by_lens_rejected[lens]++
    }
  }

  cr_rows_exist = (ca_total + fact_total > 0)
  if (findings == 0 && escapes == 0 && !cr_rows_exist) {
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

  # ---- conductor section (PD9/PD11/PD13, phase 6) -------------------------
  printf "\n== conductor ==\n"
  n_conductor = 0; n_exempt = 0
  for (f in has_conductor) { n_conductor++; if (f in exempt) n_exempt++ }
  printf "Campaigns with a conductor record: %d (%d exempt)\n", n_conductor, n_exempt
  printf "Conductor rows: check=%d adjudication=%d fact=%d\n", kind_check, kind_adj, fact_total
  printf "  controlled check/adjudication rows: %d of %d; unverified facts: %d of %d\n", \
    ca_controlled, ca_total, fact_unverified, fact_total
  if (d == 0) {
    printf "Wrong-override rate: n/a (no rejected findings in campaigns with a conductor record)\n"
  } else {
    printf "Wrong-override rate: %d/%d rejected findings later reversed (%.0f%%)\n", wrong_override, d, 100 * wrong_override / d
    printf "  rejected (judgment): %d of %d\n", j, d
  }
}
' $FILES
