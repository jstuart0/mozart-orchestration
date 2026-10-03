#!/usr/bin/env python3
"""Phase-6 gates for the carved manual bundle (2026-09-19-deliver-mozart-md-carve).

Seven checks that conservation cannot make, because conservation proves text still
EXISTS and is blind to whether the pointers into it still resolve:

  INDEX        agents/INDEX.md names every content destination, marks PIPELINE.md and
               LEARNINGS.md adjacent-not-members, and carries the EVAL disambiguation.
  ANCHORS      zero same-file `](#` and zero cross-file `.md#` across the PARTITION
               SET, plus a POSITIVE floor of pinned pointers. The two absence checks
               alone are satisfied by deleting every link; the floor is what stops it.
  POINTERS     Pattern 1, BOTH directions: every manual-set file is cited by >=1
               pointer, and every file a pointer names exists.
  REFS         D18's two-tier reference check (see the tier note below).
  FRONTMATTER  no carved file carries `name:` frontmatter, so none registers as an
               agent under Claude Code's discovery.
  ABSENCE      Pattern 2 - carve-map.tsv's absence table is populated and every row
               names an idiom and a disposition.
  ON_DEMAND    (V26) the template files that sit in agents/ beside the manual but are
               NOT manual members: present, cited by name by the file that uses them,
               never routed through a D2 pointer, never loaded as agents, listed in both
               required-file lists, and absent from the persona.

Read-only. Exit 0 iff every check passes.
"""
import pathlib, re, sys, subprocess

CONTENT = ["AUDIT","CONTEXT-BUDGET","COUNTERPOINT","DELIVER","DIAGNOSE","EVAL","FLOWS",
           "INCIDENT","INTAKE","OPERATE","STATE","TICKETS","WORKTREES"]
MANUAL   = CONTENT + ["INDEX"]                 # 14 - the files mozart is told to read
PARTITION = ["mozart"] + CONTENT               # 14 - the files holding PRE lines

# D18 WEAK TIER, and this is the judgment call, stated rather than buried.
#
# Population: `(see *Italic*` references only (18 today), NOT every `(see ...)` (37).
# The repo's convention for citing a section is italics. Of the 37 bare `(see ...)`
# forms, 25 are not section references at all - file names (`INTEGRATION.md`), stage
# references ("the table in stage 12"), relative words ("above"), and inline code
# spans. Taking the larger population would force a 25-entry exclusion list, and an
# exclusion list that large becomes the dumping ground the gate exists to prevent.
#
# Named exceptions: two references resolve to no heading anywhere in the bundle. Both
# were verified to resolve to nothing AT BASE TOO (`git show 8ec105c:agents/mozart.md`
# finds no such heading), so they are PRE-EXISTING dangling references that the carve
# neither created nor moved. They are named here rather than tolerated by a count, so
# a third one fails.
WEAK_KNOWN_DANGLING = {
    "The conductor record",
    "Project creation, fallback only",
}

# Files in agents/ that the manual's own text tells you to copy, not to read as
# procedure. A new CLASS, not manual members: MANUAL stays 14, so V20 (every member
# named by a D2 pointer) and V22 (exactly 14 tested) are untouched. Each maps to the
# one file that cites it by backticked name. Decision 3 of 2026-10-03-deliver-eval-
# efficiency-fixes: they are never named in the D2 pointer form, because V21 would then
# look for a heading inside a file that is not in its heading set, and never named in
# agents/mozart.md, because the persona must not carry a path to a file it does not read.
ON_DEMAND = {
    "TEMPLATE-STATE.md": "STATE.md",
    "TEMPLATE-LEDGER.md": "STATE.md",
    "TEMPLATE-CONDUCTOR.md": "STATE.md",
    "TEMPLATE-FLOW.md": "STATE.md",
    "TEMPLATE-REPORT.md": "DELIVER.md",
}
ON_DEMAND_FLOOR = 5
ON_DEMAND_NAMED = (("TEMPLATE-STATE.md", "STATE.md"), ("TEMPLATE-REPORT.md", "DELIVER.md"))

