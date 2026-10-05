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
# The template is agents/TEMPLATE-STATE.md (phase 3 of 2026-10-03-deliver-eval-
# efficiency-fixes moved it out of agents/STATE.md). A missing template yields an
# empty list, and the floors below turn that into a FAIL, not a quiet pass.
v1_fields=$(awk '/^\*\*Last updated\*\*/{f=1} f && /^\*\*[A-Z]/{gsub(/^\*\*/,"");sub(/\*\*.*/,"");print} f && /^## Tickets/{exit}' \
  agents/TEMPLATE-STATE.md | sort -u)
v1_alt=$(printf '%s\n' "$v1_fields" | paste -sd'|' -)

# Control on the derivation itself. Every other derived scope in this file has
# one - V0b_derivation's floor, V4_population's pinned 18, V4c_shapes by name,
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
v1_enum=$(grep -m1 -E '^\*\*Status\*\*: ' agents/TEMPLATE-STATE.md | sed -E 's/^\*\*Status\*\*: //; s/ *\| */ /g')
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

# UNION, because this population SPLITS across destinations (F9 said retarget only
# V2_sit; it did not say the three clauses land in one file). Measured at the 1c
# baseline: 'Reading stdout...' is PRE 132 and 'escalate to user with the codex
# stdout...' is PRE 127 — both inside `## Codex availability and use`, which D9 keeps
# INLINE WHOLE — while 'escalate to the user with the stdout transcript...' is PRE
# 1340, which carves to agents/DELIVER.md. Scoping to either file alone loses a
# clause and drops the count below the floor of 3.
v2_sit_scope="agents/mozart.md agents/DELIVER.md"
v2_sit_files=$(ls $v2_sit_scope 2>/dev/null | grep -c .)
v2_sit=$(grep -hcF 'Reading stdout instead of the target file' $v2_sit_scope 2>/dev/null | paste -sd+ - | bc)
v2_sit=$((v2_sit + $(grep -hcF 'escalate to user with the codex stdout as evidence' $v2_sit_scope 2>/dev/null | paste -sd+ - | bc)))
v2_sit=$((v2_sit + $(grep -hcF 'escalate to the user with the stdout transcript as evidence' $v2_sit_scope 2>/dev/null | paste -sd+ - | bc)))
[ "$v2_sit_files" -eq 2 ] || v2_sit=0
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
push_range_value=$(grep -m1 -oE 'PUSH_RANGE="[^"]*"' <<<"$cmdlines" | sed -E 's/^PUSH_RANGE="//; s/"$//')
push_since_value=$(grep -m1 -oE 'PUSH_SINCE="[^"]*"' <<<"$cmdlines" | sed -E 's/^PUSH_SINCE="//; s/"$//')
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
v3_check_anchors agents/DELIVER.md "$v3_ams" "$v3_ame" mozart-per-phase-gate
report "V3_region_anchors" "$([ -z "$v3_anchors_bad" ] && echo 0 || echo 1)" \
  "${v3_anchors_bad:-all 3 region anchor pairs resolve; no region falls back to EOF}"

