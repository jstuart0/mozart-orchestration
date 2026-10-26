"""mozart_contract - the seam every other module stands on.

Context (the only way a test reaches in), the schema validator, strict JSON, the hermetic
subprocess runner, the descriptor-relative writer, hook hygiene and the one sibling
loader. It depends only on mozart_grant.

load_sibling runs a module from bytes the launcher already verified (see the CLI's _boot):
nothing here puts a directory on sys.path or imports by name, so a stray file beside the
bundle is never executed and no .pyc is ever written.
"""
import dataclasses
import functools
import hashlib
import json
import math
import os
import pwd
import re
import stat as _stat
import subprocess
import sys
import threading
import time
import types

BUNDLE_VERSION = "1"
_MOZART_BUNDLE = True  # lets load_sibling hand this module back to whoever asks for it
MAX_DEPTH = 8
# {file name: (bytes, path)}; the launcher puts it in this module's namespace before the first line runs.
_SOURCES = globals().setdefault("_SOURCES", {})
_CLOEXEC = getattr(os, "O_CLOEXEC", 0)


class ContractError(Exception):
    def __init__(self, code, message, detail=None):
        super().__init__(message)
        self.code, self.message, self.detail = code, message, detail


def source(fname):
    """The verified bytes of a bundle file."""
    return _SOURCES[fname][0]


def load_schema():
    if "schema" not in _SOURCES:
        _SOURCES["schema"] = json.loads(_SOURCES["mozart-schemas.json"][0].decode("utf-8"))
    return _SOURCES["schema"]


def load_sibling(name):
    """Execute a bundle module from its verified bytes and register it under its own name."""
    mod = sys.modules.get(name)
    if mod is not None and getattr(mod, "_MOZART_BUNDLE", False):
        return mod
    schema = load_schema()
    fname = name + ".py"
    if fname not in schema["bundle"]["files"] or fname not in _SOURCES:
        raise ContractError("bundle-integrity", f"{name} is not a listed bundle module")
    data, path = _SOURCES[fname]
    mod = types.ModuleType(name)
    mod.__file__ = path
    mod._MOZART_BUNDLE = True
    mod.__dict__["load_sibling"] = load_sibling
    sys.modules[name] = mod
    try:
        exec(compile(data, path, "exec"), mod.__dict__)
        if mod.BUNDLE_VERSION != schema["bundle_version"]:
            raise ContractError("bundle-integrity", f"{name} is bundle version {mod.BUNDLE_VERSION}, want {schema['bundle_version']}")
    except BaseException:
        sys.modules.pop(name, None)
        raise
    return mod


grant = load_sibling("mozart_grant")


@dataclasses.dataclass(frozen=True)
class Context:
    """Everything outside the process a verb touches. Built only by production() and by
    tests/resources/testing.py; no environment variable, flag or file constructs one."""
    home: str
    environ: dict
    now: object = None          # test hooks: None in production
    runner: object = None
    remote_home: object = None
    stat: object = None
    sleep_hook: object = None
    ssh_bin: str = "/usr/bin/ssh"

    @classmethod
    def production(cls):
        env = {}
        for key in ("HOME", "MOZART_CHILD_SESSION", "MOZART_LAUNCH_CHILD"):
            if key in os.environ:
                env[key] = os.environ[key]
        return Context(home=grant.passwd_home(), environ=env)

    def clock(self):
        return (self.now or time.time)()

    def fstat(self):
        return self.stat or os.fstat

    def resources(self):
        return os.path.join(self.home, ".mozart", "resources")


# --- validation -------------------------------------------------------------------------------

def _lookup(schema, path):
    node = schema
    for part in path.split("."):
        node = node[part]
    return node


def _resolve(spec, schema):
    while "$ref" in spec:
        spec = dict(_lookup(schema, spec["$ref"]), **{k: v for k, v in spec.items() if k != "$ref"})
    return spec


def _grammar(spec, schema):
    gram = schema["grammars"][spec["grammar"]]
    if gram.get("match") != "full":
        raise ContractError("bad-request", f"grammar {spec['grammar']} must say match: full")
    return gram


