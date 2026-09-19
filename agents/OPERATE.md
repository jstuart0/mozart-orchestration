## OPERATE pipeline

For changing or debugging a **live system** directly — installs, config changes, infra mutations, hands-on debugging of running Kubernetes / hosts / storage / databases / services. The artifact is a state change to running infrastructure, not a git diff. Verification is empirical (curl, logs, `get`, `top`), not CI. Rollback is a recorded command against a snapshot, not `git revert`. That trio — no diff, empirical gate, snapshot rollback — is why OPERATE is a distinct shape and not a DELIVER tier: every DELIVER gate (codex-on-diff, valerie-against-plan, per-phase test runs) assumes a reviewable diff and a test suite that OPERATE work doesn't have.

**Use the DELIVER-vs-OPERATE boundary test at intake.** If the change reaches the system through a git commit + CI/Argo/release pipeline, it's DELIVER (otto reviews the manifest, jackson writes it, the pipeline deploys). If it lands straight on the running system (`kubectl apply`, `helm upgrade`, `apt install`, an in-place config edit, a service restart), it's OPERATE. When a change *could* go either way, prefer the GitOps/DELIVER path for anything that has one; OPERATE is for direct changes, installs, and live debugging with no repo in the loop.

hank is the only agent that mutates live state. otto plans and reviews; dick investigates; xander reviews the security surface; scott documents — all read-only on the live system.

### Modes (detected at intake)
- **install** — bring up something new on the cluster/host (a package, a service, a Helm release, a new manifest set)
- **config-change** — modify a setting on a running system (a ConfigMap, an env var, a Helm value, an app config file, a scaling change)
- **infra-debug** — figure out why a running system is misbehaving and fix it (crashloop, failed rollout, storage pressure, networking). Pairs with DIAGNOSE: investigate read-only first, then apply the fix under the loop
- **migration** — a stateful or ordered change (storage, DB schema on a live instance, a resource that must be recreated). Always HEAVY

### Tiers (OPERATE)
| Tier | When | Gate adjustments |
|---|---|---|
| **TINY** | A single, obviously reversible change on a non-stateful resource (restart a pod, apply a one-line ConfigMap edit with a clean server-side dry-run) | hank runs the full loop (verify → dry-run → snapshot → apply → verify → record) but skips otto's separate change-plan stage and the xander/codex pre-flight review. The loop is never skipped — even TINY takes a snapshot |
| **STANDARD** | Default. Multi-step changes, installs, most config changes | Full pipeline below |
| **HEAVY** | Anything touching storage (Ceph, PVs), RBAC, secrets, a live DB schema, production-stateful workloads, or any resource-recreation / immutable-field change | STANDARD + mandatory xander at the pre-flight gate + mandatory otto immutable-field / server-side-dry-run verification + **ian for code-side ramifications when the change touches a code-consumed resource** + codex on the change plan. Irreversible steps require explicit user sign-off before apply |

When unsure between STANDARD and HEAVY: choose HEAVY. On live infrastructure the cost of an extra dry-run is seconds; the cost of an un-snapshotted storage mutation is a rebuild.

### 1. Intake + context pin
- Restate the change in one sentence — what system, what change, why now
- **Pin the target from both sides**: what the consuming repo documents and what a live command observes — the cluster context, the host name, the database the connection actually reaches, or the cloud account and region from an identity call against the expected profile. Record both as a `fact` conductor row linked to gate `1`; that row is the reference every mutating command is checked against. A mismatch stops the campaign; neither side wins by default
- Classify mode (install / config-change / infra-debug / migration) and tier (TINY / STANDARD / HEAVY)
- **In install / upgrade mode, resolve the version before planning** — query the upstream project's current stable release and what the intended install source (chart, package, image) would actually land, and surface both plus the gap. Chart and distro defaults lag upstream routinely; a fresh install landing a major version behind is the failure this check exists to prevent. A major-version gap goes to the user as a decision (take current / stay back with a stated reason) before otto plans against a version
- Run the **long-running drift sanity check** (the same one in the DELIVER pre-flight gates — node pressure, Failed-pod count, Argo OutOfSync). Surface drift before you change anything on top of it
- **Ask: report/plan only, or plan-then-apply?** For infra-debug, default to "investigate first, decide after findings" (DIAGNOSE → OPERATE)
- Confirm the change has a rollback story *in principle* before planning. If it's genuinely irreversible (destructive DDL, PV deletion), say so now — the user decides whether to proceed before any work
- Create the state file (`Status: in-progress`, `Flow: OPERATE-FULL` or `OPERATE-PLAN-ONLY`) and the flow sketch (Shape: OPERATE) in `active/` per the *Directory convention*. Resolve the ticket per the Ticket lifecycle (an OPERATE change that mutates production is commit-equivalent — it gets a ticket unless the stanza is `system: none`)

### 2. Recon (infra-debug / migration modes)
- For infra-debug: brief **dick** to investigate read-only (logs, events, `describe`, `--previous`, config dumps) and **otto** to reason about the manifests/charts. Produce a root-cause + a proposed change. Skip for clean install / config-change modes where there's nothing to diagnose
- For migration: otto verifies which fields are immutable on the existing live resources and whether the change needs resource recreation (his immutable-field discipline) — this shapes the change plan's rollback and ordering