v3_step1=$(v3_region agents/scott.md  "$v3_a1s" "$v3_a1e")
v3_step7=$(v3_region agents/scott.md  "$v3_a7s" "$v3_a7e")
v3_mozgate=$(v3_region agents/DELIVER.md "$v3_ams" "$v3_ame")

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
push_count_value=$(grep -m1 -oE 'PUSH_COUNT=[$][(][^)]*[)]' <<<"$cmdlines")
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
report "V4_population" "$(eq "$v4_n" 18)" "specialists derived from the roster=$v4_n (want 18)"

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
  grep -qx "$want" <<<"$v4c_shapes" || v4c_missing="$v4c_missing $want"
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
      grep -qx "$pp" <<<"$v4c_shapes" || printf '%s ' "$pp"
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
# Population: v4_roster, UNMODIFIED. mozart IS one of the 18 (agents/README.md
# :15; V4_population pins 18) - hand-appending it here would be exactly the
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
  grep -qE "$v7_spawn_pat" <<<"$v7_fxline" || v7_spawnctl_bad="$v7_spawnctl_bad [not matched: $v7_fxline]"
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
  grep -qiE "(^|[^A-Za-z])${ag}[^A-Za-z]" <<<"$v7_claimlines_pad" || continue
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
# PATTERN 2 / D4 RE-SCOPE. Was `^agents/mozart\.md:` — a path literal. The control's
# intent is "mozart's OWN text does the binding, regardless of what any persona's own
# file says", and after the carve mozart's own text is the persona PLUS the 13 manual
# files. Measured: harry's claim line is at PRE 370, which moved to agents/WORKTREES.md,
# so the mozart.md-only scope reported harry=0 and the control failed.
#
# A GLOB WOULD BE WRONG HERE, and this is the one place in the campaign where that is
# true. `agents/*.md` would pull in harry.md, valerie.md and every other persona —
# exactly the population this control excludes by construction. So the manual set is
# enumerated literally, and a floor guards the enumeration: if a name is mistyped the
# alternation silently narrows, which is the failure mode a literal list has and a
# glob does not.
v7_manual_re='^agents/(mozart|AUDIT|CONTEXT-BUDGET|COUNTERPOINT|DELIVER|DIAGNOSE|EVAL|FLOWS|INCIDENT|INTAKE|OPERATE|STATE|TICKETS|WORKTREES)\.md:'
v7_manual_files=$(ls agents/*.md 2>/dev/null | grep -cE '^agents/(mozart|AUDIT|CONTEXT-BUDGET|COUNTERPOINT|DELIVER|DIAGNOSE|EVAL|FLOWS|INCIDENT|INTAKE|OPERATE|STATE|TICKETS|WORKTREES)\.md$')
v7_mzclaims_pad=$(printf '%s\n' "$v7_claimlines_pad" | grep -E "$v7_manual_re")
v7_mzharry=$(grep -qiE "(^|[^A-Za-z])harry[^A-Za-z]" <<<"$v7_mzclaims_pad" && echo 1 || echo 0)
v7_mzvalerie=$(grep -qiE "(^|[^A-Za-z])valerie[^A-Za-z]" <<<"$v7_mzclaims_pad" && echo 1 || echo 0)
v7_mzsarah=$(grep -qiE "(^|[^A-Za-z])sarah[^A-Za-z]" <<<"$v7_mzclaims_pad" && echo 1 || echo 0)
v7_claimn=$(printf '%s\n' "$v7_claimants" | tr ' ' '\n' | grep -c .)
if [ "$v7_claimn" -ge 5 ] && [ "$v7_manual_files" -ge 8 ] && [ "$v7_mzharry" = 1 ] && [ "$v7_mzvalerie" = 1 ] && [ "$v7_mzsarah" = 1 ]; then
  v7_claimctl=0
else
  v7_claimctl=1
fi
report "V7_claim_control" "$v7_claimctl" \
  "claimants derived=$v7_claimn (floor 5); mozart's OWN text (persona + $v7_manual_files manual file(s), floor 8) separately binds harry/valerie/sarah=$v7_mzharry/$v7_mzvalerie/$v7_mzsarah (want 1 each - proves the population reaches mozart's own text independent of any persona's own file)"

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

# P2 - the "## Stage progress" template. It lives in agents/TEMPLATE-STATE.md since
# phase 3 of 2026-10-03-deliver-eval-efficiency-fixes; agents/STATE.md no longer
# carries a skeleton, and reading it would yield an empty list that V8 reports as a
# mismatch (an empty population is a FAIL here, never a pass).
v8_p2=$(awk '/^## Stage progress/{s=1;next} s&&/^## /{exit} s' agents/TEMPLATE-STATE.md \
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

# P5 - the "### <N>." stage-heading bodies, scoped to the DELIVER section so
# OPERATE's and INCIDENT's own "### 2."/"### 3." don't pollute it.
#
# THIS POPULATION SPLITS ACROSS TWO DESTINATIONS, and it is structural rather
# than incidental: D-F carves `### 1. Intake` to agents/INTAKE.md and leaves
# stages 2..13 in agents/DELIVER.md. Scoping to DELIVER.md alone yields
# [2 2b 3 ... 13] against a reference of [1 2 2b 3 ... 13] and FAILS on the
# missing stage 1 - measured, not predicted. P5 is therefore the ORDERED
# CONCATENATION of INTAKE.md's numeric stage keys and DELIVER.md's.
#
# INTAKE.md needs no section anchor: its only numeric "### <N>." heading is
# `### 1. Intake`. Its other ### headings (Passthrough vs. orchestrate, and the
# rest) are non-numeric and cannot match, and the carved intake body's
# pre-flight gates are #### and cannot match either.
v8_p5_intake=$(grep -oE '^### [0-9]+[a-z]?\.' agents/INTAKE.md \
  | grep -oE '[0-9]+[a-z]?' | paste -sd' ' -)
v8_p5_deliver=$(awk '/^## DELIVER pipeline/{s=1;next} s&&/^## /{exit} s' agents/DELIVER.md \
  | grep -oE '^### [0-9]+[a-z]?\.' | grep -oE '[0-9]+[a-z]?' | paste -sd' ' -)
v8_p5=$(printf '%s %s' "$v8_p5_intake" "$v8_p5_deliver" | sed 's/^ *//; s/ *$//')
# Population control: BOTH halves must contribute, or a silently-empty half
# would let the other half alone define the answer.
v8_p5_halves=0
[ -n "$v8_p5_intake" ] && v8_p5_halves=$((v8_p5_halves + 1))
[ -n "$v8_p5_deliver" ] && v8_p5_halves=$((v8_p5_halves + 1))
[ "$v8_p5_halves" -eq 2 ] || v8_p5="INCOMPLETE($v8_p5_halves/2):$v8_p5"

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
grep -qxF "$v10a_member" <<<"$v10a_out" || v10a_bad="$v10a_bad [named member absent: $v10a_member]"
v10a_missing=""
while IFS= read -r v10a_line; do
  [ -n "$v10a_line" ] || continue
  grep -qxF "$v10a_line" <<<"$v10a_out" || v10a_missing="$v10a_missing [$v10a_line]"
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
# DELIVER-family gating is fixed), plus split-layout (Check M, phase 2b) and
# the two older categories the split fixtures exercise: stranded-artifacts
# (Check H, a ledger left behind in active/) and stale-paths (Check G, a Paths
# block that still names active/).
# ---------------------------------------------------------------------------
v11_script_repo=$(dirname "$(dirname "$gatefile")")
v11_corpus="$v11_script_repo/tests/fixtures/conductor/lint"
v11_expected="$v11_corpus/expected.tsv"
v11_cats='conductor-missing|conductor-unlinked|conductor-row|conductor-reference|decision-trigger|mutation-manifest|missing-2b|split-layout|stranded-artifacts|stale-paths|escape-unrecorded'
v11_bad=""
# The awk on this machine splits strings by byte: a lone byte of a multibyte
# character tested against a bracket expression aborts it ("towc: multibyte
# conversion failure") in a UTF-8 locale and nowhere else. Lint, metrics and the
# library are therefore run here under a UTF-8 locale the machine is checked to
# have (a missing one fails, it does not skip), and once under C. A multibyte
# fixture run under whatever locale the caller exported passes by accident.
# D12: the corpus predates the lens-record date, so every corpus run pins it after the last 2099-11 fixture and
# before the 2099-12 ones that exercise the rule; V34 runs the default constant itself.
gate_lens=2099-12-01
gate_utf8=$(locale -a 2>/dev/null | grep -iE '\.utf-?8$' | grep -ixE 'en_US\.utf-?8' | head -1)
[ -n "$gate_utf8" ] || gate_utf8=$(locale -a 2>/dev/null | grep -iE '\.utf-?8$' | head -1)
[ -n "$gate_utf8" ] || v11_bad="$v11_bad [no UTF-8 locale in locale -a: the multibyte lint fixtures cannot be exercised]"
v11_scratch=$(mktemp -d) || { v11_bad="$v11_bad [mktemp failed -- no scratch space for the corpus copies]"; v11_scratch=""; }

# F47: the floor used to count only the two subdirs, so the legacy prefix,
# legacy flat and legacy-root fixtures the corpus now carries were invisible
# to it — a floor that cannot see the layouts the check was blind to cannot
# notice them being deleted. Count every state file under the corpus.
v11_floor=$(find "$v11_corpus" -name '*.state.md' 2>/dev/null | wc -l | tr -d ' ')
# Sibling files get their own floors: a state-file floor cannot notice a split
# fixture losing its ledger or conductor half.
v11_ledger_floor=$(find "$v11_corpus" -name '*.ledger.md' 2>/dev/null | wc -l | tr -d ' ')
v11_conductor_floor=$(find "$v11_corpus" -name '*.conductor.md' 2>/dev/null | wc -l | tr -d ' ')
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
# ...and the split pair (state + ledger + conductor) in each layout it can sit in.
v11_layout_probe "split pair current/active (ledger)" "$v11_corpus/.mozart/plans/active"/*.ledger.md
v11_layout_probe "split pair current/active (conductor)" "$v11_corpus/.mozart/plans/active"/*.conductor.md
v11_layout_probe "split pair current/finished (ledger)" "$v11_corpus/.mozart/plans/finished"/*.ledger.md
v11_layout_probe "split pair current/finished (conductor)" "$v11_corpus/.mozart/plans/finished"/*.conductor.md
v11_layout_probe "split pair legacy active- prefix" "$v11_corpus/.mozart/plans"/active-*.conductor.md
v11_layout_probe "split pair legacy finished- prefix" "$v11_corpus/.mozart/plans"/finished-*.conductor.md
v11_layout_probe "split pair legacy flat prefixless" "$v11_corpus/.mozart/plans"/[0-9]*.conductor.md
v11_layout_probe "split pair legacy root thoughts/shared" "$v11_corpus/thoughts/shared/plans"/[0-9]*.ledger.md

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
      sub(/\..*$/, "", slug)
      printf "%s\t%s\t%s\n", cat, slug, key
    }
  '
}

# F47 residual, closed here: the legacy-root fixture was gitignored by the
# blanket `thoughts/` rule and passed locally while being absent from every
# other checkout. A corpus file git cannot see is a phantom, so assert the
# whole corpus is tracked rather than trusting that it is. Every file counts,
# not just *.state.md (an ignored .ledger.md or expected.tsv is the same
# phantom); .DS_Store is excluded because the repo ignores it by design.
v11_tracked_vs_disk() { # $1 = repo, $2 = dir -> "<on-disk> <tracked>"
  local on_disk tracked
  on_disk=$(find "$2" -type f ! -name .DS_Store 2>/dev/null | wc -l | tr -d ' ')
  tracked=$(git -C "$1" ls-files -- "${2#"$1/"}" 2>/dev/null | grep -vc '/\.DS_Store$' || true)
  printf '%s %s' "$on_disk" "$tracked"
}
read -r v11_on_disk v11_tracked <<<"$(v11_tracked_vs_disk "$v11_script_repo" "$v11_corpus")"

v11_expected_triples=$(awk -F'\t' -v cats="$v11_cats" '
    BEGIN { n = split(cats, a, "|"); for (i = 1; i <= n; i++) catset[a[i]] = 1 }
    $1 == "lint" && ($2 in catset) { printf "%s\t%s\t%s\n", $2, $3, $4 }
  ' "$v11_expected" | sort -u)
v11_expected_n=$(grep -c '^lint	' "$v11_expected" || true)

# The assertion body below is a function of a corpus DIRECTORY, so it can be
# run on the in-repo corpus and on an aged copy of it. A lint verdict that
# depends on how old the fixture files are is a gate that goes red on a
# calendar date: Check F reports any active state file untouched for more than
# STALE_DAYS, and a checkout, an archive extract or a CI cache all stamp the
# fixtures with whatever time they happen to have.
v11_arm() { # $1 = arm label, $2 = corpus dir
  local label="$1" src="$2" arm_bad="" dir
  v11_ov_out=""; v11_emitted=0
  # Lint a copy stamped "now", so the verdict does not depend on the source's
  # age. A copy that is missing files would lint "clean" and prove nothing, so
  # the file count must match the source and any cp/touch failure fails the arm.
  dir="$v11_scratch/fresh-${label// /-}"
  if ! { mkdir -p "$dir" && cp -R "$src/." "$dir/" && find "$dir" -exec touch {} + ; }; then
    v11_bad="$v11_bad [$label: could not copy and re-stamp the corpus]"
    return
  fi
  local src_n dir_n
  src_n=$(find "$src" -type f | wc -l | tr -d ' ')
  dir_n=$(find "$dir" -type f | wc -l | tr -d ' ')
  if [ "$src_n" -ne "$dir_n" ] || [ "$src_n" -lt 1 ]; then
    v11_bad="$v11_bad [$label: fresh copy holds $dir_n file(s), source holds $src_n]"
    return
  fi

  v11_ov_out=$(LC_ALL="$gate_utf8" MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 MOZART_LINT_LENS_SINCE="$gate_lens" bash "$gate_root/scripts/mozart-lint.sh" "$dir" 2>&1)
  local ov_rc=$?
  local no_out
  no_out=$(LC_ALL="$gate_utf8" MOZART_LINT_LENS_SINCE="$gate_lens" bash "$gate_root/scripts/mozart-lint.sh" "$dir" 2>&1)

  local ov_triples no_triples
  ov_triples=$(printf '%s\n' "$v11_ov_out" | v11_extract "$v11_cats" | sort -u)
  no_triples=$(printf '%s\n' "$no_out" | v11_extract "$v11_cats" | sort -u)

  # F49: every LINT line the corpus emits must be accounted for in
  # expected.tsv. Set-equality over a FILTERED category list cannot see a
  # fixture that also fires an unfiltered category -- 2099-07-29-noflow-j fired
  # missing-12b as well as its intended missing-2b, so it was not failing only
  # for its stated reason and nothing said so. Compare totals, not just the
  # filtered set: N emitted lines, N expected rows, N distinct triples.
  v11_emitted=$(grep -c '^LINT \[' <<<"$v11_ov_out" || true)
  local triple_n
  triple_n=$(grep -c . <<<"$ov_triples" || true)

  [ "$ov_rc" -eq 1 ] || arm_bad="$arm_bad [override rc=$ov_rc want 1]"
  [ "$v11_emitted" -eq "$v11_expected_n" ] || arm_bad="$arm_bad [corpus emitted $v11_emitted LINT line(s), expected.tsv records $v11_expected_n — a fixture is firing a category nothing accounts for]"
  [ "$triple_n" -eq "$v11_expected_n" ] || arm_bad="$arm_bad [$triple_n distinct triples vs $v11_expected_n expected rows]"
  [ "$ov_triples" = "$v11_expected_triples" ] || arm_bad="$arm_bad [K/L triples not set-equal to expected.tsv]"
  # D12: six HEAVY fixtures dated before 2099-12 are silent on the lens-record rules only because the corpus pins
  # the lens date to $gate_lens. With the pin removed (the default 2026-10-04 applies to every 2099 slug) the run
  # must add exactly these 11 triples and lose none, so the pin is a checked fact and not a silent assumption.
  local unp_out unp_triples unp_extra unp_lost unp_want
  unp_out=$(env -u MOZART_LINT_LENS_SINCE LC_ALL="$gate_utf8" MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 bash "$gate_root/scripts/mozart-lint.sh" "$dir" 2>&1)
  unp_triples=$(printf '%s\n' "$unp_out" | v11_extract "$v11_cats" | sort -u)
  unp_extra=$(comm -13 <(printf '%s\n' "$ov_triples") <(printf '%s\n' "$unp_triples"))
  unp_lost=$(comm -23 <(printf '%s\n' "$ov_triples") <(printf '%s\n' "$unp_triples"))
  unp_want=$(printf '%s\n' \
    "$(printf 'conductor-row\t2099-07-16-deliver-kP\tCR1')" "$(printf 'conductor-row\t2099-07-16-deliver-kP\ttier')" \
    "$(printf 'conductor-row\t2099-10-08-phase-combinedheavy\tCR1')" "$(printf 'conductor-row\t2099-10-08-phase-combinedheavy\ttier')" \
    "$(printf 'conductor-row\t2099-10-14-phase-heavyfirst\tCR1')" "$(printf 'conductor-row\t2099-10-14-phase-heavyfirst\ttier')" \
    "$(printf 'conductor-row\t2099-10-20-phase-lenspre\tCR1')" "$(printf 'conductor-row\t2099-10-20-phase-lenspre\tCR2')" "$(printf 'conductor-row\t2099-10-20-phase-lenspre\ttier')" \
    "$(printf 'conductor-row\t2099-10-26-phase-widgets\ttier')" "$(printf 'conductor-row\t2099-10-29-phase-boldheavy\ttier')" | sort)
  [ "$(grep -c . <<<"$unp_want")" -eq 11 ] || arm_bad="$arm_bad [the pin-dependence list holds $(grep -c . <<<"$unp_want") members, want 11]"
  { [ "$unp_extra" = "$unp_want" ] && [ -z "$unp_lost" ]; } \
    || arm_bad="$arm_bad [removing the lens-date pin did not add exactly the 11 named lens-rule triples (added: $(printf '%s' "$unp_extra" | tr '\t\n' ' /' | cut -c1-200); lost: $(printf '%s' "$unp_lost" | tr '\t\n' ' /' | cut -c1-80))]"
  local member
  for member in \
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
    "$(printf 'decision-trigger\t2099-05-30-deliver-precutoff-header\tD1')" \
    "$(printf 'split-layout\t2099-09-05-deliver-split-dupledger\tfindings-ledger-duplicate')" \
    "$(printf 'split-layout\t2099-09-04-deliver-split-dupconductor\tconductor-record-duplicate')" \
    "$(printf 'split-layout\t2099-09-06-deliver-split-ledgermissing\tfindings-ledger-missing')" \
    "$(printf 'split-layout\t2099-05-21-deliver-split-conductormissing\tconductor-record-missing')" \
    "$(printf 'split-layout\t2099-09-07-deliver-split-ledgernohead\tfindings-ledger-noheading')" \
    "$(printf 'split-layout\t2099-09-08-deliver-split-conductornohead\tconductor-record-noheading')" \
    "$(printf 'conductor-unlinked\t2099-09-04-deliver-split-dupconductor\t9')" \
    "$(printf 'conductor-unlinked\t2099-09-02-deliver-split-unlinked\t9')" \
    "$(printf 'conductor-unlinked\t2099-09-03-deliver-split-rejected\tF2')" \
    "$(printf 'conductor-missing\t2099-09-10-deliver-split-emptyconductor\t-')" \
    "$(printf 'conductor-unlinked\t2099-09-12-deliver-mixed-conductor\tF3')" \
    "$(printf 'stranded-artifacts\t2099-09-13-deliver-split-halfmoved\tstate is in finished/ but sibling artifact(s) remain in active/')" \
    "$(printf 'split-layout\t2099-09-13-deliver-split-halfmoved\tfindings-ledger-missing')" \
    "$(printf 'conductor-unlinked\tfinished-2099-09-21-deliver-split-fprefix\t5')" \
    "$(printf 'conductor-unlinked\t2099-09-23-deliver-split-legacyroot\tF2')" \
    "$(printf 'conductor-row\t2099-09-18-deliver-split-crlf\tCR2')" \
    "$(printf 'conductor-row\t2099-09-18-deliver-split-crlf\tCR3')" \
    "$(printf 'conductor-unlinked\t2099-09-18-deliver-split-crlf\tF2')" \
    "$(printf 'conductor-unlinked\t2099-09-19-deliver-split-quoted\t5')" \
    "$(printf 'conductor-unlinked\t2099-05-25-deliver-split-preadopted\t9')" \
    "$(printf 'conductor-unlinked\t2099-09-20-deliver-zerostate\tF2')" \
    "$(printf 'split-layout\t2099-09-25-deliver-split-noheadinfile\tfindings-ledger-noheading')" \
    "$(printf 'conductor-unlinked\t2099-09-25-deliver-split-noheadinfile\tF2')" \
    "$(printf 'split-layout\t2099-09-26-deliver-split-conductorstray\tconductor-record-noheading')" \
    "$(printf 'conductor-unlinked\t2099-07-16-deliver-kP\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-05-phase-notier\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-06-phase-placeholder\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-07-phase-unfilled\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-08-phase-combinedheavy\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-10-phase-heavyfmt\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-12-phase-lower\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-13-phase-title\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-14-phase-heavyfirst\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-27-phase-quoted\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-11-phase-stdfmt\tP2')" \
    "$(printf 'conductor-unlinked\t2099-10-31-phase-italicstd\tP2')" \
    "$(printf 'conductor-unlinked\t2099-11-01-phase-underlight\tP2')" \
    "$(printf 'conductor-unlinked\t2099-11-02-phase-stdarrow\tP2')" \
    "$(printf 'conductor-unlinked\t2099-11-03-phase-stdnow\tP2')" \
    "$(printf 'conductor-unlinked\t2099-11-04-phase-commaplaceholder\tP2')" \
    "$(printf 'conductor-unlinked\t2099-11-05-phase-suffixed\tP2')" \
    "$(printf 'conductor-unlinked\t2099-11-07-phase-boldstdesc\tP2')" \
    "$(printf 'conductor-unlinked\t2099-11-09-phase-ticked\tP2')" \
    "$(printf 'conductor-unlinked\t2099-11-14-phase-boldlist\tP2')" \
    "$(printf 'conductor-unlinked\t2099-07-02-deliver-k9\t9')" \
    "$(printf 'conductor-row\t2099-10-16-phase-stdmalformed\tCR1')" \
    "$(printf 'conductor-row\t2099-10-19-phase-lensbad\tCR2')" \
    "$(printf 'conductor-row\t2099-10-21-phase-lensian\tCR1')" \
    "$(printf 'conductor-row\t2099-10-22-phase-lensreason\tCR1')" \
    "$(printf 'conductor-row\t2099-10-23-phase-lenstoken\tCR1')" \
    "$(printf 'conductor-row\t2099-10-26-phase-widgets\tCR1')" \
    "$(printf 'conductor-row\t2099-10-26-phase-widgets\tCR2')" \
    "$(printf 'conductor-row\t2099-11-10-phase-lenshyphen\tCR1')" \
    "$(printf 'conductor-row\t2099-11-11-phase-lensrunning\tCR1')" \
    "$(printf 'conductor-row\t2099-11-12-phase-lenswsreason\tCR1')" \
    "$(printf 'conductor-row\t2099-11-15-phase-lenscell\tCR1')" \
    "$(printf 'conductor-row\t2099-11-17-phase-heavyrepeat\tCR1')" \
    "$(printf 'conductor-row\t2099-11-18-phase-xanderskip\tCR2')" \
    "$(printf 'conductor-row\t2099-11-19-phase-prebare\tCR1')" \
    "$(printf 'conductor-row\t2099-11-20-phase-escnorow\tCR1')" \
    "$(printf 'conductor-row\t2099-11-21-phase-rownoesc\tCR1')" \
    "$(printf 'conductor-row\t2099-11-22-phase-passlinkwrong\tCR1')" \
    "$(printf 'conductor-row\t2099-12-10-phase-escnoclaim\tCR1')" \
    "$(printf 'conductor-row\t2099-12-11-phase-escdocsreason\tCR1')" \
    "$(printf 'conductor-row\t2099-12-12-phase-escseereason\tCR1')" \
    "$(printf 'conductor-row\t2099-12-13-phase-escprefixlink\tCR1')" \
    "$(printf 'conductor-row\t2099-12-14-phase-escplaceholder\tCR1')" \
    "$(printf 'conductor-row\t2099-12-15-phase-escnotrun\tCR1')" \
    "$(printf 'conductor-row\t2099-12-17-phase-escoldform\tCR1')" \
    "$(printf 'conductor-row\t2099-12-16-phase-escafterk\tCR3')" \
    "$(printf 'conductor-row\t2099-12-18-phase-escorder\tCR4')" \
    "$(printf 'conductor-row\t2099-12-20-phase-esctwodigit\tCR3')" \
    "$(printf 'conductor-row\t2099-12-01-phase-bareheavy\ttier')" \
    "$(printf 'conductor-row\t2099-12-02-phase-emptysurface\ttier')" \
    "$(printf 'conductor-row\t2099-12-03-phase-unlistedonly\ttier')" \
    "$(printf 'conductor-row\t2099-12-04-phase-baredated\ttier')" \
    "$(printf 'conductor-row\t2099-12-04-phase-baredated\tCR1')" \
    "$(printf 'conductor-row\t2099-12-07-phase-authcase\tCR1')" \
    "$(printf 'conductor-row\t2099-12-08-phase-semisecrets\tCR1')"
  do
    grep -qxF "$member" <<<"$ov_triples" || arm_bad="$arm_bad [named member absent: $member]"
  done
  grep -qxF "$(printf 'mutation-manifest\t2099-07-31-operate-ignore\tC2')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: C2 (all-literal ignore paths must not fire)]"
  # F48 control: the escaped-pipe fixture's CR2 carries `\|` in BOTH source and
  # control and is otherwise well formed. It must stay silent — otherwise the
  # width rule is just rejecting every row that mentions a pipe, and CR1's
  # finding would prove nothing about column alignment.
  grep -qxF "$(printf 'conductor-row\t2099-08-16-deliver-pipe-escaped\tCR2')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: pipe-escaped CR2 (a correctly escaped row must not fire)]"
  grep -qxF "$(printf 'mutation-manifest\t2099-07-31-operate-ignore\tC8')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: operate-ignore C8 (the escaped change-ledger twin must not fire)]"
  # Check M and the sibling readers must stay silent on these (the contract's
  # 2.1, 2.2-silent, 2.8 a and b, 2.9, 2.11 Check M, 2.12, and the four
  # layouts that carry a clean or exempt split pair).
  local quiet
  for quiet in 2099-09-01-deliver-split-clean 2099-05-23-deliver-split-exempt 2099-05-24-deliver-split-preledger \
    2099-09-11-deliver-mixed-ledger 2099-09-15-deliver-split-placeholders active-2099-09-17-deliver-split-aprefix \
    2099-09-22-deliver-split-flat 2099-09-24-deliver-split-finishedclean 2099-09-09-deliver-split-emptyledger \
    2099-05-22-deliver-split-emptypre; do
    grep -q "	${quiet}	" <<<"$ov_triples" \
      && arm_bad="$arm_bad [named-absent member present: $quiet produced a triple]"
  done
  grep -qxF "$(printf 'split-layout\t2099-09-14-deliver-split-pathsstale\tfindings-ledger-missing')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: Check M fired on pathsstale, whose derived sibling exists]"
  grep -qxF "$(printf 'conductor-unlinked\t2099-09-05-deliver-split-dupledger\tF2')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: the in-file rejected row of dupledger was read though the sibling wins]"
  grep -qxF "$(printf 'split-layout\t2099-09-25-deliver-split-noheadinfile\tfindings-ledger-duplicate')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: a headingless ledger sibling was treated as usable and reported as a duplicate of the in-file section]"
  grep -qxF "$(printf 'conductor-missing\t2099-09-08-deliver-split-conductornohead\t-')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: a headingless conductor sibling also yielded conductor-missing (one cause, one line)]"
  grep -qxF "$(printf 'conductor-row\t2099-09-18-deliver-split-crlf\tCR1')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: the CRLF sibling's well-formed CR1 fired]"
  grep -qxF "$(printf 'conductor-unlinked\t2099-09-18-deliver-split-crlf\t9')" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: the CRLF sibling's CR1 (links 9) was not read]"
  grep -qE '^LINT .*\.(ledger|conductor)\.md — ' <<<"$v11_ov_out" \
    && arm_bad="$arm_bad [a LINT line names a sibling file as its path: findings are always reported against the state file]"
  grep -q "	2099-07-27-operate-j	" <<<"$ov_triples" \
    && arm_bad="$arm_bad [named-absent member present: missing-2b fired on OPERATE-family 2099-07-27-operate-j]"
  # Phase rows are required on HEAVY only. Each of these carries a ticked,
  # unlinked or lens-free Phase line and must stay silent for its own reason.
  for quiet in 2099-10-02-phase-standard 2099-10-03-phase-light 2099-10-04-phase-tiny \
    2099-10-09-phase-combinedstd 2099-10-15-phase-stdfirst \
    2099-11-06-phase-stdfree 2099-11-08-phase-boldcombined 2099-10-30-phase-boldstd 2099-11-16-phase-lensemdash \
    2099-10-18-phase-lensok 2099-10-20-phase-lenspre 2099-10-24-phase-stdsurface 2099-10-25-phase-escalated 2099-10-28-phase-lowersurface 2099-12-05-phase-datedok 2099-12-06-phase-mixedsurface 2099-12-09-phase-escok 2099-12-19-phase-escorderok 2099-12-21-phase-esctwodigitok; do
    grep -q "	${quiet}	" <<<"$ov_triples" \
      && arm_bad="$arm_bad [named-absent member present: $quiet produced a triple]"
  done
  # 4.17: a HEAVY phase with no row at all is one cause, one line.
  [ "$(grep -c "	2099-10-10-phase-heavyfmt	" <<<"$ov_triples")" -eq 1 ] \
    || arm_bad="$arm_bad [heavyfmt (HEAVY, P2 has no row) did not produce exactly one triple]"
  # 4.14: the phase-row message and the expected P<digit> rows are the same
  # population, and the expected side has a floor so 1 = 1 cannot pass.
  local p_msgs p_rows
  p_msgs=$(grep -c 'ticked Phase line has no linked conductor row' <<<"$v11_ov_out" || true)
  p_rows=$(awk -F'\t' '$1 == "lint" && $2 == "conductor-unlinked" && $4 ~ /^P[0-9]/' "$v11_expected" | grep -c . || true)
  [ "$p_msgs" -eq "$p_rows" ] || arm_bad="$arm_bad [phase-row message count $p_msgs != $p_rows expected P<N> rows]"
  [ "$p_rows" -ge 5 ] || arm_bad="$arm_bad [expected P<N> rows $p_rows < floor 5]"
  local slug
  for slug in 2000-01-01-deliver-legacy 2099-05-31-deliver-prebound 2000-01-03-deliver-legacy-ledger \
    2099-08-08-deliver-revisit-trigger 2099-08-09-deliver-revisit-when; do
    grep -q "	${slug}	" <<<"$ov_triples" \
      && arm_bad="$arm_bad [pre-adoption or accepted-spelling slug $slug produced a triple]"
  done

  # Check N (escape-unrecorded). Present: every firing fixture by name, so editing expected.tsv
  # alone cannot hide one. Absent: the silent twins (recorded, prefix-collision twin, fenced,
  # external, ticket id, self-reference, not-a-claim), each shown able to fire by its firing sibling.
  local esc_want esc_n no_esc
  for member in \
    "$(printf 'escape-unrecorded\t2099-05-02-deliver-esc-noneyet\t2099-09-02-diagnose-noneyet')" \
    "$(printf 'escape-unrecorded\t2099-05-02-deliver-esc-placeholder\t2099-09-02-diagnose-placeholder')" \
    "$(printf 'escape-unrecorded\t2099-05-03-deliver-esc-noheading\t2099-09-03-diagnose-noheading')" \
    "$(printf 'escape-unrecorded\t2099-05-05-deliver-esc-forms\t2099-09-05-diagnose-form-plain')" \
    "$(printf 'escape-unrecorded\t2099-05-05-deliver-esc-forms\t2099-09-05-diagnose-form-bold')" \
    "$(printf 'escape-unrecorded\t2099-05-05-deliver-esc-forms\t2099-09-05-diagnose-form-boldcolon')" \
    "$(printf 'escape-unrecorded\t2099-05-05-deliver-esc-forms\t2099-09-05-diagnose-form-tick')" \
    "$(printf 'escape-unrecorded\t2099-05-05-deliver-esc-forms\t2099-09-05-diagnose-form-nested')" \
    "$(printf 'escape-unrecorded\t2099-05-05-deliver-esc-forms\t2099-09-05-diagnose-form-partial')" \
    "$(printf 'escape-unrecorded\t2099-05-07-deliver-esc-pm\t2099-09-07-incident-pm')" \
    "$(printf 'escape-unrecorded\t2099-09-08-diagnose-nostate\t2099-09-08-diagnose-nostate')" \
    "$(printf 'escape-unrecorded\t2099-08-30-diagnose-nostate\t2099-08-30-diagnose-nostate')" \
    "$(printf 'escape-unrecorded\t2099-05-09-deliver-esc-prefix\t2099-09-09-diagnose-a')" \
    "$(printf 'escape-unrecorded\t2099-05-10-deliver-esc-section\t2099-09-10-diagnose-section')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-act\t2099-09-11-diagnose-lk-act-no')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-fin\t2099-09-11-diagnose-lk-fin-no')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-abo\t2099-09-11-diagnose-lk-abo-no')" \
    "$(printf 'escape-unrecorded\tactive-2099-05-11-deliver-esc-lk-apre\t2099-09-11-diagnose-lk-apre-no')" \
    "$(printf 'escape-unrecorded\tfinished-2099-05-11-deliver-esc-lk-fpre\t2099-09-11-diagnose-lk-fpre-no')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-flat\t2099-09-11-diagnose-lk-flat-no')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-leg\t2099-09-11-diagnose-lk-leg-no')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-rev\t2099-09-11-diagnose-lk-rev-no')" \
    "$(printf 'escape-unrecorded\t2099-05-13-deliver-esc-dup\t2099-09-13-diagnose-dup')" \
    "$(printf 'escape-unrecorded\t2099-05-13-deliver-esc-dup\t2099-09-13-diagnose-dup2')" \
    "$(printf 'escape-unrecorded\t2099-05-16-deliver-esc-fence\t2099-09-16-diagnose-fence-after')" \
    "$(printf 'escape-unrecorded\t2099-09-18-diagnose-dotted\t2099-09-18-diagnose-dotted')" \
    "$(printf 'escape-unrecorded\t2099-05-23-deliver-esc-ext\t2099-09-23-diagnose-extslug')" \
    "$(printf 'escape-unrecorded\t2099-05-27-deliver-esc-wrap\t2099-09-27-diagnose-wrap2')" \
    "$(printf 'escape-unrecorded\t2099-05-28-deliver-esc-mb\t2099-09-28-diagnose-mbunrec')"
  do
    grep -qxF "$member" <<<"$ov_triples" || arm_bad="$arm_bad [named member absent: $member]"
  done
  for member in \
    "$(printf 'escape-unrecorded\t2099-05-01-deliver-esc-recorded\t2099-09-01-diagnose-recorded')" \
    "$(printf 'escape-unrecorded\t2099-05-02-deliver-esc-trailing\t2099-09-02-diagnose-trailing')" \
    "$(printf 'escape-unrecorded\t2099-05-04-deliver-esc-real\t2099-09-04-diagnose-not-applicable')" \
    "$(printf 'escape-unrecorded\t2099-05-04-deliver-esc-real\t2099-09-04-diagnose-silent-forms')" \
    "$(printf 'escape-unrecorded\t2099-09-06-diagnose-self\t2099-09-06-diagnose-self')" \
    "$(printf 'escape-unrecorded\t2099-05-09-deliver-esc-prefix\t2099-09-09-diagnose-ab')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-act\t2099-09-11-diagnose-lk-act-ok')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-fin\t2099-09-11-diagnose-lk-fin-ok')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-abo\t2099-09-11-diagnose-lk-abo-ok')" \
    "$(printf 'escape-unrecorded\tactive-2099-05-11-deliver-esc-lk-apre\t2099-09-11-diagnose-lk-apre-ok')" \
    "$(printf 'escape-unrecorded\tfinished-2099-05-11-deliver-esc-lk-fpre\t2099-09-11-diagnose-lk-fpre-ok')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-flat\t2099-09-11-diagnose-lk-flat-ok')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-leg\t2099-09-11-diagnose-lk-leg-ok')" \
    "$(printf 'escape-unrecorded\t2099-05-11-deliver-esc-lk-rev\t2099-09-11-diagnose-lk-rev-ok')" \
    "$(printf 'escape-unrecorded\t2099-09-12-diagnose-ticket\t2099-09-12-diagnose-ticket')" \
    "$(printf 'escape-unrecorded\t2099-05-16-deliver-esc-fence\t2099-09-16-diagnose-fence-backtick')" \
    "$(printf 'escape-unrecorded\t2099-05-16-deliver-esc-fence\t2099-09-16-diagnose-fence-tilde')" \
    "$(printf 'escape-unrecorded\t2099-05-16-deliver-esc-fence\t2099-09-16-diagnose-fence-open')" \
    "$(printf 'escape-unrecorded\t2099-05-23-deliver-esc-ext\t2099-09-23-diagnose-external')" \
    "$(printf 'escape-unrecorded\t2099-05-27-deliver-esc-wrap\t2099-09-27-diagnose-wrapcarry')" \
    "$(printf 'escape-unrecorded\t2099-05-28-deliver-esc-mb\t2099-09-28-diagnose-mbquote')" \
    "$(printf 'escape-unrecorded\t2099-05-28-deliver-esc-mb\t2099-09-28-diagnose-mbdash')" \
    "$(printf 'escape-unrecorded\t2099-05-28-deliver-esc-mb\t2099-09-28-diagnose-mbpre')"
  do
    grep -qxF "$member" <<<"$ov_triples" \
      && arm_bad="$arm_bad [named-absent member present: ${member//$'\t'/ / }]"
  done
  esc_want=$(awk -F'\t' '$1 == "lint" && $2 == "escape-unrecorded"' "$v11_expected" | grep -c . || true)
  esc_n=$(grep -c '^escape-unrecorded	' <<<"$ov_triples" || true)
  no_esc=$(grep -c '^escape-unrecorded	' <<<"$no_triples" || true)
  [ "$esc_n" -eq "$esc_want" ] || arm_bad="$arm_bad [escape-unrecorded: $esc_n emitted, $esc_want in expected.tsv]"
  [ "$esc_want" -ge 6 ] || arm_bad="$arm_bad [escape-unrecorded expected rows $esc_want < floor 6]"
  [ "$no_esc" -eq "$esc_want" ] || arm_bad="$arm_bad [escape-unrecorded fires $no_esc time(s) without the adoption-date override, want $esc_want: the check must not be gated on it]"

  # F45: two same-category triples in one file (fixture #3's CR1/CR2, #34's
  # C3-C6) could have their reasons swapped and still pass a key-only
  # set-equality check. Assert the actual message text too, so the gate
  # proves each fired for ITS OWN stated reason.
  msg_check() { # $1=path-suffix (basename), $2=key, $3=expected message substring
    grep -F "$1" <<<"$v11_ov_out" | grep -F -- "— $2:" | grep -qF "$3" \
      || arm_bad="$arm_bad [message mismatch: $1 $2 does not contain '$3']"
  }
  msg_check "2099-07-03-deliver-ctl.state.md" "CR1" "control restates the claim"
  msg_check "2099-07-03-deliver-ctl.state.md" "CR2" "empty or placeholder control"
  msg_check "2099-07-31-operate-ignore.state.md" "C3" "bad ignore token: spec.*"
  msg_check "2099-07-31-operate-ignore.state.md" "C4" "bad ignore token: status.conditions[*]"
  msg_check "2099-07-31-operate-ignore.state.md" "C5" "bad ignore token: spec."
  msg_check "2099-07-31-operate-ignore.state.md" "C6" "bad ignore token: status"
  # F48: the two pipe fixtures are the same shape modulo the escape, so a
  # key-only assertion would pass if both produced the same finding. Name the
  # distinct reasons: the raw row is rejected on WIDTH, the escaped row parses
  # and is then rejected on its genuinely empty control.
  msg_check "2099-08-15-deliver-pipe-raw.state.md" "CR1" "row has 8 cells, header has 7"
  msg_check "2099-08-16-deliver-pipe-escaped.state.md" "CR1" "empty or placeholder control"
  msg_check "2099-07-31-operate-ignore.state.md" "C7" "row has 8 cells, header has 7"
  # Check M: six keys, six reasons. A key-only check would pass if two keys
  # swapped their texts.
  msg_check "2099-09-05-deliver-split-dupledger.state.md" "findings-ledger-duplicate" "## Findings ledger is in the state file and in the sibling ledger file"
  msg_check "2099-09-04-deliver-split-dupconductor.state.md" "conductor-record-duplicate" "## Conductor record is in the state file and in the sibling conductor file"
  msg_check "2099-09-06-deliver-split-ledgermissing.state.md" "findings-ledger-missing" "declares a findings ledger but the sibling ledger file"
  msg_check "2099-05-21-deliver-split-conductormissing.state.md" "conductor-record-missing" "declares a conductor record but the sibling conductor file"
  msg_check "2099-09-07-deliver-split-ledgernohead.state.md" "findings-ledger-noheading" "sibling ledger file has content outside a ## Findings ledger section"
  msg_check "2099-09-08-deliver-split-conductornohead.state.md" "conductor-record-noheading" "sibling conductor file has content outside a ## Conductor record section"
  msg_check "2099-09-26-deliver-split-conductorstray.state.md" "conductor-record-noheading" "sibling conductor file has content outside a ## Conductor record section (no such heading, or text ahead of it)"
  msg_check "2099-07-16-deliver-kP.state.md" "P2" "ticked Phase line has no linked conductor row"
  msg_check "2099-10-16-phase-stdmalformed.state.md" "CR1" "empty or placeholder control"
  msg_check "2099-10-19-phase-lensbad.state.md" "CR2" "HEAVY phase row does not record ian and xander"
  msg_check "2099-10-21-phase-lensian.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-10-22-phase-lensreason.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-10-23-phase-lenstoken.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-10-26-phase-widgets.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-10-26-phase-widgets.state.md" "CR2" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-11-10-phase-lenshyphen.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-11-11-phase-lensrunning.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-11-12-phase-lenswsreason.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-11-15-phase-lenscell.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-11-17-phase-heavyrepeat.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-11-18-phase-xanderskip.state.md" "CR2" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-11-19-phase-prebare.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-11-20-phase-escnorow.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-11-21-phase-rownoesc.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-11-22-phase-passlinkwrong.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-10-phase-escnoclaim.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-11-phase-escdocsreason.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-12-phase-escseereason.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-13-phase-escprefixlink.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-14-phase-escplaceholder.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-15-phase-escnotrun.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-17-phase-escoldform.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-16-phase-escafterk.state.md" "CR3" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-18-phase-escorder.state.md" "CR4" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-20-phase-esctwodigit.state.md" "CR3" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-01-phase-bareheavy.state.md" "tier" "HEAVY tier line has no usable surface record"
  msg_check "2099-12-02-phase-emptysurface.state.md" "tier" "HEAVY tier line has no usable surface record"
  msg_check "2099-12-03-phase-unlistedonly.state.md" "tier" "HEAVY tier line has no usable surface record"
  msg_check "2099-12-04-phase-baredated.state.md" "tier" "HEAVY tier line has no usable surface record"
  msg_check "2099-12-04-phase-baredated.state.md" "CR1" "HEAVY phase row does not record ian and xander"
  msg_check "2099-12-07-phase-authcase.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-12-08-phase-semisecrets.state.md" "CR1" "HEAVY phase row with surface auth, secrets or security does not record xander as run"
  msg_check "2099-09-18-deliver-split-crlf.state.md" "CR2" "row has 8 cells, header has 7"
  msg_check "2099-09-18-deliver-split-crlf.state.md" "CR3" "empty or placeholder control"
  msg_check "2099-05-03-deliver-esc-noheading.state.md" "2099-09-03-diagnose-noheading" "has no ## Escapes block"
  msg_check "2099-05-02-deliver-esc-noneyet.state.md" "2099-09-02-diagnose-noneyet" "## Escapes block has no Traces-to: line naming 2099-09-02-diagnose-noneyet"
  msg_check "2099-09-08-diagnose-nostate.md" "2099-09-08-diagnose-nostate" "traces to 2099-05-08-deliver-esc-ghost, which has no state file in this repo"
  msg_check "2099-08-30-diagnose-nostate.postmortem.md" "2099-08-30-diagnose-nostate" "traces to 2099-05-08-deliver-esc-ghosttwo, which has no state file in this repo"
  grep -qxF "$(printf 'conductor-missing\t2099-05-31-deliver-prebound\t-')" <<<"$no_triples" \
    || arm_bad="$arm_bad [override-control triple absent from the no-override run]"
  grep -qxF 'conductor adoption date overridden: 2099-06-01' <<<"$v11_ov_out" \
    || arm_bad="$arm_bad [override-visibility line absent from the override run]"
  grep -q '^conductor adoption date overridden:' <<<"$no_out" \
    && arm_bad="$arm_bad [no-override run printed an override line]"
  [ -z "$arm_bad" ] || v11_bad="$v11_bad [$label:$arm_bad]"
}

# Arm (a): the in-repo corpus as it stands. Arm (b): a copy whose every file is
# stamped 2020-01-01, which is what the corpus looks like to any consumer more
# than STALE_DAYS after the fixtures were last written.
v11_aged="$v11_scratch/aged"
if [ -n "$v11_scratch" ] && mkdir -p "$v11_aged" && cp -R "$v11_corpus/." "$v11_aged/" \
   && find "$v11_aged" -exec touch -t 202001010000 {} + ; then
  :
else
  v11_bad="$v11_bad [could not build the aged corpus copy]"
fi

# Raw lint of the aged copy (no normalization) must emit stale-active: this is
# what shows the normalization in v11_arm is removing something real, and that
# a lint which stopped checking staleness is noticed.
v11_raw_aged=$(bash "$gate_root/scripts/mozart-lint.sh" "$v11_aged" 2>&1)
v11_stale_n=$(printf '%s\n' "$v11_raw_aged" | grep -c '^LINT \[stale-active\]' || true)
[ "$v11_stale_n" -ge 40 ] || v11_bad="$v11_bad [raw lint of the aged corpus emitted $v11_stale_n stale-active line(s), floor 40 -- the aged arm is not aged]"
# The stale-active lines go through a variable and a here-string, not a pipeline
# ending in `grep -q`: this file runs under pipefail, and a `-q` that exits on
# its first match hands the upstream grep a SIGPIPE once the output outgrows a
# pipe write (about 14 KB here). That reads as "member absent" (a false FAIL) in
# the first check and as "member absent" again, i.e. a false PASS, in the second.
v11_stale_lines=$(printf '%s\n' "$v11_raw_aged" | grep '^LINT \[stale-active\]')
for v11_stale_member in 2099-08-11-deliver-flat active-2099-08-12-deliver-prefix; do
  grep -qF "$v11_stale_member.state.md" <<<"$v11_stale_lines" \
    || v11_bad="$v11_bad [named member absent: stale-active for $v11_stale_member in the aged corpus]"
done
grep -qF "2099-07-01-deliver-clean.state.md" <<<"$v11_stale_lines" \
  && v11_bad="$v11_bad [named-absent member present: stale-active on the terminal fixture 2099-07-01-deliver-clean]"

if [ -n "$v11_scratch" ]; then
  v11_arm "in-repo corpus" "$v11_corpus"
  v11_arm_a_emitted=$v11_emitted
  v11_arm "aged corpus copy" "$v11_aged"
  # Once under C: the same corpus, the same verdict count, no abort.
  v11_c_out=$(LC_ALL=C MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 MOZART_LINT_LENS_SINCE="$gate_lens" bash "$gate_root/scripts/mozart-lint.sh" "$v11_scratch/fresh-in-repo-corpus" 2>&1); v11_c_rc=$?
  v11_c_n=$(grep -c '^LINT \[' <<<"$v11_c_out" || true)
  { [ "$v11_c_rc" -eq 1 ] && [ "$v11_c_n" -eq "$v11_expected_n" ]; } \
    || v11_bad="$v11_bad [LC_ALL=C: lint exited $v11_c_rc with $v11_c_n LINT line(s), want 1 and $v11_expected_n]"
fi
[ -z "$v11_scratch" ] || rm -rf "$v11_scratch"

[ "$v11_floor" -ge 173 ] || v11_bad="$v11_bad [fixture floor $v11_floor < 173: a lint fixture was lost]"
[ "$v11_ledger_floor" -ge 16 ] || v11_bad="$v11_bad [ledger sibling floor $v11_ledger_floor < 16]"
[ "$v11_conductor_floor" -ge 25 ] || v11_bad="$v11_bad [conductor sibling floor $v11_conductor_floor < 25]"
# The slug rule is "basename up to the first dot" (Check N, and all three extractors). That reads a
# state file's slug correctly only while no slug holds a dot; the corpus must keep that premise.
v11_dotted=$(find "$v11_corpus" -name '*.state.md' 2>/dev/null | sed 's#.*/##; s#\.state\.md$##' | grep -c '\.' || true)
[ "$v11_dotted" -eq 0 ] || v11_bad="$v11_bad [$v11_dotted corpus state file(s) have a dot in the slug: the first-dot slug rule would cut them]"
v11_escdirs=$(find "$v11_corpus" -type d \( -name investigations -o -name incidents \) 2>/dev/null | grep -c . || true)
[ "$v11_escdirs" -ge 3 ] || v11_bad="$v11_bad [corpus has $v11_escdirs investigations/incidents dir(s), floor 3 (both roots, and incidents)]"
[ -z "$v11_layout_missing" ] || v11_bad="$v11_bad [corpus layout(s) unpopulated:$v11_layout_missing]"
[ "$v11_tracked" -eq "$v11_on_disk" ] || v11_bad="$v11_bad [$v11_on_disk corpus file(s) on disk but $v11_tracked tracked by git — an ignored fixture passes here and exists nowhere else]"
# Self-test: the widened comparison can fail. An ignored file planted in a
# scratch repo must make it unequal.
v11_st=$(mktemp -d) && {
  git -C "$v11_st" init -q 2>/dev/null && mkdir -p "$v11_st/c" && : > "$v11_st/c/a.md" \
    && git -C "$v11_st" add -A 2>/dev/null && : > "$v11_st/c/.DS_Store" && : > "$v11_st/c/ignored.ledger.md" \
    && printf 'ignored.ledger.md\n' > "$v11_st/.git/info/exclude"
  read -r v11_st_disk v11_st_tracked <<<"$(v11_tracked_vs_disk "$v11_st" "$v11_st/c")"
  [ "$v11_st_disk" -ne "$v11_st_tracked" ] || v11_bad="$v11_bad [tracked-vs-disk self-test: a planted ignored file did not make the counts differ ($v11_st_disk vs $v11_st_tracked)]"
  rm -rf "$v11_st"
} || v11_bad="$v11_bad [mktemp failed -- the tracked-vs-disk self-test could not run]"
# F49: two overlapping suite runs failed V11 with a "named member absent" for a
# member that was there, and a 9-way batch failed V10b the same way. The shape is
# a variable piped into a quiet grep under pipefail: grep -q exits on its first
# hit, the producer still has a write to make (bash's printf issues the closing
# newline separately, and the 78 KB lint output and 17 KB triple list need
# several), and a producer that writes into a closed pipe gets SIGPIPE, so the
# pipeline reports failure for a match. Idle it almost never loses the race; CPU
# contention from another run makes it lose. Reproduced in isolation under load:
# 1 in 400 at 20 KB and 1 in 3000 at 1.2 KB, member on the first line, against
# 0 for a here-string. A variable read through a here-string has no producer to
# kill. Three parts: the hazard is real here (a 3 MB producer loses every time,
# so this is not folklore), the here-string form is immune, and no line in this
# file pipes a variable straight into a quiet grep. A multi-stage pipe whose
# first stage is not quiet is outside the scan: that stage reads to the end and
# its successor's output is a single small write.
v11_big=$(head -c 3000000 /dev/zero | tr '\0' 'x' | fold -w 80)
v11_big="first-line"$'\n'"$v11_big"
echo "$v11_big" | grep -qxF first-line \
  && v11_bad="$v11_bad [SIGPIPE control: a 3 MB variable piped into a quiet grep found its first-line member; the hazard F49 closed is not reproducing, so the immunity check below proves nothing]"
grep -qxF first-line <<<"$v11_big" \
  || v11_bad="$v11_bad [a here-string quiet grep lost a first-line member in a 3 MB variable]"
unset v11_big
# F60: the first version of this scan saw one spelling. A variable-fed printf or echo is the producer, whatever
# its quoting; an early-exiting consumer is grep -q (also -Fq, -F -q, --quiet), grep -m (also -m1,
# --max-count) or head. Each of those can close the pipe on a producer that still has a write to make. A
# two-stage pipe whose first grep reads to the end and feeds a quiet grep is a smaller race (one small write)
# but is converted too, so the rule has no "outside the scan" category left to argue about.
# The one allowed hit is the deliberate 3 MB control above, which proves the hazard is real.
# Scope: this reads only this gate file. scripts/mozart-lint.sh keeps no variable-fed pipe into an early-exiting
# grep: its three flow-family tests were converted to here-strings (it has no pipefail, so they were safe, but the
# ports copy that file and the convention is now uniform).
v11_prod='(printf +(-- +)?("[^"]*"|'"'"'[^'"'"']*'"'"') +|echo +(-[a-zA-Z]+ +)?)("[^"]*"|\$[A-Za-z_{][A-Za-z0-9_}]*) *\| *'
v11_pipe_pat1="${v11_prod}"'(grep( +-[^ ]+)* +(-[a-zA-Z]*[qm][a-zA-Z0-9]*|--quiet|--max-count)|head)([^A-Za-z0-9_-]|$)'
v11_pipe_pat2="${v11_prod}"'grep[^|]*\| *grep( +-[^ ]+)* +(-[a-zA-Z]*q[a-zA-Z]*|--quiet)'
v11_pipe_count() { grep -cE -e "$v11_pipe_pat1" -e "$v11_pipe_pat2" || true; }
v11_pf=printf; v11_ec=echo; v11_gr=grep; v11_hd=head
v11_plants=(
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr -qxF y"
  "$v11_pf '%s' \"\$x\" | $v11_gr -qE -- \"\$p\" || true"
  "$v11_pf \"%s\\n\" \"\$x\" | $v11_gr -q y"
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr -F -q y"
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr --quiet y"
  "$v11_ec \"\$x\" | $v11_gr -q y"
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr -m1 y"
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr --max-count=1 y"
  "$v11_pf '%s\\n' \"\$x\" | $v11_hd -1"
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr -F y | $v11_gr -qF z"
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr -F y | $v11_gr --quiet z"
)
for v11_pl in "${v11_plants[@]}"; do
  [ "$(v11_pipe_count <<<"$v11_pl")" -eq 1 ] \
    || v11_bad="$v11_bad [pipe-into-quiet-grep scan did not flag a planted spelling: $v11_pl]"
done
v11_clean=(
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr -c y"
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr -F -x -v -e y"
  "$v11_pf '%s\\n' \"\$x\" | $v11_gr -E 'a|b' | wc -l"
  "$v11_gr -qxF y <<<\"\$x\""
  "$v11_hd -1 <<<\"\$x\""
  "$v11_gr -m1 -F y <<<\"\$x\" | $v11_gr -qF z"
)
for v11_pl in "${v11_clean[@]}"; do
  [ "$(v11_pipe_count <<<"$v11_pl")" -eq 0 ] \
    || v11_bad="$v11_bad [pipe-into-quiet-grep scan flagged a clean line: $v11_pl]"
done
[ "${#v11_plants[@]}" -eq 11 ] && [ "${#v11_clean[@]}" -eq 6 ] \
  || v11_bad="$v11_bad [the pipe scan holds ${#v11_plants[@]} plants and ${#v11_clean[@]} clean lines, want 11 and 6: a plant was deleted along with its pattern alternative]"
v11_pipe_sites=$(v11_pipe_count < "$gatefile")
[ "$v11_pipe_sites" -eq 1 ] && [ "$(grep -E -e "$v11_pipe_pat1" "$gatefile" | grep -c 'v11_big')" -eq 1 ] \
  || v11_bad="$v11_bad [$v11_pipe_sites line(s) of this file pipe a variable into an early-exiting grep or head; the only allowed one is the v11_big control: write grep -q ... <<<\"\$var\"]"
v11_default=$(grep -oE 'CONDUCTOR_SINCE="\$\{MOZART_LINT_CONDUCTOR_SINCE:-[0-9]{4}-[0-9]{2}-[0-9]{2}\}"' "$gate_root/scripts/mozart-lint.sh" \
  | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
if [ -z "$v11_default" ] || { [ "$v11_default" != "2026-09-18" ] && [ "$(printf '%s\n%s\n' "$v11_default" "2026-09-18" | sort | head -1)" = "$v11_default" ]; }; then
  v11_bad="$v11_bad [CONDUCTOR_SINCE default '$v11_default' < 2026-09-18]"
fi
report "V11" "$([ -z "$v11_bad" ] && echo 0 || echo 1)" \
  "${v11_bad:-lint corpus, in-repo and aged copy (raw aged lint emits $v11_stale_n stale-active): override rc=1, floor=$v11_floor across 6 layouts plus the split pair ($v11_ledger_floor ledger and $v11_conductor_floor conductor siblings), $v11_arm_a_emitted emitted = $v11_expected_n expected (no unaccounted category), K/L triples set-equal, named members present, override-visibility correct both ways, CONDUCTOR_SINCE default=$v11_default}"

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
  pkeys=$(printf '%s' "$prow" | awk -F'|' '{print $4}' | grep -oE '`[^`]+`' | tr -d '`' | sed -E 's/^P<N>:heavy$/P:heavy/' | tr '\n' ' ' | sed -E 's/ +$//; s/^ +//')
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
grep -qF '`9`' <<<"$v12_deliver_row" || v12_bad="$v12_bad [DELIVER named member 9 absent from prose row]"
grep -qF '`P<N>:heavy`' <<<"$v12_deliver_row" || v12_bad="$v12_bad [DELIVER named member P<N>:heavy absent from prose row]"
[ "$CONDUCTOR_GATES_DELIVER" = "5 9 10 13 P:heavy" ] || v12_bad="$v12_bad [CONDUCTOR_GATES_DELIVER is '$CONDUCTOR_GATES_DELIVER', want exactly '5 9 10 13 P:heavy']"
grep -qF 'P:heavy' <<<"$CONDUCTOR_GATES_DELIVER" || v12_bad="$v12_bad [lint constant lacks P:heavy]"
[ "$CONDUCTOR_GATES_OPERATE" = "1:fact 4 6" ] && [ "$CONDUCTOR_GATES_INCIDENT" = "1 5" ] \
  || v12_bad="$v12_bad [OPERATE or INCIDENT constant changed: '$CONDUCTOR_GATES_OPERATE' / '$CONDUCTOR_GATES_INCIDENT']"
v12_operate_row=$(printf '%s\n' "$v12_rows" | grep -E '^\| OPERATE \|')
grep -qF '`1:fact`' <<<"$v12_operate_row" || v12_bad="$v12_bad [OPERATE named member 1:fact absent from prose row]"
v12_incident_row=$(printf '%s\n' "$v12_rows" | grep -E '^\| INCIDENT \|')
grep -qF '`MITIGATE-ONLY`' <<<"$v12_incident_row" || v12_bad="$v12_bad [INCIDENT named member MITIGATE-ONLY absent from prose row]"

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
    grep -qxF "$line" <<<"$out" || missing="$missing [$line]"
  done < <(cut -f2 "$expected")
  [ -z "$missing" ] || v10b_bad="$v10b_bad [$case expected line(s) absent:$missing]"
  shift 2
  for member in "$@"; do
    grep -qxF "$member" <<<"$out" || v10b_bad="$v10b_bad [$case named member absent: $member]"
  done
  if [ "$case" != "metrics-split" ]; then
    # Both counted lines print only when non-zero. These corpora have no sibling
    # that is skipped or that shadows an in-file section, so a line here means
    # the zero case started printing.
    grep -q '^  sibling files ' <<<"$out" \
      && v10b_bad="$v10b_bad [$case prints a sibling-count line though its count is 0]"
  fi
  if [ "$case" = "metrics-split" ]; then
    # One lens per layout: the catches line is unordered, so each token is
    # checked on its own. Present: the seven layouts and the split, mixed and
    # single-file campaigns. Absent: everything that must not be read.
    lens_line=$(printf '%s\n' "$out" | grep '^  by lens:')
    for tok in bob ruby tessa percy xander ian dexter hank nina jackson scott sarah infile; do
      grep -qE "(^| )$tok=1( |$)" <<<"$lens_line" || v10b_bad="$v10b_bad [metrics-split catches-by-lens token absent: $tok=1]"
    done
    for tok in shadow orphan zerostate nohead otto; do
      grep -q "$tok=" <<<"$lens_line" && v10b_bad="$v10b_bad [metrics-split catches-by-lens token present: $tok= (must not be read)]"
    done
  fi
  if [ "$case" = "metrics-conductor" ]; then
    lens_line=$(printf '%s\n' "$out" | grep '^  rejected by lens:')
    for tok in "bob=1/1" "tessa=1/1" "ruby=1/1"; do
      grep -qF "$tok" <<<"$lens_line" || v10b_bad="$v10b_bad [metrics-conductor rejected-by-lens token absent: $tok]"
    done
    grep -q 'xander=' <<<"$lens_line" && v10b_bad="$v10b_bad [metrics-conductor reversed lens xander= present in rejected-by-lens line]"
  fi
}

v10b_run_case "metrics-conductor" 6 \
  "Wrong-override rate: 1/3 rejected findings later reversed (33%)" \
  "  rejected (judgment): 1 of 3"
v10b_run_case "metrics-vacuity" 1 \
  "Wrong-override rate: n/a (no rejected findings in campaigns with a conductor record)"
v10b_run_case "metrics-split" 16 \
  "Campaigns: 17 (17 STANDARD)" \
  "  sibling files shadowing an in-file section (in-file rows ignored): 2" \
  "Confirmed catches (Critical/High, disposition=fixed): 13" \
  "  sibling files skipped (no section heading): 3" \
  "Wrong-override rate: 1/1 rejected findings later reversed (100%)"
v10b_run_case "metrics-light" 4 \
  "Campaigns: 1 (1 LIGHT)" \
  "Catches per campaign by tier: LIGHT=1.0"

report "V10b" "$([ -z "$v10b_bad" ] && echo 0 || echo 1)" \
  "${v10b_bad:-metrics-conductor, metrics-vacuity, metrics-split and metrics-light: exit=0, expected lines present, rejected-by-lens tokens correct, named members present}"

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
v13_check "$gate_root/agents/WORKTREES.md" "### Per-campaign artifacts" "$L3" "decisions.md" "WORKTREES Per-campaign artifacts / decisions.md"
v13_check "$gate_root/agents/STATE.md" "### Directory convention" "$L3" "decisions.md" "STATE Directory convention / decisions.md"
v13_check "$gate_root/agents/PIPELINE.md" "## Output paths" "$L2" "decisions.md" "PIPELINE Output paths / decisions.md"
v13_check "$gate_root/commands/mozart.md" "### 6. Maintain all artifacts" "$L3" "decisions.md" "commands 6. Maintain all artifacts / decisions.md"
v13_check "$gate_root/README.md" "## What's in the box" "$L2" "decisions.md" "README What's in the box / decisions.md"
# (a2) the split layout's two sibling files at the same five sites. Dot-prefixed so a
# stray `ledger.md` substring elsewhere in the section cannot satisfy it.
for v13_sib in .ledger.md .conductor.md; do
  v13_check "$gate_root/agents/WORKTREES.md" "### Per-campaign artifacts" "$L3" "$v13_sib" "WORKTREES Per-campaign artifacts / $v13_sib"
  v13_check "$gate_root/agents/STATE.md" "### Directory convention" "$L3" "$v13_sib" "STATE Directory convention / $v13_sib"
  v13_check "$gate_root/agents/PIPELINE.md" "## Output paths" "$L2" "$v13_sib" "PIPELINE Output paths / $v13_sib"
  v13_check "$gate_root/commands/mozart.md" "### 6. Maintain all artifacts" "$L3" "$v13_sib" "commands 6. Maintain all artifacts / $v13_sib"
  v13_check "$gate_root/README.md" "## What's in the box" "$L2" "$v13_sib" "README What's in the box / $v13_sib"
done

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

[ "$v13_sites" -ge 30 ] || v13_bad="$v13_bad [scoped-site population $v13_sites < 30]"
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
grep -q 'nothing to aggregate' <<<"$v14_m_out" \
  && v14_bad="$v14_bad [metrics reported 'nothing to aggregate' under a spaced root]"
# The spaced FILE must reach the tally, not merely fail to crash the run: its
# two conductor rows are the ONLY rows in this corpus, so these counts are
# non-zero if and only if awk opened the spaced path intact.
v14_m_member='Conductor rows: check=1 adjudication=0 fact=1'
grep -qxF "$v14_m_member" <<<"$v14_m_out" \
  || v14_bad="$v14_bad [named member absent from metrics output: $v14_m_member]"

# Check F needs a file older than STALE_DAYS to have anything to report.
touch -t 200001010000 "$v14_spaced" 2>/dev/null
v14_l_out=$(bash "$gate_root/scripts/mozart-lint.sh" "$v14_root" 2>&1)
v14_l_rc=$?
[ "$v14_l_rc" -eq 1 ] || v14_bad="$v14_bad [lint exit=$v14_l_rc want 1 under a spaced root]"
grep -F 'LINT [stale-active]' <<<"$v14_l_out" | grep -qF 'deliver-spaced name.state.md' \
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
S2	agents/TEMPLATE-CONDUCTOR.md
S3	agents/STATE.md
S4	agents/STATE.md
S5	agents/TEMPLATE-STATE.md
S6	agents/TEMPLATE-STATE.md
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
S18	agents/TEMPLATE-STATE.md
S19	agents/hank.md
S21	agents/hank.md
M2	agents/harry.md
M4	agents/DELIVER.md
M7	agents/harry.md
MP	agents/mozart.md
JP	agents/jackson.md
S22a	agents/nina.md
S22b	agents/nina.md
S23	agents/DELIVER.md
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

[ "$v15_rows" -ge 28 ] || v15_bad="$v15_bad [registry has $v15_rows row(s), floor 28]"
# Braces are load-bearing on ${v15_dupes}: the message continues with an
# em-dash, and bash reads the multibyte character as part of the variable NAME
# without them, so under `set -u` the gate aborts with "unbound variable" on
# the very path it exists to report. Caught by control 1 producing no verdict
# at all rather than a FAIL -- a check that cannot print its own finding is
# indistinguishable from one that has nothing to report.
[ -z "$v15_dupes" ] || v15_bad="${v15_bad} [duplicate registry key(s): ${v15_dupes}— a duplicate preserves the row count while some other snippet goes unchecked]"
[ -z "$v15_only_registry" ] || v15_bad="${v15_bad} [registered with no snippet file: ${v15_only_registry}]"
[ -z "$v15_only_files" ] || v15_bad="${v15_bad} [snippet file(s) with no registry row, so never checked: ${v15_only_files}]"
grep -qxF "$(printf 'S3\tagents/STATE.md')" <<<"$v15_registry" \
  || v15_bad="$v15_bad [named member absent from the registry: S3 -> agents/STATE.md]"
for v15_nm in "S2	agents/TEMPLATE-CONDUCTOR.md" "S5	agents/TEMPLATE-STATE.md" "S6	agents/TEMPLATE-STATE.md" "S18	agents/TEMPLATE-STATE.md"; do
  grep -qxF "$v15_nm" <<<"$v15_registry" \
    || v15_bad="$v15_bad [named member absent from the registry: $(printf '%s' "$v15_nm" | tr '\t' ' ')]"
done

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
# a mechanism. D26 moved the number rather than the content.
#
# agents/nina.md's ceiling moved 31,523 -> 33,750 when the read rules were re-frozen as
# S22a/S22b plus a Bucket-members section (D27). The file grew because the frozen spans
# and the enumerated members are BOTH required and are deliberately not substitutes: a
# span that enumerated every member would need re-freezing whenever a provider ships a
# service, and members without the span leave the rule unfrozen. Reviewed content, so
# the raise is taken on the D21 rule - raise when the content that consumed the budget
# was reviewed, refuse when the raise is what makes an unreviewed edit fit.
#
# agents/OPERATE.md's ceiling is 14,991 per D21 of 2026-09-19-deliver-nina-cloud-
# persona (was 14,600). Two reviewed changes consumed the old budget: the HEAVY
# trigger widening, which is a live-pipeline defect fix independent of that
# campaign, and nina's four OPERATE sites. The file was first trimmed to 14,591 --
# 9 bytes -- rather than raised mid-edit, and the raise was then taken on its own
# merits afterwards. That ordering is the rule: RAISE when the content that
# consumed the budget was reviewed; REFUSE when the raise is what makes an
# unreviewed edit fit. A third raise here is not the answer -- the next campaign
# needing room in OPERATE.md carves it.
#
# Phase 8 of 2026-10-03-deliver-eval-efficiency-fixes: the 299-byte no-progress bullet
# (300 with its newline) is reviewed content, so the raises are taken on the D21 rule, each to
# the exact new size: agents/dick.md 23490 -> 23751 (+261, headroom was 39), agents/nina.md
# 33750 -> 33862 (+112, headroom was 188) and agents/DELIVER.md 58747 -> 58775 (+28, headroom
# was 73; the clause on the attempts-cap line is 28 bytes over it). agents/otto.md (21691 of
# 21700), agents/hank.md and agents/CONTEXT-BUDGET.md fit and are not raised.
#
# Phase 7 mid-build findings of the same campaign (F50-F56): the LIGHT re-check bullet at the
# per-phase gate, the HEAVY-surface and otto/nina ineligibility sentence at the head of stage 4,
# the surface-record wording in stage 8 and the codex r2 skip exclusion in stage 9 are reviewed
# content, so agents/DELIVER.md 58775 -> 59522 (+747, headroom was 0), to the exact new size.
# F63 (third fix commit): the one escalation-pass bullet in stage 8 is reviewed content, so agents/DELIVER.md
# 59522 -> 59692 (+170, headroom was 0), to the exact new size.
# Final round: the escalation record's claim form named in stage 8 (F65): agents/DELIVER.md 59692 -> 59830
# (+138, headroom was 0), to the exact new size.
# agents/mozart.md gained under 800 bytes and stays under its 55000 ceiling, which is NOT raised.
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
agents/mozart.md	55000
agents/INDEX.md	4200
agents/AUDIT.md	4700
agents/CONTEXT-BUDGET.md	1800
agents/DIAGNOSE.md	5566
agents/EVAL.md	6300
agents/OPERATE.md	14991
agents/INCIDENT.md	11700
agents/STATE.md	47146
agents/INTAKE.md	19900
agents/COUNTERPOINT.md	5400
agents/FLOWS.md	16800
agents/WORKTREES.md	18200
agents/TICKETS.md	24700
agents/DELIVER.md	59830
agents/hank.md	22300
agents/dick.md	23751
agents/otto.md	21700
agents/nina.md	33862
agents/TEMPLATE-STATE.md	4300
agents/TEMPLATE-LEDGER.md	700
agents/TEMPLATE-CONDUCTOR.md	900
agents/TEMPLATE-FLOW.md	1900
agents/TEMPLATE-REPORT.md	1500
V16_BUDGETS_EOF
)

v16_bad=""
v16_rows=$(printf '%s\n' "$v16_budgets" | grep -c .)
[ "$v16_rows" -ge 24 ] || v16_bad="$v16_bad [budget table has $v16_rows row(s), floor 24 = 13 content destinations + INDEX.md + mozart.md + hank/dick/otto/nina + 5 TEMPLATE files]"
grep -qxF "$(printf 'agents/mozart.md\t55000')" <<<"$v16_budgets" \
  || v16_bad="$v16_bad [named member absent from the budget table: agents/mozart.md 55000]"
v16_has_row() { # $1 = table, $2 = path: true when the FIRST field equals the path exactly
  printf '%s\n' "$1" | awk -F'\t' -v f="$2" '$1 == f { found = 1 } END { exit !found }'
}
v16_has_row "$v16_budgets" agents/DELIVER.md \
  || v16_bad="$v16_bad [named member absent from the budget table: agents/DELIVER.md]"
v16_without=$(printf '%s\n' "$v16_budgets" | grep -vE '^agents/DELIVER\.md')
v16_has_row "$v16_without" agents/DELIVER.md \
  && v16_bad="$v16_bad [self-test: the DELIVER.md row was deleted from a copy of the table and the member check still passed]"
v16_lookalike=$(printf 'docs/agents/DELIVER.md\t62400\n')
v16_has_row "$v16_lookalike" agents/DELIVER.md \
  && v16_bad="$v16_bad [self-test: docs/agents/DELIVER.md satisfied the exact-field member check]"

# Every template on disk or in the index needs a row, so a sixth template added
# without a ceiling fails here instead of growing unbudgeted. Derived, with a floor:
# an empty derivation (no git, no files) would otherwise pass for "all have rows".
v16_templates=$( { git ls-files 'agents/TEMPLATE-*.md' 2>/dev/null; ls agents/TEMPLATE-*.md 2>/dev/null; } | sort -u)
v16_ntemplates=$(printf '%s\n' "$v16_templates" | grep -c .)
[ "$v16_ntemplates" -ge 5 ] || v16_bad="$v16_bad [template population $v16_ntemplates < 5: agents/TEMPLATE-*.md not found]"
while IFS= read -r v16_t; do
  [ -n "$v16_t" ] || continue
  v16_has_row "$v16_budgets" "$v16_t" || v16_bad="$v16_bad [template without a budget row: $v16_t]"
done < <(printf '%s\n' "$v16_templates")
for v16_named in agents/TEMPLATE-STATE.md agents/TEMPLATE-FLOW.md agents/TEMPLATE-REPORT.md; do
  v16_has_row "$v16_budgets" "$v16_named" \
    || v16_bad="$v16_bad [named member absent from the budget table: $v16_named]"
