#!/usr/bin/env python3
"""check-resources.py - the checker for the multi-host resource scripts.

Not installed with the bundle: it tests the scripts, it is not one of them.
Python 3.9 is the floor (the production interpreter on macOS is the system
/usr/bin/python3), and the checker runs under `python3 -I` and under
`/usr/bin/env -i`, so it takes nothing from the environment it was started in.

Usage:
  python3 -I scripts/check-resources.py [--list] [--timing] [--only GATE[:CASE]]
                                        [--deadline SECONDS]

Output is one line per gate, `PASS  <gate>  <detail>` or `FAIL  <gate>  <detail>`,
which scripts/mozart-contract-gates.sh parses. Exit 0 when every gate passes, 1
when one fails, 2 on a usage error.

Every gate names a mutation. The mutation is applied to a scratch copy of
scripts/ and the gate's case must FAIL against it; a gate whose case still
passes against the mutated copy could not have caught the defect, and fails.
"""

from __future__ import annotations

import argparse
import ast
import calendar
import contextlib
import hashlib
import json
import math
import os
import pwd
import random
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPTS = REPO / "scripts"
STUBS = REPO / "tests" / "resources" / "bin"
GATES_FILE = "mozart-contract-gates.sh"
DEFAULT_DEADLINE_S = 120

# Names are built by concatenation so this file never matches its own scans.
CANARY_NAME = "MOZART_SECRET" + "_CANARY"
CANARY_VALUE = "canary-" + "7f3a9c1e"

STUB_NAMES = [
    "claude", "hook", "ioreg", "kubectl", "nvidia-smi", "readstdin", "security", "sleeper",
    "sw_vers", "sysctl", "uname", "xcode-select", "xcodebuild",
]
UTILITIES = [
    "sleep", "date", "find", "id", "ps", "mktemp", "rm", "cat", "dd", "wc",
    "sha256sum", "shasum", "getconf", "nproc",
]
FIXTURE_FLOOR = 25  # tracked files under tests/resources after phase 2 (the plan's per-phase floor)
REQUIRED_UTILITIES = ["sleep", "date", "find", "mktemp", "rm", "cat", "dd", "wc"]
PROBE_UNDETERMINED = ("load", "probed_at")
SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

STOPPING = threading.Event()  # set when the deadline or a signal ends the run: nothing new may start
LIVE = []  # every spawned process, so a deadline or an error can still reap them
SLOTS = threading.BoundedSemaphore(6)  # processes in flight: cases run in parallel, the machine stays usable


class Deadline(Exception):
    pass


class Result:
    def __init__(self, rc, out, err, secs, timed_out):
        self.rc = rc
        self.out = out
        self.err = err
        self.secs = secs
        self.timed_out = timed_out


def kill_group(proc):
    with contextlib.suppress(ProcessLookupError, PermissionError, OSError):
        os.killpg(proc.pid, signal.SIGKILL)


def run(argv, env, cwd=None, timeout=30, stdin=None):
    """Run argv with a timeout and a closed (or supplied) stdin. Always reaps the group."""
    with SLOTS:
        if STOPPING.is_set():
            raise Deadline()
        start = time.monotonic()
        proc = subprocess.Popen(
            argv, env=env, cwd=cwd, start_new_session=True,
            stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        LIVE.append(proc)
        timed_out = False
        try:
            out, err = proc.communicate(input=stdin, timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_group(proc)
            out, err = proc.communicate()
        finally:
            kill_group(proc)
            with contextlib.suppress(ValueError):
                LIVE.remove(proc)
        return Result(proc.returncode, out, err, time.monotonic() - start, timed_out)


def reap_all():
    drop_hook_scratch()
    for proc in list(LIVE):
        kill_group(proc)
        with contextlib.suppress(Exception):
            proc.wait(timeout=2)
        with contextlib.suppress(ValueError):
            LIVE.remove(proc)


def passwd_home():
    return Path(pwd.getpwuid(os.geteuid()).pw_dir)


def tree_snapshot(root, content=False):
    """{relative path: (type, mode, size, mtime_ns[, sha256])} from lstat alone; None when root is absent.

    Files are never opened unless content=True, which is for scratch trees this checker
    made itself: the real <home>/.mozart may be written by a live mozart, and later holds
    packs, so it is compared by lstat only.
    """
    if not os.path.lexists(root):
        return None
    rows = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames + dirnames):
            path = os.path.join(dirpath, name)
            st = os.lstat(path)
            row = (stat.S_IFMT(st.st_mode), st.st_mode, st.st_size, st.st_mtime_ns)
            if content and stat.S_ISREG(st.st_mode):
                with open(path, "rb") as fh:
                    row += (hashlib.sha256(fh.read()).hexdigest(),)
            rows[os.path.relpath(path, root)] = row
    st = os.lstat(root)
    rows["."] = (stat.S_IFMT(st.st_mode), st.st_mode, 0, st.st_mtime_ns)
    return rows


def snapshot_changes(before, after):
    """Paths that differ between two snapshots (added, removed or changed)."""
    if before is None or after is None:
        return [] if before is after else ["<the tree itself appeared or disappeared>"]
    return sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))


def real_search_path():
    return ":".join(p for p in (os.environ.get("PATH", ""), SYSTEM_PATH) if p)


# --- schema --------------------------------------------------------------------

def load_schema(scripts=SCRIPTS):
    with open(scripts / "mozart-schemas.json", encoding="utf-8") as fh:
        return json.load(fh)


def pattern_for(spec, schema):
    if "grammar" in spec:
        return schema["grammars"][spec["grammar"]]["pattern"]
    return spec.get("pattern")


def check_value(name, value, spec, schema):
    """Validate one probe value against its schema entry; returns problems."""
    if value is None:
        return [] if spec.get("nullable") else [f"{name}: null is not allowed"]
    kind = spec["type"]
    problems = []
    if kind == "bool":
        if type(value) is not bool:
            problems.append(f"{name}: want bool, got {value!r}")
    elif kind == "int":
        if type(value) is not int:
            problems.append(f"{name}: want int, got {value!r}")
    elif kind == "number":
        if type(value) not in (int, float) or (type(value) is float and not math.isfinite(value)):
            problems.append(f"{name}: want number, got {value!r}")
    elif kind == "string":
        if not isinstance(value, str):
            problems.append(f"{name}: want string, got {value!r}")
        else:
            pat = pattern_for(spec, schema)
            if pat and not re.fullmatch(pat, value):
                problems.append(f"{name}: {value!r} does not match {pat}")
            if len(value) > spec.get("maxLength", 10 ** 9):
                problems.append(f"{name}: longer than {spec['maxLength']} characters")
    elif kind == "map":
        if not isinstance(value, dict):
            problems.append(f"{name}: want a name-to-value map, got {value!r}")
        else:
            if len(value) > spec.get("maxProperties", 10 ** 9):
                problems.append(f"{name}: more than {spec['maxProperties']} entries")
            for key, item in value.items():
                problems += check_value(f"{name}.<key>", key, dict(spec["keys"], nullable=False), schema)
                problems += check_value(f"{name}[{key!r}]", item, dict(spec["values"], nullable=False), schema)
    elif kind == "list":
        if not isinstance(value, list):
            problems.append(f"{name}: want list, got {value!r}")
        else:
            if len(value) > spec.get("maxItems", 10 ** 9):
                problems.append(f"{name}: more than {spec['maxItems']} items")
            item = dict(spec.get("items", {}), nullable=False)
            allowed = None
            if "enum_from" in item:
                allowed = schema
                for part in item["enum_from"].split("."):
                    allowed = allowed[part]
            for i, element in enumerate(value):
                problems += check_value(f"{name}[{i}]", element, item, schema)
                if allowed is not None and element not in allowed:
                    problems.append(f"{name}[{i}]: {element!r} is not in {item['enum_from']}")
    if kind in ("int", "number") and type(value) in (int, float) and type(value) is not bool:
        if "min" in spec and value < spec["min"]:
            problems.append(f"{name}: {value} is below {spec['min']}")
        if "max" in spec and value > spec["max"]:
            problems.append(f"{name}: {value} is above {spec['max']}")
    return problems


def validate_probe(doc, schema):
    facts = schema["facts"]
    extra = schema["probe"]["extra_keys"]
    if not isinstance(doc, dict):
        return [f"probe output is {type(doc).__name__}, want an object"]
    problems = []
    want = set(facts) | set(extra)
    if set(doc) != want:
        problems.append(f"keys differ from the schema: {sorted(set(doc) ^ want)}")
    for name, spec in facts.items():
        if name in doc:
            problems += check_value(name, doc[name], spec, schema)
    for name, spec in extra.items():
        if name in doc:
            problems += check_value(name, doc[name], spec, schema)
    if doc.get("probe_version") != schema["probe"]["probe_version"]:
        problems.append(f"probe_version is {doc.get('probe_version')!r}")
    return problems


# --- the probe harness ----------------------------------------------------------