### 3. Change plan (otto)
- **otto authors the change plan** — he's the infra planner here, not just a reviewer. The plan is ops-shaped, not code-shaped:
  - the **exact commands**, in order, with the pinned target on each
  - the **dry-run** command for each mutating step (server-side for k8s)
  - the **snapshot step**: what to capture and where to store it, for every resource that changes
  - the **rollback procedure**: the exact command(s) to restore from the snapshot
  - the **blast radius / ramifications** (a required, first-class section — not a one-liner): every consumer of the thing being changed, what degrades or breaks *during* the change (not just if it fails), whether the change causes downtime or a restart of dependents, deployment/restart ordering, and what recovers automatically vs. needs a manual step. "What depends on this ConfigMap/Secret/Service/endpoint, and what happens to each while it's mid-change?"
  - **for install / upgrade modes, the version decision** (see otto's *Version currency* and hank's step 0): the resolved upstream latest stable, the version this install path actually lands, the gap between them, and the pin with its reason. A plan that names a version without saying where the number came from is incomplete — send it back
  - the **mutation manifest** for each mutating step, as the Operate-mode rules define it — including its `ignore:` list of literal field paths and every secret-bearing value as `<redacted>`
- **On HEAVY OPERATE, when the change touches a resource that code consumes** — a shared ConfigMap, a Secret, a Service contract, an endpoint, an env var read by app code — mozart runs **ian** to trace the *code-side* consumers and risk-rank them, the same ripple analysis he does for DELIVER. otto owns the infra-side blast radius (what k8s resources depend on it, ordering); ian owns the code-side (what app code reads it and breaks). This pairing is the ramifications analysis for a live change
- The plan lives at `.mozart/plans/active/<slug>.md`. On TINY, hank composes a minimal version inline instead of a separate otto stage

### 4. Pre-flight gate (hank + xander/codex on HEAVY)
- **hank** runs every dry-run in the plan and takes every snapshot, recording snapshot paths and rollback commands into the state file's **Change ledger — before applying anything.** A failed dry-run, an unexpected diff, an immutable-field `Forbidden`, or a snapshot that can't be taken is a **hard stop** back to otto/the user — not a warning to push through
- **HEAVY**: **xander** reviews the security surface of the change (RBAC grants, secret exposure, network policy, new public surface); **otto** confirms the server-side dry-run is clean against the *actual live resources*; **codex** reviews the change plan (commands + rollback + ordering). Any BLOCK stops the apply
- The gate's output is a go/no-go. No apply happens until the snapshots exist and the dry-runs are clean

### 5. Apply (hank)
- hank executes **one variable per mutation**: each step changes what its manifest names and nothing else, and hank checks the read-back against the manifest before the next step (see Operate-mode rules). A fix proposed mid-apply — by you or by hank — gets its own manifest before it runs. No batch-and-check-at-the-end
- Any unexpected result mid-sequence stops the apply; hank surfaces it and, if the system is now in an inconsistent state, applies the recorded rollback rather than pressing forward

### 6. Verify (hank)
- **Empirical, observed-not-expected.** Curl the endpoint and read the status; `get` the resources and confirm Ready; read the logs; check whatever the change was supposed to affect. hank reports what he *observed*, with the evidence — never "it should work now"
- Surfaces he can't verify (a UI flow, an external integration) are called out explicitly as unverified, not assumed healthy
- Fill in the Change ledger's observed-verification cell

### 7. Record (scott)
- **scott** writes/updates the runbook and the rollback record into the repo docs and/or the configured wiki — what changed, on what target, how it was verified, and the exact rollback command + snapshot location. On TINY, hank's return summary carries this and scott is skipped
- Transition the ticket to its terminal state; set `Status: complete`; move the state file, flow sketch, and plan from `active/` to `finished/` per the *Directory convention*

### Decision point (PLAN-ONLY / OPERATE-PLAN-ONLY)
If the user asked for a change plan without execution, stop after stage 3: otto's change plan (commands + snapshots + rollback + blast radius) is the deliverable. The user reviews and decides whether to apply. Re-enter at stage 4 when they say go.

### Operate-mode rules
- **Never mutate without a snapshot and a recorded rollback command.** The one rule the whole shape exists to enforce. A TINY change is not an exception
- **Resolve versions, never recall them.** Every install or upgrade — including a TINY one-liner and every passthrough "just install X" — states the resolved upstream latest stable, what the install path actually lands, and the gap, before it runs. Chart/package defaults lag upstream by months or a major version as a matter of course; accepting one silently is how a fresh install lands a year out of date. A major-version gap without a stated reason is a stop, not a default
- **Server-side dry-run for Kubernetes, always.** `--dry-run=server`, not client — server-side is what catches immutable-field and admission-webhook failures
- **Pin the target from both sides — documented and live-observed — and check every mutating command against it.** Explicit context + namespace (or host + instance). A context mismatch is a stop, never a silent switch-and-proceed
- **Observed, not expected.** Every "it works" carries the check behind it. This is your CLAUDE.md Rule 1 as a gate
- **Don't debug and mutate blind.** infra-debug investigates read-only first (dick + otto); mutations to test a hypothesis still go through the full loop
- **Irreversible or out-of-authority steps escalate before apply.** PV deletion, destructive DDL, storage operations without a clean restore — user sign-off first
- **Prefer GitOps when it exists.** If the change has a git/CI/Argo path, that's DELIVER — route there instead of applying directly. OPERATE is for what genuinely has no repo in the loop
- **HEAVY on anything stateful.** Storage, RBAC, secrets, live DB schema, resource recreation — full pre-flight gate, no shortcuts
- **One variable per mutation, with a mutation manifest.** Each step changes one field, or a set of fields that must move together with a `coupling:` rationale; a create or install is one entry, `created: <resource>` with its source digest, a multi-resource apply of pure creates is one step, and a modification bundled into an install is still its own entry. Each entry records field, old value, and new value. A secret-bearing value is always `<redacted>` with only its key name recorded; a hash is allowed only for generated high-entropy material (keys, tokens of at least 128 bits), and never a length. hank's Apply step defines the read-back check and the `ignore:` list of literal field paths it may skip. A dry-run is not this control

