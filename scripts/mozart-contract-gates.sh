#!/usr/bin/env bash
#
# mozart-contract-gates.sh — the mechanical checks for the persona contracts.
#
# WHY THIS FILE IS A SHELL SCRIPT AND NOT A FENCED BLOCK IN A MARKDOWN DOC:
# every gate below scans markdown. A gate written inside a markdown file lies
# within some gate's scope, so it matches its own text and passes on the
# strength of its own example. That defect recurred four times before this file
# existed. The gates live here; the scanned docs carry a pointer only. V0
# asserts that separation rather than assuming it.
#
# Usage:  bash scripts/mozart-contract-gates.sh [repo-root]
# Syntax: bash -n scripts/mozart-contract-gates.sh   # run this FIRST — a script
#         that does not parse produces no gate results, and "no result" must not
#         read as "no findings".
#
# Gates V0-V3 cover the state-field probes (#6), the codex output flag (#7) and
# the push-transmitted range (#8). V4/V4c/V5/V6 (the pipeline-placement marker,
# #9) are added by that phase; V0 derives its scope from this script's own
# assignments, so it covers new gates without being edited.

set -uo pipefail

# Absolutise BEFORE the cd. Invoked as `bash scripts/mozart-contract-gates.sh
# <other-root>`, a relative BASH_SOURCE re-resolves against the new cwd and the
# script reads a different file - or none. That is not hypothetical: it made V0b
# derive its token set from a path that does not exist on `main`, yielding an
# EMPTY set, an empty alternation, and a pattern that matched every `=` in the
# repo. The gate still failed loudly here, but a degenerate pattern is one
# refactor away from matching nothing and passing vacuously instead.
gatefile=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
gate_root="${1:-$(cd "$(dirname "$gatefile")/.." && pwd)}"
cd "$gate_root" || { echo "FATAL: cannot cd to $gate_root"; exit 2; }

gate_fail=0
report() { # report <name> <ok:0|1> <detail>
  if [ "$2" = "0" ]; then
    printf 'PASS  %-22s %s\n' "$1" "$3"
  else
    printf 'FAIL  %-22s %s\n' "$1" "$3"
    gate_fail=$((gate_fail + 1))
  fi
}
eq() { [ "$1" = "$2" ] && echo 0 || echo 1; }
ge() { [ "$1" -ge "$2" ] && echo 0 || echo 1; }

# Every gate below asserts a COMMAND, not a mention of one. A floor that counts
# substring presence is satisfiable by inert prose inside a fence - measured on
# all three sites: replacing the real command with `echo "we used to git -C
# <worktree> fetch origin --quiet here"` (and the equivalents) left the whole
# suite green. Deletion was already caught; substitution is what a reflow
# produces, and it is what passed.
#
# NO BACKSLASHES in this string: it crosses `awk -v`, which processes escape
# sequences in assignments. That trap has already cost this campaign a round.
# `(^|[|;&(]|! )` admits a leading-whitespace line start, a pipeline stage, a
# `;`/`&&`/`||` separator, `(`, and `if ! cmd` - so legitimate shell forms still
# count, which is the half that keeps the gate off correct work.
v3_cmdpos='(^|[|;&(]|! )[[:space:]]*'

echo "== mozart contract gates =="
echo "root: $gate_root"
echo "gate file: $gatefile"
echo

# ---------------------------------------------------------------------------
# V0 - no gate's scope reaches this file, and no gate body has been mirrored
#      into a scanned file.                                    (Rules 1, 2)
# ---------------------------------------------------------------------------

# Scope source: TRACKED markdown, from git - not `grep -r`.
#
# `grep -r --include='*.md' .` walks the working tree, and .gitignore does not
# bound it. From the canonical checkout that sweep descends into `.mozart/`,
# where the campaign plans live - and a plan quotes gate bodies verbatim, so V0b
# reported hits and V2's pinned counts blew past their pins. The failure was
# WORSE than a false alarm: `.mozart/` is gitignored, so CI and a fresh clone
# passed while the maintainer's own repo-root run failed, and V3 shares an exit
# code with it. `git ls-files` is what a reviewer means by "the repo", it is
# derived rather than a hand-written --exclude-dir list, and it also moots
# untracked scratch markdown flipping a count-pinned gate.
#
# It removes a second divergence too: `grep` here is /usr/bin/grep (BSD), while
# an interactive shell may resolve a ugrep wrapper that honours .gitignore. The
# same command returned 19 and 8 on this host. File selection must not depend on
# which grep answered.
md_grep() { git ls-files -z '*.md' | xargs -0 grep -H "$@" -- ; }

md_n=$(git ls-files '*.md' | grep -c .)
report "V0_scope_source" "$(ge "$md_n" 1)" "tracked markdown files in scope=$md_n (floor 1; 0 means git gave us nothing and every sweep below would be vacuous)"

# (a) structural: the scanned population is markdown; assert none of it is a
#     shell script, so no gate's scope can reach this file.
mdsh=$(git ls-files '*.md' | grep -c '[.]sh$')
case "$gatefile" in
  *.md) mdsh=$((mdsh + 1)) ;;
esac
report "V0a_scope_disjoint" "$(eq "$mdsh" 0)" "shell scripts inside the markdown scope=$mdsh (want 0)"

# (b) identity: derive the token set from THIS script's own assignments - never
#     a hand-written list, which is the scope-writing defect under repair - and
#     pin the count of markdown files carrying any of them at zero. A gate added
#     later is covered without editing V0.
#
# Two changes keep the zero baseline a property of the GATES rather than of what
# the docs happen not to say:
#
#   1. Derived at TRUE line start, with no leading-whitespace strip. Stripping
#      first pulled in awk-internal names from inside embedded programs (`nm=`,
#      `sg=`, `pp=`) - two-letter tokens that carry no identity at all.
#   2. Every derived token that was also an ordinary word is namespaced. A
#      fixture proved the point: `?enum=x` in a tracked doc tripped V0b, and it
#      was right to - `enum` really was a gate variable. `alt=` in an HTML tag
#      and `root=/dev/sda1` in a kernel-cmdline example are the same collision
#      waiting to happen. `root fail alt enum fields corpus inv ord sit ctl cite
#      fam` are now `gate_*`/`v1_*`/`v2_*`/`v3_*`.
#
# The residual is still real and still self-enforcing: a gate naming a variable
# that already appears in tracked markdown fails V0b immediately and must be
# renamed. That is the design, not a gap.
gatevars=$(sed 's/^local //' "$gatefile" \
  | grep -oE '^[A-Za-z_][A-Za-z_0-9]*=' | tr -d '=' | sort -u)
gatevar_n=$(printf '%s\n' "$gatevars" | grep -c .)
# A derivation that produced nothing is not a clean derivation. An empty token
# set builds the alternation `(^|[^A-Za-z_0-9])()=`, which matches every `=` in
# the repo - and the symmetric refactor matches none of them and passes.
report "V0b_derivation" "$(ge "$gatevar_n" 10)" "gate variables derived from $gatefile=$gatevar_n (floor 10; 0 means the gate file was unreadable and the pattern below would be degenerate)"
[ "$gatevar_n" -ge 1 ] || gatevars="__no_gate_vars_derived__"
patfile=$(mktemp)
printf '(^|[^A-Za-z_0-9])(%s)=' "$(printf '%s\n' "$gatevars" | paste -sd'|' -)" > "$patfile"
gatevar_where=$(git ls-files -z '*.md' | xargs -0 grep -lE -f "$patfile" -- 2>/dev/null | paste -sd' ' -)
gatevar_hits=$(printf '%s' "$gatevar_where" | tr ' ' '\n' | grep -c .)
rm -f "$patfile"
report "V0b_no_mirrored_gate" "$(eq "$gatevar_hits" 0)" \
  "derived $(printf '%s\n' "$gatevars" | wc -l | tr -d ' ') names; markdown hits=$gatevar_hits ${gatevar_where}"

# ---------------------------------------------------------------------------
# V1 - the shipped state-field probes match what the template writes, and no
#      bare-form grep survives.                                (Rules 2, 3)
# ---------------------------------------------------------------------------

# Scope derived: the field list comes from the state-file template, not a list.
v1_fields=$(awk '/^\*\*Last updated\*\*/{f=1} f && /^\*\*[A-Z]/{gsub(/^\*\*/,"");sub(/\*\*.*/,"");print} f && /^## Tickets/{exit}' \
  agents/mozart.md | sort -u)
v1_alt=$(printf '%s\n' "$v1_fields" | paste -sd'|' -)

# Control on the derivation itself. Every other derived scope in this file has
# one - V0b_derivation's floor, V4_population's pinned 17, V4c_shapes by name,
# V3_ctl's heading check - and V1, the gate for the campaign's headline bug, did
# not. Rename the template's `**Last updated**` anchor and the field list comes
# back EMPTY, the alternation `()` matches nothing, and a live bare-form
# `grep -l "Status: stopped"` reports 0: issue #6 reintroduced with its own gate
# green. Measured on a fixture. Two conditions, because a floor alone would
# accept a list that no longer contains the field this gate is about.
v1_nfields=$(printf '%s\n' "$v1_fields" | grep -c .)
v1_hasstatus=$(printf '%s\n' "$v1_fields" | grep -cx 'Status')
if [ "$v1_nfields" -ge 5 ] && [ "$v1_hasstatus" -eq 1 ]; then v1_fl=0; else v1_fl=1; fi
report "V1_fieldlist" "$v1_fl" "state-file template fields derived=$v1_nfields (floor 5), 'Status' among them=$v1_hasstatus (want 1); an empty or Status-less list makes the alternation below match nothing"

