# Changelog

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
