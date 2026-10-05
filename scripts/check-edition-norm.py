#!/usr/bin/env python3
"""check-edition-norm.py - the clause-level run (V-NORM) of the edition parity work.

Source-only: this script reads git history and tests/parity/norm-map.tsv, neither of which a port
has, and it is never copied to a port. The table check (check-edition-text.py) pins named clauses
by position; this one compares whole sentences. It takes every sentence the predecessor campaign
added or changed in a mapped range of the source, rewrites it with the edition's closed rewrite
rows (tests/parity/translate.tsv), and prints each one the port's target file does not contain.

  check-edition-norm.py --edition E --class rules|layout --root PORT     the check
  check-edition-norm.py --check-map                                       the map covers the diff
  check-edition-norm.py --check-rewrites [--edition E]                    every rewrite row fires
  check-edition-norm.py --allowlist [--edition E]                         the replaced/dropped entries

Matching rule (test contract 1c.1b):
  * Added lines of `git diff <base> <head>` inside a mapped range. A sentence is a run of at least
    40 characters after whitespace collapse, split at ". ", "? ", "! ", at ".** " (a bold lead-in
    sentence stands alone), at table-cell boundaries ("|", not "\\|") and at list-item starts (the
    marker is dropped, so a renumbered list matches).
  * The edition's rewrite rows apply in one pass, longest `from` first.
  * A sentence matches when the rewritten, whitespace-collapsed text occurs in the whitespace-collapsed
    target file. Emphasis markers and backticks are not stripped.
  * One direction: a port may hold sentences the source never had. Only a sentence the target lacks is
    printed.
  * By default a sentence that also occurs among the removed lines of the same hunk is not checked: a
    line that changes one word is wholly "+" in the diff, and its unchanged sentences were ported (or
    deliberately worded otherwise) before this campaign. --all-added checks them too.
  * An added, non-blank line outside every row of the map is an error, not a pass.

Exit: 0 clean; 1 a sentence missing or a map/translate problem; 2 usage, or a revision this clone lacks.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

DEFAULT_BASE = "df2322d"
DEFAULT_HEAD = "3fdf576"
SPEC_PATHS = ["agents", "README.md", "INTEGRATION.md", "docs", "commands", "CONTRIBUTING.md"]
EDITIONS = ("codex", "copilot", "local")
CLASSES = ("rules", "layout")
MAP_COLUMNS = ["id", "file", "lines", "class", "codex", "copilot", "local", "note"]
TRANSLATE_COLUMNS = ["edition", "from", "to", "applies"]
MIN_SENTENCE = 40
ALLOW_KINDS = ("replaced", "dropped")

LIST_MARKER = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?")
CELL_SPLIT = re.compile(r"(?<!\\)\|")
SENTENCE_SPLIT = re.compile(r"(?<=[.?!]) |(?<=[.?!]\*\*) ")
HUNK_HEADER = re.compile(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


class Usage(Exception):
    pass


def collapse(text):
    return " ".join(text.split())


def sentences(line):
    found = []
    for cell in CELL_SPLIT.split(LIST_MARKER.sub("", line, count=1)):
        for part in SENTENCE_SPLIT.split(collapse(cell)):
            if len(part) >= MIN_SENTENCE:
                found.append(part)
    return found


# ---- the diff -------------------------------------------------------------------------------------

class Added:
    """One sentence of one added line."""

    def __init__(self, path, line, text, unchanged):
        self.path, self.line, self.text, self.unchanged = path, line, text, unchanged


class Diff:
    """What the predecessor added: each non-blank line as (path, number) -> text, and its sentences."""

    def __init__(self):
        self.lines, self.items = {}, []


def git(source, *args):
    """git -C <source>, whatever repository the caller's environment (a hook, a worktree) points at."""
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
    return subprocess.run(["git", "-C", source, *args], capture_output=True, text=True, env=env)


def require_revisions(source, revisions):
    for rev in revisions:
        if git(source, "rev-parse", "--verify", "--quiet", rev + "^{commit}").returncode != 0:
            raise Usage(f"revision {rev} is not in {source} (a shallow clone has no history to diff)")