done
# scott is not budgeted by this campaign (Decision 11): no scott file has a row.
printf '%s\n' "$v16_budgets" | awk -F'\t' '$1 ~ /scott/ { found = 1 } END { exit !found }' \
  && v16_bad="$v16_bad [named-absent member present: a scott row in the budget table]"

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
# V17 - the carve conservation self-test (2026-09-19-deliver-mozart-md-carve).
#
#   V17_carve_selftest  the gate's own 12-mutation self-test. Runs on a synthetic
#                       mktemp fixture and never reads the repo tree or any git
#                       history, so it is valid independently of the tree's state.
#                       A run reporting fewer than 12 mutations FAILS: the floor is
#                       what stops a stale implementation from satisfying this gate
#                       while C3 inverse and C3c go untested (F36/F43).
#
#   V17_carve_phase     RETIRED 2026-09-19 (D9 of 2026-09-19-deliver-nina-cloud-persona).
#                       It asserted POST-is-PRE-re-partitioned against a pinned
#                       PRE-carve baseline: a ONE-TIME MIGRATION PROOF, verified when
#                       the carve merged at 71024d1, and not re-provable once the
#                       carved files legitimately change. Every trigger-table row a
#                       later campaign adds lands INSIDE a mapped range, which fails
#                       `C3c within-range` (the range is permuted) and has NO escape
#                       hatch by design - additions.allow admits additions BETWEEN
#                       ranges only. Left standing the gate did not inconvenience the
#                       next edit, it forbade the entire class of edit the bundle
#                       exists to receive, so it could thereafter produce only false
#                       failures. What the carve proved stays proved.
#
#                       tests/carve/{carve-map.tsv,PHASE,phases.expected,additions.allow}
#                       are RETAINED as the audit trail this retirement rests on, and
#                       carve-map.tsv is additionally read by the STANDING V23_absence
#                       gate - do not tidy them away. V18/V20/V21/V22/V24 remain the
#                       bundle's standing invariants and are unaffected.
#
#                       Transferable lesson: a gate built to prove a migration must
#                       declare its lifetime when it is built. This one did not, and
#                       the campaign that wrote it never asked how it would behave on
#                       the first ordinary edit afterwards.
#
# python3 missing is a FAIL, never a skip. A gate that quietly disappears when its
# interpreter is absent is the vacuity case this suite exists to remove.
v17_script="$gate_root/scripts/check-carve-conservation.py"
if ! command -v python3 >/dev/null 2>&1; then
  report "V17_carve_selftest" 1 "python3 not found - the conservation gate cannot run (FAIL, not skip)"
elif [ ! -f "$v17_script" ]; then
  report "V17_carve_selftest" 1 "scripts/check-carve-conservation.py is missing"
else
  v17_st_out=$(python3 "$v17_script" --self-test --quiet 2>&1); v17_st_rc=$?
  v17_st_n=$(printf '%s\n' "$v17_st_out" | sed -n 's/.*carve_selftest *\([0-9]*\) of \([0-9]*\) mutations.*/\1 \2/p')
  v17_st_caught=${v17_st_n%% *}; v17_st_total=${v17_st_n##* }
  if [ "$v17_st_rc" -eq 0 ] && [ "${v17_st_caught:-0}" -ge 12 ] && [ "${v17_st_caught:-0}" = "${v17_st_total:-0}" ]; then
    report "V17_carve_selftest" 0 "$v17_st_caught of $v17_st_total mutations rejected, each by its named control (floor 12); positive control green"
  else
    report "V17_carve_selftest" 1 "self-test rc=$v17_st_rc caught=${v17_st_caught:-?}/${v17_st_total:-?} (floor 12): $(printf '%s' "$v17_st_out" | tail -3 | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# V25 - agents/nina.md still demands a source and a date, and still carries the
#       read-rule controls in the SHAPE that makes them controls.
#
# HONEST RESIDUAL, stated here rather than discovered later: this gate proves
# things about nina's FILE. It proves NOTHING about any finding she produces at
# runtime. A persona file can carry every rule below and still return a
# behavioural claim with no resolution behind it. The runtime discriminator is
# the reviewer rule in agents/DELIVER.md - a nina behavioural claim with no
# source and date attached is not a finding, it is an `[unresolved]` entry filed
# in the wrong section, and the reviewer returns it as such. Gating a real
# finding needs a findings-artifact linter that does not exist.
#
# WHY THE ASSERTIONS ARE SHAPED THE WAY THEY ARE. Floors and named members are
# necessary and NOT sufficient here, and this campaign proved it three separate
# times by watching a floor fail to discriminate:
#   - A10 asserts the value-kind list is EXACTLY seven, not >= 7. A floor passes
#     with `string` added as an eighth, which re-admits every argv leak the
#     removal of `string` was written to close.
#   - A4 asserts a named member PER BUCKET, not one global floor. A global floor
#     lets one bucket be emptied into another.
#   - A2 asserts the eight prefix families BY NAME, per provider, not `>= 4`.
#     Measured by mutation: the AWS families alone are four, so a `>= 4` floor
#     survives deleting any single family - the exact narrowing A2 exists to
#     catch. The floor could not meet its own stated rationale (D19).
# The general form: when the population is small and enumerable, assert the SET,
# not its cardinality.
#
# python3 missing is a FAIL, never a skip.
# ---------------------------------------------------------------------------
v25_target="$gate_root/agents/nina.md"
if ! command -v python3 >/dev/null 2>&1; then
  report "V25_nina_template" 1 "python3 not found - the nina template gate cannot run (FAIL, not skip)"
elif [ ! -f "$v25_target" ]; then
  report "V25_nina_template" 1 "agents/nina.md is missing - the persona this gate asserts over does not exist"
else
  v25_out=$(python3 - "$v25_target" <<'V25_PY' 2>&1
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
bad = []
def need(c, label):
    if not c: bad.append(label)

# A1 - the four conditions are a CONJUNCTION. A rewrite to "any of the following"
# satisfies every floor and every named member while inverting the control.
need("all four" in t and "conjunction, not a disjunction" in t, "A1 conjunction absent")
need("any of the following" not in t.lower(), "A1 disjunction rewrite present")

# A2 (D19) - the eight verb-prefix families, BY NAME, per provider.
FAMS = {"AWS": ["describe-*", "list-*", "get-*-policy", "get-*-configuration"],
        "Azure": ["az <svc> show", "az <svc> list"],
        "GCP": ["gcloud <svc> describe", "gcloud <svc> list"]}
fams = 0
for prov, members in FAMS.items():
    for m in members:
        if "`%s`" % m in t: fams += 1
        else: bad.append("A2 %s prefix family missing: %s" % (prov, m))
need(fams == 8, "A2 prefix families == 8 (got %d)" % fams)
# S22a wraps this sentence across two lines, so the probe normalises whitespace.
need("denied by default, and the denial is a finding" in re.sub(r"\s+", " ", t),
     "A2 default-deny sentence absent")
NAMED = ["aws sts get-caller-identity", "az account show", "gcloud config list account"]
named = sum(1 for c in NAMED if "`%s`" % c in t)
need(named >= 3, "A2 named-allowed-call floor (got %d, want >= 3)" % named)

# A3 - the projection form rule names all five prohibited forms.
for k, v in (("wildcard", "a wildcard `*`"), ("current-node", "the current-node `@`"),
             ("bare parent", "bare parent selector"), ("[] over object", "`[]` taken over an object"),
             ("--output text", "`--output text` over a non-scalar")):
    need(v in t, "A3 prohibited form missing: %s" % k)

# A4 - per-bucket floor AND one named member each. Bucket 3's floor counts
# provider-API members only: kubectl is struck from the allowed verbs entirely,
# so padding that bucket with verbs nina cannot invoke must not satisfy it.
BUCKETS = {1: (10, "sts:AssumeRole"), 2: (6, "ec2 describe-instance-attribute --attribute userData"),
           3: (14, "secretsmanager:GetSecretValue"), 4: (5, "gcloud pubsub subscriptions pull"),
           5: (8, "169.254.169.254")}
counts = {}
for b, (floor, member) in BUCKETS.items():
    # Bucket 5 is last in the members section, so without \*\* as a stop it swallows the
    # worked-examples block and reports a population it does not have.
    m = re.search(r'\*\*Bucket %d —.*?(?=\n\*\*Bucket |\n\*\*Worked |\n#### )' % b, t, re.S)
    if not m:
        bad.append("A4 bucket %d header absent" % b); counts[b] = 0; continue
    members = [x for x in re.findall(r'`([^`]+)`', m.group(0)) if not x.startswith("kubectl")]
    counts[b] = len(members)
    if len(members) < floor:
        bad.append("A4 bucket %d has %d provider-API member(s), floor %d" % (b, len(members), floor))
    if member not in members:
        bad.append("A4 bucket %d named member absent: %s" % (b, member))

# A5 - the five calls that defeated the verb-only version.
for c in ("lambda list-functions", "describe-launch-template-versions",
          "cloudformation describe-stacks", "ecs describe-tasks", "compute project-info describe"):
    need(c in t, "A5 defeating call absent: %s" % c)

# A6 / A7 - one-line deletions with a security consequence.
need("contaminated" in t and "do not write the findings artifact" in t, "A6 contamination stop absent")
need("do not relax under INCIDENT" in t, "A7 no-relaxation-under-INCIDENT absent")

# A8 - the enforcement half, and the comparison that makes the pin a pin.
need("tests/policy/nina-review-role.json" in t, "A8 review-role path absent")
need("operator-declared principal" in t, "A8 operator-declared-principal rule absent")
need("exact-ARN string equality, never substring" in t, "A8 exact-ARN comparison absent")
need("#### Review role" in t, "A8 anchor `#### Review role` absent")

# A9 - condition 2b's operative content: the redaction floor, the boundary rule
# the floor is a floor FOR, and the grammar the whole allowlist rests on.
RED = ["`Environment.Variables.*`", "`userData`", "`*Password*`", "`*Token*`",
       "`*Secret*`", "`*Credential*`", "`Condition.sts:ExternalId`", "connection strings"]
red = sum(1 for x in RED if x in t)
need(red >= 7, "A9 redaction path floor (got %d, want >= 7)" % red)
need("`Environment.Variables.*`" in t, "A9 named member Environment.Variables absent")
need("Sibling-structure rule" in t, "A9 sibling-structure rule absent")
need(r"^[A-Za-z_][A-Za-z0-9_]*(\[\]|\.[A-Za-z_][A-Za-z0-9_]*)*$" in t, "A9 grammar regex absent")

# A10 - EXACTLY seven value kinds, asserted as an equality. `string` must be absent.
m = re.search(r'closed set of exactly seven\*\*:\s*\*\*(.+?)\*\*', t)
if not m:
    bad.append("A10 value-kind list not found")
    kinds = []
else:
    kinds = [k.strip().strip('`') for k in m.group(1).split('·')]
    need(len(kinds) == 7, "A10 value kinds == 7 (got %d: %s)" % (len(kinds), kinds))
    need("ARN" in kinds, "A10 named member ARN absent")
    need("string" not in [k.lower() for k in kinds], "A10 'string' must not be a declarable kind")

# A11 - the wrapper, which the grammar regex does not constrain.
need("is the only admissible wrapper" in t, "A11 value() sole-admissible-wrapper rule absent")
for w in ("`json(`", "`yaml(`", "`flatten(`", "`list(`"):
    need(w in t, "A11 denied wrapper absent: %s" % w)

if bad:
    print("FAIL " + "; ".join(bad)); sys.exit(1)
print("PASS 11 assertions; conjunction; %d prefix families by name + %d named calls; "
      "5 prohibited projection forms; buckets 1-5 = %d/%d/%d/%d/%d provider-API members "
      "(floors 10/6/14/5/8), each with its named member; 5 defeating calls; contamination "
      "stop; no-INCIDENT-relaxation; review role + exact-ARN at `#### Review role`; "
      "%d redaction paths (floor 7) + sibling rule + grammar regex; value kinds == %d with "
      "'string' absent; value() sole gcloud wrapper"
      % (fams, named, counts[1], counts[2], counts[3], counts[4], counts[5], red, len(kinds)))
V25_PY
)
  v25_rc=$?
  if [ "$v25_rc" -eq 0 ]; then
    report "V25_nina_template" 0 "${v25_out#PASS }"
  else
    report "V25_nina_template" 1 "${v25_out#FAIL }"
  fi
fi

# ---------------------------------------------------------------------------
# V27 - portable grep and awk in the shipped scripts
#
# CI runs on GNU userland; the author's machine is BSD. A grep pattern that
# carries a backslash escape inside quotes is read by the shell as the two
# characters, and then grep decides what they mean: BSD grep -E reads a tab,
# GNU grep -E reads the letter t. V16 shipped exactly that and was green here
# and red in CI. The portable spelling is a pattern built by printf (or $'..').
# V27 rejects the next one, in single quotes or double quotes.
#
# The gate must not trip on its own text: the scan pattern is assembled from
# pieces below, and the planted self-test lines are written with printf.
# ---------------------------------------------------------------------------
v27_bs=$(printf '\\')
v27_esc="${v27_bs}${v27_bs}[tnrdswb]"
v27_flags="( +(-[A-Za-z0-9]+( +[0-9]+)?|--[a-z-]*(=[^ ]+)?))*"
v27_re="[ef]?grep${v27_flags} +('[^']*${v27_esc}|\"[^\"\$]*${v27_esc})"
v27_bad=""
v27_files=("$gate_root"/scripts/*.sh)
v27_scanned=${#v27_files[@]}
[ "$v27_scanned" -ge 4 ] || v27_bad="$v27_bad [only $v27_scanned script(s) under scripts/*.sh, floor 4]"
for v27_member in mozart-contract-gates.sh mozart-lint.sh lib-campaign.sh; do
  [ -f "$gate_root/scripts/$v27_member" ] || v27_bad="$v27_bad [named member absent from the scan: scripts/$v27_member]"
done
v27_hits=$(grep -nE "$v27_re" "${v27_files[@]}" 2>/dev/null || true)
[ -z "$v27_hits" ] || v27_bad="$v27_bad [raw escape in a grep pattern -- GNU and BSD read it differently, build it with printf: $(head -3 <<<"$v27_hits" | tr '\n' ' ')]"
v27_self=$(grep -cE "$v27_re" "$gatefile" || true)
[ "$v27_self" -eq 0 ] || v27_bad="$v27_bad [the gate file trips its own scan: $v27_self line(s)]"
if v27_tmp=$(mktemp -d); then
  printf "grep -q '^a%st'\n" "$v27_bs" > "$v27_tmp/single.sh"
  printf 'grep -qE "^a%sd+"\n' "$v27_bs" > "$v27_tmp/double.sh"
  printf "grep -m1 -E 'a%st'\n" "$v27_bs" > "$v27_tmp/digitflag.sh"
  printf "grep -A2 -E 'a%sd'\n" "$v27_bs" > "$v27_tmp/context.sh"
  printf "grep -m 1 -E 'a%st'\n" "$v27_bs" > "$v27_tmp/spacedarg.sh"
  printf "grep --color=never 'a%st'\n" "$v27_bs" > "$v27_tmp/longflag.sh"
  printf 'grep -E "it%ss %st"\n' "'" "$v27_bs" > "$v27_tmp/otherquote.sh"
  printf "grep -q '^a'\n" > "$v27_tmp/clean.sh"
  printf 'grep -E "it%ss a"\n' "'" > "$v27_tmp/cleanquote.sh"
  for v27_plant in single double digitflag context spacedarg longflag otherquote; do
    grep -qE "$v27_re" "$v27_tmp/$v27_plant.sh" || v27_bad="$v27_bad [self-test: planted $v27_plant raw escape was not caught]"
  done
  for v27_plant in clean cleanquote; do
    grep -qE "$v27_re" "$v27_tmp/$v27_plant.sh" && v27_bad="$v27_bad [self-test: a clean $v27_plant pattern was flagged]"
  done
  rm -rf "$v27_tmp"
else
  v27_bad="$v27_bad [mktemp failed -- the self-tests could not run]"
fi
report "V27_portable_grep" "$([ -z "$v27_bad" ] && echo 0 || echo 1)" \
  "${v27_bad:-no raw escape in a grep pattern across $v27_scanned script(s), gate file clean, seven planted shapes caught}"

# V27b scans awk programs inside single quotes after `awk ` and the bodies of
# heredocs whose delimiter contains AWK. A heredoc under any other delimiter is
# NOT scanned (a self-test below pins that); the floor on lint and the library
# turns a renamed delimiter into a failure instead of a silent skip.
# V27b - gawk-only constructs. CI's awk is mawk and the author's is
# one-true-awk; both lack these. Names are checked across the whole script;
# the regex-interval and three-argument match() checks apply to the extracted
# awk programs only, since shell grep -E patterns legitimately use {n}.
v27b_programs() { # $1 = script -> stdout: the text of every single-quoted awk program
  awk '
    inprog { q = index($0, "\047"); if (q) { print substr($0, 1, q - 1); inprog = 0 } else print; next }
    pend || index($0, "awk ") {
      line = $0
      if (!pend) line = substr($0, index($0, "awk "))
      q = index(line, "\047")
      if (!q) { pend = (substr($0, length($0)) == "\\"); next }
      pend = 0
      body = substr(line, q + 1)
      e = index(body, "\047")
      if (e) print substr(body, 1, e - 1); else { print body; inprog = 1 }
    }
  ' "$1"
}
v27b_heredocs() { # $1 = script -> stdout: the body of every heredoc whose delimiter names AWK
  awk '
    hd != "" { if ($0 == hd) hd = ""; else print; next }
    /<<\047?[A-Z_]*AWK[A-Z_]*\047?/ {
      hd = $0; sub(/^.*<</, "", hd); gsub(/\047/, "", hd); sub(/[ \t].*$/, "", hd)
    }
  ' "$1"
}
v27b_names='gensub\(|asorti?\(|strftime|systime|PROCINFO|IGNORECASE|BEGINFILE|ENDFILE'
v27b_prog_re='match\([^,()]*,[^,()]*,|\{[0-9]+(,[0-9]*)?\}'
v27b_check() { # $1 = script -> stdout: offending lines (empty when clean)
  grep -nE "$v27b_names" "$1"
  { v27b_programs "$1"; v27b_heredocs "$1"; } | grep -E "$v27b_prog_re"
}
v27b_bad=""
v27b_progs=0
for v27b_script in "$gate_root/scripts/mozart-lint.sh" "$gate_root/scripts/mozart-metrics.sh" "$gate_root/scripts/lib-campaign.sh"; do
  [ -f "$v27b_script" ] || { v27b_bad="$v27b_bad [named member absent: $v27b_script]"; continue; }
  v27b_n=$({ v27b_programs "$v27b_script"; v27b_heredocs "$v27b_script"; } | grep -c . || true)
  [ "$v27b_n" -ge 1 ] || v27b_bad="$v27b_bad [no awk program extracted from $(basename "$v27b_script") -- the extractor is blind]"
  v27b_progs=$((v27b_progs + v27b_n))
  case "$v27b_script" in
    */mozart-lint.sh|*/lib-campaign.sh)
      [ "$(v27b_heredocs "$v27b_script" | grep -c . || true)" -ge 1 ] \
        || v27b_bad="$v27b_bad [no awk heredoc body read from $(basename "$v27b_script") -- its delimiter must contain AWK or the program is unscanned]" ;;
  esac
  v27b_hit=$(v27b_check "$v27b_script")
  [ -z "$v27b_hit" ] || v27b_bad="$v27b_bad [gawk-only construct in $(basename "$v27b_script"): $(head -2 <<<"$v27b_hit" | tr '\n' ' ')]"
done
v27b_tmp=$(mktemp -d) || { v27b_bad="$v27b_bad [mktemp failed -- the self-tests could not run]"; v27b_tmp=/nonexistent-v27b; }
printf "awk 'BEGIN { print gensub(/a/, \"b\", \"g\") }'\n" > "$v27b_tmp/name.sh"
printf "awk '/a{2}/ { print }'\n" > "$v27b_tmp/interval.sh"
printf "awk '{ match(\$0, /x/, m) }'\n" > "$v27b_tmp/match3.sh"
printf "X=\$(cat <<'X_AWK_EOF'\n/a{2}/ { print }\nX_AWK_EOF\n)\n" > "$v27b_tmp/heredoc.sh"
printf "awk '{ print }'\n" > "$v27b_tmp/clean.sh"
printf "X=\$(cat <<'X_AWK_EOF'\nfunction f(s, m) { return match(s, /x/, m) }\nX_AWK_EOF\n)\n" > "$v27b_tmp/heredoc3.sh"
printf "X=\$(cat <<'X_PROG_EOF'\n/a{2}/ { print }\nX_PROG_EOF\n)\n" > "$v27b_tmp/heredoc-unnamed.sh"
printf "X=\$(cat <<'X_AWK_EOF' || true\n/a{2}/ { print }\nX_AWK_EOF\n)\n" > "$v27b_tmp/heredoc-ortrue.sh"
printf "IFS= read -r -d '' X <<'X_AWK_EOF' || true\n{ print }\nX_AWK_EOF\ngrep -E 'a{2}' f\n" > "$v27b_tmp/heredoc-ortrue-after.sh"
for v27b_plant in name interval match3 heredoc heredoc3 heredoc-ortrue; do
  [ -n "$(v27b_check "$v27b_tmp/$v27b_plant.sh")" ] || v27b_bad="$v27b_bad [self-test: planted $v27b_plant construct was not caught]"
done
[ -z "$(v27b_check "$v27b_tmp/heredoc-ortrue-after.sh")" ] || v27b_bad="$v27b_bad [self-test: a heredoc opener carrying || true was not closed at its delimiter -- the shell grep -E interval after it was scanned as awk]"
[ -z "$(v27b_check "$v27b_tmp/clean.sh")" ] || v27b_bad="$v27b_bad [self-test: a clean awk line was flagged]"
[ -z "$(v27b_check "$v27b_tmp/heredoc-unnamed.sh")" ] || v27b_bad="$v27b_bad [self-test: the documented limit changed -- a heredoc whose delimiter lacks AWK is now scanned; update the V27b comment]"
rm -rf "$v27b_tmp"
report "V27b_portable_awk" "$([ -z "$v27b_bad" ] && echo 0 || echo 1)" \
  "${v27b_bad:-no gawk-only construct in $v27b_progs awk program line(s) across lint, metrics and the library, planted self-tests caught}"

# ---------------------------------------------------------------------------
# V30_lib - scripts/lib-campaign.sh: the one place lint and metrics get their
# shared awk helpers and the sibling-file rule (phase 2a)
#
# Real scripts, real scratch copies. Library absent or empty is exit 3 with a
# named message (exit 2 stays "nothing to lint"); the library is found from
# the script's own absolutised path (relative path, other cwd, spaced path);
# sourcing it has no side effect; the two spellings of the sibling rule agree;
# a function defined twice cannot pass as a clean run; metrics reads a CRLF
# state file exactly as it reads the LF original. The derivation guard counts
# code lines, so the scripts cannot grow a private copy of the rule.
# ---------------------------------------------------------------------------
v30_repo=$(dirname "$(dirname "$gatefile")")
v30_corpus="$v30_repo/tests/fixtures/conductor/metrics-conductor"
v30_lib="$gate_root/scripts/lib-campaign.sh"
v30_bad=""
v30_tmp=$(mktemp -d) || { v30_bad="$v30_bad [mktemp failed -- the scratch copies could not be built]"; v30_tmp=/nonexistent-v30; }
v30_runs=0

for v30_s in mozart-lint mozart-metrics; do
  [ "$(grep -c 'lib-campaign\.sh' "$gate_root/scripts/$v30_s.sh")" -ge 1 ] || v30_bad="$v30_bad [$v30_s.sh does not name lib-campaign.sh]"
done

mkdir -p "$v30_tmp/absent/scripts" "$v30_tmp/empty/scripts"
cp "$gate_root"/scripts/mozart-lint.sh "$gate_root"/scripts/mozart-metrics.sh "$v30_tmp/absent/scripts/" || v30_bad="$v30_bad [cp of the scripts failed]"
cp "$gate_root"/scripts/mozart-lint.sh "$gate_root"/scripts/mozart-metrics.sh "$v30_tmp/empty/scripts/" || v30_bad="$v30_bad [cp of the scripts failed]"
: > "$v30_tmp/empty/scripts/lib-campaign.sh"
for v30_state in absent empty; do
  for v30_s in mozart-lint mozart-metrics; do
    v30_out=$(bash "$v30_tmp/$v30_state/scripts/$v30_s.sh" "$v30_corpus" 2>&1); v30_rc=$?
    v30_runs=$((v30_runs + 1))
    [ "$v30_rc" -eq 3 ] || v30_bad="$v30_bad [$v30_s with the library $v30_state: exit $v30_rc, want 3]"
    [ "$v30_out" = "$v30_s: scripts/lib-campaign.sh not found beside this script" ] \
      || v30_bad="$v30_bad [$v30_s with the library $v30_state: wrong message: $(head -1 <<<"$v30_out")]"
  done
done
[ "$v30_runs" -ge 4 ] || v30_bad="$v30_bad [absent/empty arm ran $v30_runs time(s), floor 4]"

mkdir -p "$v30_tmp/noplans"
for v30_s in mozart-lint mozart-metrics; do
  bash "$gate_root/scripts/$v30_s.sh" "$v30_tmp/noplans" >/dev/null 2>&1; v30_rc=$?
  [ "$v30_rc" -eq 2 ] || v30_bad="$v30_bad [CONTROL: $v30_s on a root with no plans dir: exit $v30_rc, want 2]"
done

mkdir -p "$v30_tmp/sp ace/scripts"
cp "$gate_root"/scripts/*.sh "$v30_tmp/sp ace/scripts/" || v30_bad="$v30_bad [cp to the spaced path failed]"
for v30_s in mozart-lint mozart-metrics; do
  v30_ref=$(bash "$gate_root/scripts/$v30_s.sh" "$v30_corpus" 2>&1; echo "rc=$?")
  v30_rel=$(cd "$v30_tmp/sp ace" && bash "scripts/$v30_s.sh" "$v30_corpus" 2>&1; echo "rc=$?")
  v30_spc=$(cd / && bash "$v30_tmp/sp ace/scripts/$v30_s.sh" "$v30_corpus" 2>&1; echo "rc=$?")
  case "$v30_ref" in *"not found beside"*|"") v30_bad="$v30_bad [$v30_s: the reference run did not run]" ;; esac
  [ "$v30_rel" = "$v30_ref" ] || v30_bad="$v30_bad [$v30_s run by a relative path from another cwd differs from the reference run]"
  [ "$v30_spc" = "$v30_ref" ] || v30_bad="$v30_bad [$v30_s run from a path containing a space differs from the reference run]"
done

mkdir -p "$v30_tmp/crlf"
cp -R "$v30_corpus/." "$v30_tmp/crlf/" || v30_bad="$v30_bad [cp of the metrics-conductor corpus failed]"
v30_crlf_n=0
while IFS= read -r -d '' v30_f; do
  awk '{ print $0 "\r" }' "$v30_f" > "$v30_f.crlf" && mv "$v30_f.crlf" "$v30_f" || v30_bad="$v30_bad [CRLF conversion failed]"
  v30_crlf_n=$((v30_crlf_n + 1))
done < <(find "$v30_tmp/crlf" -name '*.state.md' -print0)
[ "$v30_crlf_n" -ge 1 ] || v30_bad="$v30_bad [no state file found to convert to CRLF]"
v30_lf=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v30_corpus" 2>&1; echo "rc=$?")
v30_cr=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v30_tmp/crlf" 2>&1; echo "rc=$?")
grep -qxF '== mozart pipeline economics ==' <<<"$v30_lf" || v30_bad="$v30_bad [the LF metrics run printed no table]"
[ "$v30_cr" = "$v30_lf" ] || v30_bad="$v30_bad [metrics on a CRLF copy of metrics-conductor differs from the LF original]"

if [ -s "$v30_lib" ]; then
  mkdir -p "$v30_tmp/dup/scripts"
  cp "$gate_root"/scripts/mozart-lint.sh "$gate_root"/scripts/mozart-metrics.sh "$v30_tmp/dup/scripts/"
  awk '{ print } /CAMPAIGN_AWK_LIB <</ { print "function trim(s) { return s }" }' "$v30_lib" > "$v30_tmp/dup/scripts/lib-campaign.sh"
  [ "$(grep -c '^function trim(s) { return s }$' "$v30_tmp/dup/scripts/lib-campaign.sh")" -eq 1 ] || v30_bad="$v30_bad [the duplicate-function plant did not land]"
  for v30_s in mozart-lint mozart-metrics; do
    v30_out=$(bash "$v30_tmp/dup/scripts/$v30_s.sh" "$v30_corpus" 2>/dev/null); v30_rc=$?
    [ "$v30_rc" -eq 3 ] || v30_bad="$v30_bad [$v30_s with a function defined twice: exit $v30_rc, want 3 (an awk failure is not 'nothing to lint' or 'findings')]"
    grep -qE 'pipeline economics|^LINT ' <<<"$v30_out" && v30_bad="$v30_bad [$v30_s printed results with a function defined twice]"
  done
fi

# A library cut off mid-heredoc is non-empty, so the empty check alone passes it.
# Two cut points: inside the CAMPAIGN_AWK_LIB heredoc, and after it with only the
# sentinel missing.
if [ -s "$v30_lib" ]; then
  v30_cut_at=$(grep -n 'function split_cells' "$v30_lib" | head -1 | cut -d: -f1)
  v30_end_at=$(grep -n '^CAMPAIGN_LIB_END=1$' "$v30_lib" | head -1 | cut -d: -f1)
  { [ -n "$v30_cut_at" ] && [ -n "$v30_end_at" ]; } || v30_bad="$v30_bad [truncation arm: cut points not found in the library (split_cells '$v30_cut_at', sentinel '$v30_end_at')]"
  v30_trunc_runs=0
  for v30_cut in "mid-heredoc:$((${v30_cut_at:-2} - 1))" "no-sentinel:$((${v30_end_at:-2} - 1))"; do
    v30_name=${v30_cut%%:*}
    mkdir -p "$v30_tmp/trunc-$v30_name/scripts"
    cp "$gate_root"/scripts/mozart-lint.sh "$gate_root"/scripts/mozart-metrics.sh "$v30_tmp/trunc-$v30_name/scripts/"
    head -n "${v30_cut##*:}" "$v30_lib" > "$v30_tmp/trunc-$v30_name/scripts/lib-campaign.sh"
    [ -s "$v30_tmp/trunc-$v30_name/scripts/lib-campaign.sh" ] || v30_bad="$v30_bad [truncation arm $v30_name: the truncated copy is empty, so it tests the empty case]"
    for v30_s in mozart-lint mozart-metrics; do
      v30_out=$(bash "$v30_tmp/trunc-$v30_name/scripts/$v30_s.sh" "$v30_corpus" 2>&1); v30_rc=$?
      v30_trunc_runs=$((v30_trunc_runs + 1))
      [ "$v30_rc" -eq 3 ] || v30_bad="$v30_bad [$v30_s with a library truncated ($v30_name): exit $v30_rc, want 3]"
      [ "$v30_out" = "$v30_s: scripts/lib-campaign.sh not found beside this script" ] \
        || v30_bad="$v30_bad [$v30_s with a library truncated ($v30_name): wrong output: $(head -1 <<<"$v30_out")]"
    done
  done
  [ "$v30_trunc_runs" -ge 4 ] || v30_bad="$v30_bad [truncation arm ran $v30_trunc_runs time(s), floor 4]"
fi

if [ -s "$v30_lib" ]; then
  v30_src=$(bash -c 'a=$-; . "$1"; . "$1"; [ "$a" = "$-" ] && echo same-flags' _ "$v30_lib" 2>&1)
  if [ -x /bin/bash ]; then
    v30_sys=$(/bin/bash -c '. "$1"; [ -n "$CAMPAIGN_AWK_LIB" ] && echo loaded' _ "$v30_lib" 2>&1)
    [ "$v30_sys" = "loaded" ] || v30_bad="$v30_bad [the system /bin/bash cannot source the library (stock macOS bash 3.2 cannot parse a command substitution holding an unpaired backtick): $v30_sys]"
  fi
  v30_srcu=$(bash -uc 'a=$-; . "$1"; . "$1"; [ "$a" = "$-" ] && echo same-flags' _ "$v30_lib" 2>&1)
  [ "$v30_src" = "same-flags" ] || v30_bad="$v30_bad [sourcing the library printed output or changed shell flags: $v30_src]"
  [ "$v30_srcu" = "same-flags" ] || v30_bad="$v30_bad [sourcing the library under set -u printed output or changed shell flags: $v30_srcu]"
  v30_agree=0
  for v30_case in "/a b/p/x.state.md" "x.state.md" "/p/2026-10-03-s.state.md"; do
    for v30_kind in ledger conductor; do
      v30_sh=$(bash -c '. "$1"; campaign_sibling "$2" "$3"' _ "$v30_lib" "$v30_case" "$v30_kind")
      v30_aw=$(bash -c '. "$1"; awk "$CAMPAIGN_AWK_LIB"$'"'"'\nBEGIN { printf "%s", campaign_sibling_awk(ARGV[1], ARGV[2]) }'"'"' "$2" "$3"' _ "$v30_lib" "$v30_case" "$v30_kind")
      [ -n "$v30_sh" ] && [ "$v30_sh" = "$v30_aw" ] && [ "$v30_sh" = "${v30_case%.state.md}.$v30_kind.md" ] \
        && v30_agree=$((v30_agree + 1)) \
        || v30_bad="$v30_bad [sibling of '$v30_case' ($v30_kind): shell='$v30_sh' awk='$v30_aw']"
    done
  done
  [ "$v30_agree" -eq 6 ] || v30_bad="$v30_bad [sibling agreement: $v30_agree of 6 cases]"
  v30_prog='BEGIN { printf "[%s][%s]", trim("  a b \r"), normhdr(" **Kind**`\r") }'
  v30_trim=$( . "$v30_lib"; awk "$CAMPAIGN_AWK_LIB"$'\n'"$v30_prog" </dev/null )
  [ "$v30_trim" = "[a b][kind]" ] || v30_bad="$v30_bad [library trim/normhdr do not strip a carriage return: '$v30_trim', want '[a b][kind]']"
  v30_non=$(bash -c '. "$1"; campaign_sibling "$2" ledger; echo "rc=$?"' _ "$v30_lib" "/p/not-a-state-file.md")
  [ "$v30_non" = "rc=1" ] || v30_bad="$v30_bad [campaign_sibling on a non-state path: '$v30_non', want empty output and rc=1]"
else
  v30_bad="$v30_bad [scripts/lib-campaign.sh missing or empty -- sourcing and sibling arms could not run]"
fi

# The scripts themselves must parse under the system bash too: stock macOS ships
# 3.2, which cannot parse a command substitution whose heredoc body holds an
# unpaired backtick (lint keeps its awk in one). Syntax check only.
if [ -x /bin/bash ]; then
  for v30_s in mozart-lint mozart-metrics; do
    v30_syn=$(/bin/bash -n "$gate_root/scripts/$v30_s.sh" 2>&1) \
      || v30_bad="$v30_bad [$v30_s.sh does not parse under /bin/bash: $(head -1 <<<"$v30_syn")]"
  done
fi

v30_code_lines() { grep -vE '^[[:space:]]*#' "$1"; }
v30_sib_re='\.(ledger|conductor)\.md'
v30_strip_re='basename[^|]*\.state\.md|%+\.state\.md|sub\(.*state\.md|sed .*state\.md|basename -s'
for v30_s in mozart-lint mozart-metrics; do
  v30_n=$(v30_code_lines "$gate_root/scripts/$v30_s.sh" | grep -cE "$v30_sib_re" || true)
  [ "$v30_n" -eq 0 ] || v30_bad="$v30_bad [$v30_s.sh derives a sibling path in $v30_n code line(s): the rule lives in the library]"
done
v30_lint_strips=$(v30_code_lines "$gate_root/scripts/mozart-lint.sh" | grep -cE "$v30_strip_re" || true)
v30_lint_basename=$(v30_code_lines "$gate_root/scripts/mozart-lint.sh" | grep -cE 'basename "\$f" \.state\.md' || true)
v30_lint_percent=$(v30_code_lines "$gate_root/scripts/mozart-lint.sh" | grep -cF '${f%.state.md}.decisions.md' || true)
v30_metrics_strips=$(v30_code_lines "$gate_root/scripts/mozart-metrics.sh" | grep -cE "$v30_strip_re" || true)
{ [ "$v30_lint_strips" -eq 3 ] && [ "$v30_lint_basename" -eq 2 ] && [ "$v30_lint_percent" -eq 1 ]; } \
  || v30_bad="$v30_bad [mozart-lint.sh .state.md strips: $v30_lint_strips total ($v30_lint_basename basename, $v30_lint_percent decisions-log), want exactly 3 (2, 1) -- a fourth is a new derivation]"
[ "$v30_metrics_strips" -eq 0 ] || v30_bad="$v30_bad [mozart-metrics.sh strips .state.md in $v30_metrics_strips code line(s), want 0]"
printf '%s\n' "x=\"\${f%.ledger.md}\"" > "$v30_tmp/plant-code.sh"
printf '%s\n' "# x=\"\${f%.ledger.md}\"" > "$v30_tmp/plant-comment.sh"
[ "$(v30_code_lines "$v30_tmp/plant-code.sh" | grep -cE "$v30_sib_re" || true)" -eq 1 ] || v30_bad="$v30_bad [self-test: a sibling derivation in a code line was not caught]"
[ "$(v30_code_lines "$v30_tmp/plant-comment.sh" | grep -cE "$v30_sib_re" || true)" -eq 0 ] || v30_bad="$v30_bad [self-test: a comment line was flagged]"

rm -rf "$v30_tmp"
report "V30_lib" "$([ -z "$v30_bad" ] && echo 0 || echo 1)" \
  "${v30_bad:-library absent/empty exit 3 ($v30_runs runs), cwd/spaced paths, CRLF metrics equals LF, duplicate function not a clean run, sibling spellings agree, lint has $v30_lint_strips allow-listed .state.md strips, metrics $v30_metrics_strips}"

# ---------------------------------------------------------------------------
# V30_layout_agreement - one campaign, three layouts, one verdict (phase 2b)
#
# The same campaign is built three ways (everything in the state file; ledger
# and conductor record in sibling files; ledger in the state file and conductor
# record in a sibling) and run through lint and metrics. Each script must give
# the same answer in all three layouts, and the answer must not be empty: a
# layout the scripts silently failed to read would otherwise agree with itself
# by reading nothing. The sibling rule exists in two spellings (shell for lint,
# awk for metrics); this is the behavioural test that they point at the same file.
# ---------------------------------------------------------------------------
v32_bad=""
v32_tmp=$(mktemp -d) || { v32_bad="$v32_bad [mktemp failed -- the layouts could not be built]"; v32_tmp=/nonexistent-v32; }
v32_slug=2099-09-30-deliver-agree
# `read`, not $(cat <<EOF): bash 3.2 cannot parse a command substitution whose
# heredoc body holds an unpaired quote or backtick.
IFS= read -r -d '' v32_cond <<'V32_COND_EOF' || true
## Conductor record
| id | kind | claim | links | source | control (command -> observed) | written-to |
|----|------|-------|-------|--------|-------------------------------|------------|
| CR1 | check | codex on diff raised nothing open | 9 | bash t.sh 2026-09-01T00:00Z | bash t.sh -> exit 0 | n/a |
| CR2 | adjudication | the F1 claim does not reproduce | F1 | bash repro.sh 2026-09-01T00:05Z | bash repro.sh -> no repro | n/a |
| CR3 | fact | the upstream API is unversioned | - | doc unverified |  | n/a |
V32_COND_EOF
IFS= read -r -d '' v32_led <<'V32_LED_EOF' || true
## Findings ledger
| id | stage | lens | severity | disposition | note |
|----|-------|------|----------|-------------|------|
| F1 | 4-plan-review | bob | Medium | rejected | claim does not reproduce |
| F2 | 9-codex-r2 | hank | High | fixed (def5678) | reverses F1 - a third source showed it |
| F3 | 4-plan-review | ruby | Medium | rejected | no adjudication row |
V32_LED_EOF
v32_head() { printf '%s\n' "# Pipeline state: $v32_slug" '' '**Last updated**: 2026-09-17T00:00Z' \
  '**Status**: CAMPAIGN COMPLETE — SHIPPED' '**Flow**: FULL' '**Tier**: STANDARD' '**Context**: BROWNFIELD' \
  '**Mode**: AUTONOMOUS' '' '## Stage progress' '- [x] 2b. Constraints — skipped: no trigger' \
  '- [x] 9. Codex on diff — 2026-09-02T00:00Z'; }
for v32_layout in single split mixed; do
  v32_dir="$v32_tmp/$v32_layout/.mozart/plans/finished"
  mkdir -p "$v32_dir" || v32_bad="$v32_bad [mkdir failed]"
  case "$v32_layout" in
    single) { v32_head; printf '\n%s\n\n%s\n' "$v32_cond" "$v32_led"; } > "$v32_dir/$v32_slug.state.md" ;;
    split)  v32_head > "$v32_dir/$v32_slug.state.md"
            printf '# Conductor record\n\n%s\n' "$v32_cond" > "$v32_dir/$v32_slug.conductor.md"
            printf '# Findings ledger\n\n%s\n' "$v32_led" > "$v32_dir/$v32_slug.ledger.md" ;;
    mixed)  { v32_head; printf '\n%s\n' "$v32_led"; } > "$v32_dir/$v32_slug.state.md"
            printf '# Conductor record\n\n%s\n' "$v32_cond" > "$v32_dir/$v32_slug.conductor.md" ;;
  esac
done
v32_ref_lint=""; v32_ref_metrics=""
for v32_layout in single split mixed; do
  v32_l=$(MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 MOZART_LINT_LENS_SINCE="$gate_lens" bash "$gate_root/scripts/mozart-lint.sh" "$v32_tmp/$v32_layout" 2>&1 | sed "s|$v32_tmp/$v32_layout||g"; echo "rc=${PIPESTATUS[0]}")
  v32_m=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v32_tmp/$v32_layout" 2>&1; echo "rc=$?")
  if [ "$v32_layout" = single ]; then
    v32_ref_lint=$v32_l; v32_ref_metrics=$v32_m
    grep -qF "conductor-unlinked" <<<"$v32_l" && grep -qF "— F3:" <<<"$v32_l" \
      || v32_bad="$v32_bad [single-file reference lint run did not report the unadjudicated F3: $(head -3 <<<"$v32_l")]"
    grep -qxF "Wrong-override rate: 1/2 rejected findings later reversed (50%)" <<<"$v32_m" \
      || v32_bad="$v32_bad [single-file reference metrics run lacks the wrong-override line]"
    grep -qxF "Conductor rows: check=1 adjudication=1 fact=1" <<<"$v32_m" \
      || v32_bad="$v32_bad [single-file reference metrics run lacks the conductor-rows line]"
  else
    [ "$v32_l" = "$v32_ref_lint" ] || v32_bad="$v32_bad [lint differs between the single-file and $v32_layout layouts]"
    [ "$v32_m" = "$v32_ref_metrics" ] || v32_bad="$v32_bad [metrics differs between the single-file and $v32_layout layouts]"
  fi
done
rm -rf "$v32_tmp"
report "V30_layout_agreement" "$([ -z "$v32_bad" ] && echo 0 || echo 1)" \
  "${v32_bad:-lint and metrics give the same verdict on one campaign built single-file, split and mixed (each verdict non-empty)}"

# ---------------------------------------------------------------------------
# V33_templates - a raw copy of each state template is a clean campaign (phase 3)
#
# The skeletons moved out of agents/STATE.md into agents/TEMPLATE-*.md, which the
# conductor copies at intake. Two things can go wrong with that move and neither is
# visible to a text gate: a template header drifts from what the scripts parse, or a
# placeholder in a template is counted as a real row or a real declaration. So the
# test is behavioural: build a campaign from RAW copies, run both scripts, and
# require that nothing is read from it. The raw copies are built here at gate time,
# not committed as fixtures, because a committed copy would be a second copy of the
# template that could drift from the first and keep passing.
#
# Two controls show the assertions can fail for the right reason: a conductor
# header with one column dropped must produce a conductor-row finding, and a
# Paths declaration that names a real path with no file there must produce a
# findings-ledger-missing finding. Without them, "no finding" could mean the
# scripts looked at nothing.
# ---------------------------------------------------------------------------
v33_bad=""
v33_tmp=$(mktemp -d) || { v33_bad="$v33_bad [mktemp failed -- the raw campaigns could not be built]"; v33_tmp=/nonexistent-v33; }
v33_slug=2099-09-30-deliver-raw
# A fresh campaign starts with nothing done. Lint flags only some ticks (a ticked stage 5 against
# "not yet run"), so the template is also read directly: no done or skipped mark, and a
# non-empty population of unticked lines so an emptied file cannot pass.
v33_ticked=$(grep -cE '^- \[[x-]\] ' "$gate_root/agents/TEMPLATE-STATE.md")
v33_unticked=$(grep -cE '^- \[ \] ' "$gate_root/agents/TEMPLATE-STATE.md")
[ "$v33_ticked" = "0" ] && [ "$v33_unticked" -ge 15 ] \
  || v33_bad="$v33_bad [TEMPLATE-STATE.md has $v33_ticked ticked line(s) (want 0) and $v33_unticked unticked (floor 15): a fresh campaign must start with nothing done]"
v33_build() { # $1 = root: raw copies of the three templates in active/
  mkdir -p "$1/.mozart/plans/active" || return 1
  cp "$gate_root/agents/TEMPLATE-STATE.md" "$1/.mozart/plans/active/$v33_slug.state.md" || return 1
  cp "$gate_root/agents/TEMPLATE-LEDGER.md" "$1/.mozart/plans/active/$v33_slug.ledger.md" || return 1
  cp "$gate_root/agents/TEMPLATE-CONDUCTOR.md" "$1/.mozart/plans/active/$v33_slug.conductor.md" || return 1
}
v33_lint() { MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 MOZART_LINT_LENS_SINCE="$gate_lens" bash "$gate_root/scripts/mozart-lint.sh" "$1" 2>&1; }
v33_count() { printf '%s\n' "$1" | grep -c "$2" ; }
v33_raw="$v33_tmp/raw"
if v33_build "$v33_raw"; then
  v33_out=$(v33_lint "$v33_raw")
  grep -qF "conductor adoption date overridden: 2099-06-01" <<<"$v33_out" \
    || v33_bad="$v33_bad [lint did not run on the raw copies: $(head -2 <<<"$v33_out" | tr '\n' ' ')]"
  # The adoption-date line above shows lint ran. A raw copy is a clean campaign, so any
  # LINT line (a tick left in the skeleton, a placeholder read as a declaration) fails.
  grep -q '^mozart-lint: clean' <<<"$v33_out" \
    || v33_bad="$v33_bad [a raw template trio does not lint clean: $(printf '%s' "$v33_out" | grep '^LINT' | head -3 | tr '\n' ' ')]"
  [ "$(v33_count "$v33_out" '^LINT \[split-layout\]')" = "0" ] \
    || v33_bad="$v33_bad [a raw template trio emits split-layout: a placeholder was read as a declaration]"
  [ "$(v33_count "$v33_out" '^LINT \[conductor-row\]')" = "0" ] \
    || v33_bad="$v33_bad [a raw template trio emits conductor-row: the template header does not resolve]"
  v33_m=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v33_raw" 2>&1; echo "rc=$?")
  grep -qxF "rc=2" <<<"$v33_m" \
    || v33_bad="$v33_bad [metrics on the raw trio did not exit 2: $(printf '%s' "$v33_m" | tr '\n' ' ')]"
  grep -qF "no findings-ledger data yet" <<<"$v33_m" \
    || v33_bad="$v33_bad [metrics on the raw trio read rows from a template]"
  # The Tier pipe-list is not a tier: one real finding row makes metrics print its tier line.
  printf '%s\n' '| F1 | 4-plan-review | bob | High | fixed (plan r2) | x |' >> "$v33_raw/.mozart/plans/active/$v33_slug.ledger.md"
  v33_m=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v33_raw" 2>&1)
  grep -qxF "Campaigns: 1 (1 UNTIERED)" <<<"$v33_m" \
    || v33_bad="$v33_bad [the template Tier pipe-list was classified as a tier: $(grep -m1 '^Campaigns:' <<<"$v33_m")]"
else
  v33_bad="$v33_bad [the raw trio could not be built -- a template is missing or unreadable]"
fi
# The state template alone, no siblings beside it: its two Paths lines must be placeholders,
# not declarations, or a campaign that never splits would be reported as missing its siblings.
v33_alone="$v33_tmp/alone"
if mkdir -p "$v33_alone/.mozart/plans/active" \
   && cp "$gate_root/agents/TEMPLATE-STATE.md" "$v33_alone/.mozart/plans/active/$v33_slug.state.md"; then
  [ "$(v33_count "$(v33_lint "$v33_alone")" '^LINT \[split-layout\]')" = "0" ] \
    || v33_bad="$v33_bad [the state template alone emits split-layout: its Findings ledger or Conductor record line is a declaration, not a placeholder]"
else
  v33_bad="$v33_bad [the state-template-alone campaign could not be built]"
fi
# Control 1: drop the last column from the conductor header only.
v33_mut="$v33_tmp/mut1"
if v33_build "$v33_mut"; then
  awk '/^\| id \| kind \| claim/ { sub(/ \| written-to \|[ ]*$/, " |") } { print }' \
    "$gate_root/agents/TEMPLATE-CONDUCTOR.md" > "$v33_mut/.mozart/plans/active/$v33_slug.conductor.md"
  [ "$(v33_count "$(v33_lint "$v33_mut")" '^LINT \[conductor-row\]')" -ge 1 ] \
    || v33_bad="$v33_bad [control failed: a conductor header missing a column did not produce conductor-row]"
fi
# Control 2: a real declaration with no file behind it.
v33_mut="$v33_tmp/mut2"
if v33_build "$v33_mut"; then
  awk -v p=".mozart/plans/active/$v33_slug.ledger.md" '/^- Findings ledger: / { print "- Findings ledger: " p; next } { print }' \
    "$gate_root/agents/TEMPLATE-STATE.md" > "$v33_mut/.mozart/plans/active/$v33_slug.state.md"
  rm -f "$v33_mut/.mozart/plans/active/$v33_slug.ledger.md"
  v33_l=$(v33_lint "$v33_mut")
  grep -F 'LINT [split-layout]' <<<"$v33_l" | grep -qF 'findings-ledger-missing' \
    || v33_bad="$v33_bad [control failed: a real Findings ledger declaration with no file did not produce findings-ledger-missing]"
fi
rm -rf "$v33_tmp"

# No duplicate skeleton: the anchors and both table headers each live in exactly one
# agents/*.md file, and it is the template. A copy left behind in STATE.md would be a
# second skeleton that drifts, and V15 counts per target so it would not see it.
v33_only() { # $1 = fixed string, $2 = file that must hold the only copy
  local files
  files=$(grep -lF -- "$1" "$gate_root"/agents/*.md 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')
  [ "$files" = "$2 " ] || v33_bad="$v33_bad [skeleton line '$1' is in: ${files:-nowhere} (want only $2)]"
}
v33_only '**Last updated**: <ISO timestamp>' TEMPLATE-STATE.md
v33_only '| id | stage | lens | severity | disposition | note |' TEMPLATE-LEDGER.md
v33_only '| id | kind | claim | links | source | control (command -> observed) | written-to |' TEMPLATE-CONDUCTOR.md
for v33_h in '^## Paths$' '^## Stage progress$' '^## Iteration counters$'; do
  [ "$(grep -c "$v33_h" "$gate_root/agents/STATE.md")" = "0" ] \
    || v33_bad="$v33_bad [agents/STATE.md still carries a skeleton heading matching $v33_h]"
done
report "V33_templates" "$([ -z "$v33_bad" ] && echo 0 || echo 1)" \
  "${v33_bad:-raw TEMPLATE-STATE/LEDGER/CONDUCTOR copies: no split-layout, no conductor-row, metrics exit 2, Tier pipe-list not a tier; both controls fire; each skeleton line lives only in its template}"

# ---------------------------------------------------------------------------
# V33_layout_prose - the split layout is written down once, and the sites that list
# a campaign's artifacts or the state_md5 key say so (phase 3)
# ---------------------------------------------------------------------------
v34_bad=""
# Every phrase below is pinned inside the section that owns it (v3_region: first heading
# match to the next heading of the stated rank, HTML-comment lines dropped), not by a
# file-wide count or first match that a comment or another paragraph could satisfy.
v34_sec() { # $1 = file, $2 = start ERE, $3 = end ERE -> region on stdout; empty when the start anchor is gone
  local r
  r=$(v3_region "$gate_root/$1" "$2" "$3")
  case "$r" in __REGION_START_NOT_FOUND__*) return 0 ;; esac
  printf '%s\n' "$r"
}
v34_closeout=$(v34_sec agents/DELIVER.md '^#### Campaign closeout' '^#### |^### |^## ')
v34_resume=$(v34_sec agents/STATE.md '^### Resume from a state file' '^### |^## ')
v34_detect=$(v34_sec agents/STATE.md '^### Detecting an in-progress run at intake' '^### |^## ')
v34_ledger=$(v34_sec docs/EVAL.md '^## The ledger' '^## ')
v34_mech=$(v34_sec docs/EVAL.md '^## Mechanical metrics' '^## ')
for v34_pair in "closeout:$v34_closeout" "resume:$v34_resume" "detect:$v34_detect" "ledger:$v34_ledger" "mech:$v34_mech"; do
  [ "$(printf '%s\n' "${v34_pair#*:}" | grep -c .)" -ge 3 ] \
    || v34_bad="$v34_bad [section '${v34_pair%%:*}' is missing or has under 3 lines: its anchor was renamed]"
done
# Closeout covers the siblings, in the two bullets that name state-file artifacts.
for v34_pat in 'reachable from HEAD' 'Paths block lists the ACTUAL artifact paths'; do
  v34_line=$(grep -m1 -F -- "$v34_pat" <<<"$v34_closeout")
  [ -n "$v34_line" ] || { v34_bad="$v34_bad [DELIVER closeout bullet absent from its section: $v34_pat]"; continue; }
  for v34_sib in .ledger.md .conductor.md; do
    grep -qF -- "$v34_sib" <<<"$v34_line" \
      || v34_bad="$v34_bad [DELIVER closeout bullet '$v34_pat' does not name $v34_sib]"
  done
done
# Resume rule present once, in the resume section; category count word agrees with the list.
[ "$(printf '%s\n' "$v34_resume" | grep -c 'never split on resume')" = "1" ] \
  || v34_bad="$v34_bad [agents/STATE.md's resume section must state 'never split on resume' exactly once]"
[ "$(grep -c 'never split on resume' "$gate_root/agents/STATE.md")" = "1" ] \
  || v34_bad="$v34_bad ['never split on resume' appears other than once in agents/STATE.md]"
v34_sent=$(grep -m1 -F 'finding categories:' <<<"$v34_detect")
v34_word=$(printf '%s' "$v34_sent" | sed -n 's/.* \([a-z][a-z]*\) finding categories:.*/\1/p')
case "$v34_word" in fifteen) v34_want=15 ;; sixteen) v34_want=16 ;; seventeen) v34_want=17 ;; eighteen) v34_want=18 ;; *) v34_want=-1 ;; esac
v34_list=${v34_sent#*finding categories:}
v34_list=${v34_list%%. \*\**}
v34_have=$(printf '%s' "$v34_list" | grep -o '`[a-z0-9-]*`' | grep -c .)
[ "$v34_want" = "$v34_have" ] \
  || v34_bad="$v34_bad [STATE category sentence says '$v34_word' ($v34_want) but lists $v34_have backticked categories]"
[ "$v34_word" = "seventeen" ] || v34_bad="$v34_bad [STATE category sentence says '$v34_word', want seventeen after phase 5]"
grep -qF '`escape-unrecorded`' <<<"$v34_list" || v34_bad="$v34_bad [STATE category sentence omits escape-unrecorded]"
grep -qF '`split-layout`' <<<"$v34_list" || v34_bad="$v34_bad [STATE category sentence omits split-layout]"
# state_md5: no 'state-file hash' wording left; the order is defined once, in the state_md5
# bullet of docs/EVAL.md's ledger section, and that bullet names both siblings.
v34_old=$(grep -ciE 'state-file hash' "$gate_root/agents/EVAL.md" "$gate_root/commands/mozart-eval.md" | awk -F: '{ s += $NF } END { print s + 0 }')
[ "$v34_old" = "0" ] || v34_bad="$v34_bad [$v34_old 'state-file hash' line(s) left in agents/EVAL.md and commands/mozart-eval.md]"
v34_md5=$(grep -m1 -F -- '`state_md5`**:' <<<"$v34_ledger")
for v34_sib in .ledger.md .conductor.md 'in that order'; do
  grep -qF -- "$v34_sib" <<<"$v34_md5" || v34_bad="$v34_bad [docs/EVAL.md's state_md5 bullet (ledger section) does not say '$v34_sib']"
done
[ "$(grep -c 'in that order' "$gate_root/docs/EVAL.md")" = "1" ] || v34_bad="$v34_bad [docs/EVAL.md must define the state_md5 concatenation order exactly once]"
for v34_f in agents/EVAL.md commands/mozart-eval.md docs/EVAL.md; do
  grep -q 'state_md5' "$gate_root/$v34_f" || v34_bad="$v34_bad [$v34_f does not name state_md5]"
done
# Positive half: naming state_md5 was true before the layout change. The line that names it
# must also say it covers the sibling ledger and conductor files.
for v34_f in agents/EVAL.md commands/mozart-eval.md; do
  grep -F 'state_md5' "$gate_root/$v34_f" | grep -qF 'sibling ledger and conductor files' \
    || v34_bad="$v34_bad [$v34_f: no line names state_md5 together with 'sibling ledger and conductor files']"
done
v34_fields=$(grep -ohE 'state_[a-z0-9_]+' "$gate_root/agents/EVAL.md" "$gate_root/commands/mozart-eval.md" "$gate_root/docs/EVAL.md" | sort -u | tr '\n' ' ')
[ "$v34_fields" = "state_md5 " ] || v34_bad="$v34_bad [state_ field names in the EVAL files: $v34_fields (want only state_md5)]"
# The bug-report template points at the sibling files.
grep -F 'state.md' "$gate_root/.github/ISSUE_TEMPLATE/bug_report.md" | grep -qF 'ledger' \
  || v34_bad="$v34_bad [bug_report.md's state-file line does not mention the ledger sibling]"
# The lint column list in docs/EVAL.md carries the new category.
grep -F '| Repo | Total |' <<<"$v34_mech" | grep -qF 'split-layout' \
  || v34_bad="$v34_bad [docs/EVAL.md lint table (Mechanical metrics section) has no split-layout column]"
grep -F '| Repo | Total |' <<<"$v34_mech" | grep -qF 'escape-unrecorded' \
  || v34_bad="$v34_bad [docs/EVAL.md lint table (Mechanical metrics section) has no escape-unrecorded column]"
report "V33_layout_prose" "$([ -z "$v34_bad" ] && echo 0 || echo 1)" \
  "${v34_bad:-closeout names both siblings in both bullets; 'never split on resume' once; category sentence says $v34_word and lists $v34_have; no 'state-file hash' wording; state_md5 order defined once; bug-report and lint-table sites updated}"

# ---------------------------------------------------------------------------
# V34_phase_rows - one tier parse, two scripts, one verdict (phase 4)
#
# Phase rows (P<N>) are required on HEAVY only. The tier is read by one library
# function for both scripts, first Tier line wins, a placeholder is not a value.
# Each lint fixture below is copied alone into a scratch root and run through
# BOTH scripts: lint must fire (or not) on the Phase line, and metrics must
# bucket the campaign under the expected tier. An aggregate over the whole
# corpus could not say which fixture produced which answer.
# ---------------------------------------------------------------------------
v34_bad=""
v34_lib="$gate_root/scripts/lib-campaign.sh"
v34_corpus="$gate_root/tests/fixtures/conductor/lint/.mozart/plans/active"
v34_tmp=$(mktemp -d) || { v34_bad="$v34_bad [mktemp failed]"; v34_tmp=/nonexistent-v34; }
v34_n=0
v34_lint="$gate_root/scripts/mozart-lint.sh"
# Every case runs under the UTF-8 locale V11 resolved (see gate_utf8); the
# multibyte cases run once more under C.
v34_loc="$gate_utf8"
v34_lens="$gate_lens"
[ -n "$v34_loc" ] || v34_bad="$v34_bad [no UTF-8 locale in locale -a: the multibyte cases would run under the caller's locale and prove nothing]"
# Lint exits 0 on a root with no finding and 1 on a root with findings; metrics
# exits 0 on any root holding a state file. Both statuses are read beside the
# output, so a script that crashes (empty output, nonzero status) cannot pass as
# "fired 0 times" or as an empty bucket.
v34_case() { # $1 = slug, $2 = 1 when lint must report the Phase line, $3 = metrics tier bucket, $4 = lint exit status when it is not decided by $2
  local slug="$1" want_fire="$2" want_bucket="$3" root lout mout fired bucket lrc mrc want_lrc
  root="$v34_tmp/$slug"
  mkdir -p "$root/.mozart/plans/active" && cp "$v34_corpus/$slug.state.md" "$root/.mozart/plans/active/" \
    || { v34_bad="$v34_bad [$slug: could not stage the fixture]"; return; }
  lout=$(env LC_ALL="$v34_loc" MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 ${v34_lens:+MOZART_LINT_LENS_SINCE=$v34_lens} bash "$v34_lint" "$root" 2>&1); lrc=$?
  fired=$(printf '%s\n' "$lout" | grep -c 'ticked Phase line has no linked conductor row' || true)
  mout=$(LC_ALL="$v34_loc" bash "$gate_root/scripts/mozart-metrics.sh" "$root" 2>&1); mrc=$?
  bucket=$(printf '%s\n' "$mout" | sed -n 's/^Campaigns: 1 (1 \(.*\))$/\1/p')
  v34_n=$((v34_n + 1))
  want_lrc=0; [ "$want_fire" = "1" ] && want_lrc=1
  want_lrc="${4:-$want_lrc}"
  [ "$lrc" = "$want_lrc" ] || v34_bad="$v34_bad [$slug: lint exited $lrc, want $want_lrc]"
  [ "$mrc" = "0" ] || v34_bad="$v34_bad [$slug: metrics exited $mrc, want 0]"
  [ "$fired" = "$want_fire" ] || v34_bad="$v34_bad [$slug: lint reported the Phase line $fired time(s), want $want_fire]"
  [ "$bucket" = "$want_bucket" ] || v34_bad="$v34_bad [$slug: metrics bucket '$bucket', want '$want_bucket']"
}
if [ -d "$v34_corpus" ]; then
  v34_case 2099-07-16-deliver-kP 1 HEAVY
  v34_case 2099-10-02-phase-standard 0 STANDARD
  v34_case 2099-10-03-phase-light 0 LIGHT
  v34_case 2099-10-04-phase-tiny 0 TINY
  v34_case 2099-10-05-phase-notier 1 UNTIERED
  v34_case 2099-10-06-phase-placeholder 1 UNTIERED
  v34_case 2099-10-07-phase-unfilled 1 UNTIERED
  v34_case 2099-10-08-phase-combinedheavy 1 HEAVY
  v34_case 2099-10-09-phase-combinedstd 0 STANDARD
  v34_case 2099-10-10-phase-heavyfmt 1 HEAVY
  v34_case 2099-10-11-phase-stdfmt 1 UNTIERED
  v34_case 2099-10-12-phase-lower 1 UNTIERED
  v34_case 2099-10-13-phase-title 1 UNTIERED
  v34_case 2099-10-14-phase-heavyfirst 1 HEAVY
  v34_case 2099-10-15-phase-stdfirst 0 STANDARD
  v34_case 2099-10-16-phase-stdmalformed 0 STANDARD 1
  v34_case 2099-10-27-phase-quoted 1 UNTIERED
  v34_case 2099-10-29-phase-boldheavy 1 HEAVY
  v34_case 2099-10-30-phase-boldstd 0 STANDARD
  v34_case 2099-10-31-phase-italicstd 1 UNTIERED
  v34_case 2099-11-01-phase-underlight 1 UNTIERED
  v34_case 2099-11-02-phase-stdarrow 1 UNTIERED
  v34_case 2099-11-03-phase-stdnow 1 UNTIERED
  v34_case 2099-11-04-phase-commaplaceholder 1 UNTIERED
  v34_case 2099-11-05-phase-suffixed 1 UNTIERED
  v34_case 2099-11-06-phase-stdfree 0 STANDARD
  v34_case 2099-11-07-phase-boldstdesc 1 UNTIERED
  v34_case 2099-11-08-phase-boldcombined 0 STANDARD
  v34_case 2099-11-09-phase-ticked 1 UNTIERED
  v34_case 2099-11-14-phase-boldlist 1 UNTIERED
  v34_case 2099-11-16-phase-lensemdash 0 HEAVY
  v34_case 2099-11-17-phase-heavyrepeat 0 HEAVY 1
  v34_case 2099-11-18-phase-xanderskip 0 HEAVY 1
  v34_case 2099-11-19-phase-prebare 0 HEAVY 1
  v34_case 2099-11-20-phase-escnorow 0 HEAVY 1
  v34_case 2099-11-21-phase-rownoesc 0 HEAVY 1
  v34_case 2099-11-22-phase-passlinkwrong 0 HEAVY 1
  v34_case 2099-12-10-phase-escnoclaim 0 HEAVY 1
  v34_case 2099-12-11-phase-escdocsreason 0 HEAVY 1
  v34_case 2099-12-12-phase-escseereason 0 HEAVY 1
  v34_case 2099-12-13-phase-escprefixlink 0 HEAVY 1
  v34_case 2099-12-14-phase-escplaceholder 0 HEAVY 1
  v34_case 2099-12-15-phase-escnotrun 0 HEAVY 1
  v34_case 2099-12-17-phase-escoldform 0 HEAVY 1
  v34_case 2099-12-16-phase-escafterk 0 HEAVY 1
  v34_case 2099-12-18-phase-escorder 0 HEAVY 1
  v34_case 2099-12-20-phase-esctwodigit 0 HEAVY 1
  v34_case 2099-12-21-phase-esctwodigitok 0 HEAVY 0
  v34_case 2099-12-19-phase-escorderok 0 HEAVY 0
  v34_case 2099-12-09-phase-escok 0 HEAVY 0
  v34_loc=C
  v34_case 2099-11-16-phase-lensemdash 0 HEAVY
  v34_case 2099-11-17-phase-heavyrepeat 0 HEAVY 1
  v34_case 2099-11-18-phase-xanderskip 0 HEAVY 1
  v34_case 2099-11-19-phase-prebare 0 HEAVY 1
  v34_case 2099-11-20-phase-escnorow 0 HEAVY 1
  v34_case 2099-11-21-phase-rownoesc 0 HEAVY 1
  v34_case 2099-11-22-phase-passlinkwrong 0 HEAVY 1
  v34_case 2099-12-10-phase-escnoclaim 0 HEAVY 1
  v34_case 2099-12-11-phase-escdocsreason 0 HEAVY 1
  v34_case 2099-12-12-phase-escseereason 0 HEAVY 1
  v34_case 2099-12-13-phase-escprefixlink 0 HEAVY 1
  v34_case 2099-12-14-phase-escplaceholder 0 HEAVY 1
  v34_case 2099-12-15-phase-escnotrun 0 HEAVY 1
  v34_case 2099-12-17-phase-escoldform 0 HEAVY 1
  v34_case 2099-12-16-phase-escafterk 0 HEAVY 1
  v34_case 2099-12-18-phase-escorder 0 HEAVY 1
  v34_case 2099-12-20-phase-esctwodigit 0 HEAVY 1
  v34_case 2099-12-21-phase-esctwodigitok 0 HEAVY 0
  v34_case 2099-12-19-phase-escorderok 0 HEAVY 0
  v34_case 2099-12-09-phase-escok 0 HEAVY 0
  v34_loc="$gate_utf8"
fi
[ "$v34_n" -ge 70 ] || v34_bad="$v34_bad [only $v34_n fixture(s) ran, floor 70]"

# D12, the default lens-record date. The corpus runs above pin the date after the 2099-11 fixtures; these runs use
# the constant itself. One fixture (a bare HEAVY tier line, a row with no lens fields) is copied under a slug dated
# the day before the constant and the day of it: the first must stay silent, so no campaign dated before the change
# gains a finding, and the second must report both rules. The override must move the boundary both ways and announce itself.
v34_lens_def=$(grep -oE 'LENS_SINCE="\$\{MOZART_LINT_LENS_SINCE:-[0-9]{4}-[0-9]{2}-[0-9]{2}\}"' "$gate_root/scripts/mozart-lint.sh" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
[ "$v34_lens_def" = "2026-10-04" ] || v34_bad="$v34_bad [the lens-record date default is '$v34_lens_def', want 2026-10-04: the day after the change landed, so nothing dated 2026-10-03 or earlier gains a finding]"
v34_bnd() { # $1 = slug date, rest = extra env assignments -> lint output and exit status, no lens date unless given
  local d="$1" slug root; shift
  slug="$d-phase-boundary"; root="$v34_tmp/b-$d-$#"
  mkdir -p "$root/.mozart/plans/active" && sed "s/2099-12-04-phase-baredated/$slug/" "$v34_corpus/2099-12-04-phase-baredated.state.md" > "$root/.mozart/plans/active/$slug.state.md" \
    || { printf 'STAGE-FAILED'; return; }
  env -u MOZART_LINT_LENS_SINCE LC_ALL="$v34_loc" MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 "$@" bash "$v34_lint" "$root" 2>&1
  printf 'rc=%s\n' "$?"
}
if [ -f "$v34_corpus/2099-12-04-phase-baredated.state.md" ]; then
  v34_b0=$(v34_bnd 2026-10-03)
  grep -q 'rc=0$' <<<"$v34_b0" && ! grep -q '^LINT' <<<"$v34_b0" || v34_bad="$v34_bad [a campaign dated 2026-10-03 gained a finding under the default lens-record date: $(head -2 <<<"$v34_b0" | cut -c1-120 | tr '\n' ' ')]"
  v34_b1=$(v34_bnd 2026-10-04)
  { grep -q 'rc=1$' <<<"$v34_b1" && grep -q 'HEAVY tier line has no usable surface record' <<<"$v34_b1" && grep -q 'HEAVY phase row does not record ian and xander' <<<"$v34_b1"; } \
    || v34_bad="$v34_bad [a campaign dated 2026-10-04 did not report both lens-record rules under the default date: $(head -2 <<<"$v34_b1" | cut -c1-120 | tr '\n' ' ')]"
  v34_b2=$(v34_bnd 2026-10-04 MOZART_LINT_LENS_SINCE=2026-10-05)
  { grep -q 'rc=0$' <<<"$v34_b2" && grep -qxF 'lens-record date overridden: 2026-10-05' <<<"$v34_b2"; } \
    || v34_bad="$v34_bad [MOZART_LINT_LENS_SINCE=2026-10-05 did not exempt a 2026-10-04 campaign, or did not announce itself]"
  v34_b3=$(v34_bnd 2026-10-03 MOZART_LINT_LENS_SINCE=2026-10-03)
  grep -q 'rc=1$' <<<"$v34_b3" || v34_bad="$v34_bad [MOZART_LINT_LENS_SINCE=2026-10-03 did not bring a 2026-10-03 campaign under the rule]"
else
  v34_bad="$v34_bad [the dated lens-record fixture 2099-12-04-phase-baredated is missing]"
fi

# The helper can fail. A lint that crashes prints nothing and exits 3: without
# the status check that reads as "fired 0 times", the answer a silent case wants.
# Point the helper at a stub that does exactly that and require it to object.
printf '#!/bin/bash\nexit 3\n' > "$v34_tmp/crash-lint.sh" || v34_bad="$v34_bad [could not write the crash stub]"
v34_keep_bad="$v34_bad"; v34_keep_lint="$v34_lint"; v34_keep_n="$v34_n"
v34_bad=""; v34_lint="$v34_tmp/crash-lint.sh"
if [ -d "$v34_corpus" ]; then v34_case 2099-10-02-phase-standard 0 STANDARD; fi
v34_selftest="$v34_bad"
v34_bad="$v34_keep_bad"; v34_lint="$v34_keep_lint"; v34_n="$v34_keep_n"
case "$v34_selftest" in
  *"lint exited 3"*) : ;;
  *) v34_bad="$v34_bad [self-test: a lint that crashes (exit 3, no output) did not fail v34_case]" ;;
