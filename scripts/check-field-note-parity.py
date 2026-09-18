#!/usr/bin/env python3
"""V-FN1 / V-FN2 / behaviour — cross-port field-note, mechanism and script parity.

Pre-merge campaign tool, NOT a CI gate: no single port's CI can see the other
three checkouts, and `mozart-contract-gates.sh`'s report() has only PASS/FAIL
(no SKIP), so installing a cross-worktree check there would be permanently red
or vacuously green. Run it by hand across four worktrees before merge.

V-FN1  parity     — the field-note prose is identical across all four ports.
V-FN2  bullets    — each canonical mechanism bullet occurs exactly once per site.
V-FN3  behaviour  — each port's shipped lint/metrics scripts (or lack thereof,
                    for local) agree with the committed fixture corpus, per the
                    PD24 runner loop (2026-09-17-deliver-conductor-self-verification).

Vacuity controls, per the rule this tool exists to enforce:
  * population floor   — entry count >= floor
  * named member       — a specific entry must be present by name
  * distinct realpaths — N inputs must be N *different* files, >= 4 ports
  * digest vs the Phase-0 canonical file, never vs a constant pasted from a
    tree that no longer exists
  * placeholder parity — '*(no field notes yet)*' is present at 0 sites or all
    of them, never some (it is a factual claim that goes false on first entry)

For .toml inputs the *parsed* developer_instructions value is digested, not the
raw file bytes: the agent receives the parsed string, and in a TOML basic
multi-line string (triple-double-quote) a backslash escape is processed, so two
files can be byte-different but value-identical, and vice versa.
"""
import sys, os, re, hashlib, pathlib, argparse, subprocess

try:
    import tomllib
except ImportError:
    import tomli as tomllib

HEADING = "## Field notes (append-only)"
ENTRY_RE = re.compile(r"(?m)^### 20[0-9][0-9]-[0-9]{2}-[0-9]{2} ")
NEXT_SECTION_RE = re.compile(r"(?m)^## ")
PLACEHOLDER = "*(no field notes yet)*"

EXPECT = {
    "mozart":  (2, "Scope every empirical finding to platform, tool version, and date"),
    "jackson": (1, "Mutation testing finds MISSING tests"),
}


def persona_text(path: pathlib.Path) -> str:
    """The prose the agent actually receives."""
    if path.suffix == ".toml":
        return tomllib.loads(path.read_text())["developer_instructions"]
    return path.read_text()


def section(path: pathlib.Path):
    """(entries_text_or_None, entry_count, placeholder_present).

    Bounded (PD16): the section ends at the next top-level '## ' heading
    after the first entry, so a persona that puts another section (local's
    '## Model attestation') directly after its field notes does not have
    that trailing section swept into the digest.
    """
    t = persona_text(path)
    i = t.find(HEADING)
    if i < 0:
        return None, 0, False
    region = t[i:]
    m = ENTRY_RE.search(region)          # scoped: first entry AFTER the heading
    if not m:
        ph = PLACEHOLDER in region
        return None, 0, ph
    after_first_entry = region[m.end():]
    nxt = NEXT_SECTION_RE.search(after_first_entry)
    end = m.end() + (nxt.start() if nxt else len(after_first_entry))
    region = region[:end]
    ph = PLACEHOLDER in region
    body = region[m.start():].rstrip() + "\n"
    return body, len(ENTRY_RE.findall(body)), ph


REQUIRED_PORTS = ("orchestration", "codex", "copilot", "local")


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
    if sorted(counts.values()) != [1] * len(REQUIRED_PORTS):
        return None, (f"inputs per port {counts} — need exactly one file from each "
                      f"of the {len(REQUIRED_PORTS)} ports; distinctness alone is not provenance")
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


# --- V-FN3: behaviour (PD24 runner loop) ------------------------------------

CASES = ("lint", "metrics-placeholder", "metrics-conductor", "metrics-vacuity")
LINT_CATEGORIES = frozenset({
    "conductor-missing", "conductor-unlinked", "conductor-row",
    "conductor-reference", "decision-trigger", "mutation-manifest",
    "missing-2b",
})
OVERRIDE_DATE = "2099-06-01"
OVERRIDE_LINE_PREFIX = "conductor adoption date overridden:"
LINT_FIXTURE_FLOOR = 47
LINT_LINE_RE = re.compile(r"^LINT \[([^\]]+)\]\s+(\S+) — ([^:]*):")

