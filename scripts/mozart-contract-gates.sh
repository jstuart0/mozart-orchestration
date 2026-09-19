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
  agents/STATE.md | sort -u)
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
# PATTERN 2 / D4 RE-SCOPE. This was `agents/mozart.md` — a PATH LITERAL, the idiom
# that does NOT widen. The state-file template moved to agents/STATE.md in this very
# commit, so a scope of mozart.md would assert the absence of a bare-form grep from a
# file that no longer contains the template at all: green for no reason. Re-scoped to
# the glob agents/*.md, which is the model form (it widens automatically because D-A
# lands the carved files flat in agents/). Population floor, because a glob matching
# nothing also counts zero.
v1_absence_files=$(ls agents/*.md 2>/dev/null | grep -c .)
v1_stale=$(grep -hcE "grep[^\"']*[\"']($v1_alt): " agents/*.md 2>/dev/null | paste -sd+ - | bc)
[ "$v1_absence_files" -ge 20 ] || v1_stale=$((v1_stale + 1))
report "V1_absence" "$(eq "$v1_stale" 0)" "bare-form grep invocations=$v1_stale (want 0) across $v1_absence_files agents/*.md file(s) (floor 20) over fields: $v1_alt"

# must half: the two-form patterns exist, in the pinned quantity and flag mix.
# GLOB, not a single file: this population SPLITS across destinations. Five of the
# seven two-form probes are in the state-file sweep (PRE 880-890 -> agents/STATE.md,
# phase 4) and two — the only -LE pair — are in the stage-12 close-out sweep
# (PRE 1594 -> agents/DELIVER.md, phase 5.6). Retargeting to STATE.md alone yields
# 5/0 and fails, measured. The glob holds the whole population at EVERY phase: before
# a section carves its patterns are in mozart.md, after it they are in the carved
# file, and agents/*.md covers both without a per-phase edit.
v1_pat_files=$(ls agents/*.md 2>/dev/null | grep -c .)
v1_pats=$(grep -hoE "grep -[lL]E '[^']*'" agents/*.md 2>/dev/null | sed -E "s/^grep -[lL]E '//; s/'\$//")
v1_npat=$(printf '%s\n' "$v1_pats" | grep -c . )
v1_ell=$(grep -hoE "grep -lE '[^']*'" agents/*.md 2>/dev/null | grep -c .)
v1_bigell=$(grep -hoE "grep -LE '[^']*'" agents/*.md 2>/dev/null | grep -c .)
[ "$v1_pat_files" -ge 20 ] || v1_npat=-1
report "V1_npat" "$(eq "$v1_npat" 7)" "two-form probe patterns=$v1_npat (want 7) across $v1_pat_files agents/*.md file(s) (floor 20)"
report "V1_flagmix" "$(eq "$v1_ell/$v1_bigell" "6/1")" "-lE/-LE = $v1_ell/$v1_bigell (want 6/1; which site carries -L is a MANUAL check)"

# behavioural half: each pattern must match the template's bold form AND the
# legacy bare form, must not match a different enum value, and its value must
# be a member of the template's declared enum.
v1_enum=$(grep -m1 -E '^\*\*Status\*\*: ' agents/STATE.md | sed -E 's/^\*\*Status\*\*: //; s/ *\| */ /g')
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

# Shapes derived from the UNION over the GLOB agents/*.md, not from a path pair.
# Before the carve this was `cat agents/PIPELINE.md agents/mozart.md`: PIPELINE.md
# alone yields five (it has no ## EVAL pipeline section) and mozart.md supplied the
# sixth. The carve moves ## AUDIT / ## DIAGNOSE / ## EVAL pipeline into their own
# files, and a two-path scope cannot see them - measured: the pair form drops EVAL
# and reports five shapes, taking V4c_role_shapes down with it.
#
# The glob is the model form from the carve plan's Pattern 2 table: it auto-widens
# to every carved file because D-A lands them flat in agents/. Verified the widening
# is clean - of the 24 files agents/*.md matches, only PIPELINE.md and mozart.md (and
# now the carved shape files) contain a '^## <SHAPE> pipeline' heading, so the union
# is identical to the pair form's at base and gains nothing spurious.
#
# POPULATION FLOOR, because a glob that matches nothing also derives no shapes and
# would report "MISSING: everything" rather than going quietly green - but a glob
# that matched only ONE file could still satisfy a naive check, so the floor is real.
v4c_files=$(ls agents/*.md 2>/dev/null | grep -c .)
v4c_shapes=$(cat agents/*.md 2>/dev/null \
  | grep -oE '^## [A-Z]+ pipeline' | sed 's/^## //; s/ pipeline$//' | sort -u)
v4c_missing=""
for want in DELIVER AUDIT DIAGNOSE OPERATE INCIDENT EVAL; do
  printf '%s\n' "$v4c_shapes" | grep -qx "$want" || v4c_missing="$v4c_missing $want"
done
[ "$v4c_files" -ge 20 ] || v4c_missing="$v4c_missing [population: agents/*.md matched only $v4c_files file(s), floor 20]"
report "V4c_shapes" "$([ -z "$v4c_missing" ] && echo 0 || echo 1)" \
  "shapes derived from the union over $v4c_files agents/*.md file(s)=$(printf '%s' "$v4c_shapes" | paste -sd, -)${v4c_missing:+ MISSING:$v4c_missing}"

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
#
# Honest limitation, stated rather than left implicit: v7_verb and
# v7_spawn_pat below are HAND-WRITTEN. That is not a scope shortcut this gate
# takes - it is the property's DEFINITION: "capability-vs-claim" only means
# something once someone decides which words count as a claim, the same way
# V1's field list or V4's roster columns had to be named once before they
# could be derived. What stays derived, and is never hand-listed, is the
# POPULATION each half applies the verb set to - v4_roster for spawn, every
# tracked markdown file for write. Each half also carries its own
# two-condition control (V7_spawn_control, V7_claim_control) precisely
# because a hand-written verb set is where this gate's own risk concentrates
# - see the Risks section of the plan this gate was built from, which names
# the verb sets as "the weakest part of both gates."

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
# The exclusion is ACCEPTED, NOT ELIMINATED (tessa T3): a future CHANGELOG
# entry making a LIVE capability claim about an agent - not narrating past
# history - would be permanently invisible to this gate. The blind spot is
# real, it is whole-file (not scoped to old-version headings, which was
# considered and rejected as more fragile than the hole it closes), and it is
# the price of the V2 precedent this exclusion follows. Same treatment V9's
# own header gives its token-vs-parser limit, below.
# Negation guard (codex r2, Medium): prose like "You do **not** write to
# `.mozart/...`" would otherwise bind a claim and fail CI for a persona
# correctly declaring it does NOT write - a gate blocking legitimate text is
# worse than one missing a defect, because it teaches people to distrust the
# suite. Filtered BEFORE claimant binding: a candidate line whose write-verb
# is itself negated within a short window never becomes a claim line. Bound
# to 20 chars (not 80, like the verb-to-path window) so it only reaches a
# negator genuinely modifying THIS verb, not an unrelated "not" earlier in a
# long sentence.
v7_negpat="(^|[^A-Za-z])(not|never|don.t|doesn.t|isn.t)[^.]{0,20}($v7_verb)"
v7_claimlines=$(git ls-files -z '*.md' | xargs -0 grep -nHEi "($v7_verb)[^.]{0,80}\.mozart/|\.mozart/[^ ]*[^.]{0,80}($v7_verb)" -- \
  | grep -v '^CHANGELOG\.md:' \
  | grep -viE "$v7_negpat")
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

# Live fixture proving the negation guard, both directions (codex r2,
# Medium): the negated form must NOT survive extraction, and a genuine
# unnegated claim must still survive it.
v7_neg_fixdir=$(mktemp -d)
printf 'You do **not** write to `.mozart/research/<slug>.md`.\n' > "$v7_neg_fixdir/negated.md"
printf 'Write the brief to `.mozart/research/<slug>.md`.\n' > "$v7_neg_fixdir/positive.md"
v7_neg_survived=$(grep -nHEi "($v7_verb)[^.]{0,80}\.mozart/|\.mozart/[^ ]*[^.]{0,80}($v7_verb)" "$v7_neg_fixdir/negated.md" \
  | grep -viE "$v7_negpat" | grep -c .)
v7_pos_survived=$(grep -nHEi "($v7_verb)[^.]{0,80}\.mozart/|\.mozart/[^ ]*[^.]{0,80}($v7_verb)" "$v7_neg_fixdir/positive.md" \
  | grep -viE "$v7_negpat" | grep -c .)
rm -rf "$v7_neg_fixdir"
v7_neg_bad=""
[ "$v7_neg_survived" -eq 0 ] || v7_neg_bad="$v7_neg_bad [negated form wrongly survived the filter as a claim]"
[ "$v7_pos_survived" -ge 1 ] || v7_neg_bad="$v7_neg_bad [genuine unnegated claim was wrongly filtered out]"
report "V7_negation_fixture" "$([ -z "$v7_neg_bad" ] && echo 0 || echo 1)" \
  "${v7_neg_bad:-negated write-verb prose does not register as a claim (survived=$v7_neg_survived); a real claim still does (survived=$v7_pos_survived)}"

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

# Two more documentation mandates (plan 1.1's T3 and honest-limitation
# deliverables) that nothing mechanized (valerie, reconciliation r3): the two
# places V7 discloses its OWN limits were exactly the two places nothing
# checked, which is this campaign's signature defect one layer out. Self-
# referential checks on the gate script's own comments, same pattern V0b
# already uses to read "$gatefile" directly.
# Anchored to COMMENT lines ('# ...'), not just present anywhere in the file:
# a bare grep here would match this check's OWN quoted pattern string two
# lines down and pass at floor 1 even if the disclosure comment itself were
# deleted - self-matching inflating its own floor, the identical vacuity
# shape V0 exists to catch, one level deeper. Comment-anchoring means only
# the actual prose disclosure can satisfy it.
v7_changelog_residual=$(grep -cEi '^# .*accepted, not eliminated' "$gatefile")
report "V7_changelog_residual_stated" "$(ge "$v7_changelog_residual" 1)" \
  "V7's CHANGELOG.md exclusion states its own residual blind spot=$v7_changelog_residual (floor 1)"

v7_honest_limit=$(grep -cEi '^# .*not a scope shortcut' "$gatefile")
report "V7_honest_limitation_stated" "$(ge "$v7_honest_limit" 1)" \
  "verb-set honest-limitation comment present=$v7_honest_limit (floor 1)"

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
v8_p2=$(awk '/^## Stage progress/{s=1;next} s&&/^## /{exit} s' agents/STATE.md \
  | grep -oE '^- \[.\] [0-9]+[a-z]?\.' | grep -oE '[0-9]+[a-z]?' | paste -sd' ' -)

# P3 - README.md mermaid. A DEDICATED extractor, not v3_fence_filter: this
# needs the SPECIFIC ```mermaid open tag, not a generic any-fence toggle.
# Scoped to the pipeline section FIRST (codex r2, Medium): reading the first
# ```mermaid block in the whole file would make an unrelated diagram added
# above this one silently become P3's population - correct content failing
# on a change that never touched it. Section-scope, then fence-scope.
v8_p3=$(awk '/^## The pipeline at a glance/{s=1;next} s&&/^## /{exit} s' README.md \
  | awk '/^```mermaid/{f=1;next} f&&/^```/{exit} f' \
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

# Live fixture proving P3's section-scoping (codex r2, Medium): an unrelated
# mermaid block ABOVE the pipeline section must not become the population.
v8_p3_fixdir=$(mktemp -d)
cat > "$v8_p3_fixdir/readme.md" <<'EOF'
# Title

## Some other section

```mermaid
flowchart LR
    X[99z · Unrelated]
```

## The pipeline at a glance

```mermaid
flowchart LR
    A[1 · Intake]
    A --> B[2 · Research]
```
EOF
v8_p3_unscoped=$(awk '/^```mermaid/{s=1;next} s&&/^```/{exit} s' "$v8_p3_fixdir/readme.md" \
  | grep -oE '\[[0-9]+[a-z]? ' | tr -d '[ ' | paste -sd' ' -)
v8_p3_scoped=$(awk '/^## The pipeline at a glance/{s=1;next} s&&/^## /{exit} s' "$v8_p3_fixdir/readme.md" \
  | awk '/^```mermaid/{f=1;next} f&&/^```/{exit} f' \
  | grep -oE '\[[0-9]+[a-z]? ' | tr -d '[ ' | paste -sd' ' -)
rm -rf "$v8_p3_fixdir"
v8_p3_bad=""
[ "$v8_p3_unscoped" = "99z" ] || v8_p3_bad="$v8_p3_bad [unscoped extraction should have read the unrelated block first, got [$v8_p3_unscoped] - fixture itself is wrong]"
[ "$v8_p3_scoped" = "1 2" ] || v8_p3_bad="$v8_p3_bad [scoped extraction should read only the pipeline block, got [$v8_p3_scoped]]"
report "V8_p3_scope_fixture" "$([ -z "$v8_p3_bad" ] && echo 0 || echo 1)" \
  "${v8_p3_bad:-scoping to the pipeline section before the fence rejects an unrelated mermaid block above it (unscoped would have read [99z])}"

# ---------------------------------------------------------------------------
# V9 - DELIVER stage-key TOKEN parity across prose sites: every site names
#      the same set of letter-suffixed key TOKENS as the reference. Named for
#      what it checks, not more: this is token presence, not a claim parser
#      - it has no negative-context awareness, so a hypothetical or negated
#      sentence carrying the right tokens still passes (codex r2, Low). A
#      gate whose name promises more than it verifies is the same defect
#      class this campaign exists to remove, in miniature.
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

# ---------------------------------------------------------------------------
# V10a — metrics placeholder-vs-real note-cell bug (PD10, phase 1)
#
# scripts/mozart-metrics.sh used to skip ANY findings-ledger row containing a
# literal '<' anywhere on the line, and ANY escapes line containing '<'
# anywhere - not just a row whose note/target cell IS a template placeholder.
# A real finding whose note mentioned "n<3 cases", or a real escape whose
# Traces-to target was followed by "n<3 affected", was silently dropped from
# both the numerator (catches) and the denominator (escapes). PD10 narrows
# the skip to: findings - the note cell, trimmed, is WHOLLY `<...>`;
# escapes - the line says "none yet", or the Traces-to TARGET itself starts
# with '<'. tests/fixtures/conductor/metrics-placeholder/ carries both a
# `n<3 cases` fixed-High row and a `n<3 affected` Traces-to row that must
# now count, alongside the untouched template rows that must still be
# skipped. Runs $gate_root's OWN mozart-metrics.sh (so a base tree
# reproduces the bug; the head tree proves the fix) against the corpus
# resolved from this script's own repo, per PD8's split.
# ---------------------------------------------------------------------------
v10a_script_repo=$(dirname "$(dirname "$gatefile")")
v10a_corpus="$v10a_script_repo/tests/fixtures/conductor/metrics-placeholder"
v10a_expected="$v10a_corpus/expected.tsv"
v10a_floor=$(grep -c "$(printf '^metrics\t')" "$v10a_expected" 2>/dev/null || echo 0)
v10a_member='Confirmed catches (Critical/High, disposition=fixed): 2'
v10a_out=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v10a_corpus" 2>&1)
v10a_rc=$?
v10a_bad=""
[ "$v10a_rc" -eq 0 ] || v10a_bad="$v10a_bad [exit=$v10a_rc want 0]"
[ "$v10a_floor" -ge 2 ] || v10a_bad="$v10a_bad [expected-file floor $v10a_floor < 2 -- corpus file empty or truncated]"
printf '%s\n' "$v10a_out" | grep -qxF "$v10a_member" || v10a_bad="$v10a_bad [named member absent: $v10a_member]"
v10a_missing=""
while IFS= read -r v10a_line; do
  [ -n "$v10a_line" ] || continue
  printf '%s\n' "$v10a_out" | grep -qxF "$v10a_line" || v10a_missing="$v10a_missing [$v10a_line]"
done < <(cut -f2 "$v10a_expected")
[ -z "$v10a_missing" ] || v10a_bad="$v10a_bad expected line(s) absent:$v10a_missing"
report "V10a" "$([ -z "$v10a_bad" ] && echo 0 || echo 1)" \
  "${v10a_bad:-metrics-placeholder: exit=$v10a_rc, $v10a_floor expected line(s) present, named member present}"

# ---------------------------------------------------------------------------
# V11 — lint Checks K/L behave per the committed corpus (PD24, phase 5)
#
# Same $gatefile/$gate_root split as V10a: corpus from this script's own
# repo, script under test from $gate_root, so pointing gate_root at a base
# worktree exercises base scripts against head fixtures. Category set is the
# six K/L names plus missing-2b (phase 5b, step 31, now that Check J's
# DELIVER-family gating is fixed).
# ---------------------------------------------------------------------------
v11_script_repo=$(dirname "$(dirname "$gatefile")")
v11_corpus="$v11_script_repo/tests/fixtures/conductor/lint"
v11_expected="$v11_corpus/expected.tsv"
v11_cats='conductor-missing|conductor-unlinked|conductor-row|conductor-reference|decision-trigger|mutation-manifest|missing-2b'

# F47: the floor used to count only the two subdirs, so the legacy prefix,
# legacy flat and legacy-root fixtures the corpus now carries were invisible
# to it — a floor that cannot see the layouts the check was blind to cannot
# notice them being deleted. Count every state file under the corpus.
v11_floor=$(find "$v11_corpus" -name '*.state.md' 2>/dev/null | wc -l | tr -d ' ')
# ...and assert each of the six layouts K/L must reach is actually populated.
# A total floor alone cannot tell "47 files, all in active/" from "47 files
# across six layouts"; the second is what this corpus is for.
v11_layout_missing=""
v11_layout_probe() { # $1 = human label, $2.. = glob expansion
  local label="$1"; shift
  local hit=0 probe
  for probe in "$@"; do [ -f "$probe" ] && hit=1 && break; done
  [ "$hit" -eq 1 ] || v11_layout_missing="$v11_layout_missing [$label]"
}
v11_layout_probe "current/active"  "$v11_corpus/.mozart/plans/active"/*.state.md
v11_layout_probe "current/finished" "$v11_corpus/.mozart/plans/finished"/*.state.md
v11_layout_probe "legacy active- prefix" "$v11_corpus/.mozart/plans"/active-*.state.md
v11_layout_probe "legacy finished- prefix" "$v11_corpus/.mozart/plans"/finished-*.state.md
v11_layout_probe "legacy flat prefixless" "$v11_corpus/.mozart/plans"/[0-9]*.state.md
v11_layout_probe "legacy root thoughts/shared" "$v11_corpus/thoughts/shared/plans"/[0-9]*.state.md

v11_extract() { # stdin: raw LINT output -> stdout: category\tslug\tkey, restricted to $1 (pipe-joined)
  awk -F'\t' -v cats="$1" '
    BEGIN { n = split(cats, a, "|"); for (i = 1; i <= n; i++) catset[a[i]] = 1 }
    /^LINT \[/ {
      line = $0
      rest = line
      sub(/^LINT \[/, "", rest)
      split(rest, p, "]")
      cat = p[1]
      if (!(cat in catset)) next
      body = rest
      sub(/^[^]]*\][ \t]*/, "", body)
      nsep = split(body, q, " — ")
      path = q[1]
      keymsg = q[2]
      for (i = 3; i <= nsep; i++) keymsg = keymsg " — " q[i]
      split(keymsg, r, ": ")
      key = r[1]
      slug = path
      sub(/^.*\//, "", slug)
      sub(/\.state\.md$/, "", slug)
      printf "%s\t%s\t%s\n", cat, slug, key
    }
  '
}