# must-not half: no invocation may still grep the bare "<Field>: " form.
v1_stale=$(grep -cE "grep[^\"']*[\"']($v1_alt): " agents/mozart.md)
report "V1_absence" "$(eq "$v1_stale" 0)" "bare-form grep invocations=$v1_stale (want 0) over fields: $v1_alt"

# must half: the two-form patterns exist, in the pinned quantity and flag mix.
v1_pats=$(grep -oE "grep -[lL]E '[^']*'" agents/mozart.md | sed -E "s/^grep -[lL]E '//; s/'\$//")
v1_npat=$(printf '%s\n' "$v1_pats" | grep -c . )
v1_ell=$(grep -oE "grep -lE '[^']*'" agents/mozart.md | grep -c .)
v1_bigell=$(grep -oE "grep -LE '[^']*'" agents/mozart.md | grep -c .)
report "V1_npat" "$(eq "$v1_npat" 7)" "two-form probe patterns=$v1_npat (want 7)"
report "V1_flagmix" "$(eq "$v1_ell/$v1_bigell" "6/1")" "-lE/-LE = $v1_ell/$v1_bigell (want 6/1; which site carries -L is a MANUAL check)"

# behavioural half: each pattern must match the template's bold form AND the
# legacy bare form, must not match a different enum value, and its value must
# be a member of the template's declared enum.
v1_enum=$(grep -m1 -E '^\*\*Status\*\*: ' agents/mozart.md | sed -E 's/^\*\*Status\*\*: //; s/ *\| */ /g')
v1_bad=""
v1_corpus=$(mktemp -d)
while IFS= read -r gpat; do
  [ -n "$gpat" ] || continue
  gval="${gpat##*: }"
  case " $v1_enum " in
    *" $gval "*) ;;
    *) v1_bad="$v1_bad [value '$gval' not in enum: $v1_enum]" ; continue ;;
  esac
  gother=""
  for candidate in $v1_enum; do
    [ "$candidate" = "$gval" ] || { gother="$candidate"; break; }
  done
  printf '**Status**: %s\n' "$gval"   > "$v1_corpus/bold.md"
  printf 'Status: %s\n'     "$gval"   > "$v1_corpus/legacy.md"
  printf '**Status**: %s\n' "$gother" > "$v1_corpus/other.md"
  grep -lE "$gpat" "$v1_corpus/bold.md"   >/dev/null 2>&1 || v1_bad="$v1_bad [<$gpat> misses bold form]"
  grep -lE "$gpat" "$v1_corpus/legacy.md" >/dev/null 2>&1 || v1_bad="$v1_bad [<$gpat> misses legacy form]"
  grep -lE "$gpat" "$v1_corpus/other.md"  >/dev/null 2>&1 && v1_bad="$v1_bad [<$gpat> also matches '$gother']"
done < <(printf '%s\n' "$v1_pats")
rm -rf "$v1_corpus"
# Vacuity guard: zero patterns is not "every pattern passed".
[ "$v1_npat" -gt 0 ] || v1_bad=" [no two-form patterns to test - vacuous, not clean]"
report "V1_behaviour" "$([ -z "$v1_bad" ] && echo 0 || echo 1)" \
  "${v1_bad:-all $v1_npat patterns match bold + legacy, reject a foreign value, and carry an enum-member value}"

# ---------------------------------------------------------------------------
# V2 - every codex invocation carries -o in argument position; prompts emit
#      findings last; the output-flag check precedes the budget theory.
#                                                              (Rules 1, 3)
# ---------------------------------------------------------------------------
# Scope excludes this file by construction: --include='*.md' cannot match .sh.
# Each site is truncated to the region between "codex exec " and the prompt
# quote that opens after it, so an -o named inside a prompt does not count.

codexsites=$(md_grep -nF 'codex exec ' 2>/dev/null | grep -v '^CHANGELOG\.md:')
v2_inv=$(printf '%s\n' "$codexsites" | grep -c .)
report "V2_inv" "$(eq "$v2_inv" 8)" "codex exec sites=$v2_inv (want 8)"

