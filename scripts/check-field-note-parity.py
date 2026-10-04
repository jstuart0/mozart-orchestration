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
import sys, os, re, hashlib, pathlib, argparse, subprocess, shutil, tempfile

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

CASES = ("lint", "metrics-placeholder", "metrics-conductor", "metrics-vacuity", "metrics-split")
# The six K/L names, missing-2b, split-layout (Check M), and the two older
# categories the split fixtures exercise: stranded-artifacts (Check H, a ledger
# left behind in active/) and stale-paths (Check G), and escape-unrecorded (Check N).
LINT_CATEGORIES = frozenset({
    "conductor-missing", "conductor-unlinked", "conductor-row",
    "conductor-reference", "decision-trigger", "mutation-manifest",
    "missing-2b", "split-layout", "stranded-artifacts", "stale-paths",
    "escape-unrecorded",
})
OVERRIDE_DATE = "2099-06-01"
# D12: the corpus predates the lens-record date; the 2099-12 fixtures exercise the rule.
LENS_OVERRIDE = "2099-12-01"
OVERRIDE_LINE_PREFIX = "conductor adoption date overridden:"
LINT_FIXTURE_FLOOR = 171
# Sibling files get their own floors: a state-file floor cannot notice a split
# fixture losing its ledger or conductor half.
LINT_LEDGER_FLOOR = 16
LINT_CONDUCTOR_FLOOR = 25
# F59: the path was parsed as \S+, so a corpus under a path containing a space
# parsed ZERO triples while the linter it was checking emitted all of them
# correctly — the harness carried the very defect F50 fixed in the shell
# scripts. The linter's own format is `<path> — <key>: <msg>`, so take the path
# non-greedily up to the FIRST " — ", which is how the bash-side extractor in
# mozart-contract-gates.sh has always split it. The key runs to the first colon
# or, for a message that has none (stale-paths), to the end of the line, as the
# bash side's split on ": " does.
LINT_LINE_RE = re.compile(r"^LINT \[([^\]]+)\]\s+(.+?) — ([^:]*)(?::|$)")

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
    # the split pair (state + ledger + conductor) in each layout it can sit in
    ("split pair current/active (ledger)", ".mozart/plans/active", "*.ledger.md"),
    ("split pair current/active (conductor)", ".mozart/plans/active", "*.conductor.md"),
    ("split pair current/finished (ledger)", ".mozart/plans/finished", "*.ledger.md"),
    ("split pair current/finished (conductor)", ".mozart/plans/finished", "*.conductor.md"),
    ("split pair legacy active- prefix", ".mozart/plans", "active-*.conductor.md"),
    ("split pair legacy finished- prefix", ".mozart/plans", "finished-*.conductor.md"),
    ("split pair legacy flat prefixless", ".mozart/plans", "[0-9]*.conductor.md"),
    ("split pair legacy root thoughts/shared", "thoughts/shared/plans", "[0-9]*.ledger.md"),
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
    # F52: PD1's adoption gate is header-present OR date-on-or-after. This
    # slug is BEFORE the override cutoff and carries a conductor record, so
    # only the union reaches its decisions log.
    ("decision-trigger", "2099-05-30-deliver-precutoff-header", "D1"),
    # Check M, one fixture per key
    ("split-layout", "2099-09-05-deliver-split-dupledger", "findings-ledger-duplicate"),
    ("split-layout", "2099-09-04-deliver-split-dupconductor", "conductor-record-duplicate"),
    ("split-layout", "2099-09-06-deliver-split-ledgermissing", "findings-ledger-missing"),
    ("split-layout", "2099-05-21-deliver-split-conductormissing", "conductor-record-missing"),
    ("split-layout", "2099-09-07-deliver-split-ledgernohead", "findings-ledger-noheading"),
    ("split-layout", "2099-09-08-deliver-split-conductornohead", "conductor-record-noheading"),
    # the sibling is read, in each place it can be
    ("conductor-unlinked", "2099-09-04-deliver-split-dupconductor", "9"),
    ("conductor-unlinked", "2099-09-02-deliver-split-unlinked", "9"),
    ("conductor-unlinked", "2099-09-03-deliver-split-rejected", "F2"),
    ("conductor-missing", "2099-09-10-deliver-split-emptyconductor", "-"),
    ("conductor-unlinked", "2099-09-12-deliver-mixed-conductor", "F3"),
    ("stranded-artifacts", "2099-09-13-deliver-split-halfmoved",
     "state is in finished/ but sibling artifact(s) remain in active/"),
    ("split-layout", "2099-09-13-deliver-split-halfmoved", "findings-ledger-missing"),
    ("conductor-unlinked", "finished-2099-09-21-deliver-split-fprefix", "5"),
    ("conductor-unlinked", "2099-09-23-deliver-split-legacyroot", "F2"),
    ("conductor-row", "2099-09-18-deliver-split-crlf", "CR2"),
    ("conductor-row", "2099-09-18-deliver-split-crlf", "CR3"),
    ("conductor-unlinked", "2099-09-18-deliver-split-crlf", "F2"),
    ("conductor-unlinked", "2099-09-19-deliver-split-quoted", "5"),
    ("conductor-unlinked", "2099-05-25-deliver-split-preadopted", "9"),
    ("conductor-unlinked", "2099-09-20-deliver-zerostate", "F2"),
    # a headingless sibling is not usable: the in-file section is still read
    ("split-layout", "2099-09-25-deliver-split-noheadinfile", "findings-ledger-noheading"),
    ("conductor-unlinked", "2099-09-25-deliver-split-noheadinfile", "F2"),
    # a sibling with its heading AND text ahead of it is still reported
    ("split-layout", "2099-09-26-deliver-split-conductorstray", "conductor-record-noheading"),
    # Phase rows are required on HEAVY and on a tier that is absent, a
    # placeholder or unparseable; the lens record only where (surface: is written
    ("conductor-unlinked", "2099-07-16-deliver-kP", "P2"),
    ("conductor-unlinked", "2099-10-05-phase-notier", "P2"),
    ("conductor-unlinked", "2099-10-06-phase-placeholder", "P2"),
    ("conductor-unlinked", "2099-10-07-phase-unfilled", "P2"),
    ("conductor-unlinked", "2099-10-08-phase-combinedheavy", "P2"),
    ("conductor-unlinked", "2099-10-10-phase-heavyfmt", "P2"),
    ("conductor-unlinked", "2099-10-12-phase-lower", "P2"),
    ("conductor-unlinked", "2099-10-13-phase-title", "P2"),
    ("conductor-unlinked", "2099-10-14-phase-heavyfirst", "P2"),
    ("conductor-unlinked", "2099-10-27-phase-quoted", "P2"),
    # a bold Tier value is a value: HEAVY, so the Phase line is required
    ("conductor-unlinked", "2099-10-29-phase-boldheavy", "P2"),
    # escalation text, lists, suffixes, italic and backticked values are no value
    ("conductor-unlinked", "2099-10-11-phase-stdfmt", "P2"),
    ("conductor-unlinked", "2099-10-31-phase-italicstd", "P2"),
    ("conductor-unlinked", "2099-11-01-phase-underlight", "P2"),
    ("conductor-unlinked", "2099-11-02-phase-stdarrow", "P2"),
    ("conductor-unlinked", "2099-11-03-phase-stdnow", "P2"),
    ("conductor-unlinked", "2099-11-04-phase-commaplaceholder", "P2"),
    ("conductor-unlinked", "2099-11-05-phase-suffixed", "P2"),
    ("conductor-unlinked", "2099-11-07-phase-boldstdesc", "P2"),
    ("conductor-unlinked", "2099-11-09-phase-ticked", "P2"),
    ("conductor-unlinked", "2099-11-14-phase-boldlist", "P2"),
    ("conductor-row", "2099-10-16-phase-stdmalformed", "CR1"),
    ("conductor-row", "2099-10-19-phase-lensbad", "CR2"),
    ("conductor-row", "2099-10-21-phase-lensian", "CR1"),
    ("conductor-row", "2099-10-22-phase-lensreason", "CR1"),
    ("conductor-row", "2099-10-23-phase-lenstoken", "CR1"),
    ("conductor-row", "2099-10-26-phase-widgets", "CR1"),
    ("conductor-row", "2099-10-26-phase-widgets", "CR2"),
    ("conductor-row", "2099-11-10-phase-lenshyphen", "CR1"),
    ("conductor-row", "2099-11-11-phase-lensrunning", "CR1"),
    ("conductor-row", "2099-11-12-phase-lenswsreason", "CR1"),
    ("conductor-row", "2099-11-15-phase-lenscell", "CR1"),
    ("conductor-row", "2099-11-17-phase-heavyrepeat", "CR1"),
    ("conductor-row", "2099-11-18-phase-xanderskip", "CR2"),
    ("conductor-row", "2099-11-19-phase-prebare", "CR1"),
    ("conductor-row", "2099-11-20-phase-escnorow", "CR1"),
    ("conductor-row", "2099-11-21-phase-rownoesc", "CR1"),
    ("conductor-row", "2099-11-22-phase-passlinkwrong", "CR1"),
    ("conductor-row", "2099-12-10-phase-escnoclaim", "CR1"),
    ("conductor-row", "2099-12-11-phase-escdocsreason", "CR1"),
    ("conductor-row", "2099-12-12-phase-escseereason", "CR1"),
    ("conductor-row", "2099-12-13-phase-escprefixlink", "CR1"),
    ("conductor-row", "2099-12-14-phase-escplaceholder", "CR1"),
    ("conductor-row", "2099-12-15-phase-escnotrun", "CR1"),
    ("conductor-row", "2099-12-17-phase-escoldform", "CR1"),
    ("conductor-row", "2099-12-16-phase-escafterk", "CR3"),
    ("conductor-row", "2099-12-18-phase-escorder", "CR4"),
    ("conductor-row", "2099-12-01-phase-bareheavy", "tier"),
    ("conductor-row", "2099-12-02-phase-emptysurface", "tier"),
    ("conductor-row", "2099-12-03-phase-unlistedonly", "tier"),
    ("conductor-row", "2099-12-04-phase-baredated", "tier"),
    ("conductor-row", "2099-12-04-phase-baredated", "CR1"),
    ("conductor-row", "2099-12-07-phase-authcase", "CR1"),
    ("conductor-row", "2099-12-08-phase-semisecrets", "CR1"),
    # Check N: one member per rule, so an expected.tsv edited in step cannot hide one
    ("escape-unrecorded", "2099-05-02-deliver-esc-noneyet", "2099-09-02-diagnose-noneyet"),
    ("escape-unrecorded", "2099-05-03-deliver-esc-noheading", "2099-09-03-diagnose-noheading"),
    ("escape-unrecorded", "2099-05-05-deliver-esc-forms", "2099-09-05-diagnose-form-partial"),
    ("escape-unrecorded", "2099-05-07-deliver-esc-pm", "2099-09-07-incident-pm"),
    ("escape-unrecorded", "2099-09-08-diagnose-nostate", "2099-09-08-diagnose-nostate"),
    ("escape-unrecorded", "2099-08-30-diagnose-nostate", "2099-08-30-diagnose-nostate"),
    ("escape-unrecorded", "2099-05-09-deliver-esc-prefix", "2099-09-09-diagnose-a"),
    ("escape-unrecorded", "2099-05-10-deliver-esc-section", "2099-09-10-diagnose-section"),
    ("escape-unrecorded", "2099-05-11-deliver-esc-lk-abo", "2099-09-11-diagnose-lk-abo-no"),
    ("escape-unrecorded", "2099-05-11-deliver-esc-lk-rev", "2099-09-11-diagnose-lk-rev-no"),
    ("escape-unrecorded", "2099-05-13-deliver-esc-dup", "2099-09-13-diagnose-dup2"),
    ("escape-unrecorded", "2099-05-16-deliver-esc-fence", "2099-09-16-diagnose-fence-after"),
    ("escape-unrecorded", "2099-09-18-diagnose-dotted", "2099-09-18-diagnose-dotted"),
    ("escape-unrecorded", "2099-05-23-deliver-esc-ext", "2099-09-23-diagnose-extslug"),
    ("escape-unrecorded", "2099-05-27-deliver-esc-wrap", "2099-09-27-diagnose-wrap2"),
    ("escape-unrecorded", "2099-05-28-deliver-esc-mb", "2099-09-28-diagnose-mbunrec"),
)
NAMED_ABSENT_TRIPLES = (
    ("mutation-manifest", "2099-07-31-operate-ignore", "C2"),      # all-literal ignore paths
    # F48 control: a correctly escaped row must stay silent, or the width rule
    # is just rejecting every row that mentions a pipe and CR1 proves nothing.
    ("conductor-row", "2099-08-16-deliver-pipe-escaped", "CR2"),
    ("mutation-manifest", "2099-07-31-operate-ignore", "C8"),      # the escaped change-ledger twin
    ("split-layout", "2099-09-14-deliver-split-pathsstale", "findings-ledger-missing"),  # derived sibling exists
    ("conductor-unlinked", "2099-09-05-deliver-split-dupledger", "F2"),  # the in-file row is ignored, the sibling wins
    ("conductor-missing", "2099-09-08-deliver-split-conductornohead", "-"),  # one cause, one line
    ("conductor-row", "2099-09-18-deliver-split-crlf", "CR1"),
    ("conductor-unlinked", "2099-09-18-deliver-split-crlf", "9"),  # the CRLF sibling's CR1 was read
    ("split-layout", "2099-09-25-deliver-split-noheadinfile", "findings-ledger-duplicate"),  # headingless: not usable, not a duplicate
    # Check N silent twins: recorded, prefix-collision twin, fenced, external, ticket id, self reference
    ("escape-unrecorded", "2099-05-01-deliver-esc-recorded", "2099-09-01-diagnose-recorded"),
    ("escape-unrecorded", "2099-05-02-deliver-esc-trailing", "2099-09-02-diagnose-trailing"),
    ("escape-unrecorded", "2099-05-04-deliver-esc-real", "2099-09-04-diagnose-not-applicable"),
    ("escape-unrecorded", "2099-05-04-deliver-esc-real", "2099-09-04-diagnose-silent-forms"),
    ("escape-unrecorded", "2099-09-06-diagnose-self", "2099-09-06-diagnose-self"),
    ("escape-unrecorded", "2099-05-09-deliver-esc-prefix", "2099-09-09-diagnose-ab"),
    ("escape-unrecorded", "2099-05-11-deliver-esc-lk-act", "2099-09-11-diagnose-lk-act-ok"),
    ("escape-unrecorded", "2099-05-11-deliver-esc-lk-fin", "2099-09-11-diagnose-lk-fin-ok"),
    ("escape-unrecorded", "2099-05-11-deliver-esc-lk-abo", "2099-09-11-diagnose-lk-abo-ok"),
    ("escape-unrecorded", "active-2099-05-11-deliver-esc-lk-apre", "2099-09-11-diagnose-lk-apre-ok"),
    ("escape-unrecorded", "finished-2099-05-11-deliver-esc-lk-fpre", "2099-09-11-diagnose-lk-fpre-ok"),
    ("escape-unrecorded", "2099-05-11-deliver-esc-lk-flat", "2099-09-11-diagnose-lk-flat-ok"),
    ("escape-unrecorded", "2099-05-11-deliver-esc-lk-leg", "2099-09-11-diagnose-lk-leg-ok"),
    ("escape-unrecorded", "2099-05-11-deliver-esc-lk-rev", "2099-09-11-diagnose-lk-rev-ok"),
    ("escape-unrecorded", "2099-09-12-diagnose-ticket", "2099-09-12-diagnose-ticket"),
    ("escape-unrecorded", "2099-05-16-deliver-esc-fence", "2099-09-16-diagnose-fence-backtick"),
    ("escape-unrecorded", "2099-05-16-deliver-esc-fence", "2099-09-16-diagnose-fence-tilde"),
    ("escape-unrecorded", "2099-05-16-deliver-esc-fence", "2099-09-16-diagnose-fence-open"),
    ("escape-unrecorded", "2099-05-23-deliver-esc-ext", "2099-09-23-diagnose-external"),
    ("escape-unrecorded", "2099-05-27-deliver-esc-wrap", "2099-09-27-diagnose-wrapcarry"),
    # a multibyte character beside the slug is not a slug character: still recorded
    ("escape-unrecorded", "2099-05-28-deliver-esc-mb", "2099-09-28-diagnose-mbquote"),
    ("escape-unrecorded", "2099-05-28-deliver-esc-mb", "2099-09-28-diagnose-mbdash"),
    ("escape-unrecorded", "2099-05-28-deliver-esc-mb", "2099-09-28-diagnose-mbpre"),
)
# F48: the two pipe fixtures are the same shape modulo the escape, so a
# key-only assertion would pass if both produced the same finding. Name the
# distinct reasons.
NAMED_MESSAGES = (
    ("2099-08-15-deliver-pipe-raw", "CR1", "row has 8 cells, header has 7"),
    ("2099-08-16-deliver-pipe-escaped", "CR1", "empty or placeholder control"),
    ("2099-07-31-operate-ignore", "C7", "row has 8 cells, header has 7"),
    # Check M: six keys, six reasons
    ("2099-09-05-deliver-split-dupledger", "findings-ledger-duplicate",
     "## Findings ledger is in the state file and in the sibling ledger file"),
    ("2099-09-04-deliver-split-dupconductor", "conductor-record-duplicate",
     "## Conductor record is in the state file and in the sibling conductor file"),
    ("2099-09-06-deliver-split-ledgermissing", "findings-ledger-missing",
     "declares a findings ledger but the sibling ledger file"),
    ("2099-05-21-deliver-split-conductormissing", "conductor-record-missing",
     "declares a conductor record but the sibling conductor file"),
    ("2099-09-07-deliver-split-ledgernohead", "findings-ledger-noheading",
     "sibling ledger file has content outside a ## Findings ledger section"),
    ("2099-09-08-deliver-split-conductornohead", "conductor-record-noheading",
     "sibling conductor file has content outside a ## Conductor record section"),
    ("2099-09-18-deliver-split-crlf", "CR2", "row has 8 cells, header has 7"),
    ("2099-09-18-deliver-split-crlf", "CR3", "empty or placeholder control"),
    ("2099-09-26-deliver-split-conductorstray", "conductor-record-noheading",
     "sibling conductor file has content outside a ## Conductor record section"),
    ("2099-07-16-deliver-kP", "P2", "ticked Phase line has no linked conductor row"),
    ("2099-10-19-phase-lensbad", "CR2", "HEAVY phase row does not record ian and xander"),
    ("2099-10-21-phase-lensian", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-10-22-phase-lensreason", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-10-23-phase-lenstoken", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-10-26-phase-widgets", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-10-26-phase-widgets", "CR2", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),  # an unlisted word fails safe: xander every phase
    ("2099-11-10-phase-lenshyphen", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-11-11-phase-lensrunning", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-11-12-phase-lenswsreason", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-11-15-phase-lenscell", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-11-17-phase-heavyrepeat", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-11-18-phase-xanderskip", "CR2", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-11-19-phase-prebare", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-11-20-phase-escnorow", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-11-21-phase-rownoesc", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-11-22-phase-passlinkwrong", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-10-phase-escnoclaim", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-11-phase-escdocsreason", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-12-phase-escseereason", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-13-phase-escprefixlink", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-14-phase-escplaceholder", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-15-phase-escnotrun", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-17-phase-escoldform", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-16-phase-escafterk", "CR3", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-18-phase-escorder", "CR4", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-01-phase-bareheavy", "tier", "HEAVY tier line has no usable surface record"),
    ("2099-12-02-phase-emptysurface", "tier", "HEAVY tier line has no usable surface record"),
    ("2099-12-03-phase-unlistedonly", "tier", "HEAVY tier line has no usable surface record"),
    ("2099-12-04-phase-baredated", "tier", "HEAVY tier line has no usable surface record"),
    ("2099-12-04-phase-baredated", "CR1", "HEAVY phase row does not record ian and xander"),
    ("2099-12-07-phase-authcase", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
    ("2099-12-08-phase-semisecrets", "CR1", "HEAVY phase row with surface auth, secrets or security does not record xander as run"),
)
NAMED_ABSENT_SLUGS = (
    "2000-01-01-deliver-legacy", "2099-05-31-deliver-prebound",
    "2000-01-03-deliver-legacy-ledger",                            # F39: pre-adoption, no grandfathering needed
    "2099-08-08-deliver-revisit-trigger", "2099-08-09-deliver-revisit-when",  # F43: both spellings accepted
    # clean or exempt split pairs and silent mixes: nothing may fire on them
    "2099-09-01-deliver-split-clean", "2099-05-23-deliver-split-exempt",
    "2099-05-24-deliver-split-preledger", "2099-09-11-deliver-mixed-ledger",
    "2099-09-15-deliver-split-placeholders", "active-2099-09-17-deliver-split-aprefix",
    "2099-09-22-deliver-split-flat", "2099-09-24-deliver-split-finishedclean",
    "2099-09-09-deliver-split-emptyledger", "2099-05-22-deliver-split-emptypre",
    # STANDARD, LIGHT, TINY and the lens-exempt shapes: nothing may fire
    "2099-10-02-phase-standard", "2099-10-03-phase-light", "2099-10-04-phase-tiny",
    "2099-10-09-phase-combinedstd", "2099-10-15-phase-stdfirst",
    "2099-10-18-phase-lensok", "2099-10-20-phase-lenspre", "2099-10-24-phase-stdsurface",
    "2099-10-25-phase-escalated", "2099-10-28-phase-lowersurface",
    # a balanced ** wrapper is not part of the value; a free-text STANDARD is still STANDARD
    "2099-10-30-phase-boldstd", "2099-11-06-phase-stdfree", "2099-11-08-phase-boldcombined",
    # an em dash before the lens name is not a letter: both lenses recorded
    "2099-11-16-phase-lensemdash",
    # dated lens rule and escalation evidence: a usable surface, a mixed or skipped-but-unneeded lens, the full escalation record
    "2099-12-05-phase-datedok",
    "2099-12-06-phase-mixedsurface",
    "2099-12-09-phase-escok",
    "2099-12-19-phase-escorderok",
)
OVERRIDE_CONTROL_TRIPLE = ("conductor-missing", "2099-05-31-deliver-prebound", "-")
# F59: the spaced-path arm gets its own named member rather than borrowing
# NAMED_PRESENT[0], so deleting this line is a visible edit rather than a
# silently weaker assertion.
SPACED_NAMED_MEMBER = ("conductor-row", "2099-08-15-deliver-pipe-raw", "CR1")
# metrics-split: one lens per layout and campaign kind. The catches-by-lens line
# is unordered, so each token is checked on its own (mirror of V10b).
SPLIT_LENSES_PRESENT = ("bob", "ruby", "tessa", "percy", "xander", "ian", "dexter",
                        "hank", "nina", "jackson", "scott", "sarah", "infile")
SPLIT_LENSES_ABSENT = ("shadow", "orphan", "zerostate", "nohead", "otto")


def read_tsv(path):
    rows = []
    if not path.exists():
        return rows
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        rows.append(line.split("\t"))
    return rows


def utf8_locale():
    """A UTF-8 locale this machine has, or exit. Lint's awk dies on a lone byte
    of a multibyte character only in such a locale, so a harness that runs under
    whatever the caller exported can pass without ever meeting the failure."""
    names = subprocess.run(["locale", "-a"], capture_output=True, text=True).stdout.split()
    found = [n for n in names if re.search(r"\.utf-?8$", n, re.I)]
    if not found:
        print("FAIL  behaviour: no UTF-8 locale in `locale -a`; the multibyte lint "
              "fixtures cannot be exercised")
        sys.exit(1)
    return "en_US.UTF-8" if "en_US.UTF-8" in found else found[0]


def run_script(script, root, env_overrides):
    env = dict(os.environ)
    env.pop("MOZART_LINT_CONDUCTOR_SINCE", None)
    env["MOZART_LINT_LENS_SINCE"] = LENS_OVERRIDE
    env.update(env_overrides)
    env["LC_ALL"] = utf8_locale()
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
        # The slug is the file name up to the FIRST dot: a state file has none, and a
        # post-mortem (<slug>.postmortem.md) or an investigation reported against its
        # own path is cut to the slug it was written under.
        slug = pathlib.Path(path).name.split(".")[0]
        triples.add((cat, slug, key))
    return triples, override_present


def cmd_behaviour(corpus, scripts_roots, only=None):
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
    ledger_floor = len(list(lint_root.rglob("*.ledger.md")))
    conductor_floor = len(list(lint_root.rglob("*.conductor.md")))
    if ledger_floor < LINT_LEDGER_FLOOR or conductor_floor < LINT_CONDUCTOR_FLOOR:
        print(f"FAIL  behaviour: corpus has {ledger_floor} ledger and {conductor_floor} conductor "
              f"siblings, below floors {LINT_LEDGER_FLOOR} and {LINT_CONDUCTOR_FLOOR} — the split "
              f"fixtures lost a half")
        return 1
    unpopulated = [label for label, sub, pat in LINT_LAYOUTS
                   if not list((lint_root / sub).glob(pat))]
    if unpopulated:
        print(f"FAIL  behaviour: corpus layout(s) unpopulated: {unpopulated} — "
              f"K/L must reach all six and only a populated layout can show it")
        return 1

    # F59 coverage: a copy of the lint corpus under a path containing a space,
    # so the END-TO-END proof (script + this harness's parse) covers the case
    # V14 proves for the shell scripts alone. Built here rather than committed:
    # the point is the path, and a committed spaced directory would have to be
    # mirrored byte-for-byte into copilot's fixture tree for no added signal.
    # Both lint runs read a copy stamped "now": lint's stale-active check goes by
    # file mtime, so a corpus older than its threshold would emit extra lines
    # that expected.tsv rightly does not record.
    fresh_tmp = tempfile.mkdtemp()
    fresh_lint = pathlib.Path(fresh_tmp) / "lint"
    shutil.copytree(lint_root, fresh_lint)
    for entry in [fresh_lint, *fresh_lint.rglob("*")]:
        os.utime(entry)
    source_files = sum(1 for p in lint_root.rglob("*") if p.is_file())
    fresh_files = sum(1 for p in fresh_lint.rglob("*") if p.is_file())
    if source_files != fresh_files:
        print(f"FAIL  behaviour: fresh copy holds {fresh_files} file(s), corpus holds {source_files}")
        shutil.rmtree(fresh_tmp, ignore_errors=True)
        return 1

    spaced_tmp = tempfile.mkdtemp()
    spaced_root = pathlib.Path(spaced_tmp) / "dir with a space"
    shutil.copytree(fresh_lint, spaced_root / "lint")
    spaced_lint = spaced_root / "lint"

    overall_fail = 0
    for port in REQUIRED_PORTS:
        if only is not None and port not in only:
            continue
        root = pathlib.Path(scripts_roots[port])
        if port == "local":
            print("local: N/A — ships no campaign scripts")
            continue

        port_fail = 0
        lint_script = root / "scripts" / "mozart-lint.sh"

        proc_ov, err = run_script(lint_script, fresh_lint, {"MOZART_LINT_CONDUCTOR_SINCE": OVERRIDE_DATE})
        if err:
            print(f"FAIL  {port}  lint: {err}")
            overall_fail = 1
            continue
        triples_ov, override_present = parse_lint_output(proc_ov.stdout)
        emitted = sum(1 for l in proc_ov.stdout.splitlines() if l.startswith("LINT ["))

        proc_no, err = run_script(lint_script, fresh_lint, {})
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
        # Findings are always reported against the state file, never a sibling.
        sibling_paths = [l for l in proc_ov.stdout.splitlines()
                         if re.match(r"^LINT .*\.(ledger|conductor)\.md — ", l)]
        if sibling_paths:
            print(f"FAIL  {port}  lint: {len(sibling_paths)} LINT line(s) name a sibling file as "
                  f"their path, e.g. {sibling_paths[0]!r}")
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

        # --- F59: same corpus, spaced path, same expected triples -----------
        proc_sp, err = run_script(lint_script, spaced_lint, {"MOZART_LINT_CONDUCTOR_SINCE": OVERRIDE_DATE})
        if err:
            print(f"FAIL  {port}  lint (spaced path): {err}")
            port_fail = 1
        else:
            # Control: without this the arm could be running against a path with
            # no space in it and prove nothing about the parse.
            if "dir with a space" not in proc_sp.stdout:
                print(f"FAIL  {port}  lint (spaced path): no output line names the spaced path — "
                      f"the arm is not exercising what it claims to")
                port_fail = 1
            triples_sp, _ = parse_lint_output(proc_sp.stdout)
            if triples_sp != expected_lint:
                missing = expected_lint - triples_sp
                extra = triples_sp - expected_lint
                print(f"FAIL  {port}  lint (spaced path): triples mismatch — "
                      f"missing={sorted(missing)} extra={sorted(extra)}")
                port_fail = 1
            elif SPACED_NAMED_MEMBER not in triples_sp:
                print(f"FAIL  {port}  lint (spaced path): named member absent: {SPACED_NAMED_MEMBER}")
                port_fail = 1
            else:
                print(f"ok    {port}  lint (spaced path): {len(triples_sp)}/{len(expected_lint)} "
                      f"triples set-equal under a path containing a space")

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
            if case == "metrics-split":
                by_lens = next((l for l in proc.stdout.splitlines()
                                 if l.startswith("  by lens:")), "")
                tokens = by_lens.split()
                for lens in SPLIT_LENSES_PRESENT:
                    if f"{lens}=1" not in tokens:
                        print(f"FAIL  {port}  {case}: '{lens}=1' absent from the catches-by-lens line")
                        port_fail = 1
                for lens in SPLIT_LENSES_ABSENT:
                    if any(t.startswith(f"{lens}=") for t in tokens):
                        print(f"FAIL  {port}  {case}: '{lens}=' present in the catches-by-lens line (must not be read)")
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

    shutil.rmtree(spaced_tmp, ignore_errors=True)
    shutil.rmtree(fresh_tmp, ignore_errors=True)
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
    pb.add_argument("--only", help="comma-separated ports to run (default: all). The four "
                    "--scripts-root values are still required; a port left out is not read.")

    n = ap.parse_args()
    if n.cmd == "behaviour":
        only = None
        if n.only is not None:
            only = [x for x in n.only.split(",") if x]
            unknown = [x for x in only if x not in REQUIRED_PORTS]
            if unknown or not only:
                ap.error(f"--only takes ports from {', '.join(REQUIRED_PORTS)}, got {n.only!r}")
        return cmd_behaviour(n.corpus, dict(n.scripts_root), only)
    roots = dict(n.root)
    if n.cmd == "parity":
        return cmd_parity(n.persona, n.paths, n.canonical, roots)
    return cmd_bullets(n.bullet, n.paths, roots)


if __name__ == "__main__":
    sys.exit(main())