def validate(value, spec, schema, path="$", depth=0):
    """Problems (a list of strings) with value against a schema node. Objects are closed
    unless they say additionalProperties: true; ints are never bools or floats."""
    if depth > MAX_DEPTH:
        return [f"{path}: nested deeper than {MAX_DEPTH}"]
    spec = _resolve(spec, schema)
    if value is None:
        return [] if spec.get("nullable") else [f"{path}: null is not allowed"]
    kind = spec.get("type")
    bad = []
    if kind == "bool":
        return [] if type(value) is bool else [f"{path}: want a boolean"]
    if kind in ("int", "number"):
        ok = type(value) is int or (kind == "number" and type(value) is float and math.isfinite(value))
        if not ok:
            return [f"{path}: want {kind}, got {type(value).__name__}"]
        for bound, below in (("min", True), ("max", False)):
            if bound in spec and (value < spec[bound] if below else value > spec[bound]):
                bad.append(f"{path}: {value} is {'below' if below else 'above'} {spec[bound]}")
        return bad
    if kind == "string":
        if not isinstance(value, str):
            return [f"{path}: want a string"]
        gram = _grammar(spec, schema) if "grammar" in spec else spec
        if gram.get("pattern") and not re.fullmatch(gram["pattern"], value):
            bad.append(f"{path}: does not match its grammar")
        if gram.get("no_leading_dash") and value.startswith("-"):
            bad.append(f"{path}: a leading dash is not allowed")
        allowed = _lookup(schema, spec["enum_from"]) if "enum_from" in spec else spec.get("enum")
        if allowed is not None and value not in allowed:
            bad.append(f"{path}: not one of {allowed}")
        if len(value) > spec.get("maxLength", 10 ** 9) or len(value) < spec.get("minLength", 0):
            bad.append(f"{path}: wrong length")
        if spec.get("printable") and not grant.printable(value):
            bad.append(f"{path}: not printable text")
        return bad
    if kind == "list":
        if not isinstance(value, list):
            return [f"{path}: want a list"]
        if not spec.get("minItems", 0) <= len(value) <= spec.get("maxItems", 10 ** 9):
            bad.append(f"{path}: wrong item count")
        for i, item in enumerate(value):
            bad += validate(item, spec.get("items", {"type": "any"}), schema, f"{path}[{i}]", depth + 1)
        return bad
    if kind == "map":
        if not isinstance(value, dict):
            return [f"{path}: want an object"]
        if len(value) > spec.get("maxProperties", 10 ** 9):
            bad.append(f"{path}: too many entries")
        for key, item in value.items():
            # keys are never echoed into a message: a map key may be text nobody should see again
            bad += validate(key, spec["keys"], schema, f"{path}.<key>", depth + 1)
            bad += validate(item, spec["values"], schema, f"{path}[<key>]", depth + 1)
        return bad
    if kind == "object":
        if not isinstance(value, dict):
            return [f"{path}: want an object"]
        props = spec.get("properties", {})
        if not spec.get("additionalProperties", False):
            bad += [f"{path}: an unknown key is present" for k in value if k not in props]
        bad += [f"{path}: missing {k!r}" for k in spec.get("required", []) if k not in value]
        for key, sub in props.items():
            if key in value:
                bad += validate(value[key], sub, schema, f"{path}.{key}", depth + 1)
        for rule in spec.get("when", []):
            if value.get(rule["if"]["key"]) == rule["if"]["equals"]:
                bad += [f"{path}: {k!r} is required when {rule['if']['key']} is {rule['if']['equals']!r}" for k in rule.get("require", []) if k not in value]
                bad += [f"{path}: {k!r} is forbidden when {rule['if']['key']} is {rule['if']['equals']!r}" for k in rule.get("forbid", []) if k in value]
        return bad
    return [f"{path}: schema node has no usable type"]


def loads_strict(data, max_bytes=1 << 20):
    """Parse JSON bytes as a contract allows: valid UTF-8, no duplicate keys, no NaN or
    Infinity, no leading-zero numbers (the JSON grammar), nested at most MAX_DEPTH, one object."""
    def pairs(items):
        keys = [k for k, _ in items]
        if len(set(keys)) != len(keys):
            raise ValueError("duplicate key")
        return dict(items)

    def refuse(token):
        raise ValueError(f"{token} is not allowed")

    def depth(node):
        if isinstance(node, dict):
            node = list(node.values())
        if not isinstance(node, list):
            return 0
        return 1 + max((depth(v) for v in node), default=0)

    if len(data) > max_bytes:
        raise ValueError("too large")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=pairs, parse_constant=refuse)
        if not isinstance(value, dict):
            raise ValueError("not a JSON object")
        if depth(value) > MAX_DEPTH:
            raise ValueError("nested too deeply")
    except (UnicodeDecodeError, RecursionError) as exc:
        raise ValueError(type(exc).__name__) from None
    return value