noout=$(printf '%s\n' "$codexsites" | awk '
  { i=index($0,"codex exec "); rest=substr($0,i+11);
    q=index(rest,"\""); if (q>0) rest=substr(rest,1,q-1);
    if (match(rest,/(^| )-o /)==0) print }' | grep -c .)
noout_where=$(printf '%s\n' "$codexsites" | awk -F: '
  { i=index($0,"codex exec "); rest=substr($0,i+11);
    q=index(rest,"\""); if (q>0) rest=substr(rest,1,q-1);
    if (match(rest,/(^| )-o /)==0) print $1 ":" $2 }' | paste -sd' ' -)
report "V2_noout" "$(eq "$noout" 0)" "sites lacking -o before the prompt quote=$noout ${noout_where}"

oldp=$(printf '%s\n' "$codexsites" | grep -cF 'Write findings to')
report "V2_oldp" "$(eq "$oldp" 0)" "codex prompts still saying 'Write findings to'=$oldp (want 0)"

ordsites=$(md_grep -nF 'Exit 0 + missing target file' 2>/dev/null | grep -v '^CHANGELOG\.md:')
ordn=$(printf '%s\n' "$ordsites" | grep -c .)
v2_ord=$(printf '%s\n' "$ordsites" | awk '
  { f=index($0,"check the invocation for"); g=index($0,"budget");
    if (f==0 || g==0 || f>g) print }' | grep -c .)
report "V2_ordsites" "$(eq "$ordn" 2)" "exit-0-no-file diagnosis sites=$ordn (want 2)"
report "V2_ord" "$(eq "$v2_ord" 0)" "sites where the output-flag check is absent or after the budget theory=$v2_ord (want 0)"

v2_sit=$(grep -cF 'Reading stdout instead of the target file' agents/mozart.md)
v2_sit=$((v2_sit + $(grep -cF 'escalate to user with the codex stdout as evidence' agents/mozart.md)))
v2_sit=$((v2_sit + $(grep -cF 'escalate to the user with the stdout transcript as evidence' agents/mozart.md)))
report "V2_sit" "$(ge "$v2_sit" 3)" "stdout rule + both escalation clauses surviving=$v2_sit (floor 3)"

# ---------------------------------------------------------------------------
# V3 - the range values are pinned; every scan cites the right name for its
#      family; the scans and the stop rule actually exist.     (Rules 2, 3)
# ---------------------------------------------------------------------------

v3_ctl=$(grep -c '^## Pull request authoring' agents/scott.md)
report "V3_ctl" "$(eq "$v3_ctl" 1)" "section heading '## Pull request authoring' found=$v3_ctl (control: a rename must not silently empty the scope)"

# Fenced command lines inside the section, comments stripped. The fence toggle
# is a flag, not an awk range - an awk range would end on its own start line.
cmdfenced=$(awk '
  /^## Pull request authoring/ { insec=1; next }
  /^## / { insec=0 }
  !insec { next }
  /^[[:space:]]*```/ { infence=!infence; if (infence) fid++; next }
  infence {
    if ($0 ~ /^[[:space:]]*#/) next            # whole-line comment
    sub(/[[:space:]]#.*/,"")                   # trailing comment only: a bare
                                               # /^## / inside an awk program is
                                               # data, not a comment, and a naive
                                               # sub(/#.*/,"") deletes the rest of
                                               # the line - which is how an inlined
                                               # gate hid from V3_noinline.
    if ($0 ~ /[^[:space:]]/) print fid "\t" $0
  }
' agents/scott.md)
cmdlines=$(printf '%s\n' "$cmdfenced" | cut -f2-)

# Values are PINNED, byte-for-byte. A behavioural test cannot discriminate here:
# `git rev-list --count HEAD --not --remotes=origin` and the same command with
# HEAD dropped both return 0 whenever the base has no unpushed commits, which is
# the normal case and precisely why the bug is invisible until it matters.
want_range='HEAD --not --remotes=origin'
want_since='origin/<base>'
# Read the values from FENCED COMMAND LINES, not the whole file. File-wide
# extraction is spoofable: with the real definition broken and
# `<!-- PUSH_RANGE="HEAD --not --remotes=origin" -->` planted ANYWHERE ABOVE it,
# `grep -m1` returns the comment and this gate passes. Measured. Only the
# occurrence count caught it, and only because the plant was additive.
range_defs=$(printf '%s\n' "$cmdlines" | grep -coE 'PUSH_RANGE="[^"]*"')
since_defs=$(printf '%s\n' "$cmdlines" | grep -coE 'PUSH_SINCE="[^"]*"')
push_range_value=$(printf '%s\n' "$cmdlines" | grep -m1 -oE 'PUSH_RANGE="[^"]*"' | sed -E 's/^PUSH_RANGE="//; s/"$//')
push_since_value=$(printf '%s\n' "$cmdlines" | grep -m1 -oE 'PUSH_SINCE="[^"]*"' | sed -E 's/^PUSH_SINCE="//; s/"$//')
report "V3_range_defs" "$(eq "$range_defs/$since_defs" "1/1")" "PUSH_RANGE/PUSH_SINCE definitions=$range_defs/$since_defs (want 1/1)"
report "V3_push_range_value" "$(eq "$push_range_value" "$want_range")" "PUSH_RANGE=[$push_range_value] want [$want_range]"
report "V3_push_since_value" "$(eq "$push_since_value" "$want_since")" "PUSH_SINCE=[$push_since_value] want [$want_since]"

a1=$(printf '%s\n' "$cmdlines" | grep -cF -- '--not --remotes=origin')
a2=$(printf '%s\n' "$cmdlines" | grep -cF -- 'origin/<base>')
bb=$(printf '%s\n' "$cmdlines" | grep -cF -- '<base>..HEAD')
report "V3_a1" "$(eq "$a1" 1)" "literal '--not --remotes=origin' on fenced command lines=$a1 (want 1: the definition block)"
report "V3_a2" "$(eq "$a2" 1)" "literal 'origin/<base>' on fenced command lines=$a2 (want 1: the definition block)"
report "V3_b"  "$(eq "$bb" 0)" "local range '<base>..HEAD' on fenced command lines=$bb (want 0)"

v3_cite=$(printf '%s\n' "$cmdlines" | awk '
  { if (index($0,"$PUSH_RANGE")>0 || index($0,"$PUSH_SINCE")>0) n++ } END { print n+0 }')
report "V3_cite" "$(ge "$v3_cite" 3)" "fenced command lines expanding a range name=$v3_cite (floor 3: gitleaks, trufflehog, fallback)"

# Family mismatch, quote-agnostic: a --log-opts family member takes the RANGE,
# a --since-commit family member takes the single COMMIT. Never crossed.
v3_fam=$(printf '%s\n' "$cmdlines" | awk '
  { if (index($0,"--log-opts")>0     && index($0,"$PUSH_SINCE")>0) n++;
    if (index($0,"--since-commit")>0 && index($0,"$PUSH_RANGE")>0) n++ } END { print n+0 }')
report "V3_fam" "$(eq "$v3_fam" 0)" "family mismatches (range name on a single-commit flag or vice versa)=$v3_fam (want 0)"

# The fallback must be a real git log -p over the named range, not a citation.
fallback_is_real=$(printf '%s\n' "$cmdlines" | awk -v cp="$v3_cmdpos" '
  { if ($0 ~ /git .*log .*-p .*[$]PUSH_RANGE/ && $0 ~ (cp "git[[:space:]]")) n++ } END { print n+0 }')
report "V3_fallback_is_real" "$(ge "$fallback_is_real" 1)" "fenced 'git ... log ... -p ... \$PUSH_RANGE' fallback commands=$fallback_is_real (floor 1)"

# The quoting asymmetry is documented as intrinsic and load-bearing, so it gets
# asserted in BOTH directions rather than described. --log-opts takes ONE string
# the scanner re-splits, so it must be quoted; git log takes separate argv words,
# so it must NOT be. Each form breaks silently in the other's position, and
# `fallback_is_real` alone accepts a quoted fallback.
fallback_quoted=$(printf '%s\n' "$cmdlines" | awk '
  { if ($0 ~ /git .*log .*-p .*[$]PUSH_RANGE/ && index($0,"\"$PUSH_RANGE\"")>0) n++ } END { print n+0 }')
scanner_unquoted=$(printf '%s\n' "$cmdlines" | awk '
  { if (index($0,"--log-opts")>0     && index($0,"$PUSH_RANGE")>0 && index($0,"\"$PUSH_RANGE\"")==0) n++
    if (index($0,"--since-commit")>0 && index($0,"$PUSH_SINCE")>0 && index($0,"\"$PUSH_SINCE\"")==0) n++ } END { print n+0 }')
report "V3_fallback_unquoted" "$(eq "$fallback_quoted" 0)" "fallback commands that QUOTE \$PUSH_RANGE=$fallback_quoted (want 0; git log needs split argv words)"
report "V3_scanner_quoted"    "$(eq "$scanner_unquoted" 0)" "scanner flags that leave their range name UNQUOTED=$scanner_unquoted (want 0; --log-opts/--since-commit take one string)"

# The stop rule binds BOTH coupled sites, asserted per file. scott's runs once at
# 12b; mozart's per-phase gate runs on every phase of every campaign, and is the
# shared definition scott cites - so hardening one and not the other hardens the
# rarer path. Deletion from either is a failure, not a partial pass.
# A rule's SCOPE is the step it governs, not the file it lives in. Counting a
# pinned sentence file-wide is satisfiable by inert text: with the real bullets
# deleted and both sentences appended as HTML comments, all three of these
# passed. Measured. So: restrict to the region, drop HTML comments, and require
# the rule to be the BULLET it is supposed to be - position is part of the
# requirement, not decoration.
# Resolve the region by LINE NUMBER, via grep. Passing the anchors through
# `awk -v` does not work: awk processes escape sequences in -v assignments, so
# `^1\. \*\*Secret scan` reaches the dynamic regex as `^1. **Secret scan` and
# matches nothing - a silently empty region, which is a vacuous pass waiting to
# happen. Caught by these gates failing on correct text.
v3_region() { # v3_region <file> <start-ere> <end-ere>
  v3_rs=$(grep -nE "$2" "$1" | head -1 | cut -d: -f1)
  [ -n "$v3_rs" ] || { echo "__REGION_START_NOT_FOUND__"; return 0; }
  v3_re=$(grep -nE "$3" "$1" | cut -d: -f1 | awk -v a="$v3_rs" '$1>a {print; exit}')
  [ -n "$v3_re" ] || v3_re=$(( $(wc -l < "$1") + 1 ))
  awk -v a="$v3_rs" -v b="$v3_re" 'NR>=a && NR<b' "$1" | grep -v '<!--'
}
# Fenced command lines only, from a region. Same fence-flag rules as $cmdlines:
# a flag, never an awk range, and only trailing `#` comments stripped.
v3_fence_filter() {
  awk '
    /^[[:space:]]*```/ { infence=!infence; next }
    infence {
      if ($0 ~ /^[[:space:]]*#/) next
      sub(/[[:space:]]#.*/,"")
      if ($0 ~ /[^[:space:]]/) print
    }'
}

# Anchors defined ONCE and consumed by both the resolution check and the region
# extraction, so the two cannot drift apart.
v3_a1s='^1\. \*\*Secret scan before publish' ; v3_a1e='^2\. \*\*Find the template'
v3_a7s='^7\. \*\*Write the body'             ; v3_a7e='^8\. \*\*Push and open'
v3_ams='^### 7\. Implement'                  ; v3_ame='^### 8\. Mid-build'

# V3_ctl exists because a rename must not silently EMPTY a scope. The symmetric
# case had no control: lose the END anchor and v3_region falls back to EOF, so
# the region silently WIDENS and a rule relocated 80 lines downstream still
# lands inside it. Failing wide reads exactly like passing. Measured: with the
# end anchor renamed and both stop-rule bullets moved into step 5, every gate
# passed; without the rename the same relocation is caught.
#
# Checked with plain calls, NOT command substitution - `$(...)` runs a subshell
# and the assignment to v3_anchors_bad would never reach the parent.
v3_anchors_bad=""
v3_check_anchors() { # <file> <start-ere> <end-ere> <label>
  v3_cs=$(grep -nE "$2" "$1" | head -1 | cut -d: -f1)
  if [ -z "$v3_cs" ]; then v3_anchors_bad="$v3_anchors_bad [$4: START anchor unresolved]"; return; fi
  v3_ce=$(grep -nE "$3" "$1" | cut -d: -f1 | awk -v a="$v3_cs" '$1>a {print; exit}')
  [ -n "$v3_ce" ] || v3_anchors_bad="$v3_anchors_bad [$4: END anchor unresolved - region widens to EOF]"
}
v3_check_anchors agents/scott.md  "$v3_a1s" "$v3_a1e" step1
v3_check_anchors agents/scott.md  "$v3_a7s" "$v3_a7e" step7
v3_check_anchors agents/mozart.md "$v3_ams" "$v3_ame" mozart-per-phase-gate
report "V3_region_anchors" "$([ -z "$v3_anchors_bad" ] && echo 0 || echo 1)" \
  "${v3_anchors_bad:-all 3 region anchor pairs resolve; no region falls back to EOF}"

v3_step1=$(v3_region agents/scott.md  "$v3_a1s" "$v3_a1e")
v3_step7=$(v3_region agents/scott.md  "$v3_a7s" "$v3_a7e")
v3_mozgate=$(v3_region agents/mozart.md "$v3_ams" "$v3_ame")

stop_rule_scott=$(printf '%s\n' "$v3_step1" | grep -cE '^[[:space:]]*- \*\*A scan that does not run is not a clean scan\.\*\*')
stop_rule_mozart=$(printf '%s\n' "$v3_mozgate" | grep -F 'A scan that does not run is not a clean scan' | grep -cF 'Mechanical secret scan on the staged diff')
report "V3_stop_rule_scott"  "$(ge "$stop_rule_scott" 1)"  "failed-scan stop rule as a bullet inside scott's step 1=$stop_rule_scott (floor 1; pinned by text AND position)"
report "V3_stop_rule_mozart" "$(ge "$stop_rule_mozart" 1)" "failed-scan stop rule inside mozart's per-phase secret-scan bullet=$stop_rule_mozart (floor 1; pinned by text AND position)"

zero_range_rule=$(printf '%s\n' "$v3_step1" | grep -cE '^[[:space:]]*- \*\*A scan reporting 0 commits while the push will transmit objects is a stop, not a pass\.\*\*')
report "V3_zero_range_rule" "$(ge "$zero_range_rule" 1)" "empty-range stop rule as a bullet inside scott's step 1=$zero_range_rule (floor 1; exit status alone cannot separate an empty range from a clean scan)"

# H1: the body-scan REQUIREMENT lives in step 1, but the body does not exist
# until step 7 and step 7.5 forbids inserting anything before the push - so step
# 7 is the only place it can execute. Assert the requirement AND the command.
body_scan_req=$(printf '%s\n' "$v3_step1" | grep -cF '**Body scan**')
# FENCED command lines only. Matching anywhere in the region detects deletion
# but not SUBSTITUTION, and substitution is what a reflow produces: replacing the
# runnable scan with the prose line `We may one day grep the assembled "$body"
# for secrets. Not today.` left the whole suite green. That is this campaign's
# own defect class - a proxy (a line mentioning grep and "$body") standing in for
# the property (a command exists). The stop rules got this treatment in the same
# commit; this sibling gate did not.
# The scanner must be in COMMAND POSITION, not merely present on the line, so
# that fencing a quoted mention (`echo 'grep "$body"'`) does not satisfy it -
# that is f3's substitution one layer down. Command position = line start, or
# after a pipe / separator / `!` / `(`, which admits `if ! grep -q ... "$body"`.
body_scan_cmd=$(printf '%s\n' "$v3_step7" | v3_fence_filter | awk '
  index($0,"\"$body\"")>0 && $0 ~ /(^|[|;&(]|! )[[:space:]]*(grep|gitleaks|trufflehog)[[:space:]]/' | grep -c .)
report "V3_body_scan_req" "$(ge "$body_scan_req" 1)" "body-scan requirement stated in step 1=$body_scan_req (floor 1)"
report "V3_body_scan_cmd" "$(ge "$body_scan_cmd" 1)" "body-scan commands between body creation and the push=$body_scan_cmd (floor 1; the requirement is stated 40+ lines before the artifact exists)"

want_count='PUSH_COUNT=$(git -C <worktree> rev-list --count $PUSH_RANGE)'
push_count_value=$(printf '%s\n' "$cmdlines" | grep -m1 -oE 'PUSH_COUNT=[$][(][^)]*[)]')
report "V3_push_count_value" "$(eq "$push_count_value" "$want_count")" "PUSH_COUNT=[$push_count_value] want [$want_count]"

# The fetch must sit in the unconditional prologue - the fence that defines the
# range - and NOT inside a branch the agent may not take. Before this, it was the
# first line of the scanner fence while the prose claimed it had already run;
# the scanner-less fallback is the common case, so the claim was false on the
# path that actually executes. A rewound origin then silently narrows the range.
deffence=$(printf '%s\n' "$cmdfenced" | grep -F 'PUSH_RANGE="' | head -1 | cut -f1)
fetch_in_def=$(printf '%s\n' "$cmdfenced" | awk -F'\t' -v f="$deffence" -v cp="$v3_cmdpos" '
  $1==f && index($2,"fetch origin")>0 && $2 ~ (cp "git[[:space:]]")' | grep -c .)
scanfences=$(printf '%s\n' "$cmdfenced" | awk -F'\t' -v cp="$v3_cmdpos" '
  $2 ~ (cp "(gitleaks|trufflehog)[[:space:]]") {print $1}' | sort -u)
fetch_in_scan=$(printf '%s\n' "$cmdfenced" | awk -F'\t' -v cp="$v3_cmdpos" -v s="$(printf '%s' "$scanfences" | paste -sd, -)" '
  { split(s,a,","); for(i in a) if ($1==a[i] && index($2,"fetch origin")>0 && $2 ~ (cp "git[[:space:]]")) print }' | grep -c .)
report "V3_fetch_in_prologue" "$(ge "$fetch_in_def" 1)" "fetch COMMANDS in the range-defining fence=$fetch_in_def (floor 1: it must run on every path)"
report "V3_fetch_not_branch"  "$(eq "$fetch_in_scan" 0)" "fetch commands inside a scanner-only fence=$fetch_in_scan (want 0)"

# The scanner invocations themselves had no command assertion at all - a1, cite,
# fam and scanner_quoted all read line content, so `echo running gitleaks detect
# --source <worktree> --log-opts "$PUSH_RANGE"` satisfied every one of them. This
# was the widest of the three: the two scans this section exists to require could
# be turned into echoes with the suite green. Pinned at its measured baseline.
scanner_cmds=$(printf '%s\n' "$cmdlines" | awk -v cp="$v3_cmdpos" '
  $0 ~ (cp "(gitleaks|trufflehog)[[:space:]]")' | grep -c .)
report "V3_scanner_cmds" "$(eq "$scanner_cmds" 2)" "scanner invocations in COMMAND position=$scanner_cmds (want 2: one gitleaks, one trufflehog)"

# Step 1 now defines values in one fence and consumes them in later fences, the
# same coupling step 7-8 already carries the one-shell mandate for.
one_shell=$(awk '/^1\. \*\*Secret scan before publish/{f=1} /^2\. \*\*Find the template/{f=0} f' agents/scott.md \
  | grep -cF 'set -euo pipefail')
report "V3_one_shell" "$(ge "$one_shell" 1)" "one-shell mandate inside step 1=$one_shell (floor 1; split shells leave \$PUSH_RANGE unset)"

# Rule 1 again, from the other side: the section must not re-inline a check that
# reads the file it lives in.
noinline=$(printf '%s\n' "$cmdlines" | grep -cF 'agents/scott.md')
report "V3_noinline" "$(eq "$noinline" 0)" "fenced command lines in the section that scan agents/scott.md=$noinline (want 0)"

# ---------------------------------------------------------------------------
# V4 - every specialist has the placement section, exactly once, in the
#      contract's position, with the marker inside it.          (Rules 2, 3)
# ---------------------------------------------------------------------------

# Scope derived from the roster table, never hand-listed.
v4_roster=$(awk -F'|' '
  /^## Specialists/{f=1;next} /^## /{f=0}
  f && /^\| [a-z]/ {
    if (NF != 6) { printf "MALFORMED\tROW\n"; next }
    nm=$2; cl=$5
    gsub(/^[ \t]+|[ \t]+$/,"",nm); gsub(/^[ \t]+|[ \t]+$/,"",cl)
    print nm "\t" cl
  }' agents/README.md)
v4_n=$(printf '%s\n' "$v4_roster" | grep -c .)
report "V4_population" "$(eq "$v4_n" 17)" "specialists derived from the roster=$v4_n (want 17)"

v4_bad=""
while IFS="$(printf '\t')" read -r ag _; do
  [ -n "$ag" ] || continue
  af="agents/$ag.md"
  [ -f "$af" ] || { v4_bad="$v4_bad [$ag: no file $af]"; continue; }
  v4_secn=$(grep -c "^## Where you fit in mozart's pipeline" "$af")
  [ "$v4_secn" = "1" ] || { v4_bad="$v4_bad [$ag: section count=$v4_secn, want 1]"; continue; }
  v4_sec=$(grep -n "^## Where you fit in mozart's pipeline" "$af" | cut -d: -f1)
  v4_fn=$(grep -n '^## Field notes' "$af" | head -1 | cut -d: -f1)
  [ -n "$v4_fn" ] || { v4_bad="$v4_bad [$ag: no ## Field notes to order against]"; continue; }
  [ "$v4_sec" -lt "$v4_fn" ] || v4_bad="$v4_bad [$ag: section@$v4_sec is not before Field notes@$v4_fn]"
  # containment: the marker must sit strictly inside this section, not merely
  # somewhere in the file. Testing marker-present and heading-present
  # independently is what let a marker land 176 lines away and still pass.
  v4_end=$(awk -v s="$v4_sec" 'NR>s && /^## /{print NR; exit}' "$af")
  [ -n "$v4_end" ] || v4_end=$(wc -l < "$af")
  v4_in=$(awk -v s="$v4_sec" -v e="$v4_end" 'NR>s && NR<e' "$af" | grep -cE '^\*\*Your [A-Z]+ stages\*\*:')
  v4_any=$(grep -cE '^\*\*Your [A-Z]+ stages\*\*:' "$af")
  # Both halves. "At least one inside" is not containment: an agent carrying two
  # markers can have one correctly placed and one stranded in an unrelated
  # section, which is the 176-line miss this gate exists to catch.
  [ "$v4_in" -ge 1 ]        || v4_bad="$v4_bad [$ag: no marker inside the section ($v4_any in the file)]"
  [ "$v4_any" = "$v4_in" ]  || v4_bad="$v4_bad [$ag: $v4_any marker(s) in the file but only $v4_in inside the section]"
  # Cardinality: the contract says ONE marker line per roster-recorded shape.
  # Containment alone accepts a duplicated marker line, and V4c's set comparison
  # used to collapse the duplicate away.
  v4_dupshape=$(awk -v s="$v4_sec" -v e="$v4_end" 'NR>s && NR<e' "$af" \
    | grep -oE '^\*\*Your [A-Z]+ stages\*\*:' | sed -E 's/^\*\*Your //; s/ stages\*\*:$//' \
    | sort | uniq -c | awk '$1>1 {printf "%sx%s ", $2, $1}')
  [ -z "$v4_dupshape" ] || v4_bad="$v4_bad [$ag: repeated marker line(s) for $v4_dupshape]"
done < <(printf '%s\n' "$v4_roster")
report "V4_section" "$([ -z "$v4_bad" ] && echo 0 || echo 1)" \
  "${v4_bad:-all $v4_n specialists: section present exactly once, before Field notes, marker contained}"

# ---------------------------------------------------------------------------
# V4c - roster and markers agree PER PIPELINE; every shape present by name;
#       no en dash in a stage list.                                  (Rule 2)
# ---------------------------------------------------------------------------

# U+2013 EN DASH, CONSTRUCTED from its codepoint - never pasted into this file,
# so an editor that "tidies" en dashes cannot silently retarget the rule.
v4c_en=$(printf '\xe2\x80\x93')
v4c_exempt="1${v4c_en}13"

# Shapes derived from the UNION of both files: PIPELINE.md alone yields five
# (it has no ## EVAL pipeline section); mozart.md supplies the sixth.
v4c_shapes=$(cat agents/PIPELINE.md agents/mozart.md \
  | grep -oE '^## [A-Z]+ pipeline' | sed 's/^## //; s/ pipeline$//' | sort -u)
v4c_missing=""
for want in DELIVER AUDIT DIAGNOSE OPERATE INCIDENT EVAL; do
  printf '%s\n' "$v4c_shapes" | grep -qx "$want" || v4c_missing="$v4c_missing $want"
done
report "V4c_shapes" "$([ -z "$v4c_missing" ] && echo 0 || echo 1)" \
  "shapes derived from the union=$(printf '%s' "$v4c_shapes" | paste -sd, -)${v4c_missing:+ MISSING:$v4c_missing}"

# The roster's Role cell is prose, so V4c's Stages-cell comparison is blind to
# it - it read "orchestrates all three pipeline shapes" while the file added in
# the same commit enumerated six. Scope derived (the shape count); value pinned
# (the number word), so the claim cannot drift from the shapes that exist.
v4c_countword=$(printf '%s\n' "$v4c_shapes" | grep -c .)
case "$v4c_countword" in
  1) v4c_word=one ;;   2) v4c_word=two ;;   3) v4c_word=three ;; 4) v4c_word=four ;;
  5) v4c_word=five ;;  6) v4c_word=six ;;   7) v4c_word=seven ;; 8) v4c_word=eight ;;
  *) v4c_word="$v4c_countword" ;;
esac
v4c_claims=$(grep -coE 'all [a-z]+ pipeline shapes' agents/README.md)
v4c_claimok=$(grep -cF "all $v4c_word pipeline shapes" agents/README.md)
report "V4c_role_shapes" "$(eq "$v4c_claims/$v4c_claimok" "1/1")" \
  "roster Role-cell shape claims=$v4c_claims, agreeing with the $v4c_countword derived shapes ('$v4c_word')=$v4c_claimok (want 1/1)"

# Third intake surface: a persona proposed from the issue template must be able
# to satisfy the contract. Before this it offered three shapes of five, and named
# neither the section, the marker, nor the roster column - so a contribution
# authored from it failed V4, V4c and V6 on arrival.
v4c_tpl=.github/ISSUE_TEMPLATE/new_agent_proposal.md
v4c_tplmiss=""
while IFS= read -r v4c_s; do
  [ -n "$v4c_s" ] || continue
  grep -qF "$v4c_s" "$v4c_tpl" || v4c_tplmiss="$v4c_tplmiss $v4c_s"
done < <(printf '%s\n' "$v4c_shapes")
grep -qF 'stages**:' "$v4c_tpl"        || v4c_tplmiss="$v4c_tplmiss <marker-form>"
grep -qF 'roster Stages column' "$v4c_tpl" || v4c_tplmiss="$v4c_tplmiss <roster-column>"
grep -qF "## Where you fit in mozart's pipeline" "$v4c_tpl" || v4c_tplmiss="$v4c_tplmiss <section-name>"
if [ -z "$v4c_tplmiss" ]; then
  v4c_tplmsg="new_agent_proposal.md names every derived shape, the marker form, the section and the roster column"
else
  v4c_tplmsg="new_agent_proposal.md does not name:$v4c_tplmiss"
fi
report "V4c_intake_template" "$([ -z "$v4c_tplmiss" ] && echo 0 || echo 1)" "$v4c_tplmsg"

# One normalizer, two feeds. Parentheticals are dropped FIRST because they
# contain both ';' and shape-shaped uppercase words.
v4c_norm() {
  awk -F'\t' -v ENDASH="$v4c_en" '{
    nm=$1; s=$2
    gsub(/\([^)]*\)/,"",s)
    gsub(ENDASH,"~",s)
    n=split(s,segs,";")
    for(i=1;i<=n;i++){
      sg=segs[i]; pp="DELIVER"
      if (match(sg,/[A-Z][A-Z]+/)) { pp=substr(sg,RSTART,RLENGTH); sg=substr(sg,RSTART+RLENGTH) }
      while (match(sg,/[0-9]+~[0-9]+|[0-9]+[a-z]?/)) {
        print nm "\t" pp "\t" substr(sg,RSTART,RLENGTH)
        sg=substr(sg,RSTART+RLENGTH)
      }
    }
  }'
}

v4c_rosterpairs=$(printf '%s\n' "$v4_roster" | v4c_norm | sort)
v4c_markerpairs=$(while IFS="$(printf '\t')" read -r ag _; do
    [ -n "$ag" ] || continue
    [ -f "agents/$ag.md" ] || continue
    grep -hE '^\*\*Your [A-Z]+ stages\*\*:' "agents/$ag.md" | while IFS= read -r ml; do
      pp=$(printf '%s' "$ml" | sed -E 's/^\*\*Your ([A-Z]+) stages\*\*:.*/\1/')
      vv=$(printf '%s' "$ml" | sed -E 's/^\*\*Your [A-Z]+ stages\*\*:[[:space:]]*//')
      printf '%s\t%s %s\n' "$ag" "$pp" "$vv"
    done
  done < <(printf '%s\n' "$v4_roster") | v4c_norm | sort)

# comm -23 / comm -13 separately: the triples contain tabs, so comm's indented
# second column is not distinguishable from the data.
v4c_ronly=$(comm -23 <(printf '%s\n' "$v4c_rosterpairs") <(printf '%s\n' "$v4c_markerpairs") | tr '\t' ' ' | paste -sd';' -)
v4c_monly=$(comm -13 <(printf '%s\n' "$v4c_rosterpairs") <(printf '%s\n' "$v4c_markerpairs") | tr '\t' ' ' | paste -sd';' -)
v4c_diff="${v4c_ronly}${v4c_monly}"
if [ -z "$v4c_diff" ]; then
  v4c_msg="per-pipeline sets agree for all $v4_n specialists ($(printf '%s\n' "$v4c_rosterpairs" | grep -c .) agent/pipeline/stage triples)"
else
  v4c_msg="ROSTER-ONLY[$v4c_ronly] MARKER-ONLY[$v4c_monly]"
fi
report "V4c_agreement" "$([ -z "$v4c_diff" ] && echo 0 || echo 1)" "$v4c_msg"

# Any pipeline word used anywhere must be one of the derived shapes.
v4c_unknown=$(printf '%s\n%s\n' "$v4c_rosterpairs" "$v4c_markerpairs" | cut -f2 | sort -u \
  | while IFS= read -r pp; do
      [ -n "$pp" ] || continue
      printf '%s\n' "$v4c_shapes" | grep -qx "$pp" || printf '%s ' "$pp"
    done)
report "V4c_known_shapes" "$([ -z "$v4c_unknown" ] && echo 0 || echo 1)" \
  "${v4c_unknown:-every pipeline word used is a derived shape}${v4c_unknown:+<- not in the derived shape set}"

# En dash: must-not (residue after the exempt span is stripped) AND must (the
# exempt span present in exactly 2 sites of the marker/roster population), so
# tidying it to an ASCII hyphen fails too.
v4c_population=$( { printf '%s\n' "$v4_roster" | cut -f2
    while IFS="$(printf '\t')" read -r ag _; do
      [ -n "$ag" ] || continue
      [ -f "agents/$ag.md" ] || continue
      grep -hE '^\*\*Your [A-Z]+ stages\*\*:' "agents/$ag.md" \
        | sed -E 's/^\*\*Your [A-Z]+ stages\*\*:[[:space:]]*//'
    done < <(printf '%s\n' "$v4_roster"); } )
v4c_residue=$(printf '%s\n' "$v4c_population" | sed "s/${v4c_exempt}//g" | grep -cF "$v4c_en")
v4c_sites=$(printf '%s\n' "$v4c_population" | grep -cF "$v4c_exempt")
report "V4c_endash_absent" "$(eq "$v4c_residue" 0)" "en-dash residue in stage lists after stripping the exempt span=$v4c_residue (want 0)"
report "V4c_endash_exempt" "$(eq "$v4c_sites" 2)" "sites carrying the exempt span=$v4c_sites (want 2: the roster cell and mozart's marker)"

# ---------------------------------------------------------------------------
# V5 - the checklists no longer assert the exception, they point at the gate,
#      and the PR template stays command-free.                   (Rules 1, 3)
# ---------------------------------------------------------------------------
# Rule 1: this gate's own text is in a .sh, so neither scanned file contains it.

v5_stale=$(grep -lF 'scott, dick, hank, librarian, tessa, and mozart' \
  CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null | grep -c .)
report "V5_stale" "$(eq "$v5_stale" 0)" "files still asserting the deleted persona exception=$v5_stale (want 0)"

v5_ptr=$(grep -lF 'scripts/mozart-contract-gates.sh' \
  CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null | grep -c .)
report "V5_ptr" "$(eq "$v5_ptr" 2)" "files pointing at the gate script=$v5_ptr (want 2)"

v5_fences=$(grep -c '^```' .github/PULL_REQUEST_TEMPLATE.md)
report "V5_fences" "$(eq "$v5_fences" 0)" "fenced blocks in the PR template=$v5_fences (want 0 - scott reads this file as untrusted data)"

# ---------------------------------------------------------------------------
# V6 - the authoring contract carries the new wording, not the old, in BOTH
#      files, counted separately. Deletion is not restatement.       (Rule 3)
# ---------------------------------------------------------------------------

v6_stale_contract=$(grep -cF 'the DELIVER stage line' CONTRIBUTING.md)
report "V6_stale_contract" "$(eq "$v6_stale_contract" 0)" "stale 'the DELIVER stage line' wording in CONTRIBUTING.md=$v6_stale_contract (want 0)"

v6_gen_contrib=$(grep -cF 'roster Stages column' CONTRIBUTING.md)
v6_gen_readme=$(grep -cF 'roster Stages column' agents/README.md)
report "V6_generalized_contrib" "$(ge "$v6_gen_contrib" 1)" "'roster Stages column' in CONTRIBUTING.md=$v6_gen_contrib (floor 1)"
report "V6_generalized_readme"  "$(ge "$v6_gen_readme" 1)"  "'roster Stages column' in agents/README.md=$v6_gen_readme (floor 1)"

# Line-range pins into persona files rot silently: the range CONTRIBUTING.md
# pinned for the Default-standard paragraph now holds the placement section this
# campaign made universal, so it pointed new contributors at the wrong contract.
# Cite sections by name; nothing here may pin a persona file by line number.
#
# Widened (ian r2): the original check swept only CONTRIBUTING.md, so it could
# not see a LATER campaign introduce fresh cross-persona line-range pins
# elsewhere - which this campaign's own first attempt did, three times
# (harry.md, jackson.md x2, otto.md), each citing another persona file by
# line/range. Population is DERIVED from v4_roster (persona filenames), never
# hand-listed - the same discipline every other gate here uses. CHANGELOG.md
# excluded by name, same reason as V2/V7/V9: it narrates past changes, so a
# historical line citation there isn't a live persona-to-persona pin. Measured
# clean across the rest of the tracked-markdown scope before this widening.
v6_names=$(printf '%s\n' "$v4_roster" | cut -f1 | paste -sd'|' -)
v6_pinpat="agents/($v6_names)\.md.{0,3}lines? [0-9]|(^|[^A-Za-z_/])($v6_names)\.md:[0-9]+(-[0-9]+)?"
v6_pinhits=$(md_grep -nE "$v6_pinpat" 2>/dev/null | grep -v '^CHANGELOG\.md:')
v6_line_pin=$(printf '%s\n' "$v6_pinhits" | grep -c .)
report "V6_no_line_pin" "$(eq "$v6_line_pin" 0)" "line-range pins into persona files, across all tracked markdown=$v6_line_pin (want 0; cite the section) ${v6_pinhits:+[$v6_pinhits]}"

v6_hank_chain=$(grep -cF 'OPERATE stages: 1.Intake+context pin' agents/hank.md)
report "V6_hank_chain" "$(eq "$v6_hank_chain" 0)" "whole-pipeline restatement surviving in hank.md=$v6_hank_chain (want 0)"

# ---------------------------------------------------------------------------
# V7 - capability-vs-claim: a persona's tools: line must satisfy every
#      capability its own contracts promise - spawning another agent, writing
#      a persisted artifact, or claiming to be read-only.      (Rules 2, 3)
# ---------------------------------------------------------------------------
# Population: v4_roster, UNMODIFIED. mozart IS one of the 17 (agents/README.md
# :15; V4_population pins 17) - hand-appending it here would be exactly the
# scope-writing defect this gate exists to stop.

v7_verb='write|writes|writing|written|author|authors|produce|produces'

# Four alternatives. A no-Task agent must carry none of them about itself.
v7_spawn_pat='call in the specialists|[Ss]pawn [0-9A-Za-z]+ sub-?agents|via the Agent tool|Task\(subagent'

v7_spawn_bad=""
while IFS="$(printf '\t')" read -r ag _; do
  [ -n "$ag" ] || continue
  af="agents/$ag.md"
  [ -f "$af" ] || { v7_spawn_bad="$v7_spawn_bad [$ag: no file $af]"; continue; }
  v7_tools=$(grep -m1 '^tools:' "$af")
  case "$v7_tools" in
    *Task*) continue ;;   # holds Task - spawn imperatives about itself are legitimate
  esac
  v7_hits=$(grep -cE "$v7_spawn_pat" "$af")
  [ "$v7_hits" -eq 0 ] || v7_spawn_bad="$v7_spawn_bad [$ag: $v7_hits spawn-imperative hit(s), no Task in tools]"
