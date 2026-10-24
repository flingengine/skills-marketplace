# Notes: "Overwatch Gameplay Architecture and Netcode" (GDC 2017)

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

## One-paragraph summary

Overwatch runs a fixed-timestep, quantized, "deterministic enough" simulation on both client and server. The client is always ahead of the server by half RTT plus a small input buffer. The client predicts movement, abilities (via the StateScript language which can scrub time), and hit registration, keeping ring buffers of inputs and movement states. When a server snapshot disagrees with the recorded prediction for that frame, the client **restores the authoritative state and replays all inputs since then to "now"**. Packet loss is handled by a sliding window of redundant inputs and by **time dilation** (the client ticks slightly faster to refill the server's input buffer). The server uses **backwards reconciliation** (rewind targets with a movement-state component to the shooter's frame of reference) for hit registration, with extrapolation clamps at high ping. ECS keeps netcode confined to a handful of systems.

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

### How ECS simplified the netcode (~41:00 to 43:27)
- Netcode-relevant behavior lives in very few systems (movement, weapons/StateScript, `MovementState` handling) and mostly **reads** components. The main mutation is pushing into `ModifyHealthQueue`.
- Rewind for hit registration is a tuple behavior (anything with `MovementState`); "is shootable" is another (`IsHostileTo` + has `ModifyHealthQueue`). Rewind and damage are orthogonal behaviors on different component slices.

