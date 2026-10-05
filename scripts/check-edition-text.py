#!/usr/bin/env python3
"""check-edition-text.py - the edition parity reader.

One table (tests/parity/editions.tsv), one reader, shipped byte-identical in the
source repo and in every port. Each row names a rule by position (a file, a heading,
a table row) and says what must be there. See CONTRIBUTING.md in the source repo.

  check-edition-text.py --edition <name> --root <dir> [--source <dir>] [--table <path>]
      [--done "<phase ids>"] [--expect-rows N] [--expect-source-rows N]
      [--expect-ids SHA] [--expect-table-sha256 SHA] [--expect-policy-sha256 SHA]
      [--expect-reader-sha256 SHA]
  check-edition-text.py selftest
  check-edition-text.py hashes --edition <name>

Output, one line per row: ok / FAIL / PENDING / NEEDS-SOURCE. Exit 0 all ok, 1 any
FAIL, 5 no FAIL and some PENDING, 2 a bad command line.

Row cells that carry options:
  scope   ';'-separated paths or globs under --root; a trailing '+' says the phase
          creates the file. Globs never reach a /fixtures/ path.
  anchor  a heading line that must occur exactly once outside fenced blocks, then
          optional flags ' @+' (the phase creates the heading), ' @stop=N' and ' @fenced'
          (once, count, each-once, terms, pair and shape skip fenced lines and <!-- -->
          comments unless ' @fenced', which keeps fenced lines; absent and absent-re
          read hidden text too).
  row     per kind: the first cell (emphasis stripped) of one table row, 'exact' (once,
          count: whole lines equal to the needle), 'line:<prefix>' for one
          line, or key=value options (bullet-last, absent-re, gaps, moved).
  needle  a literal, or '@name' for a file in the policy directory beside the table.
"""

from __future__ import annotations

import difflib
import filecmp
import glob
import hashlib
import os
import re
import subprocess
import sys
import tempfile

EDITIONS = ("orchestration", "codex", "copilot", "local")
PHASES = ("0", "1b", "2", "3", "4", "5", "6", "7")
PHASE_ORDER = {p: i for i, p in enumerate(PHASES)}
COLUMNS = ("id", "edition", "phase", "kind", "scope", "anchor", "row", "expect", "needle")
TEXT_KINDS = ("once", "absent", "count", "each-once", "terms")
# These read only what a reader of the rendered page sees: no fenced line, no <!-- --> comment.
# absent and absent-re (and gaps) keep scanning hidden text, so a stale wording cannot hide in it.
VISIBLE_KINDS = ("once", "count", "each-once", "terms", "pair", "shape")
MAX_BYTES = 4 * 1024 * 1024
COMMENT_RE = re.compile(r"<!--.*?(?:-->|\Z)", re.S)
SRC_KINDS = ("cmp-src", "diff-src", "tree-src", "lens-src")
KINDS = (
    *TEXT_KINDS,
    "bullet-last",
    "absent-re",
    "pair",
    "gaps",
    "shape",
    "moved",
    "file-eq",
    "block-eq",
    *SRC_KINDS,
)
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
HEAD_RE = re.compile(r"^(#{1,6}) +\S")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
ANCHOR_RE = re.compile(r"^(.*?)((?: @(?:\+|fenced|stop=[1-6]))*)$")
POLICY_REF_RE = re.compile(r"(?:^|[=;])@([A-Za-z0-9._-]+)")
MASK_TOKEN = "XANDER-SURFACE-RULE"
SURVIVORS = "survivors.tsv"
LENS_TIMEOUT = 600


class Defect(Exception):
    """The row or table is malformed: always a FAIL, whatever the row's phase."""


class Content(Exception):
    """The text is not there yet: PENDING before the row's phase, FAIL at or after it."""

    def __init__(self, cls: str, detail: str = "") -> None:
        super().__init__(detail or cls)
        self.cls = cls
        self.detail = detail


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_bytes(path: str) -> bytes:
    try:
        if os.path.getsize(path) > MAX_BYTES:
            raise Defect(f"{path!r} is larger than {MAX_BYTES} bytes")
        with open(path, "rb") as fh:
            return fh.read()
    except OSError as exc:
        raise Defect(f"cannot read {path!r}: {exc}") from exc


def read_text(path: str) -> str:
    try:
        text = read_bytes(path).decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise Defect(f"cannot read {path}: {exc}") from exc
    return text.replace("\r\n", "\n")


def load_prose(path: str) -> str:
    """The text a text row matches: the file, or for a .toml its developer_instructions."""
    if not path.endswith(".toml"):
        return read_text(path)
    try:
        import tomllib
    except ImportError as exc:
        raise Defect("tomllib is needed for a .toml scope (Python 3.11 or later)") from exc
    try:
        data = tomllib.loads(read_text(path))
    except tomllib.TOMLDecodeError as exc:
        raise Defect(f"{path} does not parse as TOML: {exc}") from exc
    value = data.get("developer_instructions")
    if not isinstance(value, str) or not value.strip():
        raise Defect(f"{path} has no developer_instructions")
    return value.replace("\r\n", "\n")


# ---------------------------------------------------------------- markdown helpers


def fence_map(lines: list[str]) -> tuple[list[bool], list[tuple[int, int]]]:
    """inside[i] is true for a fence line and for a line within a fenced block;
    blocks are the outermost (open, close) line indexes. A fence line with an info
    string always opens a block, nested if one is open (these files nest ```mermaid
    inside ```markdown); a bare fence closes the innermost block when it is at least
    as long and of the same character, and is content otherwise. An unclosed block
    runs to the end of the file."""
    inside = [False] * len(lines)
    blocks: list[tuple[int, int]] = []
    stack: list[tuple[str, int, int]] = []
    for i, line in enumerate(lines):
        m = FENCE_RE.match(line)
        if m is None:
            inside[i] = bool(stack)
            continue
        char, size, info = m.group(1)[0], len(m.group(1)), m.group(2).strip()
        if not stack:
            if char == "`" and "`" in info:
                continue
            stack.append((char, size, i))
            inside[i] = True
            continue
        inside[i] = True
        top = stack[-1]
        if not info and char == top[0] and size >= top[1]:
            stack.pop()
            if not stack:
                blocks.append((top[2], i))
        elif info and not (char == "`" and "`" in info):
            stack.append((char, size, i))
    if stack:
        blocks.append((stack[0][2], len(lines) - 1))
    return inside, blocks


def heading_level(line: str) -> int:
    m = HEAD_RE.match(line)
    return len(m.group(1)) if m else 0


def parse_anchor(cell: str) -> tuple[str, bool, int | None, bool]:
    """(heading, created by the phase, stop level, scan fenced text too)."""
    m = ANCHOR_RE.match(cell)
    text, flags = (m.group(1), m.group(2)) if m else (cell, "")
    stop = re.search(r" @stop=([1-6])", flags)
    return text, " @+" in flags, int(stop.group(1)) if stop else None, " @fenced" in flags


def visible(lines: list[str], keep_fenced: bool) -> list[str]:
    """The lines with comment spans (and, unless keep_fenced, fenced lines) blanked; the line
    count is kept so a position in the result is a position in the file."""
    if not keep_fenced:
        inside = fence_map(lines)[0]
        lines = ["" if inside[i] else ln for i, ln in enumerate(lines)]
    text = COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), "\n".join(lines))
    return text.split("\n")


def cut_section(
    lines: list[str],
    anchor: str,
    created: bool,
    stop: int | None,
    where: str,
    fenced: bool = True,
) -> list[str]:
    inside = fence_map(lines)[0] if fenced else [False] * len(lines)
    hits = [i for i, ln in enumerate(lines) if not inside[i] and ln.strip() == anchor]
    if len(hits) > 1:
        raise Defect(f"anchor {anchor!r} occurs {len(hits)} times outside fences in {where}")
    if not hits:
        if created:
            raise Content("anchor-created", f"anchor {anchor!r} is created by this phase")
        raise Defect(f"anchor {anchor!r} is absent from {where}")
    start = hits[0]
    limit = stop if stop is not None else heading_level(lines[start])
    if limit == 0:
        raise Defect(f"anchor {anchor!r} is not a heading line")
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if not inside[j] and 0 < heading_level(lines[j]) <= limit:
            end = j
            break
    return lines[start:end]


