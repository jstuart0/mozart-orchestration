"""Test-only helpers for scripts/check-resources.py. Production code never imports this.

Each function takes the scripts directory under test and a JSON-able args dict and returns
a JSON-able result. tests/resources/drive.py runs one of them in a fresh `python -I`
process, so the bundle's modules (which register themselves in sys.modules under their own
names) never meet a second copy, and nothing is shared with the checker's threads.

This is the one place besides Context.production() that builds a Context.
"""
import dataclasses
import importlib.util
import io
import json
import os
import random
import sys
import types
from contextlib import redirect_stdout


def load_bundle(scripts):
    """Run the bundle from `scripts` without the launcher's checks (the launcher has its own tests)."""
    scripts = os.path.realpath(scripts)
    raw = open(os.path.join(scripts, "mozart-schemas.json"), "rb").read()
    schema = json.loads(raw)
    files = {"mozart-schemas.json": (raw, os.path.join(scripts, "mozart-schemas.json"))}
    for name in schema["bundle"]["files"]:
        path = os.path.join(scripts, name)
        files.setdefault(name, (open(path, "rb").read(), path))
    contract = types.ModuleType("mozart_contract")
    contract.__file__ = files["mozart_contract.py"][1]
    contract._SOURCES = files
    sys.modules["mozart_contract"] = contract
    exec(compile(files["mozart_contract.py"][0], contract.__file__, "exec"), contract.__dict__)
    spec = importlib.util.spec_from_file_location("mozart_resources_cli", os.path.join(scripts, "mozart-resources.py"))
    cli = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cli)
    return types.SimpleNamespace(contract=contract, grant=contract.load_sibling("mozart_grant"), state=contract.load_sibling("mozart_state"),
                                 cli=cli, schema=schema, scripts=scripts)


def make_ctx(b, args):
    """A Context for args["home"]; the seams a case asks for are filled in, the rest stay None."""
    home = args["home"]
    environ = args.get("environ", {"HOME": home})
    now = (lambda: args["now"]) if "now" in args else None
    stat = None
    if "foreign_at" in args:
        calls = []

        def stat(fd):
            real = os.fstat(fd)
            calls.append(fd)
            uid = real.st_uid + 1 if len(calls) - 1 == args["foreign_at"] else real.st_uid
            return types.SimpleNamespace(st_mode=real.st_mode, st_uid=uid)
    runner = None
    if any(k in args for k in ("probe_doc", "probe_fail", "probe_raw", "probe_marker", "probe_boom")):
        real_ctx = b.contract.Context(home=home, environ=environ)

        def runner(argv, env, stdin, timeout, cap):
            if argv[:1] != ["/bin/sh"]:
                return b.contract.run(real_ctx, argv, stdin, timeout, cap)
            if args.get("probe_boom"):  # an unexpected failure inside a verb
                raise RuntimeError("secret detail that must not reach the output")
            if "probe_marker" in args:  # proof that a probe was (not) started
                open(args["probe_marker"], "a").write("probe\n")
            if "probe_raw" in args:  # a canned answer: {"rc", "out", "flag"}
                raw = args["probe_raw"]
                return raw.get("rc", 0), raw["out"].encode("utf-8", "surrogateescape"), b"", raw.get("flag")
            if args.get("probe_fail"):
                return 1, b"", b"", None
            doc = dict(args["probe_doc"])
            names = [argv[i + 1] for i, a in enumerate(argv) if a == "--kube-context"]
            if names:
                doc["kube_contexts"] = {n: n in args.get("known_contexts", []) for n in names}
            doc["kube_contexts"] = dict(doc.get("kube_contexts") or {}, **args.get("inject_kube", {}))
            return 0, json.dumps(doc).encode() + b"\n", b"", None
    return b.contract.Context(home=home, environ=environ, now=now, runner=runner, stat=stat)


def grant_load(scripts, args):
    b = load_bundle(scripts)
    out = {}
    for case in args["cases"]:
        state = b.grant.load(case["home"], b.schema, case.get("environ", {"HOME": case["home"]}), make_ctx(b, case).fstat())
        out[case["id"]] = {k: state[k] for k in ("enabled", "reason", "detail", "sha256")}
    return out


def run_cli(scripts, args):
    b = load_bundle(scripts)
    results = []
    for call in args["calls"]:
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = b.cli.main(call["argv"], make_ctx(b, dict(args, **call)))
        results.append({"code": code, "out": json.loads(buf.getvalue())})
    return results