class Env:
    """What a case runs against: the scripts under test and a private scratch tree."""

    def __init__(self, scripts, tmp, schema, shared=None):
        self.scripts = Path(scripts)
        self.tmp = Path(tmp)
        self.schema = schema
        self.notes = []
        self.focus = None  # a mutation control sets this to run only the part of a case that can catch it
        # the scratch counter, toolbox and lock are shared by the clones the cases run on
        self.shared = shared if shared is not None else {"n": 0, "toolbox": None, "lock": threading.Lock()}

    def clone(self):
        return Env(self.scripts, self.tmp, self.schema, self.shared)

    def wants(self, part):
        return self.focus is None or self.focus == part

    def fresh(self, label):
        with self.shared["lock"]:
            self.shared["n"] += 1
            path = self.tmp / f"{label}-{self.shared['n']}"
            path.mkdir()
        return path

    @staticmethod
    def pmap(fn, items):
        """fn over items concurrently, results in order."""
        with ThreadPoolExecutor(max_workers=max(1, len(items))) as pool:
            return list(pool.map(fn, items))

    def stream(self):
        return (self.scripts / "mozart-lib-host.sh").read_bytes() + (self.scripts / "mozart-probe.sh").read_bytes()

    def toolbox(self):
        """Real utilities by symlink, and nothing else: no ssh, git, security, uptime."""
        with self.shared["lock"]:
            if self.shared["toolbox"] is None:
                box = self.tmp / "toolbox"
                box.mkdir()
                found = 0
                for name in UTILITIES:
                    real = shutil.which(name, path=real_search_path())
                    if real:
                        os.symlink(real, box / name)
                        found += 1
                missing = [n for n in REQUIRED_UTILITIES if not (box / n).exists()]
                hashers = [n for n in ("sha256sum", "shasum") if (box / n).exists()]
                if missing or not hashers:
                    raise RuntimeError(f"the stub toolbox lacks {missing or ['sha256sum or shasum']}")
                self.shared["toolbox"] = box
        return self.shared["toolbox"]

    def stub_path(self, front=None):
        parts = ([str(front)] if front else []) + [str(STUBS), str(self.toolbox())]
        return ":".join(parts)

    def real_path(self):
        """The machine's own PATH, with the claude stub in front: the real claude is never run."""
        front = self.fresh("front")
        os.symlink(STUBS / "claude", front / "claude")
        return f"{front}:{real_search_path()}"

    def probe_env(self, path, home, tmpdir, extra=None):
        resolved = shutil.which("claude", path=path)
        if resolved and not os.path.realpath(resolved).startswith(str(STUBS.resolve()) + os.sep):
            raise RuntimeError(f"claude resolves to {resolved}, not to the stub: a check must never run the real one")
        env = {"PATH": path, "HOME": str(home), "TMPDIR": str(tmpdir), CANARY_NAME: CANARY_VALUE}
        env.update(extra or {})
        return env

    def run_probe(self, shell, env, args=(), padding=0, timeout=40):
        stdin = self.stream()
        if padding:
            stdin += b"\n" + b"# padding\n" * (padding // 10)
        argv = list(shell) + ["-s", "--"] + list(args)
        res = run(argv, env=env, timeout=timeout, stdin=stdin)
        doc = None
        if res.out:
            with contextlib.suppress(ValueError):
                doc = json.loads(res.out.decode("utf-8"))
        return res, doc

    def stub_probe(self, extra=None, shell=("/bin/sh",), front=None, args=(), padding=0, home=None):
        home = home or self.fresh("home")
        tmpdir = self.fresh("tmp")
        env = self.probe_env(self.stub_path(front), home, tmpdir, extra)
        res, doc = self.run_probe(shell, env, args=args, padding=padding)
        return res, doc, home, tmpdir


def clean_doc(env, res, doc, label):
    problems = []
    if res.timed_out:
        return [f"{label}: the probe did not finish in time"]
    if res.rc != 0:
        problems.append(f"{label}: exit {res.rc}, the probe always exits 0")
    if doc is None:
        return problems + [f"{label}: output is not JSON: {res.out[:80]!r} stderr {res.err[:120]!r}"]
    if res.out.count(b"\n") != 1 or not res.out.endswith(b"\n"):
        problems.append(f"{label}: output is not exactly one line")
    return problems + [f"{label}: {p}" for p in validate_probe(doc, env.schema)]


def normalised(doc):
    return {k: v for k, v in doc.items() if k not in PROBE_UNDETERMINED}


def shell_kind(path):
    res = run([path, "-c", 'printf %s "${BASH_VERSION-}${ZSH_VERSION-}"'], env={"PATH": SYSTEM_PATH}, timeout=10)
    return "bash" if res.out else "other"


def find_shells():
    """(name, argv, kind) for every POSIX shell available, distinct by real path and flags."""
    seen = set()
    shells = []

    def add(name, argv):
        key = (os.path.realpath(argv[0]), tuple(argv[1:]))
        if key in seen or not os.access(argv[0], os.X_OK):
            return
        seen.add(key)
        shells.append((name, argv, shell_kind(argv[0])))

    for path in ("/bin/dash", "/usr/bin/dash", shutil.which("dash", path=real_search_path())):
        if path:
            add("dash", [path])
    for path in ("/bin/bash", "/usr/bin/bash", shutil.which("bash", path=real_search_path())):
        if path:
            add(f"bash --posix ({path})", [path, "--posix"])
    busybox = shutil.which("busybox", path=real_search_path())
    if busybox:
        add("busybox sh", [busybox, "sh"])
    for name in ("ksh93", "ksh"):
        path = shutil.which(name, path=real_search_path())
        if path:
            add("ksh", [path])
    add("/bin/sh", ["/bin/sh"])
    return shells


def shells_not_installed(shells):
    names = " ".join(n for n, _, _ in shells)
    return [want for want, tag in (("busybox sh", "busybox"), ("ksh93", "ksh"), ("dash", "dash")) if tag not in names]


# --- V37_probe -------------------------------------------------------------------

def case_keys(env):
    """Real PATH, real tools: the key set equals the schema, and os is uname -s."""
    home = env.fresh("home")
    tmpdir = env.fresh("tmp")
    penv = env.probe_env(env.real_path(), home, tmpdir)
    res, doc = env.run_probe(["/bin/sh"], penv)
    problems = clean_doc(env, res, doc, "real PATH")
    if doc is not None:
        facts = set(env.schema["facts"])
        extra = set(env.schema["probe"]["extra_keys"])
        if set(doc) - extra != facts:
            problems.append(f"keys minus the probe extras differ from the facts: {sorted((set(doc) - extra) ^ facts)}")
        if len(extra) != 3:
            problems.append(f"expected 3 probe extras, the schema has {len(extra)}")
        want_os = os.uname().sysname.lower()
        if doc.get("os") != want_os:
            problems.append(f"os is {doc.get('os')!r}, uname -s lowercased is {want_os!r}")
        env.notes.append(f"{len(facts)} facts + {len(extra)} extras, os == {want_os}")
    if res.err:
        problems.append(f"real PATH: stderr is not empty: {res.err[:120]!r}")
    return problems


def case_parse(env):
    """Stub PATH: version, list, flag and escaping parsing."""
    problems = []
    hostile = 'we"ird\\name\ttab \u00e9 \U0001F600 cr\rx ctl\x01 del\x7f ls\u2028 end'
    res, doc, home, _ = env.stub_probe()
    problems += clean_doc(env, res, doc, "stub PATH")
    if doc is None:
        return problems
    want = {
        "os": "darwin", "os_version": "14.5", "arch": "arm64", "cpus": 8, "mem_gb": 16.0,
        "xcodebuild": "16.2", "claude": "2.1.310", "claude_flags": env.schema["probe"]["claude_flags_checked"],
        "gpu": "apple", "gpu_name": "Apple M2 Pro", "load": 0.5,
        "ps_lstart": True if (env.toolbox() / "ps").exists() else None,
        "kube_contexts": {},
        "remote_home": os.path.realpath(home),
        "git": None, "python3": None, "node": None, "docker": None, "adb": None, "codex": None,
        "android_sdk": None, "keychain_unlocked": True, "linger": None,
        "mozart_command": False, "mozart_child_mode": False,
    }
    for key, value in want.items():
        if doc.get(key) != value:
            problems.append(f"stub PATH: {key} is {doc.get(key)!r}, want {value!r}")
    if doc.get("probe_errors") != []:
        problems.append(f"stub PATH: probe_errors is {doc.get('probe_errors')!r}, want []")

    variants = [
        ("memory 15.92 GiB rounds down to one decimal", {"STUB_MEMSIZE": "17093625856"}, "mem_gb", 15.9),
        ("aarch64 is normalised, x86_64 is not", {"STUB_UNAME_M": "x86_64"}, "arch", "x86_64"),
        ("a beta version word is a version", {"STUB_XCODE": "17.0-beta1"}, "xcodebuild", "17.0-beta1"),
        ("a quote or backslash is not a version", {"STUB_XCODE": '16.2"\\'}, "xcodebuild", None),
        ("a missing developer-tools directory skips xcodebuild", {"STUB_XCSELECT": "fail"}, "xcodebuild", None),
        ("a flag that only prefixes a listed one does not count", {"STUB_CLAUDE_FLAGS": "--printer"}, "claude_flags", []),
        ("only listed flags are reported, in schema order", {"STUB_CLAUDE_FLAGS": "--settings --print"}, "claude_flags", ["--print", "--settings"]),
        ("a non-default cpu count is read, not defaulted", {"STUB_NCPU": "12"}, "cpus", 12),
        ("a locked keychain reads false", {"STUB_KEYCHAIN": "locked"}, "keychain_unlocked", False),
        ("the Apple brand string is gpu_name, escaped", {"STUB_CPU_BRAND": 'Apple "M4" \\ Max\t\u00e9'}, "gpu_name", 'Apple "M4" \\ Max\t\u00e9'),
        ("the nvidia-smi branch reports nvidia", {"STUB_UNAME_S": "Linux", "STUB_GPU_NAME": hostile}, "gpu", "nvidia"),
        ("the nvidia-smi name round-trips", {"STUB_UNAME_S": "Linux", "STUB_GPU_NAME": hostile}, "gpu_name", hostile),
        ("a Linux stub is os linux", {"STUB_UNAME_S": "Linux"}, "os", "linux"),
    ]
    bad = b"bad\xff\xc3(name"
    variants.append(("malformed UTF-8 in a gpu name", {"STUB_UNAME_S": "Linux", "STUB_GPU_NAME": bad}, "gpu_name", "bad\ufffd\ufffd(name"))
    variants.append(("control characters, U+2028 and CR in a gpu name survive as escapes", {"STUB_UNAME_S": "Linux", "STUB_GPU_NAME": "a\r\x01\x7f\u2028z"}, "gpu_name", "a\r\x01\x7f\u2028z"))
    runs = env.pmap(lambda v: env.stub_probe(v[1]), variants)
    for (label, _, key, value), (_, doc, _, _) in zip(variants, runs):
        got = None if doc is None else doc.get(key)
        if got != value:
            problems.append(f"{label}: {key} is {got!r}, want {value!r}")
    env.notes.append("version, flag and escape parsing (hostile text on gpu_name)")
    return problems


KUBE_CANARY = "canary-ctx-9f31"
KUBE_ARN = "arn:x:eks:r1:111122223333:cluster/prod"


def case_kube(env):
    """kube_contexts is a per-request name -> bool map: no name is ever printed unasked, requested
    names get the right answer, and a hostile or surplus name is dropped before it is used."""
    problems = []
    known = f"{KUBE_CANARY}\n{KUBE_ARN}\nother-ctx"
    hostile = ["x;touch PWNED", "$(touch PWNED)", "`touch PWNED`", "-oFoo", "a b", "a\nb", "", "\u00e9", "a" * 254, "../x", "x'y", 'x"y', "x\\y"]
    many = [f"ctx-{i:02d}" for i in range(17)]
    runs = env.pmap(lambda a: env.stub_probe({"STUB_KUBE_CONTEXTS": known}, args=a), [
        (),
        sum((["--kube-context", n] for n in (KUBE_CANARY, KUBE_ARN, "absent-ctx", KUBE_CANARY)), []),
        sum((["--kube-context", n] for n in hostile + ["good-ctx"]), []),
        sum((["--kube-context", n] for n in many), []),
    ])
    (r0, d0, _, _), (r1, d1, _, _), (r2, d2, _, _), (r3, d3, _, _) = runs
    for label, res, doc in (("no names", r0, d0), ("names", r1, d1), ("hostile names", r2, d2), ("17 names", r3, d3)):
        problems += clean_doc(env, res, doc, label)
    if d0 is not None:
        if d0.get("kube_contexts") != {}:
            problems.append(f"with no names requested kube_contexts is {d0.get('kube_contexts')!r}, want {{}}")
        if KUBE_CANARY.encode() in r0.out or KUBE_ARN.encode() in r0.out or b"other-ctx" in r0.out:
            problems.append("a kubectl context name appears in the output although none was requested")
    if d1 is not None and d1.get("kube_contexts") != {KUBE_CANARY: True, KUBE_ARN: True, "absent-ctx": False}:
        problems.append(f"requested names answered {d1.get('kube_contexts')!r}")
    if d1 is not None and b"other-ctx" in r1.out:
        problems.append("a context nobody asked about was printed")
    if d2 is not None:
        if d2.get("kube_contexts") != {"good-ctx": False}:
            problems.append(f"hostile requested names were not all dropped: {d2.get('kube_contexts')!r}")
        if "kube_context-rejected" not in d2.get("probe_errors", []):
            problems.append("a rejected name is not recorded as kube_context-rejected")
        if any(h and h.encode() in r2.out for h in hostile if len(h) > 3 and h != "a b"):
            problems.append("a rejected name was echoed into the output")
    if d3 is not None:
        if len(d3.get("kube_contexts") or {}) != 16 or "kube_context-capped" not in d3.get("probe_errors", []):
            problems.append(f"17 requested names: {len(d3.get('kube_contexts') or {})} answered, errors {d3.get('probe_errors')}")
    env.notes.append("kube_contexts is membership only: {} unasked, true/false asked, hostile and surplus names dropped")
    return problems


def case_empty_path(env):
    """sh run by absolute path with an empty PATH: every tool fact is null, still valid JSON."""
    home = env.fresh("home")
    tmpdir = env.fresh("tmp")
    penv = env.probe_env("", home, tmpdir)
    res, doc = env.run_probe(["/bin/sh"], penv)
    problems = clean_doc(env, res, doc, "empty PATH")
    if doc is not None:
        tool_facts = [
            "os", "arch", "host_id", "xcodebuild", "adb", "docker", "gpu", "gpu_name", "kube_contexts",
            "claude", "claude_flags", "codex", "git", "python3", "node", "keychain_unlocked", "linger", "ps_lstart",
        ]
        for key in tool_facts:
            if doc.get(key) is not None:
                problems.append(f"empty PATH: {key} is {doc.get(key)!r}, want null")
        if "uname-missing" not in doc.get("probe_errors", []):
            problems.append("empty PATH: probe_errors does not record uname-missing")
    return problems


def case_darwin(env):
    """The Darwin branch through the stubs: host_id is the digest of the stub UUID."""
    problems = []
    uuid = "11111111-2222-3333-4444-555555555555"
    (_, doc, _, _), (_, doc_none, _, _) = env.pmap(env.stub_probe, [{"STUB_IOREG_UUID": uuid}, {"STUB_IOREG_UUID": "none"}])
    want = hashlib.sha256(uuid.encode()).hexdigest()
    if doc is None or doc.get("host_id") != want:
        problems.append(f"Darwin host_id is {None if doc is None else doc.get('host_id')!r}, want sha256 of the stub UUID")
    doc = doc_none
    if doc is None or doc.get("host_id") is not None or "host_id-unavailable" not in doc.get("probe_errors", []):
        problems.append("no machine-id source: host_id must be null with a host_id-unavailable error")
    env.notes.append("host_id = sha256 of the stub UUID, null without a source")
    return problems


def tree_files(root):
    return sorted(str(p.relative_to(root)) for p in Path(root).rglob("*"))


def case_determinism(env):
    """Deterministic under a stub PATH, no canary, HOME untouched, nothing left in TMPDIR."""
    problems = []
    home = env.fresh("home")
    (home / ".claude").mkdir()
    (home / ".claude" / "settings.json").write_text("{}\n")
    before = tree_snapshot(home, content=True)
    (res1, doc1, _, tmp1), (res2, doc2, _, tmp2) = env.pmap(lambda _: env.stub_probe(home=home), [0, 1])
    if doc1 is None or doc2 is None:
        return ["determinism: a run produced no JSON"]
    if normalised(doc1) != normalised(doc2):
        problems.append("two runs under the same stub PATH differ outside load and probed_at")
    for res in (res1, res2):
        if CANARY_VALUE.encode() in res.out + res.err:
            problems.append("the secret canary in the environment appears in the probe's output")
    changed = snapshot_changes(before, tree_snapshot(home, content=True))
    if changed:
        problems.append(f"HOME is not byte- and stat-identical after the probe: {changed[:3]}")
    for tmp in (tmp1, tmp2):
        left = tree_files(tmp)
        if left:
            problems.append(f"the probe left files in TMPDIR: {left[:3]}")
    return problems


def case_timeouts(env):
    """A hanging tool, a stdin-reading tool and a plugin-cache search are bounded, and the total budget
    is honoured. Where the check is about behaviour, the limits are generous (a busy machine must not
    turn a timeout into a skipped command); only the budget scenario uses a tight total."""
    problems = []
    front = env.fresh("front")
    os.symlink(STUBS / "sleeper", front / "nvidia-smi")
    os.symlink(STUBS / "readstdin", front / "docker")
    record = env.fresh("rec") / "record"
    extra = {"STUB_UNAME_S": "Linux", "STUB_SLEEP": "60", "STUB_RECORD": str(record)}
    find_front = env.fresh("front")
    os.symlink(STUBS / "sleeper", find_front / "find")
    search_home = env.fresh("home")
    (search_home / ".claude" / "plugins").mkdir(parents=True)
    budget_front = env.fresh("front")
    os.symlink(STUBS / "sleeper", budget_front / "nvidia-smi")
    generous = ("--sub-timeout", "2", "--total-timeout", "90")

    def scenario(which):
        if which == "tool":
            return env.stub_probe(extra, front=front, args=generous, padding=262144)
        if which == "search":
            return env.stub_probe({"STUB_SLEEP": "60"}, front=find_front, args=generous, home=search_home)
        return env.stub_probe(dict(extra, STUB_RECORD="/dev/null"), front=budget_front, args=("--total-timeout", "1"))

    (res, doc, _, _), (_, search_doc, _, _), (bres, bdoc, _, _) = env.pmap(scenario, ["tool", "search", "budget"])
    problems += clean_doc(env, res, doc, "hung tool")
    if res.secs > 45:
        problems.append(f"the probe took {res.secs:.1f}s with --sub-timeout 2 and a 60s sleeper")
    lines = record.read_text().splitlines() if record.exists() else []
    if "sleeper-started" not in lines:
        problems.append("the sleeper stub never ran, so the timeout was not exercised")
    reads = [ln for ln in lines if ln.startswith("stdin-bytes=")]
    if reads != ["stdin-bytes=0"]:
        problems.append(f"a tool read the probe's stdin (the script itself arrives there): {reads}")
    if doc is not None:
        errors = doc.get("probe_errors", [])
        if "nvidia-smi-timeout" not in errors:
            problems.append(f"the hung tool was not recorded as nvidia-smi-timeout: {errors}")
        if "docker-timeout" in errors:
            problems.append("the stdin-reading tool timed out instead of seeing a closed stdin")
        if doc.get("gpu") is not None:
            problems.append(f"gpu is {doc.get('gpu')!r} after a timeout, want null")
    if search_doc is None or "search-timeout" not in search_doc.get("probe_errors", []):
        problems.append("a hung plugin-cache search is not recorded as search-timeout")
    elif search_doc.get("mozart_command") is not None or search_doc.get("mozart_child_mode") is not None:
        problems.append("a timed-out search with nothing found must leave the mozart facts null")
    problems += clean_doc(env, bres, bdoc, "total budget")
    if bres.secs > 30:
        problems.append(f"--total-timeout 1 took {bres.secs:.1f}s")
    if bdoc is not None and not any(e.endswith(("-budget", "-timeout")) for e in bdoc.get("probe_errors", [])):
        problems.append(f"a spent total budget skipped or killed nothing: {bdoc.get('probe_errors')}")
    env.notes.append("hung and stdin-reading tools bounded")
    return problems


def case_agreement(env):
    """host_id equals the library's; remote_home is absolute or null; the argument grammar agrees."""
    problems = []
    lib = env.scripts / "mozart-lib-host.sh"
    for label, extra in (("stub", {"STUB_IOREG_UUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}), ("real", None)):
        home = env.fresh("home")
        tmpdir = env.fresh("tmp")
        path = env.stub_path() if label == "stub" else env.real_path()
        penv = env.probe_env(path, home, tmpdir, extra)
        res, doc = env.run_probe(["/bin/sh"], penv)
        lib_res = run(["/bin/sh", "-c", f'. "{lib}"; host_id'], env=penv, timeout=20)
        want = lib_res.out.decode().strip() or None
        if doc is None or doc.get("host_id") != want:
            problems.append(f"{label}: probe host_id {None if doc is None else doc.get('host_id')!r} differs from lib-host.sh's {want!r}")
        if label == "real" and want is None:
            env.notes.append("real host has no machine identifier (host_id null on both sides)")

    spaced = env.fresh("home with space")
    res, doc, _, _ = env.stub_probe(home=spaced)
    if doc is None or doc.get("remote_home") is not None or "remote_home-unsupported" not in doc.get("probe_errors", []):
        problems.append("a home path with a space must give remote_home null and remote_home-unsupported")
    res, doc, _, _ = env.stub_probe(extra={"HOME": ""})
    if doc is None or doc.get("remote_home") is not None:
        problems.append("an empty HOME must give remote_home null")

    grammar = env.schema["grammars"]["arg"]
    rng = random.Random(20261025)
    alphabet = "abcXYZ019._/- ;$*\n\u00e9'\"\\"
    samples = ["", "a", ".", "..", "/", "-", "-a", "a-", "a" * 254, "a" * 255, "a" * 256, "a\n", "\na", "a b", "a;b", "\u00e9", "~", "a/b/../c", "--upload-pack=x", "-oProxyCommand=x"]
    samples += ["".join(rng.choice(alphabet) for _ in range(rng.randint(1, 12))) for _ in range(300)]
    for shell in find_shells():
        out = run(
            shell[1] + ["-c", f'. "{lib}"; for s; do if mz_arg_ok "$s"; then echo y; else echo n; fi; done', "sh"] + samples,
            env={"PATH": SYSTEM_PATH}, timeout=40,
        )
        got = out.out.decode().split("\n")[:-1]
        want = ["y" if re.fullmatch(grammar["pattern"], s) and not s.startswith("-") else "n" for s in samples]
        if got != want:
            diff = [repr(s) for s, g, w in zip(samples, got, want) if g != w][:3]
            problems.append(f"{shell[0]}: mz_arg_ok disagrees with the schema grammar on {len(samples)} strings: {diff}")
    name_grammar = env.schema["grammars"]["kube_name"]
    name_samples = samples + ["a" * 253, "a" * 254, "arn:x:y/z", "a@b=c+d,e", "0", ":a", "a:", "a#b", "a\tb"]
    for shell in find_shells():
        out = run(
            shell[1] + ["-c", f'. "{lib}"; for s; do if mz_name_ok "$s"; then echo y; else echo n; fi; done', "sh"] + name_samples,
            env={"PATH": SYSTEM_PATH}, timeout=40,
        )
        got = out.out.decode().split("\n")[:-1]
        want = ["y" if re.fullmatch(name_grammar["pattern"], s) else "n" for s in name_samples]
        if got != want:
            diff = [repr(s) for s, g, w in zip(name_samples, got, want) if g != w][:3]
            problems.append(f"{shell[0]}: mz_name_ok disagrees with the schema grammar: {diff}")
    env.notes.append(f"argument and name grammars agree on {len(samples)} strings")
    return problems


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def case_mozart_search(env):
    """mozart_command and mozart_child_mode: user dirs first, then the plugin cache, six levels deep."""
    marker = "route MOZART" + "_CHILD_SESSION to the dispatch manual\n"
    cache = ".claude/plugins/cache/m/p"
    layouts = [
        ("nothing installed", {}, (False, False)),
        ("a stale older cache version has the marker, the newer one does not",
         {f"{cache}/1.0/commands/mozart.md": marker, f"{cache}/1.0/agents/DISPATCH.md": "x\n",
          f"{cache}/2.0/commands/mozart.md": "# mozart\n", f"{cache}/2.0/agents/DISPATCH.md": "x\n"}, (True, False)),
        ("the newer cache version has the marker, the older one does not",
         {f"{cache}/1.0/commands/mozart.md": "# mozart\n", f"{cache}/1.0/agents/DISPATCH.md": "x\n",
          f"{cache}/2.0/commands/mozart.md": marker, f"{cache}/2.0/agents/DISPATCH.md": "x\n"}, (True, True)),
        ("1.10 is newer than 1.9",
         {f"{cache}/1.9/commands/mozart.md": marker, f"{cache}/1.9/agents/DISPATCH.md": "x\n",
          f"{cache}/1.10/commands/mozart.md": "# mozart\n", f"{cache}/1.10/agents/DISPATCH.md": "x\n"}, (True, False)),
        ("user scope wins over a cache version with the marker",
         {".claude/commands/mozart.md": "# mozart\n", ".claude/agents/DISPATCH.md": "x\n",
          f"{cache}/1.0/commands/mozart.md": marker, f"{cache}/1.0/agents/DISPATCH.md": "x\n"}, (True, False)),
        ("command without the marker", {".claude/commands/mozart.md": "# mozart\n", ".claude/agents/DISPATCH.md": "x\n"}, (True, False)),
        ("command with the marker and DISPATCH", {".claude/commands/mozart.md": marker, ".claude/agents/DISPATCH.md": "x\n"}, (True, True)),
        ("marker without DISPATCH", {".claude/commands/mozart.md": marker}, (True, False)),
        ("plugin cache at depth 6", {".claude/plugins/cache/m/p/1.0/commands/mozart.md": marker, ".claude/plugins/cache/m/p/1.0/agents/DISPATCH.md": "x\n"}, (True, True)),
        ("plugin cache at depth 7", {".claude/plugins/cache/m/p/1.0/x/commands/mozart.md": marker, ".claude/plugins/cache/m/p/1.0/x/agents/DISPATCH.md": "x\n"}, (False, False)),
    ]
    problems = []

    def probe_layout(layout):
        home = env.fresh("home")
        for rel, text in layout[1].items():
            write(home / rel, text)
        return env.stub_probe(home=home)

    for (label, _, want), (_, doc, _, _) in zip(layouts, env.pmap(probe_layout, layouts)):
        got = None if doc is None else (doc.get("mozart_command"), doc.get("mozart_child_mode"))
        if got != want:
            problems.append(f"{label}: (command, child mode) is {got}, want {want}")
    env.notes.append(f"{len(layouts)} install layouts")
    return problems


def case_numbers(env):
    """A tool printing a number with a leading zero is rejected as <fact>-unparsable; the JSON stays valid."""
    problems = []
    sdk = env.fresh("sdk")
    for name in ("android-09", "android-34"):
        (sdk / "platforms" / name).mkdir(parents=True)
    only_zero = env.fresh("sdk")
    (only_zero / "platforms" / "android-009").mkdir(parents=True)
    hostile = {"STUB_NCPU": "0008", "STUB_MEMSIZE": "017179869184", "STUB_LOADAVG": "007.5 1 2"}
    runs = env.pmap(lambda extra: env.stub_probe(extra), [hostile, {"ANDROID_HOME": str(sdk)}, {"ANDROID_HOME": str(only_zero)}])
    (res, doc, _, _), (res2, doc2, _, _), (res3, doc3, _, _) = runs
    problems += clean_doc(env, res, doc, "leading zeros")
    if doc is not None:
        for fact in ("cpus", "mem_gb", "load"):
            if doc.get(fact) is not None:
                problems.append(f"{fact} is {doc.get(fact)!r} after a leading-zero value, want null")
            if f"{fact}-unparsable" not in doc.get("probe_errors", []):
                problems.append(f"{fact}-unparsable is not recorded: {doc.get('probe_errors')}")
    problems += clean_doc(env, res2, doc2, "android-09 beside android-34")
    if doc2 is not None and (doc2.get("android_sdk") != 34 or "android_sdk-unparsable" not in doc2.get("probe_errors", [])):
        problems.append(f"android-09 beside android-34: android_sdk {doc2.get('android_sdk')!r}, errors {doc2.get('probe_errors')}")
    problems += clean_doc(env, res3, doc3, "android-009 alone")
    if doc3 is not None and (doc3.get("android_sdk") is not None or "android_sdk-unparsable" not in doc3.get("probe_errors", [])):
        problems.append(f"android-009 alone: android_sdk {doc3.get('android_sdk')!r}, errors {doc3.get('probe_errors')}")
    env.notes.append("leading-zero numbers rejected")
    return problems


def case_subshell(env):
    """host_id's helpers run in subshells: a helper that times out must not taint a later tool."""
    problems = []
    front = env.fresh("front")
    os.symlink(STUBS / "sleeper", front / "ioreg")
    extra = {"STUB_SLEEP": "30"}
    res, doc, _, _ = env.stub_probe(extra, front=front, args=("--sub-timeout", "1", "--total-timeout", "20"))
    problems += clean_doc(env, res, doc, "hung ioreg")
    if doc is not None:
        errors = doc.get("probe_errors", [])
        if doc.get("host_id") is not None or "host_id-unavailable" not in errors:
            problems.append(f"a hung ioreg must leave host_id null with host_id-unavailable: {doc.get('host_id')!r} {errors}")
        for fact, want in (("claude", "2.1.310"), ("xcodebuild", "16.2"), ("ps_lstart", True)):
            if fact == "ps_lstart" and not (env.toolbox() / "ps").exists():
                continue
            if doc.get(fact) != want:
                problems.append(f"{fact} is {doc.get(fact)!r} after the host_id timeout, want {want!r}")
        misreported = [e for e in errors if e.endswith("-timeout")]
        if misreported:
            problems.append(f"a later tool succeeded but was recorded as a timeout after the host_id timeout: {misreported}")
    env.notes.append("a host_id helper timeout does not taint later tools")
    return problems


def case_android(env):
    """android_sdk is the highest platforms/android-N under ANDROID_HOME."""
    problems = []
    sdk = env.fresh("sdk")
    for name in ("android-9", "android-34", "android-33", "android-ext", "other"):
        (sdk / "platforms" / name).mkdir(parents=True)
    empty = env.fresh("empty")
    (_, doc, _, _), (_, none_doc, _, _) = env.pmap(env.stub_probe, [{"ANDROID_HOME": str(sdk)}, {"ANDROID_HOME": str(empty)}])
    if doc is None or doc.get("android_sdk") != 34:
        problems.append(f"android_sdk is {None if doc is None else doc.get('android_sdk')!r}, want 34")
    doc = none_doc
    if doc is None or doc.get("android_sdk") is not None:
        problems.append("android_sdk must be null when no SDK has platforms/")
    return problems


def git_lines(*args):
    git = shutil.which("git", path=real_search_path())
    if not git:
        return None
    home = tempfile.mkdtemp(prefix="mz-git-")
    try:
        genv = {"PATH": SYSTEM_PATH, "HOME": home, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
        res = run([git, "-C", str(REPO)] + list(args), env=genv, timeout=30)
    finally:
        shutil.rmtree(home, ignore_errors=True)
    return None if res.rc != 0 else res.out.decode("utf-8", "replace").splitlines()


def case_fixtures(env):
    """Fixtures are tracked, the stubs are 100755, and none is a markdown file."""
    problems = []
    on_disk = sorted(p.name for p in STUBS.iterdir()) if STUBS.is_dir() else []
    if on_disk != sorted(STUB_NAMES):
        problems.append(f"tests/resources/bin holds {on_disk}, want {sorted(STUB_NAMES)}")
    for name in on_disk:
        path = STUBS / name
        if not os.access(path, os.X_OK):
            problems.append(f"{name} is not executable")
        elif path.read_bytes()[:10] != b"#!/bin/sh\n":
            problems.append(f"{name} does not start with #!/bin/sh")
    tracked = git_lines("ls-files", "-s", "--", "tests/resources")
    if tracked is None:
        return problems + ["git ls-files failed: the fixtures cannot be shown to be tracked"]
    modes = {row.split("\t", 1)[1]: row.split()[0] for row in tracked}
    if len(modes) < FIXTURE_FLOOR:
        problems.append(f"{len(modes)} tracked fixture(s) under tests/resources, floor {FIXTURE_FLOOR}")
    for name in STUB_NAMES:
        if modes.get(f"tests/resources/bin/{name}") != "100755":
            problems.append(f"tests/resources/bin/{name} is not tracked with mode 100755")
    untracked = git_lines("ls-files", "--others", "--exclude-standard", "--", "tests/resources") or []
    ignored = git_lines("ls-files", "--others", "--ignored", "--exclude-standard", "--", "tests/resources") or []
    if untracked or ignored:
        problems.append(f"untracked or ignored fixture(s), `git add` them (this checker never does): {(untracked + ignored)[:3]}")
    md = [p for p in modes if p.endswith(".md")]
    if md:
        problems.append(f"markdown fixtures would join the markdown gates' population: {md}")
    env.notes.append(f"{len(modes)} tracked fixtures, stubs 100755")
    return problems


def mutate_file(path, old, new):
    text = path.read_text()
    if old not in text:
        raise RuntimeError(f"mutation target not found in {path.name}: {old!r}")
    path.write_text(text.replace(old, new, 1))


def mutation_drop_devnull(scripts):
    mutate_file(scripts / "mozart-probe.sh", '"$@" </dev/null >"$mp_outf"', '"$@" >"$mp_outf"')


def mutation_oldest_install(scripts):
    mutate_file(scripts / "mozart-probe.sh", 'mp_ver_gt "$mp_vdir" "$mp_best"', 'mp_ver_gt "$mp_best" "$mp_vdir"')


def mutation_shared_hit_names(scripts):  # one directory per call, named by a counter that subshells do not share
    mutate_file(scripts / "mozart-probe.sh", 'mp_cd=$(mktemp -d "$MP_DIR/c.XXXXXX" 2>/dev/null </dev/null)', 'mp_cd=$MP_DIR/c.$MP_SEQ; mkdir -p "$mp_cd"')


PLANT_PEP604 = "def f(x: int | None) -> None:\n    return None\n"
PLANT_ZIP = "pairs = list(zip([1], [2], strict=True))\n"


def mutation_plant_pep604(scripts):
    (scripts / "mozart_plant.py").write_text(PLANT_PEP604)


def mutation_plant_zip_strict(scripts):
    (scripts / "mozart_plant.py").write_text(PLANT_ZIP)


# --- V37_shells --------------------------------------------------------------------

def run_everywhere(env, shells):
    """The stub-PATH probe under each shell: [(name, kind, res, doc)]."""
    home = env.fresh("home")
    runs = env.pmap(lambda shell: env.stub_probe(shell=shell[1], home=home), shells)
    return [(name, kind, res, doc) for (name, _, kind), (res, doc, _, _) in zip(shells, runs)]


def watchdog_scenario(env, shells):
    """A command that really times out, after many that finished at once: every watchdog but the one that
    killed something must have done nothing, and the probe's scratch directory must outlive them all."""
    problems = []
    front = env.fresh("front")
    os.symlink(STUBS / "sleeper", front / "codex")

    def watch(shell):
        record = env.fresh("rec") / "spy"
        res, doc, _, tmpdir = env.stub_probe({"STUB_SPY": "1", "STUB_RECORD": str(record), "STUB_SLEEP": "3"}, shell=shell[1], front=front,
                                            args=("--sub-timeout", "1", "--total-timeout", "60"))
        return shell[0], res, doc, record, tmpdir
    for name, res, doc, record, tmpdir in env.pmap(watch, shells):
        seen = record.read_text().split()[-1] if record.exists() and record.read_text().split() else None
        if doc is None:
            problems.append(f"{name}: no JSON from the watchdog scenario: {res.err[:200]!r}")
            continue
        if seen != "1":
            problems.append(f"{name}: a finished watchdog wrote {seen} hit file(s) by the time the probe looked, want 1 (only the command that really timed out)")
        if "codex-timeout" not in doc.get("probe_errors", []) or doc.get("claude") != "2.1.310" or len(doc.get("claude_flags") or []) != 8:
            problems.append(f"{name}: the probe's scratch directory did not survive its watchdogs: claude {doc.get('claude')!r}, errors {doc.get('probe_errors')}")
        if res.err:
            problems.append(f"{name}: stderr is not empty after a watchdog finished: {res.err[:200]!r}")
        if tree_files(tmpdir):
            problems.append(f"{name}: the probe left files in TMPDIR: {tree_files(tmpdir)[:3]}")
    return problems


def case_shells(env):
    shells = find_shells()
    problems = []
    if not shells:
        return ["no POSIX shell found"]
    if env.focus == "watchdog":
        return watchdog_scenario(env, shells[:1])
    results = run_everywhere(env, shells)
    base = None
    for name, kind, res, doc in results:
        problems += clean_doc(env, res, doc, name)
        if res.err:
            problems.append(f"{name}: stderr is not empty: {res.err[:400]!r}")
        if doc is not None:
            if base is None:
                base = (name, normalised(doc))
            elif normalised(doc) != base[1]:
                differing = sorted(k for k in base[1] if base[1][k] != normalised(doc).get(k))
                problems.append(f"{name} differs from {base[0]} in {differing}")
    others = [name for name, _, kind in shells if kind != "bash"]
    if os.environ.get("CI") == "true" and not others:
        problems.append("CI=true and no non-bash shell (dash, busybox) is available to run the probe")
    problems += watchdog_scenario(env, shells)
    skipped = shells_not_installed(shells)
    env.notes.append("identical under " + ", ".join(name for name, _, _ in shells) + (f" (not installed here, skipped: {', '.join(skipped)})" if skipped else ""))
    return problems


def mutation_watchdog_blind(scripts):
    probe = scripts / "mozart-probe.sh"
    mutate_file(probe, 'if [ -e "$mp_donef" ] || [ ! -d "$MP_DIR" ] || ! kill -0 "$MP_PID" 2>/dev/null; then', "if false; then")
    mutate_file(probe, 'if [ -e "$mp_donef" ] || ! kill -0 "$MP_PID" 2>/dev/null || ! kill -0 "$mp_p" 2>/dev/null; then', "if false; then")


def mutation_bashism(scripts):
    mutate_file(scripts / "mozart-probe.sh", "# --- output ---", 'mp_bashism=${MP_OS,,}\n# --- output ---')


# --- V38_portable ------------------------------------------------------------------

# (label, regex over the comment-stripped code of one line, plants that must be flagged).
# A flag is looked for anywhere later in the same simple command (up to | ; &), so
# `sed -e '...' -i f`, `sed '...' -i f`, attached values (`date -d@1`, `stat -c%s`) and
# long spellings (`--date=`, `--format=`) are all caught. xargs is the exception: its
# own options precede the command it runs, and `xargs grep -r` is not `xargs -r`.
DENYLIST = [
    ("readlink -f", r"\breadlink\b[^|;&]*?\s(?:-[A-Za-z]*f|--canonicalize\b)",
     ["readlink -f /x", "readlink -fn /x", "readlink -nf /x", "readlink --canonicalize /x"]),
    ("sed -i", r"\bsed\b[^|;&]*?\s(?:-[A-Za-z]*i|--in-place)",
     ["sed -i s/a/b/ f", "sed -e 's/a/b/' -i f", "sed 's/a/b/' -i f", "sed -ni p f", "sed --in-place=.bak s f", "sed -i'' s f"]),
    ("date -d", r"\bdate\b[^|;&]*?\s(?:-[A-Za-z]*d|--date\b)",
     ["date -d @1", "date -d@1", 'date -d"$x"', "date --date=@1", "date -ud @1"]),
    ("stat -c", r"\bstat\b[^|;&]*?\s(?:-[A-Za-z]*c|--format\b|--printf\b)",
     ["stat -c %s f", "stat -c%s f", "stat -Lc %s f", "stat --format=%s f"]),
    ("timeout ", r"(?<![\w.-])timeout\s", ["timeout 5 cmd", "x | timeout 5 cmd", "/usr/bin/timeout 5 cmd"]),
    ("setsid", r"(?<![\w.-])setsid\b", ["setsid cmd", "x | setsid cmd"]),
    ("flock", r"(?<![\w.-])flock\b", ["flock f cmd", "exec flock -n 9"]),
    ("ps -o etimes", r"\bps\b.*-o\s*etimes", ["ps -o etimes= -p 1", "ps -ax -o etimes -p 1"]),
    ("xargs -r", r"\bxargs\b(?:\s+-\S+(?:\s+[0-9]+)?)*\s+(?:-[A-Za-z]*r|--no-run-if-empty)",
     ["xargs -r echo", "xargs -rn1 echo", "xargs -n 1 -r echo", "xargs --no-run-if-empty echo"]),
    ("sort -V", r"\bsort\b[^|;&]*?\s(?:-[A-Za-z]*V|--version-sort\b)",
     ["sort -V", "sort -uV", "sort --version-sort", "sort -t. -k1 -V"]),
    ("grep -P", r"\bgrep\b[^|;&]*?\s(?:-[A-Za-z]*P|--perl-regexp\b)",
     ["grep -P x", "grep -oP x", "grep --perl-regexp x", "grep -E x -P"]),
    ("declare -A", r"\bdeclare\s+-\S*A", ["declare -A m", "declare -gA m"]),
    ("mapfile", r"(?<![\w.-])(?:mapfile|readarray)\b", ["mapfile -t a", "readarray -t a"]),
    ("${x,,}", r"\$\{[A-Za-z_][A-Za-z0-9_]*(?:,,?|\^\^?)[^}]*\}", ["y=${x,,}", "y=${x^^}", "y=${x,}"]),
    ("wait -n", r"\bwait\s+-n\b", ["wait -n", "wait -n 1"]),
]
DENY_RES = [(label, re.compile(rx)) for label, rx, _ in DENYLIST]
CLEAN_LINES = [
    "readlink x", "sed -n p f", "sed -E 's/a/b/' f", "date -u +%s", "date -u +%Y-%m-%dT%H:%M:%SZ", "stat -f %z f",
    "echo --total-timeout 2", "sort -n -u", "grep -E x", "grep -rn x d", "declare m", "xargs -n 1 grep -r x",
    "xargs -0 -n1 echo", "read -r x # sed -i y",
]
LINUX_ONLY = "# linux-only"


def strip_comment(line):
    """The code part of a shell line: a # starts a comment only outside quotes and not as $# or ${#x}."""
    out = []
    i, n = 0, len(line)
    single = double = False
    while i < n:
        c = line[i]
        if single:
            out.append(c)
            single = c != "'"
        elif double:
            out.append(c)
            if c == "\\" and i + 1 < n:
                i += 1
                out.append(line[i])
            elif c == '"':
                double = False
        elif c == "\\" and i + 1 < n:
            out.append(c)
            i += 1
            out.append(line[i])
        elif c == "'":
            single = True
            out.append(c)
        elif c == '"':
            double = True
            out.append(c)
        elif c == "$" and i + 1 < n and line[i + 1] == "#":
            out.append("$#")
            i += 1
        elif c == "$" and i + 1 < n and line[i + 1] == "{":
            out.append("${")
            i += 1
            if i + 1 < n and line[i + 1] == "#":
                out.append("#")
                i += 1
        elif c == "#" and (i == 0 or line[i - 1] in " \t;&|()"):
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def scan_text(text):
    """Denylisted forms in shell text: [(line number, label)]."""
    hits = []
    for number, raw in enumerate(text.split("\n"), 1):
        code = strip_comment(raw)
        for label, rx in DENY_RES:
            if rx.search(code):
                hits.append((number, label))
        if "/proc/" in code and not raw.rstrip().endswith(LINUX_ONLY):
            hits.append((number, "/proc/ without a trailing '# linux-only'"))
    return hits


def population(scripts):
    scripts = Path(scripts)
    files = [p for p in sorted(scripts.glob("*.sh")) if p.name != GATES_FILE]
    return files + sorted(p for p in STUBS.glob("*") if p.is_file())


def case_population(env):
    files = population(env.scripts)
    problems = []
    if len(files) < 7:
        problems.append(f"{len(files)} file(s) in the shell population, floor 7")
    if "mozart-probe.sh" not in [p.name for p in files]:
        problems.append("mozart-probe.sh is not in the shell population")
    env.notes.append(f"{len(files)} shell file(s)")
    return problems


def case_denylist(env):
    problems = []
    for path in population(env.scripts):
        hits = scan_text(path.read_text(errors="replace"))
        if hits:
            problems.append(f"{path.name}: {', '.join(f'line {n} {label}' for n, label in hits[:3])}")
    env.notes.append(f"{len(DENYLIST)} denylisted forms, none present")
    return problems


def case_scanner_plants(env):
    """The scanner flags every denylisted form, spares real comments, and survives $#, ${#x} and quoted #."""
    problems = []
    plants = 0
    for label, _, examples in DENYLIST:
        if len(examples) < 2:
            problems.append(f"{label!r} has {len(examples)} plant(s), want a plain form and at least one variant")
        for example in examples:
            plants += 1
            if not any(lbl == label for _, lbl in scan_text(example)):
                problems.append(f"a plant of {label!r} ({example}) was not flagged as it")
    for clean in CLEAN_LINES:
        if scan_text(clean):
            problems.append(f"the clean line {clean!r} was flagged")
    hidden = [
        'n=$#; sed -i x f',
        'echo "a#b"; sed -i x f',
        'n=${#v}; sed -i x f',
        'echo "# not a comment"; sed -i x f',
        "echo '#'; sed -i x f",
    ]
    for line in hidden:
        if not scan_text(line):
            problems.append(f"a denylisted form after a non-comment # was hidden: {line!r}")
    if scan_text("echo ok # sed -i x f"):
        problems.append("a denylisted form inside a real comment was flagged")
    if not scan_text("read x </proc/stat"):
        problems.append("/proc/ without a linux-only marker was not flagged")
    if scan_text("read x </proc/stat # linux-only"):
        problems.append("/proc/ with a linux-only marker was flagged")
    env.notes.append(f"{plants} denylist plants (a plain form and variants per row) caught")
    return problems


def python_files(scripts):
    scripts = Path(scripts)
    files = sorted(scripts.glob("mozart*.py")) + [scripts / "check-resources.py"] + sorted((REPO / "tests" / "resources").glob("*.py"))
    return [p for p in files if p.is_file()]


def py39_problems(src, name):
    """What would not run on 3.9: syntax (feature_version), PEP 604 in annotations, zip(strict=)."""
    try:
        tree = ast.parse(src, name, feature_version=(3, 9))
    except SyntaxError as exc:
        return [f"{name}: not Python 3.9 syntax: {exc.msg} at line {exc.lineno}"]
    future = any(
        isinstance(n, ast.ImportFrom) and n.module == "__future__" and any(a.name == "annotations" for a in n.names)
        for n in tree.body
    )
    problems = []
    annotations = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            args = node.args
            every = args.posonlyargs + args.args + args.kwonlyargs + [a for a in (args.vararg, args.kwarg) if a]
            annotations += [a.annotation for a in every if a.annotation]
            if node.returns:
                annotations.append(node.returns)
        elif isinstance(node, ast.AnnAssign):
            annotations.append(node.annotation)
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "zip":
            if any(k.arg == "strict" for k in node.keywords):
                problems.append(f"{name}:{node.lineno}: zip(strict=) needs Python 3.10")
    if not future:
        for ann in annotations:
            if any(isinstance(n, ast.BinOp) and isinstance(n.op, ast.BitOr) for n in ast.walk(ann)):
                problems.append(f"{name}:{ann.lineno}: PEP 604 'X | Y' in an annotation needs `from __future__ import annotations` on 3.9")
    return problems


def case_python_floor(env):
    problems = []
    files = python_files(env.scripts)
    if "check-resources.py" not in [p.name for p in files]:
        problems.append("check-resources.py is not in the Python population")
    for path in files:
        problems += py39_problems(path.read_text(encoding="utf-8"), path.name)
    for label, src, want in (
        ("a PEP 604 annotation without the future import", PLANT_PEP604, "PEP 604"),
        ("zip(strict=)", PLANT_ZIP, "zip(strict="),
    ):
        if not any(want in p for p in py39_problems(src, "plant.py")):
            problems.append(f"the 3.9 floor missed {label}")
    if py39_problems("from __future__ import annotations\n" + PLANT_PEP604 + "pairs = list(zip([1], [2]))\n", "clean.py"):
        problems.append("the 3.9 floor flagged a PEP 604 annotation under the future import, or zip without strict")
    env.notes.append(f"{len(files)} Python file(s) parse as 3.9, no PEP 604 annotation or zip(strict=)")
    return problems


def mutation_plant_sed_i(scripts):
    path = scripts / "mozart-probe.sh"
    path.write_text(path.read_text() + '\nsed -i "s/a/b/" "$MP_DIR/out"\n')


# --- gates ---------------------------------------------------------------------------

# --- the trust root, contract, registry and matcher gates (V39-V42) ------------------------------------------
# The bundle's modules register themselves in sys.modules, so every in-process check runs in a fresh
# `python -I` child through tests/resources/drive.py; the checker only builds inputs and judges outputs.

FIXTURES = REPO / "tests" / "resources"
SHIPPED_TOOLING = {
    "check-carve-conservation.py", "check-edition-diffs.py", "check-edition-lens.sh", "check-edition-norm.py",
    "check-edition-text.py", "check-editions.sh", "check-field-note-parity.py", "check-manual-bundle.py",
    "check-resources.py", "lib-campaign.sh", "mozart-contract-gates.sh", "mozart-lint.sh", "mozart-metrics.sh",
}
PROBE_STAMP = "2026-10-26T12:00:00Z"


def drive(scripts, function, args, extra_env=None, cwd=None, timeout=90):
    """Run tests/resources/testing.py:<function> against `scripts` in a fresh isolated interpreter."""
    argv = [sys.executable, "-I", str(FIXTURES / "drive.py"), str(scripts), function]
    env = dict({"PATH": SYSTEM_PATH, "HOME": "/nonexistent"}, **(extra_env or {}))
    res = run(argv, env=env, cwd=cwd, timeout=timeout, stdin=json.dumps(args).encode())
    if res.timed_out or res.rc != 0:
        raise RuntimeError(f"{function} driver failed (exit {res.rc}): {res.err.decode('utf-8', 'replace')[-400:]}")
    return json.loads(res.out.decode())


def fixture_text(name):
    return (FIXTURES / name).read_text(encoding="utf-8")


def fixture_json(name):
    return json.loads(fixture_text(name))


def probe_doc(schema, **values):
    """A complete, valid probe document: every fact null except the ones given."""
    doc = {k: None for k in schema["facts"]}
    doc.update(kube_contexts={}, probe_version=1, probed_at=PROBE_STAMP, probe_errors=[])
    doc.update(values)
    return doc


def make_home(env, grant=None, registry=None, label="home"):
    """A fresh home with a 0700 .mozart/resources and the given user files (0600)."""
    home = Path(os.path.realpath(env.fresh(label)))
    resources = home / ".mozart" / "resources"
    resources.mkdir(parents=True)
    os.chmod(home / ".mozart", 0o700)
    os.chmod(resources, 0o700)
    for name, content in (("grant.md", grant), ("registry.md", registry)):
        if content is not None:
            path = resources / name
            path.write_bytes(content if isinstance(content, bytes) else content.encode("utf-8"))
            os.chmod(path, 0o600)
    return home


# --- V39_schema --------------------------------------------------------------------------------------------

def nested(depth):
    spec, value = {"type": "int"}, 1
    for _ in range(depth):
        spec, value = {"type": "list", "items": spec}, [value]
    return spec, value


def validator_cases():
    kube_map = {"type": "map", "keys": {"type": "string", "grammar": "kube_name"}, "values": {"type": "bool"}, "maxProperties": 2}
    deep_ok, deep_ok_value = nested(8)
    deep_bad, deep_bad_value = nested(9)
    obj = {"type": "object", "required": ["a"], "properties": {"a": {"type": "int"}}}
    return [
        ("int accepts 1", {"type": "int", "min": 1, "max": 3}, 1, True),
        ("int rejects min-1", {"type": "int", "min": 1, "max": 3}, 0, False),
        ("int accepts max", {"type": "int", "min": 1, "max": 3}, 3, True),
        ("int rejects max+1", {"type": "int", "min": 1, "max": 3}, 4, False),
        ("int rejects a bool", {"type": "int"}, True, False),
        ("int rejects a float", {"type": "int"}, 1.0, False),
        ("int rejects a string", {"type": "int"}, "1", False),
        ("number accepts an int", {"type": "number"}, 3, True),
        ("number rejects a bool", {"type": "number"}, True, False),
        ("bool rejects 1", {"type": "bool"}, 1, False),
        ("grammar is a full match: a trailing newline", {"type": "string", "grammar": "arg"}, "a\n", False),
        ("grammar no_leading_dash", {"type": "string", "grammar": "arg"}, "-a", False),
        ("grammar accepts a plain value", {"type": "string", "grammar": "arg"}, "ok/x", True),
        ("grammar max length 255", {"type": "string", "grammar": "arg"}, "a" * 256, False),
        ("length counts characters: three multibyte", {"type": "string", "maxLength": 3}, "ééé", True),
        ("length counts characters: four multibyte", {"type": "string", "maxLength": 3}, "éééé", False),
        ("length counts an astral character once", {"type": "string", "maxLength": 1}, "\U0001F600", True),
        ("printable rejects U+2028", {"type": "string", "printable": True}, "a b", False),
        ("printable rejects a control character", {"type": "string", "printable": True}, "a\x01b", False),
        ("printable rejects a C1 control (U+009B)", {"type": "string", "printable": True}, "a\u009bb", False),
        ("printable rejects a bidi override (U+202E)", {"type": "string", "printable": True}, "a\u202eb", False),
        ("printable rejects a bidi isolate (U+2066)", {"type": "string", "printable": True}, "a\u2066b", False),
        ("printable rejects a zero-width space (U+200B)", {"type": "string", "printable": True}, "a\u200bb", False),
        ("printable rejects a BOM (U+FEFF)", {"type": "string", "printable": True}, "a\ufeffb", False),
        ("printable rejects a lone surrogate", {"type": "string", "printable": True}, "a\ud800b", False),
        ("printable rejects a private-use character", {"type": "string", "printable": True}, "a\ue000b", False),
        ("printable accepts accented text and an astral character", {"type": "string", "printable": True}, "caf\u00e9 \U0001F600", True),
        ("gpu_name carries the printable rule", {"$ref": "facts.gpu_name"}, "a\u202eb", False),
        ("a map key canary is not echoed", {"type": "map", "keys": {"type": "string", "grammar": "kube_name"}, "values": {"type": "bool"}}, {"-canary-key": True}, False),
        ("closed object rejects an unknown key", obj, {"a": 1, "b": 2}, False),
        ("an object that opts out of closure accepts extra keys", dict(obj, additionalProperties=True), {"a": 1, "b": 2}, True),
        ("object rejects a missing required key", obj, {}, False),
        ("when: exited needs exit_code", {"$ref": "remote.status"}, {"launch_id": "l0123456789abcdef", "state": "exited"}, False),
        ("when: exited with exit_code is fine", {"$ref": "remote.status"}, {"launch_id": "l0123456789abcdef", "state": "exited", "exit_code": 3}, True),
        ("nullable accepts null", {"type": "int", "nullable": True}, None, True),
        ("non-nullable rejects null", {"type": "int"}, None, False),
        ("map accepts a name to bool", kube_map, {"ctx": True}, True),
        ("map rejects a bad key", kube_map, {"-x": True}, False),
        ("map rejects a non-bool value", kube_map, {"ctx": 1}, False),
        ("map rejects too many entries", kube_map, {"a": True, "b": True, "c": True}, False),
        ("enum_from accepts a member", {"type": "string", "enum_from": "trust"}, "owned", True),
        ("enum_from rejects a stranger", {"type": "string", "enum_from": "trust"}, "nope", False),
        ("list maxItems", {"type": "list", "maxItems": 1, "items": {"type": "int"}}, [1, 2], False),
        ("nesting of 8 is accepted", deep_ok, deep_ok_value, True),
        ("nesting of 9 is rejected", deep_bad, deep_bad_value, False),
    ]


def case_validator(env):
    cases = validator_cases()
    got = drive(env.scripts, "validate_batch", {"cases": [{"id": str(i), "spec": s, "value": v} for i, (_, s, v, _) in enumerate(cases)]})
    problems = []
    for i, (name, _, _, ok) in enumerate(cases):
        if bool(got[str(i)]) == ok:
            problems.append(f"validator self-test {name!r}: expected {'accepted' if ok else 'rejected'}, got {'rejected' if ok else 'accepted'}")
        if "canary" in name and "canary-key" in json.dumps(got[str(i)]):
            problems.append(f"validator self-test {name!r}: a map key was echoed into a message")
    env.notes.append(f"{len(cases)} validator self-tests")
    return problems


def spec_nodes(node, path):
    """Every JSON-value spec node in the schema (not the grant's text tables), with its path."""
    if isinstance(node, dict):
        if "type" in node and "$ref" not in node and isinstance(node["type"], str):
            yield path, node
        for key, child in node.items():
            if key not in ("when", "kind"):
                yield from spec_nodes(child, f"{path}.{key}")
    elif isinstance(node, list):
        for i, child in enumerate(node):
            yield from spec_nodes(child, f"{path}[{i}]")


def negatives(spec, schema):
    out = []
    kind = spec["type"]
    if kind == "string":
        pat = schema["grammars"][spec["grammar"]]["pattern"] if "grammar" in spec else spec.get("pattern")
        if pat:
            for cand in ("\x00", "", " \n", "!!!", "é"):
                if not re.fullmatch(pat, cand):
                    out.append(("pattern", cand))
                    break
        if "enum" in spec or "enum_from" in spec:
            out.append(("enum", "zzz-not-allowed"))
        if "maxLength" in spec:
            out.append(("maxLength", "x" * (spec["maxLength"] + 1)))
        out.append(("type", 5))
        if spec.get("printable"):
            out.append(("printable", "a\u200bb"))
    elif kind in ("int", "number"):
        if "min" in spec:
            out.append(("min", spec["min"] - 1))
        if "max" in spec:
            out.append(("max", spec["max"] + 1))
        out.append(("type", "5"))
        out.append(("type", True))
    elif kind == "list":
        if "maxItems" in spec:
            out.append(("maxItems", [None] * (spec["maxItems"] + 1)))
        out.append(("type", "not a list"))
    elif kind == "map":
        if "maxProperties" in spec:
            out.append(("maxProperties", {f"k{i}": True for i in range(spec["maxProperties"] + 1)}))
        out.append(("type", []))
    elif kind == "bool":
        out.append(("type", 0))
    elif kind == "object":
        out.append(("type", []))
        out.append(("unknown key", {"zzz_unknown_key": 1}))
    return out


def case_negatives(env):
    schema = env.schema
    cases = []
    for top in ("facts", "defs", "hook", "error", "remote", "match"):
        for path, spec in spec_nodes(schema[top], top):
            spec = dict(spec, nullable=False)
            for why, value in negatives(spec, schema):
                if spec["type"] == "object" and why == "unknown key" and spec.get("required"):
                    continue
                cases.append({"id": f"{path}:{why}", "spec": spec, "value": value})
            for bound in ("min", "max"):
                if spec["type"] == "int" and bound in spec:
                    cases.append({"id": f"{path}:accepts {bound}", "spec": spec, "value": spec[bound], "accept": True})
    got = drive(env.scripts, "validate_batch", {"cases": [{k: c[k] for k in ("id", "spec", "value")} for c in cases]})
    problems = []
    for c in cases:
        rejected = bool(got[c["id"]])
        if c.get("accept") and rejected:
            problems.append(f"{c['id']}: a boundary value was rejected: {got[c['id']][0]}")
        if not c.get("accept") and not rejected:
            problems.append(f"{c['id']}: a generated violation was accepted")
    if len(cases) < 60:
        problems.append(f"only {len(cases)} schema-generated cases, floor 60")
    env.notes.append(f"{len(cases)} schema-generated negatives and boundaries")
    return problems


def case_conformance(env):
    files = sorted(FIXTURES.glob("conformance-*.fixture"))
    cases, wanted = [], []
    covered = set()
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        for c in data["cases"]:
            node = env.schema
            for part in (c.get("schema") or data["schema"]).split("."):
                node = node[part]
            covered.add(c.get("schema") or data["schema"])
            cases.append({"id": f"{path.name}:{c['name']}", "spec": node, "value": c["value"]})
            wanted.append(c["valid"])
    got = drive(env.scripts, "validate_batch", {"cases": cases})
    problems = [f"{c['id']}: expected {'accepted' if ok else 'rejected'}" for c, ok in zip(cases, wanted) if bool(got[c["id"]]) == ok]
    if len(cases) < 20:
        problems.append(f"{len(cases)} conformance fixtures, floor 20")
    wanted_nodes = {f"hook.{v}.request" for v in env.schema["hook_verbs"]} | {f"hook.{v}.response" for v in env.schema["hook_verbs"]}
    if wanted_nodes - covered:
        problems.append(f"no conformance fixture for {sorted(wanted_nodes - covered)}")
    if not any("status.exited without exit_code" in c["id"] for c in cases):
        problems.append("the named conformance member 'status.exited without exit_code' is missing")
    env.notes.append(f"{len(cases)} conformance fixtures in {len(files)} files")
    return problems


def case_strict_json(env):
    deep = lambda n: '{"a":' * n + "1" + "}" * n
    cases = [
        ("an object", '{"a":1}', True), ("a duplicate key", '{"a":1,"a":2}', False), ("NaN", '{"a":NaN}', False),
        ("Infinity", '{"a":Infinity}', False), ("-Infinity", '{"a":-Infinity}', False), ("a list at the top", "[]", False),
        ("a bare number", "1", False), ("a leading-zero number", '{"a":0008}', False), ("a leading-zero negative", '{"a":-01}', False),
        ("trailing garbage", '{"a":1}x', False), ("nesting of 8", deep(8), True), ("nesting of 9", deep(9), False),
        ("invalid UTF-8", '{"a":"\udcff"}', False), ("pathological nesting", '{"a":' + "[" * 100000, False),
    ]
    got = drive(env.scripts, "loads_batch", {"cases": [{"id": n, "text": t} for n, t, _ in cases]})
    problems = [f"strict JSON {n!r}: expected {'accepted' if ok else 'rejected'}" for n, _, ok in cases if (got[n] is None) != ok]
    return problems


def expand_class(text):
    chars, i = set(), 0
    while i < len(text):
        if i + 2 < len(text) and text[i + 1] == "-":
            chars.update(chr(c) for c in range(ord(text[i]), ord(text[i + 2]) + 1))
            i += 3
        else:
            chars.add(text[i])
            i += 1
    return chars


def case_grammar_agree(env):
    """The schema's character classes equal the ones lib-host.sh spells out, compared as sets."""
    lib = (env.scripts / "mozart-lib-host.sh").read_text()
    problems = []
    for func, grammar in (("mz_arg_ok", "arg"), ("mz_name_ok", "kube_name")):
        body = lib[lib.index(f"{func}()"):]
        body = body[:body.index("\n}\n")]
        sh_classes = [expand_class(c) for c in re.findall(r"\[!([^\]]+)\]", body)]
        schema_classes = [expand_class(c) for c in re.findall(r"\[([^\]]+)\]", env.schema["grammars"][grammar]["pattern"])]
        limit = re.search(r"-le (\d+)", body)
        count = re.search(r"\{(\d+)(?:,(\d+))?\}\$", env.schema["grammars"][grammar]["pattern"])
        want = [schema_classes[-1]] if grammar == "arg" else [schema_classes[0], schema_classes[-1]]
        if grammar == "kube_name":
            sh_classes = sh_classes[:2]
        if sh_classes != want:
            problems.append(f"{func}: the character classes differ from the schema's {grammar} grammar")
        top = int(count.group(2) or count.group(1)) + (1 if grammar == "kube_name" else 0)
        if not limit or int(limit.group(1)) != top:
            problems.append(f"{func}: the length limit differs from the schema's {grammar} grammar ({top})")
    return problems


def case_bundle_files(env):
    listed = set(env.schema["bundle"]["files"])
    actual = {p.name for p in env.scripts.iterdir() if p.is_file() and p.name not in SHIPPED_TOOLING and p.suffix in (".sh", ".py", ".json")}
    problems = []
    if listed != actual:
        problems.append(f"bundle.files differs from the shipped files: only listed {sorted(listed - actual)}, only on disk {sorted(actual - listed)}")
    if len(listed) != len(env.schema["bundle"]["files"]):
        problems.append("bundle.files lists a file twice")
    env.notes.append(f"bundle.files = the {len(actual)} shipped files")
    return problems


def mutation_open_objects(scripts):
    mutate_file(scripts / "mozart_contract.py", 'if not spec.get("additionalProperties", False):', "if False:")


# --- V40_grant ----------------------------------------------------------------------------------------------

def install_copy(env, scripts, label="inst", mode_dir=0o700):
    """Copy the bundle to <fresh home>/.mozart/bin the way an install would; returns (home, bin)."""
    home = make_home(env, label=label)
    bin_dir = home / ".mozart" / "bin"
    bin_dir.mkdir()
    for name in json.loads((Path(scripts) / "mozart-schemas.json").read_text())["bundle"]["files"]:
        shutil.copy2(Path(scripts) / name, bin_dir / name)
        os.chmod(bin_dir / name, 0o644)
    os.chmod(bin_dir, mode_dir)
    return home, bin_dir


def production_python():
    return "/usr/bin/python3" if os.access("/usr/bin/python3", os.X_OK) else sys.executable


def case_home(env):
    """HOME never decides where the grant is; the markers disable; Context.production() uses the account record."""
    problems = []
    full = fixture_text("grant-full.fixture")
    home = make_home(env, grant=full)
    other = env.fresh("elsewhere")
    link = Path(env.fresh("links")) / "home-link"
    os.symlink(home, link)
    cases = [
        ("seam: HOME equals the home", {"HOME": str(home)}, None),
        ("HOME unset", {}, None),
        ("HOME is a symlink to the same directory", {"HOME": str(link)}, None),
        ("HOME differs", {"HOME": str(other)}, "home-mismatch"),
        ("HOME is empty", {"HOME": ""}, "home-mismatch"),
        ("MOZART_CHILD_SESSION set", {"HOME": str(home), "MOZART_CHILD_SESSION": "child-1"}, "child-session"),
        ("MOZART_CHILD_SESSION set to the empty string", {"HOME": str(home), "MOZART_CHILD_SESSION": ""}, "child-session"),
        ("MOZART_LAUNCH_CHILD non-empty", {"HOME": str(home), "MOZART_LAUNCH_CHILD": "1"}, "child-session"),
        ("MOZART_LAUNCH_CHILD empty does not mean child mode", {"HOME": str(home), "MOZART_LAUNCH_CHILD": ""}, None),
    ]
    got = drive(env.scripts, "grant_load", {"cases": [{"id": str(i), "home": str(home), "environ": e} for i, (_, e, _) in enumerate(cases)]})
    for i, (name, _, reason) in enumerate(cases):
        state = got[str(i)]
        if state["reason"] != reason or state["enabled"] != (reason is None):
            problems.append(f"{name}: reason {state['reason']!r} enabled {state['enabled']}, want {reason!r}")
    hostile = env.fresh("hostile-home")
    prod = drive(env.scripts, "production_context", {}, extra_env={"HOME": str(hostile)})
    want_home = pwd.getpwuid(os.geteuid()).pw_dir
    if prod["home"] != want_home:
        problems.append(f"Context.production().home is {prod['home']!r} with a hostile HOME, want the account record's {want_home!r}")
    if any(h is not None for h in prod["hooks"]) or prod["ssh_bin"] != "/usr/bin/ssh":
        problems.append(f"Context.production() has a test hook set or a different ssh: {prod}")
    allowed = {"HOME"} | set(env.schema["grant"]["child_markers"]["present"]) | set(env.schema["grant"]["child_markers"]["non_empty"])
    if not set(prod["environ"]) <= allowed:
        problems.append(f"Context.production() carries environment keys outside the allowlist: {prod['environ']}")
    env.notes.append("home from the account record; markers disable")
    return problems


def run_text(argv, env_vars, cwd=None, timeout=30):
    res = run(argv, env=env_vars, cwd=cwd, timeout=timeout)
    return res.rc, res.out.decode("utf-8", "replace").strip(), res.err.decode("utf-8", "replace")


def case_launcher(env):
    """The launcher forms ignore a hostile environment, the same forms without `env -i` do not (so the
    comparison can fail), and the launcher refuses anywhere but <home>/.mozart/bin."""
    problems = []
    home_cmd = env.schema["launcher"]["home_cmd"]
    py = production_python()
    want_home = pwd.getpwuid(os.geteuid()).pw_dir
    work = Path(os.path.realpath(env.fresh("hostile")))
    evil = {"DEVELOPER_DIR": "/nonexistent", "LD_PRELOAD": "/nonexistent.so", "DYLD_INSERT_LIBRARIES": "/nonexistent.dylib", "PERL5OPT": "-Mx"}
    base = {"PATH": SYSTEM_PATH, "HOME": str(work)}
    sum_tool = "/usr/bin/shasum" if os.access("/usr/bin/shasum", os.X_OK) else "/usr/bin/sha256sum"
    sum_args = ["-a", "256"] if sum_tool.endswith("shasum") else []
    sample = work / "sample"
    sample.write_bytes(b"sum me\n")
    home, bin_dir = install_copy(env, env.scripts, "fakehome")
    stray = Path(os.path.realpath(env.fresh("notbin")))
    for name in env.schema["bundle"]["files"]:
        shutil.copy2(env.scripts / name, stray / name)
    launcher = [py, "-I", str(stray / "mozart-resources.py"), "grant", "--json"]
    forms = {
        "home": ["/usr/bin/env", "-i", py, "-I", "-c", home_cmd],
        "sum": ["/usr/bin/env", "-i", sum_tool] + sum_args + [str(sample)],
        "launcher": ["/usr/bin/env", "-i", "MOZART_LAUNCH_CHILD="] + launcher,
    }
    for name, argv in forms.items():
        clean = run_text(argv, base, cwd=work)
        dirty = run_text(argv, dict(base, **evil), cwd=work)
        if clean != dirty:
            problems.append(f"the {name} launcher form's output changes under a hostile environment: {clean[:2]} vs {dirty[:2]}")
    if run_text(forms["home"], dict(base, **evil), cwd=work)[1] != want_home:
        problems.append(f"the home form did not print the account record's home {want_home!r} under a hostile HOME and loader")
    if json.loads(run_text(forms["launcher"], dict(base, **evil), cwd=work)[1] or "{}").get("error") != "launcher-location":
        problems.append("the launcher form under a hostile environment did not refuse with launcher-location")
    if not run_text(forms["sum"], base, cwd=work)[1].startswith(hashlib.sha256(b"sum me\n").hexdigest()):
        problems.append("the sum form does not print the file's sha256")
    # the negative control: the same commands without `env -i` DO change, so the comparison above can fail
    for name, argv in (("home", [py, "-I", "-c", home_cmd]), ("launcher", launcher)):
        clean = run_text(argv, base, cwd=work)
        dirty = run_text(argv, dict(base, **evil), cwd=work)
        if clean == dirty:
            problems.append(f"negative control: the {name} form without env -i is unchanged by the hostile environment, so this platform cannot show the protection works")
    refusals = [
        ("a real copy in a fake directory", launcher, {"PATH": SYSTEM_PATH, "HOME": str(home)}, "launcher-location"),
        ("the worktree copy", [py, "-I", str(env.scripts / "mozart-resources.py"), "grant", "--json"], {"PATH": SYSTEM_PATH, "HOME": str(home)}, "launcher-location"),
        ("a run without -I", [py, str(stray / "mozart-resources.py"), "grant", "--json"], {"PATH": SYSTEM_PATH, "HOME": str(home)}, "not-isolated"),
    ]
    for name, argv, evars, code in refusals:
        rc, out, _ = run_text(argv, evars)
        try:
            error = json.loads(out).get("error")
        except ValueError:
            error = None
        if rc != 2 or error != code:
            problems.append(f"{name}: exit {rc}, error {error!r}, want exit 2 and {code!r}")
    env.notes.append("env -i launcher forms unchanged under a hostile environment (and the same forms without it change); wrong location and no -I refused")
    return problems


def case_installed(env):
    """The launcher self-check against a real install layout, run in-process: it loads and grants, and
    refuses a symlinked, group-writable, missing, version-skewed or unlisted module."""
    problems = []

    def variant(label, edit=None, **args):
        home, bin_dir = install_copy(env, env.scripts, label)
        (home / ".mozart" / "resources" / "grant.md").write_text(fixture_text("grant-minimal.fixture"))
        os.chmod(home / ".mozart" / "resources" / "grant.md", 0o600)
        if edit:
            edit(bin_dir)
        return drive(bin_dir, "boot_copy", dict(args, home=str(home)))

    def symlink_state(bin_dir):
        target = bin_dir.parent / "elsewhere.py"
        shutil.move(str(bin_dir / "mozart_state.py"), target)
        os.symlink(target, bin_dir / "mozart_state.py")

    def group_writable(bin_dir):
        os.chmod(bin_dir / "mozart_state.py", 0o664)

    def skew_contract(bin_dir):
        mutate_file(bin_dir / "mozart_contract.py", 'BUNDLE_VERSION = "1"', 'BUNDLE_VERSION = "2"')

    def skew_state(bin_dir):
        mutate_file(bin_dir / "mozart_state.py", 'BUNDLE_VERSION = "1"', 'BUNDLE_VERSION = "2"')

    def extra_module(bin_dir):
        (bin_dir / "mozart_extra.py").write_text('BUNDLE_VERSION = "1"\n')

    def slash_in_list(bin_dir):
        mutate_file(bin_dir / "mozart-schemas.json", '"mozart-lib-host.sh"', '"sub/mozart-lib-host.sh"')

    def no_bundle_key(bin_dir):
        mutate_file(bin_dir / "mozart-schemas.json", '"bundle": {', '"bundlx": {')

    def broken_state(bin_dir):
        append_to(bin_dir, "mozart_state.py", "\nraise RuntimeError('boom')\n")

    def drop_module(bin_dir):
        os.unlink(bin_dir / "mozart_grant.py")

    def open_bin(bin_dir):
        os.chmod(bin_dir, 0o770)

    def world_writable(bin_dir):
        os.chmod(bin_dir / "mozart_state.py", 0o646)

    plans = [
        ("positive control", None, {"argv": ["grant"], "load": ["mozart_state"]}),
        ("a symlinked module", symlink_state, {}),
        ("a group-writable module", group_writable, {}),
        ("a group-writable bin directory", open_bin, {}),
        ("a world-writable module", world_writable, {}),
        ("a foreign owner", None, {"fake_euid": os.geteuid() + 1}),
        ("a missing module", drop_module, {}),
        ("a bundle.files name with a slash", slash_in_list, {}),
        ("a schema without bundle.files", no_bundle_key, {}),
        ("a BUNDLE_VERSION skew in the contract", skew_contract, {}),
        ("a BUNDLE_VERSION skew in a sibling", skew_state, {"load": ["mozart_state"]}),
        ("an unlisted module", extra_module, {"load": ["mozart_extra"]}),
        ("a sibling that fails to load", broken_state, {"argv": ["grant"]}),
    ]
    plans = [p for p in plans if env.wants(p[0])]  # a mutation control runs only the variant that can catch it
    results = env.pmap(lambda p: variant(p[0].replace(" ", "-"), p[1], **p[2]), plans)
    by = {p[0]: r for p, r in zip(plans, results)}
    if "positive control" in by:
        ok = by["positive control"]
        if ok.get("boot") != "ok" or ok.get("code") != 0 or ok.get("out", {}).get("enabled") is not True or ok.get("mozart_state") != "ok":
            problems.append(f"the copy in <home>/.mozart/bin did not load and grant: {ok}")
    for name in ("a symlinked module", "a group-writable module", "a group-writable bin directory", "a world-writable module", "a foreign owner", "a missing module", "a bundle.files name with a slash", "a schema without bundle.files", "a BUNDLE_VERSION skew in the contract"):
        if name in by and by[name].get("boot") != "bundle-integrity":
            problems.append(f"{name}: boot said {by[name].get('boot')!r}, want bundle-integrity")
    for name, module in (("a BUNDLE_VERSION skew in a sibling", "mozart_state"), ("an unlisted module", "mozart_extra")):
        if name in by and (by[name].get("boot") != "ok" or by[name].get(module) != "bundle-integrity"):
            problems.append(f"{name}: {by[name]}, want the module refused with bundle-integrity")
    if "a sibling that fails to load" in by:
        res = by["a sibling that fails to load"]
        if res.get("boot") != "ok" or res.get("code") != env.schema["exit_codes"]["internal"] or res.get("out", {}).get("error") != "internal":
            problems.append(f"a sibling that fails to load: {res}; want a structured internal error with the documented exit, not a traceback")
    if env.focus:
        return problems
    home, bin_dir = install_copy(env, env.scripts, "clean-subprocess")
    code = ("import dataclasses, importlib.util, io, json, sys\n"
            "sys.dont_write_bytecode = True\n"
            "from contextlib import redirect_stdout\n"
            "spec = importlib.util.spec_from_file_location('cli', sys.argv[1] + '/mozart-resources.py')\n"
            "cli = importlib.util.module_from_spec(spec); spec.loader.exec_module(cli)\n"
            "contract = cli._boot(sys.argv[2])\n"
            "ctx = dataclasses.replace(contract.Context.production(), home=sys.argv[2])\n"
            "buf = io.StringIO()\n"
            "with redirect_stdout(buf): code = cli.main(['grant'], ctx)\n"
            "print(json.dumps({'code': code, 'testing': 'testing' in sys.modules}))\n")
    rc, out, err = run_text([sys.executable, "-I", "-c", code, str(bin_dir), str(home)], {"PATH": SYSTEM_PATH, "HOME": str(home)})
    try:
        answer = json.loads(out)
    except ValueError:
        answer = {"error": err[-200:]}
    if answer.get("testing") is not False:
        problems.append(f"'testing' is in sys.modules after a CLI run, or the run failed: {answer}")
    env.notes.append("installed layout loads and grants; 11 integrity refusals; testing never imported by a CLI run")
    return problems


def case_hygiene(env):
    """Symlinked, group- or world-writable, or foreign-owned components make the grant unreadable."""
    full = fixture_text("grant-minimal.fixture")

    def build(label, edit=None):
        home = make_home(env, grant=full, label=label)
        if edit:
            edit(home / ".mozart", home / ".mozart" / "resources", home / ".mozart" / "resources" / "grant.md")
        return home

    def link_grant(dot, res, grant):
        real = Path(env.fresh("real")) / "grant.md"
        real.write_text(full)
        os.chmod(real, 0o600)
        grant.unlink()
        os.symlink(real, grant)

    def link_dir(which):
        def edit(dot, res, grant):
            target = Path(env.fresh("realdir"))
            if which == "resources":
                shutil.copytree(res, target / "r")
                shutil.rmtree(res)
                os.symlink(target / "r", res)
            else:
                shutil.copytree(dot, target / "m")
                shutil.rmtree(dot)
                os.symlink(target / "m", dot)
        return edit

    def chmod(path_index, mode):
        def edit(dot, res, grant):
            os.chmod((dot, res, grant)[path_index], mode)
        return edit

    cases = [
        ("control", None, None, None),
        ("a symlinked grant", link_grant, None, "grant-hygiene"),
        ("a symlinked resources directory", link_dir("resources"), None, "grant-hygiene"),
        ("a symlinked .mozart", link_dir("mozart"), None, "grant-hygiene"),
        ("a group-writable grant", chmod(2, 0o660), None, "grant-hygiene"),
        ("a world-writable grant", chmod(2, 0o666), None, "grant-hygiene"),
        ("a group-writable resources directory", chmod(1, 0o770), None, "grant-hygiene"),
        ("a world-writable .mozart", chmod(0, 0o757), None, "grant-hygiene"),
        ("a foreign-owned .mozart (stat seam)", None, 0, "grant-hygiene"),
        ("a foreign-owned resources directory (stat seam)", None, 1, "grant-hygiene"),
        ("a foreign-owned grant (stat seam)", None, 2, "grant-hygiene"),
    ]
    homes = [build(f"hyg{i}", c[1]) for i, c in enumerate(cases)]
    batch = []
    for i, (home, (_, _, foreign, _)) in enumerate(zip(homes, cases)):
        case = {"id": str(i), "home": str(home)}
        if foreign is not None:
            case["foreign_at"] = foreign
        batch.append(case)
    got = drive(env.scripts, "grant_load", {"cases": batch})
    problems = []
    for i, (name, _, _, reason) in enumerate(cases):
        state = got[str(i)]
        want_enabled = reason is None
        if state["reason"] != reason or state["enabled"] != want_enabled:
            problems.append(f"{name}: reason {state['reason']!r}, want {reason!r}")
    env.notes.append(f"{len(cases) - 1} hygiene failures refused, the control enables")
    return problems


def grammar_cases():
    ok = "## Remote execution\n- enabled: true\n"
    host = "## Host: a\n- trust: owned\n- transport: ssh\n- permission_mode: default\n- max_budget_usd: 5\n"
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq0uVu1rPzAh7P1nQw3Yx9c2d1m8k4f6s7t0u2v3w5x"
    return [
        ("duplicate key", ok + "- enabled: true\n"), ("True", "## Remote execution\n- enabled: True\n"), ("yes", "## Remote execution\n- enabled: yes\n"),
        ("1", "## Remote execution\n- enabled: 1\n"), ("quoted true", '## Remote execution\n- enabled: "true"\n'),
        ("inline comment", "## Remote execution\n- enabled: true # on\n"), ("BOM", b"\xef\xbb\xbf" + ok.encode()),
        ("CRLF", ok.replace("\n", "\r\n")), ("repeated section", ok + "\n" + ok), ("duplicate labels", ok + host + host),
        ("label ../x", ok + host.replace("Host: a", "Host: ../x")), ("label a/b", ok + host.replace("Host: a", "Host: a/b")),
        ("label x.y", ok + host.replace("Host: a", "Host: x.y")), ("non-UTF-8", b"## Remote execution\n- enabled: true\n\xff\n"),
        ("more than 64 KiB", (ok + "".join(f"- repos: /x{i}\n" for i in range(1)) + "\n" * 70000).encode()),
        ("unknown key", ok + "- surprise: 1\n"), ("unknown section", ok + "## Surprise\n- a: b\n"), ("missing enabled", "## Remote execution\n- repos: /srv/a\n"),
        ("no Remote execution section", host), ("bullet before any section", "- enabled: true\n"), ("prose line", ok + "hello\n"),
        ("empty value", "## Remote execution\n- enabled: \n"), ("bad trust", ok + host.replace("owned", "friendly")),
        ("port 0", ok + host + "- port: 0\n"), ("port 65536", ok + host + "- port: 65536\n"), ("port 08", ok + host + "- port: 08\n"),
        ("max_children 0", ok + host + "- max_children: 0\n"), ("address -oProxyCommand=x", ok + host + "- address: -oProxyCommand=x\n"),
        ("user root;x", ok + host + "- user: root;x\n"), ("identity_file with spaces", ok + host + "- identity_file: /srv/my keys/id\n"),
        ("host_key with a trailing command", ok + host + f"- host_key: {key}; rm -rf /\n"), ("remote_root with spaces", ok + host + "- remote_root: /srv/a b\n"),
        ("remote_root with $HOME", ok + host + "- remote_root: $HOME/work\n"), ("sandbox_image without a digest", "## Remote execution\n- enabled: true\n- sandbox_image: img:latest\n"),
        ("empty list item", "## Remote execution\n- enabled: true\n- repos: /a;;/b\n"), ("relative repo", "## Remote execution\n- enabled: true\n- repos: srv/a\n"),
        ("currency usd", "## Remote execution\n- enabled: true\n- currency: usd\n"), ("hook name ../x", ok + "## Discovery hooks\n- ../x: /srv/h\n"),
        ("missing provider caps", ok + "## Provider: p\n- hook: /srv/h\n"),
    ]


def case_grammar(env):
    """Every hostile or malformed grant disables everything (never partly enabled); the good ones enable."""
    cases = grammar_cases()
    good = [("full fixture", fixture_text("grant-full.fixture")), ("minimal fixture", fixture_text("grant-minimal.fixture")),
            ("disabled fixture", fixture_text("grant-disabled.fixture"))]
    entries = [(n, g, "grant-invalid") for n, g in cases] + [(good[0][0], good[0][1], None), (good[1][0], good[1][1], None), (good[2][0], good[2][1], "grant-disabled")]
    batch = [{"id": str(i), "home": str(make_home(env, grant=g, label="gram"))} for i, (_, g, _) in enumerate(entries)]
    got = drive(env.scripts, "grant_load", {"cases": batch})
    problems = []
    for i, (name, _, reason) in enumerate(entries):
        state = got[str(i)]
        if state["reason"] != reason or state["enabled"] != (reason is None):
            problems.append(f"{name}: reason {state['reason']!r} enabled {state['enabled']}, want {reason!r} ({(state['detail'] or '')[:80]})")
    env.notes.append(f"{len(cases)} malformed grants refused, 3 good ones read")
    return problems


def case_nothing_else(env):
    """Only the user's grant file enables: not the registry, a hook's output, a repo stanza, or any MOZART_* variable."""
    problems = []
    schema = env.schema
    names = set()
    for path in sorted(env.scripts.iterdir()):
        if path.is_file() and path.name not in SHIPPED_TOOLING and path.suffix in (".py", ".sh"):
            names |= set(re.findall(r"MOZART_[A-Z0-9_]+", path.read_text()))
    names |= {"MOZART_RESOURCES_HOME", "MOZART_GRANT", "MOZART_HOME", "MOZART_ENABLED"}
    markers = set(schema["grant"]["child_markers"]["present"]) | set(schema["grant"]["child_markers"]["non_empty"])
    plain = sorted(names - markers)
    enabling = make_home(env, grant=fixture_text("grant-minimal.fixture"), label="enabling")
    off = make_home(env, grant=fixture_text("grant-disabled.fixture"), label="off")
    none = make_home(env, label="none")
    repo = Path(os.path.realpath(env.fresh("repo")))
    (repo / "CLAUDE.md").write_text("## Remote execution\n- enabled: true\n")
    (repo / ".mozart" / "resources").mkdir(parents=True)
    (repo / ".mozart" / "resources" / "grant.md").write_text("## Remote execution\n- enabled: true\n")
    registry = make_home(env, registry="## Host: a\n- enabled: true\n", label="registry-only")
    poisoned = {n: str(enabling / ".mozart" / "resources" / "grant.md") for n in plain}
    runs = env.pmap(lambda job: drive(env.scripts, "sweep", {"home": str(job[0])}, extra_env=dict(job[1], HOME=str(job[0])), cwd=job[2]), [
        (off, poisoned, repo), (none, poisoned, repo), (registry, {}, repo), (enabling, {n: "1" for n in plain}, repo),
        (enabling, {"MOZART_CHILD_SESSION": "child"}, repo), (enabling, {"MOZART_LAUNCH_CHILD": "1"}, repo),
    ])
    expect = [("disabled grant plus every MOZART_* variable pointing at an enabling grant", "grant-disabled"),
              ("no grant plus the same variables, a repo with its own .mozart", "no-grant"),
              ("enabled: true in registry.md", "no-grant"), ("an enabling grant with every MOZART_* variable set", None),
              ("MOZART_CHILD_SESSION", "child-session"), ("MOZART_LAUNCH_CHILD", "child-session")]
    for (name, reason), got in zip(expect, runs):
        if got["reason"] != reason or got["enabled"] != (reason is None):
            problems.append(f"{name}: {got}, want reason {reason!r}")
    registry_out = drive(env.scripts, "run_cli", {"home": str(registry), "calls": [{"argv": ["show"]}]})
    if registry_out[0]["code"] != 3 or registry_out[0]["out"].get("error") != "registry-invalid":
        problems.append(f"an enabled: true bullet in registry.md is not refused as an invalid registry: {registry_out[0]['out'].get('error')}")
    env.notes.append(f"{len(plain)} MOZART_* names swept; registry, repo stanza and variables cannot enable")
    return problems


ALLOWED_EDGES = {
    ("mozart_contract", "mozart_grant"), ("mozart_state", "mozart_contract"), ("mozart_verify", "mozart_contract"),
    ("mozart_transport", "mozart_contract"), ("mozart-resources", "mozart_state"), ("mozart-resources", "mozart_contract"),
    ("mozart-resources", "mozart_grant"), ("mozart-dispatch", "mozart_state"), ("mozart-dispatch", "mozart_verify"),
    ("mozart-dispatch", "mozart_transport"), ("mozart-dispatch", "mozart_contract"), ("mozart-dispatch", "mozart_grant"),
}
STDLIB_FOR_GRANT = {"copy", "hashlib", "os", "re", "stat", "pwd", "unicodedata"}


def shipped_py(scripts):
    return sorted(Path(scripts).glob("mozart*.py"))


def call_name(node):
    f = node.func
    if isinstance(f, ast.Name):
        return f.id
    if isinstance(f, ast.Attribute):
        return f.attr if not isinstance(f.value, ast.Name) else f"{f.value.id}.{f.attr}"
    return ""


def enclosing(tree):
    """{node: name of the innermost function containing it}."""
    owner = {}

    def walk(node, current):
        for child in ast.iter_child_nodes(node):
            name = child.name if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) else current
            owner[child] = name
            walk(child, name)
    walk(tree, None)
    return owner


def case_ast(env):
    """Static rules over the shipped modules: the DAG, one loader, the trust root's imports, env reads, banned calls."""
    problems = []
    files = shipped_py(env.scripts)
    trees = {p.stem: (p, ast.parse(p.read_text(encoding="utf-8"), str(p))) for p in files}
    edges, loaders, execs, boots = set(), 0, [], {}
    schema = env.schema
    allowed_env = {"HOME"} | set(schema["grant"]["child_markers"]["present"]) | set(schema["grant"]["child_markers"]["non_empty"])
    banned_calls = {"os.system", "os.popen", "os.fork", "os.forkpty", "posix_spawn", "os.posix_spawn", "os.posix_spawnp", "__import__"}
    for stem, (path, tree) in trees.items():
        owner = enclosing(tree)
        src = path.read_text(encoding="utf-8")
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                if node.name == "load_sibling":
                    loaders += 1
                if node.name == "_boot":
                    boots[stem] = ast.get_source_segment(src, node)
            if isinstance(node, ast.ImportFrom) and node.module == "os" and any(a.name in ("environ", "environb", "getenv", "putenv", "unsetenv", "*") for a in node.names):
                problems.append(f"{stem}: imports environ from os")
            if isinstance(node, ast.Import) and any(a.name == "os" and a.asname for a in node.names):
                problems.append(f"{stem}: aliases the os module, which hides environment reads")
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                mods = [a.name for a in node.names] if isinstance(node, ast.Import) else [node.module or ""]
                for mod in mods:
                    top = mod.split(".")[0]
                    if top.startswith("mozart"):
                        problems.append(f"{stem}: imports {mod} directly (bundle modules load only through load_sibling)")
                    if top in ("pty", "ctypes", "importlib"):
                        problems.append(f"{stem}: imports {top}")
                    if top == "subprocess" and stem != "mozart_contract":
                        problems.append(f"{stem}: imports subprocess; only mozart_contract.run may start a process")
                    if stem == "mozart_grant" and top not in STDLIB_FOR_GRANT:
                        problems.append(f"mozart_grant imports {mod}, which is not on its stdlib list (a back-edge into the bundle?)")
            if isinstance(node, ast.Call):
                name = call_name(node)
                if name.endswith("load_sibling"):
                    if node.args and isinstance(node.args[0], ast.Constant):
                        edges.add((stem, node.args[0].value))
                    else:
                        problems.append(f"{stem}: calls load_sibling with a non-constant module name")
                    if stem == "mozart_grant":
                        problems.append("mozart_grant calls load_sibling (a back-edge)")
                if name in ("exec", "eval"):
                    execs.append((stem, name, owner.get(node)))
                if name in banned_calls or name.startswith("os.exec") or name.startswith("os.spawn"):
                    problems.append(f"{stem}: calls {name}")
                if any(k.arg == "shell" and isinstance(k.value, ast.Constant) and k.value.value for k in node.keywords):
                    problems.append(f"{stem}: passes shell=True")
                if (name == "Context" or name.endswith(".Context")) and owner.get(node) != "production":
                    problems.append(f"{stem}: calls {name}( outside Context.production")
                if name in ("os.getenv", "os.putenv", "os.unsetenv"):
                    problems.append(f"{stem}: reads or writes the environment with {name}")
            if isinstance(node, ast.Attribute) and node.attr in ("environ", "environb") and not (isinstance(node.value, ast.Name) and node.value.id in ("ctx", "self")):
                # ctx.environ is the Context's allowlisted copy; anything else named environ is the process environment
                if owner.get(node) != "production" or stem != "mozart_contract" or not (isinstance(node.value, ast.Name) and node.value.id == "os"):
                    problems.append(f"{stem}: touches .{node.attr} outside Context.production")
            if stem == "mozart_grant" and isinstance(node, ast.Name) and node.id == "Context":
                problems.append("mozart_grant names Context")
            if isinstance(node, ast.FunctionDef) and node.name == "production" and stem == "mozart_contract":
                keys = {n.value for n in ast.walk(node) if isinstance(n, ast.Constant) and isinstance(n.value, str) and n.value.isupper()}
                if keys != allowed_env:
                    problems.append(f"Context.production reads {sorted(keys)}, the allowlist is {sorted(allowed_env)}")
    sites = sorted((s, n, o) for s, n, o in execs)
    if any(n == "eval" for _, n, _ in sites) or sorted(o for _, n, o in sites) != ["_boot", "load_sibling"]:
        problems.append(f"exec/eval call sites are {sites}, want exactly one in _boot and one in load_sibling")
    if loaders != 1:
        problems.append(f"{loaders} definitions of load_sibling, want exactly one")
    if not boots or len(set(boots.values())) != 1:
        problems.append(f"the launcher bootstraps (_boot) are missing or not byte-identical: {sorted(boots)}")
    if not edges <= ALLOWED_EDGES:
        problems.append(f"module edges outside Decision 8: {sorted(edges - ALLOWED_EDGES)}")
    expected_now = {("mozart_contract", "mozart_grant"), ("mozart_state", "mozart_contract"), ("mozart-resources", "mozart_state"),
                    ("mozart-resources", "mozart_contract"), ("mozart-resources", "mozart_grant")}
    if len(edges) < 5 or ("mozart_state", "mozart_contract") not in edges or not expected_now <= edges:
        problems.append(f"the edge walk found {sorted(edges)}, floor 5 with the named member state -> contract")
    env.notes.append(f"{len(edges)} module edges within Decision 8, one loader, two exec sites, env read once")
    return problems


def case_ci_install(env):
    """On a CI runner only: install the bundle into the real passwd home, run the launcher the way a user
    does, and expect `grant --json` to exit 0 with enabled:false (no grant there). Removed afterwards,
    and never attempted where ~/.mozart already exists."""
    if os.environ.get("CI") != "true":
        env.notes.append("installed success path not run here (CI is not true)")
        return []
    home = Path(pwd.getpwuid(os.geteuid()).pw_dir)
    dot = home / ".mozart"
    if os.path.lexists(dot):
        env.notes.append("installed success path skipped (this account already has a ~/.mozart)")
        return []
    problems = []
    try:
        os.mkdir(dot, 0o700)  # fails if it exists: nothing here may be removed that this call did not create
    except OSError as exc:
        return [f"could not create {dot} for the installed-path check: {exc.strerror}"]
    try:
        bin_dir = dot / "bin"
        os.mkdir(bin_dir, 0o700)
        for name in env.schema["bundle"]["files"]:
            shutil.copy2(env.scripts / name, bin_dir / name)
            os.chmod(bin_dir / name, 0o644)
        rc, out, err = run_text(["/usr/bin/env", "-i", production_python(), "-I", str(bin_dir / "mozart-resources.py"), "grant", "--json"], {"PATH": SYSTEM_PATH})
        try:
            answer = json.loads(out)
        except ValueError:
            answer = {}
        if rc != 0 or answer.get("enabled") is not False or answer.get("reason") != "no-grant":
            problems.append(f"the installed launcher answered exit {rc}, {out[:200]!r} {err[-200:]!r}; want exit 0, enabled false, no-grant")
    finally:
        shutil.rmtree(dot, ignore_errors=True)
    env.notes.append("installed success path ran on this runner and was removed")
    return problems


def case_dynamic(env):
    """Running every verb leaves the user's own files byte- and stat-identical."""
    home = make_home(env, grant=fixture_text("grant-full.fixture"), registry=fixture_text("registry-full.fixture"))
    watched = {name: (home / ".mozart" / "resources" / name) for name in ("grant.md", "registry.md")}
    before = {n: (p.read_bytes(), os.stat(p).st_mtime_ns, os.stat(p).st_mode) for n, p in watched.items()}
    calls = [{"argv": ["grant"]}, {"argv": ["show"]}, {"argv": ["match", "--requires", "os=darwin"], "probe_fail": True},
             {"argv": ["facts", "--local"], "probe_doc": probe_doc(env.schema, os="darwin")}, {"argv": ["discover"]}]
    drive(env.scripts, "run_cli", {"home": str(home), "calls": calls})
    after = {n: (p.read_bytes(), os.stat(p).st_mtime_ns, os.stat(p).st_mode) for n, p in watched.items()}
    return [] if before == after else [f"the user's files changed: {[n for n in before if before[n] != after[n]]}"]


def mutation_home_from_env(scripts):
    mutate_file(scripts / "mozart_contract.py", "home=grant.passwd_home()", 'home=os.environ.get("HOME", "/")')


def append_to(scripts, module, text):
    path = scripts / module
    path.write_text(path.read_text() + text)


def mutation_attr_context(scripts):
    append_to(scripts, "mozart_state.py", "\n_ctx = contract.Context(home='/', environ={})\n")


def mutation_direct_import(scripts):
    append_to(scripts, "mozart_state.py", "\nimport mozart_contract\n")


def mutation_environ_import(scripts):
    append_to(scripts, "mozart_state.py", "\nfrom os import environ\n")


def mutation_nonconstant_loader(scripts):
    append_to(scripts, "mozart_state.py", "\n_name = 'mozart_grant'\nload_sibling(_name)\n")


def mutation_boot_group_mask(scripts):
    mutate_file(scripts / "mozart-resources.py", "not info.st_mode & 0o022", "not info.st_mode & 0o002")


def mutation_boot_owner(scripts):
    mutate_file(scripts / "mozart-resources.py", "info.st_uid == os.geteuid()", "True")


def mutation_grant_back_edge(scripts):
    path = scripts / "mozart_grant.py"
    path.write_text(path.read_text() + "\nimport mozart_contract\n")


def mutation_context_outside_production(scripts):
    path = scripts / "mozart_state.py"
    path.write_text(path.read_text() + "\n_ctx = Context(home='/', environ={})\n")


# --- V41_registry --------------------------------------------------------------------------------------------

def hook_setup(env, mode, response=None, label="hooks"):
    """A copy of the fixture hook in its own 0700 directory, with a mode file and an optional response."""
    folder = hook_scratch(label)
    shutil.copy2(STUBS / "hook", folder / "inventory-hook")
    os.chmod(folder / "inventory-hook", 0o755)
    (folder / "hook.mode").write_text(mode)
    if response is not None:
        (folder / "hook.response").write_text(response if isinstance(response, str) else json.dumps(response))
    return folder / "inventory-hook"


def discover_home(env, mode="ok", response=None, grant_extra="", registry=None, label="disc"):
    hook = hook_setup(env, mode, response)
    grant = f"## Remote execution\n- enabled: true\n{grant_extra}\n## Discovery hooks\n- inv: {hook}\n"
    return make_home(env, grant=grant, registry=registry, label=label), hook


def resource_files(home):
    """Relative paths of every regular file under resources/ (symlinks listed too)."""
    root = home / ".mozart" / "resources"
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        for name in filenames + [d for d in dirnames if os.path.islink(os.path.join(dirpath, d))]:
            found.append(os.path.relpath(os.path.join(dirpath, name), root))
    return sorted(found)


def case_discover(env):
    problems = []
    ok = fixture_json("discover-ok.fixture")
    stamp = "2026-10-26T12:00:00Z"
    labels = ["../x", "a/b", ".", "x.y", "a" * 64, ""]
    hostile = [(f"label {lab!r}", {"hosts": [{"label": lab, "probed_at": stamp, "facts": {"os": "linux"}}]}) for lab in labels]
    hostile += [("facts {enabled: true}", fixture_json("discover-hostile-facts.fixture")), ("an address key on a host", fixture_json("discover-hostile-address.fixture"))]
    modes = (("refused", 3), ("provider", 4), ("junk", 4), ("dup", 4), ("silent", 4), ("huge", 4))
    jobs = [("good", discover_home(env, response=ok)[0]), ("dynamic", discover_home(env, response=fixture_json("discover-dynamic.fixture"), label="dyn")[0])]
    jobs += [(name, discover_home(env, response=resp, label="lab")[0]) for name, resp in hostile]
    jobs += [(f"mode {mode}", discover_home(env, mode=mode, label="mode")[0]) for mode, _ in modes]
    outs = dict(zip([j[0] for j in jobs], many_discovers(env, [j[1] for j in jobs])))
    homes = dict(jobs)

    out, home = outs["good"], homes["good"]
    files = resource_files(home)
    if out["code"] != 0 or out["out"]["hooks"]["inv"].get("written") != ["mini.inv.json", "web.inv.json"]:
        problems.append(f"discover with a good hook: {out}")
    if [f for f in files if f not in ("grant.md", "discovered/mini.inv.json", "discovered/web.inv.json")]:
        problems.append(f"discover wrote something other than discovered/<label>.<hook>.json: {files}")
    stored = json.loads((home / ".mozart" / "resources" / "discovered" / "web.inv.json").read_text()) if "discovered/web.inv.json" in files else {}
    if stored.get("facts") != ok["hosts"][0]["facts"] or stored.get("hook") != "inv":
        problems.append(f"the stored record differs from what the hook reported: {stored}")
    dyn_path = homes["dynamic"] / ".mozart" / "resources" / "discovered" / "web.inv.json"
    dyn = json.loads(dyn_path.read_text()) if dyn_path.exists() else {"facts": {"(missing)": 1}}
    if set(dyn["facts"]) != {"os"}:
        problems.append(f"dynamic and request-scoped facts must be dropped on persist, kept {sorted(dyn['facts'])}")
    for name, _ in hostile:
        left = [f for f in resource_files(homes[name]) if f.startswith("discovered")]
        error = outs[name]["out"]["hooks"]["inv"].get("error")
        if outs[name]["code"] == 0 or error != "hook-output" or left:
            problems.append(f"{name}: exit {outs[name]['code']}, error {error!r}, files {left}; want a refusal with nothing written")
    for mode, code in modes:
        res = outs[f"mode {mode}"]
        if res["code"] != code or [f for f in resource_files(homes[f"mode {mode}"]) if f.startswith("discovered")]:
            problems.append(f"a hook in mode {mode!r}: exit {res['code']}, want {code} and nothing written")
    env.notes.append("discover writes only discovered/<label>.<hook>.json; hostile labels, facts and keys refused; static facts only")
    return problems


def case_symlinks(env):
    """A symlink planted at a destination, or at discovered/ itself, is refused and never written through."""
    problems = []
    ok = fixture_json("discover-ok.fixture")
    home, _ = discover_home(env, response=ok, label="sym1")
    victim = Path(os.path.realpath(env.fresh("victim")))
    (victim / "target").write_text("untouched\n")
    discovered = home / ".mozart" / "resources" / "discovered"
    discovered.mkdir(mode=0o700)
    os.symlink(victim / "target", discovered / "web.inv.json")
    res = drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["discover"]}]})[0]
    if res["out"]["hooks"]["inv"].get("error") != "grant-hygiene" or (victim / "target").read_text() != "untouched\n":
        problems.append(f"a symlink at the destination: {res['out']['hooks']['inv']}, target {(victim / 'target').read_text()!r}")
    if (discovered / "mini.inv.json").exists():
        problems.append("a refused discover still wrote another host (the check must come before any write)")
    home2, _ = discover_home(env, response=ok, label="sym2")
    outside = Path(os.path.realpath(env.fresh("outside")))
    os.chmod(outside, 0o700)
    os.symlink(outside, home2 / ".mozart" / "resources" / "discovered")
    res = drive(env.scripts, "run_cli", {"home": str(home2), "calls": [{"argv": ["discover"]}]})[0]
    if res["out"]["hooks"]["inv"].get("error") != "grant-hygiene" or list(outside.iterdir()):
        problems.append(f"discover wrote through a symlinked discovered/ directory: {res['out']['hooks']['inv']}, outside {sorted(p.name for p in outside.iterdir())}")
    return problems


