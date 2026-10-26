"""mozart_state - what mozart knows about hosts, and where it keeps it.

The registry layers (declared, discovered, this machine's own probe), the grant
snapshots, and the rule for when a host is dispatchable. Phase 3 adds the lease and
card ledgers here. Every read and write goes through mozart_contract's no-follow,
hygiene-checked descriptors; nothing here starts a process except by contract.run.
"""
import calendar
import difflib
import json
import re
import time

BUNDLE_VERSION = "1"

contract = load_sibling("mozart_contract")  # noqa: F821 - injected by the loader
grant = contract.grant

_DISCOVERED = re.compile(r"([A-Za-z0-9][A-Za-z0-9_-]{0,62})\.([A-Za-z0-9][A-Za-z0-9_-]{0,62})\.json")
_NOW_SKEW_S = 300


def kinds(schema, kind):
    return {name for name, spec in schema["facts"].items() if spec["kind"] == kind}


def parse_time(stamp):
    """Epoch seconds for an RFC 3339 `...Z` stamp; ValueError for anything that is not a real moment."""
    return calendar.timegm(time.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ"))


def collisions(labels):
    """Labels that are different strings but the same name once case is folded (the same file on a
    case-insensitive disk)."""
    seen, clash = {}, set()
    for label in labels:
        key = label.casefold()
        if key in seen and seen[key] != label:
            clash |= {seen[key], label}
        seen.setdefault(key, label)
    return sorted(clash)


# --- the declared layer: registry.md ---------------------------------------------------------

def _declared(raw, schema, label):
    """Type the `labels:` pairs of one registry host; only static, scalar facts can be declared."""
    facts = {}
    for key, text in raw.items():
        spec = schema["facts"].get(key)
        if spec is None or spec["kind"] != "static" or spec["type"] in ("list", "map"):
            raise grant.GrantError(f"host {label}: {key!r} is not a fact that can be declared")
        if spec["type"] == "int":
            value = int(text) if re.fullmatch(schema["grammars"]["canonical_int"]["pattern"], text) else text
        elif spec["type"] == "number":
            value = float(text) if re.fullmatch(r"(0|[1-9][0-9]*)(\.[0-9]+)?", text) else text
        elif spec["type"] == "bool":
            value = {"true": True, "false": False}.get(text, text)
        else:
            value = text
        problems = contract.validate(value, dict(spec, nullable=False), schema, key)
        if problems:
            raise grant.GrantError(f"host {label}: {problems[0]}")
        facts[key] = value
    return facts


def read_registry(ctx, schema):
    """{label: {labels (typed), cost, owner, contact, taints, identity}}; {} when there is no registry.md."""
    data = contract.read_below(ctx, (), "registry.md")
    if data is None:
        return {}
    try:
        parsed = grant.parse(data, schema, sections={"host": schema["registry"]["host"]}, need=None)
        return {label: dict(h, labels=_declared(h["labels"], schema, label)) for label, h in parsed["hosts"].items()}
    except grant.GrantError as exc:
        raise contract.ContractError("registry-invalid", "registry.md is not valid", str(exc)) from None


# --- the discovered layer: discovered/<label>.<hook>.json -------------------------------------

def _record_spec(schema):
    host = schema["hook"]["discover"]["response"]["properties"]["hosts"]["items"]
    props = dict(host["properties"], hook={"type": "string", "grammar": "label"})
    facts = {k: v for k, v in props["facts"]["properties"].items() if k in kinds(schema, "static")}
    return dict(host, required=host["required"] + ["hook"], properties=dict(props, facts=dict(props["facts"], properties=facts)))


def declared_labels(ctx, schema, gstate):
    """Every host label the user wrote: the registry's and the grant's blocks."""
    return set(read_registry(ctx, schema)) | set(gstate["grant"]["hosts"] if gstate["grant"] else {})


def drop_colliding(declared, discovered):
    """(kept, problems): a discovered record whose label differs from a declared label, or from another
    discovered label, only in case is dropped and reported. The user's declared host stays."""
    folds = {}
    for label in discovered:
        folds.setdefault(label.casefold(), []).append(label)
    declared_folds = {d.casefold() for d in declared}
    kept, problems = {}, []
    for label, records in discovered.items():
        if (label.casefold() in declared_folds and label not in declared) or len(folds[label.casefold()]) > 1:
            problems.append(f"discovered records for {label!r} were dropped: the label collides with another label when case is folded")
        else:
            kept[label] = records
    return kept, problems


def persist_discovered(ctx, schema, hook, hosts, declared=()):
    """Write one file per host, static facts only. Labels were checked by the hook's response
    schema; a repeated label, or one that differs only in case from a declared host or from a host
    already discovered, is refused before anything is written."""
    labels = [h["label"] for h in hosts]
    if len(set(labels)) != len(labels) or collisions(labels):
        raise contract.ContractError("hook-output", "the hook reported a label twice, or two labels that differ only in case")
    known = set(declared) | {m.group(1) for m in map(_DISCOVERED.fullmatch, contract.list_below(ctx, ("discovered",))) if m}
    if any(new != old and new.casefold() == old.casefold() for new in labels for old in known):
        raise contract.ContractError("hook-output", "a reported label differs only in case from a host that is already known")
    static = kinds(schema, "static")
    records = []
    for h in hosts:
        try:
            parse_time(h["probed_at"])
        except ValueError:
            raise contract.ContractError("hook-output", "a probed_at is not a real moment") from None
        record = {"label": h["label"], "hook": hook, "probed_at": h["probed_at"],
                  "facts": {k: v for k, v in h["facts"].items() if k in static}}
        bad = contract.validate(record, _record_spec(schema), schema)
        if bad:
            raise contract.ContractError("hook-output", "a discovered record does not match its schema", bad[0])
        records.append(record)
    names = sorted(f"{r['label']}.{hook}.json" for r in records)
    for name in names:
        contract.check_destination(ctx, ("discovered",), name)
    for r in records:
        contract.write_atomic(ctx, ("discovered",), f"{r['label']}.{hook}.json", json.dumps(r, sort_keys=True).encode() + b"\n")
    return names


def read_discovered(ctx, schema):
    """({label: [record, ...]}, [problems]). A file that fails its schema or its name is reported, not used."""
    found, problems = {}, []
    for name in contract.list_below(ctx, ("discovered",)):
        m = _DISCOVERED.fullmatch(name)
        if not m:
            problems.append(f"discovered/{name}: not a <label>.<hook>.json name")
            continue
        try:
            record = contract.loads_strict(contract.read_below(ctx, ("discovered",), name, max_bytes=65536) or b"")
            bad = contract.validate(record, _record_spec(schema), schema)
            if not bad:
                parse_time(record["probed_at"])
        except contract.ContractError as exc:
            problems.append(f"discovered/{name}: {exc.code}: {exc.message}")
            continue
        except ValueError as exc:
            problems.append(f"discovered/{name}: {exc}")
            continue
        if bad or (record["label"], record["hook"]) != m.groups():
            problems.append(f"discovered/{name}: {bad[0] if bad else 'its label or hook differs from its file name'}")
            continue
        found.setdefault(record["label"], []).append(record)
    return found, problems


# --- merging the layers ------------------------------------------------------------------------

def merged_hosts(ctx, schema, gstate):
    """Every known host with its facts resolved. Declared beats discovered and the disagreement
    is reported; among discovered records the newest probe wins; a fact older than the grant's
    max_fact_age_hours is marked stale."""
    registry = read_registry(ctx, schema)
    discovered, problems = read_discovered(ctx, schema)
    blocks = gstate["grant"]["hosts"] if gstate["grant"] else {}
    max_age = (gstate["grant"]["remote_execution"]["max_fact_age_hours"] if gstate["grant"] else 168) * 3600
    now = ctx.clock()
    hosts = {}
    declared = set(registry) | set(blocks)
    if collisions(declared):  # the user's own files disagree with each other: that is theirs to fix
        raise contract.ContractError("registry-invalid", "host labels collide when case is folded", ", ".join(collisions(declared))[:300])
    discovered, clashes = drop_colliding(declared, discovered)  # a stale or hostile record is only a problem entry
    problems = problems + clashes
    for label in sorted(declared | set(discovered)):
        reg = registry.get(label, {})
        facts, conflicts = {}, []
        for rec in sorted(discovered.get(label, []), key=lambda r: (r["probed_at"], r["hook"])):
            age = now - parse_time(rec["probed_at"])
            for key, value in rec["facts"].items():
                facts[key] = {"value": value, "source": f"discovered:{rec['hook']}", "stale": age > max_age or age < -_NOW_SKEW_S}
        for key, value in reg.get("labels", {}).items():
            if key in facts and facts[key]["value"] != value:
                conflicts.append({"fact": key, "declared": value, "discovered": facts[key]["value"], "source": facts[key]["source"]})
            facts[key] = {"value": value, "source": "declared", "stale": False}
        hosts[label] = {"label": label, "owner": reg.get("owner"), "contact": reg.get("contact"), "cost": reg.get("cost"),
                        "taints": reg.get("taints", []), "identity": reg.get("identity"), "facts": facts, "conflicts": conflicts,
                        # a host the grant has no block for is treated as the least trusted kind, here and nowhere else
                        "trust": blocks.get(label, {}).get("trust", "shared"), "has_block": label in blocks,
                        "tolerates": blocks.get(label, {}).get("tolerates", [])}
        hosts[label]["dispatchable"], hosts[label]["why_not"] = dispatchable(hosts[label], gstate, blocks.get(label))
    return hosts, problems


def dispatchable(host, gstate, block, lease_ok=None):
    """(bool, reasons). Dispatchable means: the grant is enabled, it has a block for the host with a
    host_key, the registry gives the host an identity, and a leased host has a valid lease
    (the lease ledger arrives with the lease verbs; until then a leased host has none)."""
    why = []
    if not gstate["enabled"]:
        why.append("the grant is not enabled")
    if block is None:
        why.append("no host block in the grant")
    elif not block.get("host_key"):
        why.append("the grant block has no host_key")
    if not host["identity"]:
        why.append("the registry gives no identity")
    if block is not None and block["trust"] == "leased" and not (lease_ok and lease_ok(host["label"])):
        why.append("a leased host needs a valid lease")
    return not why, why


# --- grant snapshots ---------------------------------------------------------------------------

def snapshot_grant(ctx, raw):
    """Keep the exact grant text under grant-snapshots/<sha256>.md so a later change can be diffed."""
    digest = contract.sha256_hex(raw)
    if contract.read_below(ctx, ("grant-snapshots",), digest + ".md") is None:
        contract.write_atomic(ctx, ("grant-snapshots",), digest + ".md", raw)
    return digest


def read_snapshot(ctx, schema, sha):
    if not re.fullmatch(schema["grammars"]["sha256_filename"]["pattern"], sha):
        raise contract.ContractError("bad-request", "a snapshot is named by its full 64-hex sha256")
    data = contract.read_below(ctx, ("grant-snapshots",), sha + ".md")
    if data is None:
        raise contract.ContractError("refused", "no snapshot of that grant")
    if contract.sha256_hex(data) != sha:
        raise contract.ContractError("grant-hygiene", "the snapshot's content does not hash to its file name")
    return data


def diff_grant(old, new, old_label, new_label):
    return list(difflib.unified_diff(old.decode("utf-8", "replace").splitlines(), new.decode("utf-8", "replace").splitlines(),
                                     old_label, new_label, lineterm="", n=2))


# --- this machine's own facts -------------------------------------------------------------------

def probe_spec(schema):
    props = dict(schema["facts"], **schema["probe"]["extra_keys"])
    return {"type": "object", "required": list(props), "properties": props}


def check_probe_output(schema, rc, out, flag, requested):
    """The one gate for a probe's answer, whoever ran the probe (this machine now, a remote host
    over ssh later): it finished, exited 0, printed exactly one line, strict JSON, matching the probe
    schema, and its kube_contexts answers only the names that were asked (all of them if kubectl
    answered at all). The document is untrusted until this returns."""
    if flag or rc != 0:
        raise contract.ContractError("timeout" if flag == "timeout" else "hook-output", "the probe did not finish cleanly")
    if out.count(b"\n") != 1 or not out.endswith(b"\n"):
        raise contract.ContractError("hook-output", "the probe must print exactly one line")
    try:
        doc = contract.loads_strict(out)
    except ValueError as exc:
        raise contract.ContractError("hook-output", f"the probe's output is not strict JSON: {exc}") from None
    bad = contract.validate(doc, probe_spec(schema), schema)
    if bad:
        raise contract.ContractError("hook-output", "the probe's output does not match its schema", bad[0])
    answered = doc.get("kube_contexts")
    if answered is not None and set(answered) != set(requested):
        raise contract.ContractError("hook-output", "the probe's kube_contexts does not answer exactly the names that were requested")
    return doc


def local_facts(ctx, schema, kube_names=(), tool_path=()):
    """Run the probe on this machine and return its validated document. Names a requirement asks
    about are checked against the name grammar and the count cap before they reach an argument."""
    names = list(dict.fromkeys(kube_names))
    if len(names) > schema["probe"]["max_requested_names"]:
        raise contract.ContractError("bad-request", "too many context names requested")
    argv = ["/bin/sh", "-s", "--"]
    for name in names:
        if contract.validate(name, {"type": "string", "grammar": "kube_name"}, schema):
            raise contract.ContractError("bad-request", "a requested context name is not a valid name")
        argv += ["--kube-context", name]
    stream = contract.source("mozart-lib-host.sh") + contract.source("mozart-probe.sh")
    rc, out, _, flag = contract.run(ctx, argv, stdin=stream, timeout=60, cap=1 << 17, tool_path=tool_path)
    return check_probe_output(schema, rc, out, flag, names)
