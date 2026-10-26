#!/usr/bin/python3
"""mozart-resources - which hosts mozart has, what each can do, and whether a phase fits.

Run it only as the manual says: through the installed launcher, `/usr/bin/env -i
/usr/bin/python3 -I <bin>/mozart-resources.py <verb> ...`. Every answer is one line of JSON.

  grant [--diff SHA]          what the user's grant enables (and what changed since SHA)
  show [LABEL]                the registry: every host with its facts, sources and conflicts
  facts --local               this machine's facts, from the probe
  discover                    run the grant's discovery hooks and keep their static facts
  match --requires TERMS      which hosts, and this machine, satisfy a requirement list
"""
import argparse
import json
import os
import re
import sys
from fractions import Fraction

BUNDLE_VERSION = "1"


def _boot(home):
    """Check the launcher's own location and every bundle file, then run the bundle from the
    bytes that were checked. Byte-identical in every CLI; raises RuntimeError(<error code>)."""
    import stat as st
    import types
    sys.dont_write_bytecode = True
    if not sys.flags.isolated:
        raise RuntimeError("not-isolated")
    here = os.path.realpath(os.path.dirname(os.path.abspath(__file__)))
    if here != os.path.join(os.path.realpath(home), ".mozart", "bin"):
        raise RuntimeError("launcher-location")
    flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)

    def trusted(fd, is_dir):
        info = os.fstat(fd)
        return (st.S_ISDIR(info.st_mode) if is_dir else st.S_ISREG(info.st_mode)) and info.st_uid == os.geteuid() and not info.st_mode & 0o022
    try:
        fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY)
        for name in (".mozart", "bin"):
            nfd = os.open(name, flags | os.O_DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = nfd
            if not trusted(fd, True):
                raise RuntimeError("bundle-integrity")

        def read(name):
            f = os.open(name, flags, dir_fd=fd)
            try:
                if not trusted(f, False):
                    raise RuntimeError("bundle-integrity")
                return b"".join(iter(lambda: os.read(f, 65536), b""))
            finally:
                os.close(f)
        raw = read("mozart-schemas.json")
        schema = json.loads(raw)
        version, listed = schema["bundle_version"], schema["bundle"]["files"]
        if not all(isinstance(n, str) and n and "/" not in n and ".." not in n and "\0" not in n for n in listed):
            raise RuntimeError("bundle-integrity")
        files = {"mozart-schemas.json": (raw, os.path.join(here, "mozart-schemas.json"))}
        for name in listed:
            files.setdefault(name, (read(name), os.path.join(here, name)))
        mod = types.ModuleType("mozart_contract")
        mod.__file__ = files["mozart_contract.py"][1]
        mod._SOURCES = files
        sys.modules["mozart_contract"] = mod
        exec(compile(files["mozart_contract.py"][0], mod.__file__, "exec"), mod.__dict__)
        if BUNDLE_VERSION != version or mod.BUNDLE_VERSION != version:
            raise RuntimeError("bundle-integrity")
    except RuntimeError:
        raise
    except Exception:  # noqa: BLE001 - whatever a damaged bundle throws is one answer: bundle-integrity
        raise RuntimeError("bundle-integrity") from None
    return mod


# --- the matcher: pure functions over facts, no I/O ------------------------------------------------

BARE = re.compile(r"[a-z][a-z0-9_]{0,31}")
TERM = re.compile(r"([a-z][a-z0-9_]{0,31})(!=|>=|<=|=)(.*)")
IN_TERM = re.compile(r"([a-z][a-z0-9_]{0,31}) in (.*)")
TOKEN = re.compile(r"[A-Za-z0-9._+-]+")
DOTTED = re.compile(r"[0-9]+(\.[0-9]+)*")
NUMBER = re.compile(r"(0|[1-9][0-9]*)(\.[0-9]+)?")
ORDERED = (">=", "<=")


class Usage(Exception):
    pass


def fact_class(spec):
    if spec["type"] == "string" and spec.get("grammar") == "version":
        return "version"
    return spec["type"]


def check_value(cls, op, value, schema):
    if cls == "version" and not DOTTED.fullmatch(value):
        raise Usage(f"{shown(value)} is not a plain dotted version (no leading v, suffix or empty segment)")
    if cls == "int" and not re.fullmatch(r"(0|[1-9][0-9]*)", value):
        raise Usage(f"{value!r} is not an integer")
    if cls == "number" and not NUMBER.fullmatch(value):
        raise Usage(f"{value!r} is not a number")
    if cls == "bool" and value not in ("true", "false"):
        raise Usage(f"{value!r} is not true or false")
    plain = schema["grammars"]["kube_name"]["pattern"] if cls == "map" else TOKEN.pattern
    if cls in ("string", "list", "map") and not re.fullmatch(plain, value):
        raise Usage(f"{value!r} is not a plain value")
    if op in ORDERED and cls not in ("version", "int", "number"):
        raise Usage(f"{op} needs a version, integer or number fact")


def parse_requirements(text, schema):
    """Terms from `a=1,b>=2,c in x|y`. No whitespace except the one in ` in `, no empty item, no
    repeated key, no unknown fact. A requirement list never tolerates anything: tolerations come
    from the grant or through match's separate --tolerates, so a repo stanza cannot grant one."""
    if not text:
        raise Usage("the requirement list is empty")
    terms, seen = [], set()
    for item in text.split(","):
        if item == "" or item != item.strip() or re.search(r"\s", item.replace(" in ", "", 1)):
            raise Usage(f"malformed term {item!r}")
        m = IN_TERM.fullmatch(item)
        if m:
            key, op, values = m.group(1), "in", m.group(2).split("|")
        elif BARE.fullmatch(item):
            key, op, values = item, "", []
        else:
            m = TERM.fullmatch(item)
            if not m:
                raise Usage(f"malformed term {item!r}")
            key, op, values = m.group(1), m.group(2), [m.group(3)]
        if "" in values or (op == "in" and len(values) < 1):
            raise Usage(f"{item!r} has an empty alternative")
        if key == "tolerates":
            raise Usage("tolerates is not a requirement; pass a phase's tolerations with --tolerates")
        if key not in schema["facts"]:
            raise Usage(f"unknown fact {key!r}")
        if key in seen:
            raise Usage(f"{key!r} appears twice")
        seen.add(key)
        for value in values:
            check_value(fact_class(schema["facts"][key]), op, value, schema)
        terms.append({"key": key, "op": op, "values": values})
    return terms


def render(terms):
    return ",".join(t["key"] if not t["op"] else f"{t['key']} in {'|'.join(t['values'])}" if t["op"] == "in"
                    else f"{t['key']}{t['op']}{t['values'][0]}" for t in terms)


def comparable(cls, raw):
    """A fact value or requirement value in a form where == and < mean what they should."""
    if cls == "version":
        if not isinstance(raw, str) or not DOTTED.fullmatch(raw):
            raise ValueError(f"{shown(raw)} is not a plain version")
        parts = [int(p) for p in raw.split(".")]
        while len(parts) > 1 and parts[-1] == 0:
            parts.pop()
        return tuple(parts)
    if cls == "number":
        return Fraction(str(raw))
    if cls == "int":
        return int(raw)
    if cls == "bool":
        return raw if isinstance(raw, bool) else raw == "true"
    return raw


def shown(value):
    """A fact value as it may appear in a reason: its repr (which escapes anything unprintable), cut short."""
    text = repr(value)
    return text if len(text) <= 60 else text[:59] + "\u2026"


def judge(term, entry, spec):
    """('ok'|'no'|'unknown', reason) for one term against one fact entry
    ({"value", "stale", "live"}) or None when nothing is known about the fact."""
    key, op = term["key"], term["op"]
    if entry is None:
        return "unknown", f"unknown: {key} is not known for this host"
    if entry.get("stale"):
        return "unknown", f"unknown: {key} is stale"
    if spec["kind"] == "dynamic" and not entry.get("live"):
        return "unknown", f"unknown: {key} is dynamic and needs a live identify"
    value = entry["value"]
    if op == "":
        return ("ok", "") if value is not None else ("no", f"{key} is null")
    if value is None:
        return "unknown", f"unknown: {key} is null"
    cls = fact_class(spec)
    try:
        if cls == "map":
            answers = [value.get(v) for v in term["values"]]  # True, False, or None when the name was not asked about
            if True in answers:
                return ("ok", "") if op in ("=", "in") else ("no", f"{key} has that context")
            if None in answers:
                return "unknown", f"unknown: {key} was not asked about that name"
            return ("no", f"{key} lacks that context") if op in ("=", "in") else ("ok", "")
        if cls == "list":
            member = any(v in value for v in term["values"])
            return ("ok", "") if member == (op in ("=", "in")) else ("no", f"{key} {'lacks' if op != '!=' else 'has'} {'|'.join(term['values'])}"[:200])
        fact = comparable(cls, value)
        wanted = [comparable(cls, v) for v in term["values"]]
    except ValueError as exc:
        return "no", f"{key}: {exc}"[:200]
    verdict = {"=": fact == wanted[0], "in": fact in wanted, "!=": fact != wanted[0],
               ">=": cls != "bool" and fact >= wanted[0], "<=": cls != "bool" and fact <= wanted[0]}[op]
    return ("ok", "") if verdict else ("no", f"{key} is {shown(value)}, wanted {op} {'|'.join(term['values'])}"[:200])


def evaluate(terms, entries, schema, taints=(), tolerates=()):
    """('match'|'reject'|'unknown', reasons) for a requirement list against {fact: entry}. A host with a
    taint nobody tolerates is rejected; any 'no' rejects; otherwise any 'unknown' means unknown."""
    reasons = [f"taint:{t}" for t in taints if t not in set(tolerates)]
    unknown = []
    for term in terms:
        verdict, why = judge(term, entries.get(term["key"]), schema["facts"][term["key"]])
        if verdict == "no":
            reasons.append(why)
        elif verdict == "unknown":
            unknown.append(why)
    if reasons:
        return "reject", reasons + unknown
    return ("unknown", unknown) if unknown else ("match", [])


# --- the verbs ---------------------------------------------------------------------------------------

HARD_REFUSALS = ("child-session", "home-mismatch", "grant-hygiene", "grant-invalid")


def grant_report(gstate):
    g = gstate["grant"]
    report = {"schema": "mozart.grant/v1", "enabled": gstate["enabled"], "reason": gstate["reason"], "detail": gstate["detail"],
              "sha256": gstate["sha256"]}
    if g:
        report.update(repos=g["remote_execution"]["repos"], hosts={k: {"trust": v["trust"], "transport": v["transport"]} for k, v in g["hosts"].items()},
                      providers=sorted(g["providers"]), discovery_hooks=sorted(g["discovery_hooks"]))
    return report


def tool_path_of(gstate):
    return gstate["grant"]["remote_execution"]["tool_path"] if gstate["grant"] else []


def local_entries(doc, schema):
    return {k: {"value": doc[k], "stale": False, "live": True} for k in schema["facts"] if k in doc}


def cmd_match(a, ctx, contract, state, gstate, schema):
    """Exit 0 when this machine matches or a DISPATCHABLE host matches; 3 otherwise, even if a host
    that cannot be dispatched to matches (it is still listed, with why not); 2 for a bad request."""
    try:
        terms = parse_requirements(a.requires, schema)
        tolerated = set(filter(None, (a.tolerates or "").split(",")))
        if not all(re.fullmatch(schema["grammars"]["label"]["pattern"], t) for t in tolerated):
            raise Usage("--tolerates takes a comma-separated list of taint names")
    except Usage as exc:
        raise contract.ContractError("usage", str(exc)) from None
    asked = {k for k, spec in schema["facts"].items() if spec["type"] == "map"}  # request-scoped facts: the probe is told which names to answer for
    names = sorted({v for t in terms if t["key"] in asked for v in t["values"]})
    hosts, problems = state.merged_hosts(ctx, schema, gstate)
    matches, rejects = [], []
    for label, host in hosts.items():
        entries = {k: {"value": f["value"], "stale": f["stale"], "live": False} for k, f in host["facts"].items()}
        verdict, why = evaluate(terms, entries, schema, host["taints"], set(host["tolerates"]) | tolerated)
        if verdict == "match":
            matches.append({"label": label, "trust": host["trust"], "dispatchable": host["dispatchable"], "reasons": host["why_not"]})
        else:
            rejects.append({"label": label, "reasons": why})
    try:
        verdict, why = evaluate(terms, local_entries(state.local_facts(ctx, schema, names, tool_path_of(gstate)), schema), schema)
        local = {"matches": verdict == "match", "reasons": why}
    except contract.ContractError as exc:
        local = {"matches": False, "reasons": [f"the local probe failed: {exc.code}"]}
    result = {"schema": "mozart.match/v1", "matches": matches, "rejects": rejects, "local": local}
    bad = contract.validate(result, schema["match"]["result"], schema)
    if bad:
        raise contract.ContractError("usage", "internal: the match result does not match its schema", bad[0])
    ok = local["matches"] or any(m["dispatchable"] for m in matches)
    return result, 0 if ok else 3


def cmd_discover(ctx, contract, state, gstate, schema):
    if not gstate["enabled"]:
        raise contract.ContractError("grant-disabled" if gstate["reason"] == "grant-disabled" else "no-grant", "discover needs an enabled grant")
    out, worst = {}, 0
    providers = list(gstate["grant"]["providers"].values())
    for name, path in sorted(gstate["grant"]["discovery_hooks"].items()):
        pin = next((p for p in providers if p["hook"] == path), {})  # a provider block for the same hook pins its sha and timeout
        try:
            hosts = contract.run_hook(ctx, schema, path, "discover", {}, expect_sha=pin.get("hook_sha256"),
                                      timeout=pin.get("hook_timeout_s"), tool_path=tool_path_of(gstate))["hosts"]
            out[name] = {"written": state.persist_discovered(ctx, schema, name, hosts, state.declared_labels(ctx, schema, gstate))}
        except contract.ContractError as exc:
            out[name] = {"error": exc.code, "message": exc.message}
            worst = max(worst, exit_for(exc.code, schema))
    return {"schema": "mozart.discover/v1", "hooks": out}, worst


def exit_for(code, schema):
    codes = schema["exit_codes"]
    if code in ("bad-request", "usage"):
        return codes["bad_request"]
    if code in ("provider-error", "quota", "capacity", "timeout", "hook-output"):
        return codes["provider_error"]
    if code == "internal":
        return codes["internal"]
    return codes["refused"]


def run_verb(a, ctx, contract, grant, state, schema):
    gstate = grant.load(ctx.home, schema, ctx.environ, ctx.fstat())
    if a.verb == "grant":
        report = grant_report(gstate)
        if a.diff:
            if gstate["reason"] in HARD_REFUSALS or gstate["raw"] is None:
                raise contract.ContractError(gstate["reason"] or "no-grant", "the grant cannot be read, so it cannot be diffed")
            old = state.read_snapshot(ctx, schema, a.diff)
            return {"schema": "mozart.grant-diff/v1", "from": a.diff, "to": gstate["sha256"], "changed": a.diff != gstate["sha256"],
                    "diff": state.diff_grant(old, gstate["raw"], f"snapshot {a.diff[:12]}", "current")}, 0
        if gstate["raw"] is not None:
            try:
                state.snapshot_grant(ctx, gstate["raw"])
            except contract.ContractError as exc:
                report["snapshot_error"] = exc.code
        return report, 0
    if gstate["reason"] in HARD_REFUSALS:
        raise contract.ContractError(gstate["reason"], f"every verb refuses while the grant state is {gstate['reason']}", gstate["detail"])
    if a.verb == "show":
        hosts, problems = state.merged_hosts(ctx, schema, gstate)
        if a.label:
            if a.label not in hosts:
                raise contract.ContractError("unknown-label", "no such host")
            hosts = {a.label: hosts[a.label]}
        return {"schema": "mozart.show/v1", "grant": {"enabled": gstate["enabled"], "reason": gstate["reason"]}, "hosts": hosts, "problems": problems}, 0
    if a.verb == "facts":
        return {"schema": "mozart.facts/v1", "facts": state.local_facts(ctx, schema, a.kube_context, tool_path_of(gstate))}, 0
    if a.verb == "discover":
        return cmd_discover(ctx, contract, state, gstate, schema)
    return cmd_match(a, ctx, contract, state, gstate, schema)


def build_parser(fail):
    class Parser(argparse.ArgumentParser):
        def error(self, message):
            fail(message)
    p = Parser(prog="mozart-resources.py", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="verb", required=True, parser_class=Parser)
    g = sub.add_parser("grant")
    g.add_argument("--json", action="store_true", help="accepted for callers that say so; output is always JSON")
    g.add_argument("--diff", metavar="SHA", help="the 64-hex sha256 of an earlier grant snapshot")
    s = sub.add_parser("show")
    s.add_argument("label", nargs="?")
    f = sub.add_parser("facts")
    f.add_argument("--local", action="store_true", required=True)
    f.add_argument("--kube-context", action="append", default=[], metavar="NAME")
    sub.add_parser("discover")
    m = sub.add_parser("match")
    m.add_argument("--requires", required=True, metavar="TERMS")
    m.add_argument("--tolerates", metavar="TAINTS", help="comma-separated taints this request tolerates (a phase's tolerations)")
    return p


INTERNAL_EXIT = 70  # also schema["exit_codes"]["internal"]; kept here for a failure before the schema is loaded


def main(argv, ctx=None):
    contract = sys.modules["mozart_contract"]
    schema = None

    def fail(message):
        raise contract.ContractError("usage", message)
    try:
        load_sibling = contract.load_sibling
        grant, state = load_sibling("mozart_grant"), load_sibling("mozart_state")
        load_sibling("mozart_contract")
        schema = contract.load_schema()
        out, code = run_verb(build_parser(fail).parse_args(argv), ctx or contract.Context.production(), contract, grant, state, schema)
    except contract.ContractError as exc:
        out, code = contract.error_object(exc.code, exc.message, exc.detail), exit_for(exc.code, schema) if schema else INTERNAL_EXIT
    except Exception as exc:  # noqa: BLE001 - a verb never ends in a traceback; this is the documented exit 70
        out, code = contract.error_object("internal", f"internal error ({type(exc).__name__})"), INTERNAL_EXIT
    print(json.dumps(out, sort_keys=True))
    return code


if __name__ == "__main__":
    import pwd
    try:
        _boot(pwd.getpwuid(os.geteuid()).pw_dir)
    except RuntimeError as boot_error:
        print(json.dumps({"schema": "mozart.error/v1", "error": str(boot_error), "message": "the launcher refused to start"}))
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
