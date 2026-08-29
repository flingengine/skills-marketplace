---
name: fling-architecture
description: Use when deciding where new Fling Engine code belongs, touching CMake targets or cross-folder includes, or reasoning about Gameplay/Graphics/Editor boundaries. Orientation for today's folder layout and the invariants that hold regardless of the in-progress module split.
---

# Fling Engine architecture / where things live

Canonical source: `Skills/architecture.md` at the root of the FlingEngine
repo you are working in. **If that file exists in the current working tree,
read it now** — it is the up-to-date, tool-agnostic reference and takes
precedence over the summary below. It also points to `docs/BuildModules.md`
for the in-progress module split and its locked decisions — read that too
before touching CMake targets, `FLING_ENGINE_INC()`, or cross-folder
includes; several plausible-looking cleanups are explicitly deferred or
rejected there.

Use the fallback summary only if `Skills/architecture.md` is missing.

## Fallback summary

Today's layout: `FlingEngine/` is one CMake library built via glob, with
subfolders `Core` (former Utils + Platform), `Graphics`, `Gameplay`,
`Resources`, `Editor`. `Sandbox/` is the sample game + editor. `FlingTests/`
links the full `FlingEngine` library. `external/` is vendored and never
modified. `docs/CodingStyle.md` and `docs/BuildModules.md` are the two
hand-maintained docs that matter day-to-day.

Rules that hold regardless of the module-split's progress:

- **Gameplay must not include Graphics.** `Transform`, `Camera`, `World`,
  `Game` must not include `MeshRenderer.h` or any Vulkan-facing type.
  Graphics may include Gameplay headers; not the other way around.
- **Editor is a leaf.** `Engine` and `Graphics` must not include
  `BaseEditor` or any Editor header — use the debug-UI hook pattern instead.
- **Don't add a new module folder or CMake target** without reading the
  "Locked decisions" section of `docs/BuildModules.md` first.

For the how-to on adding a new module, see `fling-adding-modules`.