done < <(printf '%s\n' "$v4_roster")
report "V7_spawn" "$([ -z "$v7_spawn_bad" ] && echo 0 || echo 1)" \
  "${v7_spawn_bad:-no no-Task agent carries a spawn imperative about itself}"

# Control - a FROZEN, ISOLATED fixture, one line per alternative, each line
# crafted to hit EXACTLY one of the four alternatives (tessa r2: the r1
# control ran against agents/mozart.md, but mozart.md's only living spawn
# text is `Task(subagent` - all its hits come from that ONE alternative, so
# narrowing v7_spawn_pat to 'Task\(subagent' alone still passed the r1
# control while silently losing the three alternatives that actually caught
# harry's and jackson's defects. A merged/aggregate corpus has the identical
# hole: one strong alternative can mask the loss of the other three under a
# bare floor. Testing each line SEPARATELY closes it - if any one alternative
# stops matching, only its own line fails, and the control catches it.
v7_fx1='## When to call in the specialists'
v7_fx2='Spawn 3 sub-agents to investigate independently.'
v7_fx3='Proposals are gathered via the Agent tool before comparing.'
v7_fx4='Task(subagent_type="xander", prompt="review the plan")'
v7_spawnctl_bad=""
for v7_fxline in "$v7_fx1" "$v7_fx2" "$v7_fx3" "$v7_fx4"; do
  printf '%s\n' "$v7_fxline" | grep -qE "$v7_spawn_pat" || v7_spawnctl_bad="$v7_spawnctl_bad [not matched: $v7_fxline]"