esac

# The library function on its own. Each row is a full line and the tier it must
# return; the awk program prints only the rows that disagree.
v34_prog='function chk(line, want,   got) {
  got = tier_of(line); n++
  if (got != want) printf "[%s: want %s got %s]", line, want, got
}
BEGIN {
  chk("**Tier**: HEAVY (surface: auth, secrets; escalated from STANDARD, D4)", "HEAVY")
  chk("**Tier**: HEAVY (escalated from STANDARD, D4)", "HEAVY")
  chk("**Tier**: TINY | LIGHT | STANDARD | HEAVY", "")
  chk("**Tier**: <tier>", "")
  chk("**Shape**: DELIVER | **Tier**: LIGHT | **Mode**: AUTONOMOUS", "LIGHT")
  chk("**Shape**: DELIVER | **Tier**: **HEAVY** | **Mode**: AUTONOMOUS", "HEAVY")
  chk("**Shape**: DELIVER | **Tier**: **STANDARD** | **Mode**: AUTONOMOUS", "STANDARD")
  chk("**Tier**: STANDARD | **Mode:** AUTONOMOUS", "STANDARD")
  chk("**Tier**: heavy", "")
  chk("**Tier**: Standard", "")
  chk("**Tier**: HEAVYish", "")
  chk("**Tier**: TINY, LIGHT, STANDARD, HEAVY", "")
  chk("**Tier**: TINY / LIGHT / STANDARD / HEAVY", "")
  chk("**Tier**: LIGHT or HEAVY", "")
  chk("**Tier**: STANDARD2", "")
  chk("**Tier**: STANDARD_x", "")
  chk("**Tier**: STANDARD/HEAVY", "")
  chk("**Tier**: STANDARD-HEAVY", "")
  chk("**Tier**: STANDARD.", "")
  chk("**Tier**: STANDARD", "STANDARD")
  chk("**Tier**: STANDARD (x)", "STANDARD")
  chk("**Tier**: STANDARD — free text", "STANDARD")
  chk("**Tier**: STANDARD; free text", "STANDARD")
  chk("**Tier**: HEAVY", "HEAVY")
  chk("**Tier**: STANDARD (escalated to HEAVY)", "")
  chk("**Tier**: STANDARD → HEAVY", "")
  chk("**Tier**: STANDARD, now HEAVY", "")
  chk("**Tier**: LIGHT; HEAVY after review", "")
  chk("**Tier**: STANDARD (HEAVYish is not a word)", "STANDARD")
  chk("**Tier**: **HEAVY**", "HEAVY")
  chk("**Tier**: **STANDARD**", "STANDARD")
  chk("**Tier**: **HEAVY** (surface: x)", "HEAVY")
  chk("**Tier**: **HEAVY** — maintainer confirmed (was STANDARD)", "HEAVY")
  chk("**Tier**: **STANDARD** (escalated to HEAVY)", "")
  chk("**Tier**: **HEAVY", "")
  chk("**Tier**: ****", "")
  chk("**Tier**: **TINY | LIGHT**", "")
  chk("**Tier**: **TINY** | **LIGHT**", "")
  chk("**Tier**: *HEAVY*", "")
  chk("**Tier**: _HEAVY_", "")
  chk("**Tier**: `HEAVY`", "")
  chk("**Tier**: *STANDARD* (plain call)", "")
  chk("**Tier**: _LIGHT_", "")
  chk("**Tier**: STANDARD(x)", "STANDARD")
  chk("**Tier**: STANDARD—free text", "STANDARD")
  chk("**Tier**: STANDARD(escalated to HEAVY)", "")
  chk("**Tier**: STANDARD (NOHEAVY)", "STANDARD")
  chk("**Tier**: STANDARD (xHEAVY)", "STANDARD")
  chk("**Tier**: HEAVY (maintainer confirmed HEAVY)", "HEAVY")
  chk("**Tier**: **HEAVY** — HEAVY after review", "HEAVY")
  chk("**Tier**: STANDARD (escalated→HEAVY)", "")
  chk("**Tier**: STANDARD (escalated to HEAVY—maintainer)", "")
  chk("**Tier**: STANDARD (HEAVY…)", "")
  chk("**Tier**: STANDARD — now “HEAVY”", "")
  chk("**Tier**: STANDARD—HEAVY", "")
  chk("**Tier**: STANDARD (“HEAVYish”)", "STANDARD")
  printf "[%s]", is_tier_line("| CR1 | fact | the doc says **Tier**: HEAVY | - |")
  printf "[%s]", is_tier_line("**Tier**: STANDARD")
  printf "[%s]", tier_has_surface("**Tier**: HEAVY (surface: billing)")
  printf "[%s]", tier_has_surface("**Tier**: HEAVY")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: auth)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing, security)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: secrets; escalated from STANDARD, D4)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: authz)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing; maintainer says auth)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (escalated, auth later)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra,auth)")
  printf "[%s]", tier_surface_wants_xander("**Shape**: DELIVER | **Tier**: HEAVY (surface: auth) | **Mode**: AUTONOMOUS")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: )")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: Auth/Secrets.)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: `auth`)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; secrets)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing; maintainer confirmed HEAVY)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing, infra)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing, widgets)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing—x)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: “auth”)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: SECURITY.)")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY (surface: billing)")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY (surface: )")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY (surface: widgets)")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY (surface: billing, widgets)")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY (surface: Billing.)")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY (surface: ; secrets)")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY (surface: infra/billing)")
  printf "[%s]", tier_escalation_d("**Tier**: HEAVY (surface: auth; escalated from STANDARD, D4)")
  printf "[%s]", tier_escalation_d("**Tier**: HEAVY (surface: auth)")
  printf "[%s]", tier_escalation_d("**Tier**: HEAVY (surface: auth; escalated from HEAVY, D4)")
  printf "[%s]", tier_escalation_d("**Tier**: HEAVY (surface: auth; escalated from LIGHT, D12)")
  printf "[%s]", tier_escalation_d("**Tier**: HEAVY (surface: auth; escalated from STANDARD D4)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface:)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: none)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: n/a)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra (auth))")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra)\r")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing) and (surface: auth)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing) (surface: infra)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; authentication)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; secret)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; auth-flow)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing; auth+secrets)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; security review)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; credentials)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing; maintainer confirmed HEAVY)")
  printf "[%s]", tier_surface_usable("**Tier**: HEAVY (surface:)")
  printf "[%s]", tier_escalation_d("**Tier**: HEAVY (surface: auth; escalated from STANDARD, D12)")
  printf "[%s]", tier_escalation_d("**Tier**: HEAVY (surface: auth; escalated from LIGHT, D4)")
  printf "[%s]", phase_order("P2")
  printf "[%s]", phase_order("P2a")
  printf "[%s]", phase_order("P2b")
  printf "[%s]", phase_order("P3")
  printf "[%s]", phase_order("P12b")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation (through P2): run")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation (through P2a): run")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation (through P2): not run")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation (through P2): run.")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation (through P2): running")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation (through P2) run")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation (through 2): run")
  printf "[%s]", escalation_pass_through("ian: run; xander: cumulative pass on escalation (through P10b): run; more")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; Auth-flow)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; Auth0)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; Secrets-Manager)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; Security2)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: infra; Crédentials)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: billing; Maintainer Confirmed HEAVY)")
  printf "[%s]", tier_surface_wants_xander("**Tier**: HEAVY (surface: Billing, INFRA)")
  printf "[%s]", escalation_pass_through("notxander: cumulative pass on escalation (through P99): run")
  printf "[%s]", escalation_pass_through("x-xander: cumulative pass on escalation (through P99): run")
  printf "[%s]", escalation_pass_through("ian: run; xander: cumulative pass on escalation (through P7): run")
  printf "[%s]", escalation_pass_through("xander: cumulative pass on escalation (through P7): run")
  printf "{%d}", n
}'
v34_want="[0][1][1][0][1][1][1][0][1][1][0][1][1][1][1][1][1][0][0][1][1][1][1][1][0][0][0][1][1][0][1][4][][][12][][1][1][1][1][0][1][1][1][1][1][1][1][0][0][0][12][4][200][201][202][300][1202][P2][P2a][][][P2][][][][P10b][1][1][1][1][0][0][0][][P99][P7][P7]{56}"
for v34_l in "$gate_utf8" C; do
  v34_got=$( . "$v34_lib" 2>/dev/null; LC_ALL="$v34_l" awk "$CAMPAIGN_AWK_LIB"$'\n'"$v34_prog" </dev/null 2>&1 )
  [ "$v34_got" = "$v34_want" ] \
    || v34_bad="$v34_bad [library tier_of / is_tier_line / tier_has_surface / tier_surface_wants_xander / tier_surface_usable / tier_escalation_d under LC_ALL=$v34_l returned '$v34_got', want '$v34_want']"
