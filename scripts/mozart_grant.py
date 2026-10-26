"""mozart_grant - the trust root: where the grant is, whether it may be read, what it says.

Standard library only, and it takes plain parameters (a home path, an environment
mapping, a stat callable), never a Context. Nothing here reads the process
environment, and the grant's location comes from the account record, never from
HOME: a HOME that disagrees with it disables everything.

The grant is a file only the user writes. It enables, it never confirms: a card
is still the user's per-action confirmation.
"""
import copy
import hashlib
import os
import re
import stat as _stat
import unicodedata

BUNDLE_VERSION = "1"


def passwd_home():
    import pwd
    return pwd.getpwuid(os.geteuid()).pw_dir


def child_mode(environ, markers):
    """True when this process is a child session: a marker present (any value, the empty
    string included) or a pass-through marker that is non-empty."""
    return any(k in environ for k in markers["present"]) or any(environ.get(k) for k in markers["non_empty"])


def _open_below(parent_fd, name, want_dir):
    """Open one path component without following a symlink. Returns (fd, None) or (None, reason)."""
    # O_NONBLOCK: opening a planted FIFO must not hang; hygiene() then refuses it as the wrong type.
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0) | (os.O_DIRECTORY if want_dir else 0)
    try:
        return os.open(name, flags, dir_fd=parent_fd), None
    except FileNotFoundError:
        return None, "missing"
    except OSError:
        return None, "symlink-or-unreadable"


def hygiene(st, want_dir, euid):
    """Why an opened component is not trustworthy, or None (checked on the fd's own stat)."""
    if _stat.S_ISDIR(st.st_mode) != want_dir or not (want_dir or _stat.S_ISREG(st.st_mode)):
        return "wrong-type"
    if st.st_uid != euid:
        return "foreign-owner"
    if st.st_mode & 0o022:
        return "group-or-world-writable"
    return None


def read_file(home, parts, stat_fn=os.fstat, max_bytes=65536):
    """Read <home>/<parts...> through O_NOFOLLOW descriptors with hygiene on every one.
    Returns (bytes, None) or (None, reason); reason is "missing" or "hygiene:<why>:<component>"."""
    euid = os.geteuid()
    try:
        fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0))
    except OSError:
        return None, "missing"
    try:
        for i, name in enumerate(parts):
            last = i == len(parts) - 1
            nfd, why = _open_below(fd, name, want_dir=not last)
            if nfd is None:
                return None, "missing" if why == "missing" else f"hygiene:{why}:{name}"
            os.close(fd)
            fd = nfd
            why = hygiene(stat_fn(fd), want_dir=not last, euid=euid)
            if why:
                return None, f"hygiene:{why}:{name}"
        data = b""
        while len(data) <= max_bytes:
            chunk = os.read(fd, 65536)
            if not chunk:
                return data, None
            data += chunk
        return None, "too-large"
    finally:
        os.close(fd)


class GrantError(Exception):
    pass


def printable(text):
    """No control, format, surrogate, separator, private-use or unassigned character (C1, bidi
    overrides, zero-width, BOM, U+2028/2029 included). The Unicode database is the interpreter's own
    and differs between versions: a code point unassigned in an older one reads as Cn here and is
    refused (it fails closed), so a parent and a remote host may disagree about an edge character."""
    return not any(unicodedata.category(c) in ("Cc", "Cf", "Cs", "Zl", "Zp", "Co", "Cn") for c in text)


def _scalar(spec, raw, schema):
    """Convert and check one text value against a key-table entry."""
    kind = spec["type"]
    if kind == "bool":
        if raw not in ("true", "false"):
            raise GrantError("a boolean is exactly true or false")
        return raw == "true"
    if kind == "int":
        if not re.fullmatch(schema["grammars"]["canonical_int"]["pattern"], raw):
            raise GrantError("not a canonical integer")
        val = int(raw)
        if not spec.get("min", val) <= val <= spec.get("max", val):
            raise GrantError(f"outside {spec.get('min')}..{spec.get('max')}")
        return val
    gram = schema["grammars"][spec["grammar"]] if "grammar" in spec else spec
    pattern = gram.get("pattern")
    if pattern and not re.fullmatch(pattern, raw):
        raise GrantError("does not match its grammar")
    if gram.get("no_leading_dash") and raw.startswith("-"):
        raise GrantError("a leading dash is not allowed")
    allowed = schema[spec["enum_from"]] if "enum_from" in spec else spec.get("enum")
    if allowed is not None and raw not in allowed:
        raise GrantError(f"not one of {allowed}")
    if len(raw) > spec.get("maxLength", 4096) or (spec.get("printable") and not printable(raw)):
        raise GrantError("too long or not printable")
    return raw


def _value(spec, raw, schema):
    if raw == "":
        raise GrantError("empty value")
    if spec["type"] in ("list", "kv"):
        items = [p.strip() for p in raw.split(spec["sep"])]
        if "" in items:
            raise GrantError("empty list item")
        if spec["type"] == "list":
            return [_scalar(dict(spec["items"], type="string"), p, schema) for p in items]
        pairs = [i.partition("=") for i in items]
        if any(not sep or not val or "=" in val for _, sep, val in pairs) or len({k for k, _, _ in pairs}) != len(pairs):
            raise GrantError("expected key=value pairs with each key once")
        return {_scalar({"type": "string", "grammar": "fact_key"}, k, schema): _scalar({"type": "string", "pattern": "[A-Za-z0-9._+-]{1,64}"}, v, schema) for k, _, v in pairs}
    return _scalar(spec, raw, schema)