done
report "V7_spawn_control" "$([ -z "$v7_spawnctl_bad" ] && echo 0 || echo 1)" \
  "${v7_spawnctl_bad:-all four spawn-imperative alternatives independently matched by an isolated, frozen fixture}"

# Write half. An agent claims a persisted artifact iff a tracked markdown
# line binds its name to a .mozart/ path under the verb alternation above.
# Attribution: a line binds to an agent iff the agent's NAME appears on that
# line (bob) - both directions of the consequence are correct by design, not
# exemption: a path line naming no roster agent is out of scope, and a line
# naming two agents binds to both.
#
# CHANGELOG.md excluded BY NAME, with a reason: it narrates past artifact
# changes, so it matches this pattern forever on correct text, and hand-adding
# an exemption later would be the exact scope-rot this gate exists to
# prevent. Same exclusion, same reason, as V2 (:211) and V9 below.
v7_claimlines=$(git ls-files -z '*.md' | xargs -0 grep -nHEi "($v7_verb)[^.]{0,80}\.mozart/|\.mozart/[^ ]*[^.]{0,80}($v7_verb)" -- \
  | grep -v '^CHANGELOG\.md:')
# Pad every line with a trailing space so a name at true line-end still has a
# following non-letter to match against - this host's grep (ugrep) treats a
# bare $ mid-pattern as an anchor, so a trailing $-alternative is a trap
# rather than a portable end-of-line test. Padding sidesteps it entirely.
v7_claimlines_pad=$(printf '%s\n' "$v7_claimlines" | sed 's/$/ /')