HEAD_RE = re.compile(r"^#{2,6} (.+)$")
PLEAD_RE = re.compile(r"\*\*[^*]+\*\* — read `[^`]+\.md`")
FILE_RE  = re.compile(r"`([A-Za-z][A-Za-z0-9/._-]*\.md)`")
CITE_RE  = re.compile(r"\(\*(.+?)\*\)")
WEAK_RE  = re.compile(r"\(see \*([^*]+)\*")


def load(root):
    out = {}
    for n in set(MANUAL + PARTITION):
        p = root / "agents" / f"{n}.md"
        out[f"{n}.md"] = p.read_text() if p.exists() else None
    return out


def headings(text):
    hs = set()
    for l in text.split("\n"):
        m = HEAD_RE.match(l)
        if m:
            h = m.group(1).strip()
            hs.add(h)
            hs.add(h.split(" (")[0].strip())      # heading minus a trailing paren
            hs.add(h.split(":")[0].strip())       # heading minus a trailing colon clause
    return hs


def ondemand_problems(texts, od, contrib, wf):
    """Everything wrong with the on-demand class, given file texts (name -> text).

    Pure over its arguments so the self-test below can run it on mutated copies.
    `texts` maps an agents/ file name to its text, and must hold every manual file,
    mozart.md, and each ON_DEMAND file (None when absent)."""
    bad = []
    if len(od) < ON_DEMAND_FLOOR:
        bad.append(f"ON_DEMAND has {len(od)} entr(ies), floor {ON_DEMAND_FLOOR}")
    for nm, nciter in ON_DEMAND_NAMED:
        if od.get(nm) != nciter:
            bad.append(f"named member absent: {nm} -> {nciter}")
    # List parsers carry a population floor: an empty parse of a required-file list
    # would make every membership test below pass for the wrong reason.
    tok = re.compile(r"agents/[A-Za-z][A-Za-z0-9-]*\.md")
    for label, text in (("CONTRIBUTING.md", contrib), ("validate-plugin.yml", wf)):
        if len(set(tok.findall(text))) < len(MANUAL):
            bad.append(f"{label}: parsed {len(set(tok.findall(text)))} agents/*.md name(s), floor {len(MANUAL)}")
    for name, citer in sorted(od.items()):
        t = texts.get(name)
        if t is None:
            bad.append(f"{name} is missing")
            continue
        if re.search(r"^name:", t, re.M):
            bad.append(f"{name} carries `name:` frontmatter (it would register as an agent)")
        c = texts.get(citer)
        if c is None or f"`{name}`" not in c:
            bad.append(f"{name} is not cited by backticked name in {citer}")
        else:
            named_on = sum(1 for l in c.split("\n") if name in l)
            if named_on != 1:
                bad.append(f"{citer} names {name} on {named_on} lines, want exactly 1")
        for label, text in (("CONTRIBUTING.md", contrib), ("validate-plugin.yml", wf)):
            if f"agents/{name}" not in text:
                bad.append(f"{label} does not list agents/{name}")
    persona = texts.get("mozart.md") or ""
    if "TEMPLATE-" in persona:
        bad.append("agents/mozart.md names a TEMPLATE- file (the persona must not)")
    for fname, t in sorted(texts.items()):
        if not t or fname in od:
            continue
        for i, l in enumerate(t.split("\n"), 1):
            if PLEAD_RE.search(l) and any(n in l for n in od):
                bad.append(f"{fname}:{i} names an ON_DEMAND file in the D2 pointer form")
    return bad


def first_line_problems(agents_texts, od):
    """A template's first line is its identity: it must occur as a whole line in
    exactly one agents/*.md file (the template), so the skeleton cannot also live
    on as text in a manual file. agents_texts maps every agents/*.md name to its text."""
    bad = []
    for name in sorted(od):
        t = agents_texts.get(name)
        if not t:
            continue                      # absence is reported by ondemand_problems
        first = t.split("\n", 1)[0]
        n = sum(1 for body in agents_texts.values() if body
                for l in body.split("\n") if l == first)
        if n != 1:
            bad.append(f"the first line of {name} ({first!r}) occurs {n} times across agents/*.md, want 1")
    return bad