# Named members (Fixture corpus, r5+) — asserted independently of aggregate
# set-equality, per M7: a check that counts or globs needs a member whose
# presence/absence it would actually reject if it flipped.
# Layout probes (F47). A total floor cannot tell "47 files, all in active/"
# from "47 files across six layouts", and six layouts is what K/L must reach.
LINT_LAYOUTS = (
    ("current/active", ".mozart/plans/active", "*.state.md"),
    ("current/finished", ".mozart/plans/finished", "*.state.md"),
    ("legacy active- prefix", ".mozart/plans", "active-*.state.md"),
    ("legacy finished- prefix", ".mozart/plans", "finished-*.state.md"),
    ("legacy flat prefixless", ".mozart/plans", "[0-9]*.state.md"),
    ("legacy root thoughts/shared", "thoughts/shared/plans", "[0-9]*.state.md"),
)

NAMED_PRESENT = (
    ("conductor-unlinked", "2099-07-02-deliver-k9", "9"),          # finished-dir scan
    ("conductor-unlinked", "2099-07-13-deliver-freeform", "10"),   # DELIVER-prefix match
    ("mutation-manifest", "2099-07-31-operate-ignore", "C4"),      # wildcard-index catch
    ("mutation-manifest", "2099-08-05-deliver-ledger-postadopt", "C1"),  # F39: no grandfathering once enforced
    ("missing-2b", "2099-08-06-deliver-combined", "-"),            # F40: combined-header Flow parsing
    ("conductor-unlinked", "2099-08-07-deliver-exempt-bypass", "5"),  # F42: exempt line is not sole content
    ("decision-trigger", "2099-08-10-deliver-revisit-placeholder", "D1"),  # F43: placeholder still fires
    ("conductor-missing", "2099-08-11-deliver-flat", "-"),         # F47: legacy flat prefixless glob
    ("conductor-missing", "active-2099-08-12-deliver-prefix", "-"),  # F47: date read through the active- prefix
    ("conductor-unlinked", "finished-2099-08-13-deliver-prefix", "5"),  # F47: finished- prefix layout
    ("conductor-unlinked", "2099-08-14-deliver-legacyroot", "9"),  # F47: legacy thoughts/shared root
    ("conductor-row", "2099-08-15-deliver-pipe-raw", "CR1"),       # F48: unescaped pipe rejected on width
    ("conductor-row", "2099-08-16-deliver-pipe-escaped", "CR1"),   # F48: escape honoured, empty control seen
    ("mutation-manifest", "2099-07-31-operate-ignore", "C7"),      # F48: change ledger width-guarded too
)
NAMED_ABSENT_TRIPLES = (
    ("mutation-manifest", "2099-07-31-operate-ignore", "C2"),      # all-literal ignore paths
    # F48 control: a correctly escaped row must stay silent, or the width rule
    # is just rejecting every row that mentions a pipe and CR1 proves nothing.
    ("conductor-row", "2099-08-16-deliver-pipe-escaped", "CR2"),
    ("mutation-manifest", "2099-07-31-operate-ignore", "C8"),      # the escaped change-ledger twin
)
# F48: the two pipe fixtures are the same shape modulo the escape, so a
# key-only assertion would pass if both produced the same finding. Name the
# distinct reasons.
NAMED_MESSAGES = (
    ("2099-08-15-deliver-pipe-raw", "CR1", "row has 8 cells, header has 7"),
    ("2099-08-16-deliver-pipe-escaped", "CR1", "empty or placeholder control"),
    ("2099-07-31-operate-ignore", "C7", "row has 8 cells, header has 7"),
)
NAMED_ABSENT_SLUGS = (
    "2000-01-01-deliver-legacy", "2099-05-31-deliver-prebound",
    "2000-01-03-deliver-legacy-ledger",                            # F39: pre-adoption, no grandfathering needed
    "2099-08-08-deliver-revisit-trigger", "2099-08-09-deliver-revisit-when",  # F43: both spellings accepted
)
OVERRIDE_CONTROL_TRIPLE = ("conductor-missing", "2099-05-31-deliver-prebound", "-")