v7_claimants=""
v7_write_bad=""
while IFS="$(printf '\t')" read -r ag _; do
  [ -n "$ag" ] || continue
  af="agents/$ag.md"
  [ -f "$af" ] || { v7_write_bad="$v7_write_bad [$ag: no file $af]"; continue; }
  printf '%s\n' "$v7_claimlines_pad" | grep -qiE "(^|[^A-Za-z])${ag}[^A-Za-z]" || continue
  v7_claimants="$v7_claimants $ag"
  v7_tools=$(grep -m1 '^tools:' "$af")
  case "$v7_tools" in
    *Write*) : ;;
    *) v7_write_bad="$v7_write_bad [$ag: claims a persisted artifact but tools: lacks Write]" ;;
  esac
done < <(printf '%s\n' "$v4_roster")
report "V7_write" "$([ -z "$v7_write_bad" ] && echo 0 || echo 1)" \
  "${v7_write_bad:-every claimant holds Write}"

# Control - THREE named members, not two (bob), tested against agents/
# mozart.md's OWN claim lines SPECIFICALLY, not membership in the merged
# claimant list (tessa r2: this campaign's own sarah.md:95 rewrite now
# self-binds her from her OWN file too, so stripping her mozart.md:1217
# mention - the exact line this control exists to exercise - left her still
# a claimant via the other site, and the merged-population membership test
# still reported PASS 1/1/1). Restricting the test to the agents/mozart.md
# SUBSET of claim lines means the control can only pass if mozart.md's own
# text does the binding, regardless of what any persona's own file says.
v7_mzclaims_pad=$(printf '%s\n' "$v7_claimlines_pad" | grep '^agents/mozart\.md:')
v7_mzharry=$(printf '%s\n' "$v7_mzclaims_pad" | grep -qiE "(^|[^A-Za-z])harry[^A-Za-z]" && echo 1 || echo 0)
v7_mzvalerie=$(printf '%s\n' "$v7_mzclaims_pad" | grep -qiE "(^|[^A-Za-z])valerie[^A-Za-z]" && echo 1 || echo 0)
v7_mzsarah=$(printf '%s\n' "$v7_mzclaims_pad" | grep -qiE "(^|[^A-Za-z])sarah[^A-Za-z]" && echo 1 || echo 0)
v7_claimn=$(printf '%s\n' "$v7_claimants" | tr ' ' '\n' | grep -c .)
if [ "$v7_claimn" -ge 5 ] && [ "$v7_mzharry" = 1 ] && [ "$v7_mzvalerie" = 1 ] && [ "$v7_mzsarah" = 1 ]; then
  v7_claimctl=0
