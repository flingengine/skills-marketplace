---
name: fling-adding-modules
description: Use when adding a new engine module to Fling Engine (a new folder under FlingEngine/ with its own CMake target), or when asked how fling_add_module works. Covers the module recipe, the UI-module worked example, and the checklist.
---

# Adding a Fling Engine module

Canonical source: `Skills/adding-modules.md` at the root of the FlingEngine
repo you are working in. **If that file exists in the current working tree,
read it now** — it is the up-to-date, tool-agnostic reference and takes
precedence over the summary below. It in turn points to `docs/BuildModules.md`
for the full design and locked decisions — read that before starting real
module work, not just this summary.

Use the fallback summary only if `Skills/adding-modules.md` is missing.

## Fallback summary

`fling_add_module()` lives in `CMake/FlingModule.cmake`. A module is: a
folder under `FlingEngine/<Name>/{inc,src}`, a `CMakeLists.txt` calling
`fling_add_module(<Name> PUBLIC_DEPS ... PRIVATE_DEPS ... PRIVATE_LIBS ...)`,
an `add_subdirectory(<Name>)` in `FlingEngine/CMakeLists.txt` placed *after*
its dependencies, `<NAME>_API` on types crossing the DLL boundary, and
`target_link_libraries(Consumer PRIVATE Fling::<Name>)` on anything that
should see its headers. Don't hand-list `.cpp` files, don't extend the old
engine-wide glob, and never edit `external/`.

Isolation test: a target that does **not** link `Fling::<Name>` must fail to
compile if it includes that module's headers. If it compiles anyway,
something is leaking includes outside `target_link_libraries`.

Checklist:

- [ ] Folder is `FlingEngine/<Name>/{inc,src}` plus `CMakeLists.txt`.
- [ ] Calls `fling_add_module(<Name> ...)` only.
- [ ] `add_subdirectory(<Name>)` placed after every `PUBLIC_DEPS`/`PRIVATE_DEPS`.
- [ ] Public headers include `<Name>API.h` and use `<NAME>_API` on exports.
- [ ] Consumers use `target_link_libraries(... Fling::<Name>)`.
- [ ] Gameplay still doesn't include Graphics; Editor stays a leaf (see
      `fling-architecture`).
- [ ] Nothing under `external/` is modified.

For the full worked example (a `UI` module, with CMake and header code), read
`Skills/adding-modules.md` in the engine repo — this fallback intentionally
omits it to avoid drifting out of sync with the canonical version.