done

# F59: the F46 guard above aborts only macOS awk (towc: multibyte conversion failure on a lone byte). Measured
# on ubuntu:24.04 (mawk 1.3.4) under LC_ALL=C.UTF-8 and LC_ALL=C: substr(s, 2, 1) of a 3-byte character is a
# byte, tested against [A-Za-z0-9] without error, so the CI runner passes the one-byte form. This static scan
# is the guard that bites everywhere: no substr(..., 1) result is matched with ~ or !~ against a bracket
# expression. Whole-prefix and whole-suffix windows (substr(s, 1, i - 1), substr(s, i + 5)) are legitimate and
# stay clean; so do == and != against a string. The scan cannot see a one-char window written as substr(s, n)
# or a byte first copied into a variable, or a window nested two parentheses deep (one level, as in
# substr(s, length(s), 1), is read); those stay a review matter.
v34_sub_re='substr[(]([^()]|[(][^()]*[)])*, *1 *[)] *!?~ *[^ ]*[[]'
v34_sub_plants=(
  'if (i > 1 && substr(s, i - 1, 1) ~ /[A-Za-z0-9]/) continue'
  'if (substr(r, i + 5, 1) !~ /[a-z]/) return 0'
  'ok = substr(s, i, 1) ~ "^[A-Z]"'
  'if (substr(s, length(s), 1) ~ /[a-z]/) continue'
  'if (substr(s, index(s,"x")+1, 1) !~ /[0-9]/) return 0'
)
v34_sub_clean=(
  'if (substr(s, 1, i - 1) ~ /[A-Za-z0-9]$/) continue'
  'if (substr(s, i + 5) ~ /^[A-Za-z0-9]/) continue'
  'if (substr(r, 1, 1) == "(") {'
  'if (substr(r, 1, 1) != ":") return ""'
  'if (substr(s, length(s) - 1) ~ /^[a-z]/) continue'
  'if (substr(s, index(s,"x"), 10) ~ /[0-9]/) continue'
)
[ "${#v34_sub_plants[@]}" -eq 5 ] && [ "${#v34_sub_clean[@]}" -eq 6 ] \
  || v34_bad="$v34_bad [the one-byte-window scan holds ${#v34_sub_plants[@]} plants and ${#v34_sub_clean[@]} clean lines, want 5 and 6: a plant was deleted]"
for v34_pl in "${v34_sub_plants[@]}"; do
  grep -qE -- "$v34_sub_re" <<<"$v34_pl" || v34_bad="$v34_bad [one-byte-window scan did not flag a planted line: $v34_pl]"
done
for v34_pl in "${v34_sub_clean[@]}"; do
  grep -qE -- "$v34_sub_re" <<<"$v34_pl" && v34_bad="$v34_bad [one-byte-window scan flagged a legitimate line: $v34_pl]"
done
v34_sub_n=0
for v34_s in lib-campaign mozart-lint mozart-metrics; do
  v34_sub_n=$((v34_sub_n + $(v30_code_lines "$gate_root/scripts/$v34_s.sh" | grep -cE -- 'substr[(]' || true)))
  v34_sub_hit=$(v30_code_lines "$gate_root/scripts/$v34_s.sh" | grep -E -- "$v34_sub_re" || true)
  [ -z "$v34_sub_hit" ] || v34_bad="$v34_bad [$v34_s.sh tests a one-byte substr window against a bracket expression (aborts macOS awk on multibyte text): $(head -1 <<<"$v34_sub_hit")]"
done
[ "$v34_sub_n" -ge 8 ] || v34_bad="$v34_bad [the one-byte-window scan saw only $v34_sub_n substr line(s) in the three scripts, floor 8: it is scanning nothing]"

# Neither script spells the Tier field itself: the rule lives in the library.
for v34_s in mozart-lint mozart-metrics; do
  v34_spell=$(v30_code_lines "$gate_root/scripts/$v34_s.sh" | grep -cF '**Tier**' || true)
  v34_spell_re=$(v30_code_lines "$gate_root/scripts/$v34_s.sh" | grep -cF 'Tier\*\*' || true)
  [ "$v34_spell" -eq 0 ] && [ "$v34_spell_re" -eq 0 ] \
    || v34_bad="$v34_bad [$v34_s.sh spells the Tier field in $((v34_spell + v34_spell_re)) code line(s): the parse lives in the library]"
done
rm -rf "$v34_tmp"
report "V34_phase_rows" "$([ -z "$v34_bad" ] && echo 0 || echo 1)" \
  "${v34_bad:-$v34_n fixtures each run alone through lint and metrics (both exit statuses read; the helper shown able to fail): Phase rows required on HEAVY and on a missing, placeholder, list, suffixed, escalation-text or unparseable tier, silent on TINY/LIGHT/STANDARD, first Tier line wins, combined header parses, a balanced bold wrapper is stripped and italic or backticked values are no value; 56 library tier_of cases and 33 tier_surface_wants_xander, 8 tier_surface_usable and 5 tier_escalation_d, phase_order and escalation_pass_through cases (case, punctuation, backticks, slashes, a word after a semicolon, an unlisted word failing safe, multibyte text beside a word), each run under a UTF-8 locale and under C (multibyte beside HEAVY, every whitelist member alone, the HEAVY-lead and preceding-letter edges); the multibyte lens and HEAVY-repeat fixtures also run under C; neither script spells the Tier field}"