def validate_batch(scripts, args):
    b = load_bundle(scripts)
    return {c["id"]: b.contract.validate(c["value"], c["spec"], b.schema) for c in args["cases"]}


def loads_batch(scripts, args):
    b = load_bundle(scripts)
    out = {}
    for c in args["cases"]:
        try:
            b.contract.loads_strict(c["text"].encode("utf-8", "surrogateescape"))
            out[c["id"]] = None
        except ValueError as exc:
            out[c["id"]] = str(exc)
    return out


def matcher_batch(scripts, args):
    b = load_bundle(scripts)
    out = {}
    for c in args["cases"]:
        try:
            terms = b.cli.parse_requirements(c["requires"], b.schema)
        except b.cli.Usage as exc:
            out[c["id"]] = {"error": str(exc)}
            continue
        verdict, reasons = b.cli.evaluate(terms, c.get("entries", {}), b.schema, c.get("taints", ()), c.get("tolerates", ()))
        out[c["id"]] = {"verdict": verdict, "reasons": reasons, "render": b.cli.render(terms)}
    return out


def matcher_properties(scripts, args):
    """Seeded property tests: version order is tuple order, parse(render(x)) == x, and adding a
    term to a requirement list never adds a match."""
    b = load_bundle(scripts)
    rng = random.Random(args["seed"])
    facts = b.schema["facts"]
    versioned = sorted(k for k, s in facts.items() if s.get("grammar") == "version")
    ints = sorted(k for k, s in facts.items() if s["type"] == "int")
    bools = sorted(k for k, s in facts.items() if s["type"] == "bool")
    bad = []

    def version():
        return ".".join(str(rng.randint(0, 30)) for _ in range(rng.randint(1, 4))) + ".0" * rng.randint(0, 2)

    def norm(text):
        parts = [int(p) for p in text.split(".")]
        while len(parts) > 1 and parts[-1] == 0:
            parts.pop()
        return tuple(parts)

    def term():
        kind = rng.choice(["version", "int", "bool"])
        key = rng.choice({"version": versioned, "int": ints, "bool": bools}[kind])
        value = {"version": version, "int": lambda: str(rng.randint(0, 99)), "bool": lambda: rng.choice(["true", "false"])}[kind]
        op = rng.choice(["", "=", "!=", "in"] + ([">=", "<="] if kind != "bool" else []))
        values = [] if op == "" else [value(), value()] if op == "in" else [value()]
        return {"key": key, "op": op, "values": values}

    def entry(key):
        spec = facts[key]
        value = {"int": lambda: rng.randint(0, 99), "bool": lambda: rng.choice([True, False])}.get(spec["type"], version)()
        return {"value": value, "stale": rng.random() < 0.1, "live": rng.random() < 0.5}

    def targeted():
        base = [rng.randint(0, 30) for _ in range(rng.randint(1, 4))]
        other = list(base)
        other[-1] = max(0, other[-1] + rng.choice([-1, 1]))
        yield ".".join(map(str, base)), ".".join(map(str, base))              # have == want
        yield ".".join(map(str, base)), ".".join(map(str, other))             # the last segment +-1
        yield ".".join(map(str, base)) + ".0" * rng.randint(1, 3), ".".join(map(str, base))  # padding with .0
        yield ".".join(map(str, base)), ".".join(map(str, base)) + ".0" * rng.randint(1, 3)

    pairs = [(version(), version()) for _ in range(args["n"])]
    for _ in range(args["n"] // 4):
        pairs.extend(targeted())
    for have, want in pairs:
        entries = {"xcodebuild": {"value": have, "stale": False, "live": False}}
        for op, expected in ((">=", norm(have) >= norm(want)), ("<=", norm(have) <= norm(want)), ("=", norm(have) == norm(want))):
            got = b.cli.evaluate(b.cli.parse_requirements(f"xcodebuild{op}{want}", b.schema), entries, b.schema)[0]
            if (got == "match") != expected:
                bad.append(f"xcodebuild {have} {op} {want}: got {got}")
        terms, seen = [], set()
        for _ in range(rng.randint(1, 4)):
            t = term()
            if t["key"] not in seen:
                seen.add(t["key"])
                terms.append(t)
        text = b.cli.render(terms)
        if b.cli.parse_requirements(text, b.schema) != terms:
            bad.append(f"parse(render(x)) != x for {text!r}")
        entries = {k: entry(k) for k in sorted(seen) if rng.random() < 0.8}
        if len(terms) > 1:
            fewer = terms[:-1]
            if b.cli.evaluate(terms, entries, b.schema)[0] == "match" and b.cli.evaluate(fewer, entries, b.schema)[0] != "match":
                bad.append(f"adding {terms[-1]} to {b.cli.render(fewer)} added a match")
    return bad


def write_one(scripts, args):
    b = load_bundle(scripts)
    ctx = b.contract.Context(home=args["home"], environ={"HOME": args["home"]})
    b.contract.write_atomic(ctx, tuple(args["parts"]), args["name"], args["data"].encode())
    return "ok"


def hook_hygiene_batch(scripts, args):
    b = load_bundle(scripts)
    return {path: b.contract.hook_hygiene(path)[1] for path in args["paths"]}


def stalled_stdin(scripts, args):
    """A child that never reads its stdin is given more than a pipe buffer holds; the runner must still
    honour its timeout. Returns how long that took and the flag."""
    import time
    b = load_bundle(scripts)
    ctx = b.contract.Context(home=args["home"], environ={"HOME": args["home"]})
    start = time.monotonic()
    rc, out, err, flag = b.contract.run(ctx, ["/bin/sleep", "30"], stdin=b"x" * (4 << 20), timeout=args["timeout"])
    return {"secs": time.monotonic() - start, "flag": flag}


def hammer(scripts, args):
    """One of N concurrent processes: create the same directories, write the same names (and a name that
    is a prefix of another), and run the runner's temp sweep, repeatedly. Returns what each step did."""
    b = load_bundle(scripts)
    ctx = b.contract.Context(home=args["home"], environ={"HOME": args["home"]})
    me = args["who"]
    errors = []
    for i in range(args["rounds"]):
        try:
            os.close(b.contract.open_resources(ctx, ("shared", "deeper")))
            b.contract.write_atomic(ctx, ("shared",), "a.json", f"writer-{me}-{i}\n".encode() * 2000)
            b.contract.write_atomic(ctx, ("shared",), "a.json.b", f"other-{me}-{i}\n".encode())
            if i % 5 == 0:
                b.contract.run(ctx, ["/bin/echo", "x"])
        except b.contract.ContractError as exc:
            errors.append(f"{exc.code}: {exc.message}")
    return errors


def boot_copy(scripts, args):
    """Load the CLI from `scripts` (a copy placed under <home>/.mozart/bin) and run its launcher
    self-check against args["home"]; optionally run a verb afterwards through Context.production()
    with only the home replaced, so the production environment path is what answers."""
    spec = importlib.util.spec_from_file_location("mozart_resources_copy", os.path.join(scripts, "mozart-resources.py"))
    cli = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cli)
    if "fake_euid" in args:  # the owner check: pretend to be another user without being root
        os.geteuid = lambda: args["fake_euid"]
    try:
        contract = cli._boot(args["home"])
    except RuntimeError as exc:
        return {"boot": str(exc)}
    out = {"boot": "ok"}
    for name in args.get("load", []):
        try:
            contract.load_sibling(name)
            out[name] = "ok"
        except Exception as exc:  # noqa: BLE001 - the caller wants the refusal's code
            out[name] = getattr(exc, "code", type(exc).__name__)
    if args.get("argv"):
        ctx = contract.Context.production()
        ctx = dataclasses.replace(ctx, home=args["home"], environ={"HOME": args["home"]})
        buf = io.StringIO()
        with redirect_stdout(buf):
            out["code"] = cli.main(args["argv"], ctx)
        out["out"] = json.loads(buf.getvalue())
        out["testing_imported"] = "testing" in sys.modules
    return out


def production_context(scripts, args):
    b = load_bundle(scripts)
    ctx = b.contract.Context.production()
    return {"home": ctx.home, "environ": sorted(ctx.environ), "hooks": [getattr(ctx, k) for k in ("now", "runner", "remote_home", "stat", "sleep_hook")],
            "ssh_bin": ctx.ssh_bin}


def sweep(scripts, args):
    """The state of args["home"]'s grant through the production environment path (real os.environ)."""
    b = load_bundle(scripts)
    ctx = dataclasses.replace(b.contract.Context.production(), home=args["home"])
    state = b.grant.load(ctx.home, b.schema, ctx.environ, ctx.fstat())
    return {k: state[k] for k in ("enabled", "reason")}
