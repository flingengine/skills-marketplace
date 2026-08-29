---
name: fling-building
description: Use when building Fling Engine, configuring CMake build modes, running Init.sh/Init.bat on a fresh clone, or diagnosing a build that works locally but fails elsewhere. Covers Debug/Release/Shipping flags and DEFINE_SHIPPING.
---

# Building Fling Engine

Fling Engine is one CMake project producing a `FlingEngine` library, a `Sandbox`
game/editor, and a `FlingTests` Catch2 target.

## First-time setup

Run once per fresh clone (or after `external/` submodules update):

```bash
./Init.sh    # Linux/macOS
Init.bat     # Windows
```

This does three things, in order:

1. `git submodule update --init --recursive` — pulls every vendored dependency
   under `external/`.
2. Builds and installs Catch2 3 locally to `external/Catch2/install` (no `sudo`
   needed; `FlingTests/CMakeLists.txt` does `find_package(Catch2 3 REQUIRED)`
   against this local install).
3. Configures CMake into `build/` with default settings.

Linux additionally needs system packages before CMake will configure cleanly
(GLFW, Vulkan headers, X11/Wayland dev libs). Check the root `README.md` for the
`apt-get` list, or `.github/workflows/build.yml` for the exact CI package list
if a package is missing.

If a build fails right after cloning, suspect a skipped `Init.sh`/`Init.bat`
before anything else — missing submodules or a missing local Catch2 install
are the most common causes.

## Day-to-day builds

Reconfiguring `build/` does **not** build — it only sets the mode. Build
separately, with your generator.

```bash
# Reconfigure for the mode you want
cmake -B build -DCMAKE_BUILD_TYPE=Debug                                # debug
cmake -B build -DCMAKE_BUILD_TYPE=Release                              # release
cmake -B build -DCMAKE_BUILD_TYPE=Release -DDEFINE_SHIPPING=ON         # shipping

# Then build
cmake --build build --parallel $(nproc)   # $(nproc): use all available cores
```

There is no `build-debug.sh` / `build-release.sh` / `build-shipping.sh` wrapper
— those were removed because CI and IDE tooling (VS Code's cmake-tools
extension) never used them and they only added indirection over a couple of
CMake flags. Don't reintroduce them; use the `cmake -B` / `cmake --build`
invocations directly.

## `DEFINE_SHIPPING`

`-DDEFINE_SHIPPING=ON` sets the `FLING_SHIPPING` preprocessor define, which
first-party code uses to strip dev-only paths:

```cpp
#ifdef FLING_SHIPPING
// shipping-only behavior
#else
// dev behavior, verbose logging, etc.
#endif
```

It also switches asset paths from absolute (convenient for iterating without
reconfiguring) to relative, so a shipped executable is portable. When adding
code that reads assets or logs verbosely, check whether it needs to be gated
behind this define the same way existing nearby code is.

## CI reference

`.github/workflows/build.yml` is ground truth for exactly what gets built and
with which flags, across Linux GCC, Linux Clang, Windows MSVC (Debug +
Release), and Windows MinGW64. If a build works locally but fails in CI (or
vice versa), diff your flags/generator against that workflow before assuming
a code bug.
