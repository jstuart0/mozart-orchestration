#!/usr/bin/env bash
# mozart-lint.sh — hygiene linter for mozart campaign artifacts.
#
# Mechanizes the state-file invariants that prose discipline demonstrably fails
# to hold (May + July 2026 evaluations): status-vs-location drift, paths-vs-
# checkbox drift, duplicate stage lines, unclosed stage lists in complete
# campaigns, stale active campaigns, stranded sibling artifacts, stale active/
# path references inside finished ## Paths blocks, and active DELIVER campaigns
# missing their 12b. Ship row or their 2b. Constraints row.
#
# Checks K (conductor-missing/-unlinked/-row/-reference, decision-trigger) and
# L (mutation-manifest) scan the SAME active+finished, current+legacy glob set
# as Checks C/D — unlike I/J, which are active/-only, K/L also read finished/
# because the conductor record and decisions log are historical evidence, not
# a template a closed campaign must still conform to. `lint_conductor()` reads
# each state file's own `## Conductor record` / `## Change ledger` /
# `## Findings ledger` sections plus its sibling `<slug>.decisions.md`, and
# emits `category<TAB>key<TAB>message` lines that the caller turns into
# `finding()` calls in the shared `LINT [<category>] <path> — <key>: <message>`
# format. `MOZART_LINT_CONDUCTOR_SINCE` overrides the adoption-date constant
# below — a fixture-corpus test hook (2026-09-17-deliver-conductor-self-
# verification); every run that sets it prints the override-visibility line
# below before any `LINT` line, so an override can never be silent.
#
# Check M (split-layout) and the sibling files. A campaign's findings ledger and
# conductor record may live in files beside the state file instead of inside it
# (the sibling rule is in lib-campaign.sh). lint_conductor() hands both paths to
# the awk, which reads them with getline in BEGIN, like the decisions log, and
# feeds their lines to the SAME row handlers as in-file lines. A sibling wins
# over an in-file copy of its section; the pair is reported (Check M) and the
# in-file rows are ignored. Flow, Tier, stage ticks and the change ledger are
# read from the state file only. Findings are always reported against the state
# file's path, never a sibling's.
#
# Check N (escape-unrecorded). A DIAGNOSE investigation or INCIDENT post-mortem that
# names the campaign a defect traces to ("Traces-to: <slug>", slug first) must find
# that campaign's ## Escapes block recording it: a recorded-escape line (the library
# rule, is_escape_line) naming the artifact's own slug as a whole token. Scanned:
# investigations/**/*.md and incidents/*.postmortem.md beside each plans root. The
# origin is looked up in every layout of both roots, aborted/ included. A finding is
# reported against the origin state file, keyed by the discovering slug, or against
# the artifact when the origin has no state file here; an origin that cannot be
# recorded is written "Traces-to: external — <where or why>; <slug>" and is silent,
# as are "none", "n/a", a ticket id and any line inside a fenced code block. Not
# gated on the conductor adoption date.
#
# Does NOT implement mozart's probe 5 (pending-pr worktrees needing a merge
# re-check) — that stays a manual sweep at intake. See agents/STATE.md
# (*State persistence (crash-resume)*), where probe 5 is defined.
#
# Usage: mozart-lint.sh [repo-root]     (default: current directory)
# Exit:  0 = clean, 1 = findings, 2 = nothing to lint
#
# Covers both artifact roots — .mozart/ (current) and thoughts/shared/ (legacy,
# never migrated) — and within each, three layouts: the current subdir
# convention (plans/active/, plans/finished/), the legacy prefix convention
# (active-*.state.md, finished-*.state.md), and legacy prefixless flat files
# (<date>-<slug>.state.md directly under plans/).
#
# Flat prefixless files are scanned by every check whose subject does not
# depend on knowing the campaign's lifecycle state from its path: C
# (paths-vs-checkbox), D (duplicate stages), F (staleness), K (conductor) and
# L (mutation manifest). A/B (status-vs-location), E (unclosed stages), G
# (stale paths), H (stranded siblings), I (12b) and J (2b) skip them by
# construction — each of those asks "is this file where its status says it
# should be" or "does this in-flight campaign conform to the current
# template", and a flat file answers neither question from its path. F47:
# K/L used to skip flat files too, which let a post-adoption flat state file
# with no ## Conductor record lint clean.

set -u

# The shared helpers live in lib-campaign.sh, found beside this script (the
# path is absolutised from BASH_SOURCE, so it works from any cwd and from a
# path containing a space). Missing, unreadable, empty or truncated (no end sentinel) is a loud exit 3,
# never a run with undefined awk functions; exit 2 keeps meaning "nothing to
# lint".
CAMPAIGN_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-campaign.sh"
CAMPAIGN_AWK_LIB=""
CAMPAIGN_LIB_END=""
if [ -r "$CAMPAIGN_LIB" ] && [ -s "$CAMPAIGN_LIB" ]; then
  . "$CAMPAIGN_LIB" 2>/dev/null
fi
if [ -z "${CAMPAIGN_AWK_LIB:-}" ] || [ "${CAMPAIGN_LIB_END:-}" != 1 ]; then
  echo "mozart-lint: scripts/lib-campaign.sh not found beside this script" >&2
  exit 3
fi

ROOT="${1:-.}"
FINDINGS=0
STALE_DAYS=7

