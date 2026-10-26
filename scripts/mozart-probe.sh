#!/bin/sh
# mozart-probe.sh - read-only host facts, printed as one JSON object on stdout.
# POSIX sh. No network, and no state-changing command: version flags and listings
# only. The probe itself writes nothing outside a scratch directory it removes;
# the tools it runs (docker, claude, git ...) are the host's own and may write
# their own caches or logs.
#
# Run it by streaming it after the shared helpers, never by path:
#   cat mozart-lib-host.sh mozart-probe.sh | sh -s -- [--total-timeout N]
#
# The output keys are exactly the "facts" in mozart-schemas.json plus
# probe_version, probed_at and probe_errors. It always exits 0: a fact it could
# not read is null and the reason is a code in probe_errors.
#
# Every external command runs through mp_run: stdin closed (the script itself
# arrives on stdin, so a command that read it would eat the rest of the probe),
# at most 5 seconds each (--sub-timeout) and --total-timeout (default 30) overall, killed by a
# watchdog because macOS has no timeout(1). Strings are escaped in pure sh so the
# probe has no dependency on any text-processing tool.

LC_ALL=C
export LC_ALL
TZ=UTC
export TZ
set -f

MP_PROBE_VERSION=1
MP_TOTAL=30
MP_EACH=5
MP_CLAUDE_FLAGS='--print --permission-mode --permission-prompts --max-budget-usd --settings --setting-sources --strict-mcp-config --disallowedTools'
MP_KEYS='os os_version arch cpus mem_gb host_id xcodebuild android_sdk adb docker gpu gpu_name kube_contexts claude claude_flags codex git python3 node mozart_child_mode mozart_command keychain_unlocked linger ps_lstart load remote_home'
MP_NL='
'
MP_TAB=$(printf '\t')
MP_CR=$(printf '\r')
MP_ERRORS=
MP_DIR=
MP_BADARG=
MP_RC=127
MP_OUT=
MP_SEQ=0
MP_SPENT=0

for mp_k in $MP_KEYS; do
  eval "F_$mp_k=null"
done

mp_intarg() { # mp_intarg <value> <max>: succeeds when the value is an integer from 1 to <max>
  case $1 in
    ''|*[!0-9]*|0*) return 1 ;;
  esac
  [ "${#1}" -le 3 ] && [ "$1" -le "$2" ]
}

while [ $# -gt 0 ]; do
  case $1 in
    --total-timeout)
      if mp_intarg "${2-}" 600; then MP_TOTAL=$2; else MP_BADARG=1; fi
      [ $# -ge 2 ] && shift
      ;;
    --sub-timeout)
      if mp_intarg "${2-}" 60; then MP_EACH=$2; else MP_BADARG=1; fi
      [ $# -ge 2 ] && shift
      ;;
    *) MP_BADARG=1 ;;
  esac
  shift
done

# --- bookkeeping -------------------------------------------------------------

mp_err() { # mp_err <code>: record a probe error once
  case "$MP_NL$MP_ERRORS" in
    *"$MP_NL$1$MP_NL"*) ;;
    *) MP_ERRORS=$MP_ERRORS$1$MP_NL ;;
  esac
}

[ -z "$MP_BADARG" ] || mp_err bad-argument

if command -v mktemp >/dev/null 2>&1 && command -v sleep >/dev/null 2>&1; then
  MP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mozart-probe.XXXXXX" 2>/dev/null </dev/null)
  if [ -n "$MP_DIR" ] && [ -d "$MP_DIR" ]; then
    trap 'rm -rf "$MP_DIR"' EXIT
    trap 'rm -rf "$MP_DIR"; exit 0' HUP INT TERM
  else
    MP_DIR=
  fi
fi

MP_T0=$(date +%s 2>/dev/null </dev/null)