def case_layers(env):
    """Declared beats discovered (and says so), dispatchable needs host_key and identity, stale facts are marked."""
    problems = []
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq0uVu1rPzAh7P1nQw3Yx9c2d1m8k4f6s7t0u2v3w5x"
    registry = ("## Host: web\n- labels: os=linux,cpus=2\n- identity: " + "1" * 64 + "\n\n## Host: keyless\n- identity: " + "2" * 64 + "\n")
    grant = ("\n## Host: web\n- trust: owned\n- transport: ssh\n- permission_mode: default\n- max_budget_usd: 5\n- host_key: " + key +
             "\n\n## Host: keyless\n- trust: owned\n- transport: ssh\n- permission_mode: default\n- max_budget_usd: 5\n")
    ok = {"hosts": [{"label": lab, "probed_at": "2026-10-26T12:00:00Z", "facts": {"os": "darwin", "cpus": 8}} for lab in ("web", "keyless", "plain")]}
    home, _ = discover_home(env, response=ok, grant_extra=grant, registry=registry, label="layers")
    t0 = calendar.timegm(time.strptime(PROBE_STAMP, '%Y-%m-%dT%H:%M:%SZ'))
    fresh, old = [{"argv": ["show"], "now": t0 + 3600}, {"argv": ["show"], "now": t0 + 200 * 3600}]
    drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["discover"]}]})
    a, b = drive(env.scripts, "run_cli", {"home": str(home), "calls": [fresh, old]})
    hosts = a["out"]["hosts"]
    web = hosts["web"]
    if web["facts"]["os"] != {"value": "linux", "source": "declared", "stale": False} or web["facts"]["cpus"]["value"] != 2:
        problems.append(f"declared must beat discovered: {web['facts']}")
    if [c["fact"] for c in web["conflicts"]] != ["os", "cpus"] and sorted(c["fact"] for c in web["conflicts"]) != ["cpus", "os"]:
        problems.append(f"the disagreement is not reported: {web['conflicts']}")
    if not web["dispatchable"]:
        problems.append(f"a host with a host_key, a registry identity and an enabled grant must be dispatchable: {web['why_not']}")
    if hosts["keyless"]["dispatchable"] or not any("host_key" in w for w in hosts["keyless"]["why_not"]):
        problems.append(f"a host without a host_key must not be dispatchable: {hosts['keyless']['why_not']}")
    if hosts["plain"]["dispatchable"]:
        problems.append("a discovered-only host must not be dispatchable")
    if any(f["stale"] for f in web["facts"].values()) or any(not f["stale"] for h in b["out"]["hosts"].values() for k, f in h["facts"].items() if f["source"] != "declared"):
        problems.append("stale marking is wrong: fresh facts stale, or 200-hour-old discovered facts not stale")
    env.notes.append("declared beats discovered with the conflict reported; dispatchable needs host_key and identity; stale marked")
    return problems