def error_object(code, message, detail=None):
    obj = {"schema": "mozart.error/v1", "error": code, "message": message[:200]}
    if detail:
        obj["detail"] = detail[:400]
    return obj


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


# --- descriptor-relative writes ---------------------------------------------------------------

_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,254}")  # a file name; <63>.<63>.json is 132 characters
STALE_TMP_S = 3600


def _io(fn):
    """Any OSError a descriptor helper lets through becomes a ContractError, never a traceback."""
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except OSError as exc:
            raise ContractError("io-error", f"{fn.__name__}: {exc.strerror or 'I/O error'}") from None
    return wrapper


def _dir_below(ctx, parent_fd, name, create):
    """Open a directory under parent_fd without following a symlink, creating it 0700 if asked.
    Many processes may create the same directory at once: losing that race is fine."""
    if not _NAME.fullmatch(name) and name != ".mozart":
        raise ContractError("bad-request", f"unsafe path component {name!r}")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | _CLOEXEC
    try:
        try:
            fd = os.open(name, flags, dir_fd=parent_fd)
        except FileNotFoundError:
            if not create:
                raise ContractError("refused", f"{name} does not exist") from None
            try:
                os.mkdir(name, 0o700, dir_fd=parent_fd)
            except FileExistsError:
                pass
            fd = os.open(name, flags, dir_fd=parent_fd)
    except OSError:
        raise ContractError("grant-hygiene", f"{name} is a symlink or unreadable") from None
    why = grant.hygiene(ctx.fstat()(fd), True, os.geteuid())
    if why:
        os.close(fd)
        raise ContractError("grant-hygiene", f"{name}: {why}")
    return fd


@_io
def open_resources(ctx, parts=(), create=True):
    """A descriptor for <home>/.mozart/resources/<parts...>, every level checked."""
    fd = os.open(ctx.home, os.O_RDONLY | os.O_DIRECTORY | _CLOEXEC)
    try:
        for name in (".mozart", "resources") + tuple(parts):
            nfd = _dir_below(ctx, fd, name, create)
            os.close(fd)
            fd = nfd
        return fd
    except BaseException:
        os.close(fd)
        raise


@_io
def check_destination(ctx, parts, name):
    """Raise unless resources/<parts>/<name> can be written: every directory passes hygiene and the
    file itself is not a symlink. Callers that write several files check them all first."""
    if not _NAME.fullmatch(name):
        raise ContractError("bad-request", f"unsafe file name {name!r}")
    fd = open_resources(ctx, parts)
    try:
        if _stat.S_ISLNK(os.lstat(name, dir_fd=fd).st_mode):
            raise ContractError("grant-hygiene", f"{name} is a symlink")
    except FileNotFoundError:
        pass
    finally:
        os.close(fd)


def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, OverflowError, ValueError):
        return False  # no such process, or not a pid at all
    except OSError:
        return True
    return True


def _drop_stale_tmp(fd, name):
    """Remove leftovers of a crashed writer of exactly this name: `.<name>.<pid>.<8 hex>.tmp` whose
    process is gone or that is an hour old. A live writer's temp file, and any other name's, stay."""
    pattern = re.compile(rf"\.{re.escape(name)}\.([0-9]{{1,9}})\.[0-9a-f]{{8}}\.tmp")
    for entry in os.listdir(fd):
        m = pattern.fullmatch(entry)
        if not m:
            continue
        try:
            if not _pid_alive(int(m.group(1))) or time.time() - os.lstat(entry, dir_fd=fd).st_mtime > STALE_TMP_S:
                os.unlink(entry, dir_fd=fd)
        except FileNotFoundError:
            pass


@_io
def write_atomic(ctx, parts, name, data, mode=0o600):
    """Write one file under resources/<parts>: temp file in the same directory, fsync, rename
    over the destination (never through a symlink), fsync the directory."""
    check_destination(ctx, parts, name)
    fd = open_resources(ctx, parts)
    try:
        _drop_stale_tmp(fd, name)
        tmp = f".{name}.{os.getpid()}.{os.urandom(4).hex()}.tmp"
        out = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | _CLOEXEC, mode, dir_fd=fd)
        try:
            view = memoryview(data)
            while view:
                view = view[os.write(out, view):]
            os.fsync(out)
        finally:
            os.close(out)
        os.replace(tmp, name, src_dir_fd=fd, dst_dir_fd=fd)
        os.fsync(fd)
    finally:
        os.close(fd)