# mp_budget prints the seconds the next command may use; 0 means the total is spent.
# Elapsed time is the larger of the wall clock (when date works) and the seconds
# already lost to timeouts, so a host without date is still bounded.
mp_budget() {
  mp_b=$MP_EACH
  mp_used=$MP_SPENT
  case $MP_T0 in
    ''|*[!0-9]*) ;;
    *)
      mp_n=$(date +%s 2>/dev/null </dev/null)
      case $mp_n in
        ''|*[!0-9]*) ;;
        *) [ $((mp_n - MP_T0)) -le "$mp_used" ] || mp_used=$((mp_n - MP_T0)) ;;
      esac
      ;;
  esac
  mp_left=$((MP_TOTAL - mp_used))
  [ "$mp_left" -ge "$mp_b" ] || mp_b=$mp_left
  [ "$mp_b" -gt 0 ] || mp_b=0
  printf '%s' "$mp_b"
}

mp_slurp() { # mp_slurp <file>: MP_OUT = the file's lines, newline-terminated, at most 4096 of them
  MP_OUT=
  mp_n=0
  [ -r "$1" ] || return 0
  while IFS= read -r mp_l || [ -n "$mp_l" ]; do
    mp_n=$((mp_n + 1))
    [ "$mp_n" -le 4096 ] || break
    MP_OUT=$MP_OUT$mp_l$MP_NL
  done <"$1"
}

# mp_run <label> <cmd> [args]: run one command, stdin closed, output capped (see ulimit).
# MP_OUT = its stdout. MP_RC = its exit status, 124 when the watchdog killed it
# or the total budget was spent, 127 when it does not exist. Succeeds only on 0.
mp_run() {
  mp_label=$1
  shift
  MP_OUT=
  MP_RC=127
  command -v "$1" >/dev/null 2>&1 || return 1
  if [ -z "$MP_DIR" ]; then
    mp_err "$mp_label-unrunnable"
    return 1
  fi
  mp_secs=$(mp_budget)
  if [ "$mp_secs" -le 0 ]; then
    mp_err "$mp_label-budget"
    MP_RC=124
    return 1
  fi
  MP_SEQ=$((MP_SEQ + 1))
  mp_pidf=$MP_DIR/pid.$MP_SEQ
  mp_hitf=$MP_DIR/hit.$MP_SEQ
  mp_outf=$MP_DIR/out.$MP_SEQ
  # A call made inside $(...) (host_id's helpers) counts in a subshell, so its
  # numbers are not seen here and the next call can reuse them: clear them first.
  rm -f "$mp_pidf" "$mp_hitf" "$mp_outf" </dev/null 2>/dev/null
  (
    mp_i=0
    while [ "$mp_i" -lt "$mp_secs" ]; do
      sleep 1
      mp_i=$((mp_i + 1))
    done
    mp_p=
    [ -r "$mp_pidf" ] && read -r mp_p <"$mp_pidf"
    case $mp_p in
      ''|*[!0-9]*) exit 0 ;;
    esac
    : >"$mp_hitf"
    kill -TERM "$mp_p"
    sleep 1
    kill -KILL "$mp_p"
  ) >/dev/null 2>&1 </dev/null &
  mp_wd=$!
  # ulimit -f counts 512-byte blocks in dash and bash --posix (128 = 64 KiB) but 1024-byte
  # blocks in plain bash (128 = 128 KiB): the cap is 64 to 128 KiB depending on the shell.
  /bin/sh -c 'echo $$ >"$0"; ulimit -f 128; exec "$@"' "$mp_pidf" "$@" </dev/null >"$mp_outf" 2>/dev/null
  MP_RC=$?
  kill "$mp_wd" 2>/dev/null
  wait "$mp_wd" 2>/dev/null
  if [ -e "$mp_hitf" ]; then
    MP_SPENT=$((MP_SPENT + mp_secs))
    MP_RC=124
    mp_err "$mp_label-timeout"
  fi
  mp_slurp "$mp_outf"
  [ "$MP_RC" -eq 0 ]
}

# host_id (mozart-lib-host.sh) runs its helpers through mz_cmd; route them through
# the same watchdog.
mz_cmd() {
  if mp_run "$1" "$@"; then
    printf '%s' "$MP_OUT"
  fi
}

# --- escaping ----------------------------------------------------------------

