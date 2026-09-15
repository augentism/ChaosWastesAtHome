# Player-created buffs

Build buffs in **Buffs / Debuffs → Player Buff Editor**, or write recipes
in a plain UTF-8 text file. Each recipe pairs one event
trigger with one timed, stacking stat effect. CWaH makes it a reward card in
the **Player Buffs** category of Rollable Buffs. Creating a recipe makes it
available to roll; you still need to acquire its card during the run.

## File location

CWaH creates a commented example on first startup at:

```text
%APPDATA%/Fatshark/Darktide/ChaosWastesAtHome/buffs.txt
```

Under Steam/Proton this is inside the game's prefix:

```text
steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/ChaosWastesAtHome/buffs.txt
```

`/cw_recipes` in chat reports the actual path, loaded count and errors.
Definitions load as data at startup. The starter
is entirely commented and adds no cards until you uncomment or add recipes.
The file survives mod updates.

## In-game editor

Select a personal recipe from the scrollable left-hand list, or choose **New buff**.
Edit its stable ID, name, trigger, effect, strength, stack cap and duration in
the middle column; chance, cooldown and enabled status are optional. The right
column previews the effect and validates changes as you type. **Save** validates
and writes it; **Delete** asks for confirmation. Selecting another buff, reloading,
or switching away asks before discarding unsaved changes. Editing a draft does
not change a buff until you save it. The editor replaces the old Mod Options form.

**Include in your catalogue** enables the recipe. **Legendary card pick** is
checked by default; uncheck it for a random regular family reward instead.
These recipes supplement any chosen family's ordinary pool, not its priority
buffs. Player Buffs stays a menu category rather than a starting family.

Outside a run, saving refreshes the Player Buffs menu immediately. Once a run
launches (including its preparation lobby), its catalogue is frozen through all
mission hops. You can still save edits, but they apply to the **next session**.
The editor always edits your personal recipes, never the connected host's data.

After editing the file externally, choose **Reload file**; no game restart
or DMF mod reload is needed. Invalid reloads preserve the last valid catalogue.
Saves refuse to overwrite externally changed files until you reload them.
The editor rewrites the file in canonical format, including disabled recipes;
comments and original formatting are retained in the previous-file backup
`buffs.txt.bak`. Replacement is staged and atomic. Fix any existing parse errors
before saving from the editor, so invalid blocks cannot be silently discarded.

## Example

```ini
[momentum]
name = Veteran's Momentum
trigger = elite_kill
effect = attack_speed
amount = 2
max_stacks = 5
duration = 10
chance = 100
cooldown = 0

[last_stand]
name = Last Stand
trigger = toughness_broken
effect = damage_reduction
amount = 10
max_stacks = 3
duration = 15
```

Momentum grants +2% attack speed on an elite kill. Five stacks give +10%.
Last Stand grants a 10% incoming damage reduction per stack when toughness
breaks. Its three stacks multiply together: `0.9 × 0.9 × 0.9 = 0.729`, or
27.1% damage reduction from this recipe.

To test a card in a singleplay CWaH run, enter `/cw_give` to list registered
custom card IDs, then use `/cw_give <full_id>` with the listed recipe ID.
This command takes the internal ID, not the display name.

## Rules

- Each successful trigger adds **one stack** and resets the **shared timer**.
  It also refreshes the timer at the stack cap. Chance failures and events
  during cooldown do neither. All stacks expire together; stacks do not each
  have their own timer and do not decay one at a time.
- The acquired card persists across missions. Temporary effect stacks start
  empty in each new mission and rebuild from triggers.
- The `[id]` is permanent: use 1–48 lowercase letters, digits and underscores,
  starting with a letter. Changing `name` does not change the ID. Renaming the
  ID makes a new card and leaves old loadout toggles referring to the old one.
- `name` is optional (defaults to the ID), with a 120-byte limit. Values are
  unquoted text: write `name = Momentum`, without quotation marks.
- Lines starting with `#` or `;` are comments. Blank lines are ignored. Comments
  must occupy their own lines. UTF-8 BOM and Windows CRLF files are accepted.