def case_snapshots(env):
    problems = []
    home = make_home(env, grant=fixture_text("grant-minimal.fixture"), label="snap")
    first = drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["grant"]}]})[0]["out"]["sha256"]
    snap = home / ".mozart" / "resources" / "grant-snapshots" / f"{first}.md"
    if not snap.exists() or hashlib.sha256(snap.read_bytes()).hexdigest() != first:
        problems.append("`grant` did not keep a snapshot named by its own sha256")
    grant_path = home / ".mozart" / "resources" / "grant.md"
    grant_path.write_text(fixture_text("grant-minimal.fixture") + "- repos: /srv/a\n")
    diff = drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["grant", "--diff", first]}]})[0]
    if diff["code"] != 0 or not diff["out"]["changed"] or not any(line.startswith("+- repos") for line in diff["out"]["diff"]):
        problems.append(f"grant --diff did not show the change: {diff}")
    snap.write_text("forged\n")
    forged = drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["grant", "--diff", first]}]})[0]
    if forged["code"] == 0 or forged["out"].get("error") != "grant-hygiene":
        problems.append(f"a snapshot whose content does not hash to its name was used: {forged}")
    bads = ("abc", "A" * 64, "a" * 63, "../x", "g" * 64)
    answers = drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["grant", "--diff", bad]} for bad in bads]})
    for bad, res in zip(bads, answers):
        if res["code"] != 2 or res["out"].get("error") != "bad-request":
            problems.append(f"grant --diff {bad!r}: exit {res['code']}, {res['out'].get('error')!r}, want exit 2 bad-request")
    return problems