# ---------------------------------------------------------------------------
# V35_escapes - Check N, and the one rule for what an escape is (phase 5)
#
# A DIAGNOSE or INCIDENT artifact that names the campaign a defect traces to must
# find that campaign's ## Escapes block recording it. Lint and metrics share one
# rule for a recorded-escape line (is_escape_line, in the library); the agreement
# corpus is four origins run through both scripts: A recorded, B "(none yet) |
# Traces-to: <slug>", C a placeholder target, D recorded with trailing "n<3
# affected". Lint must be silent on A and D and fire on B and C, and metrics must
# count exactly the lines lint accepts. The per-fixture outcomes (layouts, forms,
# fences, prefix collision, external, ticket ids) are V11's, over the lint corpus.
# This gate holds what V11 cannot: the agreement, a repo with no investigations
# tree, the frozen grammar sentence at its seven sites, and the single copy of the
# rule.
# ---------------------------------------------------------------------------
v35_bad=""
v35_repo=$(dirname "$(dirname "$gatefile")")
v35_agree="$v35_repo/tests/fixtures/conductor/escapes-agree"
v35_tmp=$(mktemp -d) || { v35_bad="$v35_bad [mktemp failed]"; v35_tmp=/nonexistent-v35; }
v35_lint() { MOZART_LINT_CONDUCTOR_SINCE=2099-06-01 MOZART_LINT_LENS_SINCE="$gate_lens" bash "$gate_root/scripts/mozart-lint.sh" "$1" 2>&1; }
v35_pick() { # $1 = scratch name, then the letters of the origins to keep (state file and artifact)
  local dst="$v35_tmp/$1" k; shift
  mkdir -p "$dst/.mozart/plans/finished" "$dst/.mozart/investigations/finished" || return 1
  for k in "$@"; do
    cp "$v35_agree/.mozart/plans/finished/2099-05-22-deliver-agree-$k.state.md" "$dst/.mozart/plans/finished/" || return 1
    cp "$v35_agree/.mozart/investigations/finished/2099-09-22-diagnose-agree-$k.md" "$dst/.mozart/investigations/finished/" || return 1
  done
}
v35_n=$(find "$v35_agree" -name '*.state.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$v35_n" -eq 4 ] || v35_bad="$v35_bad [agreement corpus holds $v35_n origin(s), want 4]"
if v35_pick all a b c d; then
  v35_l=$(v35_lint "$v35_tmp/all")
  v35_fired=$(printf '%s\n' "$v35_l" | grep -c '^LINT \[escape-unrecorded\]' || true)
  v35_m=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v35_tmp/all" 2>&1)
  v35_counted=$(printf '%s\n' "$v35_m" | sed -n 's/^Escapes (Traces-to links): \([0-9]*\)$/\1/p')
  for v35_k in b c; do
    grep '^LINT \[escape-unrecorded\]' <<<"$v35_l" | grep -qF "2099-05-22-deliver-agree-$v35_k.state.md — 2099-09-22-diagnose-agree-$v35_k:" \
      || v35_bad="$v35_bad [lint did not fire on agreement origin $v35_k]"
  done
  for v35_k in a d; do
    grep '^LINT \[escape-unrecorded\]' <<<"$v35_l" | grep -qF "agree-$v35_k" \
      && v35_bad="$v35_bad [lint fired on agreement origin $v35_k, a recorded escape]"
  done
  [ "$v35_fired" = "2" ] || v35_bad="$v35_bad [lint fired $v35_fired time(s) on the agreement corpus, want 2]"
  [ "$v35_counted" = "2" ] || v35_bad="$v35_bad [metrics counted '$v35_counted' escape(s) on the agreement corpus, want 2]"
  [ "$((v35_n - v35_fired))" = "$v35_counted" ] \
    || v35_bad="$v35_bad [lint accepts $((v35_n - v35_fired)) origin(s) as recorded but metrics counts $v35_counted: the two scripts disagree about what an escape is]"
else
  v35_bad="$v35_bad [the agreement corpus could not be copied]"
fi
# B alone is the plan's "(none yet) | Traces-to: <slug>" fixture: one finding in lint, none counted by metrics.
if v35_pick bonly b; then
  v35_fired=$(v35_lint "$v35_tmp/bonly" | grep -c '^LINT \[escape-unrecorded\]' || true)
  v35_m=$(bash "$gate_root/scripts/mozart-metrics.sh" "$v35_tmp/bonly" 2>&1)
  [ "$v35_fired" = "1" ] || v35_bad="$v35_bad [B alone: lint fired $v35_fired time(s), want 1]"
  grep -qxF 'Escapes (Traces-to links): 0' <<<"$v35_m" || v35_bad="$v35_bad [B alone: metrics did not print 'Escapes (Traces-to links): 0']"
else
  v35_bad="$v35_bad [the B-only copy could not be built]"
fi
# A repo with plans and no investigations or incidents tree: no error, no finding.
if v35_pick noinv a && rm -rf "$v35_tmp/noinv/.mozart/investigations"; then
  v35_l=$(v35_lint "$v35_tmp/noinv"; echo "rc=$?")
  grep -q '^mozart-lint: clean' <<<"$v35_l" && grep -qxF 'rc=0' <<<"$v35_l" \
    || v35_bad="$v35_bad [a repo with no investigations or incidents tree did not lint clean: $(printf '%s' "$v35_l" | tail -2 | tr '\n' ' ')]"
else
  v35_bad="$v35_bad [the no-investigations copy could not be built]"
fi
# The older corpora carry no investigations tree: Check N adds nothing there.
for v35_c in metrics-conductor metrics-split metrics-placeholder; do
  v35_cn=$(v35_lint "$v35_repo/tests/fixtures/conductor/$v35_c" | grep -c '^LINT \[escape-unrecorded\]' || true)
  [ "$v35_cn" = "0" ] || v35_bad="$v35_bad [$v35_c emits $v35_cn escape-unrecorded line(s), want 0]"
done
rm -rf "$v35_tmp"

# The grammar sentence: frozen once, present exactly once at each of seven sites.
v35_policy="$v35_repo/tests/policy/traces-to-grammar.txt"
v35_sites=0
if [ -s "$v35_policy" ] && [ "$(grep -c . "$v35_policy")" = "1" ]; then
  v35_sent=$(cat "$v35_policy")
  for v35_f in agents/dick.md agents/DIAGNOSE.md agents/INCIDENT.md agents/scott.md agents/PIPELINE.md agents/STATE.md docs/EVAL.md; do
    v35_c=$(awk -v s="$v35_sent" '{ l = $0; while ((p = index(l, s)) > 0) { c++; l = substr(l, p + length(s)) } } END { print c + 0 }' "$gate_root/$v35_f" 2>/dev/null)
    v35_sites=$((v35_sites + 1))
    [ "$v35_c" = "1" ] || v35_bad="$v35_bad [$v35_f holds the Traces-to grammar sentence $v35_c time(s), want exactly 1]"
  done
else
  v35_bad="$v35_bad [tests/policy/traces-to-grammar.txt is missing, empty or not a single line]"
fi
[ "$v35_sites" -ge 7 ] || v35_bad="$v35_bad [only $v35_sites site(s) checked, floor 7]"

# One copy of the rule: it lives in the library, and neither script spells it.
v35_lib_n=$(v30_code_lines "$gate_root/scripts/lib-campaign.sh" | grep -cF 'none yet' || true)
[ "$v35_lib_n" -ge 1 ] || v35_bad="$v35_bad [the library does not hold the recorded-escape rule ('none yet' in no code line)]"
for v35_s in mozart-lint mozart-metrics; do
  v35_dup=$(v30_code_lines "$gate_root/scripts/$v35_s.sh" | grep -cF 'none yet' || true)
  [ "$v35_dup" = "0" ] || v35_bad="$v35_bad [$v35_s.sh spells the recorded-escape rule in $v35_dup code line(s): it lives in the library]"
done
v35_mt=$(v30_code_lines "$gate_root/scripts/mozart-metrics.sh" | grep -cF 'Traces-to:' || true)
[ "$v35_mt" = "0" ] || v35_bad="$v35_bad [mozart-metrics.sh parses Traces-to: itself in $v35_mt code line(s): call is_escape_line]"
v35_mc=$(v30_code_lines "$gate_root/scripts/mozart-metrics.sh" | grep -cF 'is_escape_line' || true)
v35_lc=$(v30_code_lines "$gate_root/scripts/mozart-lint.sh" | grep -cF 'is_escape_line' || true)
{ [ "$v35_mc" -ge 1 ] && [ "$v35_lc" -ge 1 ]; } || v35_bad="$v35_bad [is_escape_line is called $v35_mc time(s) in metrics and $v35_lc in lint, want at least 1 each]"
report "V35_escapes" "$([ -z "$v35_bad" ] && echo 0 || echo 1)" \
  "${v35_bad:-agreement corpus: lint silent on A and D, fires on B and C, metrics counts the 2 lint accepts; B alone 1 finding and Escapes 0; no investigations tree is clean; the Traces-to grammar sentence is in $v35_sites sites exactly once; the rule lives in the library only}"

# ---------------------------------------------------------------------------
# V28_tiers - the LIGHT tier, HEAVY mid-build, and the codex r2 wording (phase 7)
#
# Four populations, each DERIVED and each located by position, because a
# file-wide count is satisfied by the wrong table (PIPELINE.md has three
# xander rows, DELIVER.md's stage-4 row carries an extra empty column):
#   1. every markdown table that names TINY and STANDARD names LIGHT and is
#      rectangular (cells counted by the library's split_cells, one rule);
#   2. every line that names TINY and STANDARD names LIGHT, minus a named,
#      asserted-present exclusion list;
#   3. the codex r2 wording, in the tables by header and in the prose by line;
#   4. the stage-8 and stage-4 trigger rows, by heading, exactly one row each,
#      carrying the surface phrase and the twelve-term security union.
# Every extractor is run on planted input it must reject before it is trusted
# on the tree, so an empty extraction cannot read as a pass.
# ---------------------------------------------------------------------------
v28_bad=""
v28_lib=$( . "$gate_root/scripts/lib-campaign.sh" 2>/dev/null; printf '%s' "${CAMPAIGN_AWK_LIB:-}" )
[ -n "$v28_lib" ] || v28_bad="$v28_bad [scripts/lib-campaign.sh gave no awk library: the table scan cannot run]"
v28_tmp=$(mktemp -d) || { v28_bad="$v28_bad [mktemp failed]"; v28_tmp=/nonexistent-v28; }

# Tables that name TINY and STANDARD as whole cells, in the header row or in the first column.
v28_tprog='
function norm(s) { gsub(/\*/, "", s); return trim(s) }
function finish(   n, i, hn, rn, c, v, tiny, std, light, rag, hc, rc) {
  if (nb >= 2) {
    hn = split_cells(blk[1], hc)
    tiny = 0; std = 0; light = 0; rag = ""
    for (c = 1; c <= hn; c++) {
      v = norm(hc[c])
      if (v == "TINY") tiny = 1
      if (v == "STANDARD") std = 1
      if (v == "LIGHT") light = 1
    }
    for (i = 2; i <= nb; i++) {
      if (blk[i] ~ /^[ \t]*\|[ \t:|-]*$/ && blk[i] ~ /-/) continue
      rn = split_cells(blk[i], rc)
      v = norm(rc[2])
      if (v == "TINY") tiny = 1
      if (v == "STANDARD") std = 1
      if (v == "LIGHT") light = 1
      if (rn != hn) rag = rag " " (start + i - 1)
    }
    if (tiny && std) printf "TABLE %s:%d rows=%d light=%d ragged=%s\n", FILENAME, start, nb - 2, light, rag
  }
  nb = 0
}
/^[ \t]*```/ { finish(); fence = !fence; next }
fence { next }
/^[ \t]*\|/ { if (nb == 0) start = FNR; blk[++nb] = $0; next }
{ finish() }
END { finish() }'
v28_tables() { # $1 = file -> one TABLE line per table naming TINY and STANDARD
  awk "$v28_lib"$'\n'"$v28_tprog" "$1" 2>&1
}
# Lines naming TINY and STANDARD but not LIGHT, as file:line:text.
v28_gaps() { # $@ = files
  local f
  for f in "$@"; do
    grep -n 'TINY' "$f" 2>/dev/null | grep 'STANDARD' | grep -v 'LIGHT' | sed "s|^|$f:|"
  done
}
v28_sec() { # $1 = file, $2 = start ERE, $3 = end ERE -> section text; empty when the heading is gone
  local r
  r=$(v3_region "$gate_root/$1" "$2" "$3")
  case "$r" in __REGION_START_NOT_FOUND__*) return 0 ;; esac
  printf '%s\n' "$r"
}
v28_rows() { # $1 = section text, $2 = lens -> every table row whose first cell, emphasis stripped, is the lens
  printf '%s\n' "$1" | awk -v lens="$2" '/^[ \t]*\|/ { c = $0; sub(/^[ \t]*\|[ \t]*/, "", c); sub(/[ \t]*\|.*$/, "", c); gsub(/\*/, "", c); if (c == lens) print }'
}
v28_cell() { # $1 = table text, $2 = first-cell prefix, $3 = column header -> that cell, emphasis stripped
  printf '%s\n' "$1" | awk -v want="$3" -v pre="$2" "$v28_lib"$'\n''
    function norm(s) { gsub(/\*/, "", s); return trim(s) }
    /^[ \t]*\|/ {
      n = split_cells($0, c)
      if (!col_at) { for (i = 2; i <= n; i++) if (norm(c[i]) == want) col_at = i; next }
      if (index(norm(c[2]), pre) == 1 && col_at) { print norm(c[col_at]); exit }
    }'
}
v28_terms=$(cat <<'V28_TERMS_EOF'
auth	[Aa]uth([^a-z]|$)
secrets	[Ss]ecrets
untrusted input	[Uu]ntrusted input
encryption	[Ee]ncryption
sessions	[Ss]essions
RBAC	RBAC
security headers	[Ss]ecurity headers
CSP	CSP
dependency changes	[Dd]ependenc|lockfile
CI/CD workflow changes	CI/CD
authorization (ownership and tenant filters)	[Aa]uthorization [(]ownership and tenant filters[)]
outbound requests	[Oo]utbound requests
V28_TERMS_EOF
)
v28_occ() { # $1 = text, $2 = ERE -> occurrences (not lines) of it, case-insensitive
  printf '%s\n' "$1" | grep -oiE -- "$2" | grep -c . || true
}
v28_has() { # $1 = text, $2 = fixed phrase -> true when it occurs, case-insensitive
  grep -qiF -- "$2" <<<"$1"
}
v28_hi_re='((take|choose|pick|select|use|prefer|go with|opt for|default to|err toward|err on the side of|round up to) the higher|the higher (tier|one) (wins|applies))'
v28_missing() { # $1 = text -> the union terms it lacks, one per line
  local name pat
  while IFS=$'\t' read -r name pat; do
    [ -n "$name" ] || continue
    grep -qE -- "$pat" <<<"$1" || printf '%s\n' "$name"
  done < <(printf '%s\n' "$v28_terms")
}
v28_once() { # $1 = text, $2 = fixed phrase (case-insensitive), $3 = label -> appends to v28_bad unless it occurs on exactly one line
  local n
  n=$(printf '%s\n' "$1" | grep -ciF -- "$2")
  [ "$n" = "1" ] || v28_bad="$v28_bad [$3: '$2' occurs on $n line(s), want exactly 1]"
}

# ---- the extractors must reject planted input before they are trusted ------
printf '%s\n' '| Stage | TINY | LIGHT | STANDARD | HEAVY |' '|---|---|---|---|---|' '| a | x | x | x | x |' '| b | x | x | x |' > "$v28_tmp/ragged.md"
printf '%s\n' '| Stage | TINY | STANDARD | HEAVY |' '|---|---|---|---|' '| a | x | x | x |' > "$v28_tmp/nolight.md"
printf '%s\n' '| Tier | What |' '|---|---|' '| **TINY** | x |' '| **LIGHT** | y |' '| **STANDARD** | z |' > "$v28_tmp/column.md"
printf '%s\n' '```' '| Stage | TINY | STANDARD |' '|---|---|---|' '```' > "$v28_tmp/fenced.md"
printf '%s\n' '| Tier | <TINY \| STANDARD \| HEAVY> |' '|---|---|' '| a | b |' > "$v28_tmp/escaped.md"
v28_t=$(v28_tables "$v28_tmp/ragged.md")
grep -qE 'light=1 ragged= 4$' <<<"$v28_t" || v28_bad="$v28_bad [self-test: a table with one short row was not reported ragged at its line: $v28_t]"
v28_t=$(v28_tables "$v28_tmp/nolight.md")
grep -q 'light=0' <<<"$v28_t" || v28_bad="$v28_bad [self-test: a TINY/STANDARD table with no LIGHT header was not reported light=0: $v28_t]"
v28_t=$(v28_tables "$v28_tmp/column.md")
grep -q 'light=1 ragged= *$' <<<"$v28_t" || v28_bad="$v28_bad [self-test: a table that names the tiers in its first column was not found, or its LIGHT row was missed: $v28_t]"
[ -z "$(v28_tables "$v28_tmp/fenced.md")" ] || v28_bad="$v28_bad [self-test: a table inside a code fence was scanned]"
[ -z "$(v28_tables "$v28_tmp/escaped.md")" ] || v28_bad="$v28_bad [self-test: an escaped-pipe cell was read as a tier table]"
printf '%s\n' 'Tiers: TINY / STANDARD / HEAVY' > "$v28_tmp/gap.md"
printf '%s\n' 'Tiers: TINY / LIGHT / STANDARD / HEAVY' > "$v28_tmp/nogap.md"
[ -n "$(v28_gaps "$v28_tmp/gap.md")" ] || v28_bad="$v28_bad [self-test: a line naming TINY and STANDARD without LIGHT was not reported]"
[ -z "$(v28_gaps "$v28_tmp/nogap.md")" ] || v28_bad="$v28_bad [self-test: a line naming all four tiers was reported]"
v28_row_plant=$(printf '%s\n' '| **xander** | a |' '| xander | b |' '| ian | c |')
[ "$(v28_rows "$v28_row_plant" xander | grep -c .)" = "2" ] || v28_bad="$v28_bad [self-test: the bold and plain xander rows were not both found]"
[ "$(v28_rows "$v28_row_plant" ian | grep -c .)" = "1" ] || v28_bad="$v28_bad [self-test: the ian row was not found once]"
[ "$(v28_missing 'Auth, secrets, untrusted input, encryption, sessions, RBAC, security headers, CSP, authorization (ownership and tenant filters), outbound requests; dependency lockfile; CI/CD' | grep -c .)" = "0" ] \
  || v28_bad="$v28_bad [self-test: a row carrying all twelve terms was reported as missing some]"
[ "$(v28_missing 'auth, secrets, untrusted input, encryption, sessions, RBAC, security headers, authorization (ownership and tenant filters), outbound requests; dependency lockfile; CI/CD' | tr '\n' ' ')" = "CSP " ] \
  || v28_bad="$v28_bad [self-test: a row without CSP did not report exactly CSP missing]"
[ "$(v28_occ 'a take the higher; b take the higher' 'take the higher')" = "2" ] || v28_bad="$v28_bad [self-test: two occurrences on one line were not counted as two]"
[ "$(v28_occ 'nothing here' 'take the higher')" = "0" ] || v28_bad="$v28_bad [self-test: no occurrence was not counted as zero]"
for v28_p in 'Where any two tiers both fit, take the higher.' 'we choose the higher tier' 'Pick the higher one' 'go with the higher' 'default to the higher'; do
  grep -qiE -- "$v28_hi_re" <<<"$v28_p" || v28_bad="$v28_bad [self-test: the general higher-tier ban did not match: $v28_p]"
done
grep -qiE -- "$v28_hi_re" <<<'the highest tier wins' && v28_bad="$v28_bad [self-test: the general higher-tier ban matched an unrelated sentence]"
printf '%s\n' 'When unsure between SEV levels: choose the higher one. Also use the higher tier.' > "$v28_tmp/inc.txt"
[ "$(sed 's/When unsure between SEV levels: choose the higher one//' "$v28_tmp/inc.txt" | grep -cEi -- "$v28_hi_re")" = "1" ] \
  || v28_bad="$v28_bad [self-test: a general sentence appended beside the allowed INCIDENT sentence was cut away with it]"
for v28_p in 'use the higher tier' 'prefer the higher' 'err toward the higher' 'round up to the higher' 'the higher tier wins' 'select the higher'; do
  grep -qiE -- "$v28_hi_re" <<<"$v28_p" || v28_bad="$v28_bad [self-test: the general higher-tier ban did not match: $v28_p]"
done
v28_cell_plant=$(printf '%s\n' '| Stage | TINY | LIGHT | STANDARD |' '|---|---|---|---|' '| Codex r2 on diff (9) | skip | run | default-run |')
[ "$(v28_cell "$v28_cell_plant" 'Codex r2' LIGHT)" = "run" ] || v28_bad="$v28_bad [self-test: the LIGHT cell of a planted table was not read as run]"
[ "$(v28_cell "$v28_cell_plant" 'Codex r2' STANDARD)" = "default-run" ] || v28_bad="$v28_bad [self-test: the STANDARD cell of a planted table was not read as default-run]"

# ---- 1. tier tables ---------------------------------------------------------
v28_docs=$(git ls-files 'agents/*.md' 'commands/*.md' 'docs/*.md' README.md)
v28_ndocs=$(printf '%s\n' "$v28_docs" | grep -c .)
[ "$v28_ndocs" -ge 25 ] || v28_bad="$v28_bad [the W1 file set holds $v28_ndocs file(s), floor 25]"
v28_ntab=0
# agents/OPERATE.md is out of scope (its tier axis is OPERATE's own); its table is asserted to exist and to
# stay three-tier, so the exclusion is a checked fact and not a gap.
v28_op=$(v28_tables agents/OPERATE.md)
grep -q 'light=0' <<<"$v28_op" || v28_bad="$v28_bad [exclusion: agents/OPERATE.md no longer has its own three-tier table (found: '$v28_op')]"
for v28_f in $v28_docs; do
  [ "$v28_f" = "agents/OPERATE.md" ] && continue
  while IFS= read -r v28_t; do
    [ -n "$v28_t" ] || continue
    v28_ntab=$((v28_ntab + 1))
    grep -q 'light=1' <<<"$v28_t" || v28_bad="$v28_bad [tier table does not name LIGHT: ${v28_t%% rows*}]"
    grep -qE 'ragged= *$' <<<"$v28_t" || v28_bad="$v28_bad [tier table has a row whose cell count differs from the header: ${v28_t#*ragged=}  in ${v28_t%% rows*}]"
  done < <(v28_tables "$v28_f")
done
[ "$v28_ntab" -ge 4 ] || v28_bad="$v28_bad [only $v28_ntab tier table(s) found, floor 4: mozart.md tiers, PIPELINE adjustments, PIPELINE tier policy, README]"
for v28_f in agents/mozart.md agents/PIPELINE.md README.md; do
  [ "$(v28_tables "$v28_f" | grep -c .)" -ge 1 ] || v28_bad="$v28_bad [no tier table found in $v28_f]"
done
[ "$(v28_tables agents/PIPELINE.md | grep -c .)" = "2" ] || v28_bad="$v28_bad [agents/PIPELINE.md must hold exactly two tier tables (adjustments and codex policy)]"
grep -qxF '| Stage | TINY | LIGHT | STANDARD | HEAVY |' agents/PIPELINE.md \
  || v28_bad="$v28_bad [named member absent: agents/PIPELINE.md header row '| Stage | TINY | LIGHT | STANDARD | HEAVY |']"

# ---- 2. enumeration lines ---------------------------------------------------
# Exclusions are statements about a named tier or the OPERATE tier axis, not enumerations of the
# DELIVER tiers. Each fingerprint must still be present exactly once, so the exclusion is a checked fact.
v28_excl=$(cat <<'V28_EXCL_EOF'
agents/PIPELINE.md	**Tiers:** TINY
agents/STATE.md	The same rule already works well on TINY campaigns
V28_EXCL_EOF
)
v28_gap_all=$(v28_gaps $v28_docs | grep -v '^agents/OPERATE\.md:')
while IFS=$'\t' read -r v28_xf v28_xp; do
  [ -n "$v28_xf" ] || continue
  [ "$(grep -cF -- "$v28_xp" "$v28_xf")" = "1" ] || v28_bad="$v28_bad [exclusion fingerprint not present exactly once in $v28_xf: $v28_xp]"
  v28_gap_all=$(printf '%s\n' "$v28_gap_all" | grep -vF -- "$v28_xp")
done < <(printf '%s\n' "$v28_excl")
v28_gap_all=$(printf '%s\n' "$v28_gap_all" | grep .)
[ -z "$v28_gap_all" ] || v28_bad="$v28_bad [lines naming TINY and STANDARD but not LIGHT: $(printf '%s' "$v28_gap_all" | cut -c1-90 | tr '\n' ';')]"
v28_nenum=$(for v28_f in $v28_docs; do grep 'TINY' "$v28_f" | grep -c 'STANDARD' ; done | awk '{ s += $1 } END { print s + 0 }')
[ "$v28_nenum" -ge 12 ] || v28_bad="$v28_bad [only $v28_nenum line(s) name TINY and STANDARD, floor 12: the derivation lost its population]"
[ "$(grep -cF 'When unsure between STANDARD and HEAVY' agents/OPERATE.md)" = "1" ] \
  || v28_bad="$v28_bad [control: agents/OPERATE.md must keep its own 'When unsure between STANDARD and HEAVY' exactly once]"
[ "$(grep -cF 'When unsure between STANDARD and HEAVY' agents/mozart.md)" = "0" ] \
  || v28_bad="$v28_bad [agents/mozart.md still carries 'When unsure between STANDARD and HEAVY']"

# ---- 3. mozart.md tier text -------------------------------------------------
v28_mz=$(v28_sec agents/mozart.md '^## Task tiers' '^## ')
[ "$(printf '%s\n' "$v28_mz" | grep -c .)" -ge 8 ] || v28_bad="$v28_bad [agents/mozart.md '## Task tiers' section is missing or under 8 lines]"
v28_mz_light=$(v28_rows "$v28_mz" LIGHT)
[ "$(printf '%s\n' "$v28_mz_light" | grep -c .)" = "1" ] || v28_bad="$v28_bad [agents/mozart.md tier table must hold exactly one LIGHT row]"
for v28_p in 'short plan' 'bob' 'codex r2 runs'; do
  grep -qF -- "$v28_p" <<<"$v28_mz_light" || v28_bad="$v28_bad [mozart.md LIGHT row does not say '$v28_p']"
done
grep -qiE 'skip[^;|]*codex r2|codex r2 (is )?(skipped|optional)' <<<"$v28_mz_light" && v28_bad="$v28_bad [mozart.md LIGHT row skips or softens codex r2]"
grep -qF 'sub-50-LOC' <<<"$v28_mz_light" && v28_bad="$v28_bad [mozart.md LIGHT row carries the sub-50-LOC skip clause]"
v28_once "$v28_mz" "any term in xander's stage-4 or stage-8 trigger row makes the campaign not LIGHT" "mozart.md tier text"
v28_once "$v28_mz" 'lockfile lines never count toward the size bound' "mozart.md tier text"
v28_once "$v28_mz" 'disqualifies LIGHT outright' "mozart.md tier text"
v28_once "$v28_mz" 'a cause stated only in an untrusted ticket body counts as unknown' "mozart.md tier text"
[ "$(v28_occ "$v28_mz" "$v28_hi_re")" = "1" ] || v28_bad="$v28_bad [mozart.md tier text must say take-the-higher exactly once, counted per occurrence not per line (found $(v28_occ "$v28_mz" "$v28_hi_re"))]"
[ "$(v28_occ "$v28_mz" 'take the higher')" = "1" ] || v28_bad="$v28_bad [mozart.md tier text: 'take the higher' occurs $(v28_occ "$v28_mz" 'take the higher') time(s), want exactly 1]"
v28_once "$v28_mz" 'is not LIGHT when the work touches a HEAVY surface' "mozart.md tier text"
grep -iF 'is not LIGHT when the work touches a HEAVY surface' <<<"$v28_mz" | grep -qiF 'otto or nina trigger' || v28_bad="$v28_bad [mozart.md tier text: the HEAVY-surface ineligibility sentence does not name the otto or nina trigger]"
v28_once "$v28_mz" 'bob flags any trigger term he sees in a LIGHT plan' "mozart.md tier text"
v28_once "$v28_mz" 'every listed word that applies' "mozart.md tier text"
v28_once "$v28_mz" "any term in xander's stage-8 row maps to \`security\`" "mozart.md tier text"
v28_once "$v28_mz" 'xander reviews the cumulative diff since the base once' "mozart.md tier text"
v28_once "$v28_mz" 'when that surface includes `auth`, `secrets` or `security`, xander is spawned on every phase' "mozart.md tier text (F55)"
v28_once "$v28_mz" 'the tier follows the surface' "mozart.md tier text"
v28_once "$v28_mz" 'tiers only go up' "mozart.md tier text"
v28_esc=$(printf '%s\n' "$v28_mz" | grep -i -F 'tiers only go up')
for v28_p in 'update `**Tier**:` in place' 'log the decision' 'run the stages the higher tier requires that have not run' 'give each ticked phase its conductor row' 'xander reviews the cumulative diff since the base once'; do
  grep -qF -- "$v28_p" <<<"$v28_esc" || v28_bad="$v28_bad [the escalation rule does not say: $v28_p]"
done
v28_list='`auth`, `secrets`, `schema`, `migrations`, `infra`, `billing`, `security`'
[ "$(printf '%s\n' "$v28_mz" | grep -cF -- "$v28_list")" = "1" ] || v28_bad="$v28_bad [the closed seven-word surface list must occur on exactly one line of mozart.md's tier text]"
# INCIDENT's own sentence is about SEV levels, not DELIVER tiers; it is asserted present so the exclusion is a fact.
[ "$(grep -cF 'When unsure between SEV levels: choose the higher one' agents/INCIDENT.md)" = "1" ] \
  || v28_bad="$v28_bad [control: agents/INCIDENT.md must keep its own SEV-level sentence exactly once]"
v28_cut() { # $1 = file -> its text with that file's own allowed sentence cut out, so what remains is scanned
  case "$1" in
    agents/INCIDENT.md) sed 's/When unsure between SEV levels: choose the higher one//' "$1" ;;
    agents/PIPELINE.md) sed 's/When unsure, pick the higher\.//' "$1" ;;
    agents/mozart.md)   sed 's/LIGHT and STANDARD, take the higher//' "$1" ;;
    agents/OPERATE.md)  sed 's/When unsure between STANDARD and HEAVY: choose HEAVY\.//' "$1" ;;
    *) cat "$1" ;;
  esac
}
v28_cut_scan() { # $1 = ERE, rest = files -> file:line:text of every match left after each file's own sentence is cut out
  local re="$1" f; shift
  for f in "$@"; do v28_cut "$f" | grep -nEi -- "$re" | sed "s|^|$f:|"; done
}
v28_gen=$(v28_cut_scan 'unsure between[^.]*(choose|the) higher|when unsure[^.]*(^|[^A-Za-z])HEAVY([^A-Za-z]|$)' agents/*.md)
[ -z "$v28_gen" ] || v28_bad="$v28_bad [a general 'when unsure, the higher' sentence returned: $(printf '%s' "$v28_gen" | cut -c1-80 | head -2 | tr '\n' ';')]"
# F57: the sentence is banned in any form, in every doc a reader meets, not only the literal 'unsure between'. Two
# SEV-level sentences are about incident severity, not DELIVER tiers; each is asserted present so the exclusion is a fact.
v28_sevline=$(grep -F 'When unsure, pick the higher.' agents/PIPELINE.md)
{ [ "$(printf '%s\n' "$v28_sevline" | grep -c .)" = "1" ] && grep -qF 'SEV1' <<<"$v28_sevline"; } \
  || v28_bad="$v28_bad [control: agents/PIPELINE.md must keep its SEV-tiers sentence 'When unsure, pick the higher.' on exactly one line, the one naming SEV1]"
v28_hi=$(v28_cut_scan "$v28_hi_re" $v28_docs INTEGRATION.md)
[ -z "$v28_hi" ] || v28_bad="$v28_bad [a general take-the-higher-tier sentence outside the one in mozart.md's tier text: $(printf '%s' "$v28_hi" | cut -c1-80 | head -2 | tr '\n' ';')]"
# F73: the verb list above only sees the phrasings someone thought of. The bare word is rarer than any verb list:
# a line that says "higher" (or "stricter", "more cautious", "round up", "err toward", "err on the side"), or that
# pairs an uncertainty phrase ("unsure", "in doubt", "both fit", "are close", "ties go") with a tier name or SEV in
# one sentence, is a tier-choice rule until proven otherwise. Every such line in the docs is therefore listed below
# WHOLE (file, cksum and byte length of the exact line), with what it is. A line that gains or loses a word, or a
# clause appended after an allowed sentence, changes its cksum and fails here: editing one of these lines on purpose
# means updating its row here on purpose, which is the intent. CHANGELOG.md is excluded by name (it quotes history,
# including the removed tiebreak). The check cannot see a tier-choice rule that avoids every one of those words
# ("prefer the safer tier", "the tier with more review wins"), one split across lines so that no single line holds
# both halves of an uncertainty phrase and a tier name, a file outside the scanned set (agents/*.md, commands/*.md,
# docs/*.md, README.md, INTEGRATION.md, CONTRIBUTING.md, SECURITY.md, PRIVACY.md, tracked files only), or a
# rule hidden in a script's message text.
v28_tier_t='(TINY|LIGHT|STANDARD|HEAVY|SEV)'
v28_tier_u='(unsure|uncertain|in doubt|any doubt|both fit|are close|tiebreak|tie-break|ties go)'
v28_tier_re="higher|stricter|more cautious|round up|err toward|err on the side|${v28_tier_u}[^.]*${v28_tier_t}|${v28_tier_t}[^.]*${v28_tier_u}"
v28_tier_allowed=$(cat <<'V28_TIER_ALLOWED_EOF'
INTEGRATION.md	2685477448	141	stricter reading of the every-phase flag, not a tier rule
agents/DELIVER.md	1398215508	772	12b CI wait wording, not a tier rule
agents/INCIDENT.md	1774561388	143	SEV-level rule incident severity, not DELIVER tiers
agents/INTAKE.md	131050371	156	higher-stakes in an intake table row, not a tier rule
agents/OPERATE.md	3807009027	179	OPERATE own STANDARD/HEAVY sentence
agents/PIPELINE.md	418127979	264	SEV tiers line, incident severity
agents/README.md	132093594	102	higher-level agents, roster table
agents/WORKTREES.md	2965649099	269	higher-than-capacity wording in parallelism cap
agents/ian.md	224804911	99	coverage risk wording
agents/mozart.md	144801029	356	the one tier rule: When two tiers both fit
agents/mozart.md	1069903660	699	escalation rule: stages the higher tier requires
agents/tessa.md	2264529813	238	severity/cost wording
agents/tessa.md	2712955872	215	severity/cost wording
V28_TIER_ALLOWED_EOF
)
v28_line_key() { printf '%s\n' "$1" | cksum | tr ' ' '\t'; }  # -> "crc<TAB>length"
v28_tier_flagged() { # files... -> "file<TAB>crc<TAB>length" for every line the regex flags
  local f l
  for f in "$@"; do
    grep -Ei -- "$v28_tier_re" "$f" | while IFS= read -r l; do printf '%s\t%s\n' "$f" "$(v28_line_key "$l")"; done
  done
}
v28_tier_files=$(git ls-files 'agents/*.md' 'commands/*.md' 'docs/*.md'; printf '%s\n' README.md INTEGRATION.md CONTRIBUTING.md SECURITY.md PRIVACY.md)
[ "$(printf '%s\n' "$v28_tier_files" | grep -c .)" -ge 30 ] || v28_bad="$v28_bad [the tier-choice scan holds fewer than 30 files: it is scanning nothing]"
v28_tier_got=$(v28_tier_flagged $v28_tier_files | sort)
v28_tier_want=$(printf '%s\n' "$v28_tier_allowed" | cut -f1-3 | sort)
[ "$(printf '%s\n' "$v28_tier_allowed" | grep -c .)" = "13" ] || v28_bad="$v28_bad [the allowed tier-choice table holds $(printf '%s\n' "$v28_tier_allowed" | grep -c .) rows, want 13]"
v28_tier_new=$(comm -13 <(printf '%s\n' "$v28_tier_want") <(printf '%s\n' "$v28_tier_got") | cut -f1 | sort -u | tr '\n' ' ')
v28_tier_gone=$(comm -23 <(printf '%s\n' "$v28_tier_want") <(printf '%s\n' "$v28_tier_got") | cut -f1 | sort -u | tr '\n' ' ')
[ -z "$v28_tier_new" ] || v28_bad="$v28_bad [a line that states a tier-choice rule, or edits an allowed one, in: $v28_tier_new(update the allowed row on purpose if the edit is intended)]"
[ -z "$v28_tier_gone" ] || v28_bad="$v28_bad [an allowed tier-choice line changed or vanished in: $v28_tier_gone(update its row on purpose)]"
# Self-tests: the eight shapes the reviewer wrote must be flagged, the allowed sites must not be, and a clause appended to an
# allowed sentence must change its key.
for v28_p in 'When two tiers both fit, settle on the higher tier.' 'If the tiers are close, go higher.' 'Ties go to the higher tier.' \
             'the higher takes precedence' 'When unsure, escalate to the higher tier.' 'When unsure between LIGHT and STANDARD: choose STANDARD.'; do
  grep -qEi -- "$v28_tier_re" <<<"$v28_p" || v28_bad="$v28_bad [self-test: the tier-choice scan did not flag: $v28_p]"
done
v28_mz_rule=$(grep -F 'When two tiers both fit' agents/mozart.md)
v28_inc_rule=$(grep -F 'When unsure between SEV levels' agents/INCIDENT.md)
for v28_p in "$v28_mz_rule, and likewise for STANDARD and HEAVY." "$v28_inc_rule, and likewise for DELIVER tiers."; do
  v28_k=$(printf 'agents/x.md\t%s' "$(v28_line_key "$v28_p")")
  grep -qF -- "$(printf '%s' "$v28_k" | cut -f2-3)" <<<"$v28_tier_allowed" && v28_bad="$v28_bad [self-test: a clause appended to an allowed sentence kept its key: ${v28_p: -40}]"
  grep -qEi -- "$v28_tier_re" <<<"$v28_p" || v28_bad="$v28_bad [self-test: an allowed sentence with a clause appended was not flagged: ${v28_p: -40}]"
done
grep -qEi -- "$v28_tier_re" <<<'The tier follows the surface; with none evident, STANDARD.' && v28_bad="$v28_bad [self-test: the tier-choice scan flagged a sentence with no uncertainty phrase]"
[ "$(grep -cF 'LIGHT and STANDARD, take the higher' agents/mozart.md)" = "1" ] || v28_bad="$v28_bad [control: the one legitimate take-the-higher sentence is not on exactly one line of agents/mozart.md]"
for v28_f in agents/mozart.md agents/PIPELINE.md; do
  [ "$(grep -cF 'an unknown-cause bug is not LIGHT' "$v28_f")" = "1" ] || v28_bad="$v28_bad [$v28_f must say 'an unknown-cause bug is not LIGHT' on exactly one line]"
done
for v28_f in agents/INTAKE.md README.md commands/mozart.md; do
  grep -F 'DIAGNOSE first' "$v28_f" | grep -qF 'STANDARD/HEAVY' || v28_bad="$v28_bad [control: $v28_f must keep its bug-shaped line naming DIAGNOSE first on STANDARD/HEAVY]"
done

# ---- 4. every-phase variants and the HEAVY mid-build rows ------------------
v28_variant_re='HEAVY: always|mandatory[^|.]{0,40}every phase|(run|runs) on every phase|on every phase regardless|mandatory;? others|HEAVY-tier always'
v28_variant=$(for v28_f in $v28_docs INTEGRATION.md; do
  # the one legitimate sentence is cut out of the line before matching, so a variant written beside it on the same line still hits
  sed 's/xander runs on every phase when that surface is/XANDER-SURFACE-RULE/' "$v28_f" | grep -nE "$v28_variant_re" | sed "s|^|$v28_f:|"
done)
for v28_p in 'HEAVY: always run xander' 'ian and xander run on every phase regardless'; do
  printf '%s\n' "$v28_p; xander runs on every phase when that surface is auth" | sed 's/xander runs on every phase when that surface is/XANDER-SURFACE-RULE/' | grep -qE "$v28_variant_re" \
    || v28_bad="$v28_bad [self-test: a variant beside the xander surface rule was masked: $v28_p]"
done
printf '%s\n' 'and xander runs on every phase when that surface is auth' | sed 's/xander runs on every phase when that surface is/XANDER-SURFACE-RULE/' | grep -qE "$v28_variant_re" \
  && v28_bad="$v28_bad [self-test: the xander surface rule alone was read as an every-phase variant]"
[ -z "$v28_variant" ] || v28_bad="$v28_bad [every-phase wording survives: $(printf '%s' "$v28_variant" | cut -c1-70 | tr '\n' ';')]"
# The scan also covers commands/*.md, docs/*.md and INTEGRATION.md (W2's own population). INTEGRATION.md's one hit is the
# xander-on-every-phase rule for an auth, secrets or security surface, not the old unconditional rule; it is subtracted by
# fingerprint and pinned present in section 6 below, so the allow-list names real text.
# The three W2 allow-list lines do not match the variant regex; each is asserted still present so the
# allow-list names real, unedited text rather than a line that has since moved.
for v28_a in 'agents/valerie.md|By the time you run, every phase has been committed' 'agents/OPERATE.md|mandatory xander at the pre-flight gate' 'agents/FLOWS.md|every phase gate returned a needs-revision test punch list'; do
  [ "$(grep -cF -- "${v28_a#*|}" "${v28_a%%|*}")" = "1" ] || v28_bad="$v28_bad [W2 allow-list line moved or was edited: ${v28_a%%|*}]"
done
v28_pipe_adj=$(v28_sec agents/PIPELINE.md '^### Tier adjustments' '^### ')
v28_pipe_pol=$(v28_sec agents/PIPELINE.md '^### Tier policy' '^### ')
v28_pipe_s2b=$(v28_sec agents/PIPELINE.md '^### Constraints triggers [(]stage 2b' '^### ')
v28_pipe_s4=$(v28_sec agents/PIPELINE.md '^### Reviewer triggers [(]stage 4' '^### ')
v28_pipe_s8=$(v28_sec agents/PIPELINE.md '^### Mid-build specialist triggers [(]stage 8' '^### ')
v28_del_s2b=$(v28_sec agents/DELIVER.md '^### 2b\. Constraints' '^### ')
v28_del_s4=$(v28_sec agents/DELIVER.md '^### 4\. Internal review' '^### ')
v28_del_s7=$(v28_sec agents/DELIVER.md '^### 7\. Implement' '^### ')
v28_del_s8=$(v28_sec agents/DELIVER.md '^### 8\. Mid-build specialists' '^### ')
v28_del_s9=$(v28_sec agents/DELIVER.md '^### 9\. External review' '^### ')
for v28_pair in "PIPELINE adjustments:$v28_pipe_adj" "PIPELINE policy:$v28_pipe_pol" "PIPELINE 2b:$v28_pipe_s2b" "PIPELINE 4:$v28_pipe_s4" "PIPELINE 8:$v28_pipe_s8" \
                "DELIVER 2b:$v28_del_s2b" "DELIVER 4:$v28_del_s4" "DELIVER 7:$v28_del_s7" "DELIVER 8:$v28_del_s8" "DELIVER 9:$v28_del_s9"; do
  [ "$(printf '%s\n' "${v28_pair#*:}" | grep -c .)" -ge 3 ] || v28_bad="$v28_bad [section '${v28_pair%%:*}' is missing or under 3 lines: its heading was renamed]"
done
# Tables: LIGHT cells, by header and row.
v28_cells=0
for v28_chk in "adj|Research|skip" "adj|Constraints|skip" "adj|Plan-review|bob only" "adj|Codex r1|skip" "adj|Mid-build|conditional" "adj|Codex r2|run"; do
  v28_k=${v28_chk%%|*}; v28_r=${v28_chk#*|}; v28_want=${v28_r#*|}; v28_r=${v28_r%%|*}
  v28_got=$(v28_cell "$v28_pipe_adj" "$v28_r" LIGHT)
  v28_cells=$((v28_cells + 1))
  [ "$v28_got" = "$v28_want" ] || v28_bad="$v28_bad [PIPELINE Tier adjustments: row '$v28_r' LIGHT cell is '$v28_got', want '$v28_want']"
done
[ "$(v28_cell "$v28_pipe_adj" 'Codex r2' STANDARD)" = "default-run" ] || v28_bad="$v28_bad [PIPELINE Tier adjustments: Codex r2 STANDARD cell is not default-run]"
[ "$(v28_cell "$v28_pipe_pol" LIGHT 'Codex r2 (diff)')" = "run" ] || v28_bad="$v28_bad [PIPELINE Tier policy: the LIGHT row's Codex r2 cell is not run]"
[ "$(v28_cell "$v28_pipe_pol" LIGHT 'Codex r1 (plan)')" = "skip" ] || v28_bad="$v28_bad [PIPELINE Tier policy: the LIGHT row's Codex r1 cell is not skip]"
[ "$(v28_cell "$v28_pipe_pol" STANDARD 'Codex r2 (diff)')" = "default-run" ] || v28_bad="$v28_bad [PIPELINE Tier policy: the STANDARD row's Codex r2 cell is not default-run]"
# Rows by heading, exactly one each. DELIVER's stage-2b section holds prose, not a table (the plan assumed a row).
v28_x_del4=$(v28_rows "$v28_del_s4" xander); v28_x_del8=$(v28_rows "$v28_del_s8" xander); v28_i_del8=$(v28_rows "$v28_del_s8" ian)
v28_x_pip4=$(v28_rows "$v28_pipe_s4" xander); v28_x_pip8=$(v28_rows "$v28_pipe_s8" xander); v28_i_pip8=$(v28_rows "$v28_pipe_s8" ian)
v28_x_pip2b=$(v28_rows "$v28_pipe_s2b" xander)
for v28_pair in "DELIVER stage-4 xander:$v28_x_del4" "DELIVER stage-8 xander:$v28_x_del8" "DELIVER stage-8 ian:$v28_i_del8" \
                "PIPELINE stage-4 xander:$v28_x_pip4" "PIPELINE stage-8 xander:$v28_x_pip8" "PIPELINE stage-8 ian:$v28_i_pip8" "PIPELINE stage-2b xander:$v28_x_pip2b"; do
  [ "$(printf '%s\n' "${v28_pair#*:}" | grep -c .)" = "1" ] || v28_bad="$v28_bad [${v28_pair%%:*}: the heading-scoped extraction must yield exactly one row]"
done
for v28_pair in "DELIVER stage-8 xander:$v28_x_del8" "DELIVER stage-8 ian:$v28_i_del8" "PIPELINE stage-8 xander:$v28_x_pip8" "PIPELINE stage-8 ian:$v28_i_pip8"; do
  grep -qF 'touches the recorded HEAVY surface' <<<"${v28_pair#*:}" || v28_bad="$v28_bad [${v28_pair%%:*} row lacks the surface-trigger phrase 'touches the recorded HEAVY surface']"
done
for v28_pair in "DELIVER stage-4:$v28_x_del4" "DELIVER stage-8:$v28_x_del8" "PIPELINE stage-4:$v28_x_pip4" "PIPELINE stage-8:$v28_x_pip8"; do
  v28_m=$(v28_missing "${v28_pair#*:}" | tr '\n' ',')
  [ -z "$v28_m" ] || v28_bad="$v28_bad [${v28_pair%%:*} xander row lacks union term(s): $v28_m]"
done
v28_n_terms=$(printf '%s\n' "$v28_terms" | grep -c .)
[ "$v28_n_terms" = "12" ] || v28_bad="$v28_bad [the union term table holds $v28_n_terms terms, want 12]"
grep -qF 'CSP' <<<"$v28_x_pip4$v28_x_del4" || v28_bad="$v28_bad [named member CSP absent from the stage-4 rows]"
grep -qF 'outbound requests' <<<"$v28_x_pip8$v28_x_del8" || v28_bad="$v28_bad [named member 'outbound requests' absent from the stage-8 rows]"
# The stage-2b trigger is deliberately narrower: asserted, so the exclusion is a fact and not an omission.
grep -qF 'CSP' <<<"$v28_x_pip2b" && v28_bad="$v28_bad [PIPELINE stage-2b xander row carries CSP: it must stay narrower than stage 4 and stage 8]"
grep -qF 'CSP' <<<"$v28_del_s2b" && v28_bad="$v28_bad [DELIVER stage-2b section carries CSP: it must stay narrower than stage 4 and stage 8]"
v28_xm=$(v28_missing "$(sed -n '/^Mozart invokes you on plans or slices/p' agents/xander.md)" | tr '\n' ',')
[ -z "$v28_xm" ] || v28_bad="$v28_bad [agents/xander.md trigger paragraph lacks union term(s): $v28_xm]"
grep -q '^Mozart invokes you on plans or slices' agents/xander.md || v28_bad="$v28_bad [agents/xander.md trigger paragraph moved: its first words changed]"
# The stage-8 section holds each HEAVY rule once, and the closed list in the same words as mozart.md.
v28_once "$v28_del_s8" 'ian and xander both run' "DELIVER stage 8"
v28_once "$v28_del_s8" 'xander is spawned on every phase' "DELIVER stage 8"
v28_once "$v28_del_s8" 'The surface record is required' "DELIVER stage 8"
v28_once "$v28_del_s8" 'counts as touching the surface on every phase' "DELIVER stage 8"
[ "$(printf '%s\n' "$v28_del_s8" | grep -cF -- "$v28_list")" = "1" ] || v28_bad="$v28_bad [DELIVER stage 8: the closed surface list must occur on exactly one line, in the same words as mozart.md]"
grep -F 'xander is spawned on every phase' <<<"$v28_del_s8" | grep -qE 'auth.*secrets.*security' \
  || v28_bad="$v28_bad [DELIVER stage 8: the xander-every-phase rule does not name auth, secrets and security]"
# Stage 4 head and the LIGHT bullet in stage 9.
v28_once "$v28_del_s4" "any term in xander's stage-4 or stage-8 trigger row makes the campaign not LIGHT" "DELIVER stage 4"
v28_s4_at=$(printf '%s\n' "$v28_del_s4" | grep -niF "any term in xander's stage-4 or stage-8 trigger row makes the campaign not LIGHT" | head -1 | cut -d: -f1)
v28_s4_tab=$(printf '%s\n' "$v28_del_s4" | grep -n '^| Reviewer |' | head -1 | cut -d: -f1)
{ [ -n "$v28_s4_at" ] && [ -n "$v28_s4_tab" ] && [ "$v28_s4_at" -lt "$v28_s4_tab" ]; } \
  || v28_bad="$v28_bad [DELIVER stage 4: the LIGHT-ineligibility sentence is not at the head, before the reviewer table (sentence line '$v28_s4_at', table line '$v28_s4_tab')]"
v28_light=$(printf '%s\n' "$v28_del_s9" | grep -E '^- [*][*]LIGHT[*][*]:')
[ "$(printf '%s\n' "$v28_light" | grep -c .)" = "1" ] || v28_bad="$v28_bad [DELIVER stage 9 must hold exactly one LIGHT bullet]"
[ "$(printf '%s' "$v28_light" | sed 's/^- [*][*]LIGHT[*][*]: *//; s/ *$//')" = "run" ] || v28_bad="$v28_bad [DELIVER stage 9 LIGHT bullet text is not exactly 'run': $v28_light]"
grep -qi 'skip' <<<"$v28_light" && v28_bad="$v28_bad [DELIVER stage 9 LIGHT bullet contains skip]"
[ "$(printf '%s\n' "$v28_del_s9" | grep -c 'sub-50-LOC')" = "1" ] || v28_bad="$v28_bad [DELIVER stage 9 must carry the sub-50-LOC clause exactly once]"
grep -E '^- [*][*]STANDARD[*][*]:' <<<"$v28_del_s9" | grep -qF 'sub-50-LOC' || v28_bad="$v28_bad [the sub-50-LOC clause is not on the STANDARD bullet]"

# ---- 4b. review-round policy added after phase 7 (F50-F56, F58) -------------
# Each policy sentence is pinned where it lives, by heading, so weakening one copy fails here instead of in review.
# F58 (contract 7.5 control): the context-pressure prohibition still covers phase 1 and every triggered phase.
[ "$(v28_occ "$(cat agents/mozart.md)" 'on phase 1 and on every triggered phase')" = "1" ] \
  || v28_bad="$v28_bad [agents/mozart.md: the context-pressure prohibition 'on phase 1 and on every triggered phase' is not present exactly once]"
# F50: LIGHT eligibility is re-checked against the diff at the per-phase gate, and bob flags trigger terms in the plan.
v28_once "$v28_del_s7" 'LIGHT eligibility re-check' "DELIVER stage 7"
v28_rc=$(printf '%s\n' "$v28_del_s7" | grep -iF 'LIGHT eligibility re-check')
for v28_p in 'git diff --name-only' '.github/workflows/' 'dependency manifest or lockfile' 'twelve terms' 'escalation rule in `mozart.md`'; do
  grep -qF -- "$v28_p" <<<"$v28_rc" || v28_bad="$v28_bad [DELIVER stage 7 LIGHT re-check does not say: $v28_p]"
done
v28_once "$v28_del_s4" 'bob flags any trigger term he sees in a LIGHT plan' "DELIVER stage 4"
v28_once "$v28_pipe_adj" 'bob flags any trigger term he sees in a LIGHT plan' "PIPELINE tier adjustments"
v28_bob=$(cat agents/bob.md)
v28_once "$v28_bob" 'On a LIGHT plan you review alone' "agents/bob.md"
grep -iF 'On a LIGHT plan you review alone' <<<"$v28_bob" | grep -qiF "flag any term in xander's stage-4 trigger row" \
  || v28_bad="$v28_bad [agents/bob.md: the LIGHT duty does not name xander's stage-4 trigger row]"
# F51: a HEAVY surface or an otto or nina trigger also makes the campaign not LIGHT, in both homes of the security sentence.
v28_once "$v28_del_s4" 'is not LIGHT when the work touches a HEAVY surface' "DELIVER stage 4"
grep -iF 'is not LIGHT when the work touches a HEAVY surface' <<<"$v28_del_s4" | grep -qiF 'otto or nina trigger' \
  || v28_bad="$v28_bad [DELIVER stage 4: the HEAVY-surface ineligibility sentence does not name the otto or nina trigger]"
v28_once "$v28_pipe_adj" 'a HEAVY surface' "PIPELINE tier adjustments"
# F52: the surface record names every listed word that applies; any xander-row term is `security`.
v28_once "$v28_del_s8" 'every listed word that applies' "DELIVER stage 8"
v28_once "$v28_del_s8" "any term in xander's stage-8 row maps to \`security\`" "DELIVER stage 8"
# F54: one xander pass over the cumulative diff on escalation, and the pre-escalation row form says so.
v28_state=$(cat agents/STATE.md)
v28_once "$v28_state" "xander's cumulative-diff pass on escalation covers it" "agents/STATE.md"
v28_once "$v28_state" 'xander field must be `run`' "agents/STATE.md"
v28_xan=$(cat agents/xander.md)
v28_once "$v28_xan" 'cumulative diff since the base' "agents/xander.md"
# F62/F63: the escalation pass has one record shape (a Tier line clause and a linked conductor row), named in the
# rule's homes and read by the linter; the pre-escalation row form is accepted only against that record.
v28_once "$v28_mz" 'uncommitted phase diff included' "mozart.md tier text"
v28_once "$v28_mz" 'escalated from <TIER>, D<n>' "mozart.md tier text"
v28_once "$v28_mz" 'xander: cumulative pass on escalation (through P<k>): run' "mozart.md tier text"
v28_once "$v28_del_s8" 'xander reviews the cumulative diff since the base once' "DELIVER stage 8"
v28_once "$v28_del_s8" 'uncommitted phase diff included' "DELIVER stage 8"
v28_once "$v28_pipe_s8" 'uncommitted phase diff included' "PIPELINE stage 8"
grep -qF 'uncommitted phase diff included' <<<"$v28_x_pip8" || v28_bad="$v28_bad [PIPELINE stage-8 xander row does not name the escalation pass with the uncommitted phase diff]"
grep -F 'Your DELIVER stages' <<<"$v28_xan" | grep -qF 'uncommitted phase diff included' || v28_bad="$v28_bad [agents/xander.md stages line does not say the escalation pass includes the uncommitted phase diff]"
v28_once "$v28_state" 'escalated from <TIER>, D<n>' "agents/STATE.md"
v28_once "$v28_state" 'xander: cumulative pass on escalation (through P<k>): run' "agents/STATE.md"
v28_once "$v28_state" 'P2` < `P2a` < `P2b` < `P3`' "agents/STATE.md"
v28_once "$v28_state" 'this qualifies the paragraph above' "agents/STATE.md"
v28_once "$v28_del_s8" 'xander: cumulative pass on escalation (through P<k>): run' "DELIVER stage 8"
# The documented claim form is the one the linter reads: feed STATE.md's own form, with P<k> filled in, to the library.
v28_claim=$(grep -o 'xander: cumulative pass on escalation (through P<k>): run' agents/STATE.md | head -1 | sed 's/P<k>/P3/')
v28_thr=$(awk -v c="$v28_claim" "$v28_lib"$'\n''BEGIN { printf "%s", escalation_pass_through(c) }' </dev/null 2>&1)
[ "$v28_thr" = "P3" ] || v28_bad="$v28_bad [the claim form STATE.md documents ('$v28_claim') is not read by the library's escalation_pass_through (got '$v28_thr')]"
v28_once "$v28_state" 'dated 2026-10-04 or later' "agents/STATE.md"
# F74: README states the same LIGHT ineligibility as agents/mozart.md, in its tier-table row and its tier paragraph.
v28_rd_row=$(grep -F '| **LIGHT** |' README.md)
v28_rd_par=$(grep -F 'A security-relevant change' README.md)
for v28_p in 'no otto or nina trigger' 'no dependency manifest, lockfile or CI change' 'no security or other HEAVY surface'; do
  v28_once "$v28_rd_row" "$v28_p" "README.md LIGHT row"
done
for v28_p in 'an otto or nina trigger' 'a dependency manifest, lockfile or CI change' 'is never LIGHT'; do
  v28_once "$v28_rd_par" "$v28_p" "README.md tier paragraph"
done
[ "$(printf '%s\n' "$v28_rd_row" | grep -c .)" = "1" ] && [ "$(printf '%s\n' "$v28_rd_par" | grep -c .)" = "1" ] || v28_bad="$v28_bad [README.md must hold exactly one LIGHT table row and one tier paragraph sentence]"
# F76: docs/EVAL.md names the residue this campaign created in its sampled-residue paragraph (## Findings).
v28_ev=$(v28_sec docs/EVAL.md '^## Findings' '^## ')
for v28_p in '`external — …` origins in `Traces-to` lines' 'the escalation pass row' 'a dishonest `xander: run` or `through P<k>`' 'a lowered tier, a surface record that omits a word that applies, or free text after `;`'; do
  v28_once "$v28_ev" "$v28_p" "docs/EVAL.md Findings paragraph"
done
grep -qF 'escalation_pass_through(cr_claim[id])' scripts/mozart-lint.sh || v28_bad="$v28_bad [scripts/mozart-lint.sh no longer reads the escalation-pass claim through the library's escalation_pass_through]"
grep -qF 'escalated from (TINY|LIGHT|STANDARD), D' scripts/lib-campaign.sh || v28_bad="$v28_bad [scripts/lib-campaign.sh no longer reads the Tier clause 'escalated from <TIER>, D<n>' the docs name]"
v28_once "$v28_pipe_adj" 'STANDARD at minimum, and HEAVY when the work is on that surface' "PIPELINE tier adjustments"
# F55: the xander-on-every-phase rule is pinned at every copy, not only in DELIVER stage 8.
v28_once "$v28_pipe_s8" 'every phase when the surface is auth, secrets or security' "PIPELINE stage 8"
grep -qF 'every phase when the surface is auth, secrets or security' <<<"$v28_x_pip8" \
  || v28_bad="$v28_bad [PIPELINE stage-8 xander row does not carry 'every phase when the surface is auth, secrets or security']"
grep -F 'Your DELIVER stages' <<<"$v28_xan" | grep -qF 'every phase when that surface is auth, secrets or security' \
  || v28_bad="$v28_bad [agents/xander.md stages line does not carry 'every phase when that surface is auth, secrets or security']"
grep '^Mozart invokes you on plans or slices' <<<"$v28_xan" | grep -qF 'every phase when that surface is auth, secrets or security' \
  || v28_bad="$v28_bad [agents/xander.md trigger paragraph does not carry 'every phase when that surface is auth, secrets or security']"
grep -F 'Your DELIVER stages' <<<"$v28_xan" | grep -qF 'makes it not LIGHT' \
  || v28_bad="$v28_bad [agents/xander.md stages line does not say a xander trigger makes the campaign not LIGHT]"
grep -qF 'LIGHT and STANDARD: on triggers' <<<"$v28_xan" && v28_bad="$v28_bad [agents/xander.md still says LIGHT runs xander on triggers]"
# F55: stage 2b stays narrow term by term: every union term the narrow trigger does not name is absent from both 2b texts.
v28_2b_missing=$( { v28_missing "$v28_x_pip2b"; v28_missing "$v28_del_s2b"; } | sort | uniq -c | awk '$1 == 2 { sub(/^ *2 /, ""); print }')
for v28_t in 'auth' 'secrets' 'untrusted input' 'encryption' 'sessions' 'RBAC' 'security headers' 'CSP' 'authorization (ownership and tenant filters)' 'outbound requests'; do
  grep -qxF -- "$v28_t" <<<"$v28_2b_missing" || v28_bad="$v28_bad [a stage-2b text (PIPELINE row or DELIVER section) names the stage-4/8 union term '$v28_t': 2b must stay narrower]"
done
# F56: a xander-row term removes the STANDARD codex r2 skip.
v28_std9=$(printf '%s\n' "$v28_del_s9" | grep -E '^- [*][*]STANDARD[*][*]:')
v28_has "$v28_std9" "not available when any term in xander's stage-8 trigger row applies" \
  || v28_bad="$v28_bad [DELIVER stage 9 STANDARD bullet does not remove the sub-50-LOC skip when a xander-row term applies]"
# LIGHT-ineligibility, README and FLOWS: no undefined 'security terms'.
v28_flows_impl=$(v28_sec agents/FLOWS.md '^### Implementing an existing plan' '^### ')
[ "$(printf '%s\n' "$v28_flows_impl" | grep -c .)" -ge 5 ] || v28_bad="$v28_bad [agents/FLOWS.md 'Implementing an existing plan' section is missing or under 5 lines]"
v28_once "$v28_flows_impl" "no term in xander's stage-8 row" "agents/FLOWS.md implement-an-existing-plan path"
grep -qF 'free of security terms' agents/FLOWS.md && v28_bad="$v28_bad [agents/FLOWS.md infers LIGHT from undefined 'security terms']"
grep -F 'A security-relevant change' README.md | grep -qF 'HEAVY surface' || v28_bad="$v28_bad [README.md does not say a HEAVY-surface change is never LIGHT]"

# ---- 5. codex r2 wording (W3) ----------------------------------------------
v28_opt=$(grep -niE 'codex r2|codex on diff|9 ·' agents/PIPELINE.md README.md | grep -E 'optional|opt /')
[ -z "$v28_opt" ] || v28_bad="$v28_bad [codex r2 still reads optional: $(printf '%s' "$v28_opt" | cut -c1-70 | tr '\n' ';')]"
v28_tp=$(grep -niE 'codex r2[^()]*[(][^()]*HEAVY[^()]*[)]' agents/*.md README.md | grep -vE 'STANDARD|LIGHT')
[ -z "$v28_tp" ] || v28_bad="$v28_bad [a codex r2 tier parenthetical names HEAVY alone: $(printf '%s' "$v28_tp" | cut -c1-70 | tr '\n' ';')]"
grep -F 'codex round 2' agents/valerie.md | grep -qF 'LIGHT' || v28_bad="$v28_bad [agents/valerie.md's codex round 2 line does not name LIGHT]"
grep -F 'Codex r2<br/>' README.md | grep -qF 'LIGHT' || v28_bad="$v28_bad [named member: README.md's codex r2 mermaid label does not name LIGHT]"
grep -F 'install it from' README.md | grep -qF 'LIGHT' || v28_bad="$v28_bad [named member: README.md's codex sentence does not name LIGHT]"
grep -qF 'Stage 9' agents/mozart.md && grep -F "Stage 9's table reads" agents/mozart.md | grep -qF 'LIGHT: run' \
  || v28_bad="$v28_bad [agents/mozart.md's quotation of the stage-9 table does not read LIGHT: run]"

# ---- 6. EVERY-PHASE, defined once, named in the rest ------------------------
[ "$(grep -c '^- [*][*]EVERY-PHASE[*][*]' agents/FLOWS.md)" = "1" ] || v28_bad="$v28_bad [agents/FLOWS.md must define EVERY-PHASE on exactly one bullet]"
for v28_f in agents/mozart.md agents/DELIVER.md agents/PIPELINE.md agents/INTAKE.md INTEGRATION.md README.md; do
  grep -q 'EVERY-PHASE' "$v28_f" || v28_bad="$v28_bad [$v28_f does not name EVERY-PHASE]"
done
v28_ig=$(v28_sec INTEGRATION.md '^## 6\. Pipeline flags [(]stanza optional[)]' '^---$')
[ "$(printf '%s\n' "$v28_ig" | grep -c .)" -ge 5 ] || v28_bad="$v28_bad [INTEGRATION.md section '6. Pipeline flags (stanza optional)' is missing or under 5 lines]"
grep -qF 'every_phase: true' <<<"$v28_ig" || v28_bad="$v28_bad [INTEGRATION.md section 6 does not show every_phase: true]"
v28_ih=$(v28_sec INTEGRATION.md '^## How agents read these stanzas' '^---$')
grep -F 'every_phase' <<<"$v28_ih" | grep -qE 'never writes' || v28_bad="$v28_bad [INTEGRATION.md How-agents-read paragraph does not say mozart reads every_phase and never writes it]"
v28_once "$v28_ig" 'every listed word that applies' "INTEGRATION.md section 6"
v28_once "$v28_ig" "any term in xander's stage-8 row maps to \`security\`" "INTEGRATION.md section 6"
v28_once "$v28_ig" 'xander runs on every phase when that surface is `auth`, `secrets` or `security`' "INTEGRATION.md section 6 (F55)"
grep -qE 'never writes' <<<"$v28_ig" || v28_bad="$v28_bad [INTEGRATION.md section 6 does not say mozart never writes the stanza]"

# ---- 7. dead persona text (step 28a) ---------------------------------------
[ "$(grep -cE '^## Communicate as you work' agents/mozart.md)" = "0" ] || v28_bad="$v28_bad [agents/mozart.md still has its '## Communicate as you work' section]"
[ "$(grep -c 'You run in a subprocess' agents/mozart.md)" = "0" ] || v28_bad="$v28_bad [agents/mozart.md still says 'You run in a subprocess']"
v28_comm=$(grep -lE '^## Communicate as you work' agents/*.md | grep -vc '^agents/mozart\.md$')
[ "$v28_comm" = "17" ] || v28_bad="$v28_bad [control: $v28_comm agents/*.md besides mozart.md carry the Communicate section, want 17]"
grep -qxF "$(printf 'agents/mozart.md\t55000')" <<<"$v16_budgets" || v28_bad="$v28_bad [the V16 ceiling for agents/mozart.md is no longer 55000]"

# ---- 8. a LIGHT campaign is read by metrics --------------------------------
v28_lf="$gate_root/tests/fixtures/conductor/metrics-light/.mozart/plans/finished/2099-10-20-deliver-light.state.md"
if [ -f "$v28_lf" ]; then
  v28_mk() { # $1 = scratch name, $2 = the Tier line to write -> a one-campaign root
    mkdir -p "$v28_tmp/$1/.mozart/plans/finished"
    awk -v tl="$2" '/^\*\*Tier\*\*:/ { print tl; next } { print }' "$v28_lf" > "$v28_tmp/$1/.mozart/plans/finished/2099-10-20-deliver-light.state.md"
  }
  v28_bucket() { bash "$gate_root/scripts/mozart-metrics.sh" "$v28_tmp/$1" 2>&1 | sed -n 's/^Campaigns: 1 (1 \(.*\))$/\1/p'; }
  v28_tier_template=$(grep -m1 '^[*][*]Tier[*][*]:' agents/TEMPLATE-STATE.md)
  v28_mk plain '**Tier**: LIGHT'
  v28_mk combined '**Shape**: DELIVER | **Tier**: LIGHT | **Mode**: AUTONOMOUS'
  v28_mk template "$v28_tier_template"
  v28_mk heavylist '**Tier**: TINY | LIGHT | STANDARD | HEAVY'
  [ "$(v28_bucket plain)" = "LIGHT" ] || v28_bad="$v28_bad [metrics does not bucket '**Tier**: LIGHT' as LIGHT: '$(v28_bucket plain)']"
  [ "$(v28_bucket combined)" = "LIGHT" ] || v28_bad="$v28_bad [metrics does not bucket a combined header carrying LIGHT as LIGHT: '$(v28_bucket combined)']"
  [ "$(v28_bucket template)" = "UNTIERED" ] || v28_bad="$v28_bad [metrics reads the raw state-template Tier line ($v28_tier_template) as '$(v28_bucket template)', want UNTIERED]"
  [ "$(v28_bucket heavylist)" = "UNTIERED" ] || v28_bad="$v28_bad [metrics reads a pipe-list of all four tiers as '$(v28_bucket heavylist)', want UNTIERED]"
  grep -qF 'TINY | LIGHT | STANDARD | HEAVY' <<<"$v28_tier_template" || v28_bad="$v28_bad [agents/TEMPLATE-STATE.md Tier line does not list LIGHT]"
else
  v28_bad="$v28_bad [the LIGHT metrics fixture is missing]"
fi
# docs/EVAL.md's by-tier bullet and the library's tier comment name LIGHT, positionally.
sed -n '/Catches\/campaign by tier/,/^$/p' docs/EVAL.md | grep -qF 'LIGHT' || v28_bad="$v28_bad [docs/EVAL.md's 'Catches/campaign by tier' bullet does not name LIGHT]"
v28_libc=$(awk '/^function tier_of[(]/ { for (i = n; i >= 1 && c[i] ~ /^#/; i--) print c[i]; exit } { c[++n] = $0 }' scripts/lib-campaign.sh)
[ "$(printf '%s\n' "$v28_libc" | grep -c .)" -ge 5 ] || v28_bad="$v28_bad [scripts/lib-campaign.sh: the comment block directly above tier_of is missing or under 5 lines]"
grep -q 'LIGHT' <<<"$v28_libc" || v28_bad="$v28_bad [scripts/lib-campaign.sh's tier comment (the block directly above tier_of) does not name LIGHT]"
rm -rf "$v28_tmp"
report "V28_tiers" "$([ -z "$v28_bad" ] && echo 0 || echo 1)" \
  "${v28_bad:-$v28_ntab tier tables rectangular and naming LIGHT, $v28_nenum lines name TINY and STANDARD, all but agents/OPERATE.md and 2 asserted-present exclusions name LIGHT, $v28_cells LIGHT cells and the codex r2 cells read by header, xander rows by heading (exactly one each) carry the $v28_n_terms-term union, surface phrase in the stage-8 ian and xander rows of both files, EVERY-PHASE defined once and named in six files, LIGHT metrics bucket; every extractor rejected its planted input first}"

# ---------------------------------------------------------------------------
# V29_noprogress - the no-progress stop (P4, phase 8)
#
# One frozen bullet (tests/policy/no-progress.txt), the fourth item of the
# cadence list in `## Communicate as you work` of each specialist. Population:
# V4's roster, unmodified, minus mozart (mozart's own section was deleted in
# phase 7 and the conductor rule lives in its Orchestration discipline). The
# four support agents (named personas outside the roster) carry no bullet: the
# control for the decision to leave them out. A gate cannot make a specialist
# obey the bullet; this proves the text exists once, in the right list, byte for
# byte, and that the conductor side and the thresholds it sits beside still say
# what the plan's table says.
# ---------------------------------------------------------------------------
v29_policy_file="$gate_root/tests/policy/no-progress.txt"
v29_bad=""
v29_text=""
v29_bytes=0
if [ -s "$v29_policy_file" ] && [ "$(grep -c . "$v29_policy_file")" = "1" ] && [ "$(wc -l < "$v29_policy_file" | tr -d ' ')" = "1" ]; then
  v29_text=$(cat "$v29_policy_file")
  v29_bytes=$(wc -c < "$v29_policy_file" | tr -d ' ')
else
  v29_bad="$v29_bad [tests/policy/no-progress.txt is missing, empty or not a single line]"
fi

# Content pins on the frozen text itself.
if [ -n "$v29_text" ]; then
  [ "$v29_bytes" -le 330 ] || v29_bad="$v29_bad [policy text is $v29_bytes bytes, ceiling 330: the V16 arithmetic for nina, dick and otto depends on it]"
  case "$v29_text" in '- **No progress**: '*) : ;; *) v29_bad="$v29_bad [policy text is not a bullet opening '- **No progress**: ']" ;; esac
  for v29_pin in 'the same command three times with the same result and nothing changed between' \
                 'three turns that do nothing' 'a bounded wait expires twice' \
                 ', stop. Return what you attempted' \
                 'what you attempted, the command, its last output, the likely blocker, and the next step' \
                 'Stuck is a result.'; do
    case "$v29_text" in *"$v29_pin"*) : ;; *) v29_bad="$v29_bad [policy text lacks: $v29_pin]" ;; esac
  done
fi

# One persona file against the policy text; prints the problems, nothing when clean.
v29_check_file() { # $1 = file, $2 = policy text
  local f="$1" text="$2" sec n_all n_sec n_items before after
  sec=$(awk '/^## Communicate as you work[ \t]*$/ { on = 1; next } on && /^## / { exit } on { print }' "$f")
  [ -n "$sec" ] || { printf '[no Communicate section]'; return; }
  n_all=$(grep -cxF -- "$text" "$f" || true)
  n_sec=$(grep -cxF -- "$text" <<<"$sec" || true)
  [ "$n_all" = "1" ] || printf '[bullet occurs %s time(s) in the file, want 1]' "$n_all"
  [ "$n_sec" = "1" ] || printf '[bullet occurs %s time(s) inside the section, want 1]' "$n_sec"
  # The list is the run of bullet lines that holds the policy bullet. Three
  # originals plus this one, except hank's: his cadence is five items of his own
  # (a named exception, asserted, not a loosened count).
  n_items=$(awk -v t="$text" '/^- / { n++; if ($0 == t) hit = 1; next } { if (hit) { print n; done = 1; exit } n = 0 } END { if (hit && !done) print n }' <<<"$sec")
  want_items=4; case "$f" in */hank.md) want_items=6 ;; esac
  [ "$n_items" = "$want_items" ] || printf '[cadence list has %s item(s), want %s]' "${n_items:-0}" "$want_items"
  before=$(grep -xF -B1 -- "$text" <<<"$sec" | head -1)
  case "$before" in '- **On return**'*) : ;; *) printf '[bullet does not follow the On return bullet]' ;; esac
  after=$(grep -xF -A1 -- "$text" <<<"$sec" | sed -n 2p)
  [ -z "$after" ] || printf '[bullet is not the last item of the list]'
}