def ondemand_selftest(texts, od, contrib, wf):
    """Each mutation must make ondemand_problems report something. Returns the list
    of mutations that were NOT caught, and the number tried."""
    def mutate(fn):
        t = dict(texts)
        fn(t)
        return t
    first = sorted(od)[0]
    cases = {
        "persona gains a TEMPLATE- name": lambda t: t.__setitem__("mozart.md", (t["mozart.md"] or "") + " TEMPLATE-STATE.md"),
        "a template gains name: frontmatter": lambda t: t.__setitem__(first, "name: x\n" + (t[first] or "")),
        "a manual line uses the D2 pointer form": lambda t: t.__setitem__(
            "STATE.md", (t["STATE.md"] or "") + f"\n**Foo** \u2014 read `{first}` (*Bar*)\n"),
        "the citing file stops naming a template": lambda t: t.__setitem__(
            od[first], (t[od[first]] or "").replace(f"`{first}`", "")),
    }
    missed = [n for n, fn in cases.items() if not ondemand_problems(mutate(fn), od, contrib, wf)]
    # And the lists: a required-file list without a template must be reported.
    if not ondemand_problems(texts, od, contrib.replace(f"agents/{first}", ""), wf):
        missed.append("CONTRIBUTING.md stops listing a template")
    if not ondemand_problems(texts, od, contrib, wf.replace(f"agents/{first}", "")):
        missed.append("validate-plugin.yml stops listing a template")
    # And the first-line rule: a manual file that carries a template's first line again.
    dup = {k: v for k, v in texts.items() if v}
    dup["STATE.md"] = dup["STATE.md"] + "\n" + (texts[first] or "").split("\n", 1)[0] + "\n"
    if not first_line_problems(dup, od):
        missed.append("a manual file repeats a template's first line")
    # And the exactly-one-line rule: the citing file names a template on a second line.
    two = dict(texts)
    two[od[first]] = (texts[od[first]] or "") + f"\nsee also {first}\n"
    if not ondemand_problems(two, od, contrib, wf):
        missed.append("the citing file names a template on a second line")
    return missed, len(cases) + 4


