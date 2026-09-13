#!/usr/bin/env python3
"""V-FN1 / V-FN2 — cross-port field-note and mechanism parity.

Pre-merge campaign tool, NOT a CI gate: no single port's CI can see the other
two checkouts, and `mozart-contract-gates.sh`'s report() has only PASS/FAIL
(no SKIP), so installing a cross-worktree check there would be permanently red
or vacuously green. Run it by hand across three worktrees before merge.

V-FN1  parity   — the field-note prose is identical across all three ports.
V-FN2  bullets  — each canonical mechanism bullet occurs exactly once per site.

Vacuity controls, per the rule this tool exists to enforce:
  * population floor   — entry count >= floor
  * named member       — a specific entry must be present by name
  * distinct realpaths — N inputs must be N *different* files, >= 3 ports
  * digest vs the Phase-0 canonical file, never vs a constant pasted from a
    tree that no longer exists
  * placeholder parity — '*(no field notes yet)*' is present at 0 sites or all
    of them, never some (it is a factual claim that goes false on first entry)

For .toml inputs the *parsed* developer_instructions value is digested, not the
raw file bytes: the agent receives the parsed string, and in a TOML basic
multi-line string (triple-double-quote) a backslash escape is processed, so two
files can be byte-different but value-identical, and vice versa.
"""
import sys, re, hashlib, pathlib, argparse

try:
    import tomllib
except ImportError:
    import tomli as tomllib

HEADING = "## Field notes (append-only)"
ENTRY_RE = re.compile(r"(?m)^### 20[0-9][0-9]-[0-9]{2}-[0-9]{2} ")
PLACEHOLDER = "*(no field notes yet)*"

EXPECT = {
    "mozart":  (3, "An unattended run needs a decision log"),
    "jackson": (1, "Mutation testing finds MISSING tests"),
}


def persona_text(path: pathlib.Path) -> str:
    """The prose the agent actually receives."""
    if path.suffix == ".toml":
        return tomllib.loads(path.read_text())["developer_instructions"]
    return path.read_text()


def section(path: pathlib.Path):
    """(entries_text_or_None, entry_count, placeholder_present)."""
    t = persona_text(path)
    i = t.find(HEADING)
    if i < 0:
        return None, 0, False
    region = t[i:]
    ph = PLACEHOLDER in region
    m = ENTRY_RE.search(region)          # scoped: first entry AFTER the heading
    if not m:
        return None, 0, ph
    body = region[m.start():].rstrip() + "\n"
    return body, len(ENTRY_RE.findall(body)), ph


REQUIRED_PORTS = ("orchestration", "codex", "copilot")


def bind_ports(paths, roots):
    """Map each input to the port root that contains it.

    Distinctness and count are NOT provenance: three files copied from one
    source into one directory satisfy 'len(set)==len(paths)>=3'. That is the
    aggregate trap one level up — it guards how many inputs there are, not
    what they are. Require exactly one input under each named port root.
    Returns (label_by_path, error_or_None).
    """
    if set(roots) != set(REQUIRED_PORTS):
        return None, (f"port roots given {sorted(roots)}, need exactly "
                      f"{sorted(REQUIRED_PORTS)}")
    resolved = {k: pathlib.Path(v).resolve() for k, v in roots.items()}
    label = {}
    for p in paths:
        rp = p.resolve()
        hits = [k for k, r in resolved.items() if r in rp.parents]
        if len(hits) != 1:
            return None, (f"{p} lies under {len(hits)} of the three port roots "
                          f"(need exactly 1): {hits or 'none'}")
        label[rp] = hits[0]
    counts = {k: sum(1 for v in label.values() if v == k) for k in REQUIRED_PORTS}
    if sorted(counts.values()) != [1, 1, 1]:
        return None, (f"inputs per port {counts} — need exactly one file from each "
                      f"of the three ports; distinctness alone is not provenance")
    return label, None


