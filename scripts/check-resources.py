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
DEFAULT_DEADLINE_S = 90

# Names are built by concatenation so this file never matches its own scans.
CANARY_NAME = "MOZART_SECRET" + "_CANARY"
CANARY_VALUE = "canary-" + "7f3a9c1e"

STUB_NAMES = [
    "claude", "ioreg", "kubectl", "nvidia-smi", "readstdin", "security", "sleeper",
    "sw_vers", "sysctl", "uname", "xcode-select", "xcodebuild",
]
UTILITIES = [
    "sleep", "date", "find", "id", "ps", "mktemp", "rm", "cat", "dd", "wc",
    "sha256sum", "shasum", "getconf", "nproc",
]
FIXTURE_FLOOR = len(STUB_NAMES)
REQUIRED_UTILITIES = ["sleep", "date", "find", "mktemp", "rm", "cat", "dd", "wc"]
PROBE_UNDETERMINED = ("load", "probed_at")
SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

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
        # the scratch counter, toolbox and lock are shared by the clones the cases run on
        self.shared = shared if shared is not None else {"n": 0, "toolbox": None, "lock": threading.Lock()}

    def clone(self):
        return Env(self.scripts, self.tmp, self.schema, self.shared)

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
    add("/bin/sh", ["/bin/sh"])
    return shells


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
    kube = "plain\n" + hostile + "\n\n"
    res, doc, home, _ = env.stub_probe({"STUB_KUBE_CONTEXTS": kube})
    problems += clean_doc(env, res, doc, "stub PATH")
    if doc is None:
        return problems
    want = {
        "os": "darwin", "os_version": "14.5", "arch": "arm64", "cpus": 8, "mem_gb": 16.0,
        "xcodebuild": "16.2", "claude": "2.1.310", "claude_flags": env.schema["probe"]["claude_flags_checked"],
        "gpu": "apple", "gpu_name": "Apple M2 Pro", "load": 0.5,
        "ps_lstart": True if (env.toolbox() / "ps").exists() else None,
        "kube_contexts": ["plain", hostile],
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
        ("no contexts is an empty list", {"STUB_KUBE_CONTEXTS": ""}, "kube_contexts", []),
        ("a non-default cpu count is read, not defaulted", {"STUB_NCPU": "12"}, "cpus", 12),
        ("a locked keychain reads false", {"STUB_KEYCHAIN": "locked"}, "keychain_unlocked", False),
        ("the Apple brand string is gpu_name, escaped", {"STUB_CPU_BRAND": 'Apple "M4" \\ Max\t\u00e9'}, "gpu_name", 'Apple "M4" \\ Max\t\u00e9'),
        ("the nvidia-smi branch reports nvidia", {"STUB_UNAME_S": "Linux", "STUB_GPU_NAME": hostile}, "gpu", "nvidia"),
        ("the nvidia-smi name round-trips", {"STUB_UNAME_S": "Linux", "STUB_GPU_NAME": hostile}, "gpu_name", hostile),
        ("a Linux stub is os linux", {"STUB_UNAME_S": "Linux"}, "os", "linux"),
    ]
    bad = b"bad\xff\xc3(name\nok"
    variants.append(("malformed UTF-8 in a context name", {"STUB_KUBE_CONTEXTS": bad}, "kube_contexts", ["bad\ufffd\ufffd(name", "ok"]))
    runs = env.pmap(lambda v: env.stub_probe(v[1]), variants)
    for (label, _, key, value), (_, doc, _, _) in zip(variants, runs):
        got = None if doc is None else doc.get(key)
        if got != value:
            problems.append(f"{label}: {key} is {got!r}, want {value!r}")
    env.notes.append("version, flag, list and escape parsing")
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
    """A hanging tool and a stdin-reading tool are both bounded by --total-timeout."""
    problems = []
    front = env.fresh("front")
    os.symlink(STUBS / "sleeper", front / "nvidia-smi")
    os.symlink(STUBS / "readstdin", front / "docker")
    record = env.fresh("rec") / "record"
    extra = {"STUB_UNAME_S": "Linux", "STUB_SLEEP": "30", "STUB_RECORD": str(record)}
    find_front = env.fresh("front")
    os.symlink(STUBS / "sleeper", find_front / "find")
    search_home = env.fresh("home")
    (search_home / ".claude" / "plugins").mkdir(parents=True)

    def hung(which):
        if which == "tool":
            return env.stub_probe(extra, front=front, args=("--total-timeout", "2"), padding=262144)
        return env.stub_probe({"STUB_SLEEP": "30"}, front=find_front, args=("--total-timeout", "2"), home=search_home)

    (res, doc, _, _), (_, search_doc, _, _) = env.pmap(hung, ["tool", "search"])
    problems += clean_doc(env, res, doc, "hung tool")
    if res.secs > 12:
        problems.append(f"the probe took {res.secs:.1f}s with --total-timeout 2 and a 30s sleeper")
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
        if not any(e.endswith("-budget") for e in errors):
            problems.append(f"the total budget was spent but no command was skipped: {errors}")

    doc = search_doc
    if doc is None or "search-timeout" not in doc.get("probe_errors", []):
        problems.append("a hung plugin-cache search is not recorded as search-timeout")
    elif doc.get("mozart_command") is not None or doc.get("mozart_child_mode") is not None:
        problems.append("a timed-out search with nothing found must leave the mozart facts null")
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
    env.notes.append(f"argument grammar agrees on {len(samples)} strings")
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
            problems.append(f"a later tool succeeded but was recorded as a timeout: {misreported}")
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