def first_cell(line: str) -> str:
    body = re.sub(r"^\s*\|\s*", "", line)
    m = re.search(r"(?<!\\)\|", body)
    cell = body[: m.start()] if m else body
    return cell.replace("*", "").strip()


def table_rows(lines: list[str]) -> list[list[str]]:
    """Cells of each pipe-table line outside fences (separator rows included)."""
    inside, _ = fence_map(lines)
    out = []
    for i, ln in enumerate(lines):
        if not inside[i] and ln.lstrip().startswith("|"):
            out.append(split_cells(ln))
    return out


def split_cells(line: str) -> list[str]:
    body = line.strip()
    body = body[1:] if body.startswith("|") else body
    body = body[:-1] if body.endswith("|") and not body.endswith("\\|") else body
    return [c.strip() for c in re.split(r"(?<!\\)\|", body)]


def cut_row(lines: list[str], sel: str, where: str) -> list[str]:
    created = sel.endswith(" @+")
    sel = sel[:-3] if created else sel
    if sel.startswith("line:"):
        prefix = sel[5:]
        hits = [ln for ln in lines if ln.lstrip().startswith(prefix)]
        label = "line"
    else:
        inside, _ = fence_map(lines)
        hits = [
            ln
            for i, ln in enumerate(lines)
            if not inside[i] and ln.lstrip().startswith("|") and first_cell(ln) == sel
        ]
        label = "table row"
    if not hits and created:
        raise Content("anchor-created", f"{label} {sel!r} is created by this phase")
    if len(hits) != 1:
        raise Defect(f"{label} selector {sel!r} matched {len(hits)} in {where}, want exactly 1")
    return hits


# ---------------------------------------------------------------- context


class Ctx:
    def __init__(self, edition: str, root: str, source: str | None, table: str) -> None:
        self.edition = edition
        self.root = root
        self.source = source
        self.table = table
        self.policy_dir = os.path.join(os.path.dirname(os.path.dirname(table)), "policy")

    def policy_text(self, spec: str) -> str:
        name = spec[1:]
        if "/" in name or name.startswith("."):
            raise Defect(f"policy reference {spec!r} is not a plain file name")
        path = os.path.join(self.policy_dir, name)
        if not os.path.isfile(path):
            raise Defect(f"policy file {name} is absent from {self.policy_dir}")
        text = read_text(path)
        if not text.strip():
            raise Defect(f"policy file {name} is empty")
        return text

    def needle(self, spec: str) -> str:
        if spec.startswith("@"):
            text = self.policy_text(spec)
            return text[:-1] if text.endswith("\n") else text
        if spec == "":
            raise Defect("the needle is empty")
        return spec

    def needle_lines(self, spec: str) -> list[str]:
        if not spec.startswith("@"):
            raise Defect("this kind needs an @file needle")
        lines = [ln for ln in self.policy_text(spec).split("\n") if ln.strip()]
        if not lines:
            raise Defect("the needle file holds no lines")
        return lines

    def survivors(self, row_id: str, opts: dict[str, str]) -> set[tuple[str, str]]:
        spec = opts.get("allow")
        if spec is None:
            return set()
        allowed = set()
        for ln in self.policy_text(spec).split("\n"):
            parts = ln.split("\t")
            if len(parts) == 3 and parts[0] == row_id:
                allowed.add((parts[1], parts[2]))
        return allowed


def parse_opts(cell: str) -> dict[str, str]:
    opts = {}
    for part in cell.split(";"):
        if part.strip():
            key, sep, value = part.partition("=")
            if not sep:
                raise Defect(f"option {part!r} is not key=value")
            opts[key.strip()] = value.strip()
    return opts


def resolve_scope(root: str, cell: str) -> tuple[list[str], list[str]]:
    """(existing files as root-relative paths, entries marked '+' that do not exist yet)."""
    files: list[str] = []
    missing: list[str] = []
    real_root = os.path.realpath(root)
    entries = [e.strip() for e in cell.split(";") if e.strip()]
    if not entries:
        raise Defect("the scope is empty")
    for entry in entries:
        created = entry.endswith("+")
        path = entry[:-1] if created else entry
        if not path or os.path.isabs(path) or ".." in path.split("/"):
            raise Defect(f"scope entry {entry!r} is empty, absolute or climbs out of the root")
        if any(ch in path for ch in "*?["):
            found = sorted(
                os.path.relpath(p, root)
                for p in glob.glob(os.path.join(root, path), recursive=True)
                if os.path.isfile(p)
            )
            found = [p for p in found if "/fixtures/" not in "/" + p]
            if not found and not created:
                raise Defect(f"scope {entry!r} matches no file")
            if not found:
                missing.append(path)
            files.extend(found)
        elif os.path.isfile(os.path.join(root, path)):
            files.append(path)
        elif created:
            missing.append(path)
        else:
            raise Defect(f"scope file {path} does not exist under the root")
    for rel in files:
        full = os.path.join(root, rel)
        inside_root = os.path.realpath(full).startswith(real_root + os.sep)
        if os.path.islink(full) or not inside_root:
            raise Defect(f"scope file {rel!r} is a symlink or resolves outside the root")
    return files, missing


def spans(ctx: Ctx, row: dict[str, str]) -> list[tuple[str, list[str]]]:
    """The located text of every scope file: whole file, anchored section, or one row."""
    files, missing = resolve_scope(ctx.root, row["scope"])
    if missing:
        raise Content("file-created", f"created by this phase: {', '.join(missing)}")
    anchor, created, stop, keep_fenced = parse_anchor(row["anchor"])
    out = []
    for rel in files:
        lines = load_prose(os.path.join(ctx.root, rel)).split("\n")
        if row["kind"] in VISIBLE_KINDS:
            lines = visible(lines, keep_fenced)
        if anchor:
            lines = cut_section(lines, anchor, created, stop, rel)
        if row["row"] and row["row"] != "exact" and row["kind"] in TEXT_KINDS:
            lines = cut_row(lines, row["row"], rel)
        out.append((rel, lines))
    return out


def joined(sp: list[tuple[str, list[str]]]) -> str:
    return "\n".join("\n".join(lines) for _, lines in sp)


# ---------------------------------------------------------------- kinds


def k_count(ctx: Ctx, row: dict[str, str], n: int) -> None:
    text = joined(spans(ctx, row))
    needle = ctx.needle(row["needle"])
    want = {"once": 1, "absent": 0}.get(row["kind"], n)
    if row["kind"] in ("once", "absent") and n != want:
        raise Defect(f"{row['kind']} needs expect {want}")
    if row["row"] == "exact":
        got = sum(1 for ln in text.split("\n") if ln.strip() == needle)
    else:
        got = text.count(needle)
    if got == want:
        return
    if want == 0:
        raise Content("stale-present", f"{got} occurrence(s) of the stale wording, want 0")
    if got == 0:
        raise Content("needle-absent", f"the needle occurs 0 times, want {want}")
    raise Content("count-mismatch", f"the needle occurs {got} times, want {want}")


def k_each_once(ctx: Ctx, row: dict[str, str], n: int) -> None:
    lines = ctx.needle_lines(row["needle"])
    if len(lines) != n:
        raise Defect(f"expect {n} but the needle file holds {len(lines)} lines")
    text = joined(spans(ctx, row))
    absent = [ln for ln in lines if text.count(ln) == 0]
    twice = [ln for ln in lines if text.count(ln) > 1]
    if absent:
        raise Content(
            "needle-absent", f"{len(absent)} of {n} clauses absent, first: {absent[0][:60]!r}"
        )
    if twice:
        raise Content(
            "count-mismatch", f"{len(twice)} clause(s) occur twice, first: {twice[0][:60]!r}"
        )