def mutation_follow_symlinks(scripts):
    mutate_file(scripts / "mozart_contract.py", "flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | _CLOEXEC", "flags = os.O_RDONLY | os.O_DIRECTORY | _CLOEXEC")


# --- V42_match -------------------------------------------------------------------------------------------------

def entry(value, stale=False, live=False):
    return {"value": value, "stale": stale, "live": live}


def match_table():
    xc = lambda v: {"xcodebuild": entry(v)}
    return [
        ("16.10 >= 16.9", "xcodebuild>=16.9", xc("16.10"), "match"),
        ("16.9 >= 16.10 is false", "xcodebuild>=16.10", xc("16.9"), "reject"),
        ("16.0 = 16", "xcodebuild=16", xc("16.0"), "match"),
        ("16 >= 16.0", "xcodebuild>=16.0", xc("16"), "match"),
        ("16.09 reads as (16, 9)", "xcodebuild>=16.09", xc("16.9"), "match"),
        ("v16 is not a version", "xcodebuild>=v16", xc("16"), "error"),
        ("16.0-beta is not a version", "xcodebuild>=16.0-beta", xc("16"), "error"),
        ("empty segment 16..1", "xcodebuild>=16..1", xc("16"), "error"),
        ("trailing dot 16.", "xcodebuild>=16.", xc("16"), "error"),
        ("huge versions compare", "xcodebuild>=99999999999999999999999", xc("1"), "reject"),
        ("a beta fact cannot satisfy a version", "xcodebuild>=16", xc("17.0-beta1"), "reject"),
        ("<= holds", "cpus<=8", {"cpus": entry(8)}, "match"),
        ("<= fails", "cpus<=8", {"cpus": entry(9)}, "reject"),
        ("!= holds", "cpus!=8", {"cpus": entry(4)}, "match"),
        ("!= fails", "cpus!=8", {"cpus": entry(8)}, "reject"),
        ("in matches an alternative", "os in linux|darwin", {"os": entry("darwin")}, "match"),
        ("in fails when none match", "os in linux|darwin", {"os": entry("windows")}, "reject"),
        ("in against null is unknown", "os in linux", {"os": entry(None)}, "unknown"),
        ("a bare key against null fails", "docker", {"docker": entry(None)}, "reject"),
        ("a bare key against a value holds", "docker", {"docker": entry("24.0.7")}, "match"),
        ("a bare key against a missing fact is unknown", "docker", {}, "unknown"),
        ("!= against a missing fact is unknown", "cpus!=8", {}, "unknown"),
        (">= against null is unknown", "cpus>=8", {"cpus": entry(None)}, "unknown"),
        ("<= against a missing fact is unknown", "cpus<=8", {}, "unknown"),
        ("the empty list", "", {}, "error"),
        ("a doubled comma", "os=darwin,,cpus=8", {}, "error"),
        ("a leading space", " os=darwin", {}, "error"),
        ("a space after the comma", "os=darwin, cpus=8", {}, "error"),
        ("spaces around the operator", "os = darwin", {}, "error"),
        ("a repeated key", "os=darwin,os=linux", {}, "error"),
        ("in with no alternatives", "os in ", {}, "error"),
        ("in with an empty alternative", "os in a||b", {}, "error"),
        ("in with a trailing empty alternative", "os in a|", {}, "error"),
        ("a value containing =", "os=dar=win", {}, "error"),
        ("case is significant", "os=Darwin", {"os": entry("darwin")}, "reject"),
        ("a non-ASCII value", "os=därwin", {}, "error"),
        ("an unknown fact", "nope=1", {}, "error"),
        ("an unknown taint is accepted", "os=darwin", {"os": entry("darwin")}, "match", {"tolerates": ["zzz"]}),
        ("tolerates= inside a phase requirement is refused too", "os=darwin,tolerates=gpu", {"os": entry("darwin")}, "error"),
        (">= and = are different tokens", "cpus>=8", {"cpus": entry(8)}, "match"),
        ("cpus=8 is an integer", "cpus=8", {"cpus": entry(8)}, "match"),
        ("a quoted integer is not an integer", 'cpus="8"', {"cpus": entry(8)}, "error"),
        ("a fractional integer is not an integer", "cpus=8.0", {"cpus": entry(8)}, "error"),
        ("mem_gb>=16 rejects 15.9", "mem_gb>=16", {"mem_gb": entry(15.9)}, "reject"),
        ("mem_gb>=15.9 accepts 15.9", "mem_gb>=15.9", {"mem_gb": entry(15.9)}, "match"),
        ("mem_gb=16 accepts 16.0", "mem_gb=16", {"mem_gb": entry(16.0)}, "match"),
        (">= on a string fact", "os>=1", {"os": entry("darwin")}, "error"),
        ("a dynamic fact without a live identify is unknown", "keychain_unlocked=true", {"keychain_unlocked": entry(True)}, "unknown"),
        ("a dynamic fact from a live identify holds", "keychain_unlocked=true", {"keychain_unlocked": entry(True, live=True)}, "match"),
        ("a stale fact is unknown", "cpus>=1", {"cpus": entry(8, stale=True)}, "unknown"),
        ("a list fact holds a flag", "claude_flags=--print", {"claude_flags": entry(["--print"])}, "match"),
        ("a list fact lacks a flag", "claude_flags=--print", {"claude_flags": entry([])}, "reject"),
        ("kube: membership true", "kube_contexts=ctx-a", {"kube_contexts": entry({"ctx-a": True})}, "match"),
        ("kube: membership false", "kube_contexts=ctx-a", {"kube_contexts": entry({"ctx-a": False})}, "reject"),
        ("kube: a name nobody asked about is unknown", "kube_contexts=ctx-a", {"kube_contexts": entry({})}, "unknown"),
        ("kube: != holds for a false name", "kube_contexts!=ctx-a", {"kube_contexts": entry({"ctx-a": False})}, "match"),
        ("kube: != fails for a true name", "kube_contexts!=ctx-a", {"kube_contexts": entry({"ctx-a": True})}, "reject"),
        ("kube: in finds one true", "kube_contexts in a|b", {"kube_contexts": entry({"a": False, "b": True})}, "match"),
        ("kube: the bare key means kubectl answered", "kube_contexts", {"kube_contexts": entry({})}, "match"),
        ("kube: >= is a vocabulary error", "kube_contexts>=a", {}, "error"),
        ("a taint repels", "os=darwin", {"os": entry("darwin")}, "reject", {"taints": ["gpu"]}),
        ("a toleration passed by the caller admits it", "os=darwin", {"os": entry("darwin")}, "match", {"taints": ["gpu"], "tolerates": ["gpu"]}),
        ("a repo stanza cannot tolerate: tolerates= is refused", "tolerates=gpu", {}, "error"),
        ("a repo stanza may require", "os=darwin", {"os": entry("darwin")}, "match"),
    ]


