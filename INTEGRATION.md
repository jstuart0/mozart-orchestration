# INTEGRATION.md

Mozart is pluggable for two surfaces: **ticketing** and **documentation**. You configure both by adding stanzas to your repo's `CLAUDE.md`. Mozart and his specialists read those stanzas at intake; if a stanza is missing, the corresponding behavior is skipped or falls back to a sensible default.

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

## How agents read these stanzas

Mozart resolves both stanzas at intake (DELIVER stage 1, AUDIT stage 1, DIAGNOSE stage 1) and writes the resolved values into the state file:

```yaml
ticketing:
  system: <name>
  project: <id>
  active_ticket: <id> (<existing|new>)
docs:
  in_repo: [...]
  github_wiki: <enabled|disabled>
  external_wiki: <name or none>
```

Specialists read the state file rather than re-resolving:

- **dick** creates tickets in the configured system using the configured `investigating` state
- **jackson** posts comments after each phase commit
- **valerie** transitions the ticket to `verified` (or back to `in_progress` on FIXES REQUIRED)
- **scott** publishes to the configured docs surfaces using the configured categories

If the state file lacks ticketing or docs config, agents skip the corresponding step gracefully and surface that to mozart.

---

## Migrating between systems

Switching from one ticketing system to another (e.g., Plane → Linear) is just a `CLAUDE.md` edit. Mozart re-resolves at the next intake. In-flight campaigns keep their original ticket; new campaigns use the new system.

The same applies to documentation — change the stanza, and the next scott run uses the new surface.

---

## Custom systems

If your team uses a ticketing system not listed above, file an issue or PR. The agent prompts use generic verbs (create / comment / transition / close) so adding a system is mostly a matter of filling in API endpoint patterns and authentication.
