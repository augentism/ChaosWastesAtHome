# Chaos Wastes at Home

Turns **solo** Darktide into a Chaos Wastes–style run: start a crusade from the
Mourningstar, pick a buff family when you spawn, earn Mortis Trials buffs as you
play, and at the end of each mission choose one of three next missions. Your
buffs carry over. The difficulty climbs every mission. Losing ends the run.

## Requirements

- **Darktide Mod Framework**
- Nothing else. The mod launches its own solo sessions — SoloPlay is **no longer
  required**, though it can stay installed without conflicting.

Optional: **Tertium4Or5** if you want bots. Runs are solo with no team by
default; see *Bots* below.

## Install

1. Extract into `Warhammer 40,000 DARKTIDE/mods/` so you get
   `mods/ChaosWastesAtHome/`.
2. Add `ChaosWastesAtHome` to `mods/mod_load_order.txt`, or enable it through
   Vortex. **A mod not listed there is silently never loaded.**
3. Bind **Open the Chaos Wastes menu** in the mod options. One key does
   everything.

## How a run works

1. In the Mourningstar, press your menu key. The launcher offers a **difficulty
   slider** — Malice, Heresy, Damnation, Auric, then Havoc 25 / 30 / 35 / 40 —
   and **three missions** rolled at that difficulty. Reroll if you like.
2. Press **Begin the run**. The mission loads. On spawn you choose a **buff
   family**, the same three-card screen Mortis Trials uses.
3. As you play you earn buffs. By default a completed objective grants a
   legendary card pick; kills, a timer, and terror-event clears can also be
   switched on as sources.
4. Finish the mission and the end screen offers **three next missions**. Pick one
   and you go straight there with your buffs intact. The first card is
   pre-selected, so pressing continue keeps the run going.
5. Each mission is one rung harder. Non-Havoc missions each roll a random
   **maelstrom** modifier. Havoc missions roll two modifiers, carry the Emperor's
   Fading Light, and scale their modifier loadout by rank exactly as real Havoc
   does.
6. **Dying ends the run.** So does quitting to the Mourningstar.

### Runs are opt-in

The mod only takes over missions **you started from the launcher**. Ordinary
solo play is left completely alone — no buff cards, no chaining. If you have
SoloPlay installed and launch a mission with it, this mod stays out of the way.

## The menu

One keybind, and what it opens depends on where you are:

| Where | What opens |
|---|---|
| Mourningstar | **Start a Crusade** — the launcher, with a **Rollable Buffs** tab |
| In a run | **Buffs Collected** — everything you are carrying, with the game paused |
| Anything already open | Closes it |

**Rollable Buffs** lists every buff that can be rolled, grouped by family and by
class, with its icon and real description. Almost everything is on by default;
switch anything off and it stops appearing in buff choices for good. A few are
off to begin with and shown as such — switch one on and it joins the pool.

## Bots

Runs are **solo with no team** by default. The base game would otherwise fill
your squad with three bots, so this actively suppresses them.

Turn on **Bring bots** to play with them instead. **Tertium4Or5** is the
recommended companion: it lets you choose which of your own characters take the
bot slots, and can raise the team size. With bots enabled this mod does not touch
bot spawning at all, so Tertium4Or5 behaves normally.

## Solo only, deliberately

The mod refuses to run outside a singleplay session, and this is not
configurable. The buff system sends network messages to every other player in the
session, and a client without this mod has not registered them — enabling it in a
hosted game would break other people's game, not just yours.

## Options worth knowing

Everything is in the mod options menu.

| Option | Default | Notes |
|---|---|---|
| Open the Chaos Wastes menu | unbound | **Bind this first** |
| Bring bots | off | On = the game's bots fill the squad; see above |
| Ramp difficulty each mission | on | Off keeps the run at its starting difficulty |
| Load Mortis assets | on | Needed for buff icons and effects; ~0.5s warm, ~3s on the first load after launching the game, once per run |
| Extra seconds on the end screen | 30 | Solo end screens are very short by default |
| Custom buff frequency | 1 | How often the mod's own buffs come up, relative to the shipped categories |
| Havoc theme circumstance chance | 50% | Hunting grounds / ventilation purge / toxic gas |
| Buffs per mission | 3 legendary, 7 family | Per mission, not per run — deep runs stack up fast |
| Pause while choosing | on | Freezes the game **and holds the card countdown**, so nothing is auto-picked. Off = stock 30s timer |
| Debug logging | off | Turn on before reproducing a problem. Also enables a periodic custom-buff snapshot in the log |

