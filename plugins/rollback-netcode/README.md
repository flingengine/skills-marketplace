# rollback-netcode

A Claude Code subagent that is an expert in latency hiding for real-time
multiplayer games: rollback and resimulation, client-side prediction and
replay, lag compensation, time sync, and determinism testing.

## Install

```
/plugin marketplace add flingengine/skills-marketplace
/plugin install rollback-netcode@fling-engine-skills
```

Claude delegates netcode questions to the agent automatically. To call it
directly, type `@agent-rollback-netcode:rollback-netcode-expert`.

## Contents

```
agents/rollback-netcode-expert.md   # the agent
references/                         # its reference library (study notes)
  README.md                         # sources, authors, licence status
  ggpo-networking-source/           # notes + GGPO source subset (MIT, LICENSE included)
  mk-rollback-talk/                 # notes on Stallone, GDC 2018
  overwatch-netcode-talk/           # notes on Ford, GDC 2017 (netcode half)
  multiplayer-game-programming/     # notes on Glazer & Madhav, Ch. 8, + fetch script for the sample code
```

## Credit and licensing

The notes are the maintainers' own study notes. All ideas belong to the
original speakers and authors, who are credited at the top of each
`notes.md` and in `references/README.md`. No transcripts, slide text, book
scans, or unlicensed code are included. GGPO is included under its MIT License
(`references/ggpo-networking-source/code/LICENSE`), which takes precedence over
this repository's licence for those files.

Follow the rules in `references/README.md` when you add a source.