mp_ord() { # mp_ord <char>: MP_ORD = its byte value, 0 to 255
  MP_ORD=$(printf '%d' "'$1")
  [ "$MP_ORD" -ge 0 ] || MP_ORD=$((MP_ORD + 256))
}

mp_u4() { # mp_u4 <number>: prints a JSON \uXXXX escape
  printf '\\u%04x' "$1"
}

# mp_json_str <string>: MP_J = a JSON string literal made only of printable ASCII.
# Control bytes and non-ASCII are written as \u escapes (UTF-8 decoded by hand;
# a malformed sequence becomes U+FFFD), so the output is valid JSON whatever a
# tool printed.
mp_json_str() {
  case $1 in
    *[!A-Za-z0-9\ ._/:@=+,\(\)-]*) ;;
    *)
      MP_J=\"$1\"
      return 0
      ;;
  esac
  mp_in=$1
  mp_o=
  while [ -n "$mp_in" ]; do
    mp_ch=${mp_in%"${mp_in#?}"}
    mp_in=${mp_in#?}
    case $mp_ch in
      \") mp_o=$mp_o'\"' ;;
      \\) mp_o=$mp_o'\\' ;;
      "$MP_TAB") mp_o=$mp_o'\t' ;;
      "$MP_NL") mp_o=$mp_o'\n' ;;
      "$MP_CR") mp_o=$mp_o'\r' ;;
      [\ -~]) mp_o=$mp_o$mp_ch ;;
      *)
        mp_ord "$mp_ch"
        mp_b=$MP_ORD
        if [ "$mp_b" -lt 32 ] || [ "$mp_b" -eq 127 ]; then
          mp_o=$mp_o$(mp_u4 "$mp_b")
          continue
        fi
        if [ "$mp_b" -ge 194 ] && [ "$mp_b" -le 223 ]; then
          mp_need=1
          mp_cp=$((mp_b - 192))
        elif [ "$mp_b" -ge 224 ] && [ "$mp_b" -le 239 ]; then
          mp_need=2
          mp_cp=$((mp_b - 224))
        elif [ "$mp_b" -ge 240 ] && [ "$mp_b" -le 244 ]; then
          mp_need=3
          mp_cp=$((mp_b - 240))
        else
          mp_o=$mp_o'�'
          continue
        fi
        mp_ok=1
        mp_k=0
        while [ "$mp_k" -lt "$mp_need" ]; do
          mp_nx=${mp_in%"${mp_in#?}"}
          if [ -z "$mp_nx" ]; then
            mp_ok=0
            break
          fi
          mp_ord "$mp_nx"
          if [ "$MP_ORD" -ge 128 ] && [ "$MP_ORD" -le 191 ]; then
            mp_cp=$((mp_cp * 64 + MP_ORD - 128))
            mp_in=${mp_in#?}
          else
            mp_ok=0
            break
          fi
          mp_k=$((mp_k + 1))
        done
        if [ "$mp_ok" -eq 1 ]; then
          if [ "$mp_need" -eq 2 ] && { [ "$mp_cp" -lt 2048 ] || { [ "$mp_cp" -ge 55296 ] && [ "$mp_cp" -le 57343 ]; }; }; then
            mp_ok=0
          elif [ "$mp_need" -eq 3 ] && { [ "$mp_cp" -lt 65536 ] || [ "$mp_cp" -gt 1114111 ]; }; then
            mp_ok=0
          fi
        fi
        if [ "$mp_ok" -ne 1 ]; then
          mp_o=$mp_o'�'
        elif [ "$mp_cp" -le 65535 ]; then
          mp_o=$mp_o$(mp_u4 "$mp_cp")
        else
          mp_cp=$((mp_cp - 65536))
          mp_o=$mp_o$(mp_u4 $((55296 + mp_cp / 1024)))$(mp_u4 $((56320 + mp_cp % 1024)))
        fi
        ;;
    esac
  done
  MP_J=\"$mp_o\"
}