# PD1/PD3/PD24. CONDUCTOR_SINCE defaults to the merge date (log D2); the
# fixture-hook override is documented above and asserted by gate V11.
CONDUCTOR_SINCE="${MOZART_LINT_CONDUCTOR_SINCE:-2026-09-19}"
CONDUCTOR_GATES_DELIVER="5 9 10 13 P:heavy"
CONDUCTOR_GATES_OPERATE="1:fact 4 6"
CONDUCTOR_GATES_INCIDENT="1 5"
CONDUCTOR_FLOWS_DELIVER="FULL PLAN-ONLY RESEARCH-ONLY VALIDATE-ONLY"
CONDUCTOR_FLOWS_OPERATE="OPERATE"
CONDUCTOR_FLOWS_INCIDENT="INCIDENT MITIGATE-ONLY"

if [ -n "${MOZART_LINT_CONDUCTOR_SINCE:-}" ]; then
  echo "conductor adoption date overridden: $MOZART_LINT_CONDUCTOR_SINCE"
fi

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
  # F40: **Status**: is not always the line's own field -- a combined header
  # ("**Shape**: ... | **Status**: in-progress | **Flow**: ...") puts it
  # after other fields on the same line. Match anywhere, take the value up
  # to the next "|" (if any) or end of line.
  s=$(grep -m1 -E '\*\*Status\*\*:' "$1" 2>/dev/null | sed -E 's/^.*\*\*Status\*\*:[[:space:]]*//; s/[[:space:]]*\|.*$//')
  [ -z "$s" ] && s=$(grep -m1 -iE '^status:' "$1" 2>/dev/null | sed -E 's/^[Ss]tatus:[[:space:]]*//')
  printf '%s' "$s" | tr '[:upper:]' '[:lower:]'
}

is_terminal() { # complete or aborted (including freeform "CAMPAIGN COMPLETE — SHIPPED")
  case "$1" in *complete*|*aborted*) return 0 ;; *) return 1 ;; esac
}

# Flow field, CR stripped. Handles the template's pipe-separated tolerant
# form and freeform two-part values ("OPERATE — plan → apply",
# "FULL (DELIVER, escalated from a DIAGNOSE)", "INVESTIGATE-ONLY -> decision
# point") by testing whether the trimmed value STARTS WITH a known token
# (PD3's "starts with" rule: the token followed by a non-alnum char or EOL).
flow_of() {
  # F40: same combined-header hazard as status_of() -- match **Flow**:
  # anywhere in the line, stop at the next "|" or end of line.
  grep -m1 -E '\*\*Flow\*\*:' "$1" 2>/dev/null \
    | sed -E 's/^.*\*\*Flow\*\*:[[:space:]]*//; s/[[:space:]]*\|.*$//' | tr -d '\r'
}

flow_family_of() { # PD3/PD20 -- DELIVER, OPERATE, INCIDENT, or empty
  local val="$1" tok
  for tok in $CONDUCTOR_FLOWS_DELIVER; do
    printf '%s' "$val" | grep -qE "^${tok}([^A-Za-z0-9]|\$)" && { echo DELIVER; return; }
  done
  for tok in $CONDUCTOR_FLOWS_OPERATE; do
    printf '%s' "$val" | grep -qE "^${tok}([^A-Za-z0-9]|\$)" && { echo OPERATE; return; }
  done
  for tok in $CONDUCTOR_FLOWS_INCIDENT; do
    printf '%s' "$val" | grep -qE "^${tok}([^A-Za-z0-9]|\$)" && { echo INCIDENT; return; }
  done
  echo ""
}