- A malformed block is skipped with a line-numbered error; other valid blocks
  still load. Duplicate fields reject the block. Duplicate IDs reject both
  definitions. Unknown fields and trigger/effect IDs are errors.
- Saved definitions are shared across your loadouts; each loadout retains its normal
  Rollable Buffs toggles. `enabled = false` removes a definition from registration
  on the next catalogue activation, independently of those toggles.
- Limits: 64 definitions and 64 KiB per file. Unsupported components on a
  different game build are skipped with an error.

| Field | Meaning | Allowed values |
| --- | --- | --- |
| `trigger` | Event granting a stack | One ID below; required |
| `effect` | Stat changed by each stack | One ID below; required |
| `amount` | Positive percentage per stack | 0.01–500, subject to effect limits; required |
| `max_stacks` | Maximum simultaneous effect stacks | Integer 1–31; required |
| `duration` | Shared stack lifetime in game seconds | 0.1–600; required |
| `chance` | Chance per qualifying event, in percent | 0.01–100; default 100 |
| `cooldown` | Minimum game seconds between successful triggers | 0–600; default 0 |
| `enabled` | Whether to include this recipe in your catalogue | `true` or `false`; default `true` |
| `legendary` | Legendary pick (`true`) or random regular family buff (`false`) | `true` or `false`; default `true` |

Percentages are written as numbers: `amount = 2` means 2%, not 200%.
Crit chance uses **percentage points**: `amount = 2` adds two points per stack.
These numbers describe this recipe's contribution; talents and other buffs
still combine according to the game's own stat rules.

## Triggers

| Kind | IDs |
| --- | --- |
| Hits | `hit`, `melee_hit`, `ranged_hit`, `weakspot_hit`, `critical_hit`, `melee_critical_hit`, `ranged_critical_hit`, `noncritical_hit`, `heavy_hit`, `backstab_hit` |
| Enemy hits | `elite_hit`, `special_hit`, `elite_or_special_hit` |
| Kills | `kill`, `melee_kill`, `ranged_kill`, `weakspot_kill`, `critical_kill`, `elite_kill`, `special_kill`, `elite_or_special_kill` |
| Taking damage | `damage_taken` (health or toughness), `health_damage_taken`, `toughness_broken` |
| Defence and movement | `dodge` (starting a dodge), `successful_dodge`, `slide` (starting a slide), `block`, `perfect_block`, `block_broken`, `push` (finishing a push) |
| Weapon actions | `shoot`, `melee_swing` (finishing a swing), `reload`, `reload_finished`, `wield_melee`, `wield_ranged` |
| Abilities and pickups | `ability_used`, `grenade_thrown`, `ammo_pickup` |

These use native buff events. A hit is an event per struck target, so one
cleaving attack can grant several stacks. Use `cooldown` to limit bursts.
`melee_swing` counts a completed swing even if it misses. `reload` follows the
native reload event (including individual rounds on applicable weapons);
`reload_finished` follows the completed reload action. Weapon and ability
mechanics determine which events occur; an ammo-free weapon will not gain
reload stacks, for example.

## Effects

All effects are temporary stats applied to the card's owner. There are no
instant heals, enemy debuffs, spawned attacks, or continuous-state triggers
in this version.

The total limit in the table means `amount × max_stacks`, except reductions.
These bounds prevent runaway values from a misplaced decimal or stack count.

