# Notes: "8 Frames in 16ms: Rollback Networking in Mortal Kombat and Injustice 2" (GDC 2018)

## Source and credit

- **Talk:** *8 Frames in 16ms: Rollback Networking in Mortal Kombat and Injustice 2*, by **Michael Stallone** (Lead Software Engineer, Engine, NetherRealm Studios). Game Developers Conference 2018.
- **GDC Vault (video + slides, the canonical source):** https://gdcvault.com/play/1025021/8-Frames-in-16ms-Rollback
- **Official video (GDC YouTube channel):** https://www.youtube.com/watch?v=7jb0FOcImdg
- **Slides:** the 65-slide deck on GDC Vault. Slide numbers below refer to that deck.
- All ideas, numbers, and results below belong to Michael Stallone and NetherRealm Studios. Names of games and studios are trademarks of their respective owners and are used here only to identify the source.

**About these notes:** I wrote these notes in my own words after watching the talk. They are a study aid, not a transcript. Short phrases in quotation marks are the speaker's words, quoted for reference. For exact wording, context, or a figure, watch the talk.

| | |
|---|---|
| Model | **Peer-to-peer, deterministic lockstep -> rollback (GGPO-style)**, 1v1, hard 60 Hz |
| Anchors | `slide N` = slide number in the GDC deck |

## One-paragraph summary

NetherRealm shipped a patch (Mortal Kombat X "Game of the Year" patch, later Injustice 2) that swapped their online model from delay-based lockstep to rollback. Both models send **only gamepad input**; the game is bit-for-bit deterministic. Rollback lets the game keep simulating with predicted remote input, then when real remote input arrives it **restores** a saved state at the confirmed frame and **re-simulates** forward to the present, all inside one 16.66 ms frame. They fixed input latency at 3 frames and support 7 frames of rollback (10 frames / 333 ms RTT total, covering >99% of matches). The engineering cost was 7-8 man-years, mostly **performance** (idle CPU went from 9-10 ms to 30+ ms naively) and **desync chasing**.

## Terminology (slides 4-5)

- **RTT** round-trip time A->B->A. **Network latency** one-way.
- **Netpause** game pauses because no remote data arrived within the supported window.
- **QoS** connection-quality metric; exceeding it for a while disconnects.
- **Input latency** injected delay between button press and engine response.
- **Confirm(ed) frame** most recent frame for which input from *all* players is known.
- **Desync** clients disagree on state -> disconnect.
- **Dead reckoning** the other common model (extrapolate remote state; usually server-authoritative). Not used here.

## The problem and the two models

- Fighting games need constant, predictable input cadence. Old lockstep had **dynamic input delay** (5-20 frames) that rubber-banded with RTT over the match. Players hated it.
- **Lockstep** (slide 10-11): send pad data; don't advance until remote input for the current frame exists; delay local input by enough frames to cover latency. Simple, visually smooth, performant, robust, low bandwidth. Not responsive; a single late packet stalls and the delay adjustment persists for seconds.
- **Rollback** (slide 14-15): send pad data; proceed without remote input (predict "same input as last frame"); when remote input arrives, restore to the confirmed frame and simulate forward. Responsive, robust once mature, low bandwidth, **single-frame latency** (a spike only affects the frames it actually delays; recovery is immediate). Costs: not simple, visual pops, heavy CPU.
- Comparison matrix (slide 16): Lockstep wins Simple/Visually smooth/Performant; both Robust/Low bandwidth; Rollback wins Responsive/Single-frame latency.
- Shipped numbers: **3 frames fixed input latency + 7 frames rollback = 10 frames (333 ms) before netpause**. Worst case = 8 simulated frames in 16.66 ms (hence the title). Latency curve (slide 13): vast majority of matches < 300 ms RTT; most matches are 4-5 frames of latency, i.e. only 1-2 frames of actual rollback after the 3-frame static delay.

## How they built it (chronological)

1. **First milestone: an idle character rolling back.** Turn off physics, IK, particles, even online. Build serialization (save/restore) first. Debug command `SetRollbackFrames 7`: every frame rolls back 7 frames and resimulates; success = "nothing visibly happens". Everyone ran with it on, always.
2. **Tick timeline** (slide 18): `Input & Online (fixed cost) -> Restore -> simulated frames 0..6 (stripped-down sim) -> "real" tick (full sim incl. procedural/visual systems) -> Render`. One render per frame regardless of rollback depth.
3. **Serialization: Save** (slide 19): ring buffer sized to rollback window (7 entries); object serialization virtual interface; entries for object creation/destruction (rolling back across create/destroy edges is a major pain); only save **mutable** data; not delta-based. Save buffer size: measured in KB to ~1 MB per frame.
4. **Serialization: Restore** (slide 20): parallel restore with load balancing/priority (2.7 ms -> 1.3 ms for 2x the data). **Cannot use `shared_ptr`**: shared ownership needs a second "serialization owner" concept; they moved to `unique_ptr`. Waking threads via condition variables was slow (consider warm threads/spinlocks). Single-threaded **post-serialization fixup** pass re-links pointers for systems that were not serialized (asymmetric relationships). Prefer bulk memcpy and immutable data.
5. **Object lifetime** (slide 21): two strategies.
   - *Deferred deletion*: objects stay alive until their death time leaves the rollback window. Easier, usually faster, but destructor code is dangerous and you should use handles.
   - *Delete and recreate*: default behaviour; slow unless pooled; more serialization; follows normal ctor/dtor patterns.
