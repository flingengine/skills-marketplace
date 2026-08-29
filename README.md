# skills-marketplace

A Claude Code plugin marketplace with skills for developing
[Fling Engine](https://github.com/flingengine/FlingEngine) — a cross-platform
Vulkan game engine in C++.

## Install

In Claude Code:

```
/plugin marketplace add flingengine/skills-marketplace
/plugin install fling-engine@fling-engine-skills
```

Or from the CLI:

```bash
claude plugin marketplace add flingengine/skills-marketplace
claude plugin install fling-engine@fling-engine-skills
```

## What you get

Installing the `fling-engine` plugin adds five skills, scoped to FlingEngine
development so they only activate on relevant tasks:

| Skill | Covers |
|-------|--------|
| `fling-building` | `Init.sh`/`Init.bat`, CMake build modes, `DEFINE_SHIPPING` |
| `fling-testing` | Running and adding Catch2 tests under `FlingTests/` |
| `fling-coding-style` | Doc-comment conventions, `clang-format`, what not to touch |
| `fling-architecture` | Current folder/module layout, Gameplay/Graphics/Editor boundaries |
| `fling-adding-modules` | Adding a new CMake engine module with `fling_add_module` |

These mirror the `AGENTS.md` / `Skills/` guidance maintained in the
[FlingEngine repo itself](https://github.com/flingengine/FlingEngine) — this
marketplace packages that guidance as installable Claude Code skills so it
travels with your Claude Code setup rather than needing to be present in
every clone.

## Repo layout

```
.claude-plugin/marketplace.json   # marketplace manifest
plugins/fling-engine/             # the one plugin this marketplace ships
  .claude-plugin/plugin.json
  skills/<skill-name>/SKILL.md
```

## Updating skills

FlingEngine's own docs (`AGENTS.md`, `Skills/*.md`, `docs/BuildModules.md`)
are the source of truth. When those change upstream, update the matching
`SKILL.md` here and bump `version` in both `plugin.json` and the marketplace
entry in `marketplace.json`.

## Adding a new skill

1. Create `plugins/fling-engine/skills/<name>/SKILL.md` with a `name` and a
   `description` in its frontmatter. Write the description so Claude can tell
   from a task alone whether the skill applies — name the files, folders, or
   commands involved.
2. Bump `version` in `plugins/fling-engine/.claude-plugin/plugin.json`.
3. If you want the marketplace listing's own description to change too,
   update `.claude-plugin/marketplace.json`.