There are also unbound keybinds under **Testing** to end a mission instantly as a
win or a loss, for exercising the chain without playing a whole map.

## Custom buffs

`scripts/mods/ChaosWastesAtHome/custom_buffs.lua` adds nine buffs of its own, in
their own **Custom** category so you can weight or disable them as a group:

- **Wrath Unbound** — a flat damage increase (a plain stat buff). **Off by
  default**: it was written to prove the registration path worked, and a blanket
  damage multiplier is not what the run is meant to be about. Turn it on in
  **Rollable Buffs** if you want it
- **Bulwark** — toughness on elite kills (a proc buff)
- **Building Fury** — crit chance ramps on every non-crit, resets when you crit
- **Relentless** — attack speed ramps per hit, resets after 2 seconds idle
- **Contagion** — applying a status effect applies a second one at random
- **Flayer** — every hit has a flat chance to burst the target's skull
- **Proliferation** — an afflicted enemy's death spreads its status effects to
  everything nearby
- **Chain Lightning** — hits have a chance to arc through nearby enemies,
  damaging and electrocuting each. An enemy the lightning just passed through
  briefly cannot start another arc, so chains spread outward instead of
  ping-ponging between the same two targets
- **Multishot** — ranged weapons fire five shots in a fan for one round.
  Shotguns are left alone; they already do this

The file is commented as a worked example of each shape. To add your own, see
**[docs/adding-custom-buffs.md](https://github.com/augentism/ChaosWastesAtHome/blob/master/docs/adding-custom-buffs.md)** — the five
registrations a buff needs, the buff shapes, and an index of every failure mode
encountered building these, including the two that crash only when a buff is
*applied* rather than offered and the one that quietly grinds the frame rate to
nothing.

## Known issues

- **Horde spawn crash.** A base-game spawn-point query can fail in solo play and
  crash the game. It is not caused by this mod, but the mod catches it and skips
  that horde rather than letting it kill the session. `/cw_status` reports how
  many times it happened.
- **TrueSoloQoL's auto-restart** restarts a failed mission instead of letting it
  end, which makes runs unloseable. The mod warns once in chat if it detects
  this. Turn that setting off for runs to work properly.
- Buff budgets are per mission, so long runs get very strong. Tuning welcome.

## Reporting a problem

Turn on **Debug logging**, reproduce it, then send the console log from:

```
%APPDATA%\Fatshark\Darktide\console_logs\
```

Take the newest file. The log records every buff granted, every mission
transition, and both guard counters, which is usually enough to identify the
cause without a repro.

With debug logging on, the mod also writes a **custom-buff snapshot** every ten
seconds — which buffs you are holding, your live ramp stacks, and how many times
each one has fired. It only writes when something has changed, so it does not
bury the rest of the log. You do not need to run anything to produce it; if a
buff is misbehaving, the sequence of snapshots usually shows it directly.

## Commands

| Command | What it does |
|---|---|
| `/cw_menu` | Opens the right menu for where you are |
| `/cw_launch` | The run launcher (Mourningstar only) |
| `/cw_buffs` | The rollable-buffs menu |
| `/cw_status` | Buffs granted this mission, plus any guard activity |
| `/cw_buff [family\|legendary]` | Grant one now |
| `/cw_give [name or search]` | Grant a specific buff; with no exact match it searches |
| `/cw_verify` | Print the custom-buff snapshot now (it is also logged passively — see below) |
| `/cw_win` / `/cw_lose` | End the current mission (testing) |

## Credits

- Simplified Chinese and Russian translations contributed by players.
  Russian covers every string; Simplified Chinese covers most of them, and
  anything missing falls back to English. The mod's own custom buffs are named
  and described in code and are English-only in every language — updated
  translations welcome.
