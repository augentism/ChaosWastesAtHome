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

### Optional buff packs

The source for CwahBuffs is tracked in this repository's `CwahBuffs/` folder.
Release zips install it separately as `mods/CwahBuffs/`.

Install **CwahBuffs**, **MourningBound**, or both alongside ChaosWastesAtHome,
and list each installed mod in `mod_load_order.txt`. The order of these three
mods does not matter.

- **CwahBuffs** supplies the original nine custom cards.
- **MourningBound** supplies its additional blessings and upgrades. Identical
  copies of toughness on elite kills, crit ramp, attack-speed ramp, Flayer,
  Proliferation and Chain Lightning (including their automatic copied tiers)
  have been removed. Install CwahBuffs if you want those cards.
- **Both enabled** offers both packs. MourningBound's distinct damage, cascade
  and multishot variants have separate IDs and marked card titles. Use the
  separate Rollable Buffs tabs to choose which cards can appear.

Update both packs for compatibility. Restart the game after installing,
removing, or enabling/disabling a pack; registration happens at startup.
CwahBuffs IDs stay unchanged. MourningBound's three overlapping variants now
use `cwah_mourningbound_*` IDs; reselect those variants in Rollable Buffs and
start a fresh run when upgrading from the old pack. Old shared IDs cannot
identify which pack's version was saved.

### Player-created buffs

Create your own timed stacking buffs under **Buffs / Debuffs → Player Buff Editor**,
or edit
`%APPDATA%/Fatshark/Darktide/ChaosWastesAtHome/buffs.txt`. The mod creates a
commented example on first startup. `/cw_recipes` reports its path and any
definition errors. Use **Reload file** after external edits; no restart is
needed. Saves refresh the menu outside a run; during a run or preparation lobby,
changes apply to the next session. Acquired recipes appear as normal
reward cards in **Player Buffs**. Definitions are global and Rollable Buffs
toggles remain part of each loadout.

The editor uses a scrollable preset-style list with the same panel and tab
positions as Rollable Buffs and Havoc Modifiers. **Include in your catalogue**
enables the saved definition. **Legendary card pick** selects its reward pool:
checked means a legendary pick (the default for existing recipes); unchecked
means a randomly rolled regular family buff, available with any chosen family.
Player Buffs remains a menu category, not a starting family.

Each definition selects a trigger, a stat effect, strength per stack, maximum
stacks and duration. A successful trigger adds one stack and refreshes the
shared timer, even at the cap. See [the format and complete component list](docs/player-buffs.md).

Realms parties use the **host's recipes**. With Realms installed, saved recipes
appear in the Player Buffs menu at startup; the host's catalogue is synchronized
in the preparation lobby before ready-up. Clients keep their own saved files,
but those recipes are not registered for the host's run. Everyone needs matching
CWaH code and compatible base buff packs. Reserved network slots allow switching
to a host with different recipes without restarting, after the previous session
has fully torn down. Join through the preparation lobby,
not an in-progress recipe run. `/cw_recipes` reports synchronization status.

### Choosing buffs and Havoc modifiers

Open **Buffs / Debuffs**. **Rollable Buffs** is the default subtab and keeps
all existing buff and family controls. **Havoc Modifiers** lists the available
random Havoc circumstances: select one to read its description, then enable
or disable it. Bulk controls apply to the selected subtab.

These choices are saved with your loadout and affect newly rolled mission
options, including rerolls. Havoc picks up to two distinct enabled modifiers;
with one enabled it picks one, and with none enabled it adds none. Environment
chance and The Emperor's Fading Light remain separate from these toggles.
Already offered missions and the current mission keep their rolled modifiers.

### Starting a run

1. Press your menu key — **at character select, or in the Mourningstar**. The
   launcher offers a **difficulty
   slider** — Malice, Heresy, Damnation, Auric, then Havoc 25 / 30 / 35 / 40 —
   and **three missions** rolled at that difficulty. Reroll if you like.
2. Press **Begin the run**. The mission loads. On spawn you choose a **buff
   family**, the same three-card screen Mortis Trials uses.