mp_lower() { # mp_lower <string>: MP_LC = the string with A-Z folded to a-z
  mp_in=$1
  MP_LC=
  while [ -n "$mp_in" ]; do
    mp_ch=${mp_in%"${mp_in#?}"}
    mp_in=${mp_in#?}
    case $mp_ch in
      A) mp_ch=a ;; B) mp_ch=b ;; C) mp_ch=c ;; D) mp_ch=d ;; E) mp_ch=e ;; F) mp_ch=f ;; G) mp_ch=g ;;
      H) mp_ch=h ;; I) mp_ch=i ;; J) mp_ch=j ;; K) mp_ch=k ;; L) mp_ch=l ;; M) mp_ch=m ;; N) mp_ch=n ;;
      O) mp_ch=o ;; P) mp_ch=p ;; Q) mp_ch=q ;; R) mp_ch=r ;; S) mp_ch=s ;; T) mp_ch=t ;; U) mp_ch=u ;;
      V) mp_ch=v ;; W) mp_ch=w ;; X) mp_ch=x ;; Y) mp_ch=y ;; Z) mp_ch=z ;;
    esac
    MP_LC=$MP_LC$mp_ch
  done
}

# --- fact setters ------------------------------------------------------------

mp_set() { # mp_set <key> <raw JSON token>
  eval "F_$1=\$2"
}

mp_set_str() { # mp_set_str <key> <string>: a JSON string, or null when empty
  if [ -n "$2" ]; then
    mp_json_str "$2"
    mp_set "$1" "$MP_J"
  fi
}

mp_first_line() { # mp_first_line: MP_FIRST = the first line of MP_OUT
  MP_FIRST=${MP_OUT%%"$MP_NL"*}
}

mp_version_ok() { # succeeds when $1 satisfies the version grammar in mozart-schemas.json
  case $1 in
    ''|[!0-9]*|*[!0-9A-Za-z._+-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# mp_version <label>: MP_VER = the first version-shaped word on the first line of
# MP_OUT, else empty and a <label>-unparsable error.
mp_version() {
  MP_VER=
  mp_first_line
  for mp_tok in $MP_FIRST; do
    mp_tok=${mp_tok#v}
    mp_tok=${mp_tok%,}
    if mp_version_ok "$mp_tok"; then
      MP_VER=$mp_tok
      return 0
    fi
  done
  mp_err "$1-unparsable"
  return 1
}

# mp_tool_ver <key> <cmd> [args]: the fact <key> is the tool's version, or null.
mp_tool_ver() {
  mp_key=$1
  shift
  if mp_run "$mp_key" "$@"; then
    if mp_version "$mp_key"; then
      mp_set_str "$mp_key" "$MP_VER"
    fi
  elif [ "$MP_RC" -ne 127 ] && [ "$MP_RC" -ne 124 ]; then
    mp_err "$mp_key-failed"
  fi
}

# JSON has no leading zeros, and shell arithmetic reads them as octal, so a number
# a tool prints with one ("0008") is rejected, never emitted or passed on.
mp_digits() { # succeeds when $1 is a canonical non-negative integer: digits, no leading zero
  case $1 in
    ''|*[!0-9]*|0[0-9]*) return 1 ;;
  esac
}

mp_decimal() { # succeeds when $1 is a canonical integer part and at most one fraction, e.g. 0.50
  case $1 in
    ''|.*|*.|*[!0-9.]*|*.*.*|0[0-9]*) return 1 ;;
  esac
}

mp_set_mem_kb() { # mp_set_mem_kb <kilobytes>: mem_gb in tenths of a GiB, rounded down
  mp_digits "$1" || return 1
  [ "${#1}" -le 12 ] || return 1
  mp_t=$(($1 * 10 / 1048576))
  if [ "$mp_t" -lt 10 ]; then
    mp_set mem_gb "0.$mp_t"
  else
    mp_set mem_gb "${mp_t%?}.${mp_t#"${mp_t%?}"}"
  fi
}

# --- platform ----------------------------------------------------------------

MP_OS=
MP_ARCH=
if mp_run uname uname -s; then
  mp_first_line
  mp_lower "$MP_FIRST"
  case $MP_LC in
    ''|*[!a-z0-9._-]*) mp_err os-unparsable ;;
    *)
      if [ "${#MP_LC}" -le 32 ]; then
        MP_OS=$MP_LC
        mp_set_str os "$MP_OS"
      else
        mp_err os-unparsable
      fi
      ;;
  esac
