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

gatefile="${BASH_SOURCE[0]}"
root="${1:-$(cd "$(dirname "$gatefile")/.." && pwd)}"
cd "$root" || { echo "FATAL: cannot cd to $root"; exit 2; }

fail=0
report() { # report <name> <ok:0|1> <detail>
  if [ "$2" = "0" ]; then
    printf 'PASS  %-22s %s\n' "$1" "$3"
  else
    printf 'FAIL  %-22s %s\n' "$1" "$3"
    fail=$((fail + 1))
  fi
}
eq() { [ "$1" = "$2" ] && echo 0 || echo 1; }
ge() { [ "$1" -ge "$2" ] && echo 0 || echo 1; }

echo "== mozart contract gates =="
echo "root: $root"
echo "gate file: $gatefile"
echo

# ---------------------------------------------------------------------------
# V0 - no gate's scope reaches this file, and no gate body has been mirrored
#      into a scanned file.                                    (Rules 1, 2)
# ---------------------------------------------------------------------------

# (a) structural: every gate below filters --include='*.md'. Enumerate the whole
#     population that filter can reach and assert none of it is a shell script.
mdsh=$(grep -rl --include='*.md' -e '' . 2>/dev/null | grep -c '[.]sh$')
case "$gatefile" in
  *.md) mdsh=$((mdsh + 1)) ;;
esac
report "V0a_scope_disjoint" "$(eq "$mdsh" 0)" "markdown-reachable .sh files=$mdsh (want 0)"

# (b) identity: derive the token set from THIS script's own assignments - never
#     a hand-written list, which is the scope-writing defect under repair - and
#     pin the count of markdown files carrying any of them at zero. A gate added
#     later is covered without editing V0.
gatevars=$(sed 's/^[[:space:]]*//; s/^local //' "$gatefile" \
  | grep -oE '^[A-Za-z_][A-Za-z_0-9]*=' | tr -d '=' | sort -u)
patfile=$(mktemp)
printf '(^|[^A-Za-z_0-9])(%s)=' "$(printf '%s\n' "$gatevars" | paste -sd'|' -)" > "$patfile"
gatevar_hits=$(grep -rlE --include='*.md' -f "$patfile" . 2>/dev/null | wc -l | tr -d ' ')
gatevar_where=$(grep -rlE --include='*.md' -f "$patfile" . 2>/dev/null | paste -sd' ' -)
rm -f "$patfile"
report "V0b_no_mirrored_gate" "$(eq "$gatevar_hits" 0)" \
  "derived $(printf '%s\n' "$gatevars" | wc -l | tr -d ' ') names; markdown hits=$gatevar_hits ${gatevar_where}"

# ---------------------------------------------------------------------------
# V1 - the shipped state-field probes match what the template writes, and no
#      bare-form grep survives.                                (Rules 2, 3)
# ---------------------------------------------------------------------------

# Scope derived: the field list comes from the state-file template, not a list.
fields=$(awk '/^\*\*Last updated\*\*/{f=1} f && /^\*\*[A-Z]/{gsub(/^\*\*/,"");sub(/\*\*.*/,"");print} f && /^## Tickets/{exit}' \
  agents/mozart.md | sort -u)
alt=$(printf '%s\n' "$fields" | paste -sd'|' -)

# must-not half: no invocation may still grep the bare "<Field>: " form.
v1_stale=$(grep -cE "grep[^\"']*[\"']($alt): " agents/mozart.md)
report "V1_absence" "$(eq "$v1_stale" 0)" "bare-form grep invocations=$v1_stale (want 0) over fields: $alt"

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
enum=$(grep -m1 -E '^\*\*Status\*\*: ' agents/mozart.md | sed -E 's/^\*\*Status\*\*: //; s/ *\| */ /g')
v1_bad=""
corpus=$(mktemp -d)
while IFS= read -r gpat; do
  [ -n "$gpat" ] || continue
  gval="${gpat##*: }"
  case " $enum " in
    *" $gval "*) ;;
    *) v1_bad="$v1_bad [value '$gval' not in enum: $enum]" ; continue ;;
  esac
  gother=""
  for candidate in $enum; do
    [ "$candidate" = "$gval" ] || { gother="$candidate"; break; }
  done
  printf '**Status**: %s\n' "$gval"   > "$corpus/bold.md"
  printf 'Status: %s\n'     "$gval"   > "$corpus/legacy.md"
  printf '**Status**: %s\n' "$gother" > "$corpus/other.md"
  grep -lE "$gpat" "$corpus/bold.md"   >/dev/null 2>&1 || v1_bad="$v1_bad [<$gpat> misses bold form]"
  grep -lE "$gpat" "$corpus/legacy.md" >/dev/null 2>&1 || v1_bad="$v1_bad [<$gpat> misses legacy form]"
  grep -lE "$gpat" "$corpus/other.md"  >/dev/null 2>&1 && v1_bad="$v1_bad [<$gpat> also matches '$gother']"
