#!/usr/bin/env bash
# lib-campaign.sh — shared helpers for mozart-lint.sh and mozart-metrics.sh.
#
# Sourced, never executed. Both scripts find it beside themselves (resolved
# from their own absolutised path, not the cwd) and refuse to run without it
# (exit 3). Sourcing defines functions and two variables and nothing else: no
# output, no `exit`, no change to shell options, safe to source twice.
#
# Two spellings of one rule live here, so a campaign's sibling files are
# derived in exactly one file:
#   shell  campaign_sibling <state-file> <ledger|conductor>
#   awk    campaign_sibling_awk(statefile, kind), in CAMPAIGN_AWK_LIB
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
# Same rule as campaign_sibling above; "" when not derivable.
function campaign_sibling_awk(statefile, kind,   base) {
  if (kind != "ledger" && kind != "conductor") return ""
  if (statefile !~ /\.state\.md$/) return ""
  base = statefile
  sub(/\.state\.md$/, "", base)
  return base "." kind ".md"
}
BEGIN { SENT = sprintf("%c", 1) }
CAMPAIGN_AWK_LIB_EOF