elif [ "$MP_RC" -eq 127 ]; then
  mp_err uname-missing
fi

if mp_run uname uname -m; then
  mp_first_line
  mp_lower "$MP_FIRST"
  [ "$MP_LC" != aarch64 ] || MP_LC=arm64
  case $MP_LC in
    ''|*[!a-z0-9_]*) mp_err arch-unparsable ;;
    *)
      if [ "${#MP_LC}" -le 32 ]; then
        MP_ARCH=$MP_LC
        mp_set_str arch "$MP_ARCH"
      fi
      ;;
  esac
fi

case $MP_OS in
  darwin)
    if mp_run sw_vers sw_vers -productVersion; then
      mp_first_line
      mp_version_ok "$MP_FIRST" && mp_set_str os_version "$MP_FIRST" || mp_err os_version-unparsable
    fi
    if mp_run sysctl sysctl -n hw.ncpu; then
      mp_first_line
      if mp_digits "$MP_FIRST" && [ "${#MP_FIRST}" -le 4 ] && [ "$MP_FIRST" -ge 1 ]; then
        mp_set cpus "$MP_FIRST"
      else
        mp_err cpus-unparsable
      fi
    fi
    if mp_run sysctl sysctl -n hw.memsize; then
      mp_first_line
      if mp_digits "$MP_FIRST" && [ "${#MP_FIRST}" -le 15 ]; then
        mp_set_mem_kb $((MP_FIRST / 1024)) || mp_err mem_gb-unparsable
      else
        mp_err mem_gb-unparsable
      fi
    fi
    if mp_run sysctl sysctl -n vm.loadavg; then
      for mp_tok in $MP_OUT; do
        case $mp_tok in '{'|'}') continue ;; esac
        if mp_decimal "$mp_tok"; then mp_set load "$mp_tok"; else mp_err load-unparsable; fi
        break
      done
    fi
    ;;
  *)
    mp_ver=
    if [ "$MP_OS" = linux ] && [ -r /etc/os-release ]; then
      while IFS= read -r mp_l; do
        case $mp_l in
          VERSION_ID=*)
            mp_ver=${mp_l#VERSION_ID=}
            mp_ver=${mp_ver#\"}
            mp_ver=${mp_ver%\"}
            break
            ;;
        esac
      done </etc/os-release
    fi
    if [ -z "$mp_ver" ] && [ -n "$MP_OS" ] && mp_run uname uname -r; then
      mp_first_line
      mp_ver=$MP_FIRST
    fi
    if [ -n "$mp_ver" ]; then
      mp_version_ok "$mp_ver" && mp_set_str os_version "$mp_ver" || mp_err os_version-unparsable
    fi
    mp_cpus=
    if [ -n "$MP_OS" ]; then
      if mp_run getconf getconf _NPROCESSORS_ONLN; then
        mp_first_line
        mp_cpus=$MP_FIRST
      elif mp_run nproc nproc; then
        mp_first_line
        mp_cpus=$MP_FIRST
      fi
    fi
    if [ -z "$mp_cpus" ] && [ "$MP_OS" = linux ] && [ -r /proc/cpuinfo ]; then # linux-only
      mp_n=0
      while IFS= read -r mp_l; do
        case $mp_l in processor*) mp_n=$((mp_n + 1)) ;; esac
      done </proc/cpuinfo # linux-only
      mp_cpus=$mp_n
    fi
    if [ -n "$mp_cpus" ]; then
      if mp_digits "$mp_cpus" && [ "${#mp_cpus}" -le 4 ] && [ "$mp_cpus" -ge 1 ]; then
        mp_set cpus "$mp_cpus"
      else
        mp_err cpus-unparsable
      fi
    fi
    if [ "$MP_OS" = linux ] && [ -r /proc/meminfo ]; then # linux-only
      while read -r mp_k mp_v mp_u; do
        if [ "$mp_k" = "MemTotal:" ]; then
          mp_set_mem_kb "$mp_v" || mp_err mem_gb-unparsable
          break
        fi
      done </proc/meminfo # linux-only
    fi
    if [ "$MP_OS" = linux ] && [ -r /proc/loadavg ]; then # linux-only
      read -r mp_v mp_rest </proc/loadavg # linux-only
      if mp_decimal "$mp_v"; then mp_set load "$mp_v"; else mp_err load-unparsable; fi
    fi
    ;;
esac

mp_hid=$(host_id)
if [ -n "$mp_hid" ]; then
  mp_set_str host_id "$mp_hid"
else
  mp_err host_id-unavailable
fi

# --- toolchains --------------------------------------------------------------

# On macOS /usr/bin/git, /usr/bin/python3 and xcodebuild are xcode-select shims:
# run without developer tools installed, they open an install dialog. They are
# probed only when `xcode-select -p` succeeds.
MP_XC_RC=127
if [ "$MP_OS" = darwin ]; then
  mp_run xcode-select xcode-select -p
  MP_XC_RC=$MP_RC
fi
mp_shim_ok() { # mp_shim_ok <tool>: succeeds unless <tool> is a shim and the developer tools are absent
  [ "$MP_OS" = darwin ] || return 0
  case $MP_XC_RC in 0|127) return 0 ;; esac
  # The shim is /usr/bin/<tool> however it is reached (PATH spelling, a symlink to it):
  # compare the files, not the strings. -ef (same file) is not in POSIX test but dash,
  # bash, ksh and busybox all have it.
  [ -x "/usr/bin/$1" ] || return 0
  mp_found=$(command -v "$1") || return 0
  [ "$mp_found" -ef "/usr/bin/$1" ] && return 1
  return 0
}

if [ "$MP_OS" != darwin ] || [ "$MP_XC_RC" -eq 0 ]; then
  mp_tool_ver xcodebuild xcodebuild -version
fi
mp_shim_ok git && mp_tool_ver git git --version
mp_shim_ok python3 && mp_tool_ver python3 python3 --version
mp_tool_ver node node --version
mp_tool_ver docker docker --version
mp_tool_ver adb adb version
mp_tool_ver codex codex --version

set +f
for mp_root in "${ANDROID_HOME-}" "${ANDROID_SDK_ROOT-}" "${HOME-}/Library/Android/sdk" "${HOME-}/Android/Sdk"; do
  [ -d "$mp_root/platforms" ] || continue
  mp_api=
  for mp_d in "$mp_root"/platforms/android-*; do
    mp_n=${mp_d##*/android-}
    case $mp_n in
      ''|*[!0-9]*) continue ;;
    esac
    if mp_digits "$mp_n" && [ "${#mp_n}" -le 3 ]; then
      if [ -z "$mp_api" ] || [ "$mp_n" -gt "$mp_api" ]; then
        mp_api=$mp_n
      fi
    else
      mp_err android_sdk-unparsable
    fi
  done
  [ -z "$mp_api" ] || mp_set android_sdk "$mp_api"
  break
done
set -f

if mp_run kubectl kubectl config get-contexts -o name; then
  mp_list=
  mp_count=0
  mp_rest=$MP_OUT
  while [ -n "$mp_rest" ] && [ "$mp_count" -lt 64 ]; do
    mp_line=${mp_rest%%"$MP_NL"*}
    case $mp_rest in
      *"$MP_NL"*) mp_rest=${mp_rest#*"$MP_NL"} ;;
      *) mp_rest= ;;
    esac
    mp_line=${mp_line%"$MP_CR"}
    [ -n "$mp_line" ] || continue
    mp_line=$(printf '%.253s' "$mp_line")
    mp_json_str "$mp_line"
    mp_list=$mp_list${mp_list:+,}$MP_J
    mp_count=$((mp_count + 1))
  done
  mp_set kube_contexts "[$mp_list]"