done < <(printf '%s\n' "$v1_pats")
rm -rf "$corpus"
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

codexsites=$(grep -rn --include='*.md' --exclude='CHANGELOG.md' -F 'codex exec ' . 2>/dev/null)
inv=$(printf '%s\n' "$codexsites" | grep -c .)
report "V2_inv" "$(eq "$inv" 8)" "codex exec sites=$inv (want 8)"

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

ordsites=$(grep -rn --include='*.md' --exclude='CHANGELOG.md' -F 'Exit 0 + missing target file' . 2>/dev/null)
ordn=$(printf '%s\n' "$ordsites" | grep -c .)
ord=$(printf '%s\n' "$ordsites" | awk '
  { f=index($0,"check the invocation for"); g=index($0,"budget");
    if (f==0 || g==0 || f>g) print }' | grep -c .)
report "V2_ordsites" "$(eq "$ordn" 2)" "exit-0-no-file diagnosis sites=$ordn (want 2)"
report "V2_ord" "$(eq "$ord" 0)" "sites where the output-flag check is absent or after the budget theory=$ord (want 0)"

sit=$(grep -cF 'Reading stdout instead of the target file' agents/mozart.md)
sit=$((sit + $(grep -cF 'escalate to user with the codex stdout as evidence' agents/mozart.md)))
sit=$((sit + $(grep -cF 'escalate to the user with the stdout transcript as evidence' agents/mozart.md)))
report "V2_sit" "$(ge "$sit" 3)" "stdout rule + both escalation clauses surviving=$sit (floor 3)"

# ---------------------------------------------------------------------------
# V3 - the range values are pinned; every scan cites the right name for its
#      family; the scans and the stop rule actually exist.     (Rules 2, 3)
# ---------------------------------------------------------------------------

ctl=$(grep -c '^## Pull request authoring' agents/scott.md)
report "V3_ctl" "$(eq "$ctl" 1)" "section heading '## Pull request authoring' found=$ctl (control: a rename must not silently empty the scope)"

# Fenced command lines inside the section, comments stripped. The fence toggle
# is a flag, not an awk range - an awk range would end on its own start line.
cmdlines=$(awk '
  /^## Pull request authoring/ { insec=1; next }
  /^## / { insec=0 }
  !insec { next }
  /^[[:space:]]*```/ { infence=!infence; next }
  infence {
    if ($0 ~ /^[[:space:]]*#/) next            # whole-line comment
    sub(/[[:space:]]#.*/,"")                   # trailing comment only: a bare
                                               # /^## / inside an awk program is
                                               # data, not a comment, and a naive
                                               # sub(/#.*/,"") deletes the rest of
                                               # the line - which is how an inlined
                                               # gate hid from V3_noinline.
    if ($0 ~ /[^[:space:]]/) print
  }
' agents/scott.md)

# Values are PINNED, byte-for-byte. A behavioural test cannot discriminate here:
# `git rev-list --count HEAD --not --remotes=origin` and the same command with
# HEAD dropped both return 0 whenever the base has no unpushed commits, which is
# the normal case and precisely why the bug is invisible until it matters.
want_range='HEAD --not --remotes=origin'
want_since='origin/<base>'
range_defs=$(grep -coE 'PUSH_RANGE="[^"]*"' agents/scott.md)
since_defs=$(grep -coE 'PUSH_SINCE="[^"]*"' agents/scott.md)
push_range_value=$(grep -m1 -oE 'PUSH_RANGE="[^"]*"' agents/scott.md | sed -E 's/^PUSH_RANGE="//; s/"$//')
push_since_value=$(grep -m1 -oE 'PUSH_SINCE="[^"]*"' agents/scott.md | sed -E 's/^PUSH_SINCE="//; s/"$//')
report "V3_range_defs" "$(eq "$range_defs/$since_defs" "1/1")" "PUSH_RANGE/PUSH_SINCE definitions=$range_defs/$since_defs (want 1/1)"
report "V3_push_range_value" "$(eq "$push_range_value" "$want_range")" "PUSH_RANGE=[$push_range_value] want [$want_range]"
report "V3_push_since_value" "$(eq "$push_since_value" "$want_since")" "PUSH_SINCE=[$push_since_value] want [$want_since]"

a1=$(printf '%s\n' "$cmdlines" | grep -cF -- '--not --remotes=origin')
a2=$(printf '%s\n' "$cmdlines" | grep -cF -- 'origin/<base>')
bb=$(printf '%s\n' "$cmdlines" | grep -cF -- '<base>..HEAD')
report "V3_a1" "$(eq "$a1" 1)" "literal '--not --remotes=origin' on fenced command lines=$a1 (want 1: the definition block)"
report "V3_a2" "$(eq "$a2" 1)" "literal 'origin/<base>' on fenced command lines=$a2 (want 1: the definition block)"
report "V3_b"  "$(eq "$bb" 0)" "local range '<base>..HEAD' on fenced command lines=$bb (want 0)"

cite=$(printf '%s\n' "$cmdlines" | awk '
  { if (index($0,"$PUSH_RANGE")>0 || index($0,"$PUSH_SINCE")>0) n++ } END { print n+0 }')
report "V3_cite" "$(ge "$cite" 3)" "fenced command lines expanding a range name=$cite (floor 3: gitleaks, trufflehog, fallback)"

# Family mismatch, quote-agnostic: a --log-opts family member takes the RANGE,
# a --since-commit family member takes the single COMMIT. Never crossed.
fam=$(printf '%s\n' "$cmdlines" | awk '
  { if (index($0,"--log-opts")>0     && index($0,"$PUSH_SINCE")>0) n++;
    if (index($0,"--since-commit")>0 && index($0,"$PUSH_RANGE")>0) n++ } END { print n+0 }')
report "V3_fam" "$(eq "$fam" 0)" "family mismatches (range name on a single-commit flag or vice versa)=$fam (want 0)"

# The fallback must be a real git log -p over the named range, not a citation.
fallback_is_real=$(printf '%s\n' "$cmdlines" | awk '
  { if ($0 ~ /git .*log .*-p .*[$]PUSH_RANGE/) n++ } END { print n+0 }')
report "V3_fallback_is_real" "$(ge "$fallback_is_real" 1)" "fenced 'git ... log ... -p ... \$PUSH_RANGE' fallback commands=$fallback_is_real (floor 1)"

stop_rule=$(grep -cF 'A scan that does not run is not a clean scan' agents/scott.md)
report "V3_stop_rule" "$(ge "$stop_rule" 1)" "failed-scan stop rule present=$stop_rule (floor 1, pinned by its text)"

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
done < <(printf '%s\n' "$v4_roster")
report "V4_section" "$([ -z "$v4_bad" ] && echo 0 || echo 1)" \
  "${v4_bad:-all $v4_n specialists: section present exactly once, before Field notes, marker contained}"

# ---------------------------------------------------------------------------
# V4c - roster and markers agree PER PIPELINE; every shape present by name;
#       no en dash in a stage list.                                  (Rule 2)
# ---------------------------------------------------------------------------

# U+2013 EN DASH, CONSTRUCTED from its codepoint - never pasted into this file,
# so an editor that "tidies" en dashes cannot silently retarget the rule.
EN=$(printf '\xe2\x80\x93')
v4c_exempt="1${EN}13"

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

# One normalizer, two feeds. Parentheticals are dropped FIRST because they
# contain both ';' and shape-shaped uppercase words.
v4c_norm() {
  awk -F'\t' -v EN="$EN" '{
    nm=$1; s=$2
    gsub(/\([^)]*\)/,"",s)
    gsub(EN,"~",s)
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

v4c_rosterpairs=$(printf '%s\n' "$v4_roster" | v4c_norm | sort -u)
v4c_markerpairs=$(while IFS="$(printf '\t')" read -r ag _; do
    [ -n "$ag" ] || continue
    [ -f "agents/$ag.md" ] || continue
    grep -hE '^\*\*Your [A-Z]+ stages\*\*:' "agents/$ag.md" | while IFS= read -r ml; do
      pp=$(printf '%s' "$ml" | sed -E 's/^\*\*Your ([A-Z]+) stages\*\*:.*/\1/')
      vv=$(printf '%s' "$ml" | sed -E 's/^\*\*Your [A-Z]+ stages\*\*:[[:space:]]*//')
      printf '%s\t%s %s\n' "$ag" "$pp" "$vv"
    done
  done < <(printf '%s\n' "$v4_roster") | v4c_norm | sort -u)

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
v4c_residue=$(printf '%s\n' "$v4c_population" | sed "s/${v4c_exempt}//g" | grep -cF "$EN")
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

v6_hank_chain=$(grep -cF 'OPERATE stages: 1.Intake+context pin' agents/hank.md)
report "V6_hank_chain" "$(eq "$v6_hank_chain" 0)" "whole-pipeline restatement surviving in hank.md=$v6_hank_chain (want 0)"

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL GATES PASS"
  exit 0
fi
echo "$fail GATE(S) FAILED"
exit 1
