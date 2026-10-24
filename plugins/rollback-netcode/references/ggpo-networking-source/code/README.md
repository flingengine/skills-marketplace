# GGPO source subset

GGPO by Tony Cannon, Copyright (c) 2009-2019 GroundStorm Studios, LLC. Copied unmodified (only line endings differ) from https://github.com/pond3r/ggpo at commit `7ddadef8` (2019-11-07) and redistributed under the MIT License (see `LICENSE`, which must stay with these files). This README is our own index, not the upstream one. Build files, platform shims, zlib headers and the Windows GDI renderer are omitted; everything that implements rollback is here.

| Path | What it is |
|---|---|
| `include/ggponet.h` | The public C API: `GGPOSessionCallbacks`, `ggpo_start_session`, `ggpo_add_local_input`, `ggpo_synchronize_input`, `ggpo_advance_frame`, `ggpo_idle`, `ggpo_set_frame_delay`, `GGPONetworkStats`, event codes, error codes. Heavily commented; read first. |
| `doc/Overview.md`, `doc/DeveloperGuide.md`, `doc/*.png` | Official docs: lockstep vs speculative execution diagrams, integration walkthrough, best practices, SyncTest. |
| `lib/sync.*` | Rollback driver: saved-state ring, prediction barrier, `CheckSimulation` / `AdjustSimulation` (load + replay). |
| `lib/input_queue.*` | Per-player input ring with repeat-last-input prediction, first-incorrect-frame tracking, frame delay. |
| `lib/game_input.*`, `lib/bitvector.*`, `lib/ring_buffer.h` | Input bit container, nibble bit-writer used for delta compression, fixed ring buffer. |
| `lib/timesync.*` | Frame-advantage averaging and sleep recommendation. |
| `lib/backends/p2p.*` | Peer-to-peer session: confirmed-frame computation, spectator feed, TIMESYNC events, disconnects. |
| `lib/backends/synctest.*` | Single-machine determinism test (save, rewind, replay, compare checksums). |
| `lib/backends/spectator.*` | Spectator session (receives confirmed inputs, no rollback). |
| `lib/network/udp_msg.h`, `udp_proto.*`, `udp.*` | Wire format, handshake, input packets with bit-delta compression and full unacked history, acks, quality reports, keep-alive, disconnect timers, fake latency/out-of-order injection. |
| `lib/main.cpp`, `lib/backends/backend.h`, `lib/poll.h`, `lib/types.h` | C API to backend dispatch, backend interface, poll sink interface, basic types. |
| `vectorwar/` | Sample game: `GameState` (rolled back) vs `NonGameState` (not), the seven callbacks, main loop with `ggpo_idle`, SyncTest toggle. |

See `../notes.md` for the walkthrough.