def case_table(env):
    table = match_table()
    cases = []
    for i, row in enumerate(table):
        extra = row[4] if len(row) > 4 else {}
        cases.append(dict({"id": str(i), "requires": row[1], "entries": row[2]}, **extra))
    got = drive(env.scripts, "matcher_batch", {"cases": cases})
    problems = []
    for i, row in enumerate(table):
        res = got[str(i)]
        verdict = "error" if "error" in res else res["verdict"]
        if verdict != row[3]:
            problems.append(f"{row[0]}: {row[1]!r} gave {verdict} ({res.get('error') or res.get('reasons')}), want {row[3]}")
    if len(table) < 40:
        problems.append(f"{len(table)} match cases, floor 40")
    if not any(r[0] == "16.10 >= 16.9" for r in table):
        problems.append("the named member '16.10 >= 16.9' is missing")
    env.notes.append(f"{len(table)} matcher cases")
    return problems


def case_properties(env):
    bad = drive(env.scripts, "matcher_properties", {"seed": 20261026, "n": 500})
    env.notes.append("500 seeded property cases")
    return [f"property: {b}" for b in bad[:5]]


def case_match_cli(env):
    """match through the CLI: exit codes, the stanza rule, kube membership asked of this machine, a dispatchable host."""
    problems = []
    schema = env.schema
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq0uVu1rPzAh7P1nQw3Yx9c2d1m8k4f6s7t0u2v3w5x"
    grant = ("## Remote execution\n- enabled: true\n\n## Host: mini\n- trust: owned\n- transport: ssh\n- permission_mode: default\n"
             "- max_budget_usd: 5\n- host_key: " + key + "\n")
    registry = "## Host: mini\n- labels: os=darwin,cpus=10\n- identity: " + "1" * 64 + "\n"
    home = make_home(env, grant=grant, registry=registry, label="matchcli")
    local = probe_doc(schema, os="linux", cpus=4)
    calls = [
        {"argv": ["match", "--requires", "os=darwin"], "probe_doc": local},
        {"argv": ["match", "--requires", "os=windows"], "probe_doc": local},
        {"argv": ["match", "--requires", "os=linux"], "probe_doc": local},
        {"argv": ["match", "--requires", "os=darwin,,cpus=1"], "probe_doc": local},
        {"argv": ["match", "--requires", "tolerates=gpu", "--source", "stanza"], "probe_doc": local},
        {"argv": ["match", "--requires", "kube_contexts=known"], "probe_doc": local, "known_contexts": ["known"]},
        {"argv": ["match", "--requires", "kube_contexts=other"], "probe_doc": local, "known_contexts": ["known"]},
        {"argv": ["match", "--requires", "os=darwin"], "probe_fail": True},
    ]
    res = drive(env.scripts, "run_cli", {"home": str(home), "calls": calls})
    codes = [r["code"] for r in res]
    if codes != [0, 3, 0, 2, 2, 0, 3, 0]:
        problems.append(f"match exit codes are {codes}, want [0, 3, 0, 2, 2, 0, 3, 0]")
    first = res[0]["out"]
    if [m["label"] for m in first["matches"]] != ["mini"] or not first["matches"][0]["dispatchable"] or first["local"]["matches"]:
        problems.append(f"a dispatchable registry host should match where this machine does not: {first}")
    if not res[5]["out"]["local"]["matches"] or res[6]["out"]["local"]["matches"]:
        problems.append("kube membership asked of this machine is wrong")
    if res[7]["out"]["local"]["matches"] or "failed" not in res[7]["out"]["local"]["reasons"][0]:
        problems.append(f"a failed local probe must read as no local match with a reason: {res[7]['out']['local']}")
    return problems


def mutation_string_versions(scripts):
    mutate_file(scripts / "mozart-resources.py", "        return tuple(parts)", "        return raw")


# --- phase 2 review fixes: hard refusals, hooks, robustness, concurrency, modes, layers, probe gate ------------

HOOK_SCRATCH = {"path": None, "n": 0, "lock": threading.Lock()}


def chain_clean(path):
    """The hook hygiene rule's directory half, restated here so the scratch location is chosen
    independently of the code under test: every ancestor is the user's or root's, writable by neither
    group nor world, and not a git work tree."""
    cur = os.path.realpath(path)
    while True:
        st = os.stat(cur)
        if st.st_uid not in (os.geteuid(), 0) or st.st_mode & 0o022 or os.path.lexists(os.path.join(cur, ".git")):
            return False
        if cur == os.path.dirname(cur):
            return True
        cur = os.path.dirname(cur)


def hook_scratch(label):
    """A 0700 directory for a hook whose whole directory chain the hook hygiene rule accepts: the system
    temp directory when that is clean (macOS), else the account's home (Linux /tmp is world-writable).
    Removed when the checker exits, however it exits."""
    with HOOK_SCRATCH["lock"]:
        if STOPPING.is_set():
            raise Deadline()
        if HOOK_SCRATCH["path"] is None:
            for candidate in (tempfile.gettempdir(), pwd.getpwuid(os.geteuid()).pw_dir):
                made = Path(os.path.realpath(tempfile.mkdtemp(prefix=".mz-check-hooks-", dir=candidate)))
                if chain_clean(made):
                    HOOK_SCRATCH["path"] = made
                    break
                shutil.rmtree(made, ignore_errors=True)
            else:
                raise RuntimeError("no scratch location satisfies the hook hygiene rule (a git work tree or a writable directory above every candidate)")
        HOOK_SCRATCH["n"] += 1
        folder = HOOK_SCRATCH["path"] / f"{label}-{HOOK_SCRATCH['n']}"
    folder.mkdir()
    os.chmod(folder, 0o700)
    return folder


def drop_hook_scratch():
    with HOOK_SCRATCH["lock"]:
        if HOOK_SCRATCH["path"] is not None:
            shutil.rmtree(HOOK_SCRATCH["path"], ignore_errors=True)
            HOOK_SCRATCH["path"] = None


def plant_discovered(home, label, hook, facts, probed_at=PROBE_STAMP, mode=0o600, pad=0):
    directory = home / ".mozart" / "resources" / "discovered"
    directory.mkdir(exist_ok=True)
    os.chmod(directory, 0o700)
    path = directory / f"{label}.{hook}.json"
    path.write_text(json.dumps({"label": label, "hook": hook, "probed_at": probed_at, "facts": facts}) + "\n" + " " * pad)
    os.chmod(path, mode)
    return path


def epoch(stamp):
    return calendar.timegm(time.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ"))


def one_discover(env, home):
    return drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["discover"]}]})[0]


def many_discovers(env, homes):
    """discover against several homes in ONE interpreter: starting Python is most of what a case costs."""
    return drive(env.scripts, "run_cli", {"calls": [{"argv": ["discover"], "home": str(h)} for h in homes]})


# --- verb-level hard refusals ---------------------------------------------------------------------------------

def case_hard_refusals(env):
    """A child session, a mismatched HOME, a hygiene-bad grant and an invalid grant refuse every verb
    before the registry is read or a probe is started. The registry used here is invalid on purpose: if it
    were read first the answer would be registry-invalid instead of the grant's own code."""
    problems = []
    minimal = fixture_text("grant-minimal.fixture")
    bad_registry = "## Host: a\n- enabled: true\n"
    other = env.fresh("elsewhere")

    def home_with(label, grant=minimal, mode=None):
        home = make_home(env, grant=grant, registry=bad_registry, label=label)
        if mode:
            os.chmod(home / ".mozart" / "resources" / "grant.md", mode)
        return home
    states = [
        ("MOZART_CHILD_SESSION", home_with("hr1"), lambda h: {"HOME": str(h), "MOZART_CHILD_SESSION": "c"}, "child-session"),
        ("MOZART_LAUNCH_CHILD", home_with("hr2"), lambda h: {"HOME": str(h), "MOZART_LAUNCH_CHILD": "1"}, "child-session"),
        ("a mismatched HOME", home_with("hr3"), lambda h: {"HOME": str(other)}, "home-mismatch"),
        ("a group-writable grant", home_with("hr4", mode=0o666), lambda h: {"HOME": str(h)}, "grant-hygiene"),
        ("an invalid grant", home_with("hr5", grant="garbage\n"), lambda h: {"HOME": str(h)}, "grant-invalid"),
    ]
    verbs = [["show"], ["match", "--requires", "os=darwin"], ["facts", "--local"], ["grant", "--diff", "a" * 64], ["discover"]]
    doc = probe_doc(env.schema, os="darwin")
    jobs = []
    for name, home, environ, code in states:
        marker = Path(env.fresh("marker")) / "probe"
        calls = [dict(argv=v, home=str(home), environ=environ(home), probe_doc=doc, probe_marker=str(marker)) for v in verbs]
        jobs.append((name, code, marker, calls, home))
    flat = drive(env.scripts, "run_cli", {"calls": [c for j in jobs for c in j[3]]})
    for index, (name, code, marker, _, _) in enumerate(jobs):
        for verb, res in zip(verbs, flat[index * len(verbs):(index + 1) * len(verbs)]):
            if res["code"] != 3 or res["out"].get("error") != code:
                problems.append(f"hard refusal {name} / {verb[0]}: exit {res['code']}, error {res['out'].get('error')!r}, want exit 3 and {code!r}")
        if marker.exists():
            problems.append(f"hard refusal {name}: a probe was started")
    # the contrast that makes the above mean something: with no hard refusal the same verbs do read the registry and start the probe
    free = home_with("hr0")
    marker = Path(env.fresh("marker")) / "probe"
    open_calls = drive(env.scripts, "run_cli", {"home": str(free), "calls": [
        dict(argv=["show"], probe_doc=doc, probe_marker=str(marker)), dict(argv=["facts", "--local"], probe_doc=doc, probe_marker=str(marker))]})
    if open_calls[0]["out"].get("error") != "registry-invalid" or not marker.exists():
        problems.append(f"hard refusal contrast: without one, show should read the registry and facts should probe: {open_calls[0]['out'].get('error')!r}, probe {marker.exists()}")
    env.notes.append("5 hard-refusal states x 5 verbs: exit 3, the grant's code, no registry read, no probe")
    return problems


def mutation_no_hard_refusals(scripts):
    mutate_file(scripts / "mozart-resources.py", 'HARD_REFUSALS = ("child-session", "home-mismatch", "grant-hygiene", "grant-invalid")', "HARD_REFUSALS = ()")


# --- hooks -------------------------------------------------------------------------------------------------------

def make_hook(mode="ok", response=None, dir_mode=0o700, file_mode=0o755, parent=None):
    folder = hook_scratch("hk") if parent is None else parent
    path = folder / "inventory-hook"
    shutil.copy2(STUBS / "hook", path)
    os.chmod(path, file_mode)
    (folder / "hook.mode").write_text(mode)
    if response is not None:
        (folder / "hook.response").write_text(json.dumps(response))
    os.chmod(folder, dir_mode)
    return path


def hook_grant(path, provider=""):
    text = f"## Remote execution\n- enabled: true\n\n## Discovery hooks\n- inv: {path}\n"
    if provider is not None and provider != "":
        text += f"\n## Provider: p1\n- hook: {path}\n- max_leases: 1\n- max_lease_hours: 1\n- daily_cost_ceiling_usd: 1\n{provider}"
    return text


def case_hooks(env):
    """A hook runs only if its path, its directory chain and its digest are trustworthy, and only for as
    long as its timeout; every refusal writes nothing."""
    problems = []
    ok = fixture_json("discover-ok.fixture")

    def scenario(name):
        if name == "a good hook":
            path = make_hook(response=ok)
            return make_home(env, grant=hook_grant(path)), None, 0
        if name == "a symlinked hook":
            real = make_hook(response=ok)
            link = hook_scratch("lk") / "inventory-hook"
            os.symlink(real, link)
            return make_home(env, grant=hook_grant(link)), "hook-hygiene", 3
        if name == "a group-writable hook":
            return make_home(env, grant=hook_grant(make_hook(response=ok, file_mode=0o775))), "hook-hygiene", 3
        if name == "a group-writable ancestor directory":
            return make_home(env, grant=hook_grant(make_hook(response=ok, dir_mode=0o770))), "hook-hygiene", 3
        if name == "a sticky world-writable ancestor":
            top = hook_scratch("st")
            os.chmod(top, 0o1777)  # like /tmp: world-writable with the sticky bit, which is no exemption
            sub = top / "sub"
            sub.mkdir(mode=0o700)
            return make_home(env, grant=hook_grant(make_hook(response=ok, parent=sub))), "hook-hygiene", 3
        if name == "a group-writable parent two levels up":
            top = hook_scratch("gw")
            sub = top / "mid" / "sub"
            sub.mkdir(parents=True, mode=0o700)
            os.chmod(top, 0o770)
            return make_home(env, grant=hook_grant(make_hook(response=ok, parent=sub))), "hook-hygiene", 3
        if name == "a hook inside a git work tree":
            repo = hook_scratch("repo")
            (repo / ".git").mkdir()
            sub = repo / "sub"
            sub.mkdir(mode=0o700)
            return make_home(env, grant=hook_grant(make_hook(response=ok, parent=sub))), "hook-hygiene", 3
        if name == "a sha mismatch":
            path = make_hook(response=ok)
            return make_home(env, grant=hook_grant(path, f"- hook_sha256: {'0' * 64}\n")), "hook-hygiene", 3
        if name == "a matching sha":
            path = make_hook(response=ok)
            return make_home(env, grant=hook_grant(path, f"- hook_sha256: {hashlib.sha256(path.read_bytes()).hexdigest()}\n")), None, 0
        if name == "the runner's cwd and HOME":
            path = make_hook(mode="env")
            return make_home(env, grant=hook_grant(path)), None, 0
        if name == "a hang":
            path = make_hook(mode="hang")
            return make_home(env, grant=hook_grant(path, "- hook_timeout_s: 1\n")), "timeout", 4
        path = make_hook(response=ok)  # a relative path never reaches a hook: the grant itself is invalid
        return make_home(env, grant=hook_grant("relative/inventory-hook")), "grant-invalid", 3

    names = [n for n in ["a good hook", "a symlinked hook", "a group-writable hook", "a group-writable ancestor directory", "a sticky world-writable ancestor",
                         "a group-writable parent two levels up", "a hook inside a git work tree", "a sha mismatch", "a matching sha", "the runner's cwd and HOME", "a hang", "a relative path"] if env.wants(n) or n == "a good hook"]
    built = [scenario(n) for n in names]
    outs = many_discovers(env, [b[0] for b in built])
    for name, (home, error, code), res in zip(names, built, outs):
        wrote = [f for f in resource_files(home) if f.startswith("discovered")]
        if name == "the runner's cwd and HOME":
            folder = Path(re.search(r"^## Discovery hooks\n- inv: (.*)$", (home / ".mozart" / "resources" / "grant.md").read_text(), re.M).group(1)).parent
            seen_cwd = os.path.realpath((folder / "hook.cwd").read_text().strip()) if (folder / "hook.cwd").exists() else None
            seen_home = (folder / "hook.home").read_text() if (folder / "hook.home").exists() else None
            if seen_cwd != os.path.realpath(home / ".mozart" / "resources" / "run" / "tmp") or seen_home != str(home):
                problems.append(f"hook scenario {name!r}: the hook ran in {seen_cwd!r} with HOME {seen_home!r}, want the resources run/tmp directory and the Context's home")
            wrote = ["(not applicable)"]
            continue
        got = res["out"].get("error") if error == "grant-invalid" else res["out"].get("hooks", {}).get("inv", {}).get("error")
        if res["code"] != code or got != error or (error and wrote) or (not error and not wrote):
            problems.append(f"hook scenario {name!r}: exit {res['code']}, error {got!r}, wrote {wrote}; want exit {code}, error {error!r}, {'nothing' if error else 'files'} written")
    odd = hook_scratch("odd")
    answers = {} if env.focus else drive(env.scripts, "hook_hygiene_batch", {"paths": ["", "relative/hook", "hook", "/nonexistent/hook", f"{odd}/../x", str(make_hook(response=ok)), str(odd / "nothing-here")]})
    for path, why in answers.items():
        good = path.endswith("inventory-hook")
        if (why is None) != good:
            problems.append(f"hook scenario 'hook_hygiene on {path!r}': reason {why!r}, want {'none' if good else 'a refusal'}")
    env.notes.append(f"{len(names)} hook scenarios plus 7 raw paths")
    return problems