def k_terms(ctx: Ctx, row: dict[str, str], n: int) -> None:
    pairs = []
    for ln in ctx.needle_lines(row["needle"]):
        name, sep, pat = ln.partition("\t")
        if not sep or not pat:
            raise Defect(f"terms line {ln[:40]!r} is not name<TAB>pattern")
        try:
            pairs.append((name, re.compile(pat)))
        except re.error as exc:
            raise Defect(f"term {name!r}: bad pattern: {exc}") from exc
    if len(pairs) != n:
        raise Defect(f"expect {n} but the needle file holds {len(pairs)} terms")
    lines = [ln for _, ls in spans(ctx, row) for ln in ls]
    lacking = [name for name, rx in pairs if not any(rx.search(ln) for ln in lines)]
    if lacking:
        raise Content("needle-absent", f"{len(lacking)} of {n} terms absent: {', '.join(lacking)}")


def k_bullet_last(ctx: Ctx, row: dict[str, str], n: int) -> None:
    opts = parse_opts(row["row"])
    want_len = int(opts.get("len", "0") or 0)
    exclude = {e for e in opts.get("exclude", "").split(",") if e}
    if want_len < 2:
        raise Defect("bullet-last needs len=N in the row cell")
    anchor, _, stop, _ = parse_anchor(row["anchor"])
    if not anchor:
        raise Defect("bullet-last needs the cadence heading as its anchor")
    bullet = ctx.needle(row["needle"])
    files, missing = resolve_scope(ctx.root, row["scope"])
    if missing:
        raise Content("file-created", f"created by this phase: {', '.join(missing)}")
    roster = []
    for rel in files:
        if os.path.basename(rel) in exclude:
            continue
        lines = visible(load_prose(os.path.join(ctx.root, rel)).split("\n"), True)
        if any(ln.strip() == anchor for ln in lines):
            roster.append((rel, cut_section(lines, anchor, False, stop, rel, fenced=False)))
    if len(roster) != n:
        raise Content(
            "count-mismatch", f"the cadence marker selects {len(roster)} file(s), want {n}"
        )
    absent, misplaced, twice = [], [], []
    for rel, sec in roster:
        stem = os.path.basename(rel).split(".")[0]
        length = int(opts.get(stem, want_len))
        hits = [i for i, ln in enumerate(sec) if ln == bullet]
        if not hits:
            absent.append(rel)
        elif len(hits) > 1:
            twice.append(rel)
        elif not bullet_is_last(sec, hits[0], length):
            misplaced.append(rel)
    if absent:
        raise Content(
            "needle-absent", f"the bullet is absent from {len(absent)} of {n}: {absent[0]}"
        )
    if twice:
        raise Content("count-mismatch", f"the bullet occurs twice in {twice[0]}")
    if misplaced:
        raise Content(
            "shape-mismatch",
            f"the bullet is not the last item of a list of the right length in {misplaced[0]}",
        )


def bullet_is_last(sec: list[str], i: int, length: int) -> bool:
    a = i
    while a > 0 and sec[a - 1].startswith("- "):
        a -= 1
    b = i
    while b + 1 < len(sec) and sec[b + 1].startswith("- "):
        b += 1
    return i > a and sec[i - 1].startswith("- **On return**") and i == b and b - a + 1 == length


def k_absent_re(ctx: Ctx, row: dict[str, str], n: int) -> None:
    if n != 0:
        raise Defect("absent-re needs expect 0")
    opts = parse_opts(row["row"])
    try:
        rx = re.compile(ctx.needle(row["needle"]))
    except re.error as exc:
        raise Defect(f"bad regex: {exc}") from exc
    mask = ctx.needle(opts["mask"]) if "mask" in opts else None
    allowed = ctx.survivors(row["id"], opts)
    hits = []
    for rel, lines in spans(ctx, row):
        for i, ln in enumerate(lines, 1):
            seen = ln.replace(mask, MASK_TOKEN) if mask else ln
            if rx.search(seen) and (rel, ln) not in allowed:
                hits.append(f"{rel}:{i}")
    if hits:
        raise Content("stale-present", f"{len(hits)} stale line(s), first {hits[0]}")


def k_pair(ctx: Ctx, row: dict[str, str], n: int) -> None:
    needle = ctx.needle(row["needle"])
    sp = spans(ctx, row)
    if len(sp) != n:
        raise Defect(f"expect {n} files but the scope holds {len(sp)}")
    lacking = [rel for rel, lines in sp if needle not in "\n".join(lines)]
    if lacking:
        raise Content(
            "needle-absent", f"{len(lacking)} of {n} files lack the replacement, first {lacking[0]}"
        )


def k_gaps(ctx: Ctx, row: dict[str, str], n: int) -> None:
    if n != 0:
        raise Defect("gaps needs expect 0")
    allowed = ctx.survivors(row["id"], parse_opts(row["row"]))
    hits = []
    for rel, lines in spans(ctx, row):
        for i, ln in enumerate(lines, 1):
            if "TINY" in ln and "STANDARD" in ln and "LIGHT" not in ln and (rel, ln) not in allowed:
                hits.append(f"{rel}:{i}")
    if hits:
        raise Content(
            "stale-present",
            f"{len(hits)} line(s) name TINY and STANDARD without LIGHT, first {hits[0]}",
        )


def k_shape(ctx: Ctx, row: dict[str, str], n: int) -> None:
    opts = parse_opts(row["needle"])
    sp = spans(ctx, row)
    for rel, lines in sp:
        rows = table_rows(lines)
        if not rows:
            raise Defect(f"no table in the located span of {rel}")
        block = []
        for cells in rows:
            block.append(cells)
        head = block[0]
        body = [c for c in block[1:] if not all(re.fullmatch(r":?-+:?", x) or not x for x in c)]
        ragged = [i for i, c in enumerate(block) if len(c) != len(head)]
        if ragged:
            raise Content(
                "shape-mismatch",
                f"{rel}: a row has {len(block[ragged[0]])} cells, the header {len(head)}",
            )
        if "header" in opts and opts["header"] not in [h.replace("*", "") for h in head]:
            raise Content("shape-mismatch", f"{rel}: the header names no {opts['header']}")
        if "first" in opts:
            firsts = [c[0].replace("*", "") for c in body]
            if firsts != opts["first"].split(","):
                raise Content("shape-mismatch", f"{rel}: first cells read {','.join(firsts)}")
        if len(body) != n:
            raise Content("shape-mismatch", f"{rel}: {len(body)} body rows, want {n}")


def first_line(text: str) -> str:
    return text.split("\n", 1)[0]


def k_moved(ctx: Ctx, row: dict[str, str], n: int) -> None:
    opts = parse_opts(row["row"])
    if "inline" in opts:
        line = ctx.needle(row["needle"])
        text = joined(spans(ctx, row))
        got = text.count(line)
        if got != 1:
            cls = "needle-absent" if got == 0 else "count-mismatch"
            raise Content(cls, f"the skeleton's first line occurs {got} times in the host, want 1")
        return
    files, missing = resolve_scope(ctx.root, row["scope"])
    if missing:
        raise Content("file-created", f"created by this phase: {', '.join(missing)}")
    if len(files) != n:
        raise Defect(f"expect {n} templates but the scope holds {len(files)}")
    pop_dir = os.path.join(ctx.root, opts.get("pop", ""))
    if not opts.get("pop") or not os.path.isdir(pop_dir):
        raise Defect("moved needs pop=<existing directory>")
    hosts = dict(p.split("=", 1) for p in row["needle"].split(";") if "=" in p)
    pop = sorted(
        os.path.relpath(p, ctx.root)
        for p in glob.glob(os.path.join(pop_dir, "**", "*.md"), recursive=True)
        if os.path.isfile(p)
    )
    for rel in files:
        name = os.path.basename(rel)
        text = load_prose(os.path.join(ctx.root, rel))
        first = first_line(text)
        if not text.strip() or not first.strip():
            raise Content("shape-mismatch", f"{rel} is empty")
        host = hosts.get(name)
        if host is None or not os.path.isfile(os.path.join(ctx.root, host)):
            raise Defect(f"no existing host named for {name} in the needle")
        if name not in load_prose(os.path.join(ctx.root, host)):
            raise Content("needle-absent", f"{host} does not cite {name}")
        total = sum(
            1 for p in pop for ln in read_text(os.path.join(ctx.root, p)).split("\n") if ln == first
        )
        if total != 1:
            raise Content(
                "count-mismatch",
                f"the first line of {name} occurs {total} times in the bundle, want 1",
            )


