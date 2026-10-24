# Notes: Overwatch's ECS gameplay architecture (from "Overwatch Gameplay Architecture and Netcode", GDC 2017)

## Source and credit

- **Talk:** *'Overwatch' Gameplay Architecture and Netcode*, by **Timothy Ford** (Lead Gameplay Programmer, Blizzard Entertainment, Team 4). Game Developers Conference 2017.
- **GDC Vault (canonical source):** https://gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and
- **Official video (GDC YouTube channel):** https://www.youtube.com/watch?v=W3aieHjyNvw
- **Related talk referenced below:** *Networking Scripted Weapons and Abilities in 'Overwatch'*, by **Dan Reed** (Blizzard Entertainment), GDC 2017: https://gdcvault.com/play/1024041/Networking-Scripted-Weapons-and-Abilities
- All ideas, examples, and results below belong to Timothy Ford and Blizzard Entertainment. Names of games and studios are trademarks of their respective owners and are used here only to identify the source.

**About these notes:** I wrote these notes in my own words after watching the talk. They are a study aid, not a transcript. Short phrases in quotation marks are the speaker's words, quoted for reference. For exact wording or context, watch the talk.

| | |
|---|---|
| Model | **Client-server, server-authoritative, client-side prediction with rollback-and-replay of inputs**, fixed 60 Hz command frames |
| Sections | ECS gameplay architecture 00:00 to 22:19 and 43:27 to 50:18; netcode 22:19 to 43:27; Q&A from ~50:18. Timestamps below are approximate video times (mm:ss) and may be offset by a few seconds on the official upload. |


This file covers the **gameplay architecture (ECS)** half of the talk. The netcode half is in the `rollback-netcode` plugin (`references/overwatch-netcode-talk/notes.md`).

## One-paragraph summary

Overwatch's gameplay code is a strict ECS. An `EntityAdmin` (the world) holds systems and entities. Entities are IDs that map to components. **Components have state and no functions; systems have functions and no state.** System state that other code needs lives in **singleton components**. Behavior shared between systems goes in **utility functions**, with strict rules that tie the number of call sites to the side effects. Big side effects are **deferred**: queued into a component and resolved once, at one point in the frame. These rules took about 1.5 years to settle. They let the team add a second world (Kill Cam) without the systems noticing, and confine netcode to a handful of systems.

## Gameplay architecture: ECS (00:00 to 22:19, plus 43:27 to 50:18)

The talk's stated goal is "techniques for reducing complexity in an ever growing codebase ... by adhering to a strict architecture"; netcode is the worked example. They found these rules over about 3 years, starting from an audited prototype engine.

### The canonical model (01:00)
- **World** = collection of systems + entities. **Entity** = an ID that maps to a set of components. **Components have state and no functions; systems have functions and no state.** "Components have no functions and systems have no fields."
- A **system tick iterates tuples** of components (the set of component types the behavior needs). A system does not know what an entity *is*; it only acts on its slice. An entity is subject to a behavior only if it has the *whole* tuple (02:43, 06:58).
- Example tick (prototype `PhysicsSystem`, 02:43): run the underlying physics world sim (Havok / Box2D / in-house "Domino"), then for each `{DynamicPhysics, Transform, Contact}` tuple, read the physics proxy and copy results into `Transform` and `Contact`.

### Overwatch's implementation (03:35)
- World = `EntityAdmin`: array of systems + hashmap of entities keyed by entity ID (`uint32`). Entity = ID + optional resource handle to its **entity definition** asset.
- `Component` is a base class with hundreds of subclasses. Polymorphism is used **only for lifetime** (create/destroy overrides). The only other methods allowed are small accessors, never behaviors.
- Deviation from canon: instead of fixed tuples, a system iterates a **primary component** and fetches **siblings** (e.g. iterate `Derp`, get sibling `Herp`). Ford regrets this (see Lessons).
- Scale: client ~46 systems / ~103 component types. Systems that touch many components should mostly **read** them as pure functions. The few systems that mutate many components must manage that complexity themselves.
- Worked system (05:16): `PlayerConnectionSystem` enforces AFK on servers. Tuple `{Connection, InputStream, Stats}`: if input shows a button press and stats show a contribution, reset the AFK timer; otherwise use the connection handle to send a warning/kick. AI bots have `Stats` but no `Connection`/`InputStream`, so they are never subject to it.