def read_diff(source, base, head, paths):
    """Return a Diff: every non-blank added line, and the sentences of those lines."""
    require_revisions(source, [base, head])
    out = git(source, "diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", base, head, "--", *paths)
    if out.returncode != 0:
        raise Usage(f"git diff {base} {head} failed: {out.stderr.strip()[:200]}")
    diff = Diff()
    path, in_hunk = None, False
    added, removed = [], []

    def flush():
        removed_set = {s for r in removed for s in sentences(r)}
        for offset, text in enumerate(added):
            if text.strip():
                diff.lines[(path, hunk_start + offset)] = text
            for s in sentences(text):
                diff.items.append(Added(path, hunk_start + offset, s, s in removed_set))

    hunk_start = 0
    for raw in out.stdout.split("\n"):
        raw = raw.rstrip("\r")
        if raw.startswith("diff --git "):
            if in_hunk:
                flush()
            in_hunk, path, added, removed = False, None, [], []
        elif not in_hunk and raw.startswith("+++ "):
            path = raw[6:] if raw.startswith("+++ b/") else None
        elif raw.startswith("@@") and path is not None:
            if in_hunk:
                flush()
            match = HUNK_HEADER.match(raw)
            hunk_start = int(match.group(1))
            in_hunk, added, removed = True, [], []
        elif in_hunk and raw.startswith("+"):
            added.append(raw[1:])
        elif in_hunk and raw.startswith("-"):
            removed.append(raw[1:])
    if in_hunk:
        flush()
    return diff


# ---- the map and the rewrite table ---------------------------------------------------------------

class Cell:
    def __init__(self, kind, targets=(), reason=""):
        self.kind, self.targets, self.reason = kind, list(targets), reason


class Row:
    def __init__(self, ident, path, first, last, cls, cells, number):
        self.ident, self.path, self.first, self.last = ident, path, first, last
        self.cls, self.cells, self.number = cls, cells, number

    @property
    def span(self):
        return f"{self.path}:{self.first}-{self.last}"


def read_table(path):
    if not os.path.isfile(path):
        raise Usage(f"{path} does not exist")
    with open(path, encoding="utf-8", newline="") as handle:
        text = handle.read()
    return [r.rstrip("\r").split("\t") for r in text.split("\n") if r.rstrip("\r") != ""]


def parse_cell(text, where, problems):
    for kind in ALLOW_KINDS:
        if text == kind or text.startswith(kind + ":"):
            reason = text[len(kind) + 1:].strip()
            if not reason:
                problems.append(f"{where}: a {kind} cell needs a reason after the colon")
            return Cell(kind, reason=reason)
    targets = text.split(";")
    for target in targets:
        parts = target.split("/")
        if not target or target.startswith("/") or ".." in parts or "" in parts or target != target.strip():
            problems.append(f"{where}: {text!r} is neither a relative path list nor replaced:/dropped:<reason>")
            return Cell("targets")
    return Cell("targets", targets)


def load_map(path, problems):
    table = read_table(path)
    if not table or table[0] != MAP_COLUMNS:
        problems.append(f"{path}: header is not {'<TAB>'.join(MAP_COLUMNS)}")
        return []
    rows, seen = [], set()
    for number, fields in enumerate(table[1:], start=2):
        if len(fields) != len(MAP_COLUMNS):
            problems.append(f"{path}:{number}: {len(fields)} fields, want {len(MAP_COLUMNS)}")
            continue
        ident, file, span, cls = fields[:4]
        where = f"row {ident} ({path}:{number})"
        if not ident or ident in seen:
            problems.append(f"{where}: empty or repeated id")
        seen.add(ident)
        if cls not in CLASSES:
            problems.append(f"{where}: class {cls!r} is not one of {', '.join(CLASSES)}")
        match = re.fullmatch(r"(\d+)(?:-(\d+))?", span)
        if not match or int(match.group(2) or match.group(1)) < int(match.group(1)):
            problems.append(f"{where}: lines {span!r} is not N or A-B with A <= B")
            continue
        first, last = int(match.group(1)), int(match.group(2) or match.group(1))
        cells = {e: parse_cell(fields[4 + i], f"{where} {e}", problems) for i, e in enumerate(EDITIONS)}
        rows.append(Row(ident, file, first, last, cls, cells, number))
    return rows


