---
name: ecs-architecture
description: Use when designing, writing, reviewing, or refactoring gameplay or engine systems in an Entity Component System style, especially Overwatch-style strict ECS (components with no functions, systems with no state, singleton components, utility functions, deferred side effects, explicit component tuples). Applies to new components and systems, EnTT registry/view code, moving state out of classes or globals into components, and planning Fling Engine's move from Game::Update and engine singletons to strict ECS.
---

# Strict ECS gameplay architecture (Overwatch style)

This skill is the rulebook for building gameplay and engine systems as a strict ECS, as Timothy Ford described for Overwatch at GDC 2017. Apply the rules to any code you write or review that touches entities, components, or systems.

**Source and credit:** Timothy Ford (Blizzard Entertainment), *'Overwatch' Gameplay Architecture and Netcode*, GDC 2017 (https://gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and). The rules below are a summary in our own words. Detailed notes with examples and timestamps are in `${CLAUDE_PLUGIN_ROOT}/skills/ecs-architecture/references/overwatch-ecs-notes.md`. **Read that file** when you need a worked example, the reason behind a rule, or a source to cite. When you rely on it, credit Ford and give the timestamp.

## The rules

1. **Components have state and no functions. Systems have functions and no state.** A component is plain data, with at most small accessors and lifetime hooks. A system has no member variables. Its tick iterates the entities that have every component in its tuple, and it does not know what an entity "is".
2. **System state goes in singleton components.** If a system wants a member variable, make it a component with exactly one instance per world, and reach it through the world, never through a global. State one system needs is almost always wanted by another later. (About 40% of Overwatch's components are singletons.)
3. **Systems never call other systems.** Put shared behavior in a **utility function**, and size it by this rule:
   - Called from **many** places -> reads **few** components and has **few or no** side effects (ideally pure).
   - Reads **many** components or has **many** side effects -> called from **very few** places (for example, one move function called only by the server simulation and the client prediction).
4. **Defer big side effects.** If a behavior creates entities, spawns effects, applies damage, or touches resources, ask whether it must happen now. Usually it doesn't. Append a request to a queue in a singleton component, and let one system resolve every request once, at one point in the frame. This gives one call site, cache locality, a performance budget, and easy parallelism.
5. **Keep each behavior's side effects at one call site.** Behaviors are much less complex when all their major side effects happen in one place.
6. **Use explicit tuples.** Declare which components a system reads and writes. A very long tuple is a warning that the system is too big. Read/write tags let systems with disjoint writes run in parallel.
7. **Don't force specialist subsystems into ECS.** Physics, pathfinding, audio, and projectile simulation keep their own internals behind a thin **proxy component** (an "iceberg": small surface in ECS, large state underneath).
8. **Worlds must be instantiable.** Nothing may assume there is exactly one world. If all state lives in components, a second world (kill cam, replay, editor preview, rollback resimulation, tests) just works.
9. **Create entities immediately; defer destruction.** Overwatch found that deferred creation caused off-by-one-frame bugs and switched to immediate creation after ship. Deferred destruction was fine.
10. **Write the rules down and enforce them in review.** Code that breaks the rules is where the churn and bugs collect.

## Review checklist

When you write or review ECS code, check each item:

- [ ] Does any new component have behavior (non-trivial methods)? Move the behavior to a system or utility.
- [ ] Does any system have member variables, statics, or file-scope state? Move the state to a singleton component.
- [ ] Does any system include another system's header, or call it? Replace the call with a utility function or a queued request.
- [ ] Does a utility with many call sites mutate much? Narrow what it reads and writes, or cut its call sites.
- [ ] Are big side effects (create/destroy, VFX, audio, damage, resource loads) done inline mid-simulation? Queue them instead.
- [ ] Does anything reach a world, registry, or system through a global or singleton accessor? Pass the world or registry in.
- [ ] Would this code still work with two worlds alive at once?

## Applying this to Fling Engine

Fling Engine already uses **EnTT**, but it is not yet a strict ECS. Before you change engine code, read the FlingEngine repo's `AGENTS.md`, `Skills/architecture.md`, and `Skills/module-split-plan.md` (or the `fling-engine` plugin's `fling-architecture` skill). They have the module boundaries and the decisions that are locked. Verify the current state yourself: the points below describe the engine as of October 2026.

**Where it is today:**
- One global `entt::registry` (`g_Registry`), owned by `Engine` and passed by reference to `World`, `Game`, `VulkanApp`, the render subpasses, and the editor.
- `World` documents that there is only ever one instance.
- Gameplay runs in `Game::Update(entt::registry&, float DeltaTime)`, a per-game override where each game calls its own systems ad hoc. There is no system list and no declared update order.
- Engine services are `Singleton<T>` classes (`VulkanApp`, `ResourceManager`, `Timing`, `Logger`, `FlingConfig`).
- The frame uses a variable `DeltaTime` from `Timing`.
- The vendored EnTT is **3.1.0**. Use `registry.view<A, B>()` for tuples and `registry.set<T>()` / `registry.ctx<T>()` / `registry.try_ctx<T>()` for singleton components. EnTT 3.1 has no `entt::organizer`, so declare read/write sets and scheduling in our own code.

**Direction (incremental, keeping each step shippable):**
1. **Name the systems.** Introduce a system interface and an ordered system list per world, with update phases (for example input, simulation, deferred resolution, presentation). Move ad-hoc calls out of `Game::Update` into registered systems.
2. **Move system state into singleton components** held in the registry context, starting with input. Make `Input` fill a `SingletonInput` component that gameplay systems read, instead of being queried globally.
3. **Stop reaching for globals.** Pass the world or registry into systems. Retire `g_Registry` use outside `Engine` so a second registry (editor preview, tests, replay) can exist.
4. **Introduce deferment queues** for entity spawning, VFX/audio, and damage-like events, each resolved by one system per frame.
5. **Wrap specialist subsystems** (rendering, physics, resources) behind proxy components rather than reshaping them. Keep the module rules: Gameplay must not include Graphics, and Editor stays a leaf.
6. **Add a fixed simulation step** with an accumulator for simulation systems, separate from render. This also prepares the engine for rollback netcode. If the `rollback-netcode` plugin is installed, consult its `rollback-netcode-expert` agent for that work.

Add Catch2 tests as you go: systems that are pure functions of components are easy to test with a registry built in the test.