@_io
def list_below(ctx, parts):
    """Entry names of resources/<parts>, [] when the directory does not exist."""
    try:
        fd = open_resources(ctx, parts, create=False)
    except ContractError as exc:
        if exc.code == "refused":
            return []
        raise
    try:
        return sorted(os.listdir(fd))
    finally:
        os.close(fd)


@_io
def read_below(ctx, parts, name, max_bytes=1 << 20):
    """Read resources/<parts>/<name> through no-follow, non-blocking descriptors with hygiene on every
    level (a FIFO or device is refused, not read); None when it does not exist."""
    data, why = grant.read_file(ctx.home, [".mozart", "resources", *parts, name], ctx.fstat(), max_bytes)
    if data is None and why != "missing":
        raise ContractError("grant-hygiene", f"{name}: {why}")
    return data


# --- the one subprocess runner ----------------------------------------------------------------

def subprocess_env(ctx, tool_path=(), git=False):
    info = pwd.getpwuid(os.geteuid())
    env = {
        "HOME": ctx.home, "USER": info.pw_name, "LOGNAME": info.pw_name, "LANG": "C.UTF-8",
        "TMPDIR": os.path.join(ctx.resources(), "run", "tmp"),
        "PATH": ":".join(list(tool_path) + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]),
    }
    if git:
        env["GIT_NO_REPLACE_OBJECTS"] = "1"
    return env


def _sweep(fd, cutoff, depth=0):
    """Delete entries older than cutoff below fd, directories included, through descriptors. Another
    process may be sweeping or using the same directory, so anything that vanishes is fine."""
    for entry in os.listdir(fd):
        try:
            st = os.lstat(entry, dir_fd=fd)
            if st.st_mtime >= cutoff:
                continue
            if _stat.S_ISDIR(st.st_mode):
                sub = os.open(entry, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | _CLOEXEC, dir_fd=fd)
                try:
                    if depth < 4:
                        _sweep(sub, cutoff, depth + 1)
                finally:
                    os.close(sub)
                os.rmdir(entry, dir_fd=fd)
            else:
                os.unlink(entry, dir_fd=fd)
        except OSError:
            continue


