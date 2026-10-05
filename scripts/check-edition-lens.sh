#!/usr/bin/env bash
# check-edition-lens.sh — does an edition's linter have the lens-record rule on by default?
#
# Usage: check-edition-lens.sh <edition> <root>
#   <root> is the edition's checkout; its scripts/mozart-lint.sh is the script under test.
#   The fixtures are this repo's (tests/fixtures/lens, tests/fixtures/conductor/lint), found from
#   this file's own location, so the helper is source-only: a port never carries it.
#
# Exit: 0 all six arms pass, 1 at least one arm failed (a content reason), 2 the helper could not run.
# Output: "ok <arm> ..." or "FAIL <arm>: <message>" per arm, a..f. scripts/check-edition-text.py's
# lens-src kind reads those and the exit code; it is never given a verdict by this file's text.
#
# Every run unsets MOZART_LINT_LENS_SINCE and MOZART_LINT_CONDUCTOR_SINCE (except arm e, which pins the
# second), so what is measured is the DEFAULT date compiled into the script, which is the whole point:
# no other check in the suite can see a lint default (the parity harness pins the date itself).
#   a  HEAVY, slug 2026-10-03, no surface record      no `no usable surface record` line
#      control: the same file with the date forced to 2020-01-01 gains that line and only lens lines
#   b  HEAVY, slug 2026-10-04, no surface record      exactly one `no usable surface record` line
#   c  HEAVY (surface: auth), both lens fields        neither lens message
#   d  STANDARD, slug 2026-10-04                      neither lens message
#   e  the conductor lint corpus, CONDUCTOR_SINCE=2099-06-01, lens date unset: exactly 10 such lines,
#      and a second run prints the same bytes (the count means nothing if the output is not stable)
#   f  HEAVY (surface: auth), one lens field missing  the lens-field message; (f) is what gives (c) meaning
# Fixtures are copied to scratch and touched to now first: stale-active is mtime-based.

set -uo pipefail

usage() { echo "usage: check-edition-lens.sh <edition> <root>" >&2; exit 2; }
cannot() { echo "check-edition-lens: could not run: $1" >&2; exit 2; }

