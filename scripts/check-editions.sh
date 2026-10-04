#!/usr/bin/env bash
#
# check-editions.sh — are the three ports still the same mechanism as this repo?
#
# Pre-merge tool, not a gate in mozart-contract-gates.sh: that script's report()
# has only PASS and FAIL, and a cross-checkout check there is either red in
# single-repo CI or vacuously green having compared nothing (CONTRIBUTING.md).
# mozart-codex has no CI at all, so this is the only thing that looks at it.
#
# Per edition (this repo is the fourth and always runs):
#   S3         the frozen conductor-record snippet (tests/parity/snippets/S3.txt)
#              occurs exactly once in the file that edition keeps it in
#   lib        scripts/lib-campaign.sh is byte-identical to this repo's
#              (codex and copilot; local ships no campaign scripts)
#   behaviour  the edition's lint and metrics, run over this repo's fixture
#              corpus by scripts/check-field-note-parity.py, match expected.tsv
#              (codex and copilot). This repo's own scripts are checked against
#              the corpus by the gate suite (V11, V10b), not again here.
#
# Usage:
#   check-editions.sh [--skip-behaviour] [<codex> <copilot> <local>]
#   check-editions.sh [--skip-behaviour] codex=<path> copilot=<path> local=<path>
#
# Roots: arguments (three paths in that order, or NAME=PATH pairs for any
# subset; an edition not named is skipped), else MOZART_EDITION_ROOTS (the same
# two spellings, colon-separated, so a path cannot contain a colon), else
# ../mozart-codex ../mozart-copilot ../mozart-local beside this checkout.
# Relative paths are absolutised.
#
# --skip-behaviour omits the slow arm (minutes per edition). A run that skipped
# it can never exit 0: it exits 4. The gate suite uses it for the exit-code
# arms; it is not a way to get a green run.
#
# Exit codes, in precedence order:
#   1  a check failed (an existing but empty directory is a failure)
#   3  no check failed but an edition was skipped (the path does not exist)
#   4  everything run passed, but --skip-behaviour left the behaviour arm out
#   0  all four editions ran every arm and passed
#   2  usage error
# Failure outranks skip: the SKIP line is still printed. A port script that
# exits other than 0 or 1 is reported as a failure with its output shown.

set -uo pipefail

self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$(dirname "$self_dir")
S3_FILE="$SRC/tests/parity/snippets/S3.txt"
CORPUS="$SRC/tests/fixtures/conductor"
HARNESS="$SRC/scripts/check-field-note-parity.py"
LIB="$SRC/scripts/lib-campaign.sh"

# Where each edition keeps the S3 host text. mozart-contract-gates.sh (V31)
# builds its fake roots from this same table; a change here fails that gate.
S3_HOST_orchestration=agents/STATE.md
S3_HOST_codex=.codex/skills/mozart/SKILL.md
S3_HOST_copilot=.github/mozart/manual/STATE.md
S3_HOST_local=src/mozart_local/bundle/manual/STATE.md

usage() {
  echo "usage: $0 [--skip-behaviour] [<codex> <copilot> <local>]" >&2
  echo "       $0 [--skip-behaviour] [codex=<path>] [copilot=<path>] [local=<path>]" >&2
  echo "       (else MOZART_EDITION_ROOTS, colon-separated; else ../mozart-{codex,copilot,local})" >&2
  exit 2
}

skip_behaviour=0
root_codex=""; root_copilot=""; root_local=""
given_codex=0; given_copilot=0; given_local=0

set_named() { # set_named <edition> <path>; a repeated edition is a usage error
  case $1 in
    codex)   [ "$given_codex" = 0 ]   || usage; given_codex=1;   root_codex=$2 ;;
    copilot) [ "$given_copilot" = 0 ] || usage; given_copilot=1; root_copilot=$2 ;;
    local)   [ "$given_local" = 0 ]   || usage; given_local=1;   root_local=$2 ;;
    *) usage ;;
  esac
}