def mutation_shared_hit_names(scripts):
    mutate_file(scripts / "mozart-probe.sh", '  rm -f "$mp_pidf" "$mp_hitf" "$mp_outf" </dev/null 2>/dev/null\n', '')


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


def case_shells(env):
    shells = find_shells()
    problems = []
    if not shells:
        return ["no POSIX shell found"]
    results = run_everywhere(env, shells)
    base = None
    for name, kind, res, doc in results:
        problems += clean_doc(env, res, doc, name)
        if res.err:
            problems.append(f"{name}: stderr is not empty: {res.err[:120]!r}")
        if doc is not None:
            if base is None:
                base = (name, normalised(doc))
            elif normalised(doc) != base[1]:
                differing = sorted(k for k in base[1] if base[1][k] != normalised(doc).get(k))
                problems.append(f"{name} differs from {base[0]} in {differing}")
    others = [name for name, _, kind in shells if kind != "bash"]
    if os.environ.get("CI") == "true" and not others:
        problems.append("CI=true and no non-bash shell (dash, busybox) is available to run the probe")
    env.notes.append("identical under " + ", ".join(name for name, _, _ in shells))
    return problems


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
    files = sorted(scripts.glob("mozart*.py")) + [scripts / "check-resources.py"]
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
        "V37_probe", 12000,
        [("keys", case_keys), ("parse", case_parse), ("empty-path", case_empty_path), ("darwin", case_darwin),
         ("determinism", case_determinism), ("timeouts", case_timeouts), ("agreement", case_agreement),
         ("mozart-search", case_mozart_search), ("android", case_android), ("numbers", case_numbers),
         ("subshell", case_subshell), ("fixtures", case_fixtures)],
        [("timeouts", "drop </dev/null from the command runner", mutation_drop_devnull, "stdin-bytes=4096"),
         ("subshell", "share the per-call files across subshells", mutation_shared_hit_names, "-timeout"),
         ("mozart-search", "prefer the oldest plugin-cache version", mutation_oldest_install, "want (True, False)")],
    ),
    Gate(
        "V37_shells", 3000,
        [("shells", case_shells)],
        [("shells", "plant a bashism (${var,,}) in the probe", mutation_bashism, "bad substitution")],
    ),
    Gate(
        "V38_portable", 1000,
        [("population", case_population), ("denylist", case_denylist), ("scanner-plants", case_scanner_plants),
         ("python-floor", case_python_floor)],
        [("denylist", "plant sed -i in the probe", mutation_plant_sed_i, "sed -i"),
         ("python-floor", "plant a PEP 604 annotation", mutation_plant_pep604, "PEP 604"),
         ("python-floor", "plant zip(strict=)", mutation_plant_zip_strict, "zip(strict=")],
    ),
]
CASES = {(g.name, name): fn for g in GATES for name, fn in g.cases}


def control_scripts(env, root):
    """A scratch copy of scripts/ carrying only what the cases read."""
    scratch = root / "scripts"
    scratch.mkdir()
    for path in SCRIPTS.iterdir():
        if path.is_file() and (path.suffix in (".sh", ".json") or path.name == "check-resources.py"):
            shutil.copy2(path, scratch / path.name)
    return scratch


def run_case(env, fn):
    try:
        return fn(env)
    except Deadline:
        raise
    except Exception as exc:  # a crashing case is a failing case, never a skipped one
        return [f"{fn.__name__} crashed: {type(exc).__name__}: {exc}"]


def run_gate(gate, schema, only_case=None):
    """(ok, detail) for one gate. Its cases and mutation controls run concurrently."""
    home_before = tree_snapshot(passwd_home() / ".mozart")
    problems = []
    with tempfile.TemporaryDirectory(prefix="mz-check-") as tmp:
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
            for index, (case_name, label, mutate, expect) in enumerate(gate.controls):
                root = tmp / f"control-{index}-{case_name}"
                root.mkdir()
                scratch = control_scripts(env, root)
                try:
                    mutate(scratch)
                except RuntimeError as exc:
                    problems.append(f"mutation could not be applied, so its control did not run: {exc}")
                    continue

                def control_job(fn=dict(gate.cases)[case_name], scratch=scratch, root=root):
                    return run_case(Env(scratch, root, schema), fn), []
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
        raise Deadline()

    signal.signal(signal.SIGALRM, on_alarm)
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
            print(f"FAIL  {gate.name}  deadline of {args.deadline}s exceeded", flush=True)
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