@_io
def run(ctx, argv, stdin=None, timeout=30, cap=1 << 20, tool_path=(), git=False):
    """The only place a subprocess starts. argv only (no shell), a fixed environment, the run/tmp
    directory as cwd (never the caller's), stdin closed unless bytes are given, output capped, the
    whole process group killed on a timeout or a cap overrun. The deadline starts before the first
    byte of stdin is written, and stdin is written from its own thread, so a child that never reads
    cannot stall the caller. Returns (returncode, stdout, stderr, flag): flag is None, "timeout"
    or "oversize"."""
    env = subprocess_env(ctx, tool_path, git)
    if ctx.runner is not None:
        return ctx.runner(argv, env, stdin, timeout, cap)
    tmp = open_resources(ctx, ("run", "tmp"))
    try:
        _sweep(tmp, time.time() - 86400)
    finally:
        os.close(tmp)
    deadline = time.monotonic() + timeout
    proc = subprocess.Popen(argv, env=env, cwd=env["TMPDIR"], start_new_session=True,
                            stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    chunks = {"out": [], "err": []}
    flag = []

    def kill():
        try:
            os.killpg(proc.pid, 9)
        except OSError:
            pass

    def drain(stream, key, limit):
        total = 0
        while True:
            piece = os.read(stream.fileno(), 65536)
            if not piece:
                return
            total += len(piece)
            if total > limit:
                flag.append("oversize")
                kill()
                return
            chunks[key].append(piece)

    def feed():
        try:
            proc.stdin.write(stdin)
            proc.stdin.close()
        except (OSError, ValueError):
            pass

    threads = [threading.Thread(target=drain, args=(proc.stdout, "out", cap), daemon=True),
               threading.Thread(target=drain, args=(proc.stderr, "err", 65536), daemon=True)]
    writer = threading.Thread(target=feed, daemon=True)
    for t in threads:
        t.start()
    if stdin is not None:
        writer.start()
    try:
        proc.wait(timeout=max(0.0, deadline - time.monotonic()))
    except subprocess.TimeoutExpired:
        flag.append("timeout")
        kill()
        proc.wait()
    kill()
    for t in threads + ([writer] if stdin is not None else []):
        t.join(2)
    return proc.returncode, b"".join(chunks["out"]), b"".join(chunks["err"]), (flag[0] if flag else None)


# --- hooks ------------------------------------------------------------------------------------

def _chain_problem(path):
    """Why a directory above the hook cannot be trusted, or None: every ancestor must belong to the
    user or to root and be writable by neither group nor world. A sticky bit is no exemption."""
    parent = os.path.dirname(path)
    while True:
        try:
            st = os.stat(parent)
        except OSError:
            return f"{parent} cannot be inspected"
        if st.st_uid not in (os.geteuid(), 0) or st.st_mode & 0o022:
            return f"{parent} is owned by another user or writable by group or world"
        if os.path.lexists(os.path.join(parent, ".git")):
            return "the hook is inside a git work tree"
        if parent == os.path.dirname(parent):
            return None
        parent = os.path.dirname(parent)


@_io
def hook_hygiene(path, stat_fn=os.fstat):
    """(sha256, None) for a hook the user may trust to run, else (None, reason): absolute and not a
    symlink anywhere in its path, a regular executable file the user owns that others cannot write,
    in a directory chain the user or root owns with no group- or world-writable link, and not
    inside a git work tree.

    Known limit, stated rather than hidden: the digest is taken from the opened descriptor, but the
    hook is then run by path, so there is a window between hashing and exec. Running a copy would
    break hooks that read files beside themselves, and /dev/fd execution is not portable across the
    platforms we support. The directory-chain rule above is what narrows the window to the user's
    own uid."""
    if not os.path.isabs(path) or os.path.realpath(path) != os.path.normpath(path):
        return None, "the hook path must be absolute, normalised and not a symlink"
    problem = _chain_problem(path)
    if problem:
        return None, problem
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | _CLOEXEC)
    except OSError:
        return None, "the hook cannot be opened"
    try:
        why = grant.hygiene(stat_fn(fd), False, os.geteuid())
        if why:
            return None, f"the hook is {why}"
        if not os.access(path, os.X_OK):
            return None, "the hook is not executable"
        digest = hashlib.sha256()
        while True:
            block = os.read(fd, 65536)
            if not block:
                return digest.hexdigest(), None
            digest.update(block)
    finally:
        os.close(fd)


def run_hook(ctx, schema, path, verb, request, expect_sha=None, timeout=None, tool_path=()):
    """Call `<hook> <verb>` with a validated request on stdin and return its validated response.
    Raises ContractError with a code from the schema's error list; nothing from a hook is
    trusted before it has passed the verb's closed response schema."""
    node = schema["hook"][verb]
    problems = validate(request, node["request"], schema)
    if problems:
        raise ContractError("bad-request", "the request does not match its schema", "; ".join(problems[:3]))
    digest, why = hook_hygiene(path, ctx.fstat())
    if why:
        raise ContractError("hook-hygiene", why)
    if expect_sha and digest != expect_sha:
        raise ContractError("hook-hygiene", "the hook's sha256 differs from hook_sha256 in the grant")
    limits = schema["resources_home"]["hook"]
    rc, out, _, flag = run(ctx, [path, verb], json.dumps(request).encode(), timeout or limits["timeout_s"], limits["max_output_bytes"], tool_path)
    if flag:
        raise ContractError("timeout" if flag == "timeout" else "hook-output", f"the hook {flag}")
    try:
        body = loads_strict(out)
    except ValueError as exc:
        raise ContractError("hook-output", f"the hook's output is not a strict JSON object: {exc}") from None
    if rc != 0:
        known = {2: "bad-request", 3: "refused", 4: "provider-error"}
        problems = validate(body, schema["error"], schema)
        code = body.get("error") if not problems else None
        raise ContractError(code if code in schema["error_codes"] else known.get(rc, "provider-error"), "the hook reported an error",
                            None if problems else str(body.get("message", ""))[:200])
    problems = validate(body, node["response"], schema)
    if problems:
        raise ContractError("hook-output", "the hook's response does not match its schema", "; ".join(problems[:3]))
    return body
