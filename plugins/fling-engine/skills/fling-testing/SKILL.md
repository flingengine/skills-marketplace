---
name: fling-testing
description: Use when running Fling Engine's test suite or adding a new Catch2 test to FlingTests. Covers where tests live, how to run the built binary, and CI's cross-platform expectations.
---

# Testing Fling Engine

Canonical source: `Skills/testing.md` at the root of the FlingEngine repo you
are working in. **If that file exists in the current working tree, read it
now** — it is the up-to-date, tool-agnostic reference and takes precedence
over the summary below.

Use the fallback summary only if `Skills/testing.md` is missing.

## Fallback summary

Fling Engine uses Catch2 3. The test target is `FlingTests`, built from
`FlingTests/src`, and links the full `FlingEngine` library, so tests exercise
real engine code.

Build `FlingTests` as part of a normal build (see `fling-building`), then run
the binary directly:

```bash
./build/FlingTests/bin/FlingTests                       # Linux
build\FlingTests\bin\<Debug|Release>\FlingTests.exe      # Windows
```

Make sure `Logs/` exists before running — the engine writes runtime logs
there. Catch2 CLI flags work as usual (`"[tag]"` to filter, `--list-tests`).

To add a test: add a new `.cpp` under `FlingTests/src` (match the style of
existing files like `ResourceTests.cpp`). The build globs sources with
`CONFIGURE_DEPENDS`, so no CMakeLists edit is needed — just re-run CMake
configure if the new file doesn't show up. Use `TEST_CASE`/`SECTION`, follow
`fling-coding-style` for any doc comments, and test first-party code under
`FlingEngine/` — not `external/` internals.

Every PR runs `FlingTests` on Linux (GCC + Clang) and Windows (MSVC
Debug/Release + MinGW64). A test that only passes on one platform isn't
finished — check for path-separator, endianness, and float-precision
assumptions before calling it done.
