# Chaos Wastes at Home

Turns Darktide into a Chaos Wastes–style run: start a crusade from the
Mourningstar, pick a buff family when you spawn, earn Mortis Trials buffs as you
play, and at the end of each mission choose one of three next missions. Your
buffs carry over. The difficulty climbs every mission. Losing ends the run.

Solo out of the box, and **playable with friends** through the Realms mod — see
*Playing with other people* below.

## Requirements

- **Darktide Mod Framework**
- Nothing else. The mod launches its own sessions — SoloPlay is **no longer
  required**, though it can stay installed without conflicting.

Optional:

- **Realms 0.4.0 or later** (by deluxghost) to play a run with other people.
  Load it **above** this mod in `mod_load_order.txt`. 0.4.0 is required, not
  merely recommended — it is what lets a run change mission without
  disconnecting anyone. Realms' own **Enable Realms server** setting is
  respected: switch it off and runs chain through the Mourningstar exactly as
  they do without Realms installed. Realms needs a Darktide Mod Framework from
  August 2026 or later; on an older one it fails to load with a
  `'type' field must contain valid widget type name` line in the log and is
  simply absent, with no other warning.
- **Tertium4Or5** if you want bots. Runs are solo with no team by default; see
  *Bots* below.

## Install

1. Extract into `Warhammer 40,000 DARKTIDE/mods/` so you get
   `mods/ChaosWastesAtHome/`.
2. Add `ChaosWastesAtHome` to `mods/mod_load_order.txt`, or enable it through
   Vortex. **A mod not listed there is silently never loaded.**
3. Bind **Open the Chaos Wastes menu** in the mod options. One key does
   everything.

## How a run works

1. Press your menu key — **at character select, or in the Mourningstar**. The
   launcher offers a **difficulty
   slider** — Malice, Heresy, Damnation, Auric, then Havoc 25 / 30 / 35 / 40 —
   and **three missions** rolled at that difficulty. Reroll if you like.
2. Press **Begin the run**. The mission loads. On spawn you choose a **buff
   family**, the same three-card screen Mortis Trials uses.
3. As you play you earn buffs. By default a completed objective grants a
   legendary card pick; kills, a timer, and terror-event clears can also be
   switched on as sources.
4. Finish the mission and the end screen offers **three next missions**. Pick one
   and you go straight there with your buffs intact. The first card is
   pre-selected, so pressing continue keeps the run going. Playing with other
   people, the party votes on this during the mission instead — see below.
5. Each mission is one rung harder. Non-Havoc missions each roll a random
   **maelstrom** modifier. Havoc missions roll two modifiers, carry the Emperor's
   Fading Light, and scale their modifier loadout by rank exactly as real Havoc
   does.
6. **Dying ends the run.** So does quitting to the Mourningstar.

### Runs are opt-in

The mod only takes over missions **you started from the launcher**. Ordinary
solo play is left completely alone — no buff cards, no chaining. If you have
SoloPlay installed and launch a mission with it, this mod stays out of the way.

Joining someone else's run is the exception: a guest never used the launcher, so
they follow whatever the host started. The mod still stays out of matchmade
games entirely.

## The menu

One keybind, and what it opens depends on where you are:

| Where | What opens |
|---|---|
| Character select | **Start a Crusade** — the launcher |
| Mourningstar | **Start a Crusade** — the launcher |
| In a run | **Buffs Collected** — everything you are carrying |
| Anything already open | Closes it |

**Starting from character select skips the Mourningstar entirely** — pick your
character, choose a mission, and the run loads straight into it. Starting from
the Mourningstar works exactly as it always did.

Whichever one you land on, the rest are tabs across the top of it. In a mission
there are four — Start a Crusade, Rollable Buffs, Settings, Buffs Collected —
and the game stays paused for as long as any of them is open, including while
you move between them — except with other players connected, where pausing is
skipped for the reason given below. In the Mourningstar there are three; Buffs Collected
needs a run to have something to show.

**Start a Crusade opened from inside a mission ends the run you are on.** It
counts as a loss and everything it collected is gone, then you go straight into
the new mission — no defeat screen, no stop in the Mourningstar. The button
reads *End run & begin* while a run is live so it is clear what it does. There
is no confirmation step beyond that.

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

## Playing with other people

**This mod was solo-only before 1.0.0 and no longer is.** Runs work with a full
party through **Realms**, which lets players connect directly to each other.
Everything below applies only when someone else is actually in your session;
solo behaviour is unchanged.

**Everyone must be running the same version of this mod.** Buffs are sent
between machines by number, and the numbers only agree between identical
versions — so the mod checks on connect and, if anyone does not match, withholds
its own custom buffs from the whole session rather than risk crashing them.
`/cw_peers` shows who has matched.