| Kind | IDs | Limit |
| --- | --- | --- |
| Damage | `damage`, `melee_damage`, `ranged_damage`, `melee_heavy_damage`, `warp_damage`, `burning_damage` | +500% total |
| Precision | `weakspot_damage`, `melee_weakspot_damage`, `ranged_weakspot_damage`, `critical_strike_damage`, `melee_critical_strike_damage`, `ranged_critical_strike_damage`, `backstab_damage` | +500% total |
| Enemy categories | `damage_vs_elites`, `damage_vs_specials`, `damage_vs_monsters`, `damage_vs_horde`, `armored_damage`, `super_armor_damage`, `unarmored_damage` | +500% total |
| Enemy ailments | `damage_vs_bleeding`, `damage_vs_burning`, `damage_vs_electrocuted` | +500% total |
| Impact/stagger | `melee_impact_modifier`, `ranged_impact_modifier`, `push_impact_modifier` | +500% total |
| Speed/regeneration | `attack_speed`, `melee_attack_speed`, `ranged_attack_speed`, `reload_speed`, `wield_speed`, `stamina_regeneration_modifier` | +200% total |
| Movement | `movement_speed`, `sprint_movement_speed`, `dodge_distance_modifier` | +100% total |
| Rending | `rending_multiplier`, `melee_rending_multiplier`, `ranged_rending_multiplier` | +100% total |
| Crit chance | `critical_strike_chance`, `melee_critical_strike_chance`, `ranged_critical_strike_chance` | +100 percentage points total |
| Dodge speed | `dodge_speed` | `amount × max_stacks` at most 100; stacks multiply |
| Reductions | `damage_reduction`, `toughness_damage_reduction`, `melee_damage_reduction`, `ranged_damage_reduction`, `block_cost_reduction`, `sprint_cost_reduction`, `corruption_reduction` | 95% per stack; stacks multiply |

## Multiplayer boundary

Realms runs use **only the host's catalogue**. Each player's `buffs.txt` is read
at startup and is immediately visible in the Player Buffs menu. With Realms
installed, startup reserves 64 dormant card/helper slot pairs, independently of
personal definitions. The menu previews do not allocate network IDs.
In the preparation lobby, the host fills the slots with its catalogue and sends
canonical recipe data to the clients. Clients validate and register it, check
the base lookup and resulting template IDs/signatures, and acknowledge it.
Manual ready-up and host finalization wait for those acknowledgements.

Your own saved file is never overwritten by a host. Host recipes are session
data; they are not automatically saved as your recipes. The host's cards appear
under the separate **Player Buffs** menu category, not as a starting family.
Other buff packs must still match: recipe transfer does not distribute mod code.

**First-version restrictions:** all participants need this CWaH synchronization
code and the current Realms lobby transport. Join while the host is unready in
the preparation lobby. Hosts with recipes reject in-progress engine admission.
After leaving, a new host's catalogue (or your own when you host) can replace
the slot contents without restarting. Replacement requires the previous game
session, extension systems and CWaH manager to have torn down. A host cannot
change its catalogue mid-session. Network IDs are never renumbered or removed;
unused slots become dormant and old card/pool entries are cleared. Menu toggles
use recipe IDs, not reusable slot numbers. Saves and reloads during a run only
change the personal catalogue for the next session.
Missing support or mismatched catalogues keep the lobby blocked; `/cw_recipes`
reports the status. There is no automatic timeout that bypasses this barrier.

Recipe triggers remain authoritative on the host. Their temporary stat carriers
replicate to the owning client and remain active there in a synchronized CWaH
mission. Outside an enabled CWaH session, their effects stop contributing.
Without Realms, singleplay uses the same reserved slots and teardown safety gate.

The [network investigation](player-buffs-network-investigation.md) records the
transport measurements preceding this implementation.

## Implementation

`buff_recipes.lua` owns the component registries, parser and compiler.
`user_buffs.lua` loads the AppData file, supplies menu previews, reserves slots
and gates replacement on gameplay teardown.
`recipe_sync.lua` owns the lobby transfer, acknowledgements, and readiness gates.
`view/recipe_view.lua` owns the three-column editor, live preview and confirmations;
`view/recipe_dropdown.lua` adapts the engine dropdown using the Emperor's Touch pattern.
`recipe_editor_widgets.lua` supplies shared component labels; `recipe_editor.lua`
retains the script-facing draft API. `recipe_store.lua` handles conflict checks,
backup and staged file replacement. `run.lua` captures the catalogue at launch.
Each enabled recipe compiles to a permanent controller card plus a temporary
stat carrier. Both use the existing CWaH buff registration API. The carrier
uses native stack caps, duration and refresh behaviour. Text is parsed as data;
it is never passed to `loadstring` or evaluated as Lua.