elif [ "$MP_RC" -ne 127 ] && [ "$MP_RC" -ne 124 ]; then
  mp_err kubectl-failed
fi

# --- GPU ---------------------------------------------------------------------

if [ "$MP_OS" = darwin ] && [ "$MP_ARCH" = arm64 ]; then
  mp_set_str gpu apple
  if mp_run sysctl sysctl -n machdep.cpu.brand_string; then
    mp_first_line
    mp_set_str gpu_name "$(printf '%.120s' "$MP_FIRST")"
  fi
elif mp_run nvidia-smi nvidia-smi --query-gpu=name --format=csv,noheader; then
  mp_first_line
  if [ -n "$MP_FIRST" ]; then
    mp_set_str gpu nvidia
    mp_set_str gpu_name "$(printf '%.120s' "$MP_FIRST")"
  fi
elif [ "$MP_RC" -ne 127 ] && [ "$MP_RC" -ne 124 ]; then
  mp_err nvidia-smi-failed
fi

# --- claude ------------------------------------------------------------------

mp_tool_ver claude claude --version
if mp_run claude claude --help; then
  mp_hits=" "
  mp_rest=$MP_OUT
  while [ -n "$mp_rest" ]; do
    mp_line=${mp_rest%%"$MP_NL"*}
    case $mp_rest in
      *"$MP_NL"*) mp_rest=${mp_rest#*"$MP_NL"} ;;
      *) mp_rest= ;;
    esac
    for mp_f in $MP_CLAUDE_FLAGS; do
      case "$mp_line" in
        *"$mp_f "*|*"$mp_f,"*|*"$mp_f$MP_TAB"*|*"$mp_f<"*|*"$mp_f["*|*"$mp_f="*|*"$mp_f")
          case $mp_hits in *" $mp_f "*) ;; *) mp_hits="$mp_hits$mp_f " ;; esac
          ;;
      esac
    done
  done
  mp_list=
  for mp_f in $MP_CLAUDE_FLAGS; do
    case $mp_hits in
      *" $mp_f "*) mp_json_str "$mp_f"; mp_list=$mp_list${mp_list:+,}$MP_J ;;
    esac
  done
  mp_set claude_flags "[$mp_list]"