def load_translate(path, problems):
    table = read_table(path)
    if not table or table[0] != TRANSLATE_COLUMNS:
        problems.append(f"{path}: header is not {'<TAB>'.join(TRANSLATE_COLUMNS)}")
        return {e: [] for e in EDITIONS}
    rules = {e: [] for e in EDITIONS}
    for number, fields in enumerate(table[1:], start=2):
        if len(fields) != 4 or not all(fields) or fields[0] not in EDITIONS:
            problems.append(f"{path}:{number}: not edition, from, to and applies in a known edition")
            continue
        rules[fields[0]].append((fields[1], fields[2]))
    return rules


class Rewriter:
    """One pass, longest `from` first: no replacement is rewritten again, whatever it contains."""

    def __init__(self, pairs):
        ordered = sorted(enumerate(pairs), key=lambda p: (-len(p[1][0]), p[0]))
        self.to = {f: t for _, (f, t) in ordered}
        self.fired = {f: 0 for f, _ in pairs}
        self.pattern = re.compile("|".join(re.escape(f) for _, (f, _) in ordered)) if pairs else None

    def __call__(self, text):
        if self.pattern is None:
            return text

        def swap(match):
            self.fired[match.group(0)] += 1
            return self.to[match.group(0)]
        return self.pattern.sub(swap, text)


# ---- coverage of the diff by the map -------------------------------------------------------------

def coverage_problems(rows, lines):
    problems = []
    by_file = {}
    for path, number in lines:
        by_file.setdefault(path, []).append(number)
    for path, numbers in by_file.items():
        spans = sorted((r for r in rows if r.path == path), key=lambda r: r.first)
        for left, right in zip(spans, spans[1:]):
            if right.first <= left.last:
                problems.append(f"overlap: rows {left.ident} and {right.ident} both cover {path}:{right.first}-{min(left.last, right.last)}")
        loose = [n for n in sorted(numbers) if not any(r.first <= n <= r.last for r in spans)]
        run = []
        for n in loose + [None]:
            if run and (n is None or n != run[-1] + 1):
                problems.append(f"unmapped {path}:{run[0]}-{run[-1]}")
                run = []
            if n is not None:
                run.append(n)
    for row in rows:
        if not any(p == row.path and row.first <= n <= row.last for p, n in lines):
            problems.append(f"row {row.ident} ({row.span}) covers no added line")
    return problems


# ---- the commands --------------------------------------------------------------------------------

def report_problems(problems):
    for problem in problems:
        print(f"ERROR {problem}")
    return 1 if problems else 0


def run_check(args, rows, rules, items):
    edition = args.edition
    rewrite = Rewriter(rules[edition])
    texts, missing_targets = {}, set()
    missing = allowed = checked = 0
    for row in (r for r in rows if r.cls == args.cls):
        cell = row.cells[edition]
        mine = [i for i in items if i.path == row.path and row.first <= i.line <= row.last and (args.all_added or not i.unchanged)]
        if cell.kind in ALLOW_KINDS:
            allowed += len(mine)
            continue
        for target in cell.targets:
            if target not in texts:
                full = os.path.join(args.root, target)
                if os.path.isfile(full):
                    with open(full, encoding="utf-8", errors="replace") as handle:
                        texts[target] = collapse(handle.read())
                else:
                    texts[target] = None
                    missing_targets.add(target)
                    print(f"NOTE target absent: {target} (row {row.ident})")
        for item in mine:
            wanted = rewrite(item.text)
            checked += 1
            if not any(texts[t] is not None and wanted in texts[t] for t in cell.targets):
                missing += 1
                print(f"MISSING {item.path}:{item.line} [{';'.join(cell.targets)}] {wanted}")
    print(f"norm {edition} {args.cls}: {missing} missing, {allowed} allow-listed, {checked} checked")
    return 1 if missing else 0