[ "$#" -eq 2 ] || usage
edition=$1
root=$2
case "$edition" in orchestration|codex|copilot|local) ;; *) usage ;; esac

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || cannot "cannot resolve this script's directory"
fixtures="$here/../tests/fixtures"
lint="$root/scripts/mozart-lint.sh"
[ -f "$lint" ] || cannot "$edition has no scripts/mozart-lint.sh under $root"
for arm in a b c d f; do
  ls "$fixtures/lens/$arm"/*.state.md >/dev/null 2>&1 || cannot "no fixture for arm $arm under $fixtures/lens"
done
[ -d "$fixtures/conductor/lint" ] || cannot "the conductor lint corpus is absent"

scratch=$(mktemp -d) || cannot "no scratch directory"
trap 'rm -rf "$scratch"' EXIT

MSG_SURFACE='no usable surface record'
MSG_LENS_FIELD='does not record ian and xander'

# stage <arm> -> prints the scratch root holding that fixture under .mozart/plans/active, touched to now
stage() {
  local dest="$scratch/$1"
  mkdir -p "$dest/.mozart/plans/active" || cannot "cannot create $dest"
  cp "$fixtures/lens/$1"/*.state.md "$dest/.mozart/plans/active/" || cannot "cannot copy the fixture for arm $1"
  find "$dest" -type f -exec touch {} + || cannot "cannot touch the fixture for arm $1"
  printf '%s' "$dest"
}

# run_lint <dir> [VAR=value ...] -> sets lint_out. Any VAR not listed stays unset: both date variables are
# removed first. Lint exits 0 (clean) or 1 (findings); anything else, including 2 ("nothing to lint"),
# means the script could not be measured.
run_lint() {
  local dir=$1; shift
  lint_out=$(env -u MOZART_LINT_LENS_SINCE -u MOZART_LINT_CONDUCTOR_SINCE LC_ALL=C "$@" bash "$lint" "$dir" 2>&1)
  local rc=$?
  { [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; } || cannot "the lint script exited $rc on $dir: ${lint_out:0:200}"
}

count() { grep -c -F -- "$2" <<<"$1" || true; }

failed=0
ok() { printf 'ok %s %s\n' "$1" "$2"; }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; failed=1; }

# (a) the day before the boundary: silent, and the silence is not the fixture going unread
dir=$(stage a)
run_lint "$dir"
default_out=$lint_out
run_lint "$dir" MOZART_LINT_LENS_SINCE=2020-01-01
forced_out=$lint_out
only_lens=$(comm -13 <(grep '^LINT ' <<<"$default_out" | sort) <(grep '^LINT ' <<<"$forced_out" | sort) | grep -c -v -E "$MSG_SURFACE|$MSG_LENS_FIELD" || true)
lost=$(comm -23 <(grep '^LINT ' <<<"$default_out" | sort) <(grep '^LINT ' <<<"$forced_out" | sort) | grep -c . || true)
if [ "$(count "$default_out" "$MSG_SURFACE")" -ne 0 ]; then
  fail a "a HEAVY campaign slugged 2026-10-03 gets \`$MSG_SURFACE\` by default (the lens date is earlier than 2026-10-04)"
elif [ "$(count "$forced_out" "$MSG_SURFACE")" -ne 1 ] || [ "$only_lens" -ne 0 ] || [ "$lost" -ne 0 ]; then
  fail a "control: forcing the date to 2020-01-01 must add exactly the surface line and nothing else (fixture not read as HEAVY, or the override does not work)"
else
  ok a "2026-10-03 HEAVY is silent by default; 2020-01-01 adds only the surface line"
fi

# (b) the first day: the rule is on
run_lint "$(stage b)"
if [ "$(count "$lint_out" "$MSG_SURFACE")" -eq 1 ]; then
  ok b "2026-10-04 HEAVY without a surface record gets the surface finding by default"
else
  fail b "a HEAVY campaign slugged 2026-10-04 with no surface record does not get \`$MSG_SURFACE\` exactly once by default (the lens date is later than 2026-10-04, or the rule is gone)"
fi

# (c) conformant HEAVY: neither message
run_lint "$(stage c)"
if [ "$(count "$lint_out" "$MSG_SURFACE")" -eq 0 ] && [ "$(count "$lint_out" "$MSG_LENS_FIELD")" -eq 0 ]; then
  ok c "a conformant HEAVY (surface: auth) campaign draws neither lens message"
else
  fail c "a conformant HEAVY (surface: auth) campaign with both lens fields draws a lens message"
fi

# (d) STANDARD is outside the rule
run_lint "$(stage d)"
if [ "$(count "$lint_out" "$MSG_SURFACE")" -eq 0 ] && [ "$(count "$lint_out" "$MSG_LENS_FIELD")" -eq 0 ]; then
  ok d "a STANDARD campaign dated 2026-10-04 draws neither lens message"
else
  fail d "a STANDARD campaign draws a lens message"
fi

# (e) the corpus: every 2099 slug is lens-dated under the default, so the count is the default's fingerprint
corpus="$scratch/e"
cp -R "$fixtures/conductor/lint" "$corpus" || cannot "cannot copy the conductor lint corpus"
find "$corpus" -type f -exec touch {} + || cannot "cannot touch the corpus"
run_lint "$corpus" MOZART_LINT_CONDUCTOR_SINCE=2099-06-01
first_out=$lint_out
run_lint "$corpus" MOZART_LINT_CONDUCTOR_SINCE=2099-06-01
n=$(count "$first_out" "$MSG_SURFACE")
if [ "$first_out" != "$lint_out" ]; then
  fail e "control: two runs over the corpus printed different bytes, so the count proves nothing"
elif [ "$n" -ne 10 ]; then
  fail e "the corpus draws $n \`$MSG_SURFACE\` line(s) with the lens date unset, want exactly 10"
else
  ok e "the corpus draws exactly 10 surface findings with the lens date unset, identically twice"
fi

# (f) one lens field missing on a ticked row: the lens-field message, and not the surface one
run_lint "$(stage f)"
if [ "$(count "$lint_out" "$MSG_LENS_FIELD")" -eq 1 ] && [ "$(count "$lint_out" "$MSG_SURFACE")" -eq 0 ]; then
  ok f "a ticked row missing xander draws the lens-field finding once, and only that"
else
  fail f "a HEAVY (surface: auth) row missing a lens field does not draw \`$MSG_LENS_FIELD\` exactly once"
fi

exit "$failed"
