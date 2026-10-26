#!/bin/sh
# mozart-lib-host.sh - the two helpers every host-side script shares: host_id and
# the argument-grammar check. POSIX sh, defines functions only (sourcing it runs
# nothing), and reads nothing but a machine identifier.
#
# It is streamed ahead of the probe (cat this file and mozart-probe.sh into
# `sh -s`) and sourced by mozart-remote.sh, so it must not depend on either.

# mz_cmd <cmd> [args]: run a helper with stdin closed. Callers that need a
# time bound (the probe) redefine this after sourcing; the default has none.
mz_cmd() {
  "$@" </dev/null 2>/dev/null
}

# mz_arg_ok <string>: succeeds when the string satisfies the argument grammar
# in mozart-schemas.json (grammars.arg): 1 to 255 characters from A-Za-z0-9._/-
# and no leading "-". The classes are spelled out because a bracket range is
# read through the locale by some shells.
mz_arg_ok() {
  case $1 in
    ''|-*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*) return 1 ;;
  esac
  [ "${#1}" -le 255 ]
}

# mz_sha256 <string>: prints the hex digest of the string's bytes, or nothing.
mz_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum 2>/dev/null | { read -r mz_h mz_rest; printf '%s' "$mz_h"; }
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 2>/dev/null | { read -r mz_h mz_rest; printf '%s' "$mz_h"; }
  fi
}

# host_id: prints the sha256 of this machine's identifier (IOPlatformUUID on
# macOS, machine-id elsewhere), or nothing when there is no usable source. The
# raw identifier is never printed. The digest is what `enroll` shows the user and
# what a registry `identity:` line must equal.
host_id() {
  mz_raw=
  case $(mz_cmd uname -s) in
    Darwin)
      mz_ioreg=$(mz_cmd ioreg -rd1 -c IOPlatformExpertDevice)
      mz_tail=${mz_ioreg#*\"IOPlatformUUID\"}
      if [ "$mz_tail" != "$mz_ioreg" ]; then
        mz_tail=${mz_tail#*\"}
        mz_raw=${mz_tail%%\"*}
      fi
      ;;
    *)
      for mz_file in /etc/machine-id /var/lib/dbus/machine-id; do
        if [ -r "$mz_file" ] && read -r mz_raw <"$mz_file" && [ -n "$mz_raw" ]; then
          break
        fi
        mz_raw=
      done
      ;;
  esac
  case $mz_raw in
    '') return 0 ;;
    *[!0123456789ABCDEFabcdef-]*) return 0 ;;
  esac
  [ "${#mz_raw}" -ge 8 ] || return 0
  mz_digest=$(mz_sha256 "$mz_raw")
  case $mz_digest in
    *[!0123456789abcdef]*) return 0 ;;
  esac
  [ "${#mz_digest}" -eq 64 ] && printf '%s' "$mz_digest"
  return 0
}
