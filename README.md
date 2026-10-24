# skills-marketplace

A Claude Code plugin marketplace for developing
[Fling Engine](https://github.com/flingengine/FlingEngine), a cross-platform
Vulkan game engine in C++.

| Plugin | What it adds |
|--------|--------------|
| `fling-engine` | Skills for building, testing, coding style, and architecture in the FlingEngine repo |
| `rollback-netcode` | An expert subagent for rollback, client-side prediction, and lag compensation, with a credited reference library |
| `gameplay-architecture` | A skill for building systems as a strict ECS in the Overwatch style, plus a migration path for Fling Engine |

## Install

In Claude Code:

```
/plugin marketplace add flingengine/skills-marketplace
/plugin install fling-engine@fling-engine-skills
/plugin install rollback-netcode@fling-engine-skills
/plugin install gameplay-architecture@fling-engine-skills
```

Or from the CLI:

```bash
claude plugin marketplace add flingengine/skills-marketplace
claude plugin install fling-engine@fling-engine-skills
claude plugin install rollback-netcode@fling-engine-skills
claude plugin install gameplay-architecture@fling-engine-skills
```

## `fling-engine`

Installing the `fling-engine` plugin adds five skills, scoped to FlingEngine
development so they only activate on relevant tasks:

| Skill | Covers |
|-------|--------|
| `fling-building` | `Init.sh`/`Init.bat`, CMake build modes, `DEFINE_SHIPPING` |
| `fling-testing` | Running and adding Catch2 tests under `FlingTests/` |
| `fling-coding-style` | Doc-comment conventions, `clang-format`, what not to touch |
| `fling-architecture` | Current folder/module layout, Gameplay/Graphics/Editor boundaries |
| `fling-adding-modules` | Adding a new CMake engine module with `fling_add_module` |

Each skill here is a thin wrapper: it tells Claude to read the matching
canonical file — `Skills/<topic>.md` in the FlingEngine repo you're actually
working in — and only falls back to an inline summary if that file isn't
present (for example, if FlingEngine is a dependency rather than the repo
you've checked out). The canonical files stay plain, tool-agnostic markdown
in the engine repo, so anything else that reads markdown — another agent, an
IDE, a human — gets the same context, not just Claude. The `fling-coding-style`
skill also adds one thing that isn't in the engine repo's own docs: a
Simplified Technical English (ASD-STE100) convention for comment wording,
kept here since it's a Claude-specific writing rule rather than an engine
convention.

## `rollback-netcode`

Adds the `rollback-netcode:rollback-netcode-expert` subagent. Claude
delegates to it for netcode design, implementation, review, and debugging. It
covers P2P rollback (GGPO-style), server-authoritative prediction and replay,
server-side rewind, input redundancy, time sync, and determinism testing.
Invoke it directly with `@agent-rollback-netcode:rollback-netcode-expert`.

It answers from study notes bundled in `plugins/rollback-netcode/references/`:
GGPO (Tony Cannon), Michael Stallone's GDC 2018 NetherRealm talk, Timothy
Ford's GDC 2017 Overwatch talk (netcode half), and Glazer & Madhav's *Multiplayer Game
Programming* Ch. 8. Every source is credited in its `notes.md`.
`references/README.md` lists the rules for adding a source: notes in your own
words, short attributed quotes only, and no transcripts, scans, or unlicensed
code.

## `gameplay-architecture`

Adds the `ecs-architecture` skill. Claude loads it when you design, write,
review, or refactor ECS systems. It holds the strict ECS rules from Timothy
Ford's GDC 2017 Overwatch talk: components with no functions, systems with no
state, singleton components, utility-function call-site rules, deferred side
effects, and explicit tuples. It also has a review checklist and a step-by-step
direction for moving Fling Engine from `Game::Update` and engine singletons to
that model. Load it by hand with `/gameplay-architecture:ecs-architecture`.
The ECS half of the talk's notes ships with it.

## Repo layout

```
.claude-plugin/marketplace.json   # marketplace manifest
plugins/fling-engine/
  .claude-plugin/plugin.json
  skills/<skill-name>/SKILL.md
plugins/rollback-netcode/
  .claude-plugin/plugin.json
  agents/rollback-netcode-expert.md
  references/<source>/notes.md
plugins/gameplay-architecture/
  .claude-plugin/plugin.json
  skills/ecs-architecture/SKILL.md
  skills/ecs-architecture/references/overwatch-ecs-notes.md
```

## Updating skills

FlingEngine's own docs (`AGENTS.md`, `Skills/*.md`, `docs/BuildModules.md`)
are the source of truth for everything except the ASD-STE100 comment-language
rules. Since each `SKILL.md` here just points at those files, most upstream
doc changes need no edit here at all. Update a `SKILL.md` in this repo only
when:

- Its **fallback summary** (used when `Skills/<topic>.md` is missing) has
  drifted from the real file enough to mislead someone relying on it.
- Its **frontmatter description** needs to change for Claude to trigger it
  correctly.
- You're changing the ASD-STE100 section in `fling-coding-style`, which is
  maintained only here.

After any change, bump `version` in both `plugin.json` and the marketplace
entry in `marketplace.json`. The same applies to `rollback-netcode` and
`gameplay-architecture` when you edit their agents, skills, or references.

## Adding a new skill

1. Create `plugins/fling-engine/skills/<name>/SKILL.md` with a `name` and a
   `description` in its frontmatter. Write the description so Claude can tell
   from a task alone whether the skill applies — name the files, folders, or
   commands involved.
2. Bump `version` in `plugins/fling-engine/.claude-plugin/plugin.json`.
3. If you want the marketplace listing's own description to change too,
   update `.claude-plugin/marketplace.json`.
