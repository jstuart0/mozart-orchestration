#!/usr/bin/env bash
# mozart-lint.sh — hygiene linter for mozart campaign artifacts.
#
# Mechanizes the state-file invariants that prose discipline demonstrably fails
# to hold (May + July 2026 evaluations): status-vs-location drift, paths-vs-
# checkbox drift, duplicate stage lines, unclosed stage lists in complete
# campaigns, stale active campaigns, stranded sibling artifacts, stale active/
# path references inside finished ## Paths blocks, and active DELIVER campaigns
# missing their 12b. Ship row.
#
# Does NOT implement mozart's probe 5 (pending-pr worktrees needing a merge
# re-check) — that stays a manual sweep at intake. See agents/mozart.md.
#
# Usage: mozart-lint.sh [repo-root]     (default: current directory)
# Exit:  0 = clean, 1 = findings, 2 = nothing to lint
#
# Covers both artifact roots — .mozart/ (current) and thoughts/shared/ (legacy,
# never migrated) — and within each, both the current subdir convention
# (plans/active/, plans/finished/) and the legacy prefix convention
# (active-*.state.md, finished-*.state.md). Legacy prefixless flat files are
# checked for staleness/limbo only.

set -u

ROOT="${1:-.}"
FINDINGS=0
STALE_DAYS=7

# Artifact roots, current first. A repo may have either, both, or neither.
ROOTS=()
for candidate in "$ROOT/.mozart/plans" "$ROOT/thoughts/shared/plans"; do
  [ -d "$candidate" ] && ROOTS+=("$candidate")
done

if [ "${#ROOTS[@]}" -eq 0 ]; then
  echo "mozart-lint: no $ROOT/.mozart/plans (or legacy $ROOT/thoughts/shared/plans) — nothing to lint"
  exit 2
fi

finding() {
  FINDINGS=$((FINDINGS + 1))
  printf 'LINT %-22s %s\n' "[$1]" "$2"
}

# Status field, lowercased. Handles the template form (**Status**: x) and
# tolerates freeform bodies by falling back to any "Status:" line.
status_of() {
  local s
  s=$(grep -m1 -E '^\*\*Status\*\*:' "$1" 2>/dev/null | sed -E 's/^\*\*Status\*\*:[[:space:]]*//')
  [ -z "$s" ] && s=$(grep -m1 -iE '^status:' "$1" 2>/dev/null | sed -E 's/^[Ss]tatus:[[:space:]]*//')
  printf '%s' "$s" | tr '[:upper:]' '[:lower:]'
}

is_terminal() { # complete or aborted (including freeform "CAMPAIGN COMPLETE — SHIPPED")
  case "$1" in *complete*|*aborted*) return 0 ;; *) return 1 ;; esac
}