def run_allowlist(args, rows):
    counts = {}
    for edition in ([args.edition] if args.edition else EDITIONS):
        counts[edition] = {k: 0 for k in ALLOW_KINDS}
        for row in rows:
            cell = row.cells[edition]
            if cell.kind in ALLOW_KINDS:
                counts[edition][cell.kind] += 1
                print(f"{cell.kind} {row.span} {edition}: {cell.reason}")
    for edition, per in counts.items():
        print(f"allowlist {edition}: replaced {per['replaced']}, dropped {per['dropped']}")
    return 0


def run_check_rewrites(args, rows, rules, lines):
    """A row fires when it rewrites some added line (not only a 40-character sentence) that the edition checks."""
    problems = []
    for edition in ([args.edition] if args.edition else EDITIONS):
        rewrite = Rewriter(rules[edition])
        for row in (r for r in rows if r.cells[edition].kind == "targets"):
            for (path, number), text in lines.items():
                if path == row.path and row.first <= number <= row.last:
                    rewrite(text)
        unfired = [f for f, count in rewrite.fired.items() if count == 0]
        problems += [f"rewrite never fires: {edition} {f!r}" for f in unfired]
        if not unfired:
            print(f"rewrites ok: {edition} {len(rewrite.fired)} rows")
    return report_problems(problems)


def build_parser():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="clause-level comparison of the editions with the source", add_help=True)
    parser.add_argument("--edition")
    parser.add_argument("--class", dest="cls")
    parser.add_argument("--root", help="the port checkout to read")
    parser.add_argument("--source", default=os.path.dirname(here), help="the source checkout (default: this one)")
    parser.add_argument("--map")
    parser.add_argument("--translate")
    parser.add_argument("--base", default=DEFAULT_BASE)
    parser.add_argument("--head", default=DEFAULT_HEAD)
    parser.add_argument("--paths", nargs="+", default=SPEC_PATHS)
    parser.add_argument("--all-added", action="store_true", help="also check sentences unchanged within their hunk")
    parser.add_argument("--check-map", action="store_true")
    parser.add_argument("--check-rewrites", action="store_true")
    parser.add_argument("--allowlist", action="store_true")
    return parser


def main(argv):
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as stop:
        return 2 if stop.code else 0
    try:
        modes = [m for m in ("check_map", "check_rewrites", "allowlist") if getattr(args, m)]
        if len(modes) > 1:
            raise Usage("choose one of --check-map, --check-rewrites, --allowlist")
        if args.edition is not None and args.edition not in EDITIONS:
            raise Usage(f"unknown edition {args.edition!r}; one of {', '.join(EDITIONS)}")
        plain = not modes
        if plain and (args.edition is None or args.cls not in CLASSES or not args.root):
            raise Usage("a check needs --edition, --class rules|layout and --root")
        if args.root is not None and not os.path.isdir(args.root):
            raise Usage(f"--root {args.root} is not a directory")
        source = os.path.abspath(args.source)
        map_path = args.map or os.path.join(source, "tests", "parity", "norm-map.tsv")
        translate_path = args.translate or os.path.join(source, "tests", "parity", "translate.tsv")
        problems = []
        rows = load_map(map_path, problems)
        rules = load_translate(translate_path, problems)
        if args.allowlist:
            return report_problems(problems) or run_allowlist(args, rows)
        diff = read_diff(source, args.base, args.head, args.paths)
        problems += coverage_problems(rows, diff.lines)
        if problems:
            report_problems(problems)
            return 1
        if args.check_map:
            print(f"map ok: {len(rows)} rows, {len(diff.lines)} added lines covered")
            return 0
        if args.check_rewrites:
            return run_check_rewrites(args, rows, rules, diff.lines)
        return run_check(args, rows, rules, diff.items)
    except Usage as problem:
        print(f"usage: {problem}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