# F47 residual, closed here: the legacy-root fixture was gitignored by the
# blanket `thoughts/` rule and passed locally while being absent from every
# other checkout. A corpus file git cannot see is a phantom, so assert the
# whole corpus is tracked rather than trusting that it is.
v11_on_disk=$(find "$v11_corpus" -name '*.state.md' 2>/dev/null | wc -l | tr -d ' ')
v11_tracked=$(git -C "$v11_script_repo" ls-files -- "${v11_corpus#"$v11_script_repo/"}" 2>/dev/null | grep -c '\.state\.md$' || true)

v11_ov_out=$(MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 bash "$gate_root/scripts/mozart-lint.sh" "$v11_corpus" 2>&1)
v11_ov_rc=$?
v11_no_out=$(bash "$gate_root/scripts/mozart-lint.sh" "$v11_corpus" 2>&1)

v11_ov_triples=$(printf '%s\n' "$v11_ov_out" | v11_extract "$v11_cats" | sort -u)
v11_no_triples=$(printf '%s\n' "$v11_no_out" | v11_extract "$v11_cats" | sort -u)
v11_expected_triples=$(awk -F'\t' -v cats="$v11_cats" '
    BEGIN { n = split(cats, a, "|"); for (i = 1; i <= n; i++) catset[a[i]] = 1 }
    $1 == "lint" && ($2 in catset) { printf "%s\t%s\t%s\n", $2, $3, $4 }
  ' "$v11_expected" | sort -u)

# F49: every LINT line the corpus emits must be accounted for in
# expected.tsv. Set-equality over a FILTERED category list cannot see a
# fixture that also fires an unfiltered category -- 2099-07-29-noflow-j fired
# missing-12b as well as its intended missing-2b, so it was not failing only
# for its stated reason and nothing said so. Compare totals, not just the
# filtered set: 45 emitted lines, 45 expected rows, 45 distinct triples.
v11_emitted=$(printf '%s\n' "$v11_ov_out" | grep -c '^LINT \[' || true)
v11_expected_n=$(grep -c '^lint	' "$v11_expected" || true)
v11_triple_n=$(printf '%s\n' "$v11_ov_triples" | grep -c . || true)

v11_bad=""
[ "$v11_ov_rc" -eq 1 ] || v11_bad="$v11_bad [override rc=$v11_ov_rc want 1]"
[ "$v11_floor" -ge 48 ] || v11_bad="$v11_bad [fixture floor $v11_floor < 48]"
[ -z "$v11_layout_missing" ] || v11_bad="$v11_bad [corpus layout(s) unpopulated:$v11_layout_missing]"
[ "$v11_tracked" -eq "$v11_on_disk" ] || v11_bad="$v11_bad [$v11_on_disk corpus state file(s) on disk but $v11_tracked tracked by git — an ignored fixture passes here and exists nowhere else]"
[ "$v11_emitted" -eq "$v11_expected_n" ] || v11_bad="$v11_bad [corpus emitted $v11_emitted LINT line(s), expected.tsv records $v11_expected_n — a fixture is firing a category nothing accounts for]"
[ "$v11_triple_n" -eq "$v11_expected_n" ] || v11_bad="$v11_bad [$v11_triple_n distinct triples vs $v11_expected_n expected rows]"
[ "$v11_ov_triples" = "$v11_expected_triples" ] || v11_bad="$v11_bad [K/L triples not set-equal to expected.tsv]"
for v11_member in \
  "$(printf 'conductor-unlinked\t2099-07-02-deliver-k9\t9')" \
  "$(printf 'conductor-unlinked\t2099-07-13-deliver-freeform\t10')" \
  "$(printf 'mutation-manifest\t2099-07-31-operate-ignore\tC4')" \
  "$(printf 'mutation-manifest\t2099-08-05-deliver-ledger-postadopt\tC1')" \
  "$(printf 'missing-2b\t2099-08-06-deliver-combined\t-')" \
  "$(printf 'conductor-unlinked\t2099-08-07-deliver-exempt-bypass\t5')" \
  "$(printf 'decision-trigger\t2099-08-10-deliver-revisit-placeholder\tD1')" \
  "$(printf 'conductor-missing\t2099-08-11-deliver-flat\t-')" \
  "$(printf 'conductor-missing\tactive-2099-08-12-deliver-prefix\t-')" \
  "$(printf 'conductor-unlinked\tfinished-2099-08-13-deliver-prefix\t5')" \
  "$(printf 'conductor-unlinked\t2099-08-14-deliver-legacyroot\t9')" \
  "$(printf 'conductor-row\t2099-08-15-deliver-pipe-raw\tCR1')" \
  "$(printf 'conductor-row\t2099-08-16-deliver-pipe-escaped\tCR1')" \
  "$(printf 'mutation-manifest\t2099-07-31-operate-ignore\tC7')" \
  "$(printf 'decision-trigger\t2099-05-30-deliver-precutoff-header\tD1')"
do
  printf '%s\n' "$v11_ov_triples" | grep -qxF "$v11_member" || v11_bad="$v11_bad [named member absent: $v11_member]"
done
printf '%s\n' "$v11_ov_triples" | grep -qxF "$(printf 'mutation-manifest\t2099-07-31-operate-ignore\tC2')" \
  && v11_bad="$v11_bad [named-absent member present: C2 (all-literal ignore paths must not fire)]"
# F48 control: the escaped-pipe fixture's CR2 carries `\|` in BOTH source and
# control and is otherwise well formed. It must stay silent — otherwise the
# width rule is just rejecting every row that mentions a pipe, and CR1's
# finding would prove nothing about column alignment.
printf '%s\n' "$v11_ov_triples" | grep -qxF "$(printf 'conductor-row\t2099-08-16-deliver-pipe-escaped\tCR2')" \
  && v11_bad="$v11_bad [named-absent member present: pipe-escaped CR2 (a correctly escaped row must not fire)]"
printf '%s\n' "$v11_ov_triples" | grep -qxF "$(printf 'mutation-manifest\t2099-07-31-operate-ignore\tC8')" \
  && v11_bad="$v11_bad [named-absent member present: operate-ignore C8 (the escaped change-ledger twin must not fire)]"
printf '%s\n' "$v11_ov_triples" | grep -q "	2099-07-27-operate-j	" \
  && v11_bad="$v11_bad [named-absent member present: missing-2b fired on OPERATE-family 2099-07-27-operate-j]"
for v11_slug in 2000-01-01-deliver-legacy 2099-05-31-deliver-prebound 2000-01-03-deliver-legacy-ledger \
  2099-08-08-deliver-revisit-trigger 2099-08-09-deliver-revisit-when; do
  printf '%s\n' "$v11_ov_triples" | grep -q "	${v11_slug}	" \
    && v11_bad="$v11_bad [pre-adoption or accepted-spelling slug $v11_slug produced a triple]"
done

# F45: two same-category triples in one file (fixture #3's CR1/CR2, #34's
# C3-C6) could have their reasons swapped and still pass a key-only
# set-equality check. Assert the actual message text too, so the gate
# proves each fired for ITS OWN stated reason.
v11_msg_check() { # $1=path-suffix (basename), $2=key, $3=expected message substring
  printf '%s\n' "$v11_ov_out" | grep -F "$1" | grep -F -- "— $2:" | grep -qF "$3" \
    || v11_bad="$v11_bad [message mismatch: $1 $2 does not contain '$3']"
}
v11_msg_check "2099-07-03-deliver-ctl.state.md" "CR1" "control restates the claim"
v11_msg_check "2099-07-03-deliver-ctl.state.md" "CR2" "empty or placeholder control"
v11_msg_check "2099-07-31-operate-ignore.state.md" "C3" "bad ignore token: spec.*"
v11_msg_check "2099-07-31-operate-ignore.state.md" "C4" "bad ignore token: status.conditions[*]"
v11_msg_check "2099-07-31-operate-ignore.state.md" "C5" "bad ignore token: spec."
v11_msg_check "2099-07-31-operate-ignore.state.md" "C6" "bad ignore token: status"
# F48: the two pipe fixtures are the same shape modulo the escape, so a
# key-only assertion would pass if both produced the same finding. Name the
# distinct reasons: the raw row is rejected on WIDTH, the escaped row parses
# and is then rejected on its genuinely empty control.
v11_msg_check "2099-08-15-deliver-pipe-raw.state.md" "CR1" "row has 8 cells, header has 7"
v11_msg_check "2099-08-16-deliver-pipe-escaped.state.md" "CR1" "empty or placeholder control"
v11_msg_check "2099-07-31-operate-ignore.state.md" "C7" "row has 8 cells, header has 7"
printf '%s\n' "$v11_no_triples" | grep -qxF "$(printf 'conductor-missing\t2099-05-31-deliver-prebound\t-')" \
  || v11_bad="$v11_bad [override-control triple absent from the no-override run]"
printf '%s\n' "$v11_ov_out" | grep -qxF 'conductor adoption date overridden: 2099-06-01' \
  || v11_bad="$v11_bad [override-visibility line absent from the override run]"
printf '%s\n' "$v11_no_out" | grep -q '^conductor adoption date overridden:' \
  && v11_bad="$v11_bad [no-override run printed an override line]"
v11_default=$(grep -oE 'CONDUCTOR_SINCE="\$\{MOZART_LINT_CONDUCTOR_SINCE:-[0-9]{4}-[0-9]{2}-[0-9]{2}\}"' "$gate_root/scripts/mozart-lint.sh" \
  | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
if [ -z "$v11_default" ] || { [ "$v11_default" != "2026-09-18" ] && [ "$(printf '%s\n%s\n' "$v11_default" "2026-09-18" | sort | head -1)" = "$v11_default" ]; }; then
  v11_bad="$v11_bad [CONDUCTOR_SINCE default '$v11_default' < 2026-09-18]"
fi
report "V11" "$([ -z "$v11_bad" ] && echo 0 || echo 1)" \
  "${v11_bad:-lint corpus: override rc=1, floor=$v11_floor across 6 layouts, $v11_emitted emitted = $v11_expected_n expected (no unaccounted category), K/L triples set-equal, named members present, override-visibility correct both ways, CONDUCTOR_SINCE default=$v11_default}"

# ---------------------------------------------------------------------------
# V12 — S3's row-required-gate table agrees with the lint constants (cut 2)
#
# Orchestration-only: parses agents/mozart.md's own table (scoped from the
# "conductor record is where your own claims become checkable" sentence to
# the next "### " heading) and compares it against
# scripts/mozart-lint.sh's CONDUCTOR_GATES_*/CONDUCTOR_FLOWS_* constants —
# so a future edit to either side that drifts from the other is caught
# mechanically, not left to a reviewer's memory of what the other file says.
# ---------------------------------------------------------------------------
v12_lint_src="$gate_root/scripts/mozart-lint.sh"
v12_const() { grep -oE "$1=\"[^\"]*\"" "$v12_lint_src" | head -1 | sed -E 's/^[^"]*"//; s/"$//'; }
CONDUCTOR_GATES_DELIVER=$(v12_const CONDUCTOR_GATES_DELIVER)
CONDUCTOR_GATES_OPERATE=$(v12_const CONDUCTOR_GATES_OPERATE)
CONDUCTOR_GATES_INCIDENT=$(v12_const CONDUCTOR_GATES_INCIDENT)
CONDUCTOR_FLOWS_DELIVER=$(v12_const CONDUCTOR_FLOWS_DELIVER)
CONDUCTOR_FLOWS_OPERATE=$(v12_const CONDUCTOR_FLOWS_OPERATE)
CONDUCTOR_FLOWS_INCIDENT=$(v12_const CONDUCTOR_FLOWS_INCIDENT)

v12_mozart_md="$gate_root/agents/STATE.md"
v12_section=$(awk '
    /The conductor record is where your own claims become checkable/ { p = 1 }
    p && /^### / && !/checkable/ { exit }
    p { print }
  ' "$v12_mozart_md")
v12_rows=$(printf '%s\n' "$v12_section" | grep -E '^\| (DELIVER|OPERATE|INCIDENT) \|')
v12_families=$(printf '%s\n' "$v12_rows" | awk -F'|' '{gsub(/ /,"",$2); print $2}' | sort -u)
v12_bad=""
[ "$(printf '%s\n' "$v12_families" | grep -c .)" -eq 3 ] || v12_bad="$v12_bad [families != 3: $v12_families]"
v12_anchor_n=$(grep -cF 'The conductor record is where your own claims become checkable' "$v12_mozart_md")
[ "$v12_anchor_n" -eq 1 ] || v12_bad="$v12_bad [anchor sentence found $v12_anchor_n times, want 1]"

v12_check_family() { # $1=family name, $2=prose row grep pattern, $3=lint keys var, $4=lint flows var
  local prow pkeys lkeys pflow_row
  prow=$(printf '%s\n' "$v12_rows" | grep -E "^\| $1 \|")
  pkeys=$(printf '%s' "$prow" | awk -F'|' '{print $4}' | grep -oE '`[^`]+`' | tr -d '`' | sed -E 's/^P<N>$/P/' | tr '\n' ' ' | sed -E 's/ +$//; s/^ +//')
  lkeys=$(eval "printf '%s' \"\$$3\"")
  if [ "$(printf '%s\n' "$pkeys" | tr ' ' '\n' | sort -u)" != "$(printf '%s\n' "$lkeys" | tr ' ' '\n' | sort -u)" ]; then
    v12_bad="$v12_bad [$1 keys differ: prose={$pkeys} lint={$lkeys}]"
  fi
  pflow=$(printf '%s' "$prow" | awk -F'|' '{print $3}' | grep -oE '`[^`]+`' | tr -d '`' | tr '\n' ' ' | sed -E 's/ +$//; s/^ +//')
  lflow=$(eval "printf '%s' \"\$$4\"")
  if [ "$(printf '%s\n' "$pflow" | tr ' ' '\n' | sort -u)" != "$(printf '%s\n' "$lflow" | tr ' ' '\n' | sort -u)" ]; then
    v12_bad="$v12_bad [$1 flow tokens differ: prose={$pflow} lint={$lflow}]"
  fi
}
v12_check_family "DELIVER" "" "CONDUCTOR_GATES_DELIVER" "CONDUCTOR_FLOWS_DELIVER"
v12_check_family "OPERATE" "" "CONDUCTOR_GATES_OPERATE" "CONDUCTOR_FLOWS_OPERATE"
v12_check_family "INCIDENT" "" "CONDUCTOR_GATES_INCIDENT" "CONDUCTOR_FLOWS_INCIDENT"

v12_deliver_row=$(printf '%s\n' "$v12_rows" | grep -E '^\| DELIVER \|')
printf '%s\n' "$v12_deliver_row" | grep -qF '`9`' || v12_bad="$v12_bad [DELIVER named member 9 absent from prose row]"
v12_operate_row=$(printf '%s\n' "$v12_rows" | grep -E '^\| OPERATE \|')
printf '%s\n' "$v12_operate_row" | grep -qF '`1:fact`' || v12_bad="$v12_bad [OPERATE named member 1:fact absent from prose row]"
v12_incident_row=$(printf '%s\n' "$v12_rows" | grep -E '^\| INCIDENT \|')
printf '%s\n' "$v12_incident_row" | grep -qF '`MITIGATE-ONLY`' || v12_bad="$v12_bad [INCIDENT named member MITIGATE-ONLY absent from prose row]"

report "V12" "$([ -z "$v12_bad" ] && echo 0 || echo 1)" \
  "${v12_bad:-S3 table agrees with lint constants: 3 families, per-family keys and flow tokens set-equal, named members present, anchor found once}"

# ---------------------------------------------------------------------------
# V10b — metrics conductor section (PD9/PD11/PD13, phase 6)
#
# Runs the metrics-conductor and metrics-vacuity cases against $gate_root's
# OWN mozart-metrics.sh, corpus resolved from this script's own repo (PD8).
# ---------------------------------------------------------------------------
v10b_script_repo=$(dirname "$(dirname "$gatefile")")
v10b_bad=""

v10b_run_case() { # $1=case name, $2=floor, extra named members follow as $3..
  local case="$1" floor="$2" corpus expected out rc missing member
  corpus="$v10b_script_repo/tests/fixtures/conductor/$case"
  expected="$corpus/expected.tsv"
  local n
  n=$(grep -c "$(printf '^metrics\t')" "$expected" 2>/dev/null || echo 0)
  [ "$n" -ge "$floor" ] || v10b_bad="$v10b_bad [$case expected-file floor $n < $floor]"
  out=$(bash "$gate_root/scripts/mozart-metrics.sh" "$corpus" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || v10b_bad="$v10b_bad [$case exit=$rc want 0]"
  missing=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\n' "$out" | grep -qxF "$line" || missing="$missing [$line]"
  done < <(cut -f2 "$expected")
  [ -z "$missing" ] || v10b_bad="$v10b_bad [$case expected line(s) absent:$missing]"
  shift 2
  for member in "$@"; do
    printf '%s\n' "$out" | grep -qxF "$member" || v10b_bad="$v10b_bad [$case named member absent: $member]"
  done
  if [ "$case" = "metrics-conductor" ]; then
    lens_line=$(printf '%s\n' "$out" | grep '^  rejected by lens:')
    for tok in "bob=1/1" "tessa=1/1" "ruby=1/1"; do
      printf '%s' "$lens_line" | grep -qF "$tok" || v10b_bad="$v10b_bad [metrics-conductor rejected-by-lens token absent: $tok]"
    done
    printf '%s' "$lens_line" | grep -q 'xander=' && v10b_bad="$v10b_bad [metrics-conductor reversed lens xander= present in rejected-by-lens line]"
  fi
}

v10b_run_case "metrics-conductor" 6 \
  "Wrong-override rate: 1/3 rejected findings later reversed (33%)" \
  "  rejected (judgment): 1 of 3"
v10b_run_case "metrics-vacuity" 1 \
  "Wrong-override rate: n/a (no rejected findings in campaigns with a conductor record)"

report "V10b" "$([ -z "$v10b_bad" ] && echo 0 || echo 1)" \
  "${v10b_bad:-metrics-conductor and metrics-vacuity: exit=0, expected lines present, rejected-by-lens tokens correct, named members present}"

# ---------------------------------------------------------------------------
# V13 — cross-file conductor-prose parity, section-scoped (phase 7)
#
# Proves specific terms landed in the SPECIFIC section named for them, not
# just somewhere in the file (a whole-file grep can't tell "Decisions log
# mentioned in the artifact list" from "mentioned once, in an unrelated
# aside"). v13_scoped extracts the named section (anchor line to the next
# heading at or above its own level) and counts term occurrences in it.
# ---------------------------------------------------------------------------
v13_scoped() { # $1=file $2=heading-anchor(literal prefix) $3=stop-regex $4=term -> match count
  awk -v anchor="$2" -v stoppat="$3" -v term="$4" '
    index($0, anchor) == 1 { p = 1; next }
    p && $0 ~ stoppat { exit }
    p && index($0, term) > 0 { c++ }
    END { print c + 0 }
  ' "$1" 2>/dev/null
  [ -f "$1" ] || echo 0
}
L2='^## |^# '
L3='^### |^## |^# '

v13_bad=""
v13_sites=0
v13_named_hank_apply=0

v13_check() { # $1=file $2=anchor $3=stoplevel $4=term $5=label
  local n
  n=$(v13_scoped "$1" "$2" "$3" "$4")
  v13_sites=$((v13_sites + 1))
  if [ "$n" -lt 1 ]; then
    v13_bad="$v13_bad [absent: $5]"
  fi
  if [ "$2" = "### 4. Apply" ] && [ "$1" = "$gate_root/agents/hank.md" ]; then
    [ "$n" -ge 1 ] && v13_named_hank_apply=1
  fi
}

# (a) decisions.md across the five artifact-list sites
v13_check "$gate_root/agents/mozart.md" "### Per-campaign artifacts" "$L3" "decisions.md" "mozart Per-campaign artifacts / decisions.md"
v13_check "$gate_root/agents/STATE.md" "### Directory convention" "$L3" "decisions.md" "STATE Directory convention / decisions.md"
v13_check "$gate_root/agents/PIPELINE.md" "## Output paths" "$L2" "decisions.md" "PIPELINE Output paths / decisions.md"
v13_check "$gate_root/commands/mozart.md" "### 6. Maintain all artifacts" "$L3" "decisions.md" "commands 6. Maintain all artifacts / decisions.md"
v13_check "$gate_root/README.md" "## What's in the box" "$L2" "decisions.md" "README What's in the box / decisions.md"

# (d) manifest across the nine OPERATE/INCIDENT sections
v13_check "$gate_root/agents/OPERATE.md" "### 3. Change plan (otto)" "$L3" "manifest" "OPERATE Change plan / manifest"
v13_check "$gate_root/agents/OPERATE.md" "### 5. Apply (hank)" "$L3" "manifest" "OPERATE Apply (hank) / manifest"
v13_check "$gate_root/agents/OPERATE.md" "### Operate-mode rules" "$L3" "manifest" "OPERATE Operate-mode rules / manifest"
v13_check "$gate_root/agents/INCIDENT.md" "### Incident-mode rules" "$L3" "manifest" "INCIDENT Incident-mode rules / manifest"
v13_check "$gate_root/agents/hank.md" "### 4. Apply" "$L3" "manifest" "hank 4. Apply / manifest"
v13_check "$gate_root/agents/hank.md" "## Under a declared INCIDENT" "$L2" "manifest" "hank Under a declared INCIDENT / manifest"
v13_check "$gate_root/agents/otto.md" "## Where you fit" "$L2" "manifest" "otto Where you fit / manifest"
v13_check "$gate_root/agents/PIPELINE.md" "## OPERATE pipeline" "$L2" "manifest" "PIPELINE OPERATE pipeline / manifest"
v13_check "$gate_root/agents/PIPELINE.md" "## INCIDENT pipeline" "$L2" "manifest" "PIPELINE INCIDENT pipeline / manifest"

# (e) both sides across three pin-related sections
v13_check "$gate_root/agents/OPERATE.md" "### 1. Intake + context pin" "$L3" "both sides" "OPERATE Intake + context pin / both sides"
v13_check "$gate_root/agents/OPERATE.md" "### Operate-mode rules" "$L3" "both sides" "OPERATE Operate-mode rules / both sides"
v13_check "$gate_root/agents/PIPELINE.md" "## OPERATE pipeline" "$L2" "both sides" "PIPELINE OPERATE pipeline / both sides"

# (f) the dick heading itself, exactly once
v13_dick_n=$(grep -cF '### Adjudicating a dispute' "$gate_root/agents/dick.md")
v13_sites=$((v13_sites + 1))
[ "$v13_dick_n" -eq 1 ] || v13_bad="$v13_bad [dick heading 'Adjudicating a dispute' count=$v13_dick_n, want 1]"

# (b) the promoted-note phrase must be gone from mozart.md entirely
# PATTERN 2 / D4 RE-SCOPE, same reasoning as V1_absence: the promoted-then-deleted
# phrase belonged to the State-persistence text, which left agents/mozart.md in this
# commit. Scoped to the glob so the assertion still has the text in its population.
v13_running_log_files=$(ls "$gate_root"/agents/*.md 2>/dev/null | grep -c .)
v13_running_log_n=$(grep -rlF 'running log of decisions' "$gate_root"/agents/*.md 2>/dev/null | grep -c .)
[ "$v13_running_log_files" -ge 20 ] || v13_running_log_n=$((v13_running_log_n + 1))
v13_sites=$((v13_sites + 1))
[ "$v13_running_log_n" -eq 0 ] || v13_bad="$v13_bad ['running log of decisions' still present in $v13_running_log_n of $v13_running_log_files agents/*.md file(s)]"

# (c) the deleted field note's title must be gone from every persona
v13_sites=$((v13_sites + 1))
v13_deleted_note_n=$(grep -rlF 'An unattended run needs a decision log' "$gate_root"/agents/*.md 2>/dev/null | grep -c .)
[ "$v13_deleted_note_n" -eq 0 ] || v13_bad="$v13_bad [deleted field note title still present in $v13_deleted_note_n agents/*.md file(s)]"

[ "$v13_sites" -ge 20 ] || v13_bad="$v13_bad [scoped-site population $v13_sites < 20]"
[ "$v13_named_hank_apply" -eq 1 ] || v13_bad="$v13_bad [named member absent: hank ### 4. Apply / manifest]"

report "V13" "$([ -z "$v13_bad" ] && echo 0 || echo 1)" \
  "${v13_bad:-$v13_sites scoped sites checked, named member (hank ### 4. Apply) present, both zero-count checks and the dick-heading-once check hold}"

# ---------------------------------------------------------------------------
# V14 — campaign scripts survive a path containing a space (F50)
#
# mozart-metrics.sh held its roots and its file list in whitespace-delimited
# STRINGS, so a checkout under "~/Google Drive/..." split into two
# nonexistent roots and reported "no state files"; a state FILENAME with a
# space was handed to awk as two truncated paths. mozart-lint.sh had the same
# defect in one place only — Check F word-split an unquoted $(find ...), so a
# stale campaign under a spaced path went unreported.
#
# The corpus is BUILT here rather than committed: the point is the path, and a
# committed directory with a space in its name would have to be mirrored
# byte-for-byte into the ports' fixture trees for no added signal. Both
# dimensions codex verified are exercised — a spaced ROOT and a spaced
# FILENAME — and the lint arm backdates one file so Check F actually has
# something to find rather than passing on an empty sweep.
# ---------------------------------------------------------------------------
v14_bad=""
v14_tmp=$(mktemp -d)
v14_root="$v14_tmp/dir with a space"
v14_act="$v14_root/.mozart/plans/active"
mkdir -p "$v14_act"
v14_spaced="$v14_act/2099-02-05-deliver-spaced name.state.md"
cat > "$v14_spaced" <<'V14_EOF'
# Pipeline state: 2099-02-05-deliver-spaced name

**Last updated**: 2026-09-17T00:00Z
**Status**: in-progress
**Flow**: FULL
**Tier**: STANDARD
**Context**: BROWNFIELD
**Mode**: AUTONOMOUS

## Conductor record
| id | kind | claim | links | source | control (command -> observed) | written-to |
|----|------|-------|-------|--------|-------------------------------|------------|
| CR1 | check | the spaced path is discoverable | - | `ls` 2026-09-17T00:00Z | `ls` -> the file | n/a |
| CR2 | fact | the upstream API is unversioned | - | doc unverified |  | n/a |
V14_EOF
cat > "$v14_act/2099-02-06-deliver-plain.state.md" <<'V14_EOF'
# Pipeline state: 2099-02-06-deliver-plain

**Last updated**: 2026-09-17T00:00Z
**Status**: in-progress
**Flow**: FULL
**Tier**: STANDARD
**Context**: BROWNFIELD
**Mode**: AUTONOMOUS

## Conductor record
- exempt: pre-adoption persona
V14_EOF
# Population floor + named member: without these the two runs below could
# both "pass" against an empty corpus that proves nothing about spaces.
v14_floor=$(find "$v14_root" -name '*.state.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$v14_floor" -ge 2 ] || v14_bad="$v14_bad [spaced-path corpus has $v14_floor state file(s), floor 2]"
[ -f "$v14_spaced" ] || v14_bad="$v14_bad [named member absent: the spaced FILENAME fixture was not created]"

v14_m_out=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v14_root" 2>&1)
v14_m_rc=$?
[ "$v14_m_rc" -eq 0 ] || v14_bad="$v14_bad [metrics exit=$v14_m_rc want 0 under a spaced root]"
printf '%s\n' "$v14_m_out" | grep -q 'nothing to aggregate' \
  && v14_bad="$v14_bad [metrics reported 'nothing to aggregate' under a spaced root]"
# The spaced FILE must reach the tally, not merely fail to crash the run: its
# two conductor rows are the ONLY rows in this corpus, so these counts are
# non-zero if and only if awk opened the spaced path intact.
v14_m_member='Conductor rows: check=1 adjudication=0 fact=1'
printf '%s\n' "$v14_m_out" | grep -qxF "$v14_m_member" \
  || v14_bad="$v14_bad [named member absent from metrics output: $v14_m_member]"

# Check F needs a file older than STALE_DAYS to have anything to report.
touch -t 200001010000 "$v14_spaced" 2>/dev/null
v14_l_out=$(bash "$gate_root/scripts/mozart-lint.sh" "$v14_root" 2>&1)
v14_l_rc=$?
[ "$v14_l_rc" -eq 1 ] || v14_bad="$v14_bad [lint exit=$v14_l_rc want 1 under a spaced root]"
printf '%s\n' "$v14_l_out" | grep -F 'LINT [stale-active]' | grep -qF 'deliver-spaced name.state.md' \
  || v14_bad="$v14_bad [named member absent: no stale-active finding naming the spaced filename]"
rm -rf "$v14_tmp"
report "V14" "$([ -z "$v14_bad" ] && echo 0 || echo 1)" \
  "${v14_bad:-spaced root + spaced filename: metrics exit=0 and counts the rows in the spaced file, lint exit=1 and names it in a stale-active finding, floor=$v14_floor}"

# ---------------------------------------------------------------------------
# V15 — every frozen parity snippet still matches its orchestration target
#       (F58)
#
# The canonical snippets under tests/parity/snippets/ are the frozen text that
# check-field-note-parity.py's `bullets` mode (A13) asserts appears exactly
# once at each of four ports. A13 cannot be a CI gate — no single repo's CI can
# see the other three checkouts, and report() has no SKIP — so it is a manual
# pre-merge run, and a snippet can go stale between runs. It did: F48 reworded
# the conductor-record paragraph in all four repos and S3.txt kept the old
# sentence, so A13 read 0/4 for a snippet that had been 4/4.
#
# The CROSS-PORT half still needs four checkouts. The ORCHESTRATION half does
# not: a snippet that no longer matches THIS repo's own target file is stale by
# definition, and that is exactly the divergence a reword creates at the moment
# it is made. Gating it here turns "remember to run A13" into "the edit that
# strands a snippet fails the suite it already runs".
#
# Vacuity controls: the registry below must account for every file in the
# snippets directory (an unregistered snippet fails rather than being skipped),
# the row count carries a floor, and S3 — the one that actually went stale — is
# asserted by name.
# ---------------------------------------------------------------------------
v15_snipdir="$gate_root/tests/parity/snippets"
v15_registry=$(cat <<'V15_REGISTRY_EOF'
S1	agents/mozart.md
S2	agents/STATE.md
S3	agents/STATE.md
S4	agents/STATE.md
S5	agents/STATE.md
S6	agents/STATE.md
S7	agents/STATE.md
S8	agents/OPERATE.md
S9	agents/OPERATE.md
S10	agents/OPERATE.md
S11	agents/OPERATE.md
S12	agents/INCIDENT.md
S13	agents/INCIDENT.md
S14	agents/dick.md
S15	agents/hank.md
S16	agents/otto.md
S17	agents/jackson.md
S18	agents/STATE.md
S19	agents/hank.md
S21	agents/hank.md
M2	agents/harry.md
M4	agents/mozart.md
M7	agents/harry.md
MP	agents/mozart.md
JP	agents/jackson.md
V15_REGISTRY_EOF
)

# Count occurrences of a whole snippet FILE inside a target FILE. Pure awk (no
# python3, no perl) so the suite keeps running unchanged under mawk in A10's
# bare container. RS is a control char the corpus never contains, so the target
# arrives as one record; the snippet is read line-by-line and trimmed, which is
# what `bullets` compares with .strip().
v15_occurrences() { # $1 = snippet file, $2 = target file
  awk -v snipf="$1" '
    BEGIN {
      RS = "\034"; c = 0
      while ((getline l < snipf) > 0) { needle = needle (c++ ? "\n" : "") l }
      close(snipf)
      gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", needle)
    }
    {
      if (needle == "") { print -1; exit }
      hay = $0; cnt = 0
      pos = index(hay, needle)
      while (pos > 0) { cnt++; hay = substr(hay, pos + length(needle)); pos = index(hay, needle) }
      print cnt
      exit
    }
  ' "$2"
}

v15_bad=""
v15_rows=$(printf '%s\n' "$v15_registry" | grep -c .)
v15_files=$(find "$v15_snipdir" -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')

# F63: completeness used to be a COUNT comparison (rows == files) plus a
# per-row existence test. Both hold when a row is duplicated and another is
# dropped — the count is preserved, every registered file still exists, and the
# dropped snippet is simply never checked. That is a vacuity path inside the
# check that was added to close a vacuity path, so compare the SETS instead,
# in both directions, and reject duplicate keys explicitly.
#
# Set-equality plus no-duplicates implies rows == files, so the old count test
# is not kept alongside: it would add a second, weaker message for a condition
# already named precisely below.
v15_keys=$(printf '%s\n' "$v15_registry" | awk -F'\t' 'NF { print $1 }' | sort)
v15_stems=$(find "$v15_snipdir" -name '*.txt' 2>/dev/null | sed 's#.*/##; s#\.txt$##' | sort)
v15_dupes=$(printf '%s\n' "$v15_keys" | uniq -d | tr '\n' ' ')
v15_only_registry=$(comm -23 <(printf '%s\n' "$v15_keys" | uniq) <(printf '%s\n' "$v15_stems") | tr '\n' ' ')
v15_only_files=$(comm -13 <(printf '%s\n' "$v15_keys" | uniq) <(printf '%s\n' "$v15_stems") | tr '\n' ' ')

[ "$v15_rows" -ge 25 ] || v15_bad="$v15_bad [registry has $v15_rows row(s), floor 25]"
# Braces are load-bearing on ${v15_dupes}: the message continues with an
# em-dash, and bash reads the multibyte character as part of the variable NAME
# without them, so under `set -u` the gate aborts with "unbound variable" on
# the very path it exists to report. Caught by control 1 producing no verdict
# at all rather than a FAIL -- a check that cannot print its own finding is
# indistinguishable from one that has nothing to report.
[ -z "$v15_dupes" ] || v15_bad="${v15_bad} [duplicate registry key(s): ${v15_dupes}— a duplicate preserves the row count while some other snippet goes unchecked]"
[ -z "$v15_only_registry" ] || v15_bad="${v15_bad} [registered with no snippet file: ${v15_only_registry}]"
[ -z "$v15_only_files" ] || v15_bad="${v15_bad} [snippet file(s) with no registry row, so never checked: ${v15_only_files}]"
printf '%s\n' "$v15_registry" | grep -qxF "$(printf 'S3\tagents/STATE.md')" \
  || v15_bad="$v15_bad [named member absent from the registry: S3 -> agents/STATE.md]"

v15_checked=0
while IFS=$'\t' read -r v15_snip v15_target; do
  [ -n "$v15_snip" ] || continue
  if [ ! -f "$v15_snipdir/$v15_snip.txt" ]; then
    v15_bad="$v15_bad [registered snippet file missing: $v15_snip.txt]"
    continue
  fi
  v15_n=$(v15_occurrences "$v15_snipdir/$v15_snip.txt" "$gate_root/$v15_target")
  v15_checked=$((v15_checked + 1))
  [ "$v15_n" = "1" ] || v15_bad="$v15_bad [$v15_snip.txt occurs $v15_n time(s) in $v15_target, want exactly 1]"
done < <(printf '%s\n' "$v15_registry")
[ "$v15_checked" -eq "$v15_rows" ] || v15_bad="$v15_bad [checked $v15_checked of $v15_rows registered snippets]"
report "V15" "$([ -z "$v15_bad" ] && echo 0 || echo 1)" \
  "${v15_bad:-$v15_checked frozen snippet(s) each occur exactly once in their orchestration target; registry key set == the $v15_files file(s) on disk, no duplicate keys; named member S3 present}"

# ---------------------------------------------------------------------------
# V16 — per-file size ceilings for this repo's personas (F66)
#
# These are the plan's A7 budgets. A7 was written as a hand-run command and
# wired into nothing, so three reconciliation rounds of green suites ran while
# agents/mozart.md sat over its ceiling: grepping this file for the ceiling
# returned 0 hits. A budget nobody runs is not a budget.
#
# mozart.md's ceiling is 269,500 per log D26, which supersedes D14's 269,000.
# The history is worth keeping in view, because what moved was the number and
# not the discipline: phase 7 landed mozart.md at 268,994 — six bytes under
# D14's ceiling — so the first real fix after it (F48, +399 across two
# paragraphs, 220 of them inside the byte-checked S3 snippet) could not fit.
# Measured at the time: everything the campaign added outside frozen snippet
# text was 2,325 bytes of rule prose, so closing a 299-byte gap meant deleting
# a mechanism. D26 moved the number rather than the content. The other three
# ceilings are unchanged, and all three files still sit inside them.
#
# SCOPE: orchestration's own files only. The ports enforce their own ceilings
# with their own tooling — copilot via scripts/check_agents.py against the
# table in its check.yml, local via the 30,000-char cap on MANIFEST.jsonc's
# derived_chars — and this gate cannot see their checkouts. It says nothing
# about them; do not read a PASS here as four-repo coverage.
#
# Ceilings are per-file and named, not a repo-wide total: the failure has to
# say WHICH file and by how much, or the next person is back to bisecting
# `wc -c`. Vacuity controls: a floor on how many files are tracked, every
# tracked file must exist (a vanished file fails rather than being skipped),
# and agents/mozart.md is asserted present in the table by name.
# ---------------------------------------------------------------------------
v16_budgets=$(cat <<'V16_BUDGETS_EOF'
agents/mozart.md	269500
agents/AUDIT.md	4700
agents/CONTEXT-BUDGET.md	1800
agents/DIAGNOSE.md	5500
agents/EVAL.md	6300
agents/OPERATE.md	14600
agents/INCIDENT.md	11700
agents/STATE.md	53500
agents/INTAKE.md	19900
agents/COUNTERPOINT.md	5400
agents/hank.md	22300
agents/dick.md	23490
agents/otto.md	21700
V16_BUDGETS_EOF
)

v16_bad=""
v16_rows=$(printf '%s\n' "$v16_budgets" | grep -c .)
[ "$v16_rows" -ge 4 ] || v16_bad="$v16_bad [budget table has $v16_rows row(s), floor 4]"
printf '%s\n' "$v16_budgets" | grep -qxF "$(printf 'agents/mozart.md\t269500')" \
  || v16_bad="$v16_bad [named member absent from the budget table: agents/mozart.md 269500]"

v16_checked=0
v16_sizes=""
while IFS=$'\t' read -r v16_file v16_limit; do
  [ -n "$v16_file" ] || continue
  if [ ! -f "$gate_root/$v16_file" ]; then
    v16_bad="$v16_bad [tracked file missing: $v16_file]"
    continue
  fi
  v16_n=$(wc -c < "$gate_root/$v16_file" | tr -d ' ')
  v16_checked=$((v16_checked + 1))
  v16_sizes="$v16_sizes $v16_file=$v16_n/$v16_limit"
  if [ "$v16_n" -gt "$v16_limit" ]; then
    v16_bad="$v16_bad [$v16_file is $v16_n bytes, over its $v16_limit ceiling by $((v16_n - v16_limit))]"
  fi
done < <(printf '%s\n' "$v16_budgets")
[ "$v16_checked" -eq "$v16_rows" ] || v16_bad="$v16_bad [checked $v16_checked of $v16_rows tracked file(s)]"
report "V16" "$([ -z "$v16_bad" ] && echo 0 || echo 1)" \
  "${v16_bad:-$v16_checked orchestration file(s) within their per-file ceilings:$v16_sizes}"

# ---------------------------------------------------------------------------
# V17 - the carve conservation gate (2026-09-19-deliver-mozart-md-carve).
#
# Two gates, deliberately separate:
#
#   V17_carve_selftest  the gate's own 11-mutation self-test. Runs on a synthetic
#                       mktemp fixture and never reads the repo tree, so it is
#                       valid from Phase 1 onward - before any destination file
#                       exists. A run reporting fewer than 11 mutations FAILS: the
#                       floor is what stops a stale implementation from satisfying
#                       this gate while C3 inverse and C3c go untested (F36/F43).
#
#   V17_carve_phase     conservation at the ordinal in tests/carve/PHASE, asserting
#                       EXACTLY that every mapped range with ordinal <= it is in its
#                       destination AND every range above it is still in
#                       agents/mozart.md. Exact in both directions, so
#                       under-delivering a phase fails as loudly as over-delivering.
#                       The ordinal lives in a file a reviewer reads and each phase
#                       commit bumps - not a constant nobody re-reads (F26/F41).
#
# python3 missing is a FAIL, never a skip. A gate that quietly disappears when its
# interpreter is absent is the vacuity case this suite exists to remove.
v17_script="$gate_root/scripts/check-carve-conservation.py"
if ! command -v python3 >/dev/null 2>&1; then
  report "V17_carve_selftest" 1 "python3 not found - the conservation gate cannot run (FAIL, not skip)"
  report "V17_carve_phase" 1 "python3 not found - the conservation gate cannot run (FAIL, not skip)"
elif [ ! -f "$v17_script" ]; then
  report "V17_carve_selftest" 1 "scripts/check-carve-conservation.py is missing"
  report "V17_carve_phase" 1 "scripts/check-carve-conservation.py is missing"
else
  v17_st_out=$(python3 "$v17_script" --self-test --quiet 2>&1); v17_st_rc=$?
  v17_st_n=$(printf '%s\n' "$v17_st_out" | sed -n 's/.*carve_selftest *\([0-9]*\) of \([0-9]*\) mutations.*/\1 \2/p')
  v17_st_caught=${v17_st_n%% *}; v17_st_total=${v17_st_n##* }
  if [ "$v17_st_rc" -eq 0 ] && [ "${v17_st_caught:-0}" -ge 11 ] && [ "${v17_st_caught:-0}" = "${v17_st_total:-0}" ]; then
    report "V17_carve_selftest" 0 "$v17_st_caught of $v17_st_total mutations rejected, each by its named control (floor 11); positive control green"
  else
    report "V17_carve_selftest" 1 "self-test rc=$v17_st_rc caught=${v17_st_caught:-?}/${v17_st_total:-?} (floor 11): $(printf '%s' "$v17_st_out" | tail -3 | tr '\n' ' ')"
  fi

  v17_phase_file="$gate_root/tests/carve/PHASE"
  if [ ! -f "$v17_phase_file" ]; then
    report "V17_carve_phase" 1 "tests/carve/PHASE is missing - the campaign ordinal is unpinned"
  else
    v17_ord=$(tr -d ' \n' < "$v17_phase_file")
    v17_out=$(python3 "$v17_script" --phase "$v17_ord" --quiet 2>&1); v17_rc=$?
    if [ "$v17_rc" -eq 0 ]; then
      report "V17_carve_phase" 0 "$(printf '%s' "$v17_out" | sed -n 's/^PASS  carve_conservation *//p')"
    else
      report "V17_carve_phase" 1 "ordinal $v17_ord: $(printf '%s' "$v17_out" | grep -v carve_selftest | tail -4 | tr '\n' ' ')"
    fi
  fi
fi

echo
if [ "$gate_fail" -eq 0 ]; then
  echo "ALL GATES PASS"
  exit 0
fi
echo "$gate_fail GATE(S) FAILED"
exit 1
