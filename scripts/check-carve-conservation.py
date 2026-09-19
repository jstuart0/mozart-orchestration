#!/usr/bin/env python3
"""Conservation gate for the agents/mozart.md carve.

The whole gate is one derived property:

    POST is exactly PRE, re-partitioned across the partition set, plus declared changes.

Negate each clause independently and the complete failure-mode set appears. Eight
modes; nothing else can go wrong without violating one of them:

  1 a PRE line is absent from POST .................. C1
  2 a PRE line occurs more often in POST ............ C2
  3 a POST line has no PRE origin and no declaration  C5
  4 a carved range sits in the wrong destination .... C3 forward
  5 an inline range left agents/mozart.md ........... C3 inverse
  6 content present, correctly assigned, MIS-ORDERED  C3c (within-range + between-range)
  7 a PRE line is assigned to no range, or to two ... C3 partition
  8 a range moves in the wrong phase ................ C3b

C4 is the vacuity control: population floors, the exact realpath set, and
post != baseline. It is not a failure mode of the property - it is what stops
the other seven from being satisfied by an empty population, which is the
defect this campaign exists to remove.

The unit of conservation is the NON-BLANK LINE, rstrip()-ed. Lines are
line-oriented like the source, byte-exact, and need no transform to argue about.

BASELINE: `git show <BASE_SHA>:agents/mozart.md`. The commit SHA proves WHICH
object was asked for; the pinned SHA-256 proves WHAT came back. Only the pair
survives a history rewrite or a corrupted object. Either failing is a hard FAIL,
never a skip. BASE_SHA is a commit on the campaign branch, so this campaign MUST
merge --no-ff (D8) - a squash would orphan the baseline and break the gate
retroactively.

The 11-mutation self-test runs on a synthetic mktemp fixture and never reads the
repo tree, which is what makes it valid from Phase 1 onward, before any
destination file exists. It runs on EVERY invocation: a discriminator observed
failing once and then never again is an assertion about the past.
"""

import argparse
import collections
import hashlib
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

# --- pins (D-D, F10, D5's per-campaign re-pin) ------------------------------
BASE_SHA = "fdfad2884c9adf61bb015977fe21d4ddd0e0c494"
BASE_BLOB_SHA256 = "3314c73c8544662ce4540a81e490c2f60353229121b27ac8dd6c7106be88e127"
BASE_PATH = "agents/mozart.md"

PERSONA = "agents/mozart.md"
MAP_FILE = "tests/carve/carve-map.tsv"
ROSTER_FILE = "tests/carve/phases.expected"
ADDITIONS_FILE = "tests/carve/additions.allow"

PRE_NONBLANK_FLOOR = 1800          # base: 1827
RANGE_COUNT_PIN = 43               # exact, pinned in Phase 0 from the authored map (D9 re-pin)
RANGE_COUNT_FLOOR = 43             # the plan's model minimum
CONTENT_DESTINATIONS = 13          # partition set = PERSONA + 13
EXCLUDED_FROM_PARTITION = "agents/INDEX.md"   # 100% new text, gated separately (F7/F33)

POINTER_RE = None  # compiled below


def _compile():
    global POINTER_RE
    import re
    # **<Trigger>** — read `<FILE>.md` (*<Original section heading>*) ...
    POINTER_RE = re.compile(r"\*\*[^*]+\*\* — read `[^`]+\.md` \(\*.+?\*\)")


_compile()


# ---------------------------------------------------------------------------
# data
# ---------------------------------------------------------------------------

Row = collections.namedtuple("Row", "pre_start pre_end destination order phase heading lineno")


class Additions:
    def __init__(self):
        self.typed = []        # (type, payload)
        self.changed = []      # (minus, plus)
        self.errors = []       # malformed / unpaired

    @property
    def plus_lines(self):
        out = [p for t, p in self.typed]
        out += [p for _, p in self.changed]
        return out

    @property
    def minus_lines(self):
        return [m for m, _ in self.changed]


class World:
    """Everything the controls read. Built from the repo, or synthesised by the self-test."""

    def __init__(self, pre_lines, rows, roster, files, additions, label, persona=PERSONA):
        self.pre_lines = pre_lines            # list[str], index 0 == PRE line 1
        self.rows = rows
        self.roster = roster                  # {ordinal: set(destination)}
        self.files = files                    # {destination: list[str]} for files that EXIST
        self.additions = additions
        self.label = label
        # The persona is a property of the WORLD, not a module constant. A control
        # that hard-codes it silently mis-classifies every row in any world whose
        # persona is named differently - which is how the self-test fixture caught
        # this: its persona rows fell into the phase roster as ordinal 0.
        self.persona = persona
        self.persona_baseline = list(pre_lines)