def mutation_no_sha_compare(scripts):
    mutate_file(scripts / "mozart_contract.py", "if expect_sha and digest != expect_sha:", "if False:")


def mutation_no_hook_hygiene(scripts):
    mutate_file(scripts / "mozart_contract.py", "digest, why = hook_hygiene(path, ctx.fstat())", "digest, why = None, None")


def mutation_no_git_refusal(scripts):
    mutate_file(scripts / "mozart_contract.py", 'if os.path.lexists(os.path.join(parent, ".git")):', "if False:")


def mutation_no_timeout_flag(scripts):
    mutate_file(scripts / "mozart_contract.py", 'flag.append("timeout")', "pass")


# --- one bad record must not take the registry down ------------------------------------------------------------------

def case_robust(env):
    problems = []
    ok = fixture_json("discover-ok.fixture")
    stamp_bad = "2026-13-45T25:61:61Z"
    hook = make_hook(response={"hosts": [{"label": "web", "probed_at": stamp_bad, "facts": {"os": "linux"}}]})
    home = make_home(env, grant=hook_grant(hook), label="rob1")
    res = one_discover(env, home)
    if res["code"] == 0 or res["out"]["hooks"]["inv"].get("error") != "hook-output" or [f for f in resource_files(home) if f.startswith("discovered")]:
        problems.append(f"an impossible probed_at from a hook was not refused with nothing written: {res['out']}")

    home = make_home(env, grant="## Remote execution\n- enabled: true\n", label="rob2")
    plant_discovered(home, "good", "inv", {"os": "linux"})
    plant_discovered(home, "baddate", "inv", {"os": "linux"}, probed_at=stamp_bad)
    plant_discovered(home, "huge", "inv", {"os": "linux"}, pad=70000)
    plant_discovered(home, "loose", "inv", {"os": "linux"}, mode=0o664)
    shown = drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["show"]}]})[0]
    if shown["code"] != 0 or list(shown["out"].get("hosts", {})) != ["good"]:
        problems.append(f"one bad discovered file took the registry down or leaked into it: exit {shown['code']}, hosts {list(shown['out'].get('hosts', {}))}")
    listed = " ".join(shown["out"].get("problems", []))
    for name in ("baddate", "huge", "loose"):
        if f"discovered/{name}.inv.json" not in listed:
            problems.append(f"the bad discovered file {name!r} is not reported as a per-file problem: {listed[:200]}")

    hostile = '"' * 59 + "\\" * 59 + "é'"  # 120 characters of quotes and backslashes: printable, awkward in a reason
    home = make_home(env, grant="## Remote execution\n- enabled: true\n", registry="## Host: web\n- identity: " + "1" * 64 + "\n", label="rob3")
    plant_discovered(home, "web", "inv", {"gpu_name": hostile})
    res = drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["match", "--requires", "gpu_name=x"], "probe_doc": probe_doc(env.schema)}]})[0]
    reasons = [r for item in res["out"].get("rejects", []) for r in item["reasons"]]
    if res["code"] != 3 or res["out"].get("error") or not reasons or any(len(r) > 200 for r in reasons) or any(hostile in r for r in reasons):
        problems.append(f"a hostile gpu_name in a match reason raised or was echoed whole: exit {res['code']}, {res['out'].get('error')}, {[len(r) for r in reasons]}")
    env.notes.append("an impossible date, an oversize or loose file and a hostile fact are per-record problems")
    return problems


# --- the descriptor helpers under contention ---------------------------------------------------------------------------

def case_concurrency(env):
    problems = []
    home = make_home(env, label="conc")
    n, rounds = 6, 8
    shared = home / ".mozart" / "resources" / "shared"
    if env.focus != "tmp":
        results = env.pmap(lambda i: drive(env.scripts, "hammer", {"home": str(home), "who": i, "rounds": rounds}), list(range(n)))
        errors = [e for r in results for e in r]
        if errors:
            problems.append(f"concurrent writers hit {len(errors)} error(s), first: {errors[0]}")
        final = (shared / "a.json").read_text().splitlines() if (shared / "a.json").exists() else []
        if len(final) != 2000 or len(set(final)) != 1 or not (shared / "a.json.b").exists():
            problems.append(f"the final file is missing or is a mixture of writers: {len(final)} lines, {len(set(final))} distinct")
        left = [e for e in os.listdir(shared) if e.endswith(".tmp")]
        if left:
            problems.append(f"temp files left behind after every writer finished: {left[:3]}")
    else:
        shared.mkdir(parents=True)
        os.chmod(shared, 0o700)
    dead = subprocess.Popen(["/usr/bin/true"])
    dead.wait()
    live = os.getpid()
    names = {"huge_pid": ".a.json.99999999999999999999.00000000.tmp", "mine_dead": f".a.json.{dead.pid}.00000000.tmp", "mine_live": f".a.json.{live}.00000000.tmp", "other_dead": f".a.json.b.{dead.pid}.00000000.tmp"}
    for fname in names.values():
        (shared / fname).write_text("x")
    drive(env.scripts, "write_one", {"home": str(home), "parts": ["shared"], "name": "a.json", "data": "again\n"})
    long_name = "a" * 63 + "." + "b" * 63 + ".json"  # a legal <label>.<hook>.json: 132 characters
    drive(env.scripts, "write_one", {"home": str(home), "parts": ["shared"], "name": long_name, "data": "x\n"})
    if not (shared / long_name).exists():
        problems.append("a legal <63>.<63>.json file name was refused")
    present = {k: (shared / v).exists() for k, v in names.items()}
    if not present["huge_pid"]:
        problems.append("a temp file whose pid field is not a pid was touched (or the writer crashed on it)")
    if present["mine_dead"]:
        problems.append("a dead writer's temp file for this name was not cleaned up")
    if not present["mine_live"]:
        problems.append("a live writer's temp file was removed")
    if not present["other_dead"]:
        problems.append("another name's temp file was removed by a writer of a name that merely prefixes it")
    env.notes.append(f"{n} concurrent writers x {rounds} rounds, no error and no lost file; temp cleanup is exact")
    return problems


def mutation_tmp_any_writer(scripts):
    mutate_file(scripts / "mozart_contract.py", "if not _pid_alive(int(m.group(1))) or time.time() - os.lstat(entry, dir_fd=fd).st_mtime > STALE_TMP_S:", "if True:")


def mutation_tmp_prefix(scripts):
    mutate_file(scripts / "mozart_contract.py", "m = pattern.fullmatch(entry)", 'm = re.fullmatch(rf"\\.{re.escape(name)}\\.(?:[a-z0-9.]*?)([0-9]+)\\.[0-9a-f]{{8}}\\.tmp", entry)')


def case_stalled_stdin(env):
    home = make_home(env, label="stall")
    try:
        got = drive(env.scripts, "stalled_stdin", {"home": str(home), "timeout": 1}, timeout=4)
    except RuntimeError as exc:
        return [f"stalled stdin: the runner did not honor its timeout: {str(exc)[:120]}"]
    problems = []
    if got["flag"] != "timeout" or got["secs"] > 6:
        problems.append(f"a child that never reads stdin: flag {got['flag']!r} after {got['secs']:.1f}s, want a timeout within the budget")
    return problems


def mutation_blocking_stdin(scripts):
    mutate_file(scripts / "mozart_contract.py", "        writer.start()", "        feed()")


def case_collisions(env):
    """Two labels that differ only in case are refused wherever labels meet: the grant, the registry, a hook's response."""
    problems = []
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq0uVu1rPzAh7P1nQw3Yx9c2d1m8k4f6s7t0u2v3w5x"
    block = "\n## Host: {}\n- trust: owned\n- transport: ssh\n- permission_mode: default\n- max_budget_usd: 5\n- host_key: " + key + "\n"
    base = "## Remote execution\n- enabled: true\n"
    ok = {"hosts": [{"label": lab, "probed_at": PROBE_STAMP, "facts": {"os": "linux"}} for lab in ("Web", "web")]}
    hook = make_hook(response=ok)
    cases = [
        ("two grant hosts", make_home(env, grant=base + block.format("Web") + block.format("web"), label="col1"), "show", "grant-invalid"),
        ("two discovery hooks", make_home(env, grant=base + "\n## Discovery hooks\n- Inv: /srv/a\n- inv: /srv/b\n", label="col2"), "show", "grant-invalid"),
        ("two registry hosts", make_home(env, grant=base, registry="## Host: Web\n- cost: free\n\n## Host: web\n- cost: free\n", label="col3"), "show", "registry-invalid"),
        ("a registry host and a grant block", make_home(env, grant=base + block.format("web"), registry="## Host: Web\n- cost: free\n", label="col4"), "show", "registry-invalid"),
    ]
    outs = drive(env.scripts, "run_cli", {"calls": [{"argv": [c[2]], "home": str(c[1])} for c in cases]})
    for (name, _, _, code), res in zip(cases, outs):
        if res["code"] != 3 or res["out"].get("error") != code:
            problems.append(f"label collision, {name}: exit {res['code']}, error {res['out'].get('error')!r}, want exit 3 and {code!r}")
    home = make_home(env, grant=hook_grant(hook), label="col5")
    res = one_discover(env, home)
    if res["code"] == 0 or [f for f in resource_files(home) if f.startswith("discovered")]:
        problems.append("a hook response with labels Web and web was accepted")

    # a stale or hostile DISCOVERED record that collides with a declared host is only a problem entry
    registry = "## Host: mini\n- labels: os=darwin\n- identity: " + "1" * 64 + "\n"
    home = make_home(env, grant=base, registry=registry, label="col6")
    plant_discovered(home, "MINI", "inv", {"os": "linux"})
    plant_discovered(home, "other", "inv", {"os": "linux"})
    shown, matched = drive(env.scripts, "run_cli", {"home": str(home), "calls": [
        {"argv": ["show"]}, {"argv": ["match", "--requires", "os=darwin"], "probe_doc": probe_doc(env.schema, os="linux")}]})
    if shown["code"] != 0 or sorted(shown["out"].get("hosts", {})) != ["mini", "other"]:
        problems.append(f"a discovered label that collides with a declared one took show down: exit {shown['code']}, {shown['out'].get('error') or sorted(shown['out'].get('hosts', {}))}")
    elif "MINI" not in " ".join(shown["out"]["problems"]) or shown["out"]["hosts"]["mini"]["facts"]["os"]["value"] != "darwin":
        problems.append("the collision is not reported as a problem, or the declared host lost its facts")
    if matched["code"] not in (0, 3) or matched["out"].get("error"):
        problems.append(f"a discovered label that collides with a declared one took match down: {matched['out'].get('error')}")
    hook = make_hook(response={"hosts": [{"label": "MINI", "probed_at": PROBE_STAMP, "facts": {"os": "linux"}}]})
    home = make_home(env, grant=hook_grant(hook), registry=registry, label="col7")
    res = one_discover(env, home)
    if res["code"] == 0 or [f for f in resource_files(home) if f.startswith("discovered")]:
        problems.append("a hook response label MINI was written although a declared host mini exists (a hook response label)")
    return problems


# --- modes ----------------------------------------------------------------------------------------------------------

def case_modes(env):
    """Files are 0600 and directories 0700 whatever the umask (the driver runs with umask 0)."""
    problems = []
    hook = make_hook(response=fixture_json("discover-ok.fixture"))
    home = make_home(env, grant=hook_grant(hook), label="modes")
    drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["discover"]}, {"argv": ["grant"]}]})
    resources = home / ".mozart" / "resources"
    for rel in ("discovered", "grant-snapshots", "run", "run/tmp"):
        if not (resources / rel).is_dir():
            problems.append(f"mode: directory {rel} was not created")
            continue
        mode = stat.S_IMODE(os.stat(resources / rel).st_mode)
        if mode != 0o700:
            problems.append(f"mode: directory {rel} is {oct(mode)}, want 0o700")
    for rel in sorted(p for p in resource_files(home) if p != "grant.md"):
        mode = stat.S_IMODE(os.stat(resources / rel).st_mode)
        if mode != 0o600:
            problems.append(f"mode: file {rel} is {oct(mode)}, want 0o600")
    return problems


def mutation_collision_fatal(scripts):
    mutate_file(scripts / "mozart_state.py", """    discovered, clashes = drop_colliding(declared, discovered)  # a stale or hostile record is only a problem entry
    problems = problems + clashes
""", """    if collisions(set(declared) | set(discovered)):
        raise contract.ContractError("registry-invalid", "host labels collide when case is folded")
""")


def mutation_persist_no_known(scripts):
    mutate_file(scripts / "mozart_state.py", "if any(new != old and new.casefold() == old.casefold() for new in labels for old in known):", "if False:")


def mutation_loose_file_mode(scripts):
    mutate_file(scripts / "mozart_contract.py", "def write_atomic(ctx, parts, name, data, mode=0o600):", "def write_atomic(ctx, parts, name, data, mode=0o666):")


def mutation_loose_dir_mode(scripts):
    mutate_file(scripts / "mozart_contract.py", "os.mkdir(name, 0o700, dir_fd=parent_fd)", "os.mkdir(name, 0o777, dir_fd=parent_fd)")


# --- more registry layers ----------------------------------------------------------------------------------------------

def case_layers_more(env):
    problems = []
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq0uVu1rPzAh7P1nQw3Yx9c2d1m8k4f6s7t0u2v3w5x"
    block = "\n## Host: {name}\n- trust: {trust}\n- transport: ssh\n- permission_mode: default\n- max_budget_usd: 5\n- host_key: " + key + "\n{extra}"
    blocks = block.format(name="web", trust="owned", extra="") + block.format(name="leased", trust="leased", extra="- lease: lease-a1\n") + block.format(name="keyonly", trust="owned", extra="")
    registry = f"## Host: web\n- identity: {'1' * 64}\n\n## Host: leased\n- identity: {'2' * 64}\n\n## Host: keyonly\n- cost: free\n"
    t0 = epoch(PROBE_STAMP)

    def build(enabled, label):
        home = make_home(env, grant=f"## Remote execution\n- enabled: {enabled}\n{blocks}", registry=registry, label=label)
        plant_discovered(home, "web", "inv", {"cpus": 2, "os": "linux"}, probed_at=PROBE_STAMP)
        plant_discovered(home, "web", "inv2", {"cpus": 8}, probed_at="2026-10-26T13:00:00Z")
        plant_discovered(home, "edge", "inv", {"os": "linux"}, probed_at=PROBE_STAMP)
        plant_discovered(home, "future", "inv", {"os": "linux"}, probed_at="2026-10-28T12:00:00Z")
        return home
    on, off = build("true", "lay1"), build("false", "lay2")
    max_age = 168 * 3600
    calls_on = [{"argv": ["show"], "now": t0 + 3600}, {"argv": ["show"], "now": t0 + max_age}, {"argv": ["show"], "now": t0 + max_age + 1}]
    on_out = drive(env.scripts, "run_cli", {"home": str(on), "calls": calls_on})
    off_out = drive(env.scripts, "run_cli", {"home": str(off), "calls": [{"argv": ["show"], "now": t0 + 3600}]})
    hosts = on_out[0]["out"]["hosts"]
    web = hosts["web"]["facts"]
    if web["cpus"]["value"] != 8 or web["cpus"]["source"] != "discovered:inv2":
        problems.append(f"two hooks for one host: the newest probe must win, got {web['cpus']}")
    if not hosts["future"]["facts"]["os"]["stale"]:
        problems.append("a record dated two days in the future must read as stale")
    at, after = on_out[1]["out"]["hosts"]["edge"]["facts"]["os"]["stale"], on_out[2]["out"]["hosts"]["edge"]["facts"]["os"]["stale"]
    if at or not after:
        problems.append(f"stale at exactly max_age is {at} (want False), one second later {after} (want True)")
    if not hosts["web"]["dispatchable"]:
        problems.append(f"an owned host with a host_key and an identity must be dispatchable: {hosts['web']['why_not']}")
    if hosts["leased"]["dispatchable"] or not any("lease" in w for w in hosts["leased"]["why_not"]):
        problems.append(f"a leased host without a valid lease must not be dispatchable: {hosts['leased']['why_not']}")
    if hosts["edge"]["trust"] != "shared" or hosts["edge"]["has_block"]:
        problems.append(f"a host with no grant block must read as shared: {hosts['edge']['trust']!r}")
    if hosts["keyonly"]["dispatchable"] or not any("identity" in w for w in hosts["keyonly"]["why_not"]):
        problems.append(f"a host with a host_key but no identity must not be dispatchable: {hosts['keyonly']['why_not']}")
    muted = off_out[0]["out"]["hosts"]
    if any(h["dispatchable"] for h in muted.values()) or not all(any("not enabled" in w for w in h["why_not"]) for h in muted.values() if h["has_block"]):
        problems.append("under a disabled grant nothing may be dispatchable, and each reason must say the grant is not enabled")
    if muted["web"]["facts"]["cpus"]["value"] != 8:
        problems.append("a disabled grant must still show the registry's facts")
    env.notes.append("newest probe wins, future and boundary staleness, leased and keyless hosts, a disabled grant")
    return problems


# --- the probe gate, facts --local, match semantics --------------------------------------------------------------------------

def case_facts(env):
    problems = []
    schema = env.schema
    grant = f"## Remote execution\n- enabled: true\n- tool_path: {STUBS}\n"
    home = make_home(env, grant=grant, label="facts")
    real = drive(env.scripts, "run_cli", {"home": str(home), "calls": [{"argv": ["facts", "--local"]}, {"argv": ["facts", "--local", "--kube-context", "ctx-a", "--kube-context", "nope"]}]})
    doc = real[0]["out"].get("facts")
    want_id = hashlib.sha256(b"11111111-2222-3333-4444-555555555555").hexdigest()
    if real[0]["code"] != 0 or doc is None:
        problems.append(f"facts --local through the real runner failed: {real[0]['out']}")
    else:
        problems += [f"real probe: {p}" for p in validate_probe(doc, schema)]
        if doc["os"] != "darwin" or doc["host_id"] != want_id:
            problems.append(f"real probe: os {doc['os']!r}, host_id {doc['host_id']!r}; the stub PATH from tool_path and lib-before-probe order must give darwin and {want_id[:12]}")
        if doc["kube_contexts"] != {}:
            problems.append(f"real probe: with no names asked kube_contexts is {doc['kube_contexts']!r}, want {{}}")
    asked = real[1]["out"].get("facts") or {}
    if asked.get("kube_contexts") != {"ctx-a": True, "nope": False}:
        problems.append(f"facts --local --kube-context answered {asked.get('kube_contexts')!r}")
    good = probe_doc(schema, os="darwin")
    canned = [
        ("a nonzero exit", {"probe_raw": {"rc": 1, "out": json.dumps(good) + "\n"}}, "hook-output"),
        ("two lines", {"probe_raw": {"out": json.dumps(good) + "\n" + json.dumps(good) + "\n"}}, "hook-output"),
        ("no newline", {"probe_raw": {"out": json.dumps(good)}}, "hook-output"),
        ("not strict JSON", {"probe_raw": {"out": "[1]\n"}}, "hook-output"),
        ("a schema-invalid document", {"probe_raw": {"out": json.dumps(dict(good, cpus="eight")) + "\n"}}, "hook-output"),
        ("a timeout", {"probe_raw": {"out": "", "flag": "timeout"}}, "timeout"),
        ("an unrequested context name", {"probe_doc": good, "inject_kube": {"canary-ctx-unrequested": True}}, "hook-output"),
    ]
    calls = [dict(argv=["facts", "--local"], **extra) for _, extra, _ in canned]
    calls.append({"argv": ["facts", "--local", "--kube-context", "ctx-a"], "probe_doc": good, "inject_kube": {"canary-ctx-unrequested": True}, "known_contexts": ["ctx-a"]})
    calls.append({"argv": ["facts", "--local", "--kube-context", "ctx-a"], "probe_doc": good, "known_contexts": ["ctx-a"]})
    calls.append({"argv": ["facts", "--local"], "probe_boom": True})
    outs = drive(env.scripts, "run_cli", {"home": str(home), "calls": calls})
    boom = outs[9]
    if boom["code"] != env.schema["exit_codes"]["internal"] or boom["out"].get("error") != "internal" or "secret detail" in json.dumps(boom["out"]):
        problems.append(f"an unexpected failure inside a verb: exit {boom['code']}, {boom['out']}; want the documented internal exit and no detail leaked")
    for (name, _, code), res in zip(canned, outs):
        if res["code"] not in (3, 4) or res["out"].get("error") != code:
            problems.append(f"facts --local with {name}: exit {res['code']}, error {res['out'].get('error')!r}, want a refusal with {code!r}")
    text = json.dumps(outs[6]) + json.dumps(outs[7])
    if "canary-ctx-unrequested" in text:
        problems.append("an unrequested context name appears in the output or an error text")
    if outs[6]["code"] == 0 or outs[7]["code"] == 0:
        problems.append("a probe answering an unrequested name was accepted (unrequested name)")
    if outs[8]["code"] != 0 or outs[8]["out"]["facts"]["kube_contexts"] != {"ctx-a": True}:
        problems.append(f"facts --local --kube-context output differs from the requested answer: {outs[8]['out']}")
    return problems


def mutation_no_kube_subset(scripts):
    mutate_file(scripts / "mozart_state.py", "if answered is not None and set(answered) != set(requested):", "if False:")


