# Chaos Wastes at Home

Brings the Mortis Trials buff system into regular **solo** missions. You pick a
buff family when you spawn, then earn family buffs and legendary card picks as
you play, driven by whatever triggers you turn on.

## How it works

Almost none of this is reimplemented. Fatshark's mission-buffs system is
already constructed in every non-hub mission — `GameModeCoopCompleteObjective._init_buff_system`
builds a `MissionBuffsManager`, the `hordes_buff_*` templates are registered
globally in `BuffTemplates`, and the `ConstantElementMissionBuffs` card UI is
loaded for every `in_mission` session. What a regular mission gets is the plain
base manager, which can grant buffs but has no selector, no pools and no UI.

The mod swaps that one object for `HordeMissionBuffsManager`, the survival
subclass. That brings the rest of the system with it: buff families, legendary
pools with per-archetype/ability/talent filtering, the three-card choice UI and
its timeout, buff-received notifications, and persistence across downs and
respawns. It also self-starts — the coop game mode already fires
`mission_buffs_event_player_spawned`, which is what creates the opening family
choice.

Three things the mod has to supply:

1. **A game-mode shim** (`game_mode_shim.lua`). The buff system reaches into the
   game mode for wave/island bookkeeping that a regular mission does not have:
   `get_current_wave`, `get_last_wave_completed`, `get_islands_completed`,
   `is_wave_in_progress`, `can_start_wave_one`,
   `wait_for_players_to_choose_family` and the `_waves_completed` field. The
   stubs report "wave 0", which is the state Mortis itself runs in before wave
   1: notifications are never gated on a between-wave pause, and the
   "WAVE N COMPLETED" banner never renders.

2. **One UI gate hook**. `ConstantElementMissionBuffs._is_player_in_mission`
   hard-codes `game_mode == "survival"`; without overriding it the element
   force-inactivates itself every frame.

3. **A backend bypass**. `HordeMissionBuffsManager` asks the title backend for
   family weights and a deactivated-buff list. Solo has no session to ask, so
   the mod installs the same defaults the stock failure path uses (even
   weights, nothing excluded) and skips the request.

## Triggers

Mortis paces buffs off waves. A regular mission has none, so grants are driven
by sources you enable in the mod options. Each has its own roll chance and its
own choice of what it hands out; if that kind is used up for the mission, the
other kind is granted instead.

| Source | Fires on | Default |
|---|---|---|
| Mission objectives | any objective completing (side missions optional) | on, legendary pick |
| Kills | a configurable count of all / elite+special / special / monster kills | off, family buff |
| Elapsed time | a fixed interval in minutes | off, family buff |
| Event clears | the last active terror event ending | off, family buff |

Per-mission budget defaults to Mortis's own island economy: 3 legendary card
picks and 7 family buffs. Set either to 0 to disable that kind entirely.

The objective trigger is the recommended default — it paces with the mission
and needs no per-map tuning. The event trigger watches the terror-event count
drop to zero rather than hooking `stop_event`, because events normally complete
inside `TerrorEventManager.update`; `stop_event` is only the forced-stop path.

## Solo only

The mod refuses to activate unless the session is `HOST_TYPES.singleplay`. This
is deliberate and not configurable: on a hosted session the buff system sends
`rpc_client_mission_buffs_*` to every remote player, and a client running the
stock `MissionBuffsManager` has never registered those events. Enabling this
with other people in the session would break their game, not just yours.

Bots are unaffected — every path in the buff system checks
`is_human_controlled()`.

## Commands

- `/cw_buff [family|legendary]` — grant one now, for testing.
- `/cw_status` — how many of each this mission has handed out.

## Install

```bash
python ChaosWastesAtHome/deploy.py
```

Then add `ChaosWastesAtHome` to `mods/mod_load_order.txt`. That file is managed by
Vortex on this machine, so add it through Vortex rather than editing the file
by hand if you want the change to survive a Vortex deploy.

## Caveats

- A few hordes buffs assume horde-mode context (`hordes_buff_ogryn_basic_box_spawns_cluster`
  is granted automatically to Ogryns with the box grenade;
  `hordes_buff_damage_immunity_after_game_end` is survival end-of-run only).
  They are harmless here but were written for a different mode.
- Buff titles and descriptions resolve as `loc_<buff_name>_title` /
  `_description` from the game's own localization, so they render the same as
  they do in Mortis.
- Enabling several triggers at once will hit the per-mission budget quickly.
  The budget is the real balance lever, not the trigger count.
