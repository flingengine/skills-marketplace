---
name: fling-architecture
description: Use when deciding where new Fling Engine code belongs, touching CMake targets or cross-folder includes, or reasoning about Gameplay/Graphics/Editor boundaries. Orientation for today's folder layout and the invariants that hold regardless of the in-progress module split.
---

# Fling Engine architecture / where things live

This is orientation for today's layout, not a design doc. Fling Engine is
mid-migration from one monolithic library into separate CMake modules (Core,
Resources, Gameplay, Graphics, Editor, Engine) — see the `fling-adding-modules`
skill and `docs/BuildModules.md` for the full plan and its locked decisions
before touching CMake targets, `FLING_ENGINE_INC()`, or cross-folder includes.
Several things that look like obvious cleanups are explicitly deferred or
ruled out there.

## Today's layout

- **`FlingEngine/`** — the engine, currently one CMake library (`FlingEngine`)
  built from almost every source file under this tree via glob. Subfolders:
  `Core` (includes former `Utils` + `Platform`), `Graphics`, `Gameplay`,
  `Resources`, `Editor`. CMake/includes still treat it as one target —
  `FLING_ENGINE_INC()` adds every engine `inc/` dir to consumers, so folder
  location alone doesn't enforce isolation yet.
- **`Sandbox/`** — the sample game + editor, one executable today. Editor
  support is toggled by a project-wide `WITH_EDITOR` define (planned for
  removal in favor of two separate executables, `SandboxGame` /
  `SandboxEditor`).
- **`FlingTests/`** — Catch2 tests, links the full `FlingEngine` library. See
  the `fling-testing` skill.
- **`external/`** — vendored third-party dependencies (submodules). Never
  modified.
- **`docs/`** — human-facing docs; `docs/CodingStyle.md` and
  `docs/BuildModules.md` are the two that matter day-to-day. Most other files
  under `docs/` are generated Doxygen HTML output, not hand-maintained.
- **`scripts/`** — repo tooling (`check_comment_style.py`, the one-time
  `migrate_doxygen_comments.py` migration).
- **`CMake/`** — CMake helper modules (e.g. `FlingEngineInc.cmake`,
  `FlingModule.cmake`).

## Rules that hold regardless of the module-split's progress

These are invariants, not aspirational — treat a violation as a bug to fix,
not a style preference:

- **Gameplay must not include Graphics.** Types like `Transform`, `Camera`,
  `World`, `Game` live in Gameplay and must not include `MeshRenderer.h` or
  any Vulkan-facing type. Graphics *may* include Gameplay headers
  (`Transform`, `Camera`) — the dependency only goes one way.
- **Editor is a leaf.** `Engine` and `Graphics` must not include `BaseEditor`
  or any Editor header. If you find yourself adding such an include, that's
  the exact bug `docs/BuildModules.md` calls out — look for the debug-UI hook
  pattern it describes (an `IDebugUI`-style callback) instead of a direct
  Editor dependency.
- **Don't add a new module folder or CMake target without reading the "Locked
  decisions" section of `docs/BuildModules.md` first.** Several plausible
  approaches — per-module PCH, git submodules per engine system — are
  explicitly rejected there.

## Where new code goes

- Math/logging/platform-level utility → `FlingEngine/Core`.
- Anything touching `World`, `Transform`, `Camera`, or general game types
  (but not rendering) → `FlingEngine/Gameplay`.
- Rendering, Vulkan, meshes, lights → `FlingEngine/Graphics`.
- Asset loading/management → `FlingEngine/Resources`.
- Editor-only UI/tooling → `FlingEngine/Editor`, and only linked by editor
  executables.

When in doubt about a specific new module, use the `fling-adding-modules`
skill.
