# ChaosWastesAtHome tests

Two tiers, because the failures come in two kinds. Nothing here ships:
`.releaseinclude` is a whitelist of `.mod` + `scripts` + `README.md`, and
`tests` is in the deploy script's `DEFAULT_IGNORES`.

```bash
# everything: offline, then in-game if the game happens to be running
nix develop ./nix --command python3 ChaosWastesAtHome/tests/run_tests.py

# fast tier only, no game needed -- run this on every edit
nix develop ./nix --command python3 ChaosWastesAtHome/tests/run_tests.py --offline

# one or two offline files
nix develop ./nix --command python3 ChaosWastesAtHome/tests/run_tests.py -k difficulty vote
```

A closed game reports **SKIPPED**, not failed.

In-game runs **close Darktide when finished**, even if it was already running.
Cleanup also runs after test failures, exceptions, and Ctrl+C. Add `--keep-open`
to leave the game running for inspection; `--close` is accepted but no longer
required. Offline-only runs never close the game. A failed `--start` or failed
shutdown reports failure.

Runner lifecycle tests (mocked game processes):
`nix develop path:./nix --command python3 -m unittest discover -s ChaosWastesAtHome/tests -p 'test_runner.py'`.

## offline/ — LuaJIT, no game

Runs against the game's **real data**: `require` is redirected at
`references/source/Darktide-Source-Code/`, so `hordes_buffs_data` hands back its
actual 154 templates and `mission_buffs_allowed_buffs` its actual seven
families. "Every buff we offer is a real buff" therefore means something.

| file | covers |
| --- | --- |
| `test_buff_pool.lua` | the catalogue, the enabled/disabled two-set invariant, exclusions, family offering |
| `test_buff_pack_compat.lua` | independent addon startup alone/together, both load orders, disabled packs |
| `test_buff_namespaces.lua` | colliding local IDs, helper callbacks, independent text, upgrade prerequisites and factory invocation |
| `test_cwah_multishot.lua` | real CwahBuffs hooks: five-shot fans, aimed shot preservation, activation guards, recursion, error recovery, staff arrays and launch argument flow |
| `test_cwah_catalogue.lua` | nine original cards and three helpers, idempotent registration, all card translations through both formatting passes, crit and attack-speed ramp contracts |
| `test_havoc_pool.lua` | complete Havoc circumstance discovery, missing-mutator exclusion, every candidate reaching serialized mission data, distinct picks and separate environment/Fading Light rules; controlled mutator registry |
| `test_shrines.lua` | additive mutators, host/guest setup, count limits, every reference encounter composition, boss-only rewards, duplicate deaths, spawn retries/despawns, overlapping encounters, temporary area buffs and deleted-level teardown |
| `test_buff_subtabs.lua` | real view callbacks with UI stubs: default subtab, repeated switching without duplicate rows, isolated bulk toggles and refreshed details |
| `test_run.lua` | run state, `trim_pools`, and `capture`'s merge-don't-overwrite rule |
| `test_difficulty.lua` | the danger ladder, the Havoc ramp and its cap, `build_havoc_data`'s positional format |
| `test_net_vote.lua` | tallying and all three tiebreak rules |
| `test_game_mode_shim.lua` | the canary for Fatshark moving a Mortis game-mode member |

`harness.lua` supplies a fake `mod`, a fake `Managers`, and the ten or so engine
helpers (`upairs`, `settings()`, `table.make_unique` and friends) the data files
reach for at load.

**The decompile is not the shipped build.** CLAUDE.md records that for engine
*signatures*; data tables drift far more slowly, but a test here can still pass
against stale data after a game patch. The in-game tier is the authority; this
tier is the fast filter.

## ingame/ — dt-cli, game must be running

**These drive the game.** `hop.sh` starts a run and forces wins. Do not fire it
at a session you care about.

| file | covers |
| --- | --- |
| `hop.sh` | both end-screen exits, no Mourningstar, depth advances, buffs carry |
| `buff_pool.sh` | read-only: the real offer pools hold nothing you already carry |
| `custom_buffs.sh` | read-only: `template.name` and `NetworkLookup.buff_templates` |
| `activation.sh` | read-only: the buff system is never live without a launched run |
| `vox_map_vote.sh` | the VoxPopuli seam: chat owns the end-of-round vote, players' clicks are refused, and it survives the mission gate closing. SKIPs without VoxPopuli |
| `vox_map_vote_fallback.sh` | the other half of that seam: with no end screen to spare, CWaH decides for itself and the run still continues |
| `vox_map_vote_chat.sh` | the whole loop for real — posts `!2` to Twitch, waits for it to come back over EventSub, and asserts the map chat voted for is the map that launched. **Posts in your chat** |