3. As you play you earn buffs. By default, activate a shrine and defeat its
   boss for a legendary card pick. Objectives, kills, a timer, and terror-event
   clears can also be switched on as sources.
4. Finish the mission and the end screen offers **three next missions**. Pick one
   and you go straight there with your buffs intact. The first card is
   pre-selected, so pressing continue keeps the run going. Playing with other
   people, the party votes on this during the mission instead — see below.
5. Each mission is one rung harder. Non-Havoc missions each roll a random
   **maelstrom** modifier. Havoc missions roll two modifiers, carry the Emperor's
   Fading Light, and scale their modifier loadout by rank exactly as real Havoc
   does.
6. **Dying ends the run.** So does quitting to the Mourningstar.

### Shrine rewards

Shrines work across the difficulty ladder, including Auric and Havoc. Each
activated shrine spawns supporting enemies and one designated boss. Killing
that boss triggers one reward attempt for the party; leftover enemies do not
hold it up. The shrine's attack-speed benefit applies only inside its area
during the encounter and ends when the boss dies. It grants no permanent
Atonement buff.

In **Settings**, enable **Shrines**, choose family / legendary / random rewards
and their chance, and set **Maximum shrines per map** from 1–20 (default 6).
Actual counts depend on usable map locations. Enable/count changes apply to
the next mission; reward type and chance are captured when you activate each
shrine. Existing mission modifiers are retained.

Shrines share the other sources' per-mission budgets and pool fallback. With
the default three legendary choices, further shrine rewards can become family
buffs; exhausted budgets stop further rewards. If you also enable kill or
terror-event rewards, those sources can grant additional buffs independently.

Fresh settings use shrines with 100% legendary rewards and objectives off.
Existing settings and loadouts retain their choices; old loadouts without shrine
settings load with shrines off. Enable the new source in your preferred loadout.
Realms parties need the updated mod on every peer, with the host controlling
shrine placement and rewards.

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

**With VoxPopuli installed, the viewers pick the next mission.** If
[VoxPopuli](../VoxPopuli) is present, switched on and connected to a chat, the
end-of-round vote is handed to the stream: the same three cards appear with the
same live tally, but the numbers on them are chat's and a player's click no
longer counts. Viewers answer `!1`, `!2`, `!3` or the mission's internal name.

This works **solo**, unlike the party vote — a lone streamer has a whole chat to
vote against, which is the case it exists for. If chat says nothing before the
end screen closes, the map is picked at random rather than falling back to the
players, so the feature does not quietly stop working on a slow night.

The vote is sized to whatever is left of the end screen, so *Extra seconds on
the end screen* is what gives chat room to answer; with too little left, it is
skipped and the party (or your click) decides as usual. Everything degrades to
the normal vote if VoxPopuli is absent, older, off or disconnected.

**Turn it off with *Let chat pick the next mission*** (mod options) if you want
VoxPopuli for everything else and would rather choose maps yourself. The setting
does nothing without VoxPopuli.

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
| How buffs are earned | shrines only | Shrines, objectives, kills, a timer and terror events can each be switched on as sources; existing loadouts retain their settings |
| When a vote ties | The host decides | Or *Whoever got there first*, or *Pick at random* |
| Extra seconds on the end screen *(mod options)* | 30 | Solo end screens are very short by default. Also what gives chat room to answer the map vote |
| Let chat pick the next mission *(mod options)* | on | With VoxPopuli connected, the viewers choose instead of the players. Off = you choose as usual. No effect without VoxPopuli |
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

Reward-source entries are recorded even with debug logging off. Search for
`reward requested:` to see shrines (including shrine ID and boss breed), kills
(including mode and threshold), objectives,
timers, terror events, starting buffs, and manual card grants. Each entry names
the reward kind; automatic sources also record the configured choice and chance,
so a fallback to another reward kind is visible. A request records a buff or
card offer being issued, not the player's eventual card selection. Named grants
use `reward granted:`; mission carryover has separate restoration entries.

For additional diagnostics, turn on **Debug logging**, reproduce it, then send
the console log from:

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
