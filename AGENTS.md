# TimbreBox · Agent Collaboration Rules

**Language: English · [简体中文](./AGENTS.zh-CN.md)**

## Project Goal

For now we ship only the lightweight music-player loop for Windows, macOS, Linux,
iOS, and Android, with just YouTube, Bilibili, Douyin, and TikTok as built-in
sources at launch. Audius, Internet Archive, and Radio Browser come in a later
phase; NetEase Cloud Music and QQ Music come later still. None may be presented
as a shipped capability ahead of time.

The detailed specs and design (scope source-of-truth, implementation boundaries,
phase plan, source admission, etc.) live in the **local internal docs** under
`docs/prd/` and `docs/internal/` — kept local only, never published with the
repository. Read them before starting a task.

## gstack / Agent Skill Routing

gstack is installed for Codex. Pick the minimal necessary workflow per task:

| Task | Required skill / check |
|---|---|
| New product scope, version trade-offs | `gstack-office-hours` → `gstack-plan-ceo-review` |
| Architecture, protocol, data flow, test plan | `gstack-plan-eng-review` |
| UI structure, visual system, interaction design | `gstack-plan-design-review` or `gstack-design-consultation` |
| Post-implementation code check | `gstack-review` |
| Device / browser / end-to-end verification | `gstack-qa`; report-only `gstack-qa-only` |
| Security, credentials, external binaries, IPC | `gstack-cso` and `gstack-guard` |
| Pre-release docs and handoff | `gstack-document-release` → `gstack-ship` |

Routine small fixes do not require the full workflow. Do not pull in unrelated
browsers, telemetry, remote services, or long-running processes just to "use a
skill". Every external tool must still honor the internal spec's low-resource,
no-user-credential, local-first constraints; any anonymous temporary session
state a source adapter produces must stay in memory only.

### TimbreBox control skill (drive the running player)

The repo ships its own project skill, `timbrebox-control` (`.claude/skills/`),
plus the `tools/timbrebox-ctl` wrapper, to drive the **running** app through its
local loopback control API (on by default, no token — loopback is the boundary):

- **Claude Code** auto-invokes the `timbrebox-control` skill for natural-language
  requests ("播放周杰伦的歌", pause, next, volume, shuffle, queue …); the flow is
  search → `play-ref` → `status`.
- **Codex CLI** and any local script drive the same API via
  `tools/timbrebox-ctl <cmd>` or plain `curl` on `127.0.0.1`.
- These are `timbrebox-ctl` subcommands / HTTP paths, **not** slash commands — the
  only slash command is `/timbrebox-control`; never invoke a bare `/status`.
- Project skills are enumerated at **session start** — after adding or editing a
  skill, restart the session (reopen the repo) so it loads before it can auto-trigger.
- This controls one running instance only; it never launches, builds, or edits the
  app. Full reference: `docs/agent-control-api.md`.

## Development Standards (mandatory, every fix and feature)

### Workflow: Plan → Review dependencies → Options → Pick best → Implement
1. **Plan:** arrange the plan before touching code (use TaskCreate to land
   ordered, verifiable steps).
2. **Review dependencies:** understand how this change relates to surrounding
   code — who calls it, what it depends on, and which pages / contracts / data
   layers / platforms the change ripples into.
3. **Weigh options:** offer 2–3 alternatives with trade-offs.
4. **Pick the best:** choose the best option before implementing; **never skip
   straight to editing.**
5. **Implement + verify:** `flutter analyze` and tests pass; **close the old app
   and launch a fresh build** for on-device verification.
6. Write code through the **engineering skills** (`gstack-plan-eng-review` sets
   the architecture, `gstack-review` checks the implementation); do not add
   unrelated dependencies just to "use a skill".

### Code Quality
- **One file ≤ 800 lines**; split into cohesive small files as you approach it.
- **Reuse first** (Rule of Three): reuse existing components / utilities /
  parsers before reinventing them.
- Factor reusable logic into **functions / methods** and call it across sites;
  no copy-paste drift.
- **No useless explanatory code, no useless operations, no placeholder dead
  code**; KISS, keep only the necessary implementation.
- **No mock / hardcoding / fake data:** all data comes from real sources, the
  frontend only renders; honest loading / error / empty states.

### Directory Standard (professional layering — by feature/domain, not by type)
The playback engine must decouple its directories by "platform" and "source":
- `playback/`: platform audio backends, loopback proxy, resolver, source spec —
  **source-agnostic**.
- `sources/<source>/`: one directory per source (`youtube` / `bilibili` /
  `douyin_tiktok` / `audius` / `internet_archive` / `radio_browser`); shared HTTP
  client, cookie jar, and parsing utilities go in `sources/_shared/`.
- `catalog/`: source registry plus aggregated search / pagination / charts.
- `state/` `views/` `widgets/` `model/` `design/` each keep a single
  responsibility — high cohesion, low coupling.

## Non-negotiable Boundaries

- Do not collect source accounts, browser cookies, user-imported cookies, API
  keys, tokens, or device identifiers. If a source adapter genuinely needs one,
  it may create an anonymous temporary cookie on demand, use it in this
  process's memory only, clear it on exit, and never write it to disk, logs, or
  a database.
- Do not introduce DRM circumvention, paid-content scraping, dynamic `eval`,
  unsigned plugins, or downloaded-and-executed code on mobile.
- The desktop CLI is a one-shot control client; it must not start the player or
  leave a background process behind.
- Unused sources, plugins, resolvers, and network requests must have zero
  residency.
- Before referencing or adapting third-party material, record the license,
  pinned version, and attribution in the local internal docs.

## Definition of Done

Every implementation task must cover: scope dependencies, tests/fixtures, the
failure path, performance impact, doc updates, and a rollback / source-disable
strategy (where applicable). Any commit that changes product scope, sources,
permissions, IPC, or the performance budget must also update the local internal
spec and the relevant architecture / admission docs.