def k_file_eq(ctx: Ctx, row: dict[str, str], n: int) -> None:
    if n != 1:
        raise Defect("file-eq needs expect 1")
    files, missing = resolve_scope(ctx.root, row["scope"])
    if missing:
        raise Content("file-created", f"created by this phase: {', '.join(missing)}")
    if len(files) != 1:
        raise Defect("file-eq needs exactly one file in scope")
    want = ctx.policy_text(row["needle"])
    got = read_text(os.path.join(ctx.root, files[0]))
    if not got.strip():
        raise Content("shape-mismatch", f"{files[0]} is empty")
    if got != want:
        raise Content("shape-mismatch", f"{files[0]} differs from the shipped {row['needle'][1:]}")


def k_block_eq(ctx: Ctx, row: dict[str, str], n: int) -> None:
    sp = spans(ctx, row)
    if len(sp) != 1:
        raise Defect("block-eq needs exactly one file in scope")
    rel, lines = sp[0]
    _, blocks = fence_map(lines)
    if len(blocks) != n:
        raise Content(
            "count-mismatch", f"{rel} holds {len(blocks)} fenced block(s) in the span, want {n}"
        )
    opts = parse_opts(row["row"])
    if "block" not in opts or not opts["block"].isdigit() or not 1 <= int(opts["block"]) <= n:
        raise Defect("block-eq needs block=<1..expect> in the row cell")
    a, b = blocks[int(opts["block"]) - 1]
    got = "\n".join(lines[a + 1 : b])
    want = ctx.policy_text(row["needle"]).rstrip("\n")
    if got != want:
        raise Content(
            "shape-mismatch", f"block {opts['block']} differs from the shipped {row['needle'][1:]}"
        )


def need_source(ctx: Ctx) -> str:
    if ctx.source is None:
        raise Defect("internal: a source row was evaluated without --source")
    return ctx.source


def k_cmp_src(ctx: Ctx, row: dict[str, str], n: int) -> None:
    if n != 1:
        raise Defect("cmp-src needs expect 1")
    files, missing = resolve_scope(ctx.root, row["scope"])
    if missing:
        raise Content("file-created", f"created by this phase: {', '.join(missing)}")
    if len(files) != 1:
        raise Defect("cmp-src needs exactly one file in scope")
    other = os.path.join(need_source(ctx), row["needle"])
    if not os.path.isfile(other):
        raise Defect(f"source file {row['needle']} is absent")
    a, b = read_bytes(os.path.join(ctx.root, files[0])), read_bytes(other)
    if not a or not b:
        raise Content("shape-mismatch", f"{files[0]} or its source is empty")
    if a != b:
        raise Content("shape-mismatch", f"{files[0]} differs from the source's {row['needle']}")


def live_diff(src_path: str, port_path: str, src_label: str, port_label: str) -> str:
    a = read_text(src_path).split("\n")
    b = read_text(port_path).split("\n")
    out = difflib.unified_diff(a, b, f"a/{src_label}", f"b/{port_label}", n=0, lineterm="")
    return "\n".join(out)


def held_section(held: str, port_label: str) -> str:
    """The part of a held diff whose '+++ b/' header names the port file, or ''."""
    chunks: list[list[str]] = []
    for ln in held.split("\n"):
        if ln.startswith("--- a/"):
            chunks.append([])
        if chunks:
            chunks[-1].append(ln)
    for chunk in chunks:
        if len(chunk) > 1 and chunk[1] == f"+++ b/{port_label}":
            return "\n".join(chunk).rstrip("\n")
    return ""


def k_diff_src(ctx: Ctx, row: dict[str, str], n: int) -> None:
    if n != 1:
        raise Defect("diff-src needs expect 1")
    opts = parse_opts(row["needle"])
    if "src" not in opts or "held" not in opts:
        raise Defect("diff-src needs src=<source file>;held=<held diff>")
    files, missing = resolve_scope(ctx.root, row["scope"])
    if missing:
        raise Content("file-created", f"created by this phase: {', '.join(missing)}")
    if len(files) != 1:
        raise Defect("diff-src needs exactly one file in scope")
    source = need_source(ctx)
    src_path = os.path.join(source, opts["src"])
    if not os.path.isfile(src_path):
        raise Defect(f"source file {opts['src']} is absent")
    held_path = os.path.join(source, opts["held"])
    if not os.path.isfile(held_path):
        raise Content("file-created", f"the held diff {opts['held']} is written by this phase")
    live = live_diff(src_path, os.path.join(ctx.root, files[0]), opts["src"], files[0])
    if live != held_section(read_text(held_path), files[0]):
        raise Content(
            "shape-mismatch",
            f"{files[0]} differs from {opts['src']} other than as the held diff says",
        )


def tree_files(path: str) -> list[str]:
    out = []
    for dirpath, _, names in os.walk(path):
        out.extend(
            os.path.relpath(os.path.join(dirpath, nm), path) for nm in names if nm != ".DS_Store"
        )
    return sorted(out)


def k_tree_src(ctx: Ctx, row: dict[str, str], n: int) -> None:
    if n < 1:
        raise Defect("tree-src needs a floor of at least 1 in expect")
    for rel in (row["scope"], row["needle"]):
        if not rel or os.path.isabs(rel) or ".." in rel.split("/"):
            raise Defect(f"tree path {rel!r} is empty, absolute or climbs out of the root")
    mine = os.path.join(ctx.root, row["scope"])
    theirs = os.path.join(need_source(ctx), row["needle"])
    for label, path in (("port", mine), ("source", theirs)):
        if not os.path.isdir(path):
            raise Defect(f"the {label} tree {path} is not a directory")
    a, b = tree_files(mine), tree_files(theirs)
    if len(a) < n or len(b) < n:
        raise Content("count-mismatch", f"the trees hold {len(a)} and {len(b)} files, floor {n}")
    if a != b:
        gone = sorted(set(b) - set(a))
        extra = sorted(set(a) - set(b))
        raise Content("shape-mismatch", f"file sets differ: missing {gone[:1]}, extra {extra[:1]}")
    for rel in a:
        if not filecmp.cmp(os.path.join(mine, rel), os.path.join(theirs, rel), shallow=False):
            raise Content("shape-mismatch", f"{rel} differs from the source's")