# The checker can fail: planted personas it must reject, one clean one it must pass.
v29_tmp=$(mktemp -d) || { v29_bad="$v29_bad [mktemp failed]"; v29_tmp=/nonexistent-v29; }
v29_probe="- **Probe**: a planted fourth item"
v29_head=$'## Communicate as you work\n\n- **Before your first tool call**: x\n- **At meaningful checkpoints**: y\n- **On return**: z'
printf '%s\n%s\n\n## Field notes\n' "$v29_head" "$v29_probe" > "$v29_tmp/good.md"
printf '%s\n\n## Field notes\n' "$v29_head" > "$v29_tmp/zero.md"
printf '%s\n%s\n%s\n\n## Field notes\n' "$v29_head" "$v29_probe" "$v29_probe" > "$v29_tmp/twice.md"
printf '%s\n\n## Field notes\n\n%s\n' "$v29_head" "$v29_probe" > "$v29_tmp/outside.md"
printf '## Communicate as you work\n\n- **Before your first tool call**: x\n- **At meaningful checkpoints**: y\n%s\n- **On return**: z\n\n## Field notes\n' "$v29_probe" > "$v29_tmp/misplaced.md"
[ -z "$(v29_check_file "$v29_tmp/good.md" "$v29_probe")" ] || v29_bad="$v29_bad [self-test: a clean planted persona was rejected: $(v29_check_file "$v29_tmp/good.md" "$v29_probe")]"
for v29_planted in zero twice outside misplaced; do
  [ -n "$(v29_check_file "$v29_tmp/$v29_planted.md" "$v29_probe")" ] || v29_bad="$v29_bad [self-test: planted persona '$v29_planted' was not rejected]"
done
rm -rf "$v29_tmp"

# Population: V4's roster minus mozart, equal to the files that carry the section.
v29_n=0
v29_listed=""
if [ -n "$v29_text" ]; then
  while IFS="$(printf '\t')" read -r v29_ag _; do
    [ -n "$v29_ag" ] && [ "$v29_ag" != "mozart" ] || continue
    v29_f="$gate_root/agents/$v29_ag.md"
    v29_n=$((v29_n + 1)); v29_listed="$v29_listed $v29_ag"
    [ -f "$v29_f" ] || { v29_bad="$v29_bad [$v29_ag: no file agents/$v29_ag.md]"; continue; }
    v29_res=$(v29_check_file "$v29_f" "$v29_text")
    [ -z "$v29_res" ] || v29_bad="$v29_bad [$v29_ag: $v29_res]"
  done < <(printf '%s\n' "$v4_roster")
fi
[ "$v29_n" -ge 17 ] || v29_bad="$v29_bad [only $v29_n specialist(s) checked, floor 17]"
v29_carriers=$(grep -lE '^## Communicate as you work' "$gate_root"/agents/*.md | sed 's#.*/##; s#\.md$##' | grep -vx mozart | sort | paste -sd' ' -)
v29_expected=$(printf '%s\n' $v29_listed | sort | paste -sd' ' -)
[ "$v29_carriers" = "$v29_expected" ] || v29_bad="$v29_bad [files carrying a Communicate section ($v29_carriers) differ from the roster minus mozart ($v29_expected)]"
case " $v29_listed " in *" jackson "*) : ;; *) v29_bad="$v29_bad [named member jackson absent from the checked population]" ;; esac

# Named member: jackson's three original items are unmodified and still first.
v29_jack=$(awk '/^## Communicate as you work[ \t]*$/ { on = 1; next } on && /^## / { exit } on && /^- \*\*/ { print }' "$gate_root/agents/jackson.md" | head -3)
v29_jack_want=$(printf '%s\n' \
  '- **Before your first tool call**: one sentence stating what you'"'"'re about to do.' \
  '- **At meaningful checkpoints**: when you find something significant, change direction, or hit a blocker — one sentence each.' \
  '- **On return**: a structured, scannable summary of what you did, what you found, and (if applicable) what you recommend.')
[ "$v29_jack" = "$v29_jack_want" ] || v29_bad="$v29_bad [jackson's three original cadence items changed or moved]"

# Controls: mozart and the support agents carry no bullet.
v29_sup=0
if [ -n "$v29_text" ]; then
  v29_moz=$(grep -cxF -- "$v29_text" "$gate_root/agents/mozart.md" || true)
  [ "$v29_moz" = "0" ] || v29_bad="$v29_bad [agents/mozart.md carries the bullet $v29_moz time(s), want 0]"
  for v29_sf in "$gate_root"/agents/*.md; do
    head -6 "$v29_sf" | grep -q '^name:' || continue
    v29_sn=$(basename "$v29_sf" .md)
    case " $v29_listed mozart " in *" $v29_sn "*) continue ;; esac
    v29_sup=$((v29_sup + 1))
    v29_sc=$(grep -cxF -- "$v29_text" "$v29_sf" || true)
    [ "$v29_sc" = "0" ] || v29_bad="$v29_bad [support agent $v29_sn carries the bullet $v29_sc time(s), want 0]"
  done
  [ "$v29_sup" -ge 4 ] || v29_bad="$v29_bad [only $v29_sup support agent(s) found, floor 4]"
  [ -f "$gate_root/agents/codebase-analyzer.md" ] || v29_bad="$v29_bad [named support agent codebase-analyzer absent]"
fi

# Conductor side. Each phrase is counted inside its own section or on its own
# anchored line, so a copy elsewhere in the file cannot satisfy it.
v29_section() { # $1 = file, $2 = exact heading line
  awk -v h="$2" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$1"
}
v29_od=$(v29_section "$gate_root/agents/mozart.md" '## Orchestration discipline')
v29_rule=$(grep -F '**A no-progress return is information' <<<"$v29_od" || true)
v29_rule_n=$(grep -c . <<<"$v29_rule" || true)
[ "$v29_rule_n" = "1" ] || v29_bad="$v29_bad [Orchestration discipline holds the no-progress rule $v29_rule_n time(s), want exactly 1]"
for v29_pin in 'supply the missing fact' 'continue the live agent' 'same specialist on the same work' 'CONTEXT-BUDGET.md' 'escalate' 'Never a third silent continue'; do
  case "$v29_rule" in *"$v29_pin"*) : ;; *) v29_bad="$v29_bad [the conductor rule lacks: $v29_pin]" ;; esac
done
v29_cap=$(grep -F 'Cap: 3 attempts per phase' "$gate_root/agents/DELIVER.md" || true)
v29_cap_n=$(grep -c . <<<"$v29_cap" || true)
[ "$v29_cap_n" = "1" ] || v29_bad="$v29_bad [DELIVER.md holds the per-phase attempts cap on $v29_cap_n line(s), want 1 (and the number must stay 3)]"
case "$v29_cap" in *'A no-progress return is not an attempt'*) : ;; *) v29_bad="$v29_bad [the DELIVER.md attempts-cap line does not say a no-progress return is not an attempt]" ;; esac
v29_fs=$(grep -F 'After two failed spawns of the same specialist' "$gate_root/agents/CONTEXT-BUDGET.md" || true)
v29_fs_n=$(grep -c . <<<"$v29_fs" || true)
[ "$v29_fs_n" = "1" ] || v29_bad="$v29_bad [CONTEXT-BUDGET.md holds the failed-spawns line $v29_fs_n time(s), want 1 (and the number must stay two)]"
case "$v29_fs" in *'A no-progress return counts as one failed spawn'*) : ;; *) v29_bad="$v29_bad [the CONTEXT-BUDGET.md failed-spawns line does not count a no-progress return as one]" ;; esac
grep -qF 'two polls with no output-file or CPU-time growth' "$gate_root/agents/COUNTERPOINT.md" \
  || v29_bad="$v29_bad [CONTROL: COUNTERPOINT.md's two-poll stall threshold changed]"

# CONTRIBUTING.md item 8 names the bullet once; V15's registry is untouched.
v29_item8=$(grep -E '^8\. \*\*`## Communicate as you work`\*\*' "$gate_root/CONTRIBUTING.md" || true)
v29_item8_n=$(grep -c . <<<"$v29_item8" || true)
[ "$v29_item8_n" = "1" ] || v29_bad="$v29_bad [CONTRIBUTING.md item 8 found $v29_item8_n time(s), want 1]"
v29_item8_np=$(grep -o 'tests/policy/no-progress.txt' <<<"$v29_item8" | grep -c . || true)
[ "$v29_item8_np" = "1" ] || v29_bad="$v29_bad [CONTRIBUTING.md item 8 names tests/policy/no-progress.txt $v29_item8_np time(s), want exactly 1]"
# The section is not the same in every specialist (12 share one text, ian/nina/sarah a second, hank and tessa their own); only the bullet is.
grep -qF 'same in every specialist' <<<"$v29_item8" && v29_bad="$v29_bad [CONTRIBUTING.md item 8 again claims the whole section is the same in every specialist: only the no-progress bullet is]"
[ ! -e "$gate_root/tests/parity/snippets/NP.txt" ] || v29_bad="$v29_bad [CONTROL: tests/parity/snippets/NP.txt exists: the no-progress text is not a V15 snippet]"
v29_np_rows=$(grep -cE '^NP[[:space:]]' <<<"$v15_registry" || true)
[ "$v29_np_rows" = "0" ] || v29_bad="$v29_bad [CONTROL: the V15 registry has $v29_np_rows NP row(s)]"

report "V29_noprogress" "$([ -z "$v29_bad" ] && echo 0 || echo 1)" \
  "${v29_bad:-the frozen no-progress bullet ($v29_bytes bytes) is the fourth item of the cadence list of $v29_n specialists (the V4 roster minus mozart, equal to the files carrying the section), once each, named member jackson with its three original items intact; 0 in mozart.md and in $v29_sup support agents; the conductor rule once in Orchestration discipline, one clause each in DELIVER.md and CONTEXT-BUDGET.md with their numbers unchanged; 5 planted personas judged correctly}"

# ---------------------------------------------------------------------------
# V31_editions_selftest - scripts/check-editions.sh checks itself (phase 9)
#
# check-editions.sh is the only cross-edition check and mozart-codex has no CI,
# so a checker that can exit 0 vacuously, or that can read a skip as a pass,
# would fail unseen until an edition drifted. The fake edition roots are built
# here from THIS tree: each carries the shipped scripts and a copy of the S3
# host file at the path that edition keeps it, so every arm reads real files.
# Two arms run the whole check (behaviour included); the rest pass
# --skip-behaviour, which can never exit 0, and assert the exit-code order
# (1 failure, 3 skip, 2 usage), the RUN/SKIP/FAIL lines, and the mutations.
# ---------------------------------------------------------------------------
v31_script="$gate_root/scripts/check-editions.sh"
v31_bad=""
v31_arms=0
v31_tmp=$(mktemp -d) || { v31_bad="$v31_bad [mktemp failed -- no scratch space for the fake edition roots]"; v31_tmp=/nonexistent-v31; }
v31_s3codex=.codex/skills/mozart/SKILL.md
v31_s3copilot=.github/mozart/manual/STATE.md
v31_s3local=src/mozart_local/bundle/manual/STATE.md

if [ ! -f "$v31_script" ]; then
  v31_bad="$v31_bad [scripts/check-editions.sh is absent]"
elif ! command -v python3 >/dev/null 2>&1; then
  v31_bad="$v31_bad [python3 missing: the behaviour arm cannot run (FAIL, not skip)]"
elif ! bash -n "$v31_script"; then
  v31_bad="$v31_bad [scripts/check-editions.sh does not parse]"
else
  # mk <dest> <s3 host path> <with scripts: 1|0>
  v31_mk() {
    mkdir -p "$1/$(dirname "$2")" || return 1
    cp "$gate_root/agents/STATE.md" "$1/$2" || return 1
    if [ "$3" = 1 ]; then
      mkdir -p "$1/scripts" || return 1
      cp "$gate_root"/scripts/lib-campaign.sh "$gate_root"/scripts/mozart-lint.sh "$gate_root"/scripts/mozart-metrics.sh "$1/scripts/" || return 1
    fi
  }
  v31_mk "$v31_tmp/codex" "$v31_s3codex" 1 && v31_mk "$v31_tmp/copilot" "$v31_s3copilot" 1 \
    && v31_mk "$v31_tmp/local" "$v31_s3local" 0 \
    || v31_bad="$v31_bad [building the fake edition roots failed]"
  # The host file must carry S3 exactly once, or every "present" arm below is
  # measuring a tree the script is right to refuse.
  v31_n=$(python3 -c 'import sys;print(open(sys.argv[2]).read().count(open(sys.argv[1]).read().strip()))' "$gate_root/tests/parity/snippets/S3.txt" "$gate_root/agents/STATE.md")
  [ "$v31_n" = "1" ] || v31_bad="$v31_bad [CONTROL: agents/STATE.md carries S3 $v31_n time(s), want 1]"

  # arm <label> <want rc> <command...>; sets v31_out, v31_rc, checks the code
  v31_arm() {
    v31_label=$1; v31_want=$2; shift 2
    v31_out=$("$@" 2>&1); v31_rc=$?
    v31_arms=$((v31_arms + 1))
    [ "$v31_rc" -eq "$v31_want" ] || v31_bad="$v31_bad [$v31_label: exit $v31_rc, want $v31_want]"
  }
  v31_has() { grep -qE "$2" <<<"$1" || v31_bad="$v31_bad [$3]"; }
  v31_hasnt() { ! grep -qE "$2" <<<"$1" || v31_bad="$v31_bad [$3]"; }
  v31_c="codex=$v31_tmp/codex"; v31_p="copilot=$v31_tmp/copilot"; v31_l="local=$v31_tmp/local"
  # The existing arms below test exit codes and RUN/SKIP/FAIL lines, not the text rows. Each passes
  # --table with one control row per edition that its fake root satisfies (the host file carries the
  # state-persistence heading once), so their outcomes do not depend on the shipped table.
  v31_ctl="$v31_tmp/ctl/parity/ctl.tsv"; mkdir -p "$v31_tmp/ctl/parity"
  {
    printf 'id\tedition\tphase\tkind\tscope\tanchor\trow\texpect\tneedle\n'
    printf 'ctl-v31-%s\t%s\t0\tonce\t%s\t\t\t1\t%s\n' orchestration orchestration agents/STATE.md '## State persistence (crash-resume)'
    printf 'ctl-v31-%s\t%s\t0\tonce\t%s\t\t\t1\t%s\n' codex codex "$v31_s3codex" '## State persistence (crash-resume)'
    printf 'ctl-v31-%s\t%s\t0\tonce\t%s\t\t\t1\t%s\n' copilot copilot "$v31_s3copilot" '## State persistence (crash-resume)'
    printf 'ctl-v31-%s\t%s\t0\tonce\t%s\t\t\t1\t%s\n' local local "$v31_s3local" '## State persistence (crash-resume)'
  } > "$v31_ctl"
  v31_t=(--table "$v31_ctl")

  # 9.1 everything present: four RUN lines, no SKIP, no FAIL, and local counted
  #     by its S3 run. Argument roots beat the environment. --skip-behaviour
  #     makes this a partial run, which exits 4 and never 0; the one arm that
  #     runs the behaviour arm too is the environment arm below.
  v31_arm "all present, partial" 4 env MOZART_EDITION_ROOTS=/nonexistent-v31-a:/nonexistent-v31-b:/nonexistent-v31-c \
    bash "$v31_script" "${v31_t[@]}" --skip-behaviour "$v31_tmp/codex" "$v31_tmp/copilot" "$v31_tmp/local"
  [ "$(grep -c '^RUN ' <<<"$v31_out" || true)" = "4" ] || v31_bad="$v31_bad [all present: not exactly four RUN lines]"
  for v31_e in orchestration codex copilot local; do v31_has "$v31_out" "^RUN $v31_e " "all present: no RUN line for $v31_e"; done
  v31_hasnt "$v31_out" '^SKIP ' "all present: a SKIP line"
  v31_hasnt "$v31_out" '^FAIL ' "all present: a FAIL line"
  v31_has "$v31_out" '^PARTIAL' "partial run: no PARTIAL line"

  # 9.5/9.6 discovery from the environment, a relative path and a path with a
  #     space, in one full run: the relative codex root is absolutised, the
  #     spaced copilot root works, the roots arrive without any argument.
  mkdir -p "$v31_tmp/work dir" && mv "$v31_tmp/copilot" "$v31_tmp/work dir/copilot with space" \
    || v31_bad="$v31_bad [moving the copilot root to a spaced path failed]"
  v31_arm "environment roots, relative and spaced paths" 0 bash -c 'cd "$1" && MOZART_EDITION_ROOTS="../codex:copilot with space:../local" bash "$2" --table "$3"' _ "$v31_tmp/work dir" "$v31_script" "$v31_ctl"
  v31_has "$v31_out" "^RUN codex $v31_tmp/codex" "relative path not absolutised in the RUN line"
  v31_has "$v31_out" "^RUN copilot $v31_tmp/work dir/copilot with space" "spaced path not carried through"
  [ "$(grep -c '^RUN ' <<<"$v31_out" || true)" = "4" ] || v31_bad="$v31_bad [environment roots: not exactly four RUN lines]"
  mv "$v31_tmp/work dir/copilot with space" "$v31_tmp/copilot"

  # 9.2 each edition omitted in turn: exit 3 and one SKIP line naming it.
  for v31_omit in codex copilot local; do
    case $v31_omit in
      codex) v31_set="$v31_p $v31_l" ;;
      copilot) v31_set="$v31_c $v31_l" ;;
      local) v31_set="$v31_c $v31_p" ;;
    esac
    # shellcheck disable=SC2086
    v31_arm "$v31_omit omitted" 3 bash "$v31_script" "${v31_t[@]}" --skip-behaviour $v31_set
    v31_has "$v31_out" "^SKIP $v31_omit: checkout not found" "$v31_omit omitted: no SKIP line naming it"
    [ "$(grep -c '^SKIP ' <<<"$v31_out" || true)" = "1" ] || v31_bad="$v31_bad [$v31_omit omitted: not exactly one SKIP line]"
    [ "$(grep -c '^RUN ' <<<"$v31_out" || true)" = "3" ] || v31_bad="$v31_bad [$v31_omit omitted: not exactly three RUN lines]"
  done

  # 9.3 S3 changed by one word in the codex root, and S3 present twice in the
  #     copilot root: exit 1 and the output names the failing edition.
  cp -R "$v31_tmp/codex" "$v31_tmp/codex-s3" && cp -R "$v31_tmp/copilot" "$v31_tmp/copilot-s3x2" || v31_bad="$v31_bad [copying roots for the S3 mutations failed]"
  sed 's/Reversals append/Reversals appended/' "$v31_tmp/codex-s3/$v31_s3codex" > "$v31_tmp/m" && mv "$v31_tmp/m" "$v31_tmp/codex-s3/$v31_s3codex"
  cmp -s "$v31_tmp/codex-s3/$v31_s3codex" "$v31_tmp/codex/$v31_s3codex" && v31_bad="$v31_bad [CONTROL: the S3 mutation changed nothing]"
  v31_arm "S3 mutated" 1 bash "$v31_script" "${v31_t[@]}" --skip-behaviour "$v31_tmp/codex-s3" "$v31_tmp/copilot" "$v31_tmp/local"
  v31_has "$v31_out" '^FAIL codex' "S3 mutated: the output does not name codex"
  v31_hasnt "$v31_out" '^FAIL (copilot|local|orchestration)' "S3 mutated: a different edition is named as failing"
  { echo; cat "$gate_root/tests/parity/snippets/S3.txt"; } >> "$v31_tmp/copilot-s3x2/$v31_s3copilot"
  v31_arm "S3 twice" 1 bash "$v31_script" "${v31_t[@]}" --skip-behaviour "$v31_tmp/codex" "$v31_tmp/copilot-s3x2" "$v31_tmp/local"
  v31_has "$v31_out" '^FAIL copilot' "S3 twice: the output does not name copilot"

  # 9.4 failure outranks skip, and the skip is still reported.
  v31_arm "mutated and omitted" 1 bash "$v31_script" "${v31_t[@]}" --skip-behaviour "codex=$v31_tmp/codex-s3" "$v31_p"
  v31_has "$v31_out" '^SKIP local: checkout not found' "mutated and omitted: the SKIP line is missing"
  v31_has "$v31_out" '^FAIL codex' "mutated and omitted: the output does not name codex"

  # 9.10 one byte of the shared library changed in a fake codex root; and the
  #     library absent from a fake copilot root.
  cp -R "$v31_tmp/codex" "$v31_tmp/codex-lib" && printf '#' >> "$v31_tmp/codex-lib/scripts/lib-campaign.sh"
  v31_arm "library one byte off" 1 bash "$v31_script" "${v31_t[@]}" --skip-behaviour "$v31_tmp/codex-lib" "$v31_tmp/copilot" "$v31_tmp/local"
  v31_has "$v31_out" '^FAIL codex.*lib-campaign\.sh' "library one byte off: the output does not name codex and the library"
  cp -R "$v31_tmp/copilot" "$v31_tmp/copilot-nolib" && rm "$v31_tmp/copilot-nolib/scripts/lib-campaign.sh"
  v31_arm "library absent" 1 bash "$v31_script" "${v31_t[@]}" --skip-behaviour "$v31_tmp/codex" "$v31_tmp/copilot-nolib" "$v31_tmp/local"
  v31_has "$v31_out" '^FAIL copilot.*lib-campaign\.sh' "library absent: the output does not name copilot and the library"

  # 9.5 usage errors exit 2: an unknown flag, one positional root, four, an
  #     unknown edition name. A nonexistent path is a skip; an existing empty
  #     directory is a failure, never a skip and never a pass.
  v31_arm "unknown flag" 2 bash "$v31_script" "${v31_t[@]}" --no-such-flag
  v31_arm "one positional root" 2 bash "$v31_script" "${v31_t[@]}" "$v31_tmp/codex"
  v31_arm "four positional roots" 2 bash "$v31_script" "${v31_t[@]}" "$v31_tmp/codex" "$v31_tmp/copilot" "$v31_tmp/local" "$v31_tmp/local"
  v31_arm "unknown edition name" 2 bash "$v31_script" "${v31_t[@]}" "rust=$v31_tmp/codex"
  v31_arm "nonexistent path" 3 bash "$v31_script" "${v31_t[@]}" --skip-behaviour "$v31_c" "$v31_p" "local=$v31_tmp/no such dir"
  v31_has "$v31_out" '^SKIP local: checkout not found' "nonexistent path: no SKIP line"
  mkdir "$v31_tmp/empty"
  v31_arm "empty directory" 1 bash "$v31_script" "${v31_t[@]}" --skip-behaviour "$v31_c" "$v31_p" "local=$v31_tmp/empty"
  v31_has "$v31_out" '^FAIL local' "empty directory: the output does not name local"
  v31_hasnt "$v31_out" '^SKIP ' "empty directory: read as a skip"

  # A port script that exits other than 0 or 1 is a failure with its output
  # shown, not a mysterious exit code: the codex lint exits 7 and says why. The
  # copilot root beside it is healthy, and the harness's own exit status (1, for
  # the codex failure) must not be read as copilot's.
  cp -R "$v31_tmp/codex" "$v31_tmp/codex-bad" && printf '#!/bin/sh\necho "lint-stub: boom"\nexit 7\n' > "$v31_tmp/codex-bad/scripts/mozart-lint.sh"
  v31_arm "port script exits 7" 1 bash "$v31_script" "${v31_t[@]}" "codex=$v31_tmp/codex-bad" "$v31_p" "$v31_l"
  v31_has "$v31_out" '^ok   copilot: behaviour' "port script exits 7: the healthy copilot edition is not reported ok"
  v31_has "$v31_out" 'exit=7' "port script exits 7: the harness line naming the exit code is not shown"
  v31_has "$v31_out" '^FAIL codex' "port script exits 7: the output does not name codex"
  v31_hasnt "$v31_out" '^FAIL (copilot|local)' "port script exits 7: a healthy edition is named as failing"

  # ---- the table reader (phase 1a): inline tables over scratch roots --------------------------------
  # check-editions.sh above ran with a one-row control table per edition; the arms below drive
  # scripts/check-edition-text.py itself. Every arm names its inline table; none uses the shipped one
  # except the bare-root arm, which exists to show the inline table is not the default.
  v31_reader="$gate_root/scripts/check-edition-text.py"
  v31_T=$'\t'
  v31_hdr="id${v31_T}edition${v31_T}phase${v31_T}kind${v31_T}scope${v31_T}anchor${v31_T}row${v31_T}expect${v31_T}needle"
  v31_row() { local IFS=$v31_T; printf '%s\n' "$*"; }  # nine fields, empty ones kept
  v31_rt="$v31_tmp/rt"; v31_rsrc="$v31_tmp/rsrc"
  mkdir -p "$v31_rt/fx/fixtures" "$v31_rsrc/tests/fixtures/lens" "$v31_rsrc/scripts" "$v31_tmp/tbl/policy"
  printf '## Sec\nhello\n```\n## Sec\n```\n' > "$v31_rt/a.md"
  printf 'same\n' > "$v31_rt/cp.txt"; printf 'same\n' > "$v31_rsrc/cp.txt"
  printf 'hello\n' > "$v31_rt/fx/fixtures/x.md"
  printf 'lens fixture\n' > "$v31_rsrc/tests/fixtures/lens/a.md"
  # rd <label> <want rc> <table lines file> <reader args...>
  v31_rd() {
    local lbl=$1 want=$2 tf=$3; shift 3
    v31_arm "$lbl" "$want" python3 "$v31_reader" --edition codex --root "$v31_rt" --table "$tf" "$@"
  }
  v31_tbl() { # v31_tbl <name> <row>...: writes $v31_tmp/tbl/parity/<name>.tsv with the header
    local f="$v31_tmp/tbl/parity/$1.tsv"; shift
    mkdir -p "$v31_tmp/tbl/parity"
    { printf '%s\n' "$v31_hdr"; for r in "$@"; do printf '%s\n' "$r"; done; } > "$f"
    v31_tf=$f
  }
  v31_ok="$(v31_row t-ok codex 0 once a.md "" "" 1 hello)"
  v31_pend="$(v31_row t-pend codex 2 once a.md "" "" 1 nowhere)"
  v31_passes="$(v31_row t-early codex 2 once a.md "" "" 1 hello)"

  # selftest: every kind has planted inputs it must flag and clean ones it must not
  v31_arm "reader selftest" 0 python3 "$v31_reader" selftest
  v31_has "$v31_out" '^selftest ok: 63 planted inputs flagged, 33 clean inputs accepted$' "selftest: the planted/clean counts changed"
  # the shipped table is not the default of the inline one: over a bare fake root it fails
  v31_arm "shipped table, bare fake roots" 1 bash "$v31_script" --skip-behaviour --done "" "$v31_tmp/codex" "$v31_tmp/copilot" "$v31_tmp/local"
  v31_has "$v31_out" '^FAIL ctl-noprogress-none-codex' "shipped table over a bare root: no FAIL for a phase-0 codex row"
  v31_has "$v31_out" '^FAIL ctl-mirror-copilot' "shipped table over a bare root: ctl-mirror-copilot did not fail"
  # --done: "" is legal, 1 is not (no phase-1 row), a malformed list is a usage error
  v31_tbl done "$v31_ok" "$v31_pend"
  v31_rd "--done empty" 5 "$v31_tf" --done ""
  v31_rd "--done 1 is unknown" 2 "$v31_tf" --done "1"
  v31_rd "--done malformed" 2 "$v31_tf" --done "2,3"
  v31_arm "check-editions --done 1" 2 bash "$v31_script" --skip-behaviour --done "1" "$v31_c" "$v31_p" "$v31_l"
  v31_arm "check-editions --done needs a value" 2 bash "$v31_script" --skip-behaviour --done
  v31_rd "unknown flag" 2 "$v31_tf" --no-such-flag
  python3 "$v31_reader" --edition rust --root "$v31_rt" --table "$v31_tf" >/dev/null 2>&1; [ "$?" -eq 2 ] || v31_bad="$v31_bad [unknown edition: not a usage error]"
  v31_arms=$((v31_arms + 1))
  # pending-only exits 5 with no FAIL and names the phase; a done phase makes the same row due
  v31_rd "pending only" 5 "$v31_tf" --done ""
  v31_has "$v31_out" '^PENDING t-pend: needle-absent' "pending-only: the pending row is not named with its reason"
  v31_hasnt "$v31_out" '^FAIL ' "pending-only: a FAIL line"
  v31_has "$v31_out" '^pending: codex phases 2 \(1 rows\)$' "pending-only: the last line does not name the phase"
  v31_rd "pending row, phase done" 1 "$v31_tf" --done "2"
  v31_has "$v31_out" '^FAIL t-pend: needle-absent' "a done phase did not make its failing row a FAIL"
  v31_rd "no --done: every phase due" 1 "$v31_tf"
  v31_tbl early "$v31_ok" "$v31_passes"
  v31_rd "a pending row that passes" 1 "$v31_tf" --done ""
  v31_has "$v31_out" '^FAIL t-early: passes before its phase' "a pending row that passes was not a FAIL"
  v31_tbl defect "$v31_ok" "$(v31_row t-nofile codex 2 once nosuch.md "" "" 1 hello)"
  v31_rd "pending row failing for a table defect" 1 "$v31_tf" --done ""
  v31_has "$v31_out" '^FAIL t-nofile: table defect' "a scope with no file was read as pending"
  v31_hasnt "$v31_out" '^PENDING t-nofile' "a scope with no file was pending"
  # the six pending classes, and the twins that are table defects
  printf '## Sec\nhello hello\n## Sec2\nstale\n| a | b |\n|--|--|\n| x |\n' > "$v31_rt/classes.md"
  v31_tbl classes \
    "$(v31_row c-needle codex 2 once classes.md "" "" 1 nowhere)" \
    "$(v31_row c-stale codex 2 absent classes.md "" "" 0 stale)" \
    "$(v31_row c-count codex 2 once classes.md "" "" 1 hello)" \
    "$(v31_row c-shape codex 2 shape classes.md "## Sec2" "" 1 header=a)" \
    "$(v31_row c-file codex 2 once newfile.md+ "" "" 1 hello)" \
    "$(v31_row c-anchor codex 2 once classes.md "## Later @+" "" 1 hello)"
  v31_rd "six pending classes" 5 "$v31_tf" --done ""
  for v31_cls in 'c-needle: needle-absent' 'c-stale: stale-present' 'c-count: count-mismatch' 'c-shape: shape-mismatch' 'c-file: file-created' 'c-anchor: anchor-created'; do
    v31_has "$v31_out" "^PENDING $v31_cls\$" "pending class not reported: $v31_cls"
  done
  v31_hasnt "$v31_out" '^FAIL ' "pending classes: a FAIL line"
  v31_tbl twins \
    "$(v31_row d-anchor codex 2 once classes.md "## Missing" "" 1 hello)" \
    "$(v31_row d-file codex 2 once nosuch.md "" "" 1 hello)" \
    "$(v31_row d-glob codex 2 once "zz/*.md" "" "" 1 hello)"
  v31_rd "unmarked missing anchor, file and glob" 1 "$v31_tf" --done ""
  for v31_id in d-anchor d-file d-glob; do v31_has "$v31_out" "^FAIL $v31_id: table defect" "$v31_id was not a table defect"; done
  # an anchor that occurs once outside a fence and again inside one counts once
  v31_tbl fenced "$(v31_row f-fence codex 0 once a.md "## Sec" "" 1 hello)"
  v31_rd "anchor repeated inside a fence" 0 "$v31_tf"
  # a glob that reaches only /fixtures/ matches nothing; an explicit fixture path works
  v31_tbl fixtures "$(v31_row g-glob codex 0 once "fx/**/*.md" "" "" 1 hello)"
  v31_rd "glob reaching only /fixtures/" 1 "$v31_tf"
  v31_tbl fixtures2 "$(v31_row g-explicit codex 0 once fx/fixtures/x.md "" "" 1 hello)"
  v31_rd "explicit /fixtures/ file" 0 "$v31_tf"
  # table defects: each prints FAIL <table> and exits 1
  v31_tbl dup "$v31_ok" "$(v31_row T-OK codex 0 once a.md "" "" 1 hello)"
  v31_rd "duplicate id differing in case" 1 "$v31_tf"; v31_has "$v31_out" '^FAIL <table>: .*duplicate' "duplicate id: no FAIL <table>"
  v31_tbl badkind "$(v31_row t-k codex 0 nokind a.md "" "" 1 hello)"
  v31_rd "unknown kind" 1 "$v31_tf"; v31_has "$v31_out" '^FAIL <table>: .*unknown kind' "unknown kind: no FAIL <table>"
  v31_tbl badedition "$(v31_row t-e rust 0 once a.md "" "" 1 hello)"
  v31_rd "unknown edition in a row" 1 "$v31_tf"; v31_has "$v31_out" '^FAIL <table>: .*unknown edition' "unknown edition: no FAIL <table>"
  v31_tbl badcount "$(v31_row t-c codex 0 count a.md "" "" two hello)"
  v31_rd "non-integer count" 1 "$v31_tf"; v31_has "$v31_out" '^FAIL <table>: .*not an integer' "non-integer count: no FAIL <table>"
  v31_tbl ragged "a${v31_T}b"
  v31_rd "ragged table line" 1 "$v31_tf"; v31_has "$v31_out" '^FAIL <table>: ' "ragged line: no FAIL <table>"
  : > "$v31_tmp/tbl/parity/empty.tsv"
  v31_rd "empty table" 1 "$v31_tmp/tbl/parity/empty.tsv"; v31_has "$v31_out" '^FAIL <table>: the table is empty' "empty table: no FAIL <table>"
  v31_rd "missing table" 1 "$v31_tmp/tbl/parity/nosuch.tsv"; v31_has "$v31_out" '^FAIL <table>: ' "missing table: no FAIL <table>"
  { printf '%s\r\n' "$v31_hdr"; printf '%s\r\n' "$v31_ok"; } > "$v31_tmp/tbl/parity/crlf.tsv"
  v31_rd "CRLF table" 0 "$v31_tmp/tbl/parity/crlf.tsv"
  # a root that is a file; a scope that climbs out of the root
  v31_arm "root is a file" 1 python3 "$v31_reader" --edition codex --root "$v31_rt/a.md" --table "$v31_tmp/tbl/parity/crlf.tsv"
  v31_tbl climb "$(v31_row t-up codex 0 once ../a.md "" "" 1 hello)"
  v31_rd "scope climbing out of the root" 1 "$v31_tf"
  # NEEDS-SOURCE: the count is never ignored
  v31_tbl src "$(v31_row s-cmp codex 0 cmp-src cp.txt "" "" 1 cp.txt)"
  v31_rd "-src row without --source, no count" 1 "$v31_tf"; v31_has "$v31_out" '^NEEDS-SOURCE s-cmp$' "no NEEDS-SOURCE line"
  v31_rd "-src row without --source, count equal" 0 "$v31_tf" --expect-source-rows 1
  v31_rd "-src row without --source, count unequal" 1 "$v31_tf" --expect-source-rows 2
  v31_rd "-src row with --source" 0 "$v31_tf" --source "$v31_rsrc"; v31_has "$v31_out" '^ok s-cmp$' "cmp-src with --source did not pass"
  printf 'diff\n' > "$v31_rsrc/cp.txt"
  v31_rd "cmp-src one byte off" 1 "$v31_tf" --source "$v31_rsrc"
  printf 'same\n' > "$v31_rsrc/cp.txt"
  # lens-src: the helper's exits 0, 1 and 2, and not yet written
  v31_tbl lens "$(v31_row l-lens codex 3 lens-src cp.txt "" "" 6 'scripts/check-edition-lens.sh+;tests/fixtures/lens+')"
  v31_rd "lens helper not yet written" 5 "$v31_tf" --source "$v31_tmp/tbl" --done ""
  for v31_code in 0 1 2; do
    printf '#!/bin/bash\nexit %s\n' "$v31_code" > "$v31_rsrc/scripts/check-edition-lens.sh"
    case $v31_code in 0) v31_want=0 ;; 1) v31_want=1 ;; 2) v31_want=1 ;; esac
    v31_rd "lens helper exit $v31_code at its phase" "$v31_want" "$v31_tf" --source "$v31_rsrc" --done "3"
  done
  printf "#!/bin/bash\nexit 1\n" > "$v31_rsrc/scripts/check-edition-lens.sh"
  v31_rd "lens helper exit 1 before its phase" 5 "$v31_tf" --source "$v31_rsrc" --done ""
  printf '#!/bin/bash\nexit 0\n' > "$v31_rsrc/scripts/check-edition-lens.sh"
  v31_rd "lens helper passes before its phase" 1 "$v31_tf" --source "$v31_rsrc" --done ""
  v31_has "$v31_out" '^FAIL l-lens: passes before its phase' "a lens row that passes early was not a FAIL"
  # call-site pins: each mismatch is a FAIL; the five printed literals hold
  printf 'hello\n' > "$v31_tmp/tbl/policy/n.txt"
  v31_tbl pins "$(v31_row p-ok codex 0 once a.md "" "" 1 @n.txt)"
  v31_pins_tsha=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$v31_tf")
  v31_pins_ids=$(python3 -c 'import hashlib;print(hashlib.sha256(b"p-ok\n").hexdigest())')
  v31_pins_pol=$(python3 -c 'import hashlib;print(hashlib.sha256(b"n.txt\0hello\n\0").hexdigest())')
  v31_rd "all five pins right" 0 "$v31_tf" --expect-rows 1 --expect-source-rows 0 --expect-ids "$v31_pins_ids" --expect-table-sha256 "$v31_pins_tsha" --expect-policy-sha256 "$v31_pins_pol"
  v31_rd "--expect-rows wrong" 1 "$v31_tf" --expect-rows 2 --expect-source-rows 0
  v31_rd "--expect-ids wrong" 1 "$v31_tf" --expect-ids 0000
  v31_rd "--expect-table-sha256 wrong" 1 "$v31_tf" --expect-table-sha256 0000
  v31_rd "--expect-policy-sha256 wrong" 1 "$v31_tf" --expect-policy-sha256 0000
  sed 's/@n.txt/hellp/' "$v31_tf" > "$v31_tmp/tbl/parity/pins2.tsv"
  v31_rd "a changed needle is caught by the table pin" 1 "$v31_tmp/tbl/parity/pins2.tsv" --expect-table-sha256 "$v31_pins_tsha"
  printf 'hellp\n' > "$v31_tmp/tbl/policy/n.txt"
  v31_rd "a changed policy file is caught by the policy pin" 1 "$v31_tf" --expect-policy-sha256 "$v31_pins_pol"
  printf 'hello\n' > "$v31_tmp/tbl/policy/n.txt"
  v31_arm "hashes prints five literals" 0 python3 "$v31_reader" hashes --edition codex
  for v31_k in rows source-rows ids table-sha256 policy-sha256; do v31_has "$v31_out" "^--expect-$v31_k [0-9a-f]+\$|^--expect-$v31_k [0-9]+\$" "hashes: no --expect-$v31_k line"; done
  [ "$(grep -c '^--expect-' <<<"$v31_out" || true)" = "5" ] || v31_bad="$v31_bad [hashes: not exactly five literals]"

  # ---- a planted violation per ctl-* family, run through the SHIPPED row definition ----------------
  # Each family: the row's own line is lifted from the shipped table, a scratch root is built that
  # satisfies it (rc 0, "ok <id>"), then one violation is planted (rc 1, "FAIL <id>"). A control that
  # cannot fail is not a control; this shows each can.
  v31_ctl_out=$(python3 - "$gate_root" "$v31_reader" "$v31_tmp" <<'V31_CTL_PY' 2>&1
import os, shutil, subprocess, sys, tempfile
root, reader, tmp = sys.argv[1:4]
table = [l.rstrip("\n").split("\t") for l in open(os.path.join(root, "tests/parity/editions.tsv"), encoding="utf-8")]
hdr, rows = table[0], {r[0]: r for r in table[1:]}
pol = os.path.join(root, "tests/policy")
def policy(name):
    return open(os.path.join(pol, name), encoding="utf-8").read()
def run(rid, files, source_files=None):
    d = tempfile.mkdtemp(dir=tmp)
    for sub in ("parity", "policy"):
        os.makedirs(os.path.join(d, sub))
    for f in os.listdir(pol):
        shutil.copy(os.path.join(pol, f), os.path.join(d, "policy", f))
    open(os.path.join(d, "parity/t.tsv"), "w", encoding="utf-8").write("\t".join(hdr) + "\n" + "\t".join(rows[rid]) + "\n")
    port, src = os.path.join(d, "port"), os.path.join(d, "src")
    for base, fs in ((port, files), (src, source_files or {})):
        os.makedirs(base, exist_ok=True)
        for rel, content in fs.items():
            p = os.path.join(base, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w", encoding="utf-8").write(content)
    ed = rows[rid][1]
    r = subprocess.run([sys.executable, reader, "--edition", ed, "--root", port, "--source", src,
                        "--table", os.path.join(d, "parity/t.tsv")], capture_output=True, text=True)
    return r.returncode, r.stdout
bullet = policy("no-progress.txt")
s3 = policy("s3-snippet.txt")
tree = {f"t/{i}.txt": f"{i}\n" for i in range(342)}
families = [
 ("ctl-noprogress-none-codex", {p: ('developer_instructions = """\nx\n"""\n' if p.endswith(".toml") else "x\n") for p in rows["ctl-noprogress-none-codex"][4].split(";")},
  lambda f: {k: (v.replace("x\n", "x\n" + bullet, 1) if k.endswith(".toml") else v + bullet) for k, v in f.items()}, None),
 ("ctl-choose-operate-copilot", {rows["ctl-choose-operate-copilot"][4]: rows["ctl-choose-operate-copilot"][8] + "\n"}, lambda f: {k: v + v for k, v in f.items()}, None),
 ("ctl-sev-local", {rows["ctl-sev-local"][4]: rows["ctl-sev-local"][8] + "\n"}, lambda f: {k: "" for k in f}, None),
 ("ctl-x2b-nocsp-p-copilot", {rows["ctl-x2b-nocsp-p-copilot"][4]: rows["ctl-x2b-nocsp-p-copilot"][5] + "\n| xander | auth |\n"}, lambda f: {k: v.replace("auth", "auth, CSP") for k, v in f.items()}, None),
 ("ctl-s3-copilot", {rows["ctl-s3-copilot"][4]: s3}, lambda f: {k: v + "\n" + s3 for k, v in f.items()}, None),
 ("ctl-moved-codex-1", {rows["ctl-moved-codex-1"][4]: rows["ctl-moved-codex-1"][8] + "\n"}, lambda f: {k: v + v for k, v in f.items()}, None),
 ("ctl-nolabel-codex", {rows["ctl-nolabel-codex"][4]: "Claude r1 (plan)\n"}, lambda f: {k: v + "**Codex**: r1\n" for k, v in f.items()}, None),
 ("ctl-index-members-copilot", {rows["ctl-index-members-copilot"][4]: "| `TICKETS.md` | x |\n"}, lambda f: {k: "" for k in f}, None),
 ("ctl-leak-claudemd-copilot", {".github/mozart/manual/x.md": "ok\n", ".github/agents/a.agent.md": "x\n"}, lambda f: {k: v + "CLAUDE.md\n" for k, v in f.items()}, None),
 ("ctl-mirror-copilot", {"tests/fixtures/campaign/conductor/" + k: v for k, v in tree.items()}, lambda f: {**f, "tests/fixtures/campaign/conductor/t/5.txt": "changed\n"},
  {"tests/fixtures/conductor/" + k: v for k, v in tree.items()}),
]
bad = []
for rid, files, plant, srcf in families:
    good_rc, good_out = run(rid, files, srcf)
    bad_rc, bad_out = run(rid, plant(files), srcf)
    if good_rc != 0 or not good_out.startswith("ok " + rid):
        bad.append(f"{rid}: the satisfying root did not pass ({good_rc}: {good_out[:80]!r})")
    if bad_rc != 1 or ("FAIL " + rid) not in bad_out:
        bad.append(f"{rid}: the planted violation was not a FAIL ({bad_rc}: {bad_out[:80]!r})")
print(f"CTL {len(families)} families", "BAD " + "; ".join(bad) if bad else "all planted violations fail")
V31_CTL_PY
)
  v31_arms=$((v31_arms + 1))
  v31_has "$v31_ctl_out" '^CTL 10 families all planted violations fail$' "ctl families: ${v31_ctl_out:0:200}"
fi
# D7: the script is named where contributors look for the cross-edition checks.
v31_named=$(grep -c 'scripts/check-editions\.sh' "$gate_root/CONTRIBUTING.md" || true)
[ "$v31_named" -ge 1 ] || v31_bad="$v31_bad [CONTRIBUTING.md does not name scripts/check-editions.sh]"
[ "$v31_arms" -eq 66 ] || v31_bad="$v31_bad [$v31_arms arms ran, want exactly 66 -- an arm was added or lost without the floor moving]"
rm -rf "$v31_tmp"

report "V31_editions_selftest" "$([ -z "$v31_bad" ] && echo 0 || echo 1)" \
  "${v31_bad:-check-editions.sh over $v31_arms arms: all present with four RUN lines and arguments beating the environment, a partial run 4 and never 0, environment roots with a relative and a spaced path and the whole check including behaviour 0, each edition omitted 3 with its own SKIP line, S3 changed or doubled 1 naming the edition, failure outranks skip, a one-byte or absent library 1, usage errors 2, a nonexistent path 3, an empty directory 1, a port script exiting 7 1 with its output; the table reader: its selftest (planted inputs flagged, clean ones accepted, counts pinned), the shipped table over bare fake roots 1, an empty --done 5, and --done 1 or a malformed list 2, pending-only 5, a pending row that passes or fails for a table defect 1, the six pending classes and their table-defect twins, a fenced anchor repeat, /fixtures/ globs, ten table-defect and usage cases, the NEEDS-SOURCE exit rules, the three exits of the lens helper, every call-site pin mismatch and the five printed literals, and a planted violation for ten ctl families through their shipped row}"

# ---------------------------------------------------------------------------
# V36_editions_table - the parity table, its reader and the policy files it names (phase 1a)
#
# tests/parity/editions.tsv is read by scripts/check-edition-text.py in every edition. This gate
# pins what a port copies (the table, the reader, every policy file the table names) by content,
# and ties V28's detectors to the policy files in the SAME shell: xander-terms.txt equals the
# term table V28 applies, heavy-variant.re equals its variant regex, the mask is the sentence its
# sed cuts out. V36 also keeps its own copies of those literals, so V28 and the files cannot be
# weakened together without a second, visible edit here. (v32_ is taken by V30_layout_agreement.)
# ---------------------------------------------------------------------------
v36_bad=""
v36_tsv="$gate_root/tests/parity/editions.tsv"
v36_pol="$gate_root/tests/policy"
v36_reader="$gate_root/scripts/check-edition-text.py"
v36_tmp=$(mktemp -d) || { v36_bad="$v36_bad [mktemp failed]"; v36_tmp=/nonexistent-v36; }
if [ ! -f "$v36_tsv" ]; then
  v36_bad="$v36_bad [table absent: tests/parity/editions.tsv]"
elif [ ! -f "$v36_reader" ]; then
  v36_bad="$v36_bad [reader absent: scripts/check-edition-text.py]"
elif ! command -v python3 >/dev/null 2>&1; then
  v36_bad="$v36_bad [python3 missing (FAIL, not skip)]"
else
  # ---- V28's literals, compared as shell variables in this run ----------------------------------
  v36_f_terms=$(cat "$v36_pol/xander-terms.txt")
  [ "$v36_f_terms" = "$v28_terms" ] || v36_bad="$v36_bad [xander-terms.txt differs from V28's term table (\$v28_terms)]"
  v36_f_variant=$(cat "$v36_pol/heavy-variant.re")
  [ "$v36_f_variant" = "$v28_variant_re" ] || v36_bad="$v36_bad [heavy-variant.re differs from V28's \$v28_variant_re]"
  v36_f_mask=$(cat "$v36_pol/heavy-variant.mask")
  # the phrase V28's sed cuts out, built in two parts so that this line is not a third occurrence of it
  v36_phrase="xander runs on every phase when ""that surface is"
  [ "$v36_f_mask" = "$v36_phrase" ] || v36_bad="$v36_bad [heavy-variant.mask is not the sentence V28's sed cuts out]"
  v36_mask_n=$(grep -cF -- "$v36_phrase" "$gatefile" || true)
  [ "$v36_mask_n" = "4" ] || v36_bad="$v36_bad [the masked sentence occurs on $v36_mask_n line(s) of this file, want 4 (V28's three sed calls and its self-test)]"
  # V36's own pins (so V28 and the files cannot be weakened together): twelve terms, by name
  v36_names=$(cut -f1 <<<"$v36_f_terms" | tr '\n' ',')
  [ "$v36_names" = "auth,secrets,untrusted input,encryption,sessions,RBAC,security headers,CSP,dependency changes,CI/CD workflow changes,authorization (ownership and tenant filters),outbound requests," ] \
    || v36_bad="$v36_bad [xander-terms.txt names are not the twelve in V28's table: $v36_names]"
  # one planted string per alternative of the variant regex: each must hit; the masked sentence alone must not
  for v36_p in 'HEAVY: always' 'mandatory ian on every phase' 'ian and xander run on every phase' 'xander runs on every phase' \
               'ian and xander on every phase regardless' 'mandatory; others conditional' 'ian (HEAVY-tier always)'; do
    grep -qE -- "$v36_f_variant" <<<"$v36_p" || v36_bad="$v36_bad [self-test: the variant regex missed a planted variant: $v36_p]"
  done
  v36_cut=$(sed "s/$v36_phrase/XANDER-SURFACE-RULE/" <<<"and $v36_phrase auth")
  ! grep -qE -- "$v36_f_variant" <<<"$v36_cut" || v36_bad="$v36_bad [self-test: the masked xander surface sentence alone was read as a variant]"
  v36_cut=$(sed "s/$v36_phrase/XANDER-SURFACE-RULE/" <<<"HEAVY: always; $v36_phrase auth")
  grep -qE -- "$v36_f_variant" <<<"$v36_cut" || v36_bad="$v36_bad [self-test: a variant beside the masked sentence was hidden by the mask]"
  # ---- the table: counts, ids, kinds, phases, cardinalities, marks, files -------------------------
  v28_rows "$v28_del_s4" xander > "$v36_tmp/d4"
  v28_rows "$v28_del_s8" xander > "$v36_tmp/d8"
  v28_rows "$v28_pipe_s4" xander > "$v36_tmp/p4"
  v28_rows "$v28_pipe_s8" xander > "$v36_tmp/p8"
  v36_py=$(python3 - "$gate_root" "$v36_tmp" <<'V36_PY' 2>&1
import hashlib, os, re, sys, collections, importlib.util
root = sys.argv[1]
def sha(path):
    return hashlib.sha256(open(os.path.join(root, path), "rb").read()).hexdigest()
bad = []
def need(cond, msg):
    if not cond:
        bad.append(msg)
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(root, "tests/parity/editions.tsv"), encoding="utf-8")]
hdr, rows = rows[0], rows[1:]
need(hdr == ["id", "edition", "phase", "kind", "scope", "anchor", "row", "expect", "needle"], "table header changed")
need(all(len(r) == 9 for r in rows), "a ragged table line")
N = 385
need(len(rows) == N, f"the table holds {len(rows)} rows, want {N}")
per_ed = collections.Counter(r[1] for r in rows)
need(dict(per_ed) == {'codex': 101, 'copilot': 105, 'local': 106, 'orchestration': 73}, f"rows per edition: {dict(per_ed)}")
ids = sorted(r[0] for r in rows)
need(len(set(i.lower() for i in ids)) == len(ids), "duplicate ids")
need(hashlib.sha256(("\n".join(ids) + "\n").encode()).hexdigest() == "02dc8c243207e5edb9b2d2b850b59acbe1ffa92ca655a68c9f8e66f9e7213db1", "the id list changed")
kpe = sorted(f"{r[0]} {r[3]} {r[2]} {r[7]}" for r in rows)
need(hashlib.sha256(("\n".join(kpe) + "\n").encode()).hexdigest() == "6cab856e610e742f4c57a6118c26758bb3fe28210f04a79a94949be60dd3a9af", "a row's kind, phase or expect changed")
def family(i):
    i = re.sub(r"-(orchestration|copilot|codex|local)$", "", i)
    i = re.sub(r"-\d+$", "", i)
    return "rule-copies" if i.startswith("rule-copies-") else "witness" if i.startswith("witness-") else i
