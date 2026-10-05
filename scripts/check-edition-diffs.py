#!/usr/bin/env python3
"""check-edition-diffs.py - writes the held template diffs (source-only; never copied to a port).

The reader's `diff-src` kind compares the live difflib diff of a port template against the
source's template with a diff held in this repo. This script writes that held file, using the
reader's own `live_diff` so the format cannot drift from what the reader compares:

  check-edition-diffs.py --edition copilot|local --root <port checkout> [--out <path>]

It writes tests/parity/templates-<edition>.diff (or --out; `-` prints) with one chunk per
template that differs (STATE, FLOW, REPORT, in that order); a template identical to the
source's has no chunk. Phases 3 and 5 run it; V36 checks every changed line of the result
against tests/parity/templates-allow.re and the named label members.

Exit: 0 written; 2 a bad command line, a missing port template or a missing source template.
"""

from __future__ import annotations

import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.dirname(HERE)
TEMPLATES = ("STATE", "FLOW", "REPORT")
PORT_DIR = {
    "copilot": ".github/mozart/manual",
    "local": "src/mozart_local/bundle/manual",
}
FLAGS = ("--edition", "--root", "--out", "--source")


def load_reader():
    spec = importlib.util.spec_from_file_location(
        "check_edition_text", os.path.join(HERE, "check-edition-text.py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def chunks(reader, edition: str, root: str, source: str) -> list[str]:
    out = []
    for name in TEMPLATES:
        src_rel = f"agents/TEMPLATE-{name}.md"
        port_rel = f"{PORT_DIR[edition]}/TEMPLATE-{name}.md"
        src_path, port_path = os.path.join(source, src_rel), os.path.join(root, port_rel)
        for label, path in ((src_rel, src_path), (port_rel, port_path)):
            if not os.path.isfile(path):
                raise FileNotFoundError(f"{label} is absent ({path})")
        live = reader.live_diff(src_path, port_path, src_rel, port_rel)
        if live:
            out.append(live)
    return out


def parse(argv: list[str]) -> dict[str, str] | None:
    opts: dict[str, str] = {}
    i = 0
    while i < len(argv):
        if argv[i] not in FLAGS or i + 1 >= len(argv) or argv[i] in opts:
            return None
        opts[argv[i]] = argv[i + 1]
        i += 2
    return opts


def main(argv: list[str]) -> int:
    opts = parse(argv)
    if opts is None or opts.get("--edition") not in PORT_DIR or "--root" not in opts:
        print(
            "check-edition-diffs.py: --edition copilot|local and --root <dir> are required",
            file=sys.stderr,
        )
        return 2
    edition = opts["--edition"]
    source = os.path.abspath(opts.get("--source", SOURCE))
    out = opts.get("--out", os.path.join(source, "tests", "parity", f"templates-{edition}.diff"))
    try:
        parts = chunks(load_reader(), edition, os.path.abspath(opts["--root"]), source)
    except OSError as exc:
        print(f"check-edition-diffs.py: {exc}", file=sys.stderr)
        return 2
    text = "\n".join(parts) + "\n" if parts else ""
    if out == "-":
        sys.stdout.write(text)
        return 0
    with open(out, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    lines = [ln for ln in text.split("\n") if ln[:1] in ("+", "-")]
    changed = sum(1 for ln in lines if not ln.startswith(("+++ ", "--- ")))
    print(f"wrote {out}: {len(parts)} chunk(s), {changed} changed line(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