def split_lines(text):
    """Text -> its LINES.

    A file ending in a newline splits into a trailing empty element that is not a
    line: `wc -l` on agents/mozart.md says 2507, but "...\n".split("\n") yields
    2508 elements. Counting that artifact as a PRE line puts a permanent one-line
    GAP in the partition that no carve can ever close. Dropped here, once, for
    every text the gate reads - baseline and destinations alike.
    """
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def norm(line):
    return line.rstrip()


def nonblank(lines):
    return [norm(l) for l in lines if norm(l)]


# ---------------------------------------------------------------------------
# parsing
# ---------------------------------------------------------------------------

def parse_map(text, path_label):
    rows, errs, seen_header = [], [], False
    for i, raw in enumerate(text.split("\n"), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if parts[0] == "pre_start":
            seen_header = True
            if parts != ["pre_start", "pre_end", "destination", "order", "phase", "heading"]:
                errs.append(f"{path_label}:{i}: header columns are {parts}")
            continue
        if len(parts) != 6:
            errs.append(f"{path_label}:{i}: {len(parts)} columns, want 6")
            continue
        try:
            rows.append(Row(int(parts[0]), int(parts[1]), parts[2], int(parts[3]),
                            parts[4], parts[5], i))
        except ValueError as e:
            errs.append(f"{path_label}:{i}: {e}")
    if not seen_header:
        errs.append(f"{path_label}: no header row")
    return rows, errs


def parse_roster(text):
    out = {}
    for raw in text.split("\n"):
        line = raw.strip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            continue
        out[parts[0]] = set(p for p in parts[1].split(",") if p)
    return out


def parse_additions(text):
    a = Additions()
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        i += 1
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("~ changed"):
            minus = plus = None
            while i < len(lines) and (lines[i].startswith("- ") or lines[i].startswith("+ ")):
                if lines[i].startswith("- "):
                    if minus is not None:
                        a.errors.append("changed block has two '-' lines")
                    minus = lines[i][2:]
                else:
                    if plus is not None:
                        a.errors.append("changed block has two '+' lines")
                    plus = lines[i][2:]
                i += 1
            if minus is None:
                a.errors.append("changed block has a '+' with no '-' (an unpaired half is how "
                                "a fabrication masquerades as a move)")
            elif plus is None:
                a.errors.append(f"changed block has a '-' with no '+' (unpaired): {minus[:60]!r} "
                                "(an unpaired half is how a deletion masquerades as a move)")
            else:
                a.changed.append((norm(minus), norm(plus)))
            continue
        if "\t" in line:
            t, payload = line.split("\t", 1)
            if t in ("pointer", "stanza"):
                a.typed.append((t, norm(payload)))
                continue
        a.errors.append(f"undeclared/untyped entry: {line[:80]!r}")
    return a


# ---------------------------------------------------------------------------
# block location
# ---------------------------------------------------------------------------

def find_block(hay, needle, start=0):
    """First index >= start where `needle` occurs as a contiguous run in `hay`."""
    if not needle:
        return start
    n = len(needle)
    first = needle[0]
    for i in range(start, len(hay) - n + 1):
        if hay[i] == first and hay[i:i + n] == needle:
            return i
    return -1


# ---------------------------------------------------------------------------
# controls
# ---------------------------------------------------------------------------

def control_partition(w, n_pre):
    """Mode 7: a PRE line assigned to no range, or to two."""
    fails = []
    cover = collections.Counter()
    for r in w.rows:
        if r.pre_start > r.pre_end:
            fails.append(f"C3 partition: row at line {r.lineno} is inverted ({r.pre_start}>{r.pre_end})")
            continue
        if r.pre_start < 1 or r.pre_end > n_pre:
            fails.append(f"C3 partition: row at line {r.lineno} range {r.pre_start}-{r.pre_end} "
                         f"falls outside PRE 1..{n_pre}")
            continue
        for k in range(r.pre_start, r.pre_end + 1):
            cover[k] += 1
    gaps = [k for k in range(1, n_pre + 1) if cover[k] == 0]
    over = [k for k in range(1, n_pre + 1) if cover[k] > 1]
    if gaps:
        fails.append(f"C3 partition: GAP - {len(gaps)} PRE line(s) claimed by no range "
                     f"(first: {gaps[:5]}) - that is text nobody claimed")
    if over:
        fails.append(f"C3 partition: OVERLAP - {len(over)} PRE line(s) claimed by more than one "
                     f"range (first: {over[:5]}) - that is text two files claim")
    if len(w.rows) != RANGE_COUNT_PIN:
        fails.append(f"C3 partition: range count {len(w.rows)} != pinned {RANGE_COUNT_PIN}")
    if len(w.rows) < RANGE_COUNT_FLOOR:
        fails.append(f"C3 partition: range count {len(w.rows)} < model minimum {RANGE_COUNT_FLOOR}")
    return fails


def control_phase_roster(w):
    """C3b part 1: the map's phase column induces exactly the pinned roster."""
    induced = collections.defaultdict(set)
    for r in w.rows:
        if r.destination != w.persona:
            induced[r.phase].add(r.destination)
    induced = {k: v for k, v in induced.items()}
    if induced != w.roster:
        only_map = {k: sorted(v) for k, v in induced.items() if w.roster.get(k) != v}
        only_ros = {k: sorted(v) for k, v in w.roster.items() if induced.get(k) != v}
        return [f"C3b: phase column does not induce the pinned roster; "
                f"map says {only_map}, {ROSTER_FILE} says {only_ros}"]
    return []


def expected_layout(w, phase):
    """{destination: [rows in the order they must appear]}, given the phase ordinal.

    phase is None for full mode. Rows not yet due are expected to still be in the
    persona, in PRE order, interleaved with the phase-0 rows.
    """
    layout = collections.defaultdict(list)
    not_due = []
    for r in w.rows:
        due = phase is None or float(r.phase) <= phase
        if r.destination == w.persona:
            layout[w.persona].append(r)
        elif due:
            layout[r.destination].append(r)
        else:
            layout[w.persona].append(r)
            not_due.append(r)
    for d in layout:
        if d == w.persona:
            layout[d].sort(key=lambda r: r.pre_start)
        else:
            layout[d].sort(key=lambda r: r.order)
    return layout, not_due


def control_order_column(w):
    """The order column must be 1..k per destination, and for the persona it must
    agree with PRE order - otherwise C3c's between-range check is pinned to a
    contradiction."""
    fails = []
    by = collections.defaultdict(list)
    for r in w.rows:
        by[r.destination].append(r)
    for d, rs in sorted(by.items()):
        orders = sorted(r.order for r in rs)
        if orders != list(range(1, len(rs) + 1)):
            fails.append(f"C3c: {d} order column is {orders}, want 1..{len(rs)}")
        if d == w.persona:
            if [r.order for r in sorted(rs, key=lambda x: x.pre_start)] != list(range(1, len(rs) + 1)):
                fails.append(f"C3c: {w.persona}'s order column disagrees with PRE order")
    return fails


def control_blocks(w, phase, present):
    """Modes 4, 5, 6, 8: forward, inverse, order (both scales), phase-exactness."""
    fails = []
    layout, not_due = expected_layout(w, phase)
    pre = w.pre_lines

    # index every existing post file once (F10: resolved once, reused)
    hay = {d: nonblank(w.files[d]) for d in present}

    not_due_ids = {id(r) for r in not_due}

    for dest, rows in sorted(layout.items()):
        if dest not in present:
            names = ", ".join(sorted({r.destination for r in rows}))
            fails.append(f"C3 forward: destination {dest} does not exist, but {len(rows)} "
                         f"mapped range(s) are due there ({names})")
            continue
        h = hay[dest]
        cursor = 0
        for r in rows:
            needle = nonblank(pre[r.pre_start - 1:r.pre_end])
            if not needle:
                continue
            i = find_block(h, needle, cursor)
            if i >= 0:
                cursor = i + len(needle)
                continue

            direction = "inverse" if r.destination == w.persona else "forward"
            where = f"PRE {r.pre_start}-{r.pre_end} ({r.heading[:60]})"

            # mode 8 - moved early
            if id(r) in not_due_ids:
                landed = [d for d in present if find_block(hay[d], needle, 0) >= 0]
                fails.append(
                    f"C3b: {where} has ordinal {r.phase} > --phase {phase} and must still be in "
                    f"{w.persona}, but it is not"
                    + (f" - it is already in {', '.join(landed)}" if landed else ""))
                continue

            # mode 6 - between-range: present, but earlier than a previous block
            j = find_block(h, needle, 0)
            if j >= 0:
                fails.append(f"C3c between-range: {where} is present in {dest} at non-blank line "
                             f"{j + 1} but the pinned order (order={r.order}) requires it at or "
                             f"after {cursor + 1} - two blocks in one destination are swapped")
                cursor = j + len(needle)
                continue

            # mode 6 - within-range: every line present, but not as a contiguous run in order
            hc = collections.Counter(h)
            if all(hc[x] > 0 for x in set(needle)):
                anchor = find_block(h, needle[:1], 0)
                fails.append(f"C3c within-range: {where} - all {len(needle)} line(s) are present in "
                             f"{dest} (first at non-blank line {anchor + 1}) but not as a contiguous "
                             f"block in PRE order: the lines were permuted")
                continue

            # mode 4 / 5 - wrong destination, or gone
            landed = [d for d in present if d != dest and find_block(hay[d], needle, 0) >= 0]
            if landed:
                fails.append(f"C3 {direction}: {where} is mapped to {dest} but its contiguous block "
                             f"is in {', '.join(landed)}")
            else:
                missing = [x for x in needle if hc[x] == 0]
                fails.append(f"C3 {direction}: {where} is not a contiguous block in {dest}; "
                             f"{len(missing)} of its {len(needle)} line(s) are absent from {dest} "
                             f"(first missing: {missing[0][:70]!r})" if missing else
                             f"C3 {direction}: {where} is not a contiguous block in {dest}")
    return fails


def control_c1(w, present):
    """Mode 1: nothing was lost."""
    pre = collections.Counter(nonblank(w.pre_lines))
    post = collections.Counter()
    for d in present:
        post.update(nonblank(w.files[d]))
    lost = pre - post
    for m in w.additions.minus_lines:
        if lost[m]:
            lost[m] -= 1
            if lost[m] == 0:
                del lost[m]
    if lost:
        items = list(lost.items())[:5]
        return [f"C1: {sum(lost.values())} PRE line-occurrence(s) absent from POST and not declared "
                f"as a `changed` predecessor; first: "
                + "; ".join(f"{k[:70]!r}x{v}" for k, v in items)]
    return []


def control_c2(w, present):
    """Mode 2: nothing was duplicated. Unconditional; NO allowlist path.
    Scoped to lines that exist in PRE (F32), or a legitimately declared pointer -
    zero PRE multiplicity by construction - would trip on its first appearance."""
    pre = collections.Counter(nonblank(w.pre_lines))
    post = collections.Counter()
    for d in present:
        post.update(nonblank(w.files[d]))
    bad = [(k, pre[k], post[k]) for k in pre if post[k] > pre[k]]
    if bad:
        bad.sort(key=lambda x: -(x[2] - x[1]))
        return [f"C2: {len(bad)} PRE line(s) occur more often in POST than in PRE - a rule left "
                f"inline AND carved is two copies that will drift; first: "
                + "; ".join(f"{k[:60]!r} {a}->{b}" for k, a, b in bad[:5])]
    return []


def control_c5(w, present, additions_floor):
    """Mode 3: every new line is declared and typed."""
    fails = []
    fails += [f"C5: malformed additions.allow - {e}" for e in w.additions.errors]

    pre = collections.Counter(nonblank(w.pre_lines))
    post = collections.Counter()
    for d in present:
        post.update(nonblank(w.files[d]))
    new = post - pre
    declared = collections.Counter(norm(x) for x in w.additions.plus_lines)
    undeclared = new - declared
    if undeclared:
        items = list(undeclared.items())[:5]
        fails.append(f"C5: {sum(undeclared.values())} POST line-occurrence(s) have no PRE origin and "
                     f"no declaration in {ADDITIONS_FILE}; first: "
                     + "; ".join(f"{k[:70]!r}x{v}" for k, v in items))

    # every declared addition occurs EXACTLY once in POST - this is where the
    # duplication guarantee for declared lines lives, since C2 cannot see them (F32).
    for t, payload in w.additions.typed:
        n = post[norm(payload)]
        if n != 1:
            fails.append(f"C5: declared {t} entry occurs {n}x in POST, want exactly 1: "
                         f"{payload[:70]!r}")
        if t == "pointer" and not POINTER_RE.search(payload):
            fails.append(f"C5: declared pointer does not match the D2 pointer form "
                         f"'**<Trigger>** — read `<FILE>.md` (*<heading>*)': {payload[:80]!r}")
    for minus, plus in w.additions.changed:
        if post[plus] != 1:
            fails.append(f"C5: declared `changed` replacement occurs {post[plus]}x in POST, want 1: "
                         f"{plus[:70]!r}")

    n_entries = len(w.additions.typed) + len(w.additions.changed)
    if n_entries < additions_floor:
        fails.append(f"C5: additions.allow has {n_entries} entries, floor is {additions_floor}")
    return fails


def control_c4(w, present, phase, n_pre, strict_set):
    """The vacuity control: population floors, the exact realpath set, post != baseline."""
    fails = []
    nb = len(nonblank(w.pre_lines))
    if nb < PRE_NONBLANK_FLOOR:
        fails.append(f"C4: PRE has {nb} non-blank lines, floor {PRE_NONBLANK_FLOOR} - an empty or "
                     f"truncated baseline would satisfy every other control vacuously")

    dests = {r.destination for r in w.rows}
    if EXCLUDED_FROM_PARTITION in dests:
        fails.append(f"C4: {EXCLUDED_FROM_PARTITION} appears in the carve map. It holds no PRE "
                     f"lines and cannot be a partition-set member (F33/F42); it is gated separately.")
    if strict_set:
        if len(dests) != CONTENT_DESTINATIONS + 1:
            fails.append(f"C4: carve map names {len(dests)} destinations, want exactly "
                         f"{CONTENT_DESTINATIONS + 1} ({w.persona} + {CONTENT_DESTINATIONS} content)")
        realpaths = {os.path.realpath(d) for d in present}
        if len(realpaths) != len(present):
            fails.append(f"C4: {len(present)} post-set paths resolve to only {len(realpaths)} "
                         f"realpath(s) - some destinations are the same file")
        if nonblank(w.files.get(w.persona, [])) == nonblank(w.persona_baseline):
            fails.append(f"C4: POST {w.persona} is identical to the baseline blob - nothing moved")
    return fails


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------

def run_controls(w, phase, additions_floor=0, strict_set=None):
    n_pre = len(w.pre_lines)
    if strict_set is None:
        strict_set = phase is None
    fails = []
    fails += control_partition(w, n_pre)
    fails += control_order_column(w)
    fails += control_phase_roster(w)

    layout, _ = expected_layout(w, phase)
    present = [d for d in sorted(layout) if d in w.files]

    fails += control_blocks(w, phase, present)
    fails += control_c1(w, present)
    fails += control_c2(w, present)
    fails += control_c5(w, present, additions_floor)
    fails += control_c4(w, present, phase, n_pre, strict_set)
    return fails, present


# ---------------------------------------------------------------------------
# repo mode
# ---------------------------------------------------------------------------

def resolve_baseline(root):
    """Hard FAIL on non-resolution or digest mismatch. Never a skip."""
    try:
        blob = subprocess.run(["git", "-C", str(root), "show", f"{BASE_SHA}:{BASE_PATH}"],
                              capture_output=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        stderr = getattr(e, "stderr", b"") or b""
        raise SystemExit(
            f"FAIL  carve_conservation   baseline blob {BASE_SHA}:{BASE_PATH} does not resolve "
            f"({stderr.decode().strip() or e}). A shallow clone cannot see it: the gates job needs "
            f"fetch-depth: 0. This is a hard failure, never a skip.")
    digest = hashlib.sha256(blob).hexdigest()
    if digest != BASE_BLOB_SHA256:
        raise SystemExit(
            f"FAIL  carve_conservation   baseline blob digest mismatch: got {digest}, pinned "
            f"{BASE_BLOB_SHA256}. The commit SHA proves which object was asked for; the digest "
            f"proves what came back.")
    return blob.decode()


def build_repo_world(root):
    pre = split_lines(resolve_baseline(root))
    map_p = root / MAP_FILE
    ros_p = root / ROSTER_FILE
    if not map_p.exists():
        raise SystemExit(f"FAIL  carve_conservation   {MAP_FILE} is missing - the partition spine")
    if not ros_p.exists():
        raise SystemExit(f"FAIL  carve_conservation   {ROSTER_FILE} is missing - the phase roster")
    rows, errs = parse_map(map_p.read_text(), MAP_FILE)
    if errs:
        raise SystemExit("FAIL  carve_conservation   " + "; ".join(errs))
    roster = parse_roster(ros_p.read_text())
    add_p = root / ADDITIONS_FILE
    additions = parse_additions(add_p.read_text() if add_p.exists() else "")
    files = {}
    for d in sorted({r.destination for r in rows}):
        p = root / d
        if p.exists():
            files[d] = split_lines(p.read_text())
    return World(pre, rows, roster, files, additions, "repo")


# ---------------------------------------------------------------------------
# self-test: 11 mutations on a synthetic mktemp fixture
#
# Idiom copied from scripts/mozart-contract-gates.sh:805-812 (v7_neg_fixdir):
# build the fixture, prove the filter both ways, remove it. The fixture never
# touches the repo tree, which is what makes the self-test valid at Phase 1.
# ---------------------------------------------------------------------------

# Written as TEXT with a trailing newline - exactly the shape a real file has - so
# every mutation runs against a world built through split_lines(). If the
# trailing-newline artifact were counted as a line, the POSITIVE CONTROL fails with
# a permanent partition GAP, which is how the repo tree caught it. Line 5 carries
# trailing whitespace that the POST copy does NOT have, so rstrip() normalization is
# demonstrated rather than asserted: drop it and the positive control goes red.
FIXTURE_PRE_TEXT = (
    "# Persona\n"                      # 1
    "\n"                               # 2
    "## Alpha (inline)\n"              # 3
    "alpha rule one\n"                 # 4
    "alpha rule two   \n"              # 5  <- trailing whitespace
    "\n"                               # 6
    "## Bravo\n"                       # 7
    "bravo line one\n"                 # 8
    "bravo line two\n"                 # 9
    "bravo line three\n"               # 10
    "\n"                               # 11
    "## Charlie\n"                     # 12
    "charlie line one\n"               # 13
    "charlie line two\n"               # 14
    "\n"                               # 15
    "## Delta (inline)\n"              # 16
    "delta rule one\n"                 # 17
    "\n"                               # 18
    "## Echo\n"                        # 19
    "echo line one\n"                  # 20
    "echo line two\n"                  # 21
    "\n"                               # 22
)
FIXTURE_PRE = split_lines(FIXTURE_PRE_TEXT)

# BRAVO.md deliberately receives its two ranges in NON-PRE order (echo block first),
# so between-range order is a real discriminator and not an accident of PRE order.
FIXTURE_ROWS = [
    Row(1, 6, "persona.md", 1, "0", "preamble + ## Alpha", 1),
    Row(7, 11, "BRAVO.md", 2, "2", "## Bravo", 2),
    Row(12, 15, "CHARLIE.md", 1, "3", "## Charlie", 3),
    Row(16, 18, "persona.md", 2, "0", "## Delta", 4),
    Row(19, 22, "BRAVO.md", 1, "2", "## Echo", 5),
]
FIXTURE_ROSTER = {"2": {"BRAVO.md"}, "3": {"CHARLIE.md"}}
FIXTURE_POINTER = ("**When you reach Bravo** — read `BRAVO.md` (*Bravo*) before acting.")


def fixture_world():
    pre = list(FIXTURE_PRE)
    seg = lambda a, z: list(pre[a - 1:z])
    # The persona's copy of PRE line 5 has its trailing whitespace stripped. Only a
    # working rstrip() makes it match; without one the positive control goes red on
    # C1 and C3 inverse.
    alpha = [l.rstrip() if l.strip() == "alpha rule two" else l for l in seg(1, 6)]
    assert alpha != seg(1, 6), "fixture must differ from PRE by trailing whitespace only"
    files = {
        "persona.md": alpha + [FIXTURE_POINTER, ""] + seg(16, 18),
        "BRAVO.md": seg(19, 22) + seg(7, 11),
        "CHARLIE.md": seg(12, 15),
    }
    additions = parse_additions("pointer\t" + FIXTURE_POINTER)
    w = World(pre, list(FIXTURE_ROWS), dict(FIXTURE_ROSTER), files, additions, "fixture",
              persona="persona.md")
    return w


def _fix_run(w, phase=None):
    """Run the controls against a fixture world with the repo-scale floors relaxed.
    The floors themselves are exercised in repo mode; here we are proving the
    seven property controls discriminate."""
    global RANGE_COUNT_PIN, RANGE_COUNT_FLOOR, PRE_NONBLANK_FLOOR, CONTENT_DESTINATIONS
    sp, sf, snb, scd = RANGE_COUNT_PIN, RANGE_COUNT_FLOOR, PRE_NONBLANK_FLOOR, CONTENT_DESTINATIONS
    RANGE_COUNT_PIN, RANGE_COUNT_FLOOR, PRE_NONBLANK_FLOOR, CONTENT_DESTINATIONS = 5, 5, 1, 2
    try:
        fails, _ = run_controls(w, phase, strict_set=(phase is None))
    finally:
        RANGE_COUNT_PIN, RANGE_COUNT_FLOOR, PRE_NONBLANK_FLOOR, CONTENT_DESTINATIONS = sp, sf, snb, scd
    return fails


def self_test(verbose=True):
    tmp = tempfile.mkdtemp(prefix="carve-selftest.")
    try:
        return _self_test_body(tmp, verbose)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _self_test_body(tmp, verbose):
    # Positive control FIRST: the unmutated fixture must pass. A self-test whose
    # clean case fails proves nothing about the mutated ones.
    clean = _fix_run(fixture_world())
    if clean:
        print("FAIL  carve_selftest       the UNMUTATED fixture does not pass:")
        for f in clean:
            print(f"        {f}")
        return 1

    # Also prove the fixture is written to disk, matching the repo's mktemp idiom.
    root = pathlib.Path(tmp)
    w0 = fixture_world()
    (root / "pre.md").write_text("\n".join(w0.pre_lines) + "\n")
    for name, lines in w0.files.items():
        (root / name).write_text("\n".join(lines) + "\n")
    # round-trip: reading them back through split_lines must reproduce the world,
    # or the fixture on disk is not the fixture the controls ran against.
    assert split_lines((root / "pre.md").read_text()) == w0.pre_lines, \
        "fixture pre.md does not round-trip through split_lines"
    for name, lines in w0.files.items():
        assert split_lines((root / name).read_text()) == lines, \
            f"fixture {name} does not round-trip through split_lines"

    mutations = []

    # 1 - C1: delete a line from a destination
    def m1():
        w = fixture_world()
        before = list(w.files["CHARLIE.md"])
        w.files["CHARLIE.md"] = [l for l in before if l != "charlie line two"]
        assert len(w.files["CHARLIE.md"]) == len(before) - 1, "mutation 1 did not apply"
        assert "charlie line two" not in w.files["CHARLIE.md"]
        return w, None, "CHARLIE.md lost 'charlie line two' (4 -> 3 lines)", "C1"

    # 2 - C2: duplicate a PRE line across two destinations
    def m2():
        w = fixture_world()
        assert "delta rule one" in w.files["persona.md"]
        assert "delta rule one" not in w.files["CHARLIE.md"]
        w.files["CHARLIE.md"] = w.files["CHARLIE.md"] + ["delta rule one"]
        assert w.files["CHARLIE.md"].count("delta rule one") == 1
        assert w.files["persona.md"].count("delta rule one") == 1
        return w, None, "'delta rule one' now occurs in BOTH persona.md and CHARLIE.md (1 -> 2)", "C2"

    # 3 - C5: add an undeclared line
    def m3():
        w = fixture_world()
        before = len(w.files["BRAVO.md"])
        w.files["BRAVO.md"] = w.files["BRAVO.md"] + ["a line nobody declared"]
        assert len(w.files["BRAVO.md"]) == before + 1, "mutation 3 did not apply"
        assert "a line nobody declared" not in w.pre_lines
        return w, None, "BRAVO.md gained 'a line nobody declared', absent from PRE and from additions.allow", "C5"

    # 4 - C5 pairing (F32): a `changed` '-' with no '+'
    def m4():
        w = fixture_world()
        w.additions = parse_additions("pointer\t" + FIXTURE_POINTER +
                                      "\n~ changed\n- alpha rule one\n")
        assert any("unpaired" in e for e in w.additions.errors), "mutation 4 did not apply"
        return w, None, "additions.allow carries '~ changed' with a '-' and no '+'", "C5"

    # 5 - C3 forward: move a range to a sibling destination
    def m5():
        w = fixture_world()
        blk = [l for l in w.pre_lines[11:15]]
        assert nonblank(blk), "mutation 5 fixture empty"
        w.files["CHARLIE.md"] = [l for l in w.files["CHARLIE.md"] if norm(l) not in
                                 set(nonblank(blk))]
        w.files["BRAVO.md"] = w.files["BRAVO.md"] + blk
        assert nonblank(w.files["CHARLIE.md"]) == [], "mutation 5 did not empty CHARLIE.md"
        assert all(x in nonblank(w.files["BRAVO.md"]) for x in nonblank(blk))
        return w, None, "the Charlie range (PRE 12-15) now sits in BRAVO.md, not CHARLIE.md", "C3 forward"

    # 6 - C3 inverse: delete an INLINE section from the persona
    def m6():
        w = fixture_world()
        gone = set(nonblank(w.pre_lines[15:18]))   # ## Delta + delta rule one
        before = len(nonblank(w.files["persona.md"]))
        w.files["persona.md"] = [l for l in w.files["persona.md"] if norm(l) not in gone]
        after = len(nonblank(w.files["persona.md"]))
        assert after == before - len(gone), "mutation 6 did not apply"
        assert not any(norm(l) in gone for l in w.files["persona.md"])
        return w, None, f"persona.md lost its inline '## Delta' range ({before} -> {after} non-blank)", "C3 inverse"

    # 7 - C3c within-range: permute two lines inside one range
    def m7():
        w = fixture_world()
        f = list(w.files["BRAVO.md"])
        i, j = f.index("bravo line one"), f.index("bravo line two")
        f[i], f[j] = f[j], f[i]
        assert f != w.files["BRAVO.md"], "mutation 7 did not apply"
        assert collections.Counter(f) == collections.Counter(w.files["BRAVO.md"]), \
            "mutation 7 must be a permutation, not an edit"
        w.files["BRAVO.md"] = f
        return w, None, "'bravo line one' and 'bravo line two' swapped inside BRAVO.md (same multiset)", "C3c within-range"

    # 8 - C3c between-range: swap two adjacent ranges in one destination
    def m8():
        w = fixture_world()
        before = list(w.files["BRAVO.md"])
        echo, bravo = w.pre_lines[18:22], w.pre_lines[6:11]
        w.files["BRAVO.md"] = list(bravo) + list(echo)
        assert w.files["BRAVO.md"] != before, "mutation 8 did not apply"
        assert collections.Counter(nonblank(w.files["BRAVO.md"])) == \
            collections.Counter(nonblank(before)), "mutation 8 must be a block swap, not an edit"
        return w, None, "BRAVO.md's two ranges swapped: order 2 block now precedes order 1 block", "C3c between-range"

    # 9 - C3 partition GAP: delete a map row
    def m9():
        w = fixture_world()
        before = len(w.rows)
        w.rows = [r for r in w.rows if not (r.pre_start == 12 and r.pre_end == 15)]
        assert len(w.rows) == before - 1, "mutation 9 did not apply"
        covered = set()
        for r in w.rows:
            covered |= set(range(r.pre_start, r.pre_end + 1))
        assert 12 not in covered, "mutation 9 left no gap"
        return w, None, f"map row for PRE 12-15 deleted ({before} -> {len(w.rows)} rows); PRE line 12 now unclaimed", "C3 partition"

    # 10 - C3 partition OVERLAP: overlap two map rows on one PRE line
    def m10():
        w = fixture_world()
        rows = list(w.rows)
        k = next(i for i, r in enumerate(rows) if r.pre_start == 12)
        rows[k] = rows[k]._replace(pre_start=11)
        w.rows = rows
        cov = collections.Counter()
        for r in w.rows:
            for x in range(r.pre_start, r.pre_end + 1):
                cov[x] += 1
        assert cov[11] == 2, "mutation 10 did not create an overlap"
        return w, None, "map row for PRE 12-15 widened to 11-15; PRE line 11 now claimed twice", "C3 partition"

    # 11 - C3b: pre-move a `phase > N` range
    def m11():
        w = fixture_world()
        # Run at --phase 2: only BRAVO is due. CHARLIE (ordinal 3) has moved early.
        assert nonblank(w.files["CHARLIE.md"]), "mutation 11 fixture empty"
        return w, 2, "run at --phase 2 with CHARLIE.md (ordinal 3) already carved out of the persona", "C3b"

    for fn in (m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11):
        mutations.append(fn)

    rows_out = []
    caught = 0
    for n, fn in enumerate(mutations, 1):
        try:
            w, phase, evidence, want = fn()
        except AssertionError as e:
            rows_out.append((n, "MUTATION DID NOT APPLY", str(e), "", "NOT APPLIED"))
            continue
        fails = _fix_run(w, phase)
        hit = [f for f in fails if f.startswith(want)]
        ok = bool(fails) and bool(hit)
        if ok:
            caught += 1
        rows_out.append((n, evidence, want, (hit[0] if hit else (fails[0] if fails else
                         "NO FAILURE - the mutation was NOT rejected")), "caught" if ok else "MISSED"))

    if verbose:
        print(f"      self-test fixture: {tmp} (removed on exit)")
        print(f"      positive control: unmutated fixture PASSES all controls")
        for n, ev, want, got, st in rows_out:
            print(f"      [{n:>2}] {st:<11} want={want:<20} {ev}")
            print(f"           observed: {got[:170]}")
    print(f"{'PASS' if caught == len(mutations) else 'FAIL'}  carve_selftest       "
          f"{caught} of {len(mutations)} mutations rejected, each by its named control "
          f"(floor 11); positive control green")
    return 0 if caught == len(mutations) else 1


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--phase", help="campaign ordinal (decimal, e.g. 5.3). Omit for the full check.")
    ap.add_argument("--self-test", action="store_true",
                    help="run the 11-mutation self-test on a synthetic mktemp fixture and exit")
    ap.add_argument("--additions-floor", type=int, default=0)
    ap.add_argument("--repo-root", default=None)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test(verbose=not args.quiet)

    # The self-test runs on EVERY invocation. A discriminator observed failing once
    # and then never again is an assertion about the past.
    if self_test(verbose=False) != 0:
        print("FAIL  carve_conservation   refusing to report on the tree: the gate's own "
              "self-test does not discriminate. Run --self-test for the per-mutation table.")
        return 1

    root = pathlib.Path(args.repo_root or
                        subprocess.run(["git", "rev-parse", "--show-toplevel"],
                                       capture_output=True, text=True,
                                       check=True).stdout.strip())
    w = build_repo_world(root)
    phase = float(args.phase) if args.phase is not None else None
    fails, present = run_controls(w, phase, additions_floor=args.additions_floor)

    scope = "full" if phase is None else f"--phase {args.phase}"
    detail = (f"{scope}: {len(w.rows)} ranges partition PRE 1..{len(w.pre_lines)} "
              f"({len(nonblank(w.pre_lines))} non-blank) across "
              f"{len({r.destination for r in w.rows})} mapped destination(s); "
              f"{len(present)} present; baseline {BASE_SHA[:12]} digest verified")
    if fails:
        print(f"FAIL  carve_conservation   {len(fails)} control failure(s) under {scope}")
        for f in fails:
            print(f"        {f}")
        return 1
    print(f"PASS  carve_conservation   {detail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
