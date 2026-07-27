# INTEGRATION.md

Mozart is pluggable for five surfaces: **ticketing**, **documentation**, **code retrieval**, **worktrees**, and **pull requests**. You configure them by adding stanzas to your repo's `CLAUDE.md`. Mozart and his specialists read those stanzas at intake; if a stanza is missing, the corresponding behavior is skipped or falls back to a sensible default.

This file is the contract. Copy the appropriate stanza into your repo's `CLAUDE.md`, fill in the values, and the plugin adapts.

---

## 1. Ticketing

Mozart's lifecycle includes ticket creation, state transitions (e.g., when work starts, when it's in review, when it's verified), comments after each phase commit, and ticket closure on signoff. The lifecycle is system-agnostic; only the *system, project, states, and authentication* vary.

**Where to put it:** in your repo's `CLAUDE.md`, add a `## Ticketing` section.

**If you don't include this stanza, mozart skips all ticket steps.** The pipeline still works — you just won't get tickets.

### Common fields (all systems)

```markdown
## Ticketing

system: <plane | linear | jira | github | none>
project: <project id, repo slug, board id, etc. — see per-system templates below>

states:
  open:           <state name when ticket is filed>
  in_progress:    <state name when implementation starts>
  in_review:      <state name when ready for human review>
  verified:       <state name when valerie signs off>
  investigating:  <state name when dick is investigating — optional, defaults to "open">
  cancelled:      <state name for won't-fix / superseded — optional, defaults to "verified">

auth:
  <how to retrieve the API token — environment variable, kubectl secret, gh, etc.>

api_base: <https://... or n/a for github>
```

Below are filled-in templates per system. Pick one and adapt.

### Plane

```markdown
## Ticketing

system: plane
project: <plane-project-id>
workspace: <workspace-slug>
api_base: https://plane.your-domain.example

states:
  open: Backlog
  in_progress: In Progress
  in_review: In Review
  verified: Done
  investigating: Investigating
  cancelled: Won't Fix

auth:
  # Recommended: store in a secret manager and retrieve with a one-liner
  # Example shape — substitute your own secret store / namespace / secret name
  command: <your secret-fetch command, e.g., kubectl -n <ns> get secret <secret-name> -o jsonpath='{.data.api-token}' | base64 -d>
  # Or, if using env: PLANE_API_TOKEN
```

### Linear

```markdown
## Ticketing

system: linear
project: <linear-project-or-team-id>
team: <team-key, e.g., ENG>
api_base: https://api.linear.app/graphql

states:
  open: Backlog
  in_progress: In Progress
  in_review: In Review
  verified: Done
  investigating: Triage
  cancelled: Cancelled

auth:
  env: LINEAR_API_KEY
  # Personal API key from https://linear.app/settings/api
```

### Jira

```markdown
## Ticketing

system: jira
project: <PROJECT-KEY>
api_base: https://your-domain.atlassian.net

states:
  open: To Do
  in_progress: In Progress
  in_review: In Review
  verified: Done
  investigating: Investigating
  cancelled: Won't Do

auth:
  env_user: JIRA_USER          # email
  env_token: JIRA_API_TOKEN    # https://id.atlassian.com/manage-profile/security/api-tokens
```

### GitHub Issues

```markdown
## Ticketing

system: github
project: <owner>/<repo>

states:
  # GitHub issues only have open/closed; mozart maps internal states via labels
  open: open
  in_progress: open + label:in-progress
  in_review: open + label:in-review
  verified: closed
  investigating: open + label:investigating
  cancelled: closed + label:wontfix

auth:
  command: gh auth token
```

### None

```markdown
## Ticketing

system: none
```

Mozart will skip every ticket step. Plans, state files, and flow sketches still work as normal.

---

## 2. Documentation surfaces

Scott (the technical writer agent) maintains documentation across multiple surfaces. The defaults are sensible — but if you publish to an external wiki (Wiki.js, Notion, Confluence) you'll want to configure it.

**Where to put it:** in your repo's `CLAUDE.md`, add a `## Documentation surfaces` section.