def read_tsv(path):
    rows = []
    if not path.exists():
        return rows
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        rows.append(line.split("\t"))
    return rows


def run_script(script, root, env_overrides):
    env = dict(os.environ)
    env.pop("MOZART_LINT_CONDUCTOR_SINCE", None)
    env.update(env_overrides)
    if not script.exists():
        return None, f"script not found: {script}"
    proc = subprocess.run(["bash", str(script), str(root)],
                           capture_output=True, text=True, env=env)
    return proc, None


def parse_lint_output(output):
    """(triples, override_line_present) — triples filtered to LINT_CATEGORIES."""
    triples, override_present = set(), False
    for line in output.splitlines():
        if line.startswith(OVERRIDE_LINE_PREFIX):
            override_present = True
            continue
        m = LINT_LINE_RE.match(line)
        if not m:
            continue
        cat, path, key = m.group(1), m.group(2), m.group(3).strip()
        if cat not in LINT_CATEGORIES:
            continue
        slug = pathlib.Path(path).name
        if slug.endswith(".state.md"):
            slug = slug[: -len(".state.md")]
        triples.add((cat, slug, key))
    return triples, override_present


def cmd_behaviour(corpus, scripts_roots):
    if set(scripts_roots) != set(REQUIRED_PORTS):
        print(f"FAIL  behaviour: scripts-roots given {sorted(scripts_roots)}, need "
              f"exactly {sorted(REQUIRED_PORTS)}")
        return 1

    lint_root = corpus / "lint"
    expected_lint = {(r[1], r[2], r[3]) for r in read_tsv(lint_root / "expected.tsv")
                      if r[0] == "lint"}
    expected_rows = len([r for r in read_tsv(lint_root / "expected.tsv") if r[0] == "lint"])
    state_floor = len(list(lint_root.rglob("*.state.md")))
    if state_floor < LINT_FIXTURE_FLOOR:
        print(f"FAIL  behaviour: corpus has {state_floor} lint fixtures, below floor "
              f"{LINT_FIXTURE_FLOOR} — population would be vacuous")
        return 1
    unpopulated = [label for label, sub, pat in LINT_LAYOUTS
                   if not list((lint_root / sub).glob(pat))]
    if unpopulated:
        print(f"FAIL  behaviour: corpus layout(s) unpopulated: {unpopulated} — "
              f"K/L must reach all six and only a populated layout can show it")
        return 1

    overall_fail = 0
    for port in REQUIRED_PORTS:
        root = pathlib.Path(scripts_roots[port])
        if port == "local":
            print("local: N/A — ships no campaign scripts")
            continue

        port_fail = 0
        lint_script = root / "scripts" / "mozart-lint.sh"

        proc_ov, err = run_script(lint_script, lint_root, {"MOZART_LINT_CONDUCTOR_SINCE": OVERRIDE_DATE})
        if err:
            print(f"FAIL  {port}  lint: {err}")
            overall_fail = 1
            continue
        triples_ov, override_present = parse_lint_output(proc_ov.stdout)
        emitted = sum(1 for l in proc_ov.stdout.splitlines() if l.startswith("LINT ["))

        proc_no, err = run_script(lint_script, lint_root, {})
        if err:
            print(f"FAIL  {port}  lint (no override): {err}")
            overall_fail = 1
            continue
        triples_no, override_present_no = parse_lint_output(proc_no.stdout)

        if proc_ov.returncode != 1:
            print(f"FAIL  {port}  lint: exit={proc_ov.returncode}, want 1")
            port_fail = 1
        # F49: set-equality over a FILTERED category list cannot see a fixture
        # that ALSO fires an unfiltered category — 2099-07-29-noflow-j fired
        # missing-12b alongside its intended missing-2b, so it was not failing
        # only for its stated reason and nothing said so. Compare totals too.
        if emitted != expected_rows:
            print(f"FAIL  {port}  lint: corpus emitted {emitted} LINT line(s), expected.tsv "
                  f"records {expected_rows} — a fixture is firing a category nothing accounts for")
            port_fail = 1
        if len(triples_ov) != expected_rows:
            print(f"FAIL  {port}  lint: {len(triples_ov)} distinct triples vs {expected_rows} expected rows")
            port_fail = 1
        if triples_ov != expected_lint:
            missing = expected_lint - triples_ov
            extra = triples_ov - expected_lint
            print(f"FAIL  {port}  lint: triples mismatch — missing={sorted(missing)} extra={sorted(extra)}")
            port_fail = 1
        else:
            print(f"ok    {port}  lint: {len(triples_ov)}/{len(expected_lint)} triples set-equal")
        for member in NAMED_PRESENT:
            if member not in triples_ov:
                print(f"FAIL  {port}  lint: named member absent: {member}")
                port_fail = 1
        for member in NAMED_ABSENT_TRIPLES:
            if member in triples_ov:
                print(f"FAIL  {port}  lint: named-absent member present: {member}")
                port_fail = 1
        for slug in NAMED_ABSENT_SLUGS:
            if any(t[1] == slug for t in triples_ov):
                print(f"FAIL  {port}  lint: pre-adoption slug {slug} produced a triple")
                port_fail = 1
        for slug, key, want in NAMED_MESSAGES:
            hit = [l for l in proc_ov.stdout.splitlines()
                   if slug in l and f"— {key}:" in l and want in l]
            if not hit:
                print(f"FAIL  {port}  lint: message mismatch — {slug} {key} does not contain {want!r}")
                port_fail = 1
        if not override_present:
            print(f"FAIL  {port}  lint: override run missing '{OVERRIDE_LINE_PREFIX} {OVERRIDE_DATE}'")
            port_fail = 1
        if override_present_no:
            print(f"FAIL  {port}  lint: no-override run still printed an override line")
            port_fail = 1
        if OVERRIDE_CONTROL_TRIPLE not in triples_no:
            print(f"FAIL  {port}  lint: no-override control triple absent: {OVERRIDE_CONTROL_TRIPLE}")
            port_fail = 1

        metrics_script = root / "scripts" / "mozart-metrics.sh"
        for case in CASES[1:]:
            case_root = corpus / case
            expected_lines = [r[1] for r in read_tsv(case_root / "expected.tsv") if r[0] == "metrics"]
            proc, err = run_script(metrics_script, case_root, {})
            if err:
                print(f"FAIL  {port}  {case}: {err}")
                port_fail = 1
                continue
            if proc.returncode != 0:
                print(f"FAIL  {port}  {case}: exit={proc.returncode}, want 0")
                port_fail = 1
            outlines = set(proc.stdout.splitlines())
            for line in expected_lines:
                if line not in outlines:
                    print(f"FAIL  {port}  {case}: expected line absent: {line!r}")
                    port_fail = 1
            if case == "metrics-conductor":
                lens_line = next((l for l in proc.stdout.splitlines()
                                   if l.startswith("  rejected by lens:")), "")
                for tok in ("bob=1/1", "tessa=1/1", "ruby=1/1"):
                    if tok not in lens_line:
                        print(f"FAIL  {port}  {case}: '{tok}' absent from rejected-by-lens line")
                        port_fail = 1
                if "xander=" in lens_line:
                    print(f"FAIL  {port}  {case}: reversed lens xander= present in rejected-by-lens line")
                    port_fail = 1
            if not port_fail:
                print(f"ok    {port}  {case}: expected lines present")

        print(f"{'PASS' if not port_fail else 'FAIL'}  {port}: behaviour checks complete")
        if port_fail:
            overall_fail = 1

    return overall_fail


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

    pb = sub.add_parser("behaviour")
    pb.add_argument("--corpus", required=True, type=pathlib.Path)
    pb.add_argument("--scripts-root", dest="scripts_root", action="append",
                     required=True, type=kv, metavar="PORT=PATH",
                     help="repo root for each of: " + ", ".join(REQUIRED_PORTS))

    n = ap.parse_args()
    if n.cmd == "behaviour":
        return cmd_behaviour(n.corpus, dict(n.scripts_root))
    roots = dict(n.root)
    if n.cmd == "parity":
        return cmd_parity(n.persona, n.paths, n.canonical, roots)
    return cmd_bullets(n.bullet, n.paths, roots)


if __name__ == "__main__":
    sys.exit(main())