### Lessons learned (43:27)
- **Use real tuples, not primary + sibling lookups.** Explicit tuples make component access visible; a 40-component tuple warns you the system is too complex. "I kind of like the friction."
- Tuples give a priori knowledge of which systems touch which components, so systems with disjoint tuples **run in parallel**; tagging components **read-only** lets many readers run together (e.g. `Transform` is read by many, written by few). The prototype engine did this.
- **Entity lifetime**: deferred *destruction* was fine; deferred *creation* caused off-by-one-frame bugs (create in system A, can't read in system B). They switched to immediate mid-frame creation **after ship** (around patch 1.12/1.13). It made component iterators more complex; Ford calls it still an open problem.
- **The rules took ~1.5 years to settle**: components have no functions; systems have no state; shared code goes in utils; defer complex side effects by queuing them in (singleton) components; **systems don't call functions on other systems**; plus naming conventions. Old code that breaks the rules is where the churn and bugs are (measured by Perforce changes and bug counts).
- **Don't shoehorn legacy or specialist subsystems into ECS.** Keep the subsystem intact and wrap it with a **proxy component**. "ECS is a tool for integrating a bunch of systems together. It shouldn't force design principles where it isn't welcome."
- **Iceberg components**: small surface to ECS, large hidden state underneath. Examples: projectile simulation (scripting asks to spawn projectiles, worker threads simulate them out of sight of ECS) and AI path data (ECS hooks say "this breakable broke / this door opened"; underneath it voxelizes and compresses triangles with fork/join). Path data is also used by hero abilities, so it must stay in sync between client and server.
- **Closing (49:00):** ECS is "the glue of Overwatch". Define your rules of engagement early, for any architecture. Few engineers touch physics, scripting, or audio internals, but **everyone touches the glue code**, so constrain the glue. Netcode is tricky: decouple it from the rest of the engine as much as you can.

## Netcode fundamentals (22:19 onward)

### Requirements and posture
- Responsiveness needs prediction: movement, ability use (weapons are abilities), hit registration. "Player hits a button, player sees an immediate response, even at high latency." Demo at 250 ms ping is fully responsive.
- The client is trusted with **nothing but input**. Damage is not simulated on the client at all ("they're cheaters"). Hit *registration* is predicted, health bars/hit pips are not.
- Mispredictions are inevitable with server authority + lag; minimize them with **determinism**, correct them without sacrificing responsiveness. Demo: predicted Winston jump, server says "you were frozen by Mei", client is yanked back; cooldown that fired predictively is reset.
- They explicitly do *not* cover general replication, remote entity interpolation, or the details of backwards reconciliation; they assume the reader knows Quake-lineage techniques.

### Simulation model
- **Synchronized clock, fixed update, quantization.** Time is quantized into **command frames** of fixed 16 ms (7 ms in tournament config). Space quantized to 1/1024 m (~1 mm). Q&A: they are "deterministic enough to not mispredict", not strictly deterministic like an RTS; physics ("Domino") is stable across AMD/Intel/Linux/clang thanks to quantization.
- Render loop time is converted to fixed frames with an **accumulator with rollover remainder**. Systems that predict or authoritatively simulate players implement `UpdateFixed` instead of `Update`. Q&A: the sim *must* run at 60; at 30 fps render you run two sim steps per frame; if the CPU can't keep up you enter a **death spiral** (2 steps -> 48 ms -> 3 steps -> 72 ms ...). Remote-player script simulation has a time budget (~1.5 ms) to smooth spikes.

### Client ahead of server
- With a steady stream, **client clock = server clock + RTT/2 + one buffered command frame** (RTT = ping + processing). Example: 160 ms RTT -> client is 80 ms + 16 ms ahead. Client simulates and sends input for frame 19; server later simulates frame 19 with that input.
- The server keeps a **tiny buffer of unsimulated input**, as small as possible (bigger buffer = less responsive). If starved, the server **duplicates the last input** (guess) and tells the client "I lost input".

### Prediction and reconciliation (movement)
- Client keeps a **ring buffer of movement states** and a **ring buffer of inputs** (Q&A: ~2 s of inputs; ~1-2 s of movement state per mover, all in `InputStream` and `MovementState` components).
- Server snapshot for frame N arrives ~RTT later. Client compares its recorded state for N with the server's. Match -> carry on. Mismatch -> **restore movement state to the authoritative snapshot and replay all recorded inputs from N+1 to now** (character move code is deterministic given state + input). Example: frame 17 predicted running, server says stunned by McCree flashbang; client learns this at ~frame 27, rewinds to 17, replays. Once synced, both sides agree on stun duration with no further catch-up.
- Naively overwriting the client with the server state is wrong because the server state is hundreds of ms old.

### Packet loss: time dilation and sliding-window inputs
- Transport: UDP with an optional custom reliability layer; input packets are lossy.
- **Time dilation**: on "input lost" from the server, the client shrinks its fixed step (e.g. 16 -> 15.2 ms) and simulates slightly faster, so inputs arrive at the server sooner and the server's input buffer grows to weather the loss. When healthy again, the server tells the client and it dilates the other way to shrink the buffer. This feedback loop runs continuously to stay on the "razor's edge" of minimal buffer without starving. Works well with jittery real-world ping.
- **Sliding window of inputs** (QuakeWorld lineage): every packet contains *all* inputs since the last acknowledged server movement state (e.g. ack'd frame 4, just simmed frame 19 -> send 5..19). Compresses extremely well (buttons rarely change at 60 Hz). Fills holes before the server simulates them -> no mispredictions from loss as long as one later packet arrives.

### Abilities: StateScript
- All abilities authored in a declarative scripting language, **StateScript**, that can **scrub back and forth through time**. Abilities are predicted and validated exactly like movement: rewind to the authoritative snapshot, replay inputs. Demo: Reaper leaving Wraith Form - states turn off predictively, server update rewinds them on, replay turns them off again. They predict *everything* by default and must opt out. (Dan Reed's GDC 2017 talk, linked above, covers StateScript in depth.)
- Q&A: they even **predict rockets/projectiles**. A rocket can vanish on misprediction (fired, then stunned) but "predicting rockets is rad... just do it."

### Hit registration
- ECS tuple logic: an entity is shootable if hostile (`FilterBits`/`PetMaster`/`Pet` via `CombatUtil::IsHostileTo`) and has a `ModifyHealthQueue`. Anything with a `MovementState` component (doors, payloads, platforms, heroes) is **rewound** to the shooter's frame of reference on the server (**backwards reconciliation**) before hit tests; damage is a separate deferred behavior. Rewind and damage are orthogonal behaviors on different component slices.
- Remote entities are positioned by interpolating between the last two received movement states (standard since Quake).
- Optimization: each mover has a **bounding volume of its last ~0.5 s of positions**; the server ray-tests those bounds first and only rewinds entities whose swept bounds the shot intersects.
- Shots mispredict when movement mispredicts (e.g. Mei ice wall raised you; you fired from the wrong height). Most hit-mispredict bugs were **position agreement** bugs. Reproducing a hit mispredict required 60% packet loss for 20 minutes; QA insisted on this precision.
- **Favor the shooter**, unless the victim did something to mitigate (Reaper Wraith Form -> invulnerable; the shooter's predicted blood shows but no hit pip/health change). Rationale: the victim who *saw* their ability fire must not die anyway.
- **High-ping clamps**: above ~220 ms RTT, hit impacts stop being predicted (wait for server ack) and rewind depth is clamped; beyond the clamp the server **extrapolates** the target instead of rewinding, so victims aren't shot after ducking behind cover. At 1 s ping the local client is still fully predicted and "mostly wrong".

### Misc netcode facts
- Kill cam = second EntityAdmin fed a recorded network stream; systems don't know they aren't live.
- Nav-mesh rebuilds are deterministic given the same inputs but not rolled back (40 MB); few abilities depend on it; server authority catches mistakes.
- A debugger exists that flags server/client disagreement per frame and lets you scrub to the movement state that caused it; "almost always the ray that finds where your feet are."

## Design principles (my synthesis of the talk)

1. Fixed-step, quantized simulation shared by client and server; think in **command frames**, not seconds.
2. Client runs **ahead** by RTT/2 + buffer; keep the buffer minimal and self-tuning (time dilation).
3. Keep **input history and state history** as ring buffers; reconcile by **restore + replay inputs**, never by overwriting with stale server state.
4. **Redundant sliding-window inputs** are cheap and eliminate most loss-induced mispredictions.
5. Predict everything the player does (movement, abilities, projectiles, hit *feedback*), predict nothing that costs others (damage, health).
6. Server-side **lag compensation** (backwards reconciliation) with **clamps + extrapolation** at high ping; favor the shooter with explicit victim-mitigation exceptions.
7. Defer big side effects to a single point in the frame; it makes both rollback and multithreading tractable.
8. Confine netcode to as few systems as possible; most of the game should not know it is networked.
9. Components hold state with no behavior; systems hold behavior with no state. Put "system state" in **singleton components** so a second world (Kill Cam, replay, resim) just works.
10. Systems never call other systems. Shared behavior goes in **utility functions**: many call sites -> few components, pure; many side effects -> very few call sites (e.g. one move function called by server sim and client prediction only).
11. Use explicit component tuples, with read/write tags if possible; they make coupling visible and give you parallel scheduling for free.
12. Wrap specialist subsystems (physics, pathing, projectiles, audio) behind thin proxy components; don't force them into ECS.
13. Write the rules of engagement for the glue code down early and enforce them; that's the code everyone touches.

## Q&A points worth keeping (from the Q&A after ~50:18)

- No double-buffered component state; only `InputStream` (2 s) and `MovementState` (1-2 s) ring buffers are time-scrubbable.
- Projectile hostility looks up the instigator instead of copying state (Genji deflect changes ownership).
- Entity creation was made synchronous mid-frame after ship; deferred creation caused off-by-one-frame bugs.
- Sim must run 60 Hz; death spiral risk; per-remote-player script budget.
- Quantization 1/1024 m; deterministic across compilers/platforms because of quantization.
- Misprediction smoothing hides small non-determinism; a timeline debugger finds the rest.
