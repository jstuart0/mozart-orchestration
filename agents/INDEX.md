# The bundled manual — routing table

`agents/mozart.md` is the persona: everything mozart must act on before it has read
any other file. Stage-time procedure lives here, in the bundled manual, and the
persona names each file with the trigger that sends you to it (D2).

**This table grows one row per carve phase.** A row appears in the same commit as
the file it names, so the table never promises a file that does not exist.

| File | What's in it | Read when |
|---|---|---|
| `AUDIT.md` | The AUDIT pipeline — review against a goal | the work shape is AUDIT |
| `CONTEXT-BUDGET.md` | Subagent context budget for large-CLAUDE.md repos | before briefing any subagent in a repo with a large CLAUDE.md |
| `COUNTERPOINT.md` | External tool execution — the kill-timer discipline, success detection, and what a tool failure is | before any sebastian/codex dispatch at stage 5 or 9 |
| `DIAGNOSE.md` | The DIAGNOSE pipeline — investigate a specific failure | the work shape is DIAGNOSE |
| `INCIDENT.md` | The INCIDENT pipeline — respond to a live outage | the work shape is INCIDENT (service is down *right now*) |
| `EVAL.md` | The EVAL pipeline — mozart evaluating mozart | the work shape is EVAL |
| `INTAKE.md` | The full stage-1 intake checklist, the shape-boundary tests, and passthrough routing | **boot read** — before step 2 of intake, every run, every shape |
| `OPERATE.md` | The OPERATE pipeline — change or debug a live system | the work shape is OPERATE |
| `STATE.md` | State persistence (crash-resume) and the pipeline flow sketch | before creating or updating any state file, and before narrating a stage transition |

## Adjacent, not members

`agents/PIPELINE.md` and `agents/LEARNINGS.md` sit alongside the manual and are **not
part of it**. PIPELINE.md is the *specialists'* reference — the 17-agent roster and
stage placement, cited by ~20 personas. LEARNINGS.md is the field-note protocol.
Neither is a mozart routing target, and neither is covered by this table.

Where PIPELINE.md and the manual overlap, **PIPELINE.md summarizes and the manual is
authoritative.** Without a declared direction of authority, future drift has no
correct side and both documents get edited independently.

## `agents/EVAL.md` is not `docs/EVAL.md`

Two different files, and the names are one character apart in practice:

- **`agents/EVAL.md`** — the EVAL **pipeline procedure**. The six stages mozart runs.
  This is a manual member and it is what the persona points at.
- **`docs/EVAL.md`** — the EVAL **ledger schema and report format**. Where eval
  artifacts live, the `ledger.jsonl` shape, the report template. A reference
  document, not a manual member.

copilot hit this collision first and paid for it. Cite the full path, never the bare
filename, whenever both could be meant.
