# Chaos Wastes at Home

Turns regular **solo** Darktide missions into a Chaos Wastes–style run: you pick
a buff family when you spawn, earn Mortis Trials buffs as you play, and at the
end of each mission choose one of three next missions. Your buffs carry over.
The difficulty climbs every mission. Losing ends the run.

## Requirements

- **Darktide Mod Framework**
- **[SoloPlay](https://www.nexusmods.com/warhammer40kdarktide/mods/56)** — this
  mod only activates in singleplay sessions, which is how SoloPlay hosts a
  mission. It does nothing in matchmade or hosted games (see below).

## Install

1. Extract into `Warhammer 40,000 DARKTIDE/mods/` so you get
   `mods/ChaosWastesAtHome/`.
2. Add `ChaosWastesAtHome` to `mods/mod_load_order.txt`, or enable it through
   Vortex. **A mod not listed there is silently never loaded.**

## How a run works

1. Start a solo mission as usual. On spawn you choose a **buff family** — the
   same three-card screen Mortis Trials uses.
2. As you play, you earn buffs. By default a completed objective grants a
   legendary card pick; kills, a timer, and terror-event clears can also be
   enabled as sources.
3. Finish the mission and the end screen offers **three next missions**. Pick
   one and you go straight there with your buffs intact. The first card is
   pre-selected, so pressing continue keeps the run going.
4. Each mission is one rung harder: up through the normal difficulties to
   Auric, then Havoc 25, 30, 35, 40. Havoc missions roll two modifiers, carry
   the Emperor's Fading Light, and scale their modifier loadout by rank exactly
   as real Havoc does.
5. **Dying ends the run.** So does quitting to the Morningstar, or ignoring the
   picker.

## Solo only, deliberately

The mod refuses to run outside a singleplay session, and this is not
configurable. The buff system sends network messages to every other player in
the session, and a client without this mod has not registered them — enabling
it in a hosted game would break other people's game, not just yours.

## Options worth knowing

Everything is in the mod options menu.

| Option | Default | Notes |
|---|---|---|
| Ramp difficulty each mission | on | Turn off to keep the run at its starting difficulty |
| Load Mortis assets | on | Needed for buff icons and effects to render; ~3.5s once per run |
| Extra seconds on the end screen | 30 | Solo end screens are very short by default |
| Havoc theme circumstance chance | 50% | Hunting grounds / ventilation purge / toxic gas |
| Buffs per mission | 3 legendary, 7 family | Per mission, not per run — deep runs stack up fast |
| Pause while choosing | on | Freezes gameplay while a buff card is up |
| Debug logging | off | Turn on before reproducing a problem |

There are also unbound keybinds under **Testing** to end a mission instantly as
a win or a loss, for exercising the chain without playing a whole map.

## Known issues

- **Horde spawn crash.** A base-game spawn-point query can fail in solo play and
  crash the game. It is not caused by this mod, but the mod now catches it and
  skips that horde rather than letting it kill the session. `/cw_status` reports
  how many times it happened.
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

## Commands

- `/cw_status` — buffs granted this mission, plus any guard activity
- `/cw_buff [family|legendary]` — grant one now
- `/cw_win` / `/cw_lose` — end the current mission (testing)
