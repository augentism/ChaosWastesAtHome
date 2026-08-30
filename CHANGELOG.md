# Changelog

## 0.7.0

### The menu in a mission

- **The whole menu is reachable from inside a mission.** The collected-buffs
  screen is now a tab alongside Start a Crusade, Rollable Buffs and Settings,
  and opens on Buffs Collected as before. Gameplay stays paused while any of
  them is open, including while you move between tabs.
- **Start a fresh run without going back to the Mourningstar.** Beginning a run
  from inside a mission ends the one you are on -- it counts as a loss, and
  everything it collected is gone -- then drops you straight into the new
  mission with no defeat screen and no stop in the hub. The button reads "End
  run & begin" while a run is live, so it says what it will do.

### Fixes

- **Havoc missions could load with an environmental modifier the mod never
  offered.** Darkness, ventilation purge and toxic gas were being written into
  the mission's configuration even when the chance slider had skipped them, so
  a mission could load pitch black with nothing about it on the card and no
  modifier behind it -- at any setting, including 0. The setting now governs
  the level as well as the card. It also only picks an environment the chosen
  mission actually supports.

### Diagnostics

- The log now records how each offered mission was rolled, what the three cards
  were, and -- once you are in a mission -- the modifiers, environment and
  mutators the game actually loaded, so an unexpected modifier can be traced
  without reproducing it. `/cw_modifiers` prints the same report on demand.

## 0.6.0

### Loadouts

- **Buff loadouts.** Save your whole configuration — the buff pool, every option
  on the new Settings tab — as a named loadout, and switch between them from a
  column on the left of every tab. Edits while a loadout is selected save to it
  automatically. One can be marked default and is applied at game start.
  Loadouts live as individual files under
  `%APPDATA%/Fatshark/Darktide/ChaosWastesAtHome/loadouts/`, so they can be
  edited by hand, backed up, or shared.
- Each loadout gets an icon from the game's own preset symbols; right-click one
  to change it. The `+` under the list creates a loadout from your current
  configuration.

### Buff selection

- **Disable an archetype from the opening pick.** In Rollable Buffs, select a
  family and use the button under the list to keep it out of the three offered
  at the start of a run. Excluded families are dimmed in the list, and the
  setting is saved per loadout. Switching every family off falls back to
  offering all of them rather than leaving you with no card.

### Settings

- **New Settings tab**, alongside Start a Crusade and Rollable Buffs. Everything
  that shapes a run has moved here from the mod options menu, grouped by topic,
  with each setting's description shown as you hover it. The options menu keeps
  the keybind, the asset preload, the end-screen timer, and diagnostics.
- **Starting card picks and starting family buffs.** Deal yourself an opening
  hand: a configurable number of legendary card picks, then family buffs, handed
  out once you have chosen your buff family. These are extra and do not count
  against the run's own limits.
- **Ignore buff families.** Offers buffs from every family rather than only the
  one you opened with. Buffs normally locked behind another class are included.

### Fixes

- Buff pool changes were never written to disk. The whole rollable-buffs
  selection is now saved.
- Selecting a loadout could overwrite it with the settings of the one you were
  on before, eventually making every loadout identical.
- Selecting a loadout duplicated every row in the Rollable Buffs list.
- Changing a loadout's icon did nothing on some tabs, and a click meant for the
  icon palette also fell through to the setting or buff row underneath it.
- Long setting names wrapped on top of themselves in the Settings tab.
