# Player-buff sharing: measured join boundary

Implementation update: `recipe_sync.lua` now uses this measured lobby window.
See [player-buff documentation](player-buffs.md) for current behavior; the design
and limitations below describe the earlier investigation, not the finished
implementation. The first version used deferred host-only append registration;
it has now been replaced by 64 reserved card/helper slot pairs, pre-game menu
previews, and teardown-gated host-catalogue replacement without restarting.

## Result (2026-09-15)

The installed Realms public mod-network API works in the preparation lobby,
before gameplay. CWaH can exchange validated recipe data there without changing
Realms. This is after the lobby connection, not literally before any connection.
The important safety boundary is before gameplay/player buff replication.

Two live probes passed:

1. An already-connected host/peer transitioned from gameplay to preparation.
2. Both games cold-started through their separate Steam accounts, and the peer
   joined only after the host was waiting unready in preparation. Attempt 1
   encountered the known native rel32 error; attempt 2 succeeded with the current
   10-second initial delay / 5-second retry policy.

In both probes, the host sent a 97-byte text recipe through `network_send`, the
peer parsed one definition and compiled two entries with zero errors, and sent
an acknowledgement back. On the fresh probe the peer also invoked both template
factories successfully, creating the controller and carrier tables in memory.
Both endpoints reported preparation phase `waiting`, no `Managers.state.game_session`,
and 2771 entries in `NetworkLookup.buff_templates`. Neither probe registered or
applied a buff, changed saved recipes, or readied a player. Diagnostic handlers
and temporary getters were removed/restored; both games were left in the lobby.

Reproduce from the workspace, with both Steam clients signed in:

```bash
nix develop path:./nix --command python3 -B scripts/probe-recipe-lobby.py --fresh
```

Without `--fresh`, the probe requires an existing two-player session and moves
it to preparation. This ends the current test run. It leaves games open.

## Source findings

- Realms `core/mod_network.lua` runs over `core/session_control.lua`, not a
  gameplay-only RPC bus. Registration publishes capability manifests; a send
  can fail until the peer has published its registered RPCs. Do not treat host
  `network_is_available()` alone as proof a recipient can receive the message.
- Session control uses `rpc_check_mechanism` / `rpc_check_mechanism_reply` on
  connection channels. Its handshake does not require a gameplay session.
- The installed protocol limits are 96 KiB per encoded message, fragmented into
  500-byte frames. A raw 64 KiB recipe file is not necessarily below the encoded
  limit after JSON escaping. Use bounded canonical records/chunks, not a blind
  raw-file send. Only a small payload was exercised in these probes.
- Preparation exposes `is_waiting`, `local_ready`, `is_finalizing`, `phase`,
  and `mission_name`. Its update starts gameplay after readiness/countdown and
  profile finalization. A production synchronization barrier must cover this
  transition, not merely the test runner's ready button.
- `user_buffs.lua` currently reads once at startup, registers local recipes,
  and explicitly restricts their use to authoritative singleplay. Multiplayer
  support is still disabled; this investigation does not lift those guards.
- `buff_registry.lua` appends numeric network IDs. Sorting names only makes a
  particular registration batch deterministic; it cannot reconcile previously
  registered divergent local catalogues. Copying text alone is insufficient.
- `buff_recipes.lua` compiles a controller plus carrier per recipe. Its current
  shared `active` dependency includes host authority and feeds both proc logic
  and carrier conditional stats. Multiplayer needs separate authority and
  synchronized-session gates so clients don't disable received carrier effects.
- The reference `PlayerUnitBuffExtension._add_rpc_synced_buff` sends template IDs
  for remote players and can queue them before game-object creation. Waiting
  until a spawned-player compatibility exchange is too late for unknown IDs.

## Recommended CWaH-only design (not implemented)

1. Host freezes a versioned recipe manifest for its run. Transfer schema-limited
   data only; the existing parser/compiler builds trusted template logic locally.
2. Peer joins the preparation lobby. Keep gameplay blocked while the host sends
   the manifest and each peer validates/compiles it and acknowledges the exact
   manifest revision, definition signatures, and network mappings.
3. Use a deterministic session recipe namespace/slot allocation independent of
   each player's saved recipes. A bounded reserved controller/carrier slot set
   is a candidate for the existing 64-recipe limit; its actual registration order
   and full lookup compatibility still need design and tests. Never overwrite
   unrelated IDs or renumber active instances.
4. Keep imported run definitions separate from each player's `buffs.txt` and
   saved menu toggles. Treat the host manifest as authoritative for this run;
   preserving a received recipe permanently should be a separate explicit action.
5. Gate host readiness/finalization until every participating client is verified.
   Missing support, malformed data, timeouts, and mismatches must not silently
   start gameplay with partially installed templates. Preserve lobby-only joins;
   do not allow a hot join to bypass the barrier.
6. Lock definitions during a run, carry the acknowledged snapshot through hops,
   and rebuild only at a safe lobby boundary for a different host/revision.

Still unproven: dynamic registration and ID reconciliation with divergent local
recipes, replication of actual recipe procs/stacks/expiry, malformed/oversized
payload rejection, multiple recipients, readiness races, and reconnect/host
switch cleanup. The successful general CWaH/Vox regression covers transport and
ordinary buffs, not these new recipe-specific behaviours.
