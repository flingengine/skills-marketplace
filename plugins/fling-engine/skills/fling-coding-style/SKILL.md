---
name: fling-coding-style
description: Use when writing or editing first-party C++ in FlingEngine/, Sandbox/, or FlingTests/ — especially doc comments, formatting, or anything that touches external/. Covers the doc-comment conventions, clang-format, Simplified Technical English (ASD-STE100) rules for comment wording, and what not to touch.
---

# Fling Engine coding style

Applies to first-party Fling Engine C++: `FlingEngine/`, `Sandbox/`,
`FlingTests/`. **Never edit code under `external/`** — it's vendored
third-party code and is explicitly out of scope for any refactor, formatting
pass, or cleanup.

## Doc comments, formatting, and enforcement

Canonical source for these: `Skills/coding-style.md` and
`docs/CodingStyle.md` at the root of the FlingEngine repo you are working in.
**If `Skills/coding-style.md` exists in the current working tree, read it
now** — it is the up-to-date, tool-agnostic reference (any tool or human can
read it, not just Claude) and takes precedence over the summary below.

Use the fallback summary only if that file is missing.

### Fallback summary

Use modern Doxygen-style blocks with a plain description — no `@brief`, no
`/*!`:

```cpp
/**
 * Holds onto the command line arguments passed to this application.
 *
 * @param Argc  Number of arguments
 * @param ArgV  Argument values
 * @return True if successfully initialized
 */
bool Init(const int32 Argc, const char* ArgV[]);
```

Lead with a short description; use `@param`/`@return`/`@see` only when they
add information the signature doesn't already make obvious. Layout is
enforced by `.clang-format` at the repo root — run `clang-format`, don't
hand-format. Comment *content* is checked by
`python3 scripts/check_comment_style.py`, which rejects leftover `@brief`
and `/*!`. Nothing under `external/` gets reformatted or comment-style-fixed,
ever.

## Comment language: Simplified Technical English (ASD-STE100)

This section is a convention added by this plugin — it is not (yet) part of
FlingEngine's own docs, so it applies regardless of whether
`Skills/coding-style.md` exists. If you add it to the engine's own docs,
update this note.

Write every comment — doc comments and inline `//` comments alike — in
Simplified Technical English, the controlled-language standard (ASD-STE100)
used in aerospace and defense technical writing. Target reader: someone who
can parse the comment correctly on the first read, including a non-native
English speaker. This is a project writing convention, not something
`check_comment_style.py` enforces — it's on whoever (or whatever) writes the
comment to apply it.

Scope: comment **text** only. Never rewrite code identifiers, log/assert
strings, commit messages, or chat responses to fit STE, and never touch
comments under `external/`. Approved technical names stay as-is even where
STE's general-vocabulary rule would otherwise flag them — class and file
names, and established terms like `GPU`, `CPU`, `API`, `Vulkan`, `CMake`,
`DEFINE_SHIPPING`.

### Core rules

1. **One sentence, one idea.** Keep sentences to about 20 words. A sentence
   joined by "and"/"which"/"that" into two ideas should become two sentences.
2. **Active voice, simple tense.** Use simple present, simple past, or simple
   future only — never progressive (`is doing`) or perfect (`has done`,
   `will have done`) tenses.
   - Not STE: "The buffer will have been flushed before the callback is invoked."
   - STE: "The engine flushes the buffer before it calls the callback."
3. **Write instructions as commands.** For anything the reader must do, use
   the imperative — not passive voice, not "should".
   - Not STE: "The flag should be set before `Init` is called."
   - STE: "Set the flag before you call `Init`."
4. **One word per meaning.** Pick one verb per concept and reuse it — don't
   vary vocabulary for style. Common swaps for comment text:

   | Instead of | Write |
   |---|---|
   | utilize | use |
   | in order to | to |
   | prior to / previous to | before |
   | subsequent to | after |
   | in the event that | if |
   | terminate | stop / end |
   | initiate / commence | start |
   | obtain | get |
   | ensure | make sure |
   | assist | help |
   | sufficient | enough |
   | numerous | many |
   | approximately | about |
   | currently | now |
   | perform | do |
   | facilitate | help |
   | leverage | use |
   | indicate | show |
   | additional | more |

5. **Cut vague qualifiers.** Delete "very", "quite", "really", "fairly",
   "essentially", "virtually" — or replace with the exact condition or number
   they were gesturing at.
6. **Limit noun stacks to three words.** Break up longer chains with "of" or
   "for".
   - Not STE: "the pipeline layout descriptor set index"
   - STE: "the index of the descriptor set in the pipeline layout"
7. **Keep articles.** Don't drop "a"/"the" to sound terse — comments aren't
   headlines.
8. **No idioms, slang, or metaphors** ("under the hood", "on the fly", "a
   gotcha").
9. **Spell out an abbreviation on first use per file**, unless it's an
   approved technical name already used throughout the codebase (`GPU`,
   `CPU`, `API`, `CMake`, `ECS`).

### Example

Not STE (passive, vague, one long sentence):

```cpp
// This value is generally used by the renderer in cases where the
// swapchain has not yet been fully initialized, which can occasionally
// happen on slower hardware.
```

STE:

```cpp
// The renderer uses this value if the swapchain is not ready yet.
// This can happen on slow hardware.
```

## What not to touch

- Nothing under `external/` — no reformatting, no comment-style fixes, no
  "cleanup" edits, even if it violates every rule above. It's vendored as-is.
