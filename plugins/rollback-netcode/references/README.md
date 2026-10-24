# Network latency-hiding source notes

These are study notes on rollback, client-side prediction, and lag compensation, for agents to use as references. Each folder has one `notes.md`, which starts with a **Source and credit** section that names the original authors and links to the canonical source. The notes are in my own words. They do not replace the original talks, book, or code.

| Folder | Source | Authors | Credit and license |
|---|---|---|---|
| `mk-rollback-talk/` | *8 Frames in 16ms: Rollback Networking in Mortal Kombat and Injustice 2*, GDC 2018 | Michael Stallone (NetherRealm Studios) | Notes only. [GDC Vault](https://gdcvault.com/play/1025021/8-Frames-in-16ms-Rollback) |
| `overwatch-netcode-talk/` | *'Overwatch' Gameplay Architecture and Netcode*, GDC 2017 (netcode half; the ECS half is in the `gameplay-architecture` plugin) | Timothy Ford (Blizzard Entertainment) | Notes only. [GDC Vault](https://gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and) |
| `multiplayer-game-programming/` | *Multiplayer Game Programming: Architecting Networked Games*, Ch. 8 (Addison-Wesley, 2015), and its *Robo Cat Action* sample | Joshua Glazer, Sanjay Madhav | Notes only. The sample code has no license, so it is linked at a pinned commit and is not copied. Run `fetch-sample-code.sh` for a local copy. |
| `ggpo-networking-source/` | GGPO rollback SDK | Tony Cannon / GroundStorm Studios, LLC | Notes + an unmodified subset of the source under the MIT License (`code/LICENSE`). |

## Rules for this folder

- Write notes in your own words. Quote only short phrases, attribute them, and give a slide number or timestamp.
- Do not commit transcripts, slide text, photos or scans of books, or code that has no license. Link to them instead.
- Put third-party code here only if its license allows redistribution, and keep its LICENSE file with it.
- Mark cross-source comparisons as your own analysis, not as claims from a source.