matrix = sorted(f"{family(r[0])}:{r[1]}={n}" for (r), n in [(r, 1) for r in rows])
cnt = collections.Counter((family(r[0]), r[1]) for r in rows)
matrix = sorted(f"{f}:{e}={n}" for (f, e), n in cnt.items())
need(len(set(f for f, _ in cnt)) == 83, f"{len(set(f for f, _ in cnt))} families, want 83")
need(hashlib.sha256(("\n".join(matrix) + "\n").encode()).hexdigest() == "07326263e21ad90547b7356eb362dd72bcf450958f0eab1f2470a10789fd60fc", "the family-by-edition matrix changed")
marks = []
for r in rows:
    for col, name in ((4, "scope"), (5, "anchor"), (6, "row"), (8, "needle")):
        v = r[col]
        if name in ("scope", "needle"):
            n = sum(1 for e in v.split(";") if e.endswith("+") and e != "+")
            if r[3] != "lens-src" and name == "needle":
                n = 0
        else:
            n = v.count(" @+")
        if n:
            marks.append(f"{r[0]} {name} {n}")
marks.sort()
need(len(marks) == 123, f"{len(marks)} cells carry a + mark, want 123")
need(hashlib.sha256(("\n".join(marks) + "\n").encode()).hexdigest() == "65570a53668c6d48f476cf3e89829c71ddcb2c614c3b88b448ef486f330da13d", "the + marks changed")
byid = {r[0]: r for r in rows}
for rid, kind, phase, expect in [('rule-noprogress-codex', 'bullet-last', '6', '17'), ('rule-xterms-s8-copilot', 'terms', '2', '12'), ('rule-tier-clauses-local', 'each-once', '4', '23'), ('rule-variant-codex', 'absent-re', '6', '0'), ('lay-moved-copilot', 'moved', '3', '5'), ('rule-bobduty-local', 'each-once', '4', '6'), ('lens-codex', 'lens-src', '7', '6')]:
    r = byid.get(rid)
    need(r is not None and (r[3], r[2], r[7]) == (kind, phase, expect), f"named member {rid}: {r and (r[3], r[2], r[7])}")
kinds = {r[3] for r in rows}
need(len(kinds) == 17, f"{len(kinds)} kinds in the table, want 17")
orch_kinds = {r[3] for r in rows if r[1] == "orchestration" and r[2] == "0"}
need(orch_kinds == kinds - {"lens-src"}, f"kinds without a phase-0 orchestration witness: {sorted(kinds - {'lens-src'} - orch_kinds)}")
need(all(r[2] == "0" for r in rows if r[1] == "orchestration" and r[3] != "lens-src"), "an orchestration row that is not phase 0")
need(byid["lens-orchestration"][2] == "1b", "lens-orchestration is not phase 1b")
for e in ("copilot", "codex", "local"):
    need(sum(1 for r in rows if r[1] == e and r[2] == "0" and not r[0].startswith("ctl-")) == 0, f"{e}: a phase-0 row that is not ctl-*")
phases = {r[2] for r in rows} - {"0"}
done = open(os.path.join(root, "tests/parity/editions.done"), encoding="utf-8").read().split()
need(done == [] and all(d in phases for d in done), f"editions.done holds {done}")
# ---- no rewrite token in a fragment; translate.tsv shape -----------------------------------------
tr = [l.rstrip("\n").split("\t") for l in open(os.path.join(root, "tests/parity/translate.tsv"), encoding="utf-8")]
need(tr[0] == ["edition", "from", "to", "applies"], "translate.tsv header")
tr = tr[1:]
need(all(len(t) == 4 and all(t) for t in tr), "translate.tsv: a ragged or empty cell")
need(dict(collections.Counter(t[0] for t in tr)) == {'codex': 17, 'copilot': 19, 'local': 16}, "translate.tsv rows per edition changed")
need(len({(t[0], t[1]) for t in tr}) == len(tr), "translate.tsv: a repeated (edition, from)")
frag_files = ['tier-clauses.txt', 'stage4-light-clauses.txt', 'stage7d-clauses.txt', 'stage8-clauses.txt', 'stage8-xander-row.txt', 'pipeline-s8-xander-row.txt', 'phaserows-clauses.txt', 'bob-duty-clauses.txt', 'flags-clauses.txt', 'layout-clauses.txt', 'codex-skeleton-clauses.txt', 'nolinter-clauses.txt', 'eval-sentences.txt']
for fn in frag_files:
    for ln in open(os.path.join(root, "tests/policy", fn), encoding="utf-8").read().split("\n"):
        for t in tr:
            if ln.strip() and t[1] in ln:
                bad.append(f"{fn}: a fragment contains the rewrite token {t[1]!r}: {ln[:50]!r}")
# ---- shipped files: content pins, no host or user path -------------------------------------------
pins = {'scripts/check-edition-text.py': '5c25b792dafd7ce91aa26bd466a3f8e7d688f28e8244475e3a8b8aa98a16ba78', 'tests/parity/editions.tsv': '1d5e09b6cdb90e15cf7e94929db66e1c98a849ff6790fbbab9338ee0bb55bc37', 'tests/policy/bob-duty-clauses.txt': '4136590bbe8ec8e45ca2dd3b90e00fff84c7d3656b0fba1c30cbed0a771876f6', 'tests/policy/codex-skeleton-clauses.txt': '552c6d7270b632fad6f92179b990a61ff646a0461a1628cc9bfc5d2289ed02a3', 'tests/policy/conductor-skeleton.md': '0d4c60d6831cf734ab09b369c74b0dbb8fa788df45bbfb274ee6f8debb72e3a4', 'tests/policy/eval-sentences.txt': '54bdf068c5a6e02b377d29e35c25527e39a2ea53f3979ac5c1598ea487c3c229', 'tests/policy/flags-clauses.txt': 'a7b355b06488896fe8b37ada2e61d09b24d9db152baba9195378677f16b24b3c', 'tests/policy/heavy-example.re': '2d91efe6669d8c0db322b49bd96f93fc66113d1c8ec7ae9443808ff6d2d017e2', 'tests/policy/heavy-variant.mask': 'e25b4613ad8fc627a17b30da511b7daefb2842e329bc4297bc856f2abbd768b7', 'tests/policy/heavy-variant.re': 'cd56b6cd0333cff7ef9574fa7c0671743bf1b46c5d3f9d13590e5c4209e566b2', 'tests/policy/label-forms.re': '2072d1b51d70f3f26dda69e8057b4eadc66ad8807db09fd12bac6f996e22de1d', 'tests/policy/layout-clauses.txt': '7999ff46f71fe4f1817d2847ea0f983e1f105c2ebd6acf2c231b30046be7beb6', 'tests/policy/ledger-skeleton.md': 'ef5a4b4058103f37763149bc2915925ca17ce0ceb12e542436ca7dddd5b4cfd5', 'tests/policy/no-progress.txt': 'fcdc92472fc9af1db105b23fc4a50ebbc77c037f23ce3dffc7ca46872f88fd2b', 'tests/policy/nolinter-clauses.txt': '2cf234cd490d048034001f721bc16cbc3201f4a1902188cfb74745f8a95b9f4a', 'tests/policy/phaserows-clauses.txt': '52238d65ac7077c555fa2115f858f686458a8b0098e21f1765c839d5e87be5ba', 'tests/policy/pipeline-flags-stanza.md': '7eae3fe89c3a62aad1ab320c105deb1e009990ce4d32cc65cc4d7a5b49124d96', 'tests/policy/pipeline-s8-xander-row.txt': '041e8ea14ebf4196681f58fcf7b0e39182a4d3ebfe8286848e2991c9044fd5c3', 'tests/policy/reviewer-label.re': '0e9dd6998fa0f20d9d42e4be5b2355575917f42146bc7445bc57217655f0fe2c', 'tests/policy/s3-snippet.txt': '1f3f8aea013e733877a752aa270453d3a72e11383808a2868de31fadd3b1ae70', 'tests/policy/stage4-light-clauses.txt': '8397fa50fe094c8cfd9b8756c61f37e750c4d10855892d8a5f3aaa9b3cdd0e1b', 'tests/policy/stage7d-clauses.txt': '5587c16fba00273f76993857f820f53dbf425c21810cd5bf479982e718852f3e', 'tests/policy/stage8-clauses.txt': 'ed79edc40907240582ac593efa725a7e30bcf0f9fe8e6e9c7e429c2ac172dc77', 'tests/policy/stage8-xander-row.txt': '9f7df240ac5f5103065817f64283dca4eb624317f5fc5a55075a3e164a58ddb2', 'tests/policy/survivors.tsv': '8c2f63857d61c654ed061b575fe37f776d29746349ec2a44ef5b709348b96a9c', 'tests/policy/tier-clauses.txt': '1f9f4957a2c71969b56b825f1bf09c486cb3e1a339d2fe6fe18d9a65a0fd4bc8', 'tests/policy/traces-to-grammar.txt': '4eaa67900b160688104ce20039912a0b26635daec456928fea164540d213cb74', 'tests/policy/xander-terms.txt': '7bbbff4a89df0d40ea12b2916d15d0ad78c540f09a7d7e60421e295acb88fcc4'}
named = sorted({n for r in rows for c in (r[8], r[6]) for n in re.findall(r"(?:^|[=;])@([A-Za-z0-9._-]+)", c)})
need(named == sorted(n.split("/", 2)[2] for n in pins if n.startswith("tests/policy/")), "the set of policy files the table names changed")
for path, want in pins.items():
    need(os.path.isfile(os.path.join(root, path)) and sha(path) == want, f"{path}: sha256 differs from V36's pin")
    txt = open(os.path.join(root, path), encoding="utf-8").read()
    need("mozart-local" not in txt and "/Users/" not in txt, f"{path} names mozart-local or a /Users/ path")
need(sha("tests/parity/templates-allow.re") == "20df0c46c20d29aad58da39f76d5e1292643e89ce58f1dc5d682753de0232167", "templates-allow.re changed")
need(open(os.path.join(root, "tests/policy/s3-snippet.txt"), "rb").read() == open(os.path.join(root, "tests/parity/snippets/S3.txt"), "rb").read(), "s3-snippet.txt differs from the frozen S3 snippet")
for pol, src in (("ledger-skeleton.md", "agents/TEMPLATE-LEDGER.md"), ("conductor-skeleton.md", "agents/TEMPLATE-CONDUCTOR.md")):
    need(open(os.path.join(root, "tests/policy", pol), "rb").read() == open(os.path.join(root, src), "rb").read(), f"{pol} differs from {src}")
need(os.path.getsize(os.path.join(root, "tests/parity/witness.diff")) == 0, "witness.diff is not empty")
# ctl-s3 hosts equal the S3_HOST_* table of check-editions.sh
sh = open(os.path.join(root, "scripts/check-editions.sh"), encoding="utf-8").read()
hosts = dict(re.findall(r"^S3_HOST_(\w+)=(\S+)$", sh, re.M))
need(len(hosts) == 4, f"{len(hosts)} S3_HOST_ lines in check-editions.sh")
for e, h in hosts.items():
    need(byid.get(f"ctl-s3-{e}", [None] * 9)[4] == h, f"ctl-s3-{e} host differs from S3_HOST_{e}")
# survivors: every orchestration survivor names a real line
for ln in open(os.path.join(root, "tests/policy/survivors.tsv"), encoding="utf-8").read().split("\n"):
    if ln.startswith(("rule-variant-orchestration", "rule-example-orchestration", "rule-gaps-orchestration")):
        _, rel, text = ln.split("\t")
        need(text in open(os.path.join(root, rel), encoding="utf-8").read().split("\n"), f"survivor line not found in {rel}: {text[:40]!r}")
# the reader extracts the same xander rows V28 does (rows and sections passed in files)
spec = importlib.util.spec_from_file_location("ced", os.path.join(root, "scripts/check-edition-text.py"))
ced = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ced)
ctx = ced.Ctx("orchestration", root, root, os.path.join(root, "tests/parity/editions.tsv"))
for rid, fn in [('rule-xterms-s4-orchestration', 'd4'), ('rule-xterms-s8-orchestration', 'd8'), ('rule-xterms-p4-orchestration', 'p4'), ('rule-xterms-p8-orchestration', 'p8')]:
    r = dict(zip(ced.COLUMNS, byid[rid]))
    got = "\n".join(l for _, ls in ced.spans(ctx, r) for l in ls)
    want = open(os.path.join(sys.argv[2], fn), encoding="utf-8").read().rstrip("\n") if len(sys.argv) > 2 else None
    if want is not None:
        need(got == want, f"{rid}: the reader's xander row differs from v28_rows")
# held template diffs, once they exist
allow = re.compile(open(os.path.join(root, "tests/parity/templates-allow.re")).read().strip())
label = re.compile(open(os.path.join(root, "tests/policy/reviewer-label.re")).read().strip())
for ed, floor in (("copilot", 10), ("local", 10)):
    p = os.path.join(root, f"tests/parity/templates-{ed}.diff")
    if not os.path.isfile(p):
        continue
    text = open(p, encoding="utf-8").read().split("\n")
    changed = [l for l in text if l[:1] in "+-" and not l.startswith(("+++ ", "--- "))]
    need(len(changed) >= floor, f"templates-{ed}.diff: {len(changed)} changed lines, floor {floor}")
    for l in text:
        if l and not allow.match(l):
            bad.append(f"templates-{ed}.diff: a line outside templates-allow.re: {l[:60]!r}")
        if l.startswith("+") and not l.startswith("+++ ") and label.search(l):
            bad.append(f"templates-{ed}.diff: an added line keeps a source reviewer label: {l[:60]!r}")
print("BAD " + "; ".join(bad) if bad else f"OK {len(rows)} rows")
V36_PY
)
  case "$v36_py" in OK*) ;; *) v36_bad="$v36_bad [${v36_py:0:900}]" ;; esac
  # ---- the reference rows hold against this repo alone: only the lens row waits for its phase -------
  v36_done=$(cat "$gate_root/tests/parity/editions.done")
  v36_out=$(python3 "$v36_reader" --edition orchestration --root "$gate_root" --source "$gate_root" --done "$v36_done" 2>&1); v36_rc=$?
  v36_ok=$(grep -c '^ok ' <<<"$v36_out" || true)
  v36_pend=$(grep -c '^PENDING ' <<<"$v36_out" || true)
  v36_fail=$(grep -c '^FAIL ' <<<"$v36_out" || true)
  if [ -z "$v36_done" ] || ! grep -qw 1b <<<"$v36_done"; then
    { [ "$v36_rc" -eq 5 ] && [ "$v36_ok" -eq 72 ] && [ "$v36_pend" -eq 1 ] && [ "$v36_fail" -eq 0 ] && grep -q '^PENDING lens-orchestration: file-created$' <<<"$v36_out"; } \
      || v36_bad="$v36_bad [the orchestration rows: rc=$v36_rc ok=$v36_ok pending=$v36_pend FAIL=$v36_fail, want 5 72 1 0 with only lens-orchestration pending]"
  else
    { [ "$v36_rc" -eq 0 ] && [ "$v36_ok" -eq 73 ] && [ "$v36_fail" -eq 0 ]; } \
      || v36_bad="$v36_bad [the orchestration rows with 1b done: rc=$v36_rc ok=$v36_ok FAIL=$v36_fail, want 0 73 0]"
  fi
  # the reader's call-site literals: five lines per edition, and the table's own row counts
  for v36_e in orchestration codex copilot local; do
    v36_h=$(python3 "$v36_reader" hashes --edition "$v36_e" 2>&1)
    [ "$(grep -c '^--expect-[a-z0-9-]* [0-9a-f]*$' <<<"$v36_h" || true)" = "5" ] || v36_bad="$v36_bad [hashes --edition $v36_e does not print five literals]"
  done
fi
rm -rf "$v36_tmp"

report "V36_editions_table" "$([ -z "$v36_bad" ] && echo 0 || echo 1)" \
  "${v36_bad:-385 rows (codex 101, copilot 105, local 106, orchestration 73), 83 row families by edition, the id list, the kind, phase and expect of every row and the + marks pinned by content; the seven named members; xander-terms.txt, heavy-variant.re and heavy-variant.mask equal to V28's own literals in this shell and to V36's twelve names, seven variant plants and the masked sentence; 26 policy files, the reader, the table and templates-allow.re pinned by sha256; no fragment holds a rewrite token; no host or user path in a shipped file; ctl-s3 hosts equal S3_HOST_*; the orchestration rows ok (lens waiting for 1b)}"

# ---------------------------------------------------------------------------
# V18-V23 - the carved manual bundle (phase 6). Conservation proves text still
# EXISTS; these prove the pointers into it still RESOLVE, which conservation is
# structurally blind to. python3 missing is a FAIL, never a skip.
# ---------------------------------------------------------------------------
v18_script="$gate_root/scripts/check-manual-bundle.py"
if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$v18_script" ]; then
  for v18_g in V18_index V19_anchors V20_pointers V21_refs V22_frontmatter V23_absence V24_docs V26_ondemand; do
    report "$v18_g" 1 "scripts/check-manual-bundle.py unavailable (FAIL, not skip)"
  done
else
  v18_out=$(python3 "$v18_script" 2>&1)
  v18_seen=0
  while IFS= read -r v18_line; do
    case "$v18_line" in
      PASS\ \ *) v18_seen=$((v18_seen + 1))
        report "$(printf '%s' "$v18_line" | awk '{print $2}')" 0 "$(printf '%s' "$v18_line" | cut -d' ' -f4- | sed 's/^ *//')" ;;
      FAIL\ \ *) v18_seen=$((v18_seen + 1))
        report "$(printf '%s' "$v18_line" | awk '{print $2}')" 1 "$(printf '%s' "$v18_line" | cut -d' ' -f4- | sed 's/^ *//')" ;;
    esac
  done <<EOF_V18
$v18_out
EOF_V18
  [ "$v18_seen" -eq 8 ] || report "V18_population" 1 \
    "check-manual-bundle.py reported $v18_seen gate line(s), want exactly 8"
fi

echo
if [ "$gate_fail" -eq 0 ]; then
  echo "ALL GATES PASS"
  exit 0
fi
echo "$gate_fail GATE(S) FAILED"
exit 1
