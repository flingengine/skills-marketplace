# Notes: GGPO (Good Game Peace Out) rollback networking SDK

## Source and credit

- **Project:** GGPO, created by **Tony Cannon**. Copyright (c) 2009-2019 GroundStorm Studios, LLC (http://ggpo.net). Released as open source in 2019 under the **MIT License**.
- **Repository:** https://github.com/pond3r/ggpo. Snapshot analyzed: commit [`7ddadef`](https://github.com/pond3r/ggpo/tree/7ddadef8546a7d99ff0b3530c6056bc8ee4b9c0a) (2019-11-07).
- **Redistributed files:** `code/` holds an unmodified subset of that commit (only line endings differ), redistributed under the MIT License. The license text is in `code/LICENSE` and must stay with the files. `code/README.md` is our own index, not the upstream README.
- The design and algorithms belong to Tony Cannon and GroundStorm Studios. The commentary below is my own reading of their code and docs.

| | |
|---|---|
| Size | ~7,700 lines C++ total; the rollback core (`sync`, `input_queue`, `timesync`, `udp_proto`, `p2p`, `synctest`) is under 3,000 lines. |
| Files here | `code/` (core library, public header, docs with diagrams, VectorWar sample), this file |
| Model | **Peer-to-peer deterministic rollback with optional fixed input delay**, 2-4 players, plus spectators and a single-machine determinism test (SyncTest) |
| Users | Widely used in fighting games (for example *Skullgirls* and *Street Fighter III: 3rd Strike Online Edition*). NetherRealm's in-house system (see `mk-rollback-talk/`) follows the same design. |

GGPO is the canonical reference implementation of the model NetherRealm described at GDC. Where the MK talk gives you the war stories and performance numbers, GGPO gives you the *exact algorithms* in ~3k lines: how prediction, confirmation, rollback depth, frame delay, time sync and input compression actually work. Read this alongside `mk-rollback-talk/notes.md`.

## The contract GGPO imposes on a game (Developer Guide)

Three requirements:
1. **Fully deterministic simulation**: same state + same inputs -> identical next state on all machines.
2. **Game state fully encapsulated and serializable** (save/load a byte buffer).
3. **Advance exactly one frame without rendering** (used during rollback).

Seven callbacks in `GGPOSessionCallbacks`, all mandatory: `begin_game` (deprecated), `save_game_state(buffer, len, checksum, frame)`, `load_game_state(buffer, len)`, `log_game_state` (for SyncTest diffs), `free_buffer`, `advance_frame(flags)` (called N times during a rollback; inside it you must call `ggpo_synchronize_input` then step, then `ggpo_advance_frame`), `on_event` (connection lifecycle + `TIMESYNC`).

Per-frame game loop (VectorWar `RunFrame`):
```
ggpo_idle(ms_left_in_frame)                 // network pump, may trigger rollbacks
ggpo_add_local_input(handle, &input)        // may fail: PREDICTION_THRESHOLD -> do NOT advance this frame
ggpo_synchronize_input(inputs[], &dc_flags) // fills every player's input (confirmed or predicted)
AdvanceGameState(inputs)                     // deterministic step
ggpo_advance_frame()                         // GGPO saves state here
Render()
```
`ggpo_synchronize_input` must be called every frame *including rollback frames*, and the game must use its outputs rather than the raw controller (during rollback it returns the historical inputs; with frame delay it returns delayed inputs).

Best practices from the guide (all re-appear in the MK talk):
- Isolate game state from non-game state; a single C struct makes save/load a `memcpy` (VectorWar: `GameState gs` vs `NonGameState ngs`, the latter explicitly "should not be rolled back").
- **Fixed time quanta** per frame even if rendering is variable.
- Separate update from render; defer effects and sounds generated during rollback (audio: keep generating, render only after rollback, offset by frames elapsed).
- Deterministic RNG, seeded identically, **RNG state is part of game state**.
- No wall-clock in game state (or make one peer's clock an *input*).
- Rebase pointers on load; prefer base+offset over pointers (== NetherRealm "handles over pointers").
- Hunt static/hidden state.
- **Run SyncTest constantly** on developer machines.

## Architecture (doc/Overview + code)

```
ggponet.h (C API)  ->  backend (GGPOSession vtable)
                           |- Peer2PeerBackend  : Sync + N x UdpProtocol(+TimeSync) + Udp + Poll
                           |- SyncTestBackend   : Sync only, single machine, re-runs every frame
                           `- SpectatorBackend  : receives confirmed inputs from a host, no rollback
Sync         : saved-state ring + InputQueue per player + rollback driver
InputQueue   : per-player input ring (128), prediction, first-incorrect-frame tracking, frame delay
UdpProtocol  : handshake, input packets, acks, quality reports, keep-alive, disconnect timers
TimeSync     : frame-advantage averaging -> "sleep N frames" recommendations
Udp / Poll   : dumb socket + timer/wait loop
```

### Sync (`lib/sync.cpp`) - the rollback driver

- Saved states: `SavedFrame frames[MAX_PREDICTION_FRAMES + 2]` ring (8 + 2 = 10 slots), each `{buf, cbuf, frame, checksum}` owned by the game via `save_game_state` / `free_buffer`.
- **Saves every frame** in `IncrementFrame()` (and once at frame 0). This is the simple policy NetherRealm started with and later optimized to "confirmed frame + speculative saves".
- `AddLocalInput`: rejects input when `frames_behind = framecount - last_confirmed_frame >= max_prediction_frames` (8). That is the **prediction barrier**; the game must stall that frame (GGPO's equivalent of a netpause). Otherwise stamps `input.frame = framecount` and pushes to the local queue.
- `SynchronizeInputs`: for each player, `InputQueue::GetInput(framecount)` -> confirmed input if present, else a prediction. Disconnected players get zeroed input plus a bit in `disconnect_flags`.
- `CheckSimulation` (called from `DoPoll`): asks every queue for its `GetFirstIncorrectFrame()`, takes the minimum, and if any exists calls `AdjustSimulation(seek_to)`.
- `AdjustSimulation`: `_rollingback = true; LoadFrame(seek_to); ResetPrediction(seek_to); for count times: callbacks.advance_frame(0); _rollingback = false;`. `LoadFrame` finds the saved slot by frame number, calls `load_game_state`, resets `framecount`. Each `advance_frame` re-enters the game which calls `ggpo_synchronize_input` (now confirmed inputs where available, fresh predictions beyond) and `ggpo_advance_frame` (which re-saves).
- `SetLastConfirmedFrame(frame)` discards queue entries older than `frame - 1`.

### InputQueue (`lib/input_queue.cpp`) - prediction and error detection

- Ring of 128 `GameInput` per player (`GameInput` = frame + up to 9 bytes x 2 players of button bits).
- **Prediction rule: repeat the last received input** (`_prediction = _inputs[PREVIOUS_FRAME(_head)]`). Frame 0 or an empty queue predicts all-zero. Prediction is sticky: once predicting, every later request returns the same bits until real input arrives.
- `AddInput` -> `AddDelayedInputToQueue`: if predicting and the arriving real input differs (`!_prediction.equal(input, bitsonly=true)`), record `_first_incorrect_frame` (only the first). If the arriving frame equals `_last_frame_requested` and nothing was wrong, drop out of prediction mode; otherwise advance `_prediction.frame`.
- `GetInput` asserts `_first_incorrect_frame == NullFrame`: nobody may fetch inputs while a known misprediction is outstanding; `CheckSimulation` must roll back first.
- **Frame delay** lives here: `AdvanceQueueHead` adds `_frame_delay` to the local frame number. If delay was *increased* mid-game it pads by duplicating the last input; if *decreased* it drops inputs that would land in the past. `ggpo_set_frame_delay` must be called before the first `synchronize_input` in practice, but the queue tolerates changes.
- `DiscardConfirmedFrames` never discards past `_last_frame_requested` (a frame currently being used).

### UdpProtocol (`lib/network/udp_proto.cpp`) - transport, redundancy, compression

Message types: `SyncRequest/SyncReply` (5-round-trip handshake with random cookies and a per-endpoint magic number), `Input`, `InputAck`, `QualityReport/QualityReply` (ping + frame advantage, every 1000 ms), `KeepAlive` (200 ms).

- **Input redundancy = send everything unacknowledged.** `_pending_output` (ring of 64) holds every local input since the last ack; `SendPendingOutput` writes *all* of them into one packet starting at `start_frame`. An `Input` packet also carries `ack_frame` (last input received from the peer) and `peer_connect_status[]` (each player's last known frame and disconnect flag) so N-player sessions converge on a common confirmed frame. Same idea as Overwatch's sliding window and the textbook's "last 3 moves", taken to its logical end.
- **Bit-delta compression**: inputs are encoded as changes vs. the previous input: for each frame, for each button whose bit differs from the previous frame, emit `1, on/off, button-index nibblet`; then a `0` terminator. Unchanged frames cost one bit. Decoder (`OnInput`) walks frames from `start_frame`, skips those already received, applies deltas to `_last_received_input`, and emits one `Event::Input` per new frame. Max 4096 compressed bits per packet.
- Retry: if no input packet has been received for 200 ms, resend pending output. Out-of-order packets (sequence distance > 2^15) are dropped; a debug "rogue out-of-order packet" injector and `ggpo.network.delay` simulated latency exist for testing.
- Disconnect: `disconnect_notify_start` (default 750 ms) fires `CONNECTION_INTERRUPTED` with the remaining time; `disconnect_timeout` (default 5000 ms) fires `Disconnected`. VectorWar uses 1000/3000. A disconnect rolls the simulation back to the disconnected player's last confirmed frame and zeroes their input from then on.
- RTT = `now - pong` from quality replies. `SetLocalFrameNumber` estimates the remote frame as `last_received_input.frame + RTT * 60 / 1000` and defines **local frame advantage = remoteFrame - localFrame** ("how many frames *behind* the other guy we are... it's an advantage because they'll have to predict more often").

### TimeSync (`lib/timesync.cpp`) - keeping peers level

- 40-frame windows of local and remote frame advantage (remote advantage arrives in quality reports).
- `recommend_frame_wait_duration`: average both; if `local >= remote` do nothing (only the peer that is ahead acts, and **both must agree who is ahead**). Otherwise `sleep_frames = round((remote - local) / 2)`; ignore if `< MIN_FRAME_ADVANTAGE (3)`; clamp to `MAX_FRAME_ADVANTAGE (9)`. Optional `require_idle_input` refuses to sleep while the player's last 10 inputs were changing (don't stall mid-fireball motion).
- P2P backend polls this every `RECOMMENDATION_INTERVAL = 240` frames and raises `GGPO_EVENTCODE_TIMESYNC {frames_ahead}`; the game decides how to slow down. VectorWar literally `Sleep(1000 * frames_ahead / 60)`; NetherRealm's frame lengthening (spread ~2 ms/frame) and Overwatch's time dilation are the smooth versions of the same correction.

### Peer2PeerBackend (`lib/backends/p2p.cpp`) - the confirmed frame

- `DoPoll` (from `ggpo_idle` and after every `IncrementFrame`): pump sockets -> deliver `Event::Input` into `Sync::AddRemoteInput` -> `Sync::CheckSimulation` (rollback if needed) -> compute **`total_min_confirmed`** = minimum over all players of the last frame everyone has input for (`Poll2Players` / `PollNPlayers` via `peer_connect_status`) -> push confirmed frames to spectators -> `Sync::SetLastConfirmedFrame` -> maybe emit `TIMESYNC`.
- `AddLocalInput`: refuses during rollback (`IN_ROLLBACK`) or before sync (`NOT_SYNCHRONIZED`); returns `PREDICTION_THRESHOLD` when the barrier is hit; otherwise updates `_local_connect_status[queue].last_frame` and `SendInput` to every endpoint.
- `MAX_PREDICTION_FRAMES = 8`, `GGPO_MAX_PLAYERS = 4`, `GGPO_MAX_SPECTATORS = 32`, spectators receive confirmed inputs every `GGPO_SPECTATOR_INPUT_INTERVAL = 4` frames.
- Limitation noted in code: a disconnected local player is inferred from "endpoint not initialized"; spectators can only be added before the session starts.

### SyncTestBackend (`lib/backends/synctest.cpp`) - determinism harness

Single-player session that runs every frame twice: it saves state each frame, and every `check_distance` frames (recommended 1) rewinds to `_last_verified` and replays with the *recorded* inputs, comparing the saved checksum of each frame with the replay's checksum. On mismatch it writes `synclogs/state-NNNN-original.log` and `state-NNNN-replay.log` via `log_game_state`, plus per-frame `ggpo_log` output, then `DebugBreak()`. This is the engineering answer to "how do I find hidden state": run it all the time (VectorWar's `SYNC_TEST` define feeds `rand()` as input). NetherRealm's `SetRollbackFrames 7` debug mode and offline desync replay are the same discipline.

### VectorWar sample (`code/vectorwar/`)

Minimal but complete integration: `GameState` (POD, memcpy'd) vs `NonGameState` (connection UI state, checksum display); Fletcher-32 checksum of the whole state each frame (displayed, and periodic every 90 frames, to spot desyncs by eye); `FRAME_DELAY 2`; `advance_frame` callback re-synchronizes inputs and steps; `TIMESYNC` handled with a blocking sleep; main loop gives GGPO the idle time until the next 16.6 ms tick.

## What GGPO adds to the bundle's doctrine

- **The prediction rule is "repeat last input"**, and mispredictions are detected at *input* level, not state level: the first frame whose real input differs from the prediction is the rollback target. The game never compares state between peers (only SyncTest does, locally).
- **Rollback target = first incorrect frame**, not necessarily the confirmed frame; but you can only ever land on a frame you saved, and GGPO saves every frame. NetherRealm's "only the confirmed frame needs saving" is the memory/CPU optimization on top of this; spec saves recover the average case.
- **Prediction barrier** (8 frames) is a hard stall, exposed to the game as an error code. Design your own netpause presentation (NetherRealm: frame lengthening).
- **Frame delay and rollback are complementary knobs** exposed as one number: the guide's advice is to set delay as high as the genre tolerates (1 for fighters, 4-5 for puzzle games) because rollback depth = latency - delay, and short visual events (a 2-frame flash) can be swallowed entirely by a rollback.
- **Fairness** is symmetric: both peers measure frame advantage, exchange it, and only the leader sleeps, by half the difference, with hysteresis (>= 3 frames) and a cap (9).
- **Everything unacked goes in every packet, bit-delta compressed.** With inputs changing a few times per second, a 60 Hz input stream costs a handful of bytes.
- **N-player confirmation** is the min over all peers' `last_frame` for every player, carried in every input packet; disconnects are folded into the same table so remaining peers agree on the frame from which a player's input becomes zero.
- **SyncTest**: build the determinism harness into the SDK, not the game.

## Numbers

| Constant | Value |
|---|---|
| `MAX_PREDICTION_FRAMES` / `GGPO_MAX_PREDICTION_FRAMES` | 8 |
| Saved-state ring | 10 slots (prediction frames + 2) |
| `INPUT_QUEUE_LENGTH` | 128 inputs per player |
| `GAMEINPUT_MAX_BYTES` x `GAMEINPUT_MAX_PLAYERS` | 9 x 2 bytes of buttons |
| `_pending_output` / `_send_queue` / event queues | 64-entry rings |
| `MAX_COMPRESSED_BITS` | 4096 per input packet |
| Handshake | 5 sync round trips; retry 500 ms first, then 2000 ms |
| Running retry / keep-alive / quality report / stats | 200 / 200 / 1000 / 1000 ms |
| Disconnect notify / timeout defaults | 750 / 5000 ms (VectorWar 1000 / 3000) |
| TimeSync window / min / max / interval | 40 frames / 3 / 9 / every 240 frames |
| Players / spectators / spectator input interval | 4 / 32 / every 4 frames |
| VectorWar frame delay | 2 |

## Relationship to the other sources

| Concept | GGPO | NetherRealm | Overwatch |
|---|---|---|---|
| Authority | none (P2P) | none (P2P) | server |
| What triggers rollback | remote input != predicted input | remote input arrives (all treated as significant) | server state != predicted state |
| Rollback target | first incorrect frame (saved every frame) | confirmed frame (+ spec saves) | frame of the snapshot |
| Window | 8 frames + frame delay | 7 + 3 delay | ring buffers ~1-2 s |
| Level the peers | TimeSync sleep recommendation | frame lengthening / throttle leader | time dilation |
| Loss handling | resend all unacked, bit-delta | transport tricks (not covered) | sliding window of inputs |
| Determinism tooling | SyncTest + checksums + synclogs | fenceposts + replay files + DesyncUtil + soak | server/client disagreement debugger |