**Everyone keeps their own buffs.** The host holds a snapshot of what every
player is carrying and hands it back as they spawn into the next mission,
including to someone who is still reconnecting minutes later.

**The party votes on the next mission.** When a mission ends, the end-of-round
screen shows the same three cards it always has — but with other players
connected, everyone sees them and a click is a vote. The tally updates live on
the cards, so you can see what the others are picking and change your mind.
Whoever the vote lands on is where the run goes. What happens when it ties is a
setting.

**Nobody is disconnected between missions.** The run moves the whole party
straight from the scoreboard into the next mission with the session intact.
Earlier versions restarted the host's session and had everyone reconnect; that
is gone, along with the failed rejoins that came with it.


**Pausing is off with other players connected.** Stopping the clock only stops
the host's game and disconnects everyone else within seconds, so it is skipped.
Instead, **anyone reading a buff card cannot be hurt and enemies will not target
them**, so stopping to read is safe without stopping the world. That protection is per player and lasts exactly as long as their own
screen is open.

## Options worth knowing

Most settings live on the mod's own **Settings** tab, reachable from the menu.
A few sit in the DMF mod options menu, marked below.

| Option | Default | Notes |
|---|---|---|
| Open the Chaos Wastes menu *(mod options)* | unbound | **Bind this first** |
| Ramp difficulty each mission | on | Off keeps the run at its starting difficulty |
| Bring bots | off | On = the game's bots fill the squad; see above |
| Pause while choosing | on | Freezes the game **and holds the card countdown**, so nothing is auto-picked. Off = stock 30s timer. **Skipped entirely when other players are connected** — it would disconnect them |
| Protect players while choosing | on | While a buff card is up, that player cannot be hurt and enemies ignore them. This is what makes reading safe when pausing cannot be used |
| Ignore buff families | off | Small buffs come from **every** family, not just the one you picked — ~70 instead of ~10. You still choose a family and still get its opening buff |
| Starting card picks / family buffs | 0 / 0 | A hand dealt at the start of a run, once |
| Custom buff frequency | 1 | How often the mod's own buffs come up, relative to the shipped categories |
| Legendary card picks / Family buffs | 3 / 7 | Per mission, not per run — deep runs stack up fast |
| Environment chance | 50% | Havoc only: hunting grounds / ventilation purge / toxic gas |
| How buffs are earned | objective only | Objectives, kills, a timer and terror events can each be switched on as sources |
| When a vote ties | The host decides | Or *Whoever got there first*, or *Pick at random* |
| Extra seconds on the end screen *(mod options)* | 30 | Solo end screens are very short by default |
| Load Mortis assets *(mod options)* | on | Needed for buff icons and effects; ~0.5s warm, ~3s on the first load after launching the game, once per run |
| Debug logging *(mod options)* | off | Turn on before reproducing a problem. Also enables a periodic custom-buff snapshot in the log |

The difficulty you last started a run at is remembered, and is saved as part of
a **loadout** along with everything above — switching loadouts on the start
screen moves the difficulty slider too.

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
- **Starting from character select is new.** If it misbehaves, starting from
  the Mourningstar is the well-worn path.
- **Multiplayer is newer and less tested than solo.**
- The end-of-round screen's credits and XP are placeholder numbers in any
  local session, this mod or not — the backend does not issue a report for one.
  The mission cards and the vote on that screen are unaffected.
- A player who drops and rejoins **during** a mission gets their buffs back on
  the next one rather than immediately.

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
| `/cw_launch` | The run launcher (Mourningstar, or one of this mod's missions) |
| `/cw_buffs` | The rollable-buffs menu |
| `/cw_status` | Buffs granted this mission, plus any guard activity |
| `/cw_modifiers` | What this mission is actually running — difficulty, circumstances, Havoc modifiers |
| `/cw_buff [family\|legendary]` | Grant one now |
| `/cw_give [name or search]` | Grant a specific buff; with no exact match it searches |
| `/cw_verify` | Print the custom-buff snapshot now (it is also logged passively — see above) |
| `/cw_win` / `/cw_lose` | End the current mission (testing) |
| `/cw_arm` | Mark the next mission as a run, whatever starts it. You do not need this for a normal run |

With other players connected:

| Command | What it does |
|---|---|
| `/cw_vote <number>` | Vote from chat instead of clicking a card |
| `/cw_votes` | The current tally in chat |
| `/cw_peers` | Who is connected and whether their version matches |
| `/cw_carry` | What the run is holding for each player |

## Credits

- Simplified Chinese and Russian translations contributed by players.
  Russian covers every string; Simplified Chinese covers most of them, and
  anything missing falls back to English. The mod's own custom buffs are named
  and described in code and are English-only in every language — updated
  translations welcome.