elif [ "$MP_RC" -ne 127 ] && [ "$MP_RC" -ne 124 ]; then
  mp_err claude-failed
fi

# --- mozart install ----------------------------------------------------------

# mozart_command and mozart_child_mode describe the ONE install a headless
# `claude -p "/mozart ..."` would load: user scope (~/.claude) first, otherwise the
# newest plugin-cache version (found with find, six levels deep at most, and only
# when user scope has no command). mozart_command: that install has commands/mozart.md.
# mozart_child_mode: it also ships agents/DISPATCH.md and its command mentions the
# child marker. Both are ADVISORY and self-reported by files on the host: they decide
# whether a launch is worth attempting, never whether it is allowed. An older cache
# version with the marker does not make a newer one without it capable.
mp_ver_gt() { # succeeds when dotted version $1 is newer than $2 (leading digits of each field; none counts as 0)
  mp_a=$1
  mp_b=$2
  while [ -n "$mp_a" ] || [ -n "$mp_b" ]; do
    mp_fa=${mp_a%%.*}
    mp_fb=${mp_b%%.*}
    case $mp_a in *.*) mp_a=${mp_a#*.} ;; *) mp_a= ;; esac
    case $mp_b in *.*) mp_b=${mp_b#*.} ;; *) mp_b= ;; esac
    mp_fa=${mp_fa%%[!0-9]*}
    mp_fb=${mp_fb%%[!0-9]*}
    mp_fa=${mp_fa:-0}
    mp_fb=${mp_fb:-0}
    [ "${#mp_fa}" -le 9 ] && [ "${#mp_fb}" -le 9 ] || return 1
    [ "$mp_fa" -gt "$mp_fb" ] && return 0
    [ "$mp_fa" -lt "$mp_fb" ] && return 1
  done
  return 1
}