lint_root() {
  local PLANS="$1"
  local f s n dupes slug stranded

  # --- Check A/B: status vs location ----------------------------------------
  for f in "$PLANS"/active/*.state.md "$PLANS"/active-*.state.md; do
    [ -f "$f" ] || continue
    s=$(status_of "$f")
    if is_terminal "$s"; then
      finding "status-location" "$f — Status '$s' but file lives in an active location (closeout never moved it)"
    fi
  done

  for f in "$PLANS"/finished/*.state.md "$PLANS"/finished-*.state.md; do
    [ -f "$f" ] || continue
    s=$(status_of "$f")
    if [ -n "$s" ] && ! is_terminal "$s"; then
      finding "status-location" "$f — in a finished location but Status is '$s' (moved without closing, or never actually completed)"
    fi
  done

  # --- Check C: paths-vs-checkbox codex drift --------------------------------
  for f in "$PLANS"/active/*.state.md "$PLANS"/finished/*.state.md "$PLANS"/active-*.state.md "$PLANS"/finished-*.state.md "$PLANS"/[0-9]*.state.md; do
    [ -f "$f" ] || continue
    if grep -qE '^\- \[x\] 5\. Codex' "$f" && grep -E '^\- Codex r1' "$f" | grep -q 'not yet run'; then
      finding "codex-drift" "$f — stage 5 checkbox ticked but Paths says codex r1 'not yet run'"
    fi
    if grep -qE '^\- \[x\] 9\. Codex' "$f" && grep -E '^\- Codex r2' "$f" | grep -q 'not yet run'; then
      finding "codex-drift" "$f — stage 9 checkbox ticked but Paths says codex r2 'not yet run'"
    fi
  done

  # --- Check D: duplicate stage lines ----------------------------------------
  for f in "$PLANS"/active/*.state.md "$PLANS"/finished/*.state.md "$PLANS"/active-*.state.md "$PLANS"/finished-*.state.md "$PLANS"/[0-9]*.state.md; do
    [ -f "$f" ] || continue
    # Both greps must accept the optional stage letter. Fixing only the first
    # lets the second strip it, so a real `12b` duplicate reports as `12`.
    dupes=$(grep -oE '^\- \[.\] [0-9]+[a-z]?\.' "$f" | grep -oE '[0-9]+[a-z]?' | sort | uniq -d | tr '\n' ' ')
    if [ -n "$dupes" ]; then
      finding "duplicate-stages" "$f — stage number(s) $dupes appear more than once (append-instead-of-edit; a resuming mozart can't tell which line is true)"
    fi
  done

  # --- Check E: bare [ ] stages in terminal-status files ---------------------
  for f in "$PLANS"/finished/*.state.md "$PLANS"/finished-*.state.md; do
    [ -f "$f" ] || continue
    s=$(status_of "$f")
    is_terminal "$s" || continue
    n=$(grep -cE '^\- \[ \] [0-9]+[a-z]?\.' "$f")
    if [ "$n" -gt 0 ]; then
      finding "unclosed-stages" "$f — Status terminal but $n stage line(s) still bare '[ ]' (should be [x] or '[-] skipped: <rationale>')"
    fi
  done

  # --- Check F: stale active campaigns ---------------------------------------
  for f in $(find "$PLANS"/active "$PLANS" -maxdepth 1 \( -name '*.state.md' -o -name 'active-*.state.md' \) -mtime +"$STALE_DAYS" 2>/dev/null | sort -u); do
    [ -f "$f" ] || continue
    # flat-dir sweep: only flag files that are actually non-terminal
    s=$(status_of "$f")
    is_terminal "$s" && continue
    finding "stale-active" "$f — Status '$s', untouched >${STALE_DAYS} days (needs a disposition: resume / stopped / aborted)"
  done

  # --- Check G: finished state files still referencing plans/active/ ---------
  # Scoped to the ## Paths block. A whole-file grep re-trips on any narrative or
  # ledger row that merely quotes an active/ path, which is prose, not drift.
  for f in "$PLANS"/finished/*.state.md; do
    [ -f "$f" ] || continue
    if awk '/^## Paths/{p=1;next} /^## /&&p{exit} p' "$f" | grep -q 'plans/active/'; then
      finding "stale-paths" "$f — Paths block still points at plans/active/ (closeout didn't rewrite it)"
    fi
  done

  # --- Check I: DELIVER campaigns missing the 12b. Ship row ------------------
  # active/ ONLY — never finished/, and never the bare-slug glob.
  #
  # A finished campaign's stage list is a record of what ran, not a template to
  # conform to. A stage introduced after the campaign closed can never appear in
  # it, and demanding one turns every pre-existing repo's history into lint
  # findings the moment 12b ships. Checks D and E legitimately read finished/
  # because they test time-invariant internal consistency (duplicate rows, bare
  # [ ] in a terminal file); this one tests conformance to the current template,
  # which is not time-invariant. Do not "make the loops consistent."
  #
  # The legacy prefixless glob ("$PLANS"/[0-9]*.state.md) that Checks C and D
  # include is deliberately omitted: those files predate the subdir convention,
  # so they predate 12b too, and their lifecycle state isn't knowable from the
  # path. This check also never consults the ## Pull requests stanza — an
  # in-flight campaign needs the row present (run or explicitly skipped)
  # whether or not the repo opted in, because closeout requires every stage
  # accounted for.
  for f in "$PLANS"/active/*.state.md "$PLANS"/active-*.state.md; do
    [ -f "$f" ] || continue
    if grep -qE '^\- \[[ x-]\] 12\. ' "$f" && ! grep -qE '^\- \[[ x-]\] 12b\.' "$f"; then
      finding "missing-12b" "$f — has a '12. Documentation' row but no '12b. Ship' row (insert it in place between 12 and 13; run it or mark '[-] 12b. Ship — skipped: <reason>')"
    fi
  done

  # --- Check H: sibling artifacts stranded in active/ for finished slugs -----
  for f in "$PLANS"/finished/*.state.md; do
    [ -f "$f" ] || continue
    slug=$(basename "$f" .state.md)
    stranded=$(ls "$PLANS"/active/"$slug".* 2>/dev/null | tr '\n' ' ')
    if [ -n "$stranded" ]; then
      finding "stranded-artifacts" "$slug — state is in finished/ but sibling artifact(s) remain in active/: $stranded"
    fi
  done
}

for plans in "${ROOTS[@]}"; do
  lint_root "$plans"
done

# --- Summary -----------------------------------------------------------------
if [ "$FINDINGS" -eq 0 ]; then
  echo "mozart-lint: clean (${ROOTS[*]})"
  exit 0
else
  echo "mozart-lint: $FINDINGS finding(s) — each needs a disposition before it compounds"
  exit 1
fi
