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
# Escapes have one rule, is_escape_line (awk): the line that records an escape in a
# state file's ## Escapes block. Metrics counts those lines; lint (Check N) asks
# whether the block holds one naming a discovering slug. Lookup of an origin
# campaign's state file is campaign_find_state (shell), over every layout.
#
# CAMPAIGN_AWK_LIB is awk program text. Each script prepends it to its own
# program: `awk "$CAMPAIGN_AWK_LIB"$'\n'"$PROGRAM"`. POSIX awk only (gate
# V27b): no gawk extensions, no regex intervals, no three-argument match().

campaign_sibling() { # <state-file> <ledger|conductor> -> stdout; rc 1 when not derivable
  case "$1" in *.state.md) ;; *) return 1 ;; esac
  case "$2" in ledger|conductor) ;; *) return 1 ;; esac
  printf '%s.%s.md' "${1%.state.md}" "$2"
}

# campaign_find_state <slug> <plans-root>... -> stdout: the state file of campaign <slug>;
# rc 1 when none is found. Roots are searched in the order given, and within a root
# active/, finished/, aborted/, then the legacy active- and finished- prefixes, then the
# flat prefixless file. Metrics scans aborted/ and lint's other checks do not; a campaign
# that was abandoned can still have shipped a defect, so the lookup covers it.
campaign_find_state() {
  local slug="$1" root cand
  shift
  [ -n "$slug" ] || return 1
  for root in "$@"; do
    for cand in "$root/active/$slug.state.md" "$root/finished/$slug.state.md" \
                "$root/aborted/$slug.state.md" "$root/active-$slug.state.md" \
                "$root/finished-$slug.state.md" "$root/$slug.state.md"; do
      if [ -f "$cand" ]; then printf '%s' "$cand"; return 0; fi
    done
  done
  return 1
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
# is HEAVY), or "" when the line holds no value. A balanced ** wrapper around
# the leading token ("**HEAVY** — why") is not part of it; italic, underscore
# and backticked values are no value, because only the ** wrapper is an
# observed shape and unparseable is the fail-safe side (phase rows required,
# metrics UNTIERED). "" also covers: the unfilled template (a pipe-list not
# followed by another **Field**: label, or an unfilled <tier>), anything not
# upper case ("heavy", "Standard"), a token followed by anything but the end of
# the value, a space, "(", an em dash or ";" (so "STANDARD2", "STANDARD/HEAVY",
# "TINY, LIGHT, STANDARD, HEAVY" are lists or typos, not values), and a
# non-HEAVY token whose remaining text names HEAVY as a whole word
# ("STANDARD (escalated to HEAVY)": the writer is saying HEAVY, so the line is
# not read as STANDARD).
function tier_of(line,   t, rest, tok, after) {
  t = substr(line, index(line, "**Tier**:") + 9)
  if (t ~ /\|/) {
    rest = t; sub(/^[^|]*\|[ \t]*/, "", rest)
    if (rest !~ /^\*\*[A-Za-z][^*|]*(\*\*[ \t]*:|:\*\*)/) return ""
    sub(/[ \t]*\|.*$/, "", t)
  }
  t = trim(t)
  if (t ~ /^\*\*[A-Z]+\*\*/) {
    match(t, /^\*\*[A-Z]+/)
    t = substr(t, 3, RLENGTH - 2) substr(t, RLENGTH + 3)
  }
  if (!match(t, /^[A-Z]+/)) return ""
  tok = substr(t, 1, RLENGTH)
  after = substr(t, RLENGTH + 1)
  if (after != "" && after !~ /^[ (;]/ && after !~ /^—/) return ""
  if (tok != "HEAVY" && has_heavy_word(after)) return ""
  return tok
}
# True when s holds HEAVY as a whole word: not preceded or followed by a letter
# or digit ("HEAVYish" and "NOHEAVY" are not). The neighbours are tested as a
# whole prefix and suffix, never as one byte: awk here splits bytes, and a lone
# byte of a multibyte character next to HEAVY aborts it in a UTF-8 locale.
function has_heavy_word(s,   i, n) {
  n = length(s)
  for (i = 1; i + 4 <= n; i++) {
    if (substr(s, i, 5) != "HEAVY") continue
    if (substr(s, 1, i - 1) ~ /[A-Za-z0-9]$/) continue
    if (substr(s, i + 5) ~ /^[A-Za-z0-9]/) continue
    return 1
  }
  return 0
}
# True when the Tier value carries a "(surface:" record. Keyed on the literal
# prefix only: the closed word list is a writer rule, not something to validate.
function tier_has_surface(line,   t) {
  t = substr(line, index(line, "**Tier**:") + 9)
  return (index(t, "(surface:") > 0)
}
# The "(surface:" record of a Tier line: the text after the label up to the
# first ")". "" when the line has none or the record is empty; tier_has_surface
# tells those apart.
function tier_surface_record(line,   t, i) {
  t = substr(line, index(line, "**Tier**:") + 9)
  i = index(t, "(surface:")
  if (i == 0) return ""
  t = substr(t, i + 9)
  sub(/\).*$/, "", t)
  return t
}
# Splits one segment of a surface record into normalised tokens: punctuation,
# backticks and "/" are separators, ASCII words are lower-cased. Whole strings
# only, never a one-byte window, so multibyte text beside a word is harmless.
function surface_tokens(seg, toks,   n, i, w, k, raw) {
  gsub(/[`*"'.()\/:,]/, " ", seg)
  n = split(seg, raw, /[ \t]+/)
  k = 0
  for (i = 1; i <= n; i++) {
    w = raw[i]
    if (w == "") continue
    if (w ~ /^[A-Za-z]+$/) w = tolower(w)
    toks[++k] = w
  }
  return k
}
function surface_word_listed(w) {
  return (w == "auth" || w == "secrets" || w == "schema" || w == "migrations" || w == "infra" || w == "billing" || w == "security")
}
# True when the record names at least one listed word in its first segment (the
# word list; free text may follow a ";"). An absent record, an empty one and one
# of unlisted words only are not usable.
function tier_surface_usable(line,   segs, k, toks, i) {
  if (!tier_has_surface(line)) return 0
  split(tier_surface_record(line), segs, ";")
  k = surface_tokens(segs[1], toks)
  for (i = 1; i <= k; i++) if (surface_word_listed(toks[i])) return 1
  return 0
}
# True when xander must run every phase. Fail safe by construction: the first
# segment (the word list) is always read, so an empty record, "(surface:)" and
# "(surface: )" alike, wants xander, as does a word that is not listed (the manual
# counts that as touching the surface on every phase). Any token anywhere that is
# auth, secrets or security wants it, and so does a token after a ";" that begins
# auth, secret or security ("authentication", "secret", "auth-flow", "auth+secrets"):
# free text there is read for those prefixes, and other free text ("credentials",
# "maintainer confirmed HEAVY") is accepted as free text. A second "(surface:" on the
# line is anomalous and wants it too. Case, punctuation, backticks and "/" are
# normalised away. An absent record is not read here; the lint reports it itself.
function tier_surface_wants_xander(line,   t, rest, segs, ns, s, k, toks, i) {
  if (!tier_has_surface(line)) return 0
  t = substr(line, index(line, "**Tier**:") + 9)
  rest = substr(t, index(t, "(surface:") + 9)
  if (index(rest, "(surface:") > 0) return 1
  ns = split(tier_surface_record(line), segs, ";")
  k = surface_tokens(segs[1], toks)
  if (k == 0) return 1
  for (i = 1; i <= k; i++) {
    if (toks[i] == "auth" || toks[i] == "secrets" || toks[i] == "security") return 1
    if (!surface_word_listed(toks[i])) return 1
  }
  for (s = 2; s <= ns; s++) {
    k = surface_tokens(segs[s], toks)
    for (i = 1; i <= k; i++) if (toks[i] ~ /^(auth|secret|security)/) return 1
  }
  return 0
}
# Phase keys order by number, then by sub-phase letter: P2 < P2a < P2b < P3, so
# "through P2" does not cover P2a and "through P2b" covers P2, P2a and P2b.
function phase_order(k,   n, suf) {
  sub(/^P/, "", k)
  n = k + 0
  suf = k
  sub(/^[0-9]+/, "", suf)
  return n * 100 + (suf == "" ? 0 : index("abcdefghijklmnopqrstuvwxyz", suf))
}
# The phase an escalation-pass claim covers, as "P<k>", or "" when the claim is not
# the one fixed form "xander: cumulative pass on escalation (through P<k>): run".
function escalation_pass_through(claim,   c) {
  if (!match(claim, /xander: cumulative pass on escalation \(through P[0-9]+[a-z]?\): run([^A-Za-z0-9]|$)/)) return ""
  c = substr(claim, RSTART, RLENGTH)
  sub(/^.*\(through /, "", c)
  sub(/\).*$/, "", c)
  return c
}
# The decision number of an escalation the Tier line records, as the text
# "escalated from <TINY|LIGHT|STANDARD>, D<n>", or "" when it records none.
function tier_escalation_d(line,   t, e) {
  t = substr(line, index(line, "**Tier**:") + 9)
  if (!match(t, /escalated from (TINY|LIGHT|STANDARD), D[0-9]+/)) return ""
  e = substr(t, RSTART, RLENGTH)
  sub(/^.*, D/, "", e)
  return e
}
# True when a line of a state file's ## Escapes block records an escape: it holds
# "Traces-to:", is not a "(none yet)" line, and what follows the label is not a
# <...> placeholder. Text after the target ("n<3 affected") does not matter.
function is_escape_line(line,   target) {
  if (index(line, "Traces-to:") == 0) return 0
  if (line ~ /none yet/) return 0
  target = line
  sub(/^.*Traces-to:[ \t]*/, "", target)
  if (target ~ /^</) return 0
  return 1
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