def k_lens_src(ctx: Ctx, row: dict[str, str], n: int) -> None:
    if n != 6:
        raise Defect("lens-src needs expect 6 (the six fixtures)")
    source = need_source(ctx)
    absent = []
    for entry in row["needle"].split(";"):
        created = entry.endswith("+")
        rel = entry[:-1] if created else entry
        if not rel:
            raise Defect("lens-src needle is empty")
        if not os.path.exists(os.path.join(source, rel)):
            if not created:
                raise Defect(f"source path {rel} is absent")
            absent.append(rel)
    resolve_scope(ctx.root, row["scope"])
    if absent:
        raise Content("file-created", f"created by this phase: {', '.join(absent)}")
    helper = os.path.join(source, "scripts", "check-edition-lens.sh")
    try:
        done = subprocess.run(
            ["bash", helper, ctx.edition, ctx.root],
            capture_output=True,
            text=True,
            timeout=LENS_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Defect(f"the lens helper could not run: {exc}") from exc
    if done.returncode == 0:
        return
    if done.returncode == 1:
        bad = [ln for ln in done.stdout.split("\n") if ln.startswith("FAIL")]
        raise Content("needle-absent", f"lens arm(s) failed: {bad[0] if bad else 'see helper'}")
    raise Defect(f"the lens helper exited {done.returncode}")


DISPATCH = {
    "once": k_count,
    "absent": k_count,
    "count": k_count,
    "each-once": k_each_once,
    "terms": k_terms,
    "bullet-last": k_bullet_last,
    "absent-re": k_absent_re,
    "pair": k_pair,
    "gaps": k_gaps,
    "shape": k_shape,
    "moved": k_moved,
    "file-eq": k_file_eq,
    "block-eq": k_block_eq,
    "cmp-src": k_cmp_src,
    "diff-src": k_diff_src,
    "tree-src": k_tree_src,
    "lens-src": k_lens_src,
}


def evaluate(ctx: Ctx, row: dict[str, str]) -> None:
    """Returns None when the row holds; raises Content or Defect."""
    DISPATCH[row["kind"]](ctx, row, int(row["expect"]))


# ---------------------------------------------------------------- table


def parse_table(data: bytes) -> tuple[list[dict[str, str]], list[str]]:
    problems: list[str] = []
    if not data.strip():
        return [], ["the table is empty"]
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return [], ["the table is not UTF-8"]
    lines = [ln for ln in text.replace("\r\n", "\n").split("\n") if ln.strip()]
    if lines[0].split("\t") != list(COLUMNS):
        return [], ["the header is not " + "\t".join(COLUMNS)]
    rows, seen = [], set()
    for no, ln in enumerate(lines[1:], 2):
        cells = ln.split("\t")
        if len(cells) != len(COLUMNS):
            problems.append(f"line {no}: {len(cells)} cells, want {len(COLUMNS)}")
            continue
        row = {col: cells[k] for k, col in enumerate(COLUMNS)}
        problems.extend(row_problems(row, no, seen))
        rows.append(row)
    return rows, problems


def row_problems(row: dict[str, str], no: int, seen: set[str]) -> list[str]:
    out = []
    rid = row["id"]
    if not ID_RE.match(rid):
        out.append(f"line {no}: id {rid!r} is not a plain id")
    if rid.lower() in seen:
        out.append(f"line {no}: duplicate id {rid}")
    seen.add(rid.lower())
    if row["edition"] not in EDITIONS:
        out.append(f"{rid}: unknown edition {row['edition']!r}")
    if row["phase"] not in PHASES:
        out.append(f"{rid}: unknown phase {row['phase']!r}")
    if row["kind"] not in KINDS:
        out.append(f"{rid}: unknown kind {row['kind']!r}")
    if not re.fullmatch(r"[0-9]+", row["expect"]):
        out.append(f"{rid}: expect {row['expect']!r} is not an integer")
    return out


def policy_names(rows: list[dict[str, str]]) -> list[str]:
    names = set()
    for row in rows:
        for cell in (row["needle"], row["row"]):
            names.update(POLICY_REF_RE.findall(cell))
    return sorted(names)


def policy_digest(table: str, rows: list[dict[str, str]]) -> str:
    pdir = os.path.join(os.path.dirname(os.path.dirname(table)), "policy")
    h = hashlib.sha256()
    for name in policy_names(rows):
        path = os.path.join(pdir, name)
        data = read_bytes(path) if os.path.isfile(path) else b"<absent>"
        h.update(name.encode() + b"\0" + data + b"\0")
    return h.hexdigest()


def ids_digest(rows: list[dict[str, str]]) -> str:
    return sha256_bytes(("\n".join(sorted(r["id"] for r in rows)) + "\n").encode())


# ---------------------------------------------------------------- run


def safe(text: str) -> str:
    """A message with every control character escaped (a file name may hold a newline, and a
    line starting `ok ` would then read as a verdict)."""
    return "".join(c if c.isprintable() else repr(c)[1:-1] for c in text)


def usage(msg: str) -> int:
    print(f"check-edition-text.py: {msg}", file=sys.stderr)
    return 2


VALUE_FLAGS = (
    "--edition",
    "--root",
    "--source",
    "--table",
    "--done",
    "--expect-rows",
    "--expect-source-rows",
    "--expect-ids",
    "--expect-table-sha256",
    "--expect-policy-sha256",
    "--expect-reader-sha256",
)


def parse_args(argv: list[str]) -> dict[str, str] | str:
    opts: dict[str, str] = {}
    i = 0
    while i < len(argv):
        flag = argv[i]
        if flag not in VALUE_FLAGS or i + 1 >= len(argv) or flag in opts:
            return f"bad or repeated argument {flag!r}"
        opts[flag] = argv[i + 1]
        i += 2
    return opts


def default_table() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "tests", "parity", "editions.tsv")


def load_rows(table: str, edition: str) -> tuple[list[dict[str, str]], list[dict[str, str]], bytes]:
    if not os.path.isfile(table):
        print(f"FAIL <table>: {safe(table)} is absent")
        raise SystemExit(1)
    data = read_bytes(table)
    rows, problems = parse_table(data)
    if problems:
        for p in problems:
            print(f"FAIL <table>: {safe(p)}")
        raise SystemExit(1)
    return rows, [r for r in rows if r["edition"] == edition], data


def run(opts: dict[str, str]) -> int:
    edition = opts.get("--edition", "")
    if edition not in EDITIONS or "--root" not in opts:
        return usage(
            "--edition <name> and --root <dir> are required; names: " + ", ".join(EDITIONS)
        )
    for flag in ("--expect-rows", "--expect-source-rows"):
        if flag in opts and not opts[flag].isdigit():
            return usage(f"{flag} needs an integer")
    done = None
    if "--done" in opts:
        done = opts["--done"].split()
        if any(not re.fullmatch(r"[0-9a-z]+", d) for d in done):
            return usage("--done takes space-separated phase ids")
    table = os.path.abspath(opts.get("--table", default_table()))
    all_rows, mine, data = load_rows(table, edition)
    if not mine:
        print(f"FAIL <table>: the table holds no row for edition {edition}")
        return 1
    if done is not None:
        legal = {r["phase"] for r in all_rows} - {"0"}
        bad = [d for d in done if d not in legal]
        if bad:
            return usage(f"--done ids not in the table: {' '.join(bad)}")
    root = os.path.abspath(opts["--root"])
    source = os.path.abspath(opts["--source"]) if "--source" in opts else None
    if not os.path.isdir(root) or (source is not None and not os.path.isdir(source)):
        print("FAIL <root>: the root or source is not a directory")
        return 1
    same = source is not None and os.path.realpath(source) == os.path.realpath(root)
    if same and edition != "orchestration":
        return usage("--source is the same directory as --root: a port cannot be its own source")
    ctx = Ctx(edition, root, source, table)
    tally = {"ok": 0, "FAIL": 0, "PENDING": 0, "NEEDS-SOURCE": 0}
    pending: dict[str, int] = {}
    for row in mine:
        report(ctx, row, done, tally, pending)
    src_rows = sum(1 for r in mine if r["kind"] in SRC_KINDS)
    fails = check_expectations(opts, mine, data, all_rows, table, src_rows)
    tally["FAIL"] += fails
    if tally["NEEDS-SOURCE"] and "--expect-source-rows" not in opts:
        print("FAIL <source>: rows need --source and no --expect-source-rows was given")
        tally["FAIL"] += 1
    print(
        f"{edition}: {len(mine)} rows, {tally['ok']} ok, {tally['PENDING']} pending, "
        f"{tally['FAIL']} FAIL, {tally['NEEDS-SOURCE']} need the source"
    )
    if pending:
        order = sorted(pending, key=lambda p: PHASE_ORDER[p])
        print(f"pending: {edition} phases {' '.join(order)} ({sum(pending.values())} rows)")
    if tally["FAIL"]:
        return 1
    return 5 if tally["PENDING"] else 0


def report(
    ctx: Ctx,
    row: dict[str, str],
    done: list[str] | None,
    tally: dict[str, int],
    pending: dict[str, int],
) -> None:
    rid = row["id"]
    if row["kind"] in SRC_KINDS and ctx.source is None:
        print(f"NEEDS-SOURCE {rid}")
        tally["NEEDS-SOURCE"] += 1
        return
    due = row["phase"] == "0" or done is None or row["phase"] in done
    try:
        evaluate(ctx, row)
    except Defect as exc:
        print(f"FAIL {rid}: table defect: {safe(str(exc))}")
        tally["FAIL"] += 1
        return
    except Content as exc:
        if due:
            print(f"FAIL {rid}: {exc.cls}: {safe(exc.detail)}")
            tally["FAIL"] += 1
        else:
            print(f"PENDING {rid}: {exc.cls}")
            tally["PENDING"] += 1
            pending[row["phase"]] = pending.get(row["phase"], 0) + 1
        return
    if due:
        print(f"ok {rid}")
        tally["ok"] += 1
    else:
        print(f"FAIL {rid}: passes before its phase")
        tally["FAIL"] += 1