`hop.sh` runs first, because the read-only scripts assert against a live run and
it is what produces one.

**The VoxPopuli scripts and `hop.sh` want opposite settings, and each sets its
own.** With VoxPopuli connected, CWaH hands the next-mission choice to the
viewers — so `hop.sh` would stop exercising the party/solo path it exists for.
It switches `chat_picks_mission` off for its run and restores it in a trap; the
`vox_*` scripts switch it back on rather than assuming, because a crashed run
leaves it off and every one of their assertions would then pass for the wrong
reason. A test that cannot fail is worse than no test.

**Your character is standing still in a real mission the whole time.** These
scripts force wins; they do not make anyone invulnerable, and the specials do not
know it is a test. A Trapper ended a run mid-suite once, which reads exactly like
a mod defect -- the run resets, depth drops to 0, the game returns to the
Mourningstar -- and is nothing of the kind. Before believing a failure at "the
run advanced a depth", check whether the character is still alive.

### The one rule for in-game tests

**Never `mod:io_dofile` a module that registers hooks at file scope** —
`multishot.lua`, `triggers.lua`, or `custom_buffs.lua`, which pulls in
`multishot`. `io_dofile` re-executes the file; DMF caches nothing. Every
`mod:hook` runs again, DMF drops the duplicate and logs *"Attempting to rehook
active hook"* at WARNING level — which by default goes to the player's **chat**.
It looks exactly like a mod defect and it is not: it is the harness talking to
itself. This cost most of a debugging session once.

Read state through `mod.*` accessors instead. `mod.custom_buff_id_map` and
`mod.grant_named_buff` exist for precisely this reason. `run.lua`,
`buff_pool.lua` and `difficulty.lua` register no hooks and are safe.

### Readying up without touching the keyboard

With Realms hosting, the run parks in `RealmsPreparationState` waiting for the
host to press **Ready** — and it does so at **every mission, not just the
first**. `chain.continue_run` calls `change_mechanism`, which makes Realms
re-arm the phase machine through `host_transition_started`, so mission two waits
on Ready exactly as mission one did. `lib.sh` handles it:

```lua
get_mod("Realms")._preparation.perform_action()
```

That is the same call the lobby button makes, reached through the
`mod._preparation` handle Realms parks on its own mod table. Both polling loops
call it — `wait_for_mission` for the launch and `exercise_exit` for each hop —
so no test ever needs a human at the keyboard. Readying in only one of them gets
the run started and then stalls at the first hop.

Guard it with `local_ready()` before calling, as `ready_up()` does:
`perform_action` is *"ready **or cancel** ready"*, so calling it twice un-readies
you. It is a no-op — reporting `no-preparation`, `not-waiting` or
`already-ready` — outside the lobby and with Realms absent.

Two more traps the first throwaway harness fell into, both silent:

- `mod.end_screen_up` is a **function**, not a boolean. Comparing the field to
  `true` is always false and skips whatever it was gating — which is how a
  "both exits tested" run quietly tested one exit twice.
- `player.player_unit` is a **field**, not a method. `player:player_unit()`
  throws *attempt to call method 'player_unit' (a userdata value)*.

## Checking the tests still bite

A green suite proves nothing on its own. To confirm a test would catch the thing
it names, break that thing and watch it fail — e.g. drop the per-category loop
in `run.trim_pools`, or turn `capture`'s merge into an overwrite. Both are
caught, along with four other deliberate breakages, by the mutation pass used
when this suite was written.

## Not covered

- **Multiplayer.** Every in-game test drives one instance. A guest's picker
  opening, tallies agreeing across machines, peers surviving the swap — all
  still need two instances and two accounts, and stay manual.
- **`loadouts.list()`**, which shells out to `io.popen('dir ...')` against
  Windows `cmd.exe`.
- **Engine buff effects.** Offline tests exercise selected CwahBuffs callbacks
  and hook arguments, with game stubs. Actual damage, engine stack removal,
  projectile physics and status-effect propagation still need live testing.
- **MourningBound-specific buffs.** The fork's applicable multishot and
  catalogue/localization tests were adapted to CwahBuffs; its tiers, proc
  chances and exclusive mechanics are excluded. Addon entrypoint smoke tests
  still cover both packs loading together, without loading MourningBound's
  buff catalogue.
