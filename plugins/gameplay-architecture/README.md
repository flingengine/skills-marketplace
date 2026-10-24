# gameplay-architecture

A Claude Code skill for building gameplay and engine systems as a strict
Entity Component System, in the style Timothy Ford described for Overwatch at
GDC 2017. Components have state and no functions, systems have functions and
no state, system state lives in singleton components, shared behavior goes in
utility functions with call-site rules, and big side effects are deferred.

## Install

```
/plugin marketplace add flingengine/skills-marketplace
/plugin install gameplay-architecture@fling-engine-skills
```

Claude loads the skill automatically when a task involves designing,
reviewing, or refactoring ECS systems. To load it by hand, run
`/gameplay-architecture:ecs-architecture`.

## Contents

```
skills/ecs-architecture/
  SKILL.md                         # the rules, a review checklist, and the Fling Engine migration direction
  references/overwatch-ecs-notes.md  # study notes on the ECS half of the talk
```

## Credit

The rules and examples come from Timothy Ford (Blizzard Entertainment),
*'Overwatch' Gameplay Architecture and Netcode*, GDC 2017
(https://gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and).
The notes are the maintainers' own study notes, written in their own words. No
transcript or slide text is included. The netcode half of the talk is covered
in the `rollback-netcode` plugin.
