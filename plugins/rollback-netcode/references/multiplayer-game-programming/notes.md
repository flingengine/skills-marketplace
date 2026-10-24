# Notes: *Multiplayer Game Programming*, Chapter 8 "Improved Latency Handling", and the *Robo Cat Action* sample

**About these notes:** I wrote these study notes in my own words after reading Chapter 8 of my copy of the book and its public sample code. They do not reproduce the book's text, figures, or code listings; for the full explanation, read the book. Function and file names refer to the authors' public sample code.

## Source and credit

- **Book:** Joshua Glazer and Sanjay Madhav, Chapter 8 "Improved Latency Handling" of *Multiplayer Game Programming: Architecting Networked Games*. Addison-Wesley Professional (Game Design series), 2015. ISBN-13 978-0-13-403430-0, ISBN-10 0-13-403430-9. Publisher page: https://www.informit.com/store/multiplayer-game-programming-architecting-networked-9780134034300
- **Sample code:** *Robo Cat Action* and every other sample is by the book's authors and is published at https://github.com/MultiplayerBook/MultiplayerBook. These notes refer to `Chapter 8/RoboCatAction` at commit `684044a` (2017-08-19). The repository has no license, so this folder links to the code and does not include a copy. All rights stay with the original authors.
- The techniques as taught, and the design, naming, and comments in the sample code, belong to Glazer and Madhav. The walkthrough below is my own reading of their code.

| | |
|---|---|
| Files here | this file, `fetch-sample-code.sh` (downloads the sample code at the pinned commit into a git-ignored `.cache/`) |
| Model | **Client-server**: dumb terminal -> client-side interpolation -> client-side prediction (dead reckoning, move prediction + replay) -> server-side rewind |

---

## Background concepts

Chapter 8 teaches these techniques. They are also standard in the industry; the public sources under Further reading are where most of them were first described.

