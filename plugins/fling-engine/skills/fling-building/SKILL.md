---
name: fling-building
description: Use when building Fling Engine, configuring CMake build modes, running Init.sh/Init.bat on a fresh clone, or diagnosing a build that works locally but fails elsewhere. Covers Debug/Release/Shipping flags and DEFINE_SHIPPING.
---

# Building Fling Engine

Canonical source: `Skills/building.md` at the root of the FlingEngine repo you
are working in. **If that file exists in the current working tree, read it
now** — it is the up-to-date, tool-agnostic reference (any tool or human can
read it, not just Claude) and takes precedence over the summary below.

Use the fallback summary only if `Skills/building.md` is missing — for
example if you're working in a downstream project that depends on
FlingEngine rather than in a checkout of the engine itself.

## Fallback summary

First-time setup, once per fresh clone (or after `external/` submodules
update):

```bash
./Init.sh    # Linux/macOS
Init.bat     # Windows
```

This pulls git submodules, builds/installs Catch2 3 locally (no `sudo`
needed), and configures CMake into `build/`. Linux also needs system packages
(GLFW, Vulkan headers, X11/Wayland dev libs) — check the root `README.md` or
`.github/workflows/build.yml` for the package list. A build failing right
after a fresh clone usually means `Init.sh`/`Init.bat` was skipped.

Day-to-day, reconfigure `build/` for the mode you want (this does not build,
build separately with your generator):

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug                                # debug
cmake -B build -DCMAKE_BUILD_TYPE=Release                              # release
cmake -B build -DCMAKE_BUILD_TYPE=Release -DDEFINE_SHIPPING=ON         # shipping
cmake --build build --parallel $(nproc)
```

`-DDEFINE_SHIPPING=ON` sets `FLING_SHIPPING`, used to strip dev-only code
paths (`#ifdef FLING_SHIPPING`) and switch asset paths from absolute to
relative. There are no `build-debug.sh`/etc. wrapper scripts — use the CMake
invocations directly.

`.github/workflows/build.yml` is ground truth for exact CI flags across
Linux GCC/Clang and Windows MSVC/MinGW64 — check it first if a build works
locally but fails in CI or vice versa.