# Checks K (conductor-*, decision-trigger) and L (mutation-manifest) -- PD24.
# Parses one state file (plus its sibling decisions file, read via getline so
# a missing decisions file never triggers the classic FNR==NR two-file trap
# when the "first" file is empty) and emits category<TAB>key<TAB>message
# lines. \r is stripped from every line so a CRLF-encoded state file (e.g. the
# crlf fixture) parses identically to LF. Header names are normalized per
# PD11 before resolving id/kind/claim/links/source/control/written-to: strip
# \r, strip * and backtick, trim, lowercase.
CONDUCTOR_AWK=$(cat <<'CONDUCTOR_AWK_EOF'
function starts_with_tok(val, tok,   re) {
  re = "^" tok "([^A-Za-z0-9]|$)"
  return (val ~ re)
}
function flow_family(val,   n, i, toks) {
  n = split(flows_deliver, toks, " ")
  for (i = 1; i <= n; i++) if (starts_with_tok(val, toks[i])) return "DELIVER"
  n = split(flows_operate, toks, " ")
  for (i = 1; i <= n; i++) if (starts_with_tok(val, toks[i])) return "OPERATE"
  n = split(flows_incident, toks, " ")
  for (i = 1; i <= n; i++) if (starts_with_tok(val, toks[i])) return "INCIDENT"
  return ""
}
function emit(cat, key, msg) { printf "%s\t%s\t%s\n", cat, key, msg }

# True when claim records the lens as a whole token: "<lens>:" not preceded by a
# letter or digit (so tessian: is not ian:), then either "run" or
# "no trigger", an em dash and a non-empty reason (the reason ends at a semicolon).
function lens_recorded(claim, lens,   rest, p, pre, after, dash, reason) {
  dash = "—"
  rest = claim
  while ((p = index(rest, lens ":")) > 0) {
    pre = substr(rest, 1, p - 1)
    after = trim(substr(rest, p + length(lens) + 1))
    rest = substr(rest, p + length(lens) + 1)
    if (pre ~ /[A-Za-z0-9_]$/) continue
    if (after ~ /^run([^A-Za-z0-9]|$)/) return 1
    if (after ~ /^no trigger/) {
      after = trim(substr(after, 11))
      if (index(after, dash) != 1) continue
      reason = substr(after, length(dash) + 1)
      sub(/;.*$/, "", reason)
      if (trim(reason) != "") return 1
    }
  }
  return 0
}

function valid_ignore_tok(tok,   grammar) {
  grammar = "^[A-Za-z_][A-Za-z0-9_-]*(\\[[0-9]+\\]|\\[\"[^\"*?]+\"\\])*(\\.[A-Za-z_][A-Za-z0-9_-]*(\\[[0-9]+\\]|\\[\"[^\"*?]+\"\\])*)*$"
  if (tok !~ grammar) return 0
  if (!(index(tok, ".") > 0 || index(tok, "[") > 0)) return 0
  return 1
}

# extract the leading run of digits from s (POSIX-safe: no 3-arg match)
function leading_digits(s,    t) {
  t = s
  sub(/[^0-9].*$/, "", t)
  return t
}

# ---- decisions file, read via getline (never via a second ARGV file: the
# FNR==NR idiom breaks when the first file has zero lines, which a missing
# decisions file — /dev/null — always does) --------------------------------
BEGIN {
  cur_d = ""
  if (decisions_file != "" && decisions_file != "/dev/null") {
    while ((getline dline < decisions_file) > 0) {
      gsub(/\r/, "", dline)
      if (dline ~ /^## D[0-9]+ /) {
        dd = dline
        sub(/^## D/, "", dd)
        dd = leading_digits(dd)
        cur_d = dd
        d_seen[cur_d] = 1
        d_trigger_ok[cur_d] = 0
        continue
      }
      # F43 (log D20): S4 recommends "Revisit trigger", but "Revisit when"
      # is an accepted spelling in the wild -- this campaign's own decisions
      # log used it in 17 of 19 entries.
      if (cur_d != "" && dline ~ /^- \*\*Revisit (trigger|when)\*\*:/) {
        dval = dline
        sub(/^- \*\*Revisit (trigger|when)\*\*:[ \t]*/, "", dval)
        dval = trim(dval)
        if (dval != "" && !is_placeholder(dval)) d_trigger_ok[cur_d] = 1
      }
    }
    close(decisions_file)
  }
}

# ---- row handlers --------------------------------------------------------
# Shared by the state file's own lines and by sibling lines, so a row parses the
# same wherever it lives (escaped pipes, the width guard, header resolution).
function conductor_line(raw,    n, c, i, rid, id, kind, claim, links, source, control, hdr, n_control) {
  if (raw ~ /^- exempt:/) { conductor_exempt = trim(raw); return }
  if (trim(raw) == "" || raw ~ /^## /) return
  conductor_lines++
  if (raw !~ /^\|/) return
  conductor_is_table = 1
  if (raw ~ /^\|[- |]+\|$/) return  # separator
  n = split_cells(raw, c)
  if (cr_header_ok == -1) {
    cr_ncols = n
    for (i = 1; i <= n; i++) hdr[i] = normhdr(c[i])
    idx_id = idx_kind = idx_claim = idx_links = idx_source = idx_control = idx_written = 0
    n_control = 0
    for (i = 1; i <= n; i++) {
      if (hdr[i] == "id") idx_id = i
      else if (hdr[i] == "kind") idx_kind = i
      else if (hdr[i] == "claim") idx_claim = i
      else if (hdr[i] == "links") idx_links = i
      else if (hdr[i] == "source") idx_source = i
      else if (hdr[i] ~ /^control/) { idx_control = i; n_control++ }
      else if (hdr[i] == "written-to") idx_written = i
    }
    # "control" is the one column resolved by prefix rather than exact
    # name, so it is the one that can silently resolve twice if a header
    # carries two control-prefixed columns; treat that as unresolved
    # rather than quietly keeping the last match.
    if (n_control > 1) idx_control = 0
    cr_header_ok = (idx_id && idx_kind && idx_claim && idx_links && idx_source && idx_control && idx_written) ? 1 : 0
    return
  }
  if (cr_header_ok == 0) return
  # F48: a row whose width does not match the header's is shifted, so every
  # cell index past the break addresses the wrong column. Report the row and
  # skip it -- reading `control` out of a shifted row is how an empty control
  # was accepted as filled.
  # RECORDED, not emitted here: every Check K finding is gated on PD1's
  # adoption boundary in END, and an emit from inside a record rule would
  # bypass it -- flagging a pre-adoption file this check is not allowed to
  # touch. Same reason Check L's cl_bad[] is deferred.
  if (n != cr_ncols) {
    rid = (n >= 2) ? trim(c[2]) : ""
    if (rid == "") rid = "row"
    cr_width_bad[rid] = "row has " (n - 1) " cells, header has " (cr_ncols - 1) " -- an unescaped literal | inside a cell shifts every later column; write it as \\|"
    return
  }
  ncr++
  id = trim(c[idx_id]); kind = trim(c[idx_kind]); claim = trim(c[idx_claim])
  links = trim(c[idx_links]); source = trim(c[idx_source]); control = trim(c[idx_control])
  cr_kind[id] = kind; cr_claim[id] = claim; cr_links[id] = links
  cr_source[id] = source; cr_control[id] = control
  cr_id_known[id] = 1
  cr_placeholder[id] = (is_placeholder(claim) || is_placeholder(links)) ? 1 : 0
}

function findings_row(raw,    n, c, fid, fnote, fdisp) {
  if (raw !~ /^\|/) return
  if (raw ~ /\| *id *\|/) return
  if (raw ~ /^\|[- |]+\|$/) return
  # F48 residual, stated plainly: this table is read POSITIONALLY (no header
  # resolution), so there is no width to compare a row against. `\|` is
  # honoured; an unescaped pipe in a note cell still shifts this read. The
  # conductor and change-ledger tables, which carry the checked claims, are
  # width-guarded above.
  n = split_cells(raw, c)
  if (n < 7) return
  fid = trim(c[2]); fnote = trim(c[7]); fdisp = trim(c[6])
  if (fid == "") return
  f_id_known[fid] = 1
  f_disp[fid] = fdisp
  f_note[fid] = fnote
}

# True when a ## Paths line really declares a path: a <...> placeholder, "n/a"
# and an empty value do not.
function declares_path(line,    v) {
  v = line
  sub(/^- [^:]*:[ \t]*/, "", v)
  gsub(BT, "", v)
  v = trim(v)
  return !(v == "" || is_placeholder(v) || tolower(v) == "n/a")
}

# ---- sibling files, read via getline like the decisions log: not ARGV files
# (the FNR==NR idiom and per-file resets break when a file has zero lines), and
# nothing here depends on NR or FNR. State is initialised here, once, rather
# than on the state file's first line, so lines loaded from a sibling survive
# and a zero-byte state file still reaches END with its siblings read. --------
BEGIN {
  # A literal backtick cannot sit in this heredoc: bash 3.2 cannot parse a
  # command substitution holding an unpaired one.
  BT = sprintf("%c", 96)
  section = ""
  flow = ""
  in_conductor = 0; conductor_lines = 0; conductor_is_table = 0; conductor_exempt = ""
  cr_header_ok = -1
  ncr = 0
  in_change = 0; cl_header_ok = -1; ncl = 0
  in_findings = 0; nf = 0
  in_paths = 0
  incident_stage3 = 0
  tier_seen = 0; tier = ""; tier_surface = 0
  infile_conductor = 0; infile_findings = 0
  declared_ledger = 0; declared_conductor = 0

  led_st = load_sibling(ledger_file, "## Findings ledger", led_lines)
  led_used = (led_st == "ok" || led_st == "stray")
  if (led_used) for (i = 1; i <= led_lines[0]; i++) findings_row(led_lines[i])

  con_st = load_sibling(conductor_file, "## Conductor record", con_lines)
  con_used = (con_st == "ok" || con_st == "stray")
  if (con_used) for (i = 1; i <= con_lines[0]; i++) conductor_line(con_lines[i])
}

# ---- state file (the only file given on the awk command line) -----------
{
  raw = $0
  gsub(/\r/, "", raw)
}

raw ~ /^## / {
  section = trim(raw)
  in_conductor = (section == "## Conductor record")
  in_change = (section ~ /^## Change ledger/)
  in_findings = (section == "## Findings ledger")
  in_paths = (section ~ /^## Paths/)
  if (in_conductor) infile_conductor = 1
  if (in_findings) infile_findings = 1
  next
}

# Check M input: the two declarations in ## Paths.
in_paths && raw ~ /^- Findings ledger:/ { if (declares_path(raw)) declared_ledger = 1 }
in_paths && raw ~ /^- Conductor record:/ { if (declares_path(raw)) declared_conductor = 1 }

# F40: **Flow**: is not always the line's own field -- a combined header
# ("**Shape**: ... | **Tier**: ... | **Flow**: OPERATE-FULL") puts it after
# other fields on the same line. Match anywhere, take the value up to the
# next "|" (if the line has more fields after it) or end of line.
raw ~ /\*\*Flow\*\*:/ {
  fv = raw
  sub(/^.*\*\*Flow\*\*:[ \t]*/, "", fv)
  sub(/[ \t]*\|.*$/, "", fv)
  flow = trim(fv)
}

# The first Tier line in the state file decides which Phase rows are required
# (library parse, shared with the metrics script). Table rows only quote it.
is_tier_line(raw) && !tier_seen {
  tier_seen = 1
  tier = tier_of(raw)
  tier_surface = tier_has_surface(raw)
}

# Stage progress ticks (any family): "- [x] N[a-z]. "
raw ~ /^- \[x\] [0-9]+[a-z]?\. / {
  k = raw
  sub(/^- \[x\] /, "", k)
  sub(/\..*/, "", k)
  ticked[k] = 1
  if (k == "3") incident_stage3 = 1
}

# Phase tracker ticks: "- [x] Phase N:" or "- [x] Phase Na:" (sub-phases,
# e.g. "Phase 0a" / "Phase 0b" -- an established real-world convention, not
# hypothetical: k8s-home-lab's own campaigns split gated sub-attempts this
# way).
raw ~ /^- \[x\] Phase [0-9]+[a-z]?:/ {
  k = raw
  sub(/^- \[x\] Phase /, "", k)
  sub(/:.*/, "", k)
  ticked["P" k] = 1
}

# ---- Conductor record and Findings ledger sections ------------------------
# A section that has a sibling is read from the sibling; the in-file copy is
# ignored (and reported by Check M in END).
in_conductor && !con_used { conductor_line(raw); next }
in_findings && !led_used { findings_row(raw); next }

# ---- Change ledger section (Check L) -------------------------------------
in_change && raw ~ /^\|/ {
  if (raw ~ /^\|[- |]+\|$/) next
  n = split_cells(raw, c)
  if (cl_header_ok == -1) {
    cl_ncols = n
    for (i = 1; i <= n; i++) clh[i] = normhdr(c[i])
    idx_clid = idx_manifest = 0
    for (i = 1; i <= n; i++) {
      if (clh[i] == "id") idx_clid = i
      else if (clh[i] ~ /^manifest/) idx_manifest = i
    }
    cl_header_ok = (idx_clid && idx_manifest) ? 1 : 0
    next
  }
  # F48: same width rule as the conductor table -- a rollback command with an
  # unescaped pipe would otherwise shift the manifest cell out from under the
  # index and get read as whatever landed there.
  if (cl_ncols != 0 && n != cl_ncols) {
    rid = (n >= 2) ? trim(c[2]) : ""
    if (rid == "") rid = "row"
    cl_bad[rid] = "row has " (n - 1) " cells, header has " (cl_ncols - 1) " -- an unescaped literal | inside a cell shifts every later column; write it as \\|"
    next
  }
  ncl++
  clid = trim(c[idx_clid])
  cl_id_known[clid] = 1
  if (cl_header_ok == 0) {
    cl_bad[clid] = "change-ledger row without a resolvable manifest column"
    next
  }
  manifest = trim(c[idx_manifest])
  cl_manifest[clid] = manifest
  if (manifest == "" || is_placeholder(manifest)) {
    cl_bad[clid] = "empty or placeholder manifest cell"
    next
  }
  nseg = split(manifest, segs, ";")
  fields = 0; has_coupling = 0; ignore_list = ""
  for (s = 1; s <= nseg; s++) {
    seg = trim(segs[s])
    if (seg == "") continue
    if (seg ~ /^ignore:/) {
      ig = seg; sub(/^ignore:[ \t]*/, "", ig); ignore_list = ig
    } else if (seg ~ /^coupling:/) {
      has_coupling = 1
    } else if (seg ~ /^created:/ || seg ~ /^unverifiable:/) {
      fields++
    } else if (seg ~ /->/ || seg ~ /→/) {
      fields++
    }
  }
  # F45: name the specific failing reason (which token, or the field count)
  # rather than one generic sentence for every row -- a per-member message
  # assertion is only meaningful if two different bad rows produce two
  # different messages.
  bad_reasons = ""
  if (fields >= 2 && !has_coupling) bad_reasons = bad_reasons "; " fields " fields without coupling:"
  if (ignore_list != "") {
    ntok = split(ignore_list, toks, ",")
    for (t = 1; t <= ntok; t++) {
      tok = trim(toks[t])
      if (tok == "") continue
      if (!valid_ignore_tok(tok)) bad_reasons = bad_reasons "; bad ignore token: " tok
    }
  }
  if (bad_reasons != "") {
    sub(/^; /, "", bad_reasons)
    cl_bad[clid] = bad_reasons
  }
}

END {
  family = flow_family(flow)

  # ---- Check M: split-layout. Not adoption-gated: a sibling that is missing,
  # headingless or duplicated is wrong whenever the campaign was started, and
  # none of these says anything about the conductor record's CONTENT. "Missing"
  # tests the sibling DERIVED beside the state file (ledger_file/conductor_file
  # come from the library's rule), never the path string Paths declares. ------
  if (led_st == "noheading" || led_st == "stray")
    emit("split-layout", "findings-ledger-noheading", "sibling ledger file has content outside a ## Findings ledger section (no such heading, or text ahead of it); that text is not read")
  if (con_st == "noheading" || con_st == "stray")
    emit("split-layout", "conductor-record-noheading", "sibling conductor file has content outside a ## Conductor record section (no such heading, or text ahead of it); that text is not read")
  if (led_used && infile_findings)
    emit("split-layout", "findings-ledger-duplicate", "## Findings ledger is in the state file and in the sibling ledger file; the sibling is read and the in-file section is ignored")
  if (con_used && infile_conductor)
    emit("split-layout", "conductor-record-duplicate", "## Conductor record is in the state file and in the sibling conductor file; the sibling is read and the in-file section is ignored")
  if (declared_ledger && led_st == "missing")
    emit("split-layout", "findings-ledger-missing", "Paths declares a findings ledger but the sibling ledger file beside the state file does not exist")
  if (declared_conductor && con_st == "missing")
    emit("split-layout", "conductor-record-missing", "Paths declares a conductor record but the sibling conductor file beside the state file does not exist")

  # ---- conductor-missing / exemption -------------------------------------
  # PD1 has TWO limbs: a campaign whose slug date is on or after the adoption
  # date carries this section, "and so does any campaign that already has the
  # header". post_by_date is the first limb alone — it decides only whether a
  # MISSING section is an obligation (a pre-cutoff campaign never gains one on
  # resume). is_post_adoption is the union, and it is what every check of the
  # section's CONTENT must ask.
  #
  # F52: decision-trigger asked post_by_date instead, so a campaign with a
  # conductor record and a pre-cutoff slug date had its rows and gate linkages
  # checked while its decisions log went unchecked — the one conductor-family
  # check sitting outside the control flow that already implements the union.
  post_by_date = (slug_date >= conductor_since)
  header_present = (conductor_lines > 0 || conductor_exempt != "")
  is_post_adoption = (post_by_date || header_present)
  # F42: the exempt line is an escape ONLY when it is the section's SOLE
  # content (PD1) -- conductor_lines counts every OTHER non-blank line in
  # the section (the exempt line itself never reaches that counter; see the
  # "next" in the rule above), so conductor_lines > 0 alongside a set
  # conductor_exempt means real content (a table, orphan text) coexists
  # with it. Treat the exempt line as if absent in that case: it stops
  # suppressing everything and normal row/gate-linkage checks proceed.
  exempt_is_sole = (conductor_exempt != "" && conductor_lines == 0)
  if (post_by_date) {
    if (!header_present) {
      # One cause, one line: a conductor sibling with content but no heading
      # has already been reported above, and is not also "missing".
      if (con_st != "noheading") emit("conductor-missing", "-", "post-adoption campaign has no ## Conductor record section")
      exit
    }
    if (exempt_is_sole && conductor_exempt != "- exempt: pre-adoption persona") {
      emit("conductor-missing", "-", "invalid exemption line: " conductor_exempt)
      exit
    }
  } else {
    if (!header_present) exit   # pre-adoption, no header required
  }
  if (exempt_is_sole && conductor_exempt == "- exempt: pre-adoption persona") exit   # valid exemption

  # ---- Check L (F39): shares this same PD1 adoption gate as Check K, not a
  # second copy of it. A pre-adoption campaign's change-ledger rows -- even
  # ones written before the manifest column existed -- are never flagged;
  # reaching this line already means the file is enforced (post-adoption, or
  # pre-adoption with a header already adopted, per PD1's "so does any
  # campaign that already has the header"). No grandfathering once enforced.
  for (clid in cl_bad) emit("mutation-manifest", clid, cl_bad[clid])

  # ---- header resolution ---------------------------------------------------
  if (conductor_is_table && cr_header_ok == 0) {
    emit("conductor-row", "header", "one or more of id/kind/claim/links/source/control/written-to did not resolve")
  }
  for (wid in cr_width_bad) emit("conductor-row", wid, cr_width_bad[wid])

  # ---- gate keys required for this family ----------------------------------
  if (family == "DELIVER") { gate_str = gates_deliver }
  else if (family == "OPERATE") { gate_str = gates_operate }
  else if (family == "INCIDENT") { gate_str = gates_incident }
  else { gate_str = "" }

  ngates = split(gate_str, gs, " ")
  for (g = 1; g <= ngates; g++) {
    gkey = gs[g]; want_fact = 0; heavy_only = 0
    if (index(gkey, ":fact") > 0) { want_fact = 1; sub(/:fact/, "", gkey) }
    if (index(gkey, ":heavy") > 0) { heavy_only = 1; sub(/:heavy/, "", gkey) }
    if (gkey == "P") {
      # Only TINY, LIGHT and STANDARD are exempt. No Tier line, a placeholder
      # and an unparseable value all keep the requirement.
      if (heavy_only && (tier == "TINY" || tier == "LIGHT" || tier == "STANDARD")) continue
      for (pk in ticked) {
        if (pk ~ /^P[0-9]+[a-z]?$/) {
          linked = 0; lens_ok = 0; first_row = ""
          for (id in cr_id_known) {
            if (cr_placeholder[id] || cr_links[id] != pk) continue
            linked = 1
            if (first_row == "" || id < first_row) first_row = id
            if (lens_recorded(cr_claim[id], "ian") && lens_recorded(cr_claim[id], "xander")) lens_ok = 1
          }
          if (!linked) emit("conductor-unlinked", pk, "ticked Phase line has no linked conductor row")
          else if (heavy_only && tier == "HEAVY" && tier_surface && !lens_ok)
            emit("conductor-row", first_row, "HEAVY phase row does not record ian and xander (write each as: ian: run, or ian: no trigger — <why>; the same for xander:)")
        }
      }
      continue
    }
    if (!(gkey in ticked)) continue
    linked = 0; linked_kind = ""
    for (id in cr_id_known) {
      if (!cr_placeholder[id] && cr_links[id] == gkey) { linked = 1; linked_kind = cr_kind[id] }
    }
    if (!linked) {
      emit("conductor-unlinked", gkey, "ticked required key has no linked row")
    } else if (want_fact && linked_kind != "fact") {
      emit("conductor-unlinked", gkey, "linked row is kind=" linked_kind ", want fact")
    }
  }

  # ---- rejected findings need a linked adjudication (unless deferred) ------
  defer_rejected = (family == "INCIDENT" && !incident_stage3)
  if (!defer_rejected) {
    for (fid in f_id_known) {
      disp = f_disp[fid]
      if (disp == "rejected") {
        linked = 0
        for (id in cr_id_known) {
          if (!cr_placeholder[id] && cr_kind[id] == "adjudication" && cr_links[id] == fid) linked = 1
        }
        if (!linked) emit("conductor-unlinked", fid, "rejected finding has no linked adjudication row")
      } else if (disp == "rejected (judgment)") {
        note = f_note[fid]
        if (note ~ /^D[0-9]+:/) {
          dn = note; sub(/^D/, "", dn); dn = leading_digits(dn)
          if (!(dn in d_seen)) emit("conductor-reference", "D" dn, "rejected (judgment) note cites a missing decisions-log entry")
        } else {
          emit("conductor-reference", "note", "rejected (judgment) note lacks a D<n>: citation")
        }
      }
      if (match(f_note[fid], /^reverses F[0-9]+/)) {
        rn = substr(f_note[fid], RSTART, RLENGTH)
        sub(/reverses F/, "", rn)
        tgt = "F" rn
        ok = 0
        if (tgt in f_id_known) {
          if (f_disp[tgt] ~ /^rejected/) ok = 1
        }
        if (!ok) emit("conductor-reference", tgt, "reverses a missing or non-rejected target")
      }
    }
  }

  # ---- conductor-row well-formedness (non-placeholder rows only) -----------
  for (id in cr_id_known) {
    if (cr_placeholder[id]) continue
    kind = cr_kind[id]
    if (kind != "check" && kind != "adjudication" && kind != "fact") {
      emit("conductor-row", id, "unrecognized kind: " kind)
      continue
    }
    if (kind == "check" || kind == "adjudication") {
      ctl = cr_control[id]
      if (ctl == "" || is_placeholder(ctl)) {
        emit("conductor-row", id, "empty or placeholder control")
      } else if (tolower(ctl) == tolower(cr_claim[id])) {
        emit("conductor-row", id, "control restates the claim")
      }
    } else if (kind == "fact") {
      src = cr_source[id]
      if (src == "") {
        emit("conductor-row", id, "fact row has no source")
      } else if (cr_control[id] == "" && tolower(src) !~ /unverified/) {
        emit("conductor-row", id, "fact has empty control and a source not marked unverified")
      }
    }
    if (match(cr_claim[id], /^corrects CR[0-9]+:/)) {
      linked = 0
      for (oid in cr_id_known) {
        if (!cr_placeholder[oid] && cr_kind[oid] == "check" && cr_links[oid] == id) linked = 1
      }
      if (!linked) emit("conductor-reference", id, "corrects-a-fact row has no check row linking the correction's id")
    }
  }

  # ---- decision-trigger -----------------------------------------------------
  # F52: the union, not the date. Reaching this line at all already means the
  # file is enforced -- the pre-cutoff-without-header case exited above -- so
  # this test is belt-and-braces, and it is written as the union so a future
  # reader does not reinstate the date-only reading.
  if (is_post_adoption) {
    for (d in d_seen) {
      if (!d_trigger_ok[d]) emit("decision-trigger", "D" d, "decisions-log entry has no non-placeholder Revisit trigger")
    }
  }
}
CONDUCTOR_AWK_EOF
)

# Check N programs. `read`, not $(cat <<EOF): bash 3.2 cannot parse a command
# substitution whose body holds an unpaired backtick, and these match fences.
# The claims program prints each origin slug an artifact names, once, outside fences.
IFS= read -r -d '' ESCAPE_CLAIMS_AWK <<'ESCAPE_CLAIMS_AWK_EOF' || true
# r is the text after one "Traces-to": an optional closing emphasis, an optional
# parenthesis ("Traces-to (partial ...)"), the colon, then the slug directly.
function claim_origin(r) {
  sub(/^[*`_ \t]+/, "", r)
  if (substr(r, 1, 1) == "(") {
    if (index(r, ")") == 0) return ""
    r = substr(r, index(r, ")") + 1)
    sub(/^[*`_ \t]+/, "", r)
  }
  if (substr(r, 1, 1) != ":") return ""
  r = substr(r, 2)
  sub(/^[*`_ \t]+/, "", r)
  if (!match(r, /^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z0-9][a-z0-9-]*/)) return ""
  return substr(r, 1, RLENGTH)
}
{
  gsub(/\r/, "")
  if (fence == "") {
    if ($0 ~ /^[ \t]*```/) { fence = "`"; next }
    if ($0 ~ /^[ \t]*~~~/) { fence = "~"; next }
  } else {
    if (fence == "`" && $0 ~ /^[ \t]*```/) fence = ""
    else if (fence == "~" && $0 ~ /^[ \t]*~~~/) fence = ""
    next
  }
  rest = $0
  while ((p = index(rest, "Traces-to")) > 0) {
    rest = substr(rest, p + 9)
    o = claim_origin(rest)
    if (o != "" && !(o in seen)) { seen[o] = 1; print o }
  }
}
ESCAPE_CLAIMS_AWK_EOF

# The recorded program reads an origin state file and prints recorded, unrecorded
# (a ## Escapes block with no line naming disc) or noheading (no such block).
IFS= read -r -d '' ESCAPE_RECORDED_AWK <<'ESCAPE_RECORDED_AWK_EOF' || true
# disc is a whole token when no slug character touches it on either side.
function has_token(line, tok,   off, rest, p, pre, post) {
  off = 0; rest = line
  while ((p = index(rest, tok)) > 0) {
    pre = substr(line, 1, off + p - 1)
    post = substr(line, off + p + length(tok))
    if (pre !~ /[a-z0-9-]$/ && post !~ /^[a-z0-9-]/) return 1
    off += p
    rest = substr(line, off + 1)
  }
  return 0
}
{ gsub(/\r/, "") }
/^## / { section = trim($0); if (section == "## Escapes") heading = 1; next }
section == "## Escapes" && is_escape_line($0) && has_token($0, disc) { recorded = 1 }
END { print (recorded ? "recorded" : (heading ? "unrecorded" : "noheading")) }
ESCAPE_RECORDED_AWK_EOF

# Check N for one artifact root: base/investigations/**/*.md and base/incidents/*.postmortem.md.
lint_escapes() {
  local PLANS="$1" base art slug claims origin state verdict
  base=$(dirname "$PLANS")
  [ -d "$base/investigations" ] || [ -d "$base/incidents" ] || return 0
  while IFS= read -r -d '' art; do
    grep -q 'Traces-to' "$art" 2>/dev/null || continue
    slug=$(basename "$art")
    slug=${slug%%.*}
    claims=$(awk "$ESCAPE_CLAIMS_AWK" "$art") || {
      echo "mozart-lint: awk failed on $art" >&2
      exit 3
    }
    while IFS= read -r origin; do
      [ -n "$origin" ] || continue
      [ "$origin" = "$slug" ] && continue
      state=$(campaign_find_state "$origin" "${ROOTS[@]}") || state=""
      if [ -z "$state" ]; then
        finding "escape-unrecorded" "$art — $slug: traces to $origin, which has no state file in this repo (if it cannot be recorded here, write Traces-to: external — <where or why>; $origin)"
        continue
      fi
      verdict=$(awk -v disc="$slug" "$CAMPAIGN_AWK_LIB"$'\n'"$ESCAPE_RECORDED_AWK" "$state") || {
        echo "mozart-lint: awk failed on $state" >&2
        exit 3
      }
      case "$verdict" in
        recorded) ;;
        noheading) finding "escape-unrecorded" "$state — $slug: a defect found in $art traces to this campaign, but it has no ## Escapes block (add one with a Traces-to: line naming $slug)" ;;
        *) finding "escape-unrecorded" "$state — $slug: a defect found in $art traces to this campaign, but its ## Escapes block has no Traces-to: line naming $slug" ;;
      esac
    done <<< "$claims"
  done < <(
    { find "$base/investigations" -type f -name '*.md' -print0 2>/dev/null
      find "$base/incidents" -maxdepth 1 -type f -name '*.postmortem.md' -print0 2>/dev/null; } | sort -zu
  )
}

lint_conductor() {
  local PLANS="$1"
  local f slug slug_date slug_date_src dec ledger_sib conductor_sib cat key msg conductor_out
  # F47: the legacy prefixless flat glob belongs here for the same reason it
  # belongs on C/D — the adoption gate is read from the SLUG DATE, not the
  # path, so a flat file classifies itself and a pre-adoption one exits early
  # inside the awk. Omitting it (as I and J deliberately do, for a different
  # reason stated at their own sites) made a post-adoption flat file invisible.
  for f in "$PLANS"/active/*.state.md "$PLANS"/finished/*.state.md \
           "$PLANS"/active-*.state.md "$PLANS"/finished-*.state.md \
           "$PLANS"/[0-9]*.state.md; do
    [ -f "$f" ] || continue
    slug=$(basename "$f" .state.md)
    # F47: the legacy prefix convention puts active-/finished- BEFORE the
    # date, so reading the date off the raw slug always failed and classified
    # every prefix-legacy file as pre-adoption (0000-00-00) — the same
    # vacuous pass the flat glob hole produced, one layout over.
    slug_date_src="$slug"
    case "$slug_date_src" in
      active-*)   slug_date_src="${slug_date_src#active-}" ;;
      finished-*) slug_date_src="${slug_date_src#finished-}" ;;
    esac
    slug_date=$(printf %s "$slug_date_src" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
    [ -z "$slug_date" ] && slug_date="0000-00-00"
    dec="${f%.state.md}.decisions.md"
    [ -f "$dec" ] || dec=""
    ledger_sib=$(campaign_sibling "$f" ledger)
    conductor_sib=$(campaign_sibling "$f" conductor)
    # The awk runs to completion before any finding is emitted, so a program
    # that does not parse (a function defined twice, say) is an exit 3 here
    # and not an empty process substitution that lints clean.
    conductor_out=$(awk -v slug_date="$slug_date" -v conductor_since="$CONDUCTOR_SINCE" \
                  -v gates_deliver="$CONDUCTOR_GATES_DELIVER" \
                  -v gates_operate="$CONDUCTOR_GATES_OPERATE" \
                  -v gates_incident="$CONDUCTOR_GATES_INCIDENT" \
                  -v flows_deliver="$CONDUCTOR_FLOWS_DELIVER" \
                  -v flows_operate="$CONDUCTOR_FLOWS_OPERATE" \
                  -v flows_incident="$CONDUCTOR_FLOWS_INCIDENT" \
                  -v decisions_file="$dec" \
                  -v ledger_file="$ledger_sib" \
                  -v conductor_file="$conductor_sib" \
                  "$CAMPAIGN_AWK_LIB"$'\n'"$CONDUCTOR_AWK" "$f") || {
      echo "mozart-lint: awk failed on $f" >&2
      exit 3
    }
    while IFS=$'\t' read -r cat key msg; do
      [ -z "$cat" ] && continue
      finding "$cat" "$f — $key: $msg"
    done <<< "$conductor_out"
  done
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
  # F50: word-splitting an unquoted $(find ...) broke on any path containing a
  # space -- the same defect class as mozart-metrics.sh's whitespace-delimited
  # roots/file list. NUL-delimited end to end (find -print0 | sort -zu | read
  # -d ''), because a newline is legal in a POSIX filename too.
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    # flat-dir sweep: only flag files that are actually non-terminal
    s=$(status_of "$f")
    is_terminal "$s" && continue
    finding "stale-active" "$f — Status '$s', untouched >${STALE_DAYS} days (needs a disposition: resume / stopped / aborted)"
  done < <(find "$PLANS"/active "$PLANS" -maxdepth 1 \( -name '*.state.md' -o -name 'active-*.state.md' \) -mtime +"$STALE_DAYS" -print0 2>/dev/null | sort -zu)

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

  # --- Check J: DELIVER campaigns missing the 2b. Constraints row -----------
  # active/ ONLY - never finished/, never the bare-slug glob. Same rationale
  # as Check I (:131-148) applies verbatim: a finished campaign's stage list
  # is a record of what ran, not a template to conform to.
  #
  # PD20 (log D5, phase 5b): a bare '3.' row is not evidence of a DELIVER
  # campaign on its own -- OPERATE's stage 3 is "Change plan" and INCIDENT's
  # is "Converge", neither of which has a 2b. Fires only when flow_family_of
  # returns DELIVER, or returns empty (no parseable Flow field at all) AND
  # the file has stage rows 2., 3. and 12. -- the shape of a DELIVER stage
  # list with no Flow header to classify it by.
  for f in "$PLANS"/active/*.state.md "$PLANS"/active-*.state.md; do
    [ -f "$f" ] || continue
    if grep -qE '^\- \[[ x-]\] 3\. ' "$f" && ! grep -qE '^\- \[[ x-]\] 2b\.' "$f"; then
      family=$(flow_family_of "$(flow_of "$f")")
      fires=0
      if [ "$family" = "DELIVER" ]; then
        fires=1
      elif [ -z "$family" ] && grep -qE '^\- \[[ x-]\] 2\. ' "$f" \
           && grep -qE '^\- \[[ x-]\] 12\. ' "$f"; then
        fires=1
      fi
      if [ "$fires" -eq 1 ]; then
        finding "missing-2b" "$f — -: has a '3. Plan' row but no '2b. Constraints' row (insert it in place between 2 and 3; record the trigger outcome or mark '[-] 2b. Constraints — skipped: no trigger')"
      fi
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

  # --- Checks K/L: conductor record + mutation manifest -----------------
  lint_conductor "$PLANS"

  # --- Check N: an investigation or post-mortem's origin records it -------
  lint_escapes "$PLANS"
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