def check_expectations(
    opts: dict[str, str],
    mine: list[dict[str, str]],
    data: bytes,
    all_rows: list[dict[str, str]],
    table: str,
    src_rows: int,
) -> int:
    got = {
        "--expect-rows": str(len(mine)),
        "--expect-source-rows": str(src_rows),
        "--expect-ids": ids_digest(mine),
        "--expect-table-sha256": sha256_bytes(data),
        "--expect-policy-sha256": policy_digest(table, all_rows),
        "--expect-reader-sha256": sha256_bytes(read_bytes(os.path.abspath(__file__))),
    }
    fails = 0
    for flag, value in got.items():
        if flag in opts and opts[flag] != value:
            print(f"FAIL {flag[2:]}: the table says {value}, the call site pins {opts[flag]}")
            fails += 1
    return fails


def cmd_hashes(argv: list[str]) -> int:
    opts = parse_args(argv)
    if isinstance(opts, str) or set(opts) - {"--edition"} or opts.get("--edition") not in EDITIONS:
        return usage("hashes takes --edition <name>")
    table = default_table()
    all_rows, mine, data = load_rows(table, opts["--edition"])
    print(f"--expect-rows {len(mine)}")
    print(f"--expect-source-rows {sum(1 for r in mine if r['kind'] in SRC_KINDS)}")
    print(f"--expect-ids {ids_digest(mine)}")
    print(f"--expect-table-sha256 {sha256_bytes(data)}")
    print(f"--expect-policy-sha256 {policy_digest(table, all_rows)}")
    print(f"--expect-reader-sha256 {sha256_bytes(read_bytes(os.path.abspath(__file__)))}")
    return 0


# ---------------------------------------------------------------- selftest helpers


def make_row(**kw: str) -> dict[str, str]:
    row = dict.fromkeys(COLUMNS, "")
    row.update({"id": "t", "edition": "codex", "phase": "0", "expect": "1"})
    row.update(kw)
    return row


# ---------------------------------------------------------------- selftest

BULLET = "- **No progress**: stop."
CADENCE = "## Cadence\n\n- **A**: a\n- **On return**: r\n" + BULLET + "\n\nTail.\n"
BASE_PORT = {
    "a.md": "# T\n\n## Sec\nhello world\nhello again\n\n## Other\nbye\n",
    "b.md": "## Sec\n```\n## Sec\n```\nx\n",
    "dup.md": "## Sec\none\n## Sec\ntwo\n",
    "empty.md": "",
    "p1.md": CADENCE,
    "p2.md": CADENCE,
    "bad-before.md": "## Cadence\n\n- **A**: a\n" + BULLET + "\n- **On return**: r\n",
    "bad-trail.md": "## Cadence\n\n- **A**: a\n- **On return**: r\n" + BULLET + " more\n",
    "bad-break.md": "## Cadence\n\n- **A**: a\n- **On return**: r\n\n" + BULLET + "\n",
    "bad-sec.md": "## Cadence\n\n- **A**: a\n- **On return**: r\n\n## What NOT\n\n- x\n"
    + BULLET
    + "\n",
    "bad-none.md": "## Cadence\n\n- **A**: a\n- **On return**: r\n",
    "tbl.md": "## T\n| Tier | A | B |\n|---|---|---|\n| TINY | a | b |\n| LIGHT | a | b |\n"
    "| STANDARD | a | b |\n| HEAVY | a | b |\n",
    "tbl-rag.md": "## T\n| Tier | A | B |\n|---|---|---|\n| TINY | a | b |\n| LIGHT | a |\n",
    "tbl-order.md": "## T\n| Tier | A |\n|---|---|\n| LIGHT | a |\n| TINY | a |\n",
    "rows.md": "## T\n| **xander** | auth, secrets |\n| ian | public API |\n",
    "auth.md": "authorization only\nsecrets\n",
    "gap.md": "TINY and STANDARD and LIGHT\nTINY and STANDARD only\n",
    "sv.md": "xander runs on every phase when that surface is auth\nHEAVY: always\n",
    "sv2.md": "xander runs on every phase when that surface is auth\n",
    "tpl.md": "# Tpl first\nbody\n",
    "host.md": "see `tpl.md`\n",
    "other.md": "# Other\n",
    "skel.md": "# Skel\n",
    "blocks.md": "## F\n```\nA\n```\ntext\n````\nB\n```\ninner\n```\n````\n",
    "cp.txt": "same\n",
    "tr/a.txt": "1\n",
    "tr/b.txt": "2\n",
}
BASE_SOURCE = {
    "cp.txt": "same\n",
    "cp-diff.txt": "other\n",
    "tr/a.txt": "1\n",
    "tr/b.txt": "2\n",
    "tr2/a.txt": "1\n",
    "tr2/b.txt": "3\n",
    "held.diff": "",
}
POLICY = {
    "one.txt": "hello world\n",
    "two.txt": "hello world\nhello again\n",
    "miss.txt": "hello world\nnope\n",
    "emptyp.txt": "\n",
    "terms.txt": "auth\t[Aa]uth([^a-z]|$)\nsecrets\t[Ss]ecrets\n",
    "terms-bad.txt": "x\t[unclosed\n",
    "bullet.txt": BULLET + "\n",
    "variant.re": "HEAVY: always|(run|runs) on every phase\n",
    "mask.txt": "xander runs on every phase when that surface is\n",
    "survivors.tsv": "t-allow\tsv.md\tHEAVY: always\nt-allow\tgap.md\tTINY and STANDARD only\n",
    "skel.txt": "# Skel\n",
    "blk.txt": "A\n",
    "blk2.txt": "B\n```\ninner\n```",
}
TOML_OPEN = 'developer_instructions = """\n## Cadence\n\n- **A**: a\n- **On return**: r\n'
TOML_CLOSE = '\n"""\n'
NOLAST = "## Cadence\n\n- **A**: a\n- **B**: b\n" + BULLET + "\n"
NESTED = "## F\n```markdown\nouter\n```mermaid\ninner\n```\nafter\n```\n## G\nx\n"
LENS_FILES = "scripts/check-edition-lens.sh+;tests/fixtures/lens+"


def lens_source(code: int) -> dict[str, str]:
    return {
        "scripts/check-edition-lens.sh": f"#!/bin/bash\nexit {code}\n",
        "tests/fixtures/lens/a.md": "fixture\n",
    }


def case(
    label: str,
    want: str,
    extra_port: dict[str, str] | None = None,
    extra_source: dict[str, str] | None = None,
    **cells: str,
) -> tuple:
    return (label, want, make_row(**cells), extra_port or {}, extra_source or {})