def main():
    root = pathlib.Path(subprocess.run(["git","rev-parse","--show-toplevel"],
                        capture_output=True, text=True, check=True).stdout.strip())
    f = load(root)
    missing = [n for n in set(MANUAL + PARTITION) if f.get(f"{n}.md") is None]
    results = []

    def rep(name, ok, detail):
        results.append((name, ok, detail))

    if missing:
        rep("V18_index", False, f"missing bundle files: {sorted(set(missing))}")
        for n in ("V19_anchors","V20_pointers","V21_refs","V22_frontmatter","V23_absence","V24_docs","V26_ondemand"):
            rep(n, False, "bundle incomplete")
        return emit(results)

    heads = {n: headings(t) for n, t in f.items()}

    # --- INDEX -------------------------------------------------------------
    idx = f["INDEX.md"]
    named = [n for n in CONTENT if f"`{n}.md`" in idx]
    bad = []
    if len(named) != len(CONTENT):
        bad.append(f"names {len(named)} of {len(CONTENT)} content destinations "
                   f"(missing {sorted(set(CONTENT)-set(named))})")
    for adj in ("PIPELINE.md","LEARNINGS.md"):
        if adj not in idx: bad.append(f"does not mention {adj} as adjacent-not-member")
    if "agents/EVAL.md" not in idx or "docs/EVAL.md" not in idx:
        bad.append("missing the agents/EVAL.md vs docs/EVAL.md disambiguation")
    if "`DELIVER.md`" not in idx: bad.append("named member DELIVER.md absent")
    rep("V18_index", not bad,
        "; ".join(bad) or f"INDEX.md names all {len(CONTENT)} content destinations, "
        f"marks PIPELINE.md/LEARNINGS.md adjacent-not-members, carries the EVAL "
        f"disambiguation, named member DELIVER.md present")

    # --- ANCHORS -----------------------------------------------------------
    same = {n: f[n].count("](#") for n in [x+".md" for x in PARTITION]}
    cross = {n: len(re.findall(r"\.md#", f[n])) for n in [x+".md" for x in PARTITION]}
    pinned = sum(1 for n in [x+".md" for x in PARTITION]
                 for l in f[n].split("\n") if PLEAD_RE.search(l) and CITE_RE.search(l))
    bad = []
    if sum(same.values()):  bad.append(f"same-file `](#` present: "
                                       f"{ {k:v for k,v in same.items() if v} }")
    if sum(cross.values()): bad.append(f"cross-file `.md#` present: "
                                       f"{ {k:v for k,v in cross.items() if v} }")
    if pinned < 9: bad.append(f"pinned pointers={pinned}, floor 9 (3 from 1a + 6 from 1c)")
    rep("V19_anchors", not bad,
        "; ".join(bad) or f"across {len(PARTITION)} partition-set file(s): same-file "
        f"`](#`=0, cross-file `.md#`=0, and {pinned} D2 pointers (floor 9) - the "
        f"positive floor is what stops the two absences being satisfied by deletion")

    # --- POINTERS (Pattern 1, both directions) ------------------------------
    # A BACKTICKED FILENAME IS NOT A POINTER. The first version of this gate asked
    # only whether `<FILE>.md` appeared anywhere in the persona, while pointer-form
    # validation lived in V21 - so deleting a file's activation trigger and leaving an
    # inert prose mention behind kept this gate green while the persona had lost the
    # thing that sends mozart to read it. D2's whole point is that "see X" is not
    # enough. The naming line must now SATISFY THE D2 POINTER FORM (either shape,
    # routed included) and name the file among its backticked *.md files - the same
    # routed-aware resolution V21's strict tier uses, not a second implementation.
    persona = f["mozart.md"]
    persona_pointer_lines = [l for l in persona.split("\n")
                             if PLEAD_RE.search(l) and CITE_RE.search(l)]
    def named_by_pointer(n):
        want = f"{n}.md"
        return any(want in [x.split("/")[-1] for x in FILE_RE.findall(l)]
                   for l in persona_pointer_lines)
    uncited = [n for n in MANUAL if not named_by_pointer(n)]
    inert = [n for n in MANUAL if not named_by_pointer(n) and f"`{n}.md`" in persona]
    dangling = []
    for n in [x+".md" for x in PARTITION]:
        for i, l in enumerate(f[n].split("\n"), 1):
            if not PLEAD_RE.search(l): continue
            for fn in FILE_RE.findall(l):
                base = fn.split("/")[-1]
                if base not in f and not (root / fn).exists() and not (root/"agents"/base).exists():
                    dangling.append(f"{n}:{i} -> {fn}")
    bad = []
    if uncited:
        bad.append(f"manual-set file(s) named by no D2-POINTER-FORM line: {uncited}")
    if inert:
        bad.append(f"...and {inert} appear only as INERT PROSE MENTIONS - a backticked "
                   f"filename with no trigger is exactly what D2 forbids")
    if dangling: bad.append(f"pointer(s) naming a non-existent file: {dangling[:5]}")
    if len(persona_pointer_lines) < 14:
        bad.append(f"persona carries {len(persona_pointer_lines)} pointer-form line(s), floor 14")
    if not named_by_pointer("INTAKE"):
        bad.append("named member absent: INTAKE.md must be named by the unconditional "
                   "stage-1 boot read, which is Pattern 1's named member (D-F/F13)")
    rep("V20_pointers", not bad,
        "; ".join(bad) or f"all {len(MANUAL)} manual-set files are named by a line that "
        f"SATISFIES the D2 pointer form ({len(persona_pointer_lines)} such lines, floor 14; "
        f"routed shape included), every file a pointer names exists (both directions), "
        f"named member INTAKE.md present via the stage-1 boot read")

    # --- REFS (D18 two tiers) ----------------------------------------------
    strict_n = strict_bad = 0
    sbad = []
    for n in [x+".md" for x in PARTITION] + ["INDEX.md"]:
        for i, l in enumerate(f[n].split("\n"), 1):
            if not PLEAD_RE.search(l): continue
            named_files = [x.split("/")[-1] for x in FILE_RE.findall(l)]
            for c in CITE_RE.finditer(l):
                strict_n += 1
                if not any(c.group(1) in heads.get(nf, set()) for nf in named_files):
                    strict_bad += 1
                    sbad.append(f"{n}:{i} names {named_files} but no such heading: *{c.group(1)}*")
    # The weak tier's resolution universe is ALL of agents/*.md, not just the
    # bundle: mozart legitimately cites a persona's section (PRE 77's
    # `(see *Consult requested* handling, stage 3)` resolves to agents/harry.md:249,
    # and did so at base too). Scoping the universe to the bundle alone would report
    # a legitimate cross-persona reference as dangling - the population error this
    # campaign keeps finding, pointed the other way.
    every = set().union(*heads.values())
    for extra in sorted((root / "agents").glob("*.md")):
        every |= headings(extra.read_text())
    weak_n = 0; wbad = []
    for n in [x+".md" for x in PARTITION] + ["INDEX.md"]:
        for i, l in enumerate(f[n].split("\n"), 1):
            for m in WEAK_RE.finditer(l):
                weak_n += 1
                c = m.group(1).strip()
                if c not in every and c not in WEAK_KNOWN_DANGLING:
                    wbad.append(f"{n}:{i} (see *{c}*)")
    bad = []
    if strict_bad: bad.append(f"STRICT: {strict_bad} pointer(s) cite a heading absent "
                              f"from every file they name: {sbad[:4]}")
    if strict_n < 20: bad.append(f"STRICT population {strict_n} < floor 20")
    if wbad: bad.append(f"WEAK: {len(wbad)} prose reference(s) name no heading in the "
                        f"bundle and are not known-dangling: {wbad[:4]}")
    if weak_n < 12: bad.append(f"WEAK population {weak_n} < floor 12")
    rep("V21_refs", not bad,
        "; ".join(bad) or f"STRICT {strict_n} pointer citations (floor 20), 0 naming a "
        f"heading their file lacks, named member *Worktree isolation (default for "
        f"code-changing campaigns)*; WEAK {weak_n} prose refs (floor 12), 0 unresolved "
        f"beyond {len(WEAK_KNOWN_DANGLING)} pre-existing dangling refs named in the script")

    # --- FRONTMATTER --------------------------------------------------------
    reg = [n for n in MANUAL if re.search(r"^name:", f[f"{n}.md"], re.M)]
    rep("V22_frontmatter", not reg and len(MANUAL) == 14,
        f"{len(reg)} of {len(MANUAL)} manual-set file(s) carry `name:` frontmatter "
        f"(want 0 over exactly 14 tested)" + (f" - {reg}" if reg else ""))

    # --- DOCS RIPPLE --------------------------------------------------------
    # The one part of the carve with no mechanical check, which is why two ripple
    # sites named twice in the plan still went unlanded (F75, F76): the phase was
    # green because nothing gated CONTRIBUTING.md or the workflow's REQUIRED list.
    # A prose ripple nobody can fail is a ripple that gets eyeballed, and an eye
    # enumerating six sites landed three.
    #
    # This asserts only the MECHANICAL half - that both required-file lists name
    # every manual-set file. Whether the prose around them is correct is still
    # judgment, but "the list forgot a file" is now a failure rather than a reading.
    #
    # The independence is real because the comparison is against MANUAL - a constant
    # in this file - and never against `ls agents/*.md`. That is the control doing the
    # work, not V16's 18-row floor or V20's 14-file floor: a hypothetical 15th manual
    # file would CLEAR both of those floors while never reaching either required-file
    # list. MANUAL is what makes a deletion detectable, which is the single thing a
    # required-files check exists for and the thing a tree-derived list can never do.
    dbad = []
    try:
        contrib = (root / "CONTRIBUTING.md").read_text()
        wf = (root / ".github/workflows/validate-plugin.yml").read_text()
    except FileNotFoundError as e:
        contrib = wf = ""
        dbad.append(f"missing doc: {e.filename}")
    miss_c = [n for n in MANUAL if f"agents/{n}.md" not in contrib]
    miss_w = [n for n in MANUAL if f"agents/{n}.md" not in wf]
    if miss_c: dbad.append(f"CONTRIBUTING.md's pre-push sweep omits {miss_c}")
    if miss_w: dbad.append(f".github/workflows/validate-plugin.yml REQUIRED omits {miss_w}")
    if "agents/DELIVER.md" not in contrib or "agents/DELIVER.md" not in wf:
        dbad.append("named member agents/DELIVER.md absent from one of the two lists")
    rep("V24_docs", not dbad,
        "; ".join(dbad) or f"both required-file lists (CONTRIBUTING.md pre-push sweep and "
        f"validate-plugin.yml REQUIRED) name all {len(MANUAL)} manual-set files; named "
        f"member agents/DELIVER.md present in both")

    # --- ABSENCE (Pattern 2) ------------------------------------------------
    cm = (root / "tests/carve/carve-map.tsv").read_text()
    rows = [l for l in cm.split("\n") if l.startswith("# absence\t")]
    bad = []
    if len(rows) < 3: bad.append(f"absence table has {len(rows)} row(s), floor 3")
    DISPOSITIONS = ("RE-SCOPE", "RECORD REASON", "NO ACTION")
    for r in rows:
        parts = r.split("\t")
        if len(parts) < 6:
            bad.append(f"malformed absence row ({len(parts)} cells, want 6): {r[:60]}")
            continue
        if parts[3] not in ("path-literal","glob","roster-derived"):
            bad.append(f"row {parts[1]} names no known idiom: {parts[3]!r}")
        # The disposition cell is the one a reader acts on, so it is validated rather
        # than merely counted: a blank or garbled cell used to pass while the gate's
        # own PASS text claimed every row named a disposition.
        disp = parts[4].strip()
        if not disp:
            bad.append(f"row {parts[1]} has an EMPTY disposition cell")
        elif not any(disp.upper().startswith(d) for d in DISPOSITIONS):
            bad.append(f"row {parts[1]} disposition {disp[:40]!r} is none of {DISPOSITIONS}")
        if not parts[5].strip():
            bad.append(f"row {parts[1]} has an empty rationale cell")
    rep("V23_absence", not bad,
        "; ".join(bad) or f"{len(rows)} Pattern-2 absence site(s) (floor 3), each naming a "
        f"known idiom, a non-empty disposition from {DISPOSITIONS}, and a rationale")

    # --- ON_DEMAND (V26) ----------------------------------------------------
    texts = dict(f)
    for n in ON_DEMAND:
        p = root / "agents" / n
        texts[n] = p.read_text() if p.exists() else None
    problems = ondemand_problems(texts, ON_DEMAND, contrib, wf)
    problems += first_line_problems(
        {q.name: q.read_text() for q in (root / "agents").glob("*.md")}, ON_DEMAND)
    missed, tried = ondemand_selftest(texts, ON_DEMAND, contrib, wf) if not problems else ([], 0)
    if missed:
        problems.append(f"self-test: mutation(s) not detected: {missed}")
    rep("V26_ondemand", not problems,
        "; ".join(problems) or f"{len(ON_DEMAND)} on-demand file(s) (floor {ON_DEMAND_FLOOR}), named member "
        f"{' and '.join(a + ' -> ' + b for a, b in ON_DEMAND_NAMED)}: each exists, has no `name:` frontmatter, is cited by "
        f"name on exactly one line of its citing file, has a first line found nowhere else in agents/*.md, and is listed in CONTRIBUTING.md and validate-plugin.yml; the persona names none "
        f"and no D2 pointer line names one; {tried} self-test mutations each detected")

    return emit(results)


def emit(results):
    for n, ok, d in results:
        print(f"{'PASS' if ok else 'FAIL'}  {n:<22} {d}")
    return 0 if all(ok for _, ok, _ in results) else 1


if __name__ == "__main__":
    sys.exit(main())