def case_cli_edges(env):
    """show with an unknown label, match's exit rule, --tolerates and the refusal of tolerates= in --requires."""
    problems = []
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq0uVu1rPzAh7P1nQw3Yx9c2d1m8k4f6s7t0u2v3w5x"
    grant = ("## Remote execution\n- enabled: true\n\n## Host: keyed\n- trust: owned\n- transport: ssh\n- permission_mode: default\n- max_budget_usd: 5\n- host_key: " + key + "\n")
    registry = ("## Host: plain\n- labels: os=darwin\n\n## Host: keyed\n- labels: os=darwin\n- identity: " + "1" * 64 + "\n- taints: gpu\n")
    home = make_home(env, grant=grant, registry=registry, label="edges")
    local = probe_doc(env.schema, os="linux")
    calls = [
        {"argv": ["show", "nosuch"]},
        {"argv": ["match", "--requires", "os=darwin", "--tolerates", "gpu"], "probe_doc": local},
        {"argv": ["match", "--requires", "os=darwin"], "probe_doc": local},
        {"argv": ["match", "--requires", "os=darwin,tolerates=gpu"], "probe_doc": local},
        {"argv": ["match", "--requires", "os=darwin", "--tolerates", "bad name!"], "probe_doc": local},
    ]
    res = drive(env.scripts, "run_cli", {"home": str(home), "calls": calls})
    if res[0]["code"] != 3 or res[0]["out"].get("error") != "unknown-label":
        problems.append(f"show of an unknown label: exit {res[0]['code']}, {res[0]['out'].get('error')!r}")
    if {m["label"]: m["trust"] for m in res[2]["out"]["matches"]} != {"plain": "shared"}:
        problems.append(f"a host with no grant block must read as shared in match: {res[2]['out']['matches']}")
    admitted = res[1]
    labels = {m["label"]: m["dispatchable"] for m in admitted["out"]["matches"]}
    if admitted["code"] != 0 or labels != {"plain": False, "keyed": True}:
        problems.append(f"--tolerates gpu should admit the tainted dispatchable host: exit {admitted['code']}, {labels}")
    repelled = res[2]
    if [m["label"] for m in repelled["out"]["matches"]] != ["plain"] or repelled["code"] != 3:
        problems.append(f"a host that matches but cannot be dispatched to must still exit 3 (only dispatchable or local matches exit 0): exit {repelled['code']}, {repelled['out'].get('matches')}")
    for i, why in ((3, "tolerates= inside --requires"), (4, "a malformed --tolerates")):
        if res[i]["code"] != 2 or res[i]["out"].get("error") != "usage":
            problems.append(f"{why}: exit {res[i]['code']}, {res[i]['out'].get('error')!r}, want exit 2 usage")
    return problems


def case_reasons(env):
    """A reason is bounded and printable whatever the fact held; a hostile value is cut, never echoed whole."""
    awkward = '"\\\'' * 40 + "‮ \x01​﻿" + "z" * 80
    cases = [{"id": "gpu", "requires": "gpu_name=x", "entries": {"gpu_name": entry(awkward)}},
             {"id": "ver", "requires": "xcodebuild>=1", "entries": {"xcodebuild": entry(awkward)}},
             {"id": "flags", "requires": "claude_flags=--print", "entries": {"claude_flags": entry([awkward])}}]
    got = drive(env.scripts, "matcher_batch", {"cases": cases})
    texts = [r for c in cases for r in got[c["id"]].get("reasons", [])]
    check = drive(env.scripts, "validate_batch", {"cases": [{"id": str(i), "spec": {"type": "string", "maxLength": 200, "printable": True}, "value": t} for i, t in enumerate(texts)]})
    problems = [f"reason {i} is not bounded, printable text: {check[str(i)][0]}" for i in range(len(texts)) if check[str(i)]]
    if not texts or any(awkward in t for t in texts):
        problems.append("a hostile fact value reached a reason whole, or produced no reason")
    return problems


# --- grant keys and size, generated from the schema ---------------------------------------------------------------------

def grant_key_cases(schema):
    base = {
        "remote_execution": {"enabled": "true"},
        "host": {"trust": "owned", "transport": "ssh", "permission_mode": "default", "max_budget_usd": "5"},
        "provider": {"hook": "/srv/h", "max_leases": "1", "max_lease_hours": "1", "daily_cost_ceiling_usd": "1"},
    }
    heading = {"remote_execution": "## Remote execution", "host": "## Host: h1", "provider": "## Provider: p1"}
    out = []
    for kind, section in schema["grant"]["sections"].items():
        if kind not in base:
            continue
        for key, spec in section["keys"].items():
            values = []
            if spec["type"] == "bool":
                values = ["True", "1", "yes"]
            elif spec["type"] == "int":
                values = ["007", "-1", "1.0", str(spec.get("min", 1) - 1), str(spec["max"] + 1)]
            else:
                node = spec.get("items", spec)
                pattern = schema["grammars"][node["grammar"]]["pattern"] if "grammar" in node else node.get("pattern")
                enum = schema[spec["enum_from"]] if "enum_from" in spec else spec.get("enum")
                if enum:
                    values.append("zzz-not-allowed")
                if pattern:
                    values += [v for v in ("!!bad!!", "é", "-") if not re.fullmatch(pattern, v)][:1]
                if "maxLength" in spec:
                    values.append("x" * (spec["maxLength"] + 1))
            for value in values:
                fields = dict(base[kind], **{key: value})
                text = "## Remote execution\n- enabled: true\n" if kind != "remote_execution" else ""
                text += heading[kind] + "\n" + "".join(f"- {k}: {v}\n" for k, v in fields.items())
                out.append((f"{kind}.{key} = {value[:20]!r}", text))
    return out


def case_grant_keys(env):
    cases = grant_key_cases(env.schema)
    controls = [("remote_execution base", "## Remote execution\n- enabled: true\n", None),
                ("host base", "## Remote execution\n- enabled: true\n## Host: h1\n- trust: owned\n- transport: ssh\n- permission_mode: default\n- max_budget_usd: 5\n", None),
                ("provider base", "## Remote execution\n- enabled: true\n## Provider: p1\n- hook: /srv/h\n- max_leases: 1\n- max_lease_hours: 1\n- daily_cost_ceiling_usd: 1\n", None)]
    entries = [(n, t, "grant-invalid") for n, t in cases] + controls
    exact = "## Remote execution\n- enabled: true\n"
    entries += [("exactly 65536 bytes", exact + "\n" * (65536 - len(exact)), None), ("65537 bytes", exact + "\n" * (65537 - len(exact)), "grant-invalid")]
    batch = [{"id": str(i), "home": str(make_home(env, grant=t, label="gk"))} for i, (_, t, _) in enumerate(entries)]
    got = drive(env.scripts, "grant_load", {"cases": batch})
    problems = []
    for i, (name, _, reason) in enumerate(entries):
        state = got[str(i)]
        if state["reason"] != reason or state["enabled"] != (reason is None):
            problems.append(f"grant key case {name}: reason {state['reason']!r} ({(state['detail'] or '')[:60]}), want {reason!r}")
    if len(cases) < 40:
        problems.append(f"only {len(cases)} schema-generated grant-key cases, floor 40")
    env.notes.append(f"{len(cases)} schema-generated grant-key negatives, 3 section bases, the 64 KiB boundary")
    return problems


def case_fifo(env):
    """A FIFO planted where a file is read must be refused, not waited on."""
    problems = []
    home = make_home(env, grant=fixture_text("grant-minimal.fixture"), label="fifo")
    grant_path = home / ".mozart" / "resources" / "grant.md"
    grant_path.unlink()
    os.mkfifo(grant_path, 0o600)
    try:
        got = drive(env.scripts, "grant_load", {"cases": [{"id": "f", "home": str(home)}]}, timeout=4)["f"]
        if got["reason"] != "grant-hygiene":
            problems.append(f"a FIFO as the grant: reason {got['reason']!r}, want grant-hygiene")
    except RuntimeError:
        problems.append("a FIFO planted as the grant hung the reader (a FIFO is read, not refused)")
    home2 = make_home(env, grant=fixture_text("grant-minimal.fixture"), label="fifo2")
    plant_discovered(home2, "good", "inv", {"os": "linux"})
    os.mkfifo(home2 / ".mozart" / "resources" / "discovered" / "pipe.inv.json", 0o600)
    try:
        shown = drive(env.scripts, "run_cli", {"home": str(home2), "calls": [{"argv": ["show"]}]}, timeout=4)[0]
        if shown["code"] != 0 or list(shown["out"]["hosts"]) != ["good"] or "pipe.inv.json" not in " ".join(shown["out"]["problems"]):
            problems.append(f"a FIFO in discovered/ was not reported as a per-file problem: {shown['code']}, {shown['out'].get('problems')}")
    except RuntimeError:
        problems.append("a FIFO planted in discovered/ hung the reader (a FIFO)")
    return problems


def mutation_blocking_open(scripts):
    mutate_file(scripts / "mozart_grant.py", "os.O_NOFOLLOW | os.O_NONBLOCK |", "os.O_NOFOLLOW |")


def case_docs_tripwire(env):
    """The docs-agreement check (verb, fact, grant-key and exit-code tables equal the schema) is still to be
    written. The day a doc that holds those tables appears, this fails until that check exists."""
    present = [p for p in ("agents/RESOURCES.md", "docs/MULTI-HOST.md") if (REPO / p).exists()]
    if present:
        return [f"{present} exist, but the docs-agreement check is still a stub; write it (tables equal the schema) before these merge"]
    env.notes.append("docs-agreement check still a stub; no doc exists yet")
    return []


def case_signal_cleanup(env):
    """SIGTERM mid-run leaves no scratch directory behind: not the checker's own, not a git probe's, not a hook's."""
    private = Path(tempfile.mkdtemp(prefix="mz-sig-"))
    home = pwd.getpwuid(os.geteuid()).pw_dir
    before = set(glob_names(home, ".mz-check-hooks-*"))
    try:
        proc = subprocess.Popen([sys.executable, "-I", str(Path(__file__).resolve()), "--only", "V41_registry:discover"],
                                env={"PATH": SYSTEM_PATH, "TMPDIR": str(private)}, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline and not (list(private.glob("mz-check-*")) and glob_names(home, ".mz-check-hooks-*") != before):
            time.sleep(0.05)
        os.kill(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, 9)
            return ["the checker did not exit within 20s of SIGTERM"]
        leftovers = sorted(p.name for p in private.iterdir())
        stray_hooks = sorted(set(glob_names(home, ".mz-check-hooks-*")) - before)
        problems = []
        if leftovers:
            problems.append(f"SIGTERM left scratch directories in TMPDIR: {leftovers[:3]}")
        if stray_hooks:
            problems.append(f"SIGTERM left hook scratch directories in the home: {stray_hooks[:3]}")
        return problems
    finally:
        shutil.rmtree(private, ignore_errors=True)
        for name in set(glob_names(home, ".mz-check-hooks-*")) - before:
            shutil.rmtree(os.path.join(home, name), ignore_errors=True)


def glob_names(directory, pattern):
    import fnmatch
    return sorted(n for n in os.listdir(directory) if fnmatch.fnmatch(n, pattern))


class Gate:
    # ceiling_ms is a regression tripwire, not the plan's budget. The plan budgets the whole
    # probe family at 8 s on a fast machine; the ceilings below (12 s, 3 s, 1 s) sit at
    # 3-8 times the measured cost so a slow 3-vCPU runner never trips them, and only
    # --enforce-ceilings turns an overrun into a failure. --timing alone reports.
    def __init__(self, name, ceiling_ms, cases, controls):
        self.name = name
        self.ceiling_ms = ceiling_ms
        self.cases = cases
        self.controls = controls  # (case, description, mutate, expected substring of a problem)


GATES = [
    Gate(
        "V37_probe", 45000,
        [("keys", case_keys), ("parse", case_parse), ("empty-path", case_empty_path), ("darwin", case_darwin),
         ("determinism", case_determinism), ("timeouts", case_timeouts), ("agreement", case_agreement),
         ("mozart-search", case_mozart_search), ("android", case_android), ("numbers", case_numbers), ("kube", case_kube),
         ("subshell", case_subshell), ("fixtures", case_fixtures)],
        [("timeouts", "drop </dev/null from the command runner", mutation_drop_devnull, "stdin-bytes=4096"),
         ("subshell", "name the per-call directory by a counter subshells share", mutation_shared_hit_names, "after the host_id timeout"),
         ("mozart-search", "prefer the oldest plugin-cache version", mutation_oldest_install, "want (True, False)")],
    ),
    Gate(
        "V37_shells", 20000,
        [("shells", case_shells)],
        [("shells", "plant a bashism (${var,,}) in the probe", mutation_bashism, "bad substitution"),
         ("shells", "make the watchdog ignore a finished command and a gone probe", mutation_watchdog_blind, "a finished watchdog", "watchdog")],
    ),
    Gate(
        "V38_portable", 3000,
        [("population", case_population), ("denylist", case_denylist), ("scanner-plants", case_scanner_plants),
         ("python-floor", case_python_floor), ("signal-cleanup", case_signal_cleanup)],
        [("denylist", "plant sed -i in the probe", mutation_plant_sed_i, "sed -i"),
         ("python-floor", "plant a PEP 604 annotation", mutation_plant_pep604, "PEP 604"),
         ("python-floor", "plant zip(strict=)", mutation_plant_zip_strict, "zip(strict=")],
    ),
    Gate(
        "V39_schema", 10000,
        [("validator", case_validator), ("negatives", case_negatives), ("conformance", case_conformance), ("strict-json", case_strict_json),
         ("grammar-agree", case_grammar_agree), ("bundle-files", case_bundle_files), ("docs-tripwire", case_docs_tripwire)],
        [("validator", "drop the closed-object check (additionalProperties)", mutation_open_objects, "closed object")],
    ),
    Gate(
        "V40_grant", 30000,
        [("home", case_home), ("launcher", case_launcher), ("installed", case_installed), ("hygiene", case_hygiene), ("grammar", case_grammar),
         ("nothing-else", case_nothing_else), ("ast", case_ast), ("dynamic", case_dynamic), ("ci-install", case_ci_install),
         ("hard-refusals", case_hard_refusals), ("grant-keys", case_grant_keys), ("fifo", case_fifo)],
        [("home", "take the home from $HOME instead of the account record", mutation_home_from_env, "account record"),
         ("ast", "a back-edge import in mozart_grant", mutation_grant_back_edge, "back-edge"),
         ("ast", "Context( outside Context.production", mutation_context_outside_production, "calls Context("),
         ("ast", "contract.Context( outside Context.production", mutation_attr_context, "calls contract.Context("),
         ("ast", "a plain import of a bundle module", mutation_direct_import, "mozart_state: imports mozart_contract directly"),
         ("ast", "from os import environ", mutation_environ_import, "imports environ from os"),
         ("ast", "load_sibling with a variable", mutation_nonconstant_loader, "non-constant module name"),
         ("hard-refusals", "HARD_REFUSALS = ()", mutation_no_hard_refusals, "hard refusal"),
         ("fifo", "open without O_NONBLOCK", mutation_blocking_open, "a FIFO"),
         ("installed", "let a group-writable bundle file through (mask 0o002)", mutation_boot_group_mask, "a group-writable module", "a group-writable module"),
         ("installed", "skip the owner check", mutation_boot_owner, "a foreign owner", "a foreign owner")],
    ),
    Gate(
        "V41_registry", 40000,
        [("discover", case_discover), ("symlinks", case_symlinks), ("layers", case_layers), ("snapshots", case_snapshots), ("hooks", case_hooks),
         ("robust", case_robust), ("concurrency", case_concurrency), ("stalled-stdin", case_stalled_stdin), ("collisions", case_collisions),
         ("modes", case_modes), ("layers-more", case_layers_more)],
        [("symlinks", "drop O_NOFOLLOW from the directory opens", mutation_follow_symlinks, "through a symlink"),
         ("hooks", "drop the hook sha256 compare", mutation_no_sha_compare, "a sha mismatch", "a sha mismatch"),
         ("hooks", "drop the hook hygiene call", mutation_no_hook_hygiene, "a symlinked hook", "a symlinked hook"),
         ("hooks", "drop the .git refusal", mutation_no_git_refusal, "a hook inside a git work tree", "a hook inside a git work tree"),
         ("hooks", "drop the timeout flag", mutation_no_timeout_flag, "a hang", "a hang"),
         ("collisions", "let a discovered collision raise registry-invalid", mutation_collision_fatal, "took show down"),
         ("collisions", "skip persist's known-label check", mutation_persist_no_known, "a hook response label"),
         ("modes", "create files 0666", mutation_loose_file_mode, "mode: file"),
         ("modes", "create directories 0777", mutation_loose_dir_mode, "mode: directory"),
         ("concurrency", "remove any writer's temp file", mutation_tmp_any_writer, "live writer's temp file", "tmp"),
         ("concurrency", "match temp files by prefix", mutation_tmp_prefix, "another name's temp file", "tmp"),
         ("stalled-stdin", "write stdin before the deadline starts", mutation_blocking_stdin, "did not honor its timeout")],
    ),
    Gate(
        "V42_match", 10000,
        [("table", case_table), ("properties", case_properties), ("match-cli", case_match_cli), ("facts", case_facts), ("cli-edges", case_cli_edges),
         ("reasons", case_reasons)],
        [("table", "compare versions as strings", mutation_string_versions, "16.10 >= 16.9"),
         ("facts", "accept a probe answering an unrequested name", mutation_no_kube_subset, "unrequested name")],
    ),
]
CASES = {(g.name, name): fn for g in GATES for name, fn in g.cases}


def control_scripts(env, root):
    """A scratch copy of scripts/ carrying only what the cases read."""
    scratch = root / "scripts"
    scratch.mkdir()
    for path in SCRIPTS.iterdir():
        if path.is_file() and (path.suffix in (".sh", ".json") or path.name == "check-resources.py" or (path.suffix == ".py" and path.name.startswith("mozart"))):
            shutil.copy2(path, scratch / path.name)
    return scratch


def run_case(env, fn):
    try:
        return fn(env)
    except Deadline:
        raise
    except Exception as exc:  # a crashing case is a failing case, never a skipped one
        return [f"{fn.__name__} crashed: {type(exc).__name__}: {exc}"]


@contextlib.contextmanager
def scratch_dir(prefix):
    """A scratch directory that is removed however the run ends, retrying while a straggler is still writing."""
    path = tempfile.mkdtemp(prefix=prefix)
    try:
        yield path
    finally:
        for _ in range(15):
            shutil.rmtree(path, ignore_errors=True)
            if not os.path.exists(path):
                break
            time.sleep(0.2)


def run_gate(gate, schema, only_case=None):
    """(ok, detail) for one gate. Its cases and mutation controls run concurrently."""
    home_before = tree_snapshot(passwd_home() / ".mozart")
    problems = []
    with scratch_dir("mz-check-") as tmp:
        tmp = Path(tmp)
        env = Env(SCRIPTS, tmp, schema)
        jobs = []  # (kind, name, label, thunk[, expected substring])
        for name, fn in gate.cases:
            if only_case and name != only_case:
                continue

            def case_job(fn=fn):
                cenv = env.clone()
                return run_case(cenv, fn), cenv.notes
            jobs.append(("case", name, name, case_job, None))
        if not only_case:
            for index, (case_name, label, mutate, expect, *rest) in enumerate(gate.controls):
                root = tmp / f"control-{index}-{case_name}"
                root.mkdir()
                scratch = control_scripts(env, root)
                try:
                    mutate(scratch)
                except RuntimeError as exc:
                    problems.append(f"mutation could not be applied, so its control did not run: {exc}")
                    continue

                def control_job(fn=dict(gate.cases)[case_name], scratch=scratch, root=root, focus=rest[0] if rest else None):
                    cenv = Env(scratch, root, schema)
                    cenv.focus = focus
                    return run_case(cenv, fn), []
                jobs.append(("control", case_name, label, control_job, expect))
        pool = ThreadPoolExecutor(max_workers=len(jobs))
        try:
            futures = [pool.submit(job[3]) for job in jobs]
            outcomes = [f.result() for f in futures]
        except Deadline:
            reap_all()
            raise
        finally:
            pool.shutdown(wait=False, cancel_futures=True)
    notes, controls_run = [], []
    for (kind, name, label, _, expect), (found, case_notes) in zip(jobs, outcomes):
        if kind == "case":
            problems += [f"{name}: {p}" for p in found]
            notes += case_notes
        elif any(expect.lower() in p.lower() for p in found):
            controls_run.append(label)
        elif found:
            problems.append(f"mutation caught for the wrong reason (want {expect!r}): {label}: {found[0][:160]}")
        else:
            problems.append(f"mutation NOT caught: {label}")
    changed = snapshot_changes(home_before, tree_snapshot(passwd_home() / ".mozart"))
    if changed:
        problems.append(f"the real <home>/.mozart changed while the checker ran: {changed[:5]}")
    if problems:
        return False, "; ".join(problems[:6]) + (f" (+{len(problems) - 6} more)" if len(problems) > 6 else "")
    done = ", ".join(notes)
    caught = "; mutation caught: " + "; ".join(controls_run) if controls_run else ""
    return True, f"{done}{caught}"


def main(argv=None):
    parser = argparse.ArgumentParser(prog="check-resources.py", description=__doc__.split("\n")[0])
    parser.add_argument("--list", action="store_true", help="print the gate names and exit")
    parser.add_argument("--timing", action="store_true", help="print milliseconds per gate (report only)")
    parser.add_argument("--enforce-ceilings", action="store_true", help="with --timing, fail a gate that runs over its ceiling")
    parser.add_argument("--only", metavar="GATE[:CASE]", help="run one gate, or one case of it, without mutation controls")
    parser.add_argument("--deadline", type=int, default=DEFAULT_DEADLINE_S, metavar="SECONDS", help="hard limit for the whole run")
    args = parser.parse_args(argv)
    args.timing = args.timing or args.enforce_ceilings

    if args.list:
        for gate in GATES:
            print(gate.name)
        return 0

    selected = GATES
    only_case = None
    if args.only:
        gate_name, _, only_case = args.only.partition(":")
        selected = [g for g in GATES if g.name == gate_name]
        if not selected or (only_case and (gate_name, only_case) not in CASES):
            print(f"unknown gate or case: {args.only}", file=sys.stderr)
            return 2

    def on_alarm(signum, frame):
        STOPPING.set()
        raise Deadline()

    signal.signal(signal.SIGALRM, on_alarm)
    signal.signal(signal.SIGTERM, on_alarm)
    signal.signal(signal.SIGINT, on_alarm)
    signal.alarm(max(1, args.deadline))
    schema = load_schema()
    failed = 0
    timings = []
    current = None
    try:
        for gate in selected:
            current = gate
            started = time.monotonic()
            try:
                ok, detail = run_gate(gate, schema, only_case)
            except Deadline:
                raise
            except Exception as exc:  # the wrapper must always get a line per gate
                ok, detail = False, f"checker error: {type(exc).__name__}: {exc}"
            ms = int((time.monotonic() - started) * 1000)
            timings.append((gate, ms))
            print(f"{'PASS' if ok else 'FAIL'}  {gate.name}  {detail}", flush=True)
            failed += 0 if ok else 1
    except Deadline:
        remaining = selected[selected.index(current):] if current else selected
        for gate in remaining:
            print(f"FAIL  {gate.name}  interrupted: the {args.deadline}s deadline passed, or the run was signalled", flush=True)
        failed += len(remaining)
    finally:
        signal.alarm(0)
        reap_all()

    if args.timing:
        total = sum(ms for _, ms in timings)
        over = 0
        for gate, ms in timings:
            flag = "" if ms <= gate.ceiling_ms else "  OVER"
            over += 1 if flag else 0
            print(f"TIME  {gate.name}  {ms} ms (ceiling {gate.ceiling_ms} ms){flag}")
        print(f"TIME  total  {total} ms")
        if args.enforce_ceilings:
            failed += over
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
