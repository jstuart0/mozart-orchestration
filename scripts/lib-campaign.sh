#!/usr/bin/env bash
# lib-campaign.sh — shared helpers for mozart-lint.sh and mozart-metrics.sh.
#
# Sourced, never executed. Both scripts find it beside themselves (resolved
# from their own absolutised path, not the cwd) and refuse to run without it
# (exit 3). Sourcing defines functions and three variables and nothing else: no
# output, no `exit`, no change to shell options, safe to source twice. Its last
# statement sets CAMPAIGN_LIB_END; a script that does not see it treats the
# library as missing, so a copy truncated mid-heredoc (non-empty, with
# CAMPAIGN_AWK_LIB half filled) is loud like an empty one.
#
# Two spellings of one rule live here, so a campaign's sibling files are
# derived in exactly one file:
#   shell  campaign_sibling <state-file> <ledger|conductor>
#   awk    campaign_sibling_awk(statefile, kind), in CAMPAIGN_AWK_LIB
# The awk side also holds load_sibling(file, heading, lines), the one reader for
# a sibling's content (getline, never an ARGV file), so lint and metrics classify
# a sibling as missing, empty, headingless, stray or ok in the same way. The
# Tier field has one parse too (is_tier_line, tier_of, tier_has_surface), so the
# two scripts cannot disagree on a campaign's tier.
# The sibling of state file F is F with `.state.md` replaced by `.ledger.md` or
# `.conductor.md`, beside F. Neither script may spell that rule itself; gate
# V30_lib counts the code lines that do.
#
# CAMPAIGN_AWK_LIB is awk program text. Each script prepends it to its own
# program: `awk "$CAMPAIGN_AWK_LIB"$'\n'"$PROGRAM"`. POSIX awk only (gate
# V27b): no gawk extensions, no regex intervals, no three-argument match().

campaign_sibling() { # <state-file> <ledger|conductor> -> stdout; rc 1 when not derivable
  case "$1" in *.state.md) ;; *) return 1 ;; esac
  case "$2" in ledger|conductor) ;; *) return 1 ;; esac
  printf '%s.%s.md' "${1%.state.md}" "$2"
}