def cmd_parity(persona, paths, canonical, roots):
    floor, member = EXPECT[persona]
    fail, digests, phs = 0, [], []
    label, err = bind_ports(paths, roots)
    if err:
        print(f"FAIL  {persona}: {err} — compare would be vacuous")
        return 1
    for p in paths:
        body, n, ph = section(p)
        phs.append(ph)
        if body is None:
            print(f"FAIL  {persona}  {p}: no field-note entry beneath the heading")
            fail = 1
            continue
        if n < floor:
            print(f"FAIL  {persona}  {p}: entries={n} below floor {floor}")
            fail = 1
        if member not in body:
            print(f"FAIL  {persona}  {p}: named member absent: {member!r}")
            fail = 1
        if ph:
            # H-B: parity alone permits the state the plan forbids. The
            # placeholder is a factual claim ("no field notes yet") that is
            # FALSE the instant an entry exists. All-three-keep-it is not an
            # acceptable parity outcome; it is three self-contradicting files.
            print(f"FAIL  {persona}  {p}: has {n} entr{'y' if n == 1 else 'ies'} AND still "
                  f"carries {PLACEHOLDER!r} — the placeholder is false once an entry lands")
            fail = 1
        d = hashlib.sha256(body.encode()).hexdigest()
        digests.append(d)
        print(f"      {label[p.resolve()]:13s} {p.name:26s} entries={n} "
              f"placeholder={'Y' if ph else 'N'} sha={d[:12]}")
    if len(digests) != len(paths):
        print(f"FAIL  {persona}: digest population {len(digests)} != inputs {len(paths)}"
              f" — compare would be vacuous")
        return 1
    if len(set(digests)) != 1:
        print(f"FAIL  {persona}: ports disagree ({len(set(digests))} distinct digests)")
        fail = 1
    if len(set(phs)) != 1:
        # Secondary control. 'all or none' is still required, but N/N is now
        # reserved for the UNREPAIRED base only -- once entries exist, the
        # per-site rule above rejects the placeholder outright.
        print(f"FAIL  {persona}: placeholder present at {sum(phs)}/{len(phs)} sites "
              f"— must be all (unrepaired base) or none (repaired)")
        fail = 1
    can = hashlib.sha256((canonical.read_text().rstrip() + "\n").encode()).hexdigest()
    if digests and digests[0] != can:
        print(f"FAIL  {persona}: ports agree with each other but NOT with the canonical "
              f"file {canonical.name} (canonical sha={can[:12]})")
        fail = 1
    if not fail:
        print(f"PASS  {persona}: {len(paths)} ports identical, == canonical {can[:12]}, "
              f"entries>={floor}, member present, placeholder {sum(phs)}/{len(phs)}")
    return fail


def cmd_bullets(bullet_files, paths, roots):
    """V-FN2 — per-member, not aggregate: each bullet exactly once at each site."""
    fail = 0
    label, err = bind_ports(paths, roots)
    if err:
        print(f"FAIL  bullets: {err} — compare would be vacuous")
        return 1
    for bf in bullet_files:
        want = bf.read_text().strip()
        for p in paths:
            n = persona_text(p).count(want)
            status = "ok" if n == 1 else "FAIL"
            if n != 1:
                fail = 1
            print(f"{status:5s} {bf.name:20s} @ {label[p.resolve()]:13s} {p.name:24s} "
                  f"occurrences={n} (want exactly 1)")
    if not fail:
        print(f"PASS  bullets: {len(bullet_files)} bullets × {len(paths)} sites, each exactly once")
    return fail


def kv(s):
    if "=" not in s:
        raise argparse.ArgumentTypeError("--root takes <port>=<path>")
    k, v = s.split("=", 1)
    return k, v


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("parity", "bullets"):
        p = sub.add_parser(name)
        p.add_argument("--root", action="append", required=True, type=kv,
                       metavar="PORT=PATH",
                       help="repo root for each of: " + ", ".join(REQUIRED_PORTS))
        if name == "parity":
            p.add_argument("persona", choices=sorted(EXPECT))
            p.add_argument("--canonical", required=True, type=pathlib.Path)
        else:
            p.add_argument("--bullet", action="append", required=True,
                           type=pathlib.Path)
        p.add_argument("paths", nargs="+", type=pathlib.Path)
    n = ap.parse_args()
    roots = dict(n.root)
    if n.cmd == "parity":
        return cmd_parity(n.persona, n.paths, n.canonical, roots)
    return cmd_bullets(n.bullet, n.paths, roots)


if __name__ == "__main__":
    sys.exit(main())