### Why separate state from behavior (06:58)
- An OOP `Connection::Update()` would have to pick one behavior, but `Connection` serves many: AFK subject, broadcast-message target list, player-name source, persistence/unlock lookup. "Connection is not an object in the OOP sense. It means different things to different systems at different times."
- **Cherry-tree analogy**: the same tree is a different subject to you, the HOA president, a gardener, a bird, a tax assessor, and a termite. It is easier to describe all behaviors of a thing when you split them by observer. Concretely: `PlayerConnectionSystem` (AFK), `ConnectionUtil` (broadcast), client UX scoreboard system (name), all over the same `Connection` state.

### Problem 1: systems that keep state (08:36)
- Legacy-ported systems had member variables, e.g. **`InputSystem` held the input state** and other systems reached it through a global accessor. Costs: **compile times** (system headers included by other systems, so refactoring one recompiles many), **coupling** (behavior leaked: `PostBuildPlayerCommand` lived in `InputSystem` although filling `PlayerCommand` is `CommandSystem`'s job, so it was unclear where new code goes).
- **Kill Cam broke it (10:58).** Kill Cam = a second pristine `EntityAdmin` fed an 8-12 s server network stream as if it came off the wire; its systems don't know they aren't live. With two admins, every "grab the global system B" call site was now wrong.
- **Fix: singleton components (11:47).** A component type with exactly one instance per `EntityAdmin`, on an anonymous entity, accessed directly through the admin. Most system state moved into singletons. Observation: state that one system "begs for" is almost always wanted by another system later, so singletons get ahead of coupling. **~40% of all components are singletons.**
- Example: `SingletonInput` holds button state. `InputSystem` still exists but only reads the OS, applies bindings and per-hero settings, and fills `SingletonInput`. `LocalPlayerMovementSystem` reads it to predict; `MovementStateSystem` reads it to package input for the server. `PostBuildPlayerCommand` moved into `CommandSystem`, so **every mutation of `PlayerCommand` happens in one file, in one update call**. "All that ambiguity goes away." (14:06)

### Problem 2: shared behavior -> utility functions (14:55)
- When several systems need the same behavior (HOA president and gardener both want the leaf count), put it in a **utility function**, not in one system that others call.
- Example: `CombatUtil::IsHostileTo(a, b)`, called by many systems. Reads only 3 optional components: `FilterBits` (team index), `PetMaster` (key shared with its pets), `Pet` (e.g. Torbjörn's turret). No `FilterBits` -> not hostile (two doors); same team -> not hostile; "hostile to everyone" team -> check pet/master pairing so your own turret doesn't shoot you; projectiles fall back to the instigator. **Small surface area and pure.**
- **The utility rules (16:32):**
  - Called from **many** sites -> must read **few** components and have **few or no side effects**.
  - Reads **many** components and has **many side effects** -> **limit call sites**. Example: `CharacterMoveUtil` moves a player one tick; called in exactly 2 places: server simulating your input, client predicting it.
- A utility function does not remove complexity by itself; it is "mostly syntactic and organizational". Side effects hidden behind a utility called from many sites are "still pretty horrible coupling."
- **The talk's headline lesson (18:10):** "Behaviors are much less complex if they are expressed in a single call site in which all major behavioral side effects are localized to that call site."

### Problem 3: big side effects -> deferment (18:10)
- When a behavior needs a big side effect, ask whether it must happen **now**. **Deferment** = store the state needed to invoke the side effect (usually in a singleton) and invoke it later at a single better moment in the frame.
- Example: impact effects. Callers include hitscan, travel-time projectiles with explosions, Zarya's channeled beam, sprays. Creating an effect is a big side effect (entity lifetime, threading, scene and resource management) plus a lot of logic: contact resolution by transform / impact type / material, culling, LOD, prioritization, and de-stacking persistent decals (a Pharah scorch mark must delete the Tracer pock marks under it to avoid z-fighting). The only real requirement is "show up before the scene renders", not "in the middle of the sim at a dozen call sites". Copy-pasted call sites multiply ("It's just a function call. No, it's not.").
- Fix (20:35): `SingletonContact` holds an array of pending contact records. Callers append a record. `ResolveContactSystem` processes all of them once per frame, before scene update / render prep. Bonus benefits: data + instruction cache locality, a **perf budget** (12 D.Vas shooting a wall: spawn the local player's effects now, smear the rest over several frames), and easy fork/join multithreading inside the one call site.
- Same pattern for damage: `ModifyHealthQueue`.
- "We constrain you. We throw you in this pit, but it is a pit of success." (22:06)

### Lessons learned (43:27)
- **Use real tuples, not primary + sibling lookups.** Explicit tuples make component access visible; a 40-component tuple warns you the system is too complex. "I kind of like the friction."
- Tuples give a priori knowledge of which systems touch which components, so systems with disjoint tuples **run in parallel**; tagging components **read-only** lets many readers run together (e.g. `Transform` is read by many, written by few). The prototype engine did this.
- **Entity lifetime**: deferred *destruction* was fine; deferred *creation* caused off-by-one-frame bugs (create in system A, can't read in system B). They switched to immediate mid-frame creation **after ship** (around patch 1.12/1.13). It made component iterators more complex; Ford calls it still an open problem.
- **The rules took ~1.5 years to settle**: components have no functions; systems have no state; shared code goes in utils; defer complex side effects by queuing them in (singleton) components; **systems don't call functions on other systems**; plus naming conventions. Old code that breaks the rules is where the churn and bugs are (measured by Perforce changes and bug counts).
- **Don't shoehorn legacy or specialist subsystems into ECS.** Keep the subsystem intact and wrap it with a **proxy component**. "ECS is a tool for integrating a bunch of systems together. It shouldn't force design principles where it isn't welcome."
- **Iceberg components**: small surface to ECS, large hidden state underneath. Examples: projectile simulation (scripting asks to spawn projectiles, worker threads simulate them out of sight of ECS) and AI path data (ECS hooks say "this breakable broke / this door opened"; underneath it voxelizes and compresses triangles with fork/join). Path data is also used by hero abilities, so it must stay in sync between client and server.
- **Closing (49:00):** ECS is "the glue of Overwatch". Define your rules of engagement early, for any architecture. Few engineers touch physics, scripting, or audio internals, but **everyone touches the glue code**, so constrain the glue. Netcode is tricky: decouple it from the rest of the engine as much as you can.

### How ECS simplified the netcode (~41:00 to 43:27)
- Netcode-relevant behavior lives in very few systems (movement, weapons/StateScript, `MovementState` handling) and mostly **reads** components. The main mutation is pushing into `ModifyHealthQueue`.
- Rewind for hit registration is a tuple behavior (anything with `MovementState`); "is shootable" is another (`IsHostileTo` + has `ModifyHealthQueue`). Rewind and damage are orthogonal behaviors on different component slices.

## Design principles (my synthesis of the talk)

1. Components hold state with no behavior; systems hold behavior with no state. Put "system state" in **singleton components** so a second world (Kill Cam, replay, resim) just works.
2. Systems never call other systems. Shared behavior goes in **utility functions**: many call sites -> few components, pure; many side effects -> very few call sites (e.g. one move function called by server sim and client prediction only).
3. Defer big side effects to a single point in the frame; it makes both rollback and multithreading tractable.
4. Use explicit component tuples, with read/write tags if possible; they make coupling visible and give you parallel scheduling for free.
5. Wrap specialist subsystems (physics, pathing, projectiles, audio) behind thin proxy components; don't force them into ECS.
6. Confine netcode (and any other cross-cutting concern) to as few systems as possible.
7. Write the rules of engagement for the glue code down early and enforce them; that's the code everyone touches.

## Q&A points worth keeping (from the Q&A after ~50:18)

- No double-buffered component state; only `InputStream` (2 s) and `MovementState` (1-2 s) ring buffers are time-scrubbable.
- Projectile hostility looks up the instigator instead of copying state (Genji deflect changes ownership).
- Entity creation was made synchronous mid-frame after ship; deferred creation caused off-by-one-frame bugs.