# `read` and not `$(cat <<EOF)`: bash 3.2 (stock macOS) cannot parse a command
# substitution whose body holds an unpaired backtick, and normhdr has one.
IFS= read -r -d '' CAMPAIGN_AWK_LIB <<'CAMPAIGN_AWK_LIB_EOF' || true
# CR is stripped as well as blanks: a CRLF-encoded state file (or sibling)
# parses identically to LF.
function trim(s) { gsub(/\r/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function normhdr(s,   t) { t = s; gsub(/\r/, "", t); gsub(/\*/, "", t); gsub(/`/, "", t); t = trim(t); t = tolower(t); return t }
function is_placeholder(s,   t) { t = trim(s); return (t ~ /^<.*>$/) }
# F48. Markdown table rows were split on a RAW pipe, so a `source` cell
# holding a shell pipeline shifted every later cell and the linter read the
# next cell along as `control` — an empty control parsed as filled, and the
# row passed clean. Two halves, both needed:
#   (a) `\|` is honoured as an escaped pipe: it stays inside its cell, so a
#       piped command is WRITABLE rather than merely banned by prose;
#   (b) the caller compares each row's cell count against the header's and
#       rejects a mismatch, so an UNESCAPED pipe fails loudly instead of
#       parsing into a wrong answer.
# A trailing delimiter is stripped first so `| a | b |` and `| a | b` count
# the same — the count check tests column shift, not trailing-pipe style.
function split_cells(line, arr,   t, i, n) {
  t = line
  sub(/\|[ \t]*$/, "", t)
  gsub(/\\\|/, SENT, t)
  n = split(t, arr, "|")
  for (i = 1; i <= n; i++) gsub(SENT, "|", arr[i])
  return n
}
# The Tier field, one parse for both scripts. A line carries it when
# **Tier**: appears anywhere on it (a combined header puts it after other
# fields) and it is not a table row, which can only quote it. The caller keeps
# the FIRST such line in the state file; a later one is never a second vote.
function is_tier_line(line) { return (index(line, "**Tier**:") > 0 && line !~ /^[ \t]*\|/) }
# The tier that line names: its leading upper-case token ("HEAVY (surface: ...)"
# is HEAVY), or "" when the line holds no value. "" covers the unfilled template
# (a pipe-list not followed by another bold field, or an unfilled <tier>) and
# anything not upper case ("heavy", "Standard", "HEAVYish"); callers read ""
# as untiered.
function tier_of(line,   t, rest, tok) {
  t = substr(line, index(line, "**Tier**:") + 9)
  if (t ~ /\|/) {
    rest = t; sub(/^[^|]*\|[ \t]*/, "", rest)
    if (rest !~ /^\*\*[A-Za-z]/) return ""
    sub(/[ \t]*\|.*$/, "", t)
  }
  t = trim(t)
  if (!match(t, /^[A-Z]+/)) return ""
  tok = substr(t, 1, RLENGTH)
  if (substr(t, RLENGTH + 1, 1) ~ /[A-Za-z]/) return ""
  return tok
}
# True when the Tier value carries a "(surface:" record. Keyed on the literal
# prefix only: the closed word list is a writer rule, not something to validate.
function tier_has_surface(line,   t) {
  t = substr(line, index(line, "**Tier**:") + 9)
  return (index(t, "(surface:") > 0)
}
# Same rule as campaign_sibling above; "" when not derivable.
function campaign_sibling_awk(statefile, kind,   base) {
  if (kind != "ledger" && kind != "conductor") return ""
  if (statefile !~ /\.state\.md$/) return ""
  base = statefile
  sub(/\.state\.md$/, "", base)
  return base "." kind ".md"
}
# Reads a sibling file with getline and collects the lines under `heading`
# (a "## ..." line, compared after trim) up to the next "## " heading into
# lines[1..n], CR stripped, n in lines[0]. Never an ARGV file: a missing or
# zero-byte file would leave the caller's FNR/NR logic with nothing to anchor
# on, which is the trap the decisions-log read in the linter already avoids.
# A "# " title line is a heading too, so a sibling that opens with a title
# before its section is not stray text. Returns:
#   "missing"    cannot be opened
#   "empty"      readable, blank lines only
#   "noheading"  has content, but `heading` never appears
#   "stray"      `heading` appears, but text sits outside every heading ahead of it
#   "ok"         `heading` appears, nothing stray
# The caller reads the section for "ok" and "stray"; a section found in the
# sibling is the one that counts, so an in-file copy of it is ignored.
function load_sibling(file, heading, lines,   raw, rc, k, nonblank, in_sec, found, titled, stray, n) {
  for (k in lines) delete lines[k]
  lines[0] = 0
  if (file == "") return "missing"
  rc = (getline raw < file)
  if (rc < 0) return "missing"
  n = 0; nonblank = 0; in_sec = 0; found = 0; titled = 0; stray = 0
  while (rc > 0) {
    gsub(/\r/, "", raw)
    if (trim(raw) != "") nonblank++
    if (raw ~ /^## /) {
      in_sec = (trim(raw) == heading)
      if (in_sec) found = 1
      titled = 1
    } else if (raw ~ /^# /) {
      in_sec = 0
      titled = 1
    } else if (in_sec) {
      lines[++n] = raw
    } else if (!titled && trim(raw) != "") {
      stray = 1
    }
    rc = (getline raw < file)
  }
  close(file)
  lines[0] = n
  if (nonblank == 0) return "empty"
  if (!found) return "noheading"
  return stray ? "stray" : "ok"
}
BEGIN { SENT = sprintf("%c", 1) }
CAMPAIGN_AWK_LIB_EOF

CAMPAIGN_LIB_END=1