# fmt: off
def selftest_cases() -> list[tuple]:
    t = "@terms.txt"
    bl = {"kind": "bullet-last", "anchor": "## Cadence", "needle": "@bullet.txt"}
    rx = {"kind": "absent-re", "expect": "0", "needle": "@variant.re"}
    mv = {"kind": "moved", "scope": "tpl.md", "row": "pop=.", "needle": "tpl.md=host.md"}
    sh = {"kind": "shape", "anchor": "## T"}
    fe = {"kind": "file-eq", "expect": "1"}
    be = {"kind": "block-eq", "scope": "blocks.md", "anchor": "## F", "expect": "2"}
    ts = {"kind": "tree-src", "scope": "tr", "expect": "2"}
    ds = {"kind": "diff-src", "scope": "cp.txt"}
    ls = {"kind": "lens-src", "scope": "cp.txt", "expect": "6", "needle": LENS_FILES}
    return [
        case("once present", "ok", kind="once", scope="a.md", anchor="## Sec",
             needle="hello world"),
        case("once outside the section", "content:needle-absent", kind="once", scope="a.md",
             anchor="## Sec", needle="bye"),
        case("once twice", "content:count-mismatch", kind="once", scope="a.md", needle="hello"),
        case("once with expect 2", "defect", kind="once", scope="a.md", expect="2", needle="hello"),
        case("empty needle", "defect", kind="once", scope="a.md", needle=""),
        case("empty needle file", "defect", kind="once", scope="a.md", needle="@emptyp.txt"),
        case("absent anchor", "defect", kind="once", scope="a.md", anchor="## Nope",
             needle="hello"),
        case("absent anchor marked +", "content:anchor-created", kind="once", scope="a.md",
             anchor="## Nope @+", needle="hello"),
        case("scope matches nothing", "defect", kind="once", scope="zz/*.md", needle="hello"),
        case("scope file absent", "defect", kind="once", scope="zz.md", needle="hello"),
        case("scope file absent marked +", "content:file-created", kind="once", scope="zz.md+",
             needle="hello"),
        case("scope climbs out of the root", "defect", kind="once", scope="../a.md",
             needle="hello"),
        case("glob reaching only /fixtures/", "defect",
             {"fixtures/x.md": "hello\n", "q/fixtures/y.md": "hello\n"}, kind="once",
             scope="**/fixtures/*.md", needle="hello"),
        case("explicit /fixtures/ file", "ok", {"q/fixtures/y.md": "hello\n"}, kind="once",
             scope="q/fixtures/y.md", needle="hello"),
        case("duplicate anchor", "defect", kind="once", scope="dup.md", anchor="## Sec",
             needle="one"),
        case("anchor repeated inside a fence counts once", "ok", kind="once", scope="b.md",
             anchor="## Sec", needle="x"),
        case("section ends at the next heading", "ok", kind="absent", scope="a.md", anchor="## Sec",
             expect="0", needle="bye"),
        case("section with a stop level", "ok", {"c.md": "## A\n### B\nz\n## C\n"}, kind="once",
             scope="c.md", anchor="## A @stop=2", needle="z"),
        case("absent but present", "content:stale-present", kind="absent", scope="a.md", expect="0",
             needle="bye"),
        case("count right", "ok", kind="count", scope="a.md", expect="2", needle="hello"),
        case("count wrong", "content:count-mismatch", kind="count", scope="a.md", expect="3",
             needle="hello"),
        case("regex metacharacters are literal", "ok", {"m.md": "a [b] (c) | d …\n"}, kind="once",
             scope="m.md", needle="[b] (c) | d …"),
        case("crlf file", "ok", {"crlf.md": "## Sec\r\nhello\r\n"}, kind="once", scope="crlf.md",
             anchor="## Sec", needle="hello"),
        case("each-once all present", "ok", kind="each-once", scope="a.md", anchor="## Sec",
             expect="2", needle="@two.txt"),
        case("each-once one clause absent", "content:needle-absent", kind="each-once", scope="a.md",
             expect="2", needle="@miss.txt"),
        case("each-once clause twice", "content",
             {"tw.md": "hello world\nhello world\nhello again\n"}, kind="each-once", scope="tw.md",
             expect="2", needle="@two.txt"),
        case("each-once cardinality", "defect", kind="each-once", scope="a.md", expect="3",
             needle="@two.txt"),
        case("each-once literal needle", "defect", kind="each-once", scope="a.md", expect="1",
             needle="hello"),
        case("terms satisfied", "ok", kind="terms", scope="rows.md", row="xander", expect="2",
             needle=t),
        case("terms only in another row", "content", kind="terms", scope="rows.md", row="ian",
             expect="2", needle=t),
        case("auth only as authorization", "content", kind="terms", scope="auth.md", expect="2",
             needle=t),
        case("terms bad pattern", "defect", kind="terms", scope="rows.md", expect="1",
             needle="@terms-bad.txt"),
        case("row selector matches none", "defect", kind="once", scope="rows.md", row="nobody",
             needle="auth"),
        case("line selector", "ok", kind="once", scope="rows.md", row="line:| ian",
             needle="public API"),
        case("bullet-last ok", "ok", row="len=3", expect="2", scope="p*.md", **bl),
        case("bullet before On return", "content", row="len=3", expect="1", scope="bad-before.md",
             **bl),
        case("bullet with trailing text", "content", row="len=3", expect="1", scope="bad-trail.md",
             **bl),
        case("bullet after a blank line", "content", row="len=3", expect="1", scope="bad-break.md",
             **bl),
        case("bullet in another section", "content", row="len=3", expect="1", scope="bad-sec.md",
             **bl),
        case("bullet absent", "content:needle-absent", row="len=3", expect="1", scope="bad-none.md",
             **bl),
        case("bullet list of the wrong length", "content", row="len=4", expect="1", scope="p1.md",
             **bl),
        case("bullet list length per persona", "ok", row="len=4;p1=3", expect="1", scope="p1.md",
             **bl),
        case("bullet roster of the wrong size", "content", row="len=3", expect="3", scope="p*.md",
             **bl),
        case("bullet roster exclusion", "ok", row="len=3;exclude=p2.md", expect="1", scope="p*.md",
             **bl),
        case("same-length fences nested by info string", "ok", {"n.md": NESTED}, kind="once",
             scope="n.md", anchor="## G", needle="x"),
        case("row created by the phase", "content", kind="once", scope="rows.md",
             row="line:| nobody @+", needle="auth"),
        case("bullet after an item that is not On return", "content:shape-mismatch",
             {"nl.md": NOLAST}, row="len=3", expect="1", scope="nl.md", **bl),
        case("tree-src file sets differ", "content:shape-mismatch", {},
             {"tr3/a.txt": "1\n", "tr3/b.txt": "2\n", "tr3/c.txt": "3\n"}, needle="tr3", **ts),
        case("scope climbing out to a file that exists", "defect", kind="once", scope="../s/cp.txt",
             needle="same"),
        case("a clause in a fence is not seen", "content:needle-absent",
             {"h.md": "x\n```\nCLAUSE\n```\n"}, kind="once", scope="h.md", needle="CLAUSE"),
        case("a clause in a fence, @fenced", "ok", {"h.md": "## H\n```\nCLAUSE\n```\n"},
             kind="once", scope="h.md", anchor="## H @fenced", needle="CLAUSE"),
        case("a clause in a comment is not seen", "content:needle-absent",
             {"h.md": "x\n<!-- CLAUSE -->\n"}, kind="once", scope="h.md", needle="CLAUSE"),
        case("a clause in a multi-line comment is not seen", "content:needle-absent",
             {"h.md": "x\n<!--\nCLAUSE\n-->\n"}, kind="once", scope="h.md", needle="CLAUSE"),
        case("a comment heading is not an anchor", "defect", {"h.md": "<!--\n## H\n-->\nCLAUSE\n"},
             kind="once", scope="h.md", anchor="## H", needle="CLAUSE"),
        case("a comment heading does not make the anchor twice", "ok",
             {"h.md": "<!--\n## H\n-->\n## H\nCLAUSE\n"}, kind="once", scope="h.md", anchor="## H",
             needle="CLAUSE"),
        case("absent still sees a fence", "content:stale-present", {"h.md": "```\nSTALE\n```\n"},
             kind="absent", scope="h.md", expect="0", needle="STALE"),
        case("absent still sees a comment", "content:stale-present", {"h.md": "<!-- STALE -->\n"},
             kind="absent", scope="h.md", expect="0", needle="STALE"),
        case("absent-re still sees a comment", "content:stale-present",
             {"h.md": "<!-- HEAVY: always -->\n"}, scope="h.md", **rx),
        case("each-once clause only in a fence", "content:needle-absent",
             {"h.md": "hello world\n```\nhello again\n```\n"}, kind="each-once", scope="h.md",
             expect="2", needle="@two.txt"),
        case("terms only in a comment", "content:needle-absent",
             {"h.md": "<!-- auth secrets -->\nx\n"}, kind="terms", scope="h.md", expect="2",
             needle=t),
        case("pair only in a fence", "content:needle-absent", {"h.md": "```\nhello\n```\n"},
             kind="pair", scope="h.md", expect="1", needle="hello"),
        case("exact line", "ok", {"h.md": "- **LIGHT**: run\n"}, kind="once", scope="h.md",
             row="exact", needle="- **LIGHT**: run"),
        case("exact line, a qualifier after it", "content:needle-absent",
             {"h.md": "- **LIGHT**: runs only when asked\n"}, kind="once", scope="h.md",
             row="exact", needle="- **LIGHT**: run"),
        case("table row by first cell, not a prefix", "defect", kind="once", scope="rows.md",
             row="xan", needle="auth"),
        case("symlink in scope", "defect", {"ln.md": "SYMLINK:a.md"}, kind="once", scope="ln.md",
             needle="hello"),
        case("symlink resolving outside the root", "defect", {"ln.md": "SYMLINK:../s/cp.txt"},
             kind="once", scope="ln.md", needle="same"),
        case("a file over the size cap", "defect", {"big.md": "x" * (MAX_BYTES + 1)}, kind="once",
             scope="big.md", needle="x"),
        case("bullet inside a TOML comment", "content",
             {"c.toml": TOML_OPEN + "# " + BULLET + TOML_CLOSE}, row="len=3", expect="1",
             scope="c.toml", **bl),
        case("bullet in a TOML string", "ok", {"c.toml": TOML_OPEN + BULLET + TOML_CLOSE},
             row="len=3", expect="1", scope="c.toml", **bl),
        case("absent-re survivor allowed", "ok", id="t-allow", scope="sv.md",
             row="mask=@mask.txt;allow=@survivors.tsv", **rx),
        case("absent-re stale line", "content", scope="sv.md", row="mask=@mask.txt", **rx),
        case("absent-re only the masked sentence", "ok", scope="sv2.md", row="mask=@mask.txt",
             **rx),
        case("absent-re unmasked", "content", scope="sv2.md", **rx),
        case("pair in every file", "ok", kind="pair", scope="a.md;b.md", expect="2",
             needle="## Sec"),
        case("pair one file lacks it", "content", kind="pair", scope="a.md;b.md", expect="2",
             needle="hello"),
        case("gaps clean", "ok", kind="gaps", scope="tbl.md", expect="0"),
        case("gaps line without LIGHT", "content", kind="gaps", scope="gap.md", expect="0"),
        case("gaps survivor allowed", "ok", id="t-allow", kind="gaps", scope="gap.md", expect="0",
             row="allow=@survivors.tsv"),
        case("shape ok", "ok", scope="tbl.md", expect="4",
             needle="header=A;first=TINY,LIGHT,STANDARD,HEAVY", **sh),
        case("shape ragged", "content:shape-mismatch", scope="tbl-rag.md", expect="2",
             needle="header=A", **sh),
        case("shape out of order", "content", scope="tbl-order.md", expect="2",
             needle="first=TINY,LIGHT", **sh),
        case("shape header lacks LIGHT", "content", scope="tbl.md", expect="4",
             needle="header=LIGHT", **sh),
        case("shape no table in the span", "defect", scope="a.md", anchor="## Sec", expect="1",
             needle="header=A", kind="shape"),
        case("moved ok", "ok", expect="1", **mv),
        case("moved first line twice", "content", {"twin.md": "# Tpl first\n"}, expect="1", **mv),
        case("moved uncited", "content", expect="1", **{**mv, "needle": "tpl.md=other.md"}),
        case("moved template empty", "content", expect="1",
             **{**mv, "scope": "empty.md", "needle": "empty.md=host.md"}),
        case("moved template created by the phase", "content", expect="1",
             **{**mv, "scope": "nope.md+"}),
        case("moved inline once", "ok", kind="moved", scope="a.md", row="inline=1", expect="1",
             needle="bye"),
        case("moved inline twice", "content", kind="moved", scope="a.md", row="inline=1",
             expect="1", needle="hello"),
        case("file-eq equal", "ok", scope="skel.md", needle="@skel.txt", **fe),
        case("file-eq differs", "content", scope="a.md", needle="@skel.txt", **fe),
        case("file-eq empty port file", "content", scope="empty.md", needle="@skel.txt", **fe),
        case("file-eq empty policy file", "defect", scope="skel.md", needle="@emptyp.txt", **fe),
        case("block-eq ok", "ok", row="block=1", needle="@blk.txt", **be),
        case("block-eq nested fence is content", "ok", row="block=2", needle="@blk2.txt", **be),
        case("block-eq wrong count", "content", row="block=1", needle="@blk.txt",
             **{**be, "expect": "3"}),
        case("block-eq wrong content", "content", row="block=1", needle="@skel.txt", **be),
        case("cmp-src equal", "ok", kind="cmp-src", scope="cp.txt", expect="1", needle="cp.txt"),
        case("cmp-src differs", "content", kind="cmp-src", scope="cp.txt", expect="1",
             needle="cp-diff.txt"),
        case("cmp-src port file created by the phase", "content", kind="cmp-src", scope="new.txt+",
             expect="1", needle="cp.txt"),
        case("tree-src equal", "ok", needle="tr", **ts),
        case("tree-src ignores .DS_Store", "ok", {"tr/.DS_Store": "x"}, needle="tr", **ts),
        case("tree-src one byte", "content", needle="tr2", **ts),
        case("tree-src floor", "content:count-mismatch", needle="tr", **{**ts, "expect": "3"}),
        case("tree-src missing tree", "defect", needle="tr", **{**ts, "scope": "nodir"}),
        case("diff-src held diff not written", "content", needle="src=cp.txt;held=held-absent.diff",
             **ds),
        case("diff-src no difference, no section", "ok", expect="1",
             needle="src=cp.txt;held=held.diff", **ds),
        case("diff-src difference the held diff lacks", "content", expect="1",
             needle="src=cp-diff.txt;held=held.diff", **ds),
        case("diff-src difference held", "ok", None, {"held-ok.diff": HELD_OK}, expect="1",
             needle="src=cp-diff.txt;held=held-ok.diff", **ds),
        case("lens-src helper not written", "content", **ls),
        case("lens-src six arms pass", "ok", None, lens_source(0), **ls),
        case("lens-src an arm fails", "content", None, lens_source(1), **ls),
        case("lens-src helper cannot run", "defect", None, lens_source(2), **ls),
             ]