def _heading(title, sections, schema):
    """(kind, label) for a `## ` heading, or raise."""
    for kind, sec in sections.items():
        if "heading" in sec and title == sec["heading"]:
            return kind, None
        prefix = sec.get("heading_prefix")
        if prefix and title.startswith(prefix):
            label = title[len(prefix):]
            if not re.fullmatch(schema["grammars"]["label"]["pattern"], label):
                raise GrantError(f"label {label!r} is not a valid label")
            return kind, label
    raise GrantError(f"unknown section {title!r}")


def parse(data, schema, sections=None, need="remote_execution"):
    """Parse grant bytes strictly. Returns {"remote_execution", "hosts", "providers", "discovery_hooks"};
    raises GrantError("line N: ...") on the first problem, so a grant is never partly enabled.
    The registry reuses it with its own `sections` table and need=None."""
    if data.startswith(b"\xef\xbb\xbf"):
        raise GrantError("a byte-order mark is not allowed")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise GrantError("not valid UTF-8") from None
    if "\r" in text or re.search("[\\x00-\\x09\\x0b-\\x1f\\x7f]", text):
        raise GrantError("CR, NUL and control characters are not allowed (LF line endings only)")
    sections = sections or schema["grant"]["sections"]
    out = {"remote_execution": None, "hosts": {}, "providers": {}, "discovery_hooks": {}}
    kind = label = table = seen = None
    seen_sections = set()

    def close(n):
        if table is not None:
            missing = [k for k, v in table.items() if v.get("required") and k not in seen]
            if missing:
                raise GrantError(f"section {kind} lacks required key(s) {missing}")

    lines = text.split("\n")
    for n, line in enumerate(lines + [None], 1):
        try:
            if line is None or line.startswith("## "):
                close(n)
                if line is None:
                    break
                kind, label = _heading(line[3:], sections, schema)
                if (kind, label) in seen_sections:
                    raise GrantError("duplicate section")
                seen_sections.add((kind, label))
                if label is not None and any(k == kind and l is not None and l != label and l.casefold() == label.casefold() for k, l in seen_sections):
                    raise GrantError(f"label {label!r} collides with another label when case is folded")
                table, seen = sections[kind].get("keys"), set()
                if kind == "remote_execution":
                    out[kind] = {}
                elif kind in ("host", "provider"):
                    out[kind + "s"][label] = {}
            elif line == "":
                continue
            elif line.startswith("- ") and kind:
                key, sep, raw = line[2:].partition(": ")
                if not sep or key in seen:
                    raise GrantError("expected `- key: value` with a key used once")
                seen.add(key)
                if kind == "discovery_hooks":
                    if not re.fullmatch(schema["grammars"]["label"]["pattern"], key):
                        raise GrantError(f"hook name {key!r} is not a valid label")
                    if any(k.casefold() == key.casefold() for k in out["discovery_hooks"]):
                        raise GrantError("hook names collide when case is folded")
                    out["discovery_hooks"][key] = _scalar(sections[kind]["value"], raw, schema)
                elif key not in table:
                    raise GrantError(f"unknown key {key!r}")
                else:
                    dest = out[kind] if kind == "remote_execution" else out[kind + "s"][label]
                    dest[key] = _value(table[key], raw, schema)
            else:
                raise GrantError("only `## Section` headings and `- key: value` bullets are allowed")
        except GrantError as exc:
            raise GrantError(f"line {n}: {exc}") from None
    if need and out[need] is None:
        raise GrantError(f"the file has no `## {sections[need]['heading']}` section")
    for kind in ("remote_execution", "host", "provider"):
        for dest in ([out[kind]] if kind == "remote_execution" else out[kind + "s"].values()):
            for key, spec in sections.get(kind, {}).get("keys", {}).items():
                dest.setdefault(key, copy.deepcopy(spec.get("default")))
    return out


def load(home, schema, environ, stat_fn=os.fstat):
    """The grant state: {"enabled", "reason", "detail", "sha256", "grant", "raw"}.

    Order matters. A child session reads nothing at all. A HOME that is set and differs from
    the account record's home disables everything before any file is opened. Only then is
    the file read, through descriptors that refuse symlinks and untrusted owners."""
    def state(reason, detail=None, **more):
        return dict({"enabled": False, "reason": reason, "detail": detail, "sha256": None, "grant": None, "raw": None}, **more)

    if child_mode(environ, schema["grant"]["child_markers"]):
        return state("child-session")
    env_home = environ.get("HOME")
    if env_home is not None and os.path.realpath(env_home) != os.path.realpath(home):
        return state("home-mismatch")
    data, why = read_file(home, [".mozart", "resources", "grant.md"], stat_fn, schema["grant"]["max_bytes"])
    if data is None:
        return state("no-grant" if why == "missing" else "grant-hygiene" if why.startswith("hygiene") else "grant-invalid", why)
    digest = hashlib.sha256(data).hexdigest()
    try:
        grant = parse(data, schema)
    except GrantError as exc:
        return state("grant-invalid", str(exc), sha256=digest)
    enabled = grant["remote_execution"]["enabled"]
    return state(None if enabled else "grant-disabled", enabled=enabled, sha256=digest, grant=grant, raw=data)