else
  v7_claimctl=1
fi
report "V7_claim_control" "$v7_claimctl" \
  "claimants derived=$v7_claimn (floor 5); agents/mozart.md's OWN claim lines separately bind harry/valerie/sarah=$v7_mzharry/$v7_mzvalerie/$v7_mzsarah (want 1 each - proves the population reaches mozart.md independent of any persona's own file)"

# Inverse half (xander) - an agent HOLDING Write must carry no UNQUALIFIED
# read-only self-assertion. Qualified forms ("Read-only on code", "not ... for
# source code") pass; a bare "Read-only." does not. Makes otto's Write grant
# safe instead of silently self-contradictory.
v7_inv_bad=""
v7_qualified_seen=0
# Punctuation-agnostic (xander r2): the r1 form required a literal period, so
# `agents/dick.md:3`'s frontmatter description - "Read-only; never fixes
# anything." - returned 0 hits and PASSed on a live contradiction (dick now
# holds Write). Broadened to a punctuation class; verified this does NOT
# false-positive on "Read-only on code." (valerie) or "Read-only on
# infrastructure." (otto) - the character directly after "Read-only" there is
# a space, never punctuation, so the class never engages.
v7_ro_punct='[.;,:]'
while IFS="$(printf '\t')" read -r ag _; do
  [ -n "$ag" ] || continue
  af="agents/$ag.md"
  [ -f "$af" ] || continue
  v7_tools=$(grep -m1 '^tools:' "$af")
  case "$v7_tools" in *Write*) : ;; *) continue ;; esac
  v7_bare=$(grep -cE "(^|[^a-z])Read-only$v7_ro_punct" "$af")
  [ "$v7_bare" -eq 0 ] || v7_inv_bad="$v7_inv_bad [$ag: $v7_bare unqualified 'Read-only<punct>' assertion(s)]"
  v7_qual=$(grep -ciE 'Read-only on|for source code' "$af")
  [ "$v7_qual" -eq 0 ] || v7_qualified_seen=$((v7_qualified_seen + 1))
done < <(printf '%s\n' "$v4_roster")
report "V7_readonly_inverse" "$([ -z "$v7_inv_bad" ] && echo 0 || echo 1)" \
  "${v7_inv_bad:-no Write-holding agent carries an unqualified 'Read-only' + punctuation assertion}"
# Control - at least one QUALIFIED form must exist among Write holders, or the
# "zero bare matches" result could be true only because no agent ever writes
# the word "Read-only" at all (V7's own defect class, one check over).
report "V7_readonly_control" "$(ge "$v7_qualified_seen" 1)" \
  "Write-holding agents carrying a QUALIFIED read-only form=$v7_qualified_seen (floor 1)"

# Live behavioural fixture for the punctuation broadening (xander r2) -
# proves both directions on a frozen corpus, not just an assertion about the
# shipped tree: the semicolon/comma form (dick's PRE-repair wording) must be
# caught, and "Read-only on code." must still read as qualified.
v7_ro_fixdir=$(mktemp -d)
printf 'Read-only on code. You report findings.\n' > "$v7_ro_fixdir/qualified_on.md"
printf 'You do not have Edit or Write for source code.\n' > "$v7_ro_fixdir/qualified_altform.md"
printf 'Read-only; never fixes anything.\n' > "$v7_ro_fixdir/bare_semicolon.md"
printf 'Read-only. You report findings.\n' > "$v7_ro_fixdir/bare_period.md"
printf 'Read-only, and nothing else.\n' > "$v7_ro_fixdir/bare_comma.md"
v7_ro_bad=""
grep -qE "(^|[^a-z])Read-only$v7_ro_punct" "$v7_ro_fixdir/qualified_on.md" \
  && v7_ro_bad="$v7_ro_bad [qualified 'Read-only on code.' wrongly flagged as bare]"
grep -qE "(^|[^a-z])Read-only$v7_ro_punct" "$v7_ro_fixdir/qualified_altform.md" \
  && v7_ro_bad="$v7_ro_bad ['for source code' phrasing wrongly flagged as bare]"
for v7_ro_bf in bare_semicolon bare_period bare_comma; do
  grep -qE "(^|[^a-z])Read-only$v7_ro_punct" "$v7_ro_fixdir/$v7_ro_bf.md" \
    || v7_ro_bad="$v7_ro_bad [$v7_ro_bf NOT caught by the broadened class]"
done
rm -rf "$v7_ro_fixdir"
report "V7_readonly_fixture" "$([ -z "$v7_ro_bad" ] && echo 0 || echo 1)" \
  "${v7_ro_bad:-broadened [.;,:] class catches bare semicolon/period/comma forms and still treats 'Read-only on ...'/'for source code' as qualified}"

# Prose-coverage coda (tessa, Low, optional) - nothing above asserts the
# CONTRIBUTING.md capability sentence actually landed, nor that harry's and
# jackson's rewritten routing sections say WHO performs the invocation; the
# earlier fixture only proved the OLD spawn wording is gone, not that the
# replacement says the right thing.
v7_contrib_rule=$(grep -cF 'must satisfy every capability its own contracts promise' CONTRIBUTING.md)
report "V7_contrib_rule_present" "$(ge "$v7_contrib_rule" 1)" \
  "CONTRIBUTING.md capability-vs-claim sentence present=$v7_contrib_rule (floor 1)"

v7_harry_wording=$(grep -cF 'mozart performs the invocation' agents/harry.md)
v7_jackson_wording=$(grep -cF 'mozart performs the invocation' agents/jackson.md)
if [ "$v7_harry_wording" -ge 1 ] && [ "$v7_jackson_wording" -ge 1 ]; then v7_invctl=0; else v7_invctl=1; fi
report "V7_invocation_wording" "$v7_invctl" \
  "harry.md/jackson.md say 'mozart performs the invocation'=$v7_harry_wording/$v7_jackson_wording (want >=1 each)"

# ---------------------------------------------------------------------------
# V8 - DELIVER stage-key parity, ORDERED (not set-equal - codex X5), over
#      five populations, against a reference with its own vacuity control.
#                                                               (Rules 2, 3)
# ---------------------------------------------------------------------------

# P1 - PIPELINE.md DELIVER fenced block: the REFERENCE. Fence detection pipes
# through the EXISTING v3_fence_filter toggle (defined above, V3) rather than
# re-authoring a second toggle-and-count implementation of the same thing
# (dexter H) - the section carries exactly one fenced block, so the flag
# toggle alone is equivalent to the fc==2-exit form this population needs.
v8_p1=$(awk '/^## DELIVER pipeline/{s=1;next} s&&/^## /{exit} s' agents/PIPELINE.md \
  | v3_fence_filter | grep -oE '^[0-9]+[a-z]?\.' | tr -d '.' | paste -sd' ' -)

