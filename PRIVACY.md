# Privacy Policy

**Last updated**: 2026-05-04

mozart-orchestration is a Claude Code plugin distributed as a corpus of markdown agent personas, a slash command, a plugin manifest, and a marketplace manifest. It is static content. The plugin itself does not collect, store, transmit, or share any user data.

## What the plugin does

The plugin defines agent personas and a `/mozart` slash command. When invoked, those personas execute inside your Claude Code session using the tools and permissions Claude Code grants them. The plugin does not run any code outside of Claude Code's agent runtime.

## What data the agents may access

When you invoke the plugin, the agents operate on whatever you point them at:

- **Files in your working directory** — agents may read, edit, write, and create files (Read, Edit, Write, Glob, Grep tools).
- **Shell commands** — some agents (notably jackson) execute shell commands via the Bash tool.
- **Web requests** — some agents (sarah, web-search-researcher, scott) perform web searches and fetches via WebSearch and WebFetch.
- **External services you have configured** — if you have configured ticketing (Plane, Linear, Jira, GitHub Issues, Notion) or external documentation (GitHub wiki, Wiki.js, Notion, Confluence) in your `CLAUDE.md`, the agents may call those services using credentials you supply via your configured secret-fetch command. The plugin does not store or proxy these credentials.
- **The OpenAI `codex` CLI** (optional) — if installed, mozart invokes it for independent plan and diff review at stages 5 and 9 of the DELIVER pipeline.

All access is performed by named subagents, transparent in mozart's live narration. You always see which agent is running and why.

## What the plugin does NOT do

- Send telemetry, analytics, or any data to the plugin author, Anthropic, or any third party of the plugin's choosing.
- Bundle or transmit credentials, tokens, or secrets.
- Modify your shell, environment variables, or system configuration outside of files you direct it to.
- Persist any data outside of your local working directory.

## Mozart's working artifacts

When mozart orchestrates work, it writes plan files, state files, flow sketches, and audit reports to `thoughts/` in your working directory. These are local files in your repo. They are not transmitted anywhere. Whether you commit them is your choice; the included `.gitignore` patterns can be adapted to keep them out of git.

## Third-party data handling

When agents call external services (your ticketing system, your wiki, web fetches, the codex CLI), those services have their own privacy policies. The plugin neither controls nor sees how those services handle data. Review their policies separately:

- Anthropic Claude Code privacy: https://www.anthropic.com/legal/privacy
- Your configured ticketing system: see that vendor's policy
- Your configured wiki: see that vendor's policy
- OpenAI Codex CLI (if used): https://openai.com/policies/privacy-policy

## Reporting concerns

If you discover a privacy concern in the plugin's design or any of its agent prompts, file a GitHub Security Advisory or issue at https://github.com/jstuart0/mozart-orchestration/issues. Contact: jay.stuart@agileservicesgrp.com.

## Changes

Material changes to this policy will be noted in `CHANGELOG.md` under the corresponding plugin version.