**If you don't include this stanza, scott edits in-repo docs only** (`README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/`) and the per-repo GitHub wiki if it exists.

### Common fields

```markdown
## Documentation surfaces

in_repo:
  - README.md
  - CHANGELOG.md
  - CONTRIBUTING.md
  - docs/

github_wiki: <enabled | disabled>   # the per-repo GitHub wiki (.wiki.git)

external_wiki:
  system: <wikijs | notion | confluence | none>
  base_url: <https://wiki.your-domain.example>
  api: <graphql | rest>
  auth:
    <how to retrieve the API key>
  categories:
    runbooks: <path or page-path on the wiki>
    decisions: <path or page-path on the wiki>
    post_mortems: <path or page-path on the wiki>
    architecture: <path or page-path on the wiki>
```

### Wiki.js example

```markdown
## Documentation surfaces

in_repo:
  - README.md
  - CHANGELOG.md
  - docs/

github_wiki: enabled

external_wiki:
  system: wikijs
  base_url: https://wiki.your-domain.example
  api: graphql
  graphql_endpoint: https://wiki.your-domain.example/graphql
  auth:
    # Example shape — substitute your own secret store / namespace / secret name
    command: <your secret-fetch command, e.g., kubectl -n <ns> get secret <secret-name> -o jsonpath='{.data.api-key}' | base64 -d>
  categories:
    runbooks: /infrastructure/runbooks
    decisions: /infrastructure/decisions
    post_mortems: /infrastructure/post-mortems
    architecture: /infrastructure/architecture
```

### Notion example

```markdown
## Documentation surfaces

in_repo:
  - README.md
  - CHANGELOG.md

github_wiki: disabled

external_wiki:
  system: notion
  base_url: https://www.notion.so/your-workspace
  api: rest
  auth:
    env: NOTION_API_KEY
  categories:
    runbooks: <database-id>
    decisions: <database-id>
    post_mortems: <database-id>
    architecture: <database-id>
```

### None (in-repo only)

```markdown
## Documentation surfaces

in_repo:
  - README.md
  - CHANGELOG.md
  - docs/

github_wiki: disabled
external_wiki:
  system: none
```

---

## 3. Code retrieval (optional)

Every code-reading agent carries a **"Code retrieval: prefer a code-aware index"** gate. The gate is product-neutral: if the consuming repo declares a code-aware retrieval tool, agents route source-code reads through it (symbol search, file outlines, symbol-source fetch, reference/call-hierarchy lookups) ahead of `Grep`/`Read`, falling back to native search only for non-code files, byte-exact pre-`Edit` reads, tiny known-offset reads, or plan-mandated greps. Code-aware indexes typically cut retrieval token usage by 80-95% on source.

**If you don't configure one, nothing changes** — agents use native `Read`/`Grep`/`Glob`.

**To enable it**, do both:

1. **Declare the tool** in your repo's `CLAUDE.md` so agents know it exists and is authoritative:

   ```markdown
   ## Code retrieval

   This repo is indexed by a code-aware retrieval tool: <tool name>.
   Prefer it over raw Grep/Read for source files. Resolve the repo at
   session start; if indexed, it is the first-choice retrieval tool.
   ```

2. **Grant the tool to the agents.** A subagent can only call tools in its `tools:` frontmatter allow-list. The shipped agents intentionally do **not** list any MCP server (the plugin stays tool-agnostic). To wire one in, append its tool pattern to the `tools:` line of each code-reading agent in your install — e.g. `, mcp__<server>__*`. Agents whose `tools:` omits the MCP can't use it regardless of the `CLAUDE.md` declaration.

**Reference implementation:** [`jcodemunch`](https://github.com) — a tree-sitter-indexed MCP server exposing `resolve_repo`, `search_symbols`, `get_file_outline`, `get_symbol_source`, `find_references`, `get_call_hierarchy`, `find_importers`, `get_dependency_graph`. Wiring it in means adding `mcp__jcodemunch__*` to each agent's `tools:` line and the `## Code retrieval` stanza above. Any LSP, IDE symbol index, or AST-backed MCP that offers equivalent operations works the same way.

---

## 4. Worktrees (stanza optional)

Mozart cuts a git worktree for every code-changing campaign at intake — this happens whether or not you declare anything; only the *configuration* is optional. **If you declare nothing, the default applies**: a sibling directory `../<repo>-worktrees/<slug>`, branch `campaign/<slug>`, cut from the repo's documented base branch (falling back to the current branch when none is declared — mozart surfaces the branch it's cutting from if it looks unexpected).