# P2 - mozart.md "## Stage progress" template
v8_p2=$(awk '/^## Stage progress/{s=1;next} s&&/^## /{exit} s' agents/mozart.md \
  | grep -oE '^- \[.\] [0-9]+[a-z]?\.' | grep -oE '[0-9]+[a-z]?' | paste -sd' ' -)

# P3 - README.md mermaid. A DEDICATED extractor, not v3_fence_filter: this
# needs the SPECIFIC ```mermaid open tag, not a generic any-fence toggle.
v8_p3=$(awk '/^```mermaid/{s=1;next} s&&/^```/{exit} s' README.md \
  | grep -oE '\[[0-9]+[a-z]? ' | tr -d '[ ' | paste -sd' ' -)

# P4 - mozart.md "### Stage labels" table
v8_p4=$(awk '/^### Stage labels/{s=1;next} s&&/^### /{exit} s' agents/mozart.md \
  | grep -oE '^\| [0-9]+[a-z]? ' | grep -oE '[0-9]+[a-z]?' | paste -sd' ' -)

# P5 - mozart.md "### <N>." stage-heading bodies, scoped to the DELIVER
# section so OPERATE's and INCIDENT's own "### 2."/"### 3." don't pollute it
v8_p5=$(awk '/^## DELIVER pipeline/{s=1;next} s&&/^## /{exit} s' agents/mozart.md \
  | grep -oE '^### [0-9]+[a-z]?\.' | grep -oE '[0-9]+[a-z]?' | paste -sd' ' -)

# Control - TWO conditions on the REFERENCE: floor >=13 and 12b present. A
# renamed "## DELIVER pipeline" heading empties P1 and would otherwise make
# all four comparisons below trivially pass against an empty string.
v8_refn=$(printf '%s\n' "$v8_p1" | tr ' ' '\n' | grep -c .)
v8_ref12b=$(printf '%s\n' "$v8_p1" | tr ' ' '\n' | grep -cx '12b')
if [ "$v8_refn" -ge 13 ] && [ "$v8_ref12b" -ge 1 ]; then v8_refctl=0; else v8_refctl=1; fi
report "V8_ref_control" "$v8_refctl" \
  "reference (P1) keys=$v8_refn (floor 13), 12b present=$v8_ref12b (want >=1)"

# Main assertion - ORDERED string equality, not set equality: position IS the
# contract (PIPELINE.md:67-84; codex X5), so appending 2b after 13 must fail
# this even though the SET would still be correct.
v8_bad=""
[ "$v8_p2" = "$v8_p1" ] || v8_bad="$v8_bad [P2 stage-progress differs: got [$v8_p2]]"
[ "$v8_p3" = "$v8_p1" ] || v8_bad="$v8_bad [P3 mermaid differs: got [$v8_p3]]"
[ "$v8_p4" = "$v8_p1" ] || v8_bad="$v8_bad [P4 stage-labels differs: got [$v8_p4]]"
[ "$v8_p5" = "$v8_p1" ] || v8_bad="$v8_bad [P5 stage-heading bodies differ: got [$v8_p5]]"
report "V8" "$([ -z "$v8_bad" ] && echo 0 || echo 1)" \
  "${v8_bad:-all five DELIVER stage-key populations agree, in order, with reference [$v8_p1]}"

# ---------------------------------------------------------------------------
# V9 - prose stage-claim parity: every RUNNING-PROSE claim about DELIVER's
#      stage count names exactly the reference's letter-suffixed keys.
#                                                            (Rules 1, 2, 3)
# ---------------------------------------------------------------------------

# Reference letter-suffixed keys, FULLY DERIVED from V8's own reference (P1) -
# no hand-written key list. Today that is {12b}; once a future phase adds 2b
# to PIPELINE.md's DELIVER block, this gate needs no edit to pick it up.
v9_refkeys=$(printf '%s\n' "$v8_p1" | tr ' ' '\n' | grep -E '^[0-9]+[a-z]$' | sort -u)

# Site population. md_grep-scoped (Rule 1 - this pattern must never sweep the
# .sh file it lives in; V0a covers only markdown-scoped gates and is silent
# about one that sweeps every tracked file). CHANGELOG.md excluded by name,
# same reason as V7's write half and V2. The bare "[0-9]+ stages" arm from the
# documented enumerating grep is CONSTRAINED here to
# "DELIVER[^.]{0,30}\([0-9]+ stages" so a future non-DELIVER "N stages" line
# can never silently join the population through that arm alone - verified
# both directions in V9_deliver_filter below. The other arms are unchanged;
# today's six sites are unaffected because each is also caught by
# "1[--]13"/"incl. 12b"/"plus 12b" (see the "why a per-line filter can't be
# the whole answer" note in the plan - commands/mozart.md:30 carries all
# three pipelines' stage counts on one line, and needs no line-level split).
v9_endash=$(printf '\xe2\x80\x93')
v9_pat='1['"$v9_endash"'-]13|stage numbers|plus (opt-in )?12b|incl\. 12b|\(plus 12b\)|DELIVER[^.]{0,30}\([0-9]+ stages'
v9_sites=$(md_grep -nE "$v9_pat" 2>/dev/null | grep -v '^CHANGELOG\.md:')

# Control - TWO conditions, on the SITE population, DISTINCT from V8's
# reference control (bob and tessa, independently): if the site regex stops
# matching - a reword, a ugrep quirk - the per-site loop below runs zero
# times and this gate would report PASS on an empty population. Floor >=6,
# plus agents/README.md as a named canary: it's the one site no other gate
# can see (V4c's en-dash exemption treats "1-13" as one opaque token there).
v9_siten=$(printf '%s\n' "$v9_sites" | grep -c .)
v9_sitecanary=$(printf '%s\n' "$v9_sites" | grep -c '^agents/README\.md:')
if [ "$v9_siten" -ge 6 ] && [ "$v9_sitecanary" -ge 1 ]; then v9_sitectl=0; else v9_sitectl=1; fi
report "V9_site_control" "$v9_sitectl" \
  "prose claim sites=$v9_siten (floor 6), agents/README.md canary present=$v9_sitecanary (want >=1)"

# Live behavioural fixture for the DELIVER-scoped arm - not just a documented
# claim (r3, codex r1b): an INCIDENT/OPERATE "N stages" line must never match
# through this arm, and the DELIVER line must still match through it.
v9_fixdir=$(mktemp -d)
printf 'INCIDENT pipeline (7 stages: declare+triage)\n' > "$v9_fixdir/incident.md"
printf 'OPERATE pipeline (7 stages: intake+pin)\n' > "$v9_fixdir/operate.md"
printf 'The DELIVER pipeline (13 stages, plus opt-in 12b Ship)\n' > "$v9_fixdir/deliver.md"
v9_fix_bad=""
grep -qE 'DELIVER[^.]{0,30}\([0-9]+ stages' "$v9_fixdir/incident.md" && v9_fix_bad="$v9_fix_bad [INCIDENT fixture wrongly matched]"
grep -qE 'DELIVER[^.]{0,30}\([0-9]+ stages' "$v9_fixdir/operate.md"  && v9_fix_bad="$v9_fix_bad [OPERATE fixture wrongly matched]"
grep -qE 'DELIVER[^.]{0,30}\([0-9]+ stages' "$v9_fixdir/deliver.md" || v9_fix_bad="$v9_fix_bad [DELIVER fixture NOT matched]"
rm -rf "$v9_fixdir"
report "V9_deliver_filter" "$([ -z "$v9_fix_bad" ] && echo 0 || echo 1)" \
  "${v9_fix_bad:-the DELIVER-scoped arm rejects INCIDENT/OPERATE N-stages lines and accepts the DELIVER line}"

# Main assertion - per site, the SET of explicitly-named letter-suffixed keys
# equals the reference set. Fully derived; no hand-written key list.
v9_bad=""
while IFS= read -r v9_line; do
  [ -n "$v9_line" ] || continue
  v9_file=$(printf '%s' "$v9_line" | cut -d: -f1)
  v9_lno=$(printf '%s' "$v9_line" | cut -d: -f2)
  v9_text=$(printf '%s' "$v9_line" | cut -d: -f3-)
  v9_sitekeys=$(printf '%s\n' "$v9_text" | grep -oE '[0-9]+[a-z]' | sort -u)
  if [ "$v9_sitekeys" != "$v9_refkeys" ]; then
    v9_bad="$v9_bad [$v9_file:$v9_lno names {$(printf '%s' "$v9_sitekeys" | paste -sd, -)} want {$(printf '%s' "$v9_refkeys" | paste -sd, -)}]"
  fi
done < <(printf '%s\n' "$v9_sites")
report "V9" "$([ -z "$v9_bad" ] && echo 0 || echo 1)" \
  "${v9_bad:-all $v9_siten prose sites name exactly the reference letter-suffixed keys}"

echo
if [ "$gate_fail" -eq 0 ]; then
  echo "ALL GATES PASS"
  exit 0
fi
echo "$gate_fail GATE(S) FAILED"
exit 1