6. **Recreatables** (slide 22): hash the creation context per type; when re-simulating across a creation edge, if the hash matches, reuse the existing object instead of re-creating. Essential for **non-deterministic** things (sounds, GPU particles): re-creating them would visually/audibly pop every rollback.
7. **Gameplay script** (slide 23): proprietary fiber-based C-like "MK script". Needed fiber stack unwinding and stack serialization; stack objects with dynamic allocations were wrapped and registered for separate cleanup because the stack memory is just zeroed on restore.
8. **Rollback artifacts** (slide 24): visual pops when divergence is large; usually minor or invisible. They treat *all* remote input as significant and roll back on every received packet (a smarter input filter could skip non-gameplay-affecting input). Never roll back across a camera cut, cinematic, or a fatality; that is a UX rule, not a technical one. Q&A: they tried blending into the corrected pose; **it felt worse** (foot sliding, delayed correction). QA preferred instant snap.

## Performance war (slides 26-50) - where most of the man-years went

- Before: idle 9-10 ms CPU. After naive rollback: **30+ ms**. Headroom from the console generation was gone; lots of idle cores.
- Tools: platform profilers, in-house **job graph visualizer**, **rollback loop / "super pause"** (when a frame exceeds ~15-16 ms, pseudo-pause and resimulate the same frame forever so you can attach a profiler), PET profiler with function thresholds, performance bots.
- Shipped Injustice 2 idle: **13 ms** for a 7-frame rollback. Spike frames (e.g. Green Arrow mesh/particle spawn) 21 ms. Note: **a spike persists for up to 8 frames** because each resim replays it; "bog is no longer a function of a single frame".
- Early MKX capture: 32 ms. The cost is dominated by the **simulated frames**, not the final render tick, so optimizations must be **multiplicative** (help all 8 frames) to matter.
- Step 1 "Turn off everything cool" during simulated frames: physics/cloth, non-gameplay raycasts, IK, particles, online, desync detection. Run them once on the render tick (or on the confirmed frame). Consequence: game code that queried procedural results (bone positions) desynced -> lesson "drive visuals, don't depend on them".
- Step 2 easy wins: no strcmp; don't do X eight times (controller polling, GC); opt objects/systems out of simulated-frame updates (environment isn't gameplay-affecting); death by a thousand cuts: dynamic allocs, pointer chasing, **walking sparse lists** (iterating 100% of objects to do work on 5%). Bulk allocation/serialization of animation state saved 0.5 ms.
- Step 3 hard wins: **promotable resimulation behaviour** (latent objects become gameplay-affecting only when needed, but you must know 7 frames in advance so both peers agree); aggressive parallelization; task-graph optimization (critical path 6 ms -> 3 ms doing more work); async UI/audio ticking; automatic emitter parallelization (originally done by hand per effect, then computed offline); animation pre-sampling; simplify common graphs; JIT graph type changes; remove false dependencies; more job priority levels. Simulated-frame job graph is far sparser than the render-frame graph: ~0.5 ms per sim frame vs ~2 ms full tick, bound by animation sampling.
- Threading lessons (slide 43): contention from non-cooperative threads (render/UI/audio) is real; manage priorities/affinities; don't oversubscribe; drop priority for latency-tolerant work; watch inversion/starvation; primitives can cost more than they save (prefer the cooperative task graph); use move semantics to avoid atomic refcount traffic on handle copies.
- **KEY INSIGHT (slide 45): you only need to save the confirmed frame.** You can only ever roll back to a frame you had everyone's input for. Big worst-case win; makes the average case *worse* (you roll back further than strictly needed), which they accepted because only the 16.66 ms worst case matters. 32 ms -> **12 ms**.
- **Particles** (slides 48-50) were the worst spike source. Heavy caching, deferred async init, automatic emitter parallelization, ~100 MB runtime particle cache to avoid runtime spawn. Per-particle **resim modes** designers had to tag:
  - `RESIM_ALWAYS` - N sims, 1 serialization (for effects that can't handle variable time steps).
  - `RESIM_NEVER` - simulate only on render frame.
  - `RESIM_PREDICTIVE` - simulate on confirm frame and render frame (a midpoint + endpoint); relies on variable-timestep support; **became the default**.
  - `RESIM_NOT_TRACKED` - 1 sim, 0 serialization (fire-and-forget environment stuff, never undone).
  - **Predictive Particle Cache (PPRS)**: loose hash each frame (player roughly same place, script roughly same state); if sim inputs match the cache entry, reuse the object untouched with a lightweight side serialization buffer. "Extremely effective"; template for anything that doesn't have to be perfect (visual/audio only, never gameplay).

## Checking the work, beta, and tuning (slides 52-57)

- They had benchmarked the impossible worst case (`SetRollbackFrames 7` every frame). Real humans press buttons ~6x/sec at most, so 7-frame rollbacks are rare. QA said ship it.
- **Netpauses feel far worse than bog.** Fix: **Frame Lengthening** - stretch frames slightly (e.g. 10 frames at 20 ms instead of 16.6 ms) instead of hard pausing; max ~2 ms/frame injected, only near the latency cap.
- Beta: ~20k users, 95% "as good or better".
- **Curveball**: telemetry showed most matches had one player rolling back the max every frame. Cause: a **performance feedback loop** - one peer gets ahead, the other bogs, bogs more, rolls back max forever. Fix: artificially slow the player who is ahead (reuse frame lengthening) whenever they are >~1.5 frames ahead of the opponent. (My note: the same principle as Overwatch's time dilation.)
- **Speculative saves ("spec saves")**: save the confirm frame (mandatory); also save near the simulation midpoint if time permits, **biased toward the confirmed frame** (predictions closer to the past are more likely to be confirmed); save at end of frame if time permits. Thresholds live-tunable. Reduced total rollback count by **30%**, mainly by avoiding "RB2 / buffer exhaustion rollbacks" (confirmed frame about to fall off the ring buffer forces a full-depth rollback even with no divergence).

## Desyncs and tooling (slides 58-60)

- More complexity -> more desyncs; biggest cause was gameplay code depending on procedural systems (IK) that were now off during simulation.
- Determinism enables **offline desync reproduction**: replay captured pad input with the recorded network delays on one kit, deterministically reproduce the match, add breadcrumb fenceposts after the fact, iterate. "Completely invaluable."
- Tools: desync detection/logging (fencepost thousands of values per tick), replay files, **DesyncUtil** (any dev pulls desyncs from the wild for the last day/week), **NRSSoak** (nightly online soak on every kit in the building, desyncs logged to a server). Final desync rate < 0.1% (speaker thinks < 0.01%).

## Lessons learned (slides 61-62, paraphrased)

Low level:
- Limit mutable state.
- Prefer handles over pointers where perf allows (handles skip post-restore fixup and allow asymmetric rollback relationships).
- Avoid shared ownership of mutable resources.
- Avoid work in constructors/destructors (they no longer run when you expect).
- Lean on memcpy/buffer swaps instead of dynamic fixup.

High level:
- **Design game systems to drive visual state, not depend on it.**
- **Design systems to update with variable time steps; parametrically is even better** (update once instead of 8 times).
- **Everyone works with debug rollback enabled**, always.
- **Defer processing until after the rollback window if reasonable** (respond to an event 7-8 ticks late and it can never be rolled back: pause menu, cinematics).
- Bog is no longer a function of a single frame.

Future work: multithread gameplay script; state-based serialization (serialize once on state change, not every frame); parametric particles; separate game state from visual state; rollback support for more systems.

## Q&A points worth keeping

- Budget before: ~10 ms idle. The exercise was shrinking the deterministic segment and optimizing it simultaneously.
- Blending into corrected pose felt worse than snapping.
- No gameplay/frame-data rebalancing was needed; most matches only see 1-2 frames of rollback.
- Man-year breakdown: ~4-5 optimization, ~1 desync chasing, ~1-2 serialization infrastructure.
- Many particles were rolled back for visual correctness, not determinism; PPRS meant they mostly stopped rolling back.
- PC (outsourced) netpauses more often because frame time is fuzzier; bog also changes your effective RTT -> feedback loops.
- Save state per frame: KBs to ~1 MB.

## How this source maps to the rest of the bundle

These links are my own comparisons and are not claims made in the talk.

- Same "save, restore, resimulate" loop as Overwatch (`../overwatch-netcode-talk/notes.md`), but **peer-to-peer and fully deterministic** rather than server-authoritative.
- Frame lengthening / slowing the leading peer is the same correction as Overwatch's time dilation and GGPO's TimeSync sleep (`../ggpo-networking-source/notes.md`).
- "Only save the confirmed frame" + "spec saves" is an optimization on top of GGPO's save-every-frame policy.
- "Defer until after the rollback window" is the same idea as Overwatch's deferred side effects.
