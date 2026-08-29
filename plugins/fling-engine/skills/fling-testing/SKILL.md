---
name: fling-testing
description: Use when running Fling Engine's test suite or adding a new Catch2 test to FlingTests. Covers where tests live, how to run the built binary, and CI's cross-platform expectations.
---

# Testing Fling Engine

Fling Engine uses [Catch2 3](https://github.com/catchorg/Catch2) for first-party
tests. The test target is `FlingTests`, built from `FlingTests/src`, and it
links the full `FlingEngine` library — tests can exercise real engine code,
not just isolated units.

## Running tests

Build the `FlingTests` target as part of a normal build (see the
`fling-building` skill), then run the resulting binary directly:

```bash
# Linux
./build/FlingTests/bin/FlingTests

# Windows (path includes the build config)
build\FlingTests\bin\<Debug|Release>\FlingTests.exe
```

`Logs/` should exist before running — the engine writes runtime logs there;
CI runs `mkdir -p Logs` first, and a missing directory is a common local
failure that looks unrelated to the actual test.

Catch2's CLI flags work as usual:

```bash
./build/FlingTests/bin/FlingTests "[tag]"   # filter by tag
./build/FlingTests/bin/FlingTests --list-tests
```

## Adding a new test

- Add a new `.cpp` under `FlingTests/src`. Look at existing files
  (`ResourceTests.cpp`, `UtilsTests.cpp`, `RendererTests.cpp`) for naming and
  structure conventions before adding your own.
- `FlingTests/CMakeLists.txt` globs sources with `CONFIGURE_DEPENDS`, so a new
  file is picked up automatically — no CMakeLists edit needed. Re-run CMake
  configure if a new file doesn't show up in the build.
- Use Catch2's `TEST_CASE` / `SECTION` macros.
- Follow the `fling-coding-style` skill for any doc comments you add to test
  code.
- Prefer testing first-party engine code under `FlingEngine/`. Do not add
  tests that exercise `external/` internals directly — that's vendored code.

## CI expectations

Every PR runs `FlingTests` on Linux (GCC + Clang) and Windows (MSVC Debug/
Release + MinGW64) via `.github/workflows/build.yml`, plus the comment-style
check. A test that only passes on one platform is not finished — before
calling a new test done, check for platform-specific assumptions: path
separators, endianness, float precision, and undefined iteration order.