- **Dumb terminal** (conservative): the server owns the truth. The client sends input and shows what comes back, so whatever it displays is at least RTT/2 old. The Chapter 6 build of the sample works this way (`RoboCatClient::Update` runs no simulation).
- **Client-side interpolation**: blend between received states instead of snapping to each one. It adds latency but hides a low server send rate (Bernier).
- **Client-side prediction** (optimistic): run the shared simulation forward on the client. For remote objects this is **dead reckoning** (assume they keep doing what they were doing). For the local player it is **move prediction and replay**: keep the moves the server has not acknowledged, apply the server state, then run those moves again on top (Carmack's QuakeWorld prediction, Bernier).
- **RTT from an echoed timestamp**: the client stamps each move and the server echoes back the last stamp it processed. RTT = now - stamp, so no clock sync is needed.
- **Correcting mispredictions**: snap to the server state, interpolate toward it (the sample's lerp; Caldwell covers splines), or adjust acceleration so the object drifts back gradually.
- **Cosmetic feedback first**: play cosmetic effects (muzzle flash, sounds) immediately and let authoritative effects (damage) wait for the server (Aldridge).
- **Server-side rewind** / lag compensation (Bernier): the server keeps recent poses and rewinds to what the shooter saw before it resolves an instant-hit shot. The sample does not implement this.

**Further reading** (public):
- Aldridge, David (2011). *I Shot You First: Networking the Gameplay of HALO: REACH*, GDC Vault.
- Bernier, Yahn W. (2001). *Latency Compensating Methods in Client/Server In-game Protocol Design and Optimization*, Valve Developer Wiki.
- Caldwell, Nick (2000). *Defeating Lag with Cubic Splines*, GameDev.net.
- Carmack, John (1996). *Here is the New Plan* (.plan file on QuakeWorld's client prediction).
- Sweeney, Tim. *Unreal Networking Architecture*, Epic Games (originally udn.epicgames.com).

---

## The code (`Chapter 8/RoboCatAction` @ `684044a`)

How to read the code (pick one):
- **Local:** run `bash fetch-sample-code.sh <dest-dir>` (this folder's script). The code lands in `<dest-dir>/Chapter 8/RoboCatAction/`; then use Read/Grep on it. With no argument it uses a git-ignored `.cache/` next to the script.
- **Single file:** fetch `https://raw.githubusercontent.com/MultiplayerBook/MultiplayerBook/684044a6eca80859fc4d9a69394702059476a7ff/Chapter%208/RoboCatAction/<Module>/<Inc|Src>/<File>`, for example `https://raw.githubusercontent.com/MultiplayerBook/MultiplayerBook/684044a6eca80859fc4d9a69394702059476a7ff/Chapter%208/RoboCatAction/RoboCat/Src/MoveList.cpp`.
- **Browse:** https://github.com/MultiplayerBook/MultiplayerBook/blob/684044a6eca80859fc4d9a69394702059476a7ff/Chapter%208/RoboCatAction

Each module has `Inc/` (headers) and `Src/` (sources). The files that matter here:

| Module | Files | Techniques |
|---|---|---|
| `RoboCat/` | `Move`, `MoveList`, `InputState`, `RoboCat`, `Timing`, `WeightedTimedMovingAverage` | Shared simulation (`RoboCat::ProcessInput` + `SimulateMovement`) and the move/timestamp types both sides use. `MoveList::AddMoveIfNew` (de-dupe), `RemovedProcessedMoves` (ack pruning). |
| `RoboCatClient/` | `RoboCatClient`, `NetworkManagerClient`, `InputManager`, `YarnClient` | Input sampling, redundant 3-move packets (`SendInputPacket`), RTT + pruning (`ReadLastMoveProcessedOnServerTimestamp`), replay and correction (`RoboCatClient::Read`, `DoClientSidePredictionAfterReplicationFor{Local,Remote}Cat`, `InterpolateClientSidePrediction`), dead-reckoned projectiles. |
| `RoboCatServer/` | `ClientProxy`, `NetworkManagerServer`, `RoboCatServer`, `YarnServer` | Per-client unprocessed move list, `HandleInputPacket`, `WriteLastMoveTimestampIfDirty`, state sent in response to new input. |

Short snippets below are quoted for commentary. Read the original files for full context.


Robo Cat Action is a top-down 2D UDP client-server game (SDL). Chapter 6 introduced replication and the `Move`/`MoveList` plumbing; **Chapter 8 adds prediction**. Diffing Chapter 6 against Chapter 8 shows exactly what "adding client-side prediction" touched:

| File | Chapter 6 | Chapter 8 |
|---|---|---|
| `RoboCatClient::Update` | "we don't simulate any movement on the client side, we only move when the server tells us" | Local cat: `ProcessInput` + `SimulateMovement` per pending move. Remote cat: `SimulateMovement(frame dt)` (dead reckoning). |
| `RoboCatClient::Read` | apply replicated pose | snapshot old pose, apply, then `DoClientSidePredictionAfterReplicationFor{Local,Remote}Cat` + `InterpolateClientSidePrediction` |
| `NetworkManagerClient::SendInputPacket` | sends last 3 moves then `moveList.Clear()` | sends last 3 moves and **keeps** them until acked; adds `DeliveryNotificationManager` state |
| `MoveList::AddMove(const Move&)` | always appends | renamed `AddMoveIfNew`: rejects timestamps <= last (duplicates from redundant sends) |
| `RoboCatServer::Update` | processes unprocessed moves | same, plus AI branch and dirty-pose detection |
| `NetworkManagerServer` | plain send | `DeliveryNotificationManager` + `ReplicationManagerTransmissionData` for ack-driven re-send |

### Shared data types (`RoboCat/`)

- `InputState` - desired left/right/forward/back floats + `mIsShooting`. Serialized with the move.
- `Move` - `InputState` + `mTimestamp` (client frame-start time) + `mDeltaTime` (derived, **not** serialized; recomputed on receipt as timestamp minus previous timestamp).
- `MoveList` - `deque<Move>` + `mLastMoveTimestamp`. `AddMove` (client sampling), `AddMoveIfNew` (server receipt, de-dupes), `RemovedProcessedMoves(lastProcessedTs)` (client ack handling), `GetLastMoveTimestamp` (server echo).
- `RoboCat` - the shared simulation. **`ProcessInput(dt, input)` sets rotation/thrust/shooting; `SimulateMovement(dt)` sets velocity from thrust, integrates position, runs collisions.** Comment in `AdjustVelocityByThrust`: velocity is set directly from thrust because *"simulating acceleration makes the client prediction a bit more complex"* - a deliberate determinism/prediction simplification. `Write` sends pose as a dirty-bit block (velocity, location, rotation) plus a 2-bit thrust direction every packet.
- `WeightedTimedMovingAverage` - RTT is smoothed over a 1 s window (`mAvgRoundTripTime = WeightedTimedMovingAverage(1.f)`).

### Client (`RoboCatClient/`)

**Input sampling** - `InputManager::Update` samples an `InputState` into a `Move` every **30 ms** (`kTimeBetweenInputSamples = 0.03f`), stamped with `Timing::GetFrameStartTime()`. `RoboCatClient::Update` consumes that pending move once (`GetAndClearPendingMove`) so client and server integrate the **same dt per move**.

**Sending** - every **33 ms** (`kTimeBetweenInputPackets`) `SendInputPacket` writes up to the **3 most recent moves** (2-bit count) and does not clear the list. This is the redundancy Overwatch also relies on; the server de-dupes with `AddMoveIfNew`.

**Ack + RTT** - `ReadLastMoveProcessedOnServerTimestamp` reads the echoed timestamp of the last move the server processed, sets RTT = current frame-start time - that timestamp, feeds it into the `mAvgRoundTripTime` moving average, and calls `MoveList::RemovedProcessedMoves` with the same timestamp. RTT falls out of the echoed move timestamp for free, and the same ack prunes the retained moves.

**Reconciliation** - `RoboCatClient::Read`:
1. Save `oldRotation/oldLocation/oldVelocity` (the current prediction).
2. Apply replicated pose if the pose bit is set.
3. Local cat -> `DoClientSidePredictionAfterReplicationForLocalCat`: only if a **pose** was received ("might have just gotten thrustDir, in which case we haven't warped backwards"), replay every remaining move in the `MoveList`: `ProcessInput(dt, state); SimulateMovement(dt);`. Because acked moves were already pruned, "all that are left are unprocessed moves".
4. Remote cat -> `DoClientSidePredictionAfterReplicationForRemoteCat`: `SimulateMovement` forward by **one full RTT** in 1/30 s chunks (RTT/2 is the more common figure; the sample uses RTT).
5. Unless this is a create packet (`ECRS_PlayerId` bit), `InterpolateClientSidePrediction(old..., isRemote)`:
   - If location differs: record `mTimeLocationBecameOutOfSync`; while out of sync for less than one RTT, `SetLocation(Lerp(old, new, alpha))` with **alpha = 0.1 for the local cat** (creep 10% per packet toward the corrected pose) and **alpha = durationOutOfSync / RTT for remotes** (finish the blend within one RTT). Same for velocity. This is the "interpolation" correction style, implemented as a per-packet lerp rather than a spline.
   - A rotation mismatch after replay is logged as an error: rotation is a pure function of input so replay must reproduce it exactly.
6. `RoboCatClient::Update` resets the out-of-sync timer for remotes when velocity hits zero ("we're in sync if our velocity is 0").

**Optimism for projectiles** - `YarnClient::Read` dead-reckons a newly replicated yarn ball forward by RTT (`location + velocity * RTT`) "since this was spawned a while ago", and `YarnClient::HandleCollisionWithCat` hides the sprite as soon as the *client* sees it hit an enemy cat, "whether server registered or not" - "tells / optimism" in code. Damage itself stays on the server (`RoboCatServer::TakeDamage`).

### Server (`RoboCatServer/`)

- `ClientProxy` holds one `MoveList mUnprocessedMoveList` per client plus `mIsLastMoveTimestampDirty`.
- `NetworkManagerServer::HandleInputPacket` reads the 2-bit move count and `AddMoveIfNew` each move; a genuinely new move sets the dirty flag.
- `SendOutgoingPackets` sends a state packet to a client **only when that client's dirty flag is set**, i.e. a state update goes out as a direct response to new input, which is what makes the echoed timestamp a valid RTT probe. `WriteLastMoveTimestampIfDirty` writes `bool dirty [+ float lastMoveTimestamp]` and clears the flag.
- `RoboCatServer::Update` runs `ProcessInput` + `SimulateMovement` for every unprocessed move with **the client's own per-move dt**, then clears the list, then marks `ECRS_Pose` dirty only if the pose actually changed. Server and client therefore execute the identical `RoboCat` code over the identical sequence of (input, dt) pairs - the determinism that makes replay converge.
- Reliability: `DeliveryNotificationManager` + `ReplicationManagerTransmissionData` let the server learn which replication state was lost and re-dirty it (Chapter 7 material, present here because Chapter 8 builds on it).

### What the sample deliberately leaves out (and where the other sources pick it up)

- No fixed simulation step; dt is per-move and floats (see Overwatch command frames in `../overwatch-netcode-talk/notes.md`).
- No server-side rewind for the yarn hitscan (Overwatch's backwards reconciliation and swept bounds are the production answer).
- Correction is a simple lerp; no spline or second-order smoothing.
- Remote cats are dead-reckoned, not interpolated, so the sample as-is does **not** meet the usual server-rewind prerequisite: rewind needs remotes to be *interpolated* (and the client to send which frames + fraction it was showing) so the server knows exactly what the shooter saw.

## Key vocabulary

dumb terminal; conservative vs optimistic prediction; client-side interpolation; dead reckoning; client move prediction and replay; RTT from an echoed timestamp; snap / interpolated / gradual correction; server-side rewind (lag compensation).