Declare a `## Worktrees` stanza when your repo has its own convention — a different location, a base branch that isn't what's checked out, a branch-naming scheme tied to your ticketing system, or a setup script that must run:

```markdown
## Worktrees

- root: ../myrepo-worktrees        # or ~/wt/myrepo, .worktrees/, etc.
- base branch: deploy/staging      # cut campaign branches from this, not from HEAD
- branch pattern: campaign/<slug>  # or ENG-<ticket>-<slug>, feature/<slug>, ...
- setup: ./hack/create_worktree.sh # optional; run instead of raw `git worktree add`
- enabled: true                    # false = never cut one; work in the main checkout
```

Every field is optional; omitted fields fall back to the default. `enabled: false` turns the behavior off entirely for repos where a worktree is the wrong unit of work (a single-branch deploy repo, a repo whose build can't run outside its original path).

**Artifacts never move into the worktree.** `.mozart/` stays at the root of the canonical checkout regardless of this stanza — that's what makes a single `ls .mozart/plans/active/*.state.md` a complete view of in-flight campaigns.

---

## 5. Pull requests (stanza optional)

Mozart does not push, and does not open pull requests, unless you declare this stanza. **If you declare nothing, the default applies**: mozart commits to the campaign branch, never contacts a remote, and names the branch in the final report for you to push and review however you like. Stage 12b (Ship) records a skip line and the rest of the pipeline is byte-for-byte what it is today.

Declare a `## Pull requests` stanza when you want mozart to push the campaign branch and open the PR at the end of a DELIVER campaign:

```markdown
## Pull requests

- enabled: true            # default false — mozart never pushes unless you declare this
- default_state: draft     # draft (default) | ready — draft flips to ready on validation signoff
- ci_wait_minutes: 10      # how long stage 13 waits for post-push CI to reach a terminal status
```

**`enabled: true` is the push authorization, and it authorizes exactly one action.** `PIPELINE.md`'s *Authority boundaries* prohibits mozart from pushing to a remote without user confirmation. That prohibition is unchanged; this stanza *is* the confirmation, for `git push -u origin campaign/<slug>` to this repo's own configured remote and nothing else. Force-push, pushes to a base or shared branch, branch deletion, merging, destructive migrations, and `kubectl apply` all still require a confirmation obtained in-session. No other stanza carries this property.

**This stanza is read from your remote's default branch, and it is the only one that is.** The consequence is worth stating plainly: **enabling Ship takes effect once the stanza is merged and pushed to your default branch, not when you write it locally.** That is the real cost of the design, and it is deliberate — the declaration goes through your repo's own review process, which is the property the whole authorization rests on.

The reason is that a PR which adds `enabled: true` must not authorize a push on the machine of whoever checks that PR out to help finish it. Mozart asks the remote which branch is default (`git ls-remote --symref origin HEAD`) rather than trusting a local pointer, because every local alternative can be steered — or can simply be absent or stale — on the checkout doing the asking.

**Your campaigns do not have to branch from that default branch.** If your `## Worktrees` stanza sets `base branch: develop` or a deploy branch, Ship still runs: the grant is read from the default branch, the PR opens against your declared base, and the pre-push echo prints both refs so the divergence is on the record. The other four stanzas are advisory (the worst a bad value does is route work to the wrong place, which is visible and undoable), so they are read from the working tree as normal.

**Write the stanza as a real stanza, not as documentation.** Three rules, because a grant that a reviewer reads as prose is not a grant anyone approved:

- The `## Pull requests` heading must appear **exactly once**, outside any code fence. Two headings is a stop, not a "last one wins" — that is how a grant gets appended below a decoy.
- Text inside a fenced ``` block is **ignored**. If you are documenting your setup — including by pasting the example above — it is documentation, not authorization, and it will not enable anything.
- `enabled: true` must be a **first-level bullet** of the stanza. A sentence that merely contains the words, like *"we do not enable this; it would read `- enabled: true`"*, does not grant anything.

**Mozart never writes this stanza.** Unlike `## Ticketing`, which mozart persists on your behalf once it has resolved your project, `## Pull requests` is yours to author. An agent that can grant itself push permission has not been granted anything. Its absence never means "mozart hasn't gotten around to it yet."

**Install a secret scanner before you enable this.** Stage 12b scans the **full branch history** (not the squashed diff) and the assembled PR body before pushing, because a secret added in one phase and removed in the next is invisible to a diff but ships in the push and stays in the remote's object store permanently:

```bash
brew install gitleaks          # or: go install github.com/zricethezav/gitleaks/v8@latest
brew install trufflehog        # or: pip install trufflehog
```

If neither is installed, mozart falls back to a fixed high-signal pattern set — AWS keys, PEM private-key headers, `ghp_`/`xox` tokens, JWT prefixes, and `key|secret|token = "…"` assignments. That fallback does **not** catch high-entropy strings, base64 blobs, connection strings, or any credential whose shape it doesn't already know. With no scanner resolved, `default_state: ready` **downgrades to `draft`** and says so in scott's return and in the PR body: a draft PR isn't indexed or broadcast to reviewers, and declaring a PR ready-for-review while running the weakest available scan is the combination worth refusing.

**There is no base-branch field here, deliberately.** The PR's base is the branch the worktree was cut from, declared once in `## Worktrees` as `base branch:`. A second declaration site would be a contract fork whose failure mode is a PR opened against the wrong base with a diff that looks correct.

---

## How agents read these stanzas

Mozart resolves the stanzas at intake (DELIVER stage 1, AUDIT stage 1, DIAGNOSE stage 1) and writes the resolved values into the state file:

```yaml
ticketing:
  system: <name>
  project: <id>
  active_ticket: <id> (<existing|new>)
docs:
  in_repo: [...]
  github_wiki: <enabled|disabled>
  external_wiki: <name or none>
worktree:
  path: <resolved worktree path, or n/a — <reason>>
  branch: <campaign branch>
pull_requests:
  enabled: <true|false>
  default_state: <draft|ready>
  ci_wait_minutes: <n>
  source_ref: base:<ref>@<sha>   # the ref the stanza was read from — origin's default branch
```

`pull_requests.source_ref` is part of the resolved value, not a note about it: an authorization is only meaningful alongside the ref it was read from, and a resumed campaign is exactly where an intake grant and a current grant can disagree. The **`base:` prefix is a discriminator** — a working-tree read and a default-branch read would otherwise have identical representations, and a check that can't tell them apart can't stop either one. A missing field, or any other prefix, is a stop.

Specialists read the state file rather than re-resolving:

- **dick** creates tickets in the configured system using the configured `investigating` state
- **jackson** posts comments after each phase commit
- **valerie** transitions the ticket to `verified` (or back to `in_progress` on FIXES REQUIRED)
- **scott** publishes to the configured docs surfaces using the configured categories, and — at stage 12b, when `pull_requests.enabled` is true — pushes the campaign branch and opens the PR at the resolved `default_state`. Scott is the one specialist that re-fetches and re-reads its stanza from the remote's default branch immediately before acting, because the action it authorizes cannot be taken back

If the state file lacks ticketing or docs config, agents skip the corresponding step gracefully and surface that to mozart.

---

## Migrating between systems

Switching from one ticketing system to another (e.g., Plane → Linear) is just a `CLAUDE.md` edit. Mozart re-resolves at the next intake. In-flight campaigns keep their original ticket; new campaigns use the new system.

The same applies to documentation — change the stanza, and the next scott run uses the new surface.

---

## Custom systems

If your team uses a ticketing system not listed above, file an issue or PR. The agent prompts use generic verbs (create / comment / transition / close) so adding a system is mostly a matter of filling in API endpoint patterns and authentication.