# take_items: the items are in the array `items`. NAME=PATH pairs (no slash
# before the =), or exactly three plain paths in edition order.
take_items() {
  n_named=0; n_plain=0
  i=0
  while [ "$i" -lt "${#items[@]}" ]; do
    name=${items[$i]%%=*}
    case $name in
      */*) n_plain=$((n_plain + 1)) ;;
      *) if [ "$name" = "${items[$i]}" ]; then n_plain=$((n_plain + 1)); else n_named=$((n_named + 1)); fi ;;
    esac
    i=$((i + 1))
  done
  if [ "$n_named" -gt 0 ] && [ "$n_plain" -gt 0 ]; then usage; fi
  if [ "$n_named" -gt 0 ]; then
    i=0
    while [ "$i" -lt "${#items[@]}" ]; do
      set_named "${items[$i]%%=*}" "${items[$i]#*=}"
      i=$((i + 1))
    done
  else
    [ "${#items[@]}" -eq 3 ] || usage
    set_named codex "${items[0]}"; set_named copilot "${items[1]}"; set_named local "${items[2]}"
  fi
}

items=()
for a in "$@"; do
  case $a in
    --skip-behaviour) skip_behaviour=1 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) items[${#items[@]}]=$a ;;
  esac
done

if [ "${#items[@]}" -gt 0 ]; then
  take_items
elif [ -n "${MOZART_EDITION_ROOTS:-}" ]; then
  IFS=: read -r -a items <<<"$MOZART_EDITION_ROOTS"
  take_items
else
  set_named codex "$SRC/../mozart-codex"
  set_named copilot "$SRC/../mozart-copilot"
  set_named local "$SRC/../mozart-local"
fi

ran=0; skipped=0; failed=0
fail() { # fail <edition> <message>
  printf 'FAIL %s: %s\n' "$1" "$2"
  failed=$((failed + 1))
}

s3_count() { # s3_count <file>: how many times S3 occurs in it
  python3 -c 'import sys
want = open(sys.argv[1]).read().strip()
print(open(sys.argv[2]).read().count(want) if want else -1)' "$S3_FILE" "$1"
}

check_s3() { # check_s3 <edition> <root>
  host=$(eval "echo \$S3_HOST_$1")
  if [ ! -f "$2/$host" ]; then
    fail "$1" "S3 host file $host not found under $2"
    return
  fi
  n=$(s3_count "$2/$host") || { fail "$1" "python3 could not read $2/$host"; return; }
  if [ "$n" = "1" ]; then
    echo "ok   $1: S3 occurs once in $host"
  else
    fail "$1" "S3 occurs $n time(s) in $host, want exactly 1"
  fi
}

check_lib() { # check_lib <edition> <root>
  if [ ! -f "$2/scripts/lib-campaign.sh" ]; then
    fail "$1" "scripts/lib-campaign.sh is absent from $2"
  elif cmp -s "$LIB" "$2/scripts/lib-campaign.sh"; then
    echo "ok   $1: scripts/lib-campaign.sh byte-identical to this repo's"
  else
    fail "$1" "scripts/lib-campaign.sh differs from this repo's (cmp)"
  fi
}

# The one precondition that is about this repo, not an edition.
src_ok=1
for f in "$S3_FILE" "$LIB" "$HARNESS" "$SRC/$S3_HOST_orchestration"; do
  [ -s "$f" ] || { src_ok=0; fail orchestration "$f is absent or empty"; }
done
[ -d "$CORPUS" ] || { src_ok=0; fail orchestration "fixture corpus $CORPUS is absent"; }
command -v python3 >/dev/null 2>&1 || { src_ok=0; fail orchestration "python3 not found"; }

echo "RUN orchestration $SRC (S3)"
ran=$((ran + 1))
[ "$src_ok" = 1 ] && check_s3 orchestration "$SRC"

behaviour_only=""
bs_codex=$SRC; bs_copilot=$SRC
for ed in codex copilot local; do
  given=$(eval "echo \$given_$ed"); path=$(eval "echo \$root_$ed")
  if [ "$given" = 0 ] || [ ! -e "$path" ]; then
    echo "SKIP $ed: checkout not found"
    skipped=$((skipped + 1))
    continue
  fi
  if [ ! -d "$path" ]; then
    echo "RUN $ed $path (not a directory)"
    ran=$((ran + 1))
    fail "$ed" "$path exists but is not a directory"
    continue
  fi
  abs=$(cd -- "$path" && pwd)
  if [ "$ed" = local ]; then
    echo "RUN $ed $abs (S3; ships no campaign scripts, so no lib or behaviour arm)"
  else
    echo "RUN $ed $abs (S3, lib, behaviour)"
  fi
  ran=$((ran + 1))
  [ "$src_ok" = 1 ] || continue
  check_s3 "$ed" "$abs"
  if [ "$ed" != local ]; then
    check_lib "$ed" "$abs"
    behaviour_only="${behaviour_only:+$behaviour_only,}$ed"
    eval "bs_$ed=\$abs"
  fi
done

partial=0
if [ -n "$behaviour_only" ] && [ "$src_ok" = 1 ]; then
  if [ "$skip_behaviour" = 1 ]; then
    partial=1
  else
    hout=$(python3 "$HARNESS" behaviour --corpus "$CORPUS" --only "$behaviour_only" \
      --scripts-root "orchestration=$SRC" --scripts-root "codex=$bs_codex" \
      --scripts-root "copilot=$bs_copilot" --scripts-root "local=$SRC" 2>&1); hrc=$?
    shown=0
    for ed in $(echo "$behaviour_only" | tr ',' ' '); do
      # The harness exits 1 when ANY edition failed, so its status says nothing
      # about this one: the edition's own PASS line is the evidence.
      if grep -qE "^PASS  $ed: behaviour checks complete" <<<"$hout"; then
        echo "ok   $ed: behaviour (lint and metrics over the corpus match expected.tsv)"
      else
        fail "$ed" "behaviour: no PASS line from the harness (exit $hrc; output below)"
        shown=1
      fi
    done
    if [ "$shown" = 1 ]; then
      sed 's/^/  | /' <<<"$hout"
    fi
  fi
fi

echo "editions: $ran run, $skipped skipped, $failed failed"
if [ "$failed" -gt 0 ]; then exit 1; fi
if [ "$skipped" -gt 0 ]; then exit 3; fi
if [ "$partial" = 1 ]; then
  echo "PARTIAL: --skip-behaviour left the behaviour arm out; exit 4, never 0"
  exit 4
fi
[ "$ran" = 4 ] || { echo "FAIL: only $ran edition(s) ran" >&2; exit 1; }
exit 0