mp_effective=
mp_search_timed_out=
if [ -n "${HOME-}" ]; then
  if [ -f "$HOME/.claude/commands/mozart.md" ]; then
    mp_effective=$HOME/.claude/commands/mozart.md
  elif [ -d "$HOME/.claude/plugins" ]; then
    if mp_run search find "$HOME/.claude/plugins" -maxdepth 6 -name mozart.md -path '*/commands/*'; then
      mp_best=
      mp_rest=$MP_OUT
      while [ -n "$mp_rest" ]; do
        mp_line=${mp_rest%%"$MP_NL"*}
        case $mp_rest in
          *"$MP_NL"*) mp_rest=${mp_rest#*"$MP_NL"} ;;
          *) mp_rest= ;;
        esac
        case $mp_line in
          */commands/mozart.md) ;;
          *) continue ;;
        esac
        [ -f "$mp_line" ] || continue
        mp_vdir=${mp_line%/commands/mozart.md}
        mp_vdir=${mp_vdir##*/}
        if [ -z "$mp_effective" ] || mp_ver_gt "$mp_vdir" "$mp_best"; then
          mp_effective=$mp_line
          mp_best=$mp_vdir
        fi
      done
    elif [ "$MP_RC" -eq 124 ]; then
      mp_search_timed_out=1
    fi
  fi
  if [ -n "$mp_search_timed_out" ]; then
    mp_err search-timeout
  else
    mp_cmd_found=false
    mp_child_found=false
    if [ -n "$mp_effective" ]; then
      mp_cmd_found=true
      if [ -f "${mp_effective%/commands/mozart.md}/agents/DISPATCH.md" ]; then
        mp_n=0
        while IFS= read -r mp_l || [ -n "$mp_l" ]; do
          mp_n=$((mp_n + 1))
          [ "$mp_n" -le 5000 ] || break
          case $mp_l in
            *MOZART_CHILD_SESSION*) mp_child_found=true; break ;;
          esac
        done <"$mp_effective"
      fi
    fi
    mp_set mozart_command "$mp_cmd_found"
    mp_set mozart_child_mode "$mp_child_found"
  fi
fi

# --- session state -----------------------------------------------------------

if [ "$MP_OS" = darwin ] && command -v security >/dev/null 2>&1; then
  if mp_run security security show-keychain-info; then
    mp_set keychain_unlocked true
  elif [ "$MP_RC" -ne 124 ]; then
    mp_set keychain_unlocked false
  fi
fi

if [ "$MP_OS" = linux ] && mp_run id id -un; then
  mp_first_line
  if [ -n "$MP_FIRST" ] && mp_run loginctl loginctl show-user "$MP_FIRST" -p Linger; then
    case $MP_OUT in
      Linger=yes*) mp_set linger true ;;
      Linger=no*) mp_set linger false ;;
    esac
  fi
fi

if mp_run ps ps -o lstart= -p "$$"; then
  mp_first_line
  if [ -n "$MP_FIRST" ]; then mp_set ps_lstart true; else mp_set ps_lstart false; fi
elif [ "$MP_RC" -ne 127 ] && [ "$MP_RC" -ne 124 ]; then
  mp_set ps_lstart false
fi

mp_home=
[ -z "${HOME-}" ] || mp_home=$(cd ~ 2>/dev/null && pwd -P 2>/dev/null)
if [ -n "$mp_home" ]; then
  if mz_arg_ok "$mp_home" && [ "${mp_home#/}" != "$mp_home" ]; then
    mp_set_str remote_home "$mp_home"
  else
    mp_err remote_home-unsupported
  fi
fi

# --- output ------------------------------------------------------------------

MP_BODY=
for mp_k in $MP_KEYS; do
  eval "mp_v=\$F_$mp_k"
  MP_BODY=$MP_BODY${MP_BODY:+,}\"$mp_k\":$mp_v
done

MP_STAMP=null
mp_now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null </dev/null)
case $mp_now in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) MP_STAMP=\"$mp_now\" ;;
esac

mp_list=
mp_rest=$MP_ERRORS
while [ -n "$mp_rest" ]; do
  mp_line=${mp_rest%%"$MP_NL"*}
  mp_rest=${mp_rest#*"$MP_NL"}
  mp_list=$mp_list${mp_list:+,}\"$mp_line\"
done

printf '{%s,"probe_version":%s,"probed_at":%s,"probe_errors":[%s]}\n' "$MP_BODY" "$MP_PROBE_VERSION" "$MP_STAMP" "$mp_list"
exit 0