# fmt: on

HELD_OK = "--- a/cp-diff.txt\n+++ b/cp.txt\n@@ -1 +1 @@\n-other\n+same"


def write_tree(base: str, files: dict[str, str]) -> None:
    for rel, content in files.items():
        path = os.path.join(base, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if content.startswith("SYMLINK:"):
            os.symlink(content[8:], path)
            continue
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(content)


def outcome(ctx: Ctx, row: dict[str, str]) -> str:
    try:
        evaluate(ctx, row)
    except Content as exc:
        return f"content:{exc.cls}"
    except Defect:
        return "defect"
    return "ok"


def selftest() -> int:
    flagged = clean = skipped = 0
    bad: list[str] = []
    try:
        import tomllib  # noqa: F401

        have_toml = True
    except ImportError:
        have_toml = False
    for label, want, row, extra_port, extra_source in selftest_cases():
        if row["scope"].endswith(".toml") and not have_toml:
            skipped += 1
            continue
        with tempfile.TemporaryDirectory() as tmp:
            port, source = os.path.join(tmp, "r"), os.path.join(tmp, "s")
            write_tree(port, {**BASE_PORT, **extra_port})
            write_tree(source, {**BASE_SOURCE, **extra_source})
            write_tree(os.path.join(tmp, "policy"), POLICY)
            ctx = Ctx(row["edition"], port, source, os.path.join(tmp, "parity", "t.tsv"))
            got = outcome(ctx, row)
        if want != "ok" and (got == want or (want == "content" and got.startswith("content:"))):
            flagged += 1
        elif want == "ok" and got == "ok":
            clean += 1
        else:
            bad.append(f"{label}: wanted {want}, got {got}")
    if bad:
        for b in bad:
            print(f"selftest FAIL {b}")
        return 1
    note = f" ({skipped} TOML inputs not run: tomllib is Python 3.11+)" if skipped else ""
    print(f"selftest ok: {flagged} planted inputs flagged, {clean} clean inputs accepted{note}")
    return 0


def main(argv: list[str]) -> int:
    if argv and argv[0] == "selftest":
        return selftest() if len(argv) == 1 else usage("selftest takes no arguments")
    if argv and argv[0] == "hashes":
        return cmd_hashes(argv[1:])
    opts = parse_args(argv)
    if isinstance(opts, str):
        return usage(opts)
    try:
        return run(opts)
    except Defect as exc:
        print(f"FAIL <input>: {safe(str(exc))}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
