# Changelog

## 0.9.8

**Everyone in a session must be on this version.** Use this rather than 0.9.7.

- The family carry-over no longer has a time limit on it, so a player whose
  rejoin takes a long time still gets their family back instead of being asked
  to pick again.

## 0.9.7

**Everyone in a session must be on this version.**

- **Actually fixed players rejoining a run being asked to pick a buff family
  again.** 0.9.6 fixed one of the two places that offers the card; this covers
  the one every request goes through, so it no longer depends on when in the
  join a player happens to arrive.

## 0.9.6

**Everyone in a session must be on this version.**

- **Fixed players rejoining a run being asked to pick a buff family again**, and
  getting that family's buffs stacked on top of the ones they were already
  carrying. Their family is now put back at the moment they spawn, before the
  game decides whether to offer them a choice -- 0.9.5 restored it a frame too
  late, by which point the card was already on their screen.

## 0.9.5

**Everyone in a session must be on this version.**

- **Everyone keeps their buffs across a mission now, not just the host.** The
  host holds a snapshot for every player in the run and hands it back when they
  spawn into the next mission -- including someone who is still reconnecting
  minutes after everyone else, which is the normal case after a mission change.
  A player who has not come back yet keeps their buffs in the snapshot rather
  than losing them, and gets them on whichever mission they next appear in.
- `/cw_carry` shows what the run is holding and for whom.

## 0.9.4

**Everyone in a session must be on this version.**

- **The Mourningstar no longer accepts joins while a run is moving on.** With
  Solo Mourningstar installed the hub is a session of its own, so it answers on
  the same address the mission did -- and anyone dialling in during the few
  seconds between missions landed there instead of in the mission. It is closed
  for that window and reopened afterwards; your Realms settings are not
  touched. Players following a run also recognise the Mourningstar and keep
  waiting for the real mission rather than settling there.
- A player following a run is now given longer to get back in. The clock only
  starts once the host's session actually goes, rather than when the mission
  ended -- on a slow hub load it could previously run out before the host had
  gone anywhere.

## 0.9.3

**Everyone in a session must be on this version**, 0.9.2 included -- the mod
checks, and withholds its custom buffs from anyone who does not match.

- **The vote now decides the next mission.** Open one with `/cw_vote_open`
  during the mission, everyone votes with `/cw_vote <number>`, and when the
  mission is completed the winner is what the end-of-round picker shows,
  already selected. `/cw_vote_close` resolves it early for testing.
  The vote has to happen during the mission because that is the only time
  there is a channel to the other players -- by the end-of-round screen the
  session is already gone.
- **With other players connected, the vote is final.** The end-of-round picker
  shows what the party chose and cannot be clicked past. On your own it stays
  fully selectable, because there the vote is only a shortcut and the picker is
  the real choice.
- **Players are carried to the next mission automatically.** Moving a run on to
  the next mission restarts the host's session, so everyone else is
  disconnected on the way through -- that is unavoidable, and it is how the
  game itself starts a new mission from inside one. The host now warns everyone
  before it happens and they rejoin on their own, using the address they joined
  with. It takes a few seconds; the chat says what is going on.
  If it cannot get back in, rejoin from the Realms menu as usual.
- **Runs can be launched again with Realms installed.** 0.9.0 refused, on the
  belief that the mission chain could not survive the restart. It can -- the
  previous release blocked a path that works.
- Fixed the end-of-round picker opening on the first mission whatever the vote
  said. It highlighted card 1 even when the vote had won on card 3, so the run
  looked like it was going somewhere it was not.

## 0.9.2

- A first attempt at handing the voted mission straight to Realms so that
  nobody would be disconnected. **It did not work** -- the game sat on a
  loading screen that never resolved. 0.9.3 replaces it; there is no reason to
  run this version.

## 0.9.1

- **Fixed the experimental synchronised pause kicking joining players.** The
  opening buff card appears the moment the host spawns, while everyone else is
  still loading -- and Realms only delivers a synchronised timescale to players
  whose connection has finished its handshake. So the host stopped dead, the
  message reached nobody, and anyone still loading died on a black screen. The
  pause now waits until every connected player can actually receive it; while
  anyone is still joining it does not pause at all.

## 0.9.0

**Everyone in a session must run this same version.** The mod checks, and
withholds its custom buffs from anyone who does not match rather than risking a
crash on their machine.

### Pausing no longer disconnects people

- Pausing stops only your own game, so with other players connected it was
  dropping them within seconds. It is now skipped by default when anyone else
  is in your session.
- **New setting, "Pause everyone (experimental)".** Routes the pause through
  Realms' synchronised timescale so the whole party stops together, which lets
  you keep Pause While Choosing switched on in multiplayer. Experimental
  because that channel was built for level slow-motion and stopping the clock
  completely may still drop the session -- if it does, switch it back off.
- **The pause now waits for everyone.** Previously it read only your own buff
  card, so whoever picked first resumed the world for everybody else while they
  were still deciding. It now holds until nobody is on a card, with a 60 second
  cap so a disconnect mid-choice cannot freeze the run.

### Voting on the next mission

- `/cw_vote_open` (host) rolls the next three missions and puts them to the
  party; everyone answers with `/cw_vote 1`, `2` or `3`, and `/cw_votes` shows
  the tally from either end.
- The vote runs **during the mission**, not on the end screen. That is not a
  preference: the end-of-round screen is a separate game state, and by the time
  it appears the session the mod talks over has already been torn down. During
  the mission is the only window there is.
- Ties, and nobody voting at all, fall to the first option. A run should not
  stall because no one pressed a button.

### Known limits

- The mission chain still does not run with Realms loaded, and launching a run
  is refused with an explanation while it is. Use `/cw_arm` and start the
  mission with SoloPlay.
- The vote is opened by hand for now. Committing its result into the next
  mission automatically is the next piece of work.
- Buffs still only carry between missions for the host.

## 0.8.0

**Groundwork for multiplayer. Nothing here changes solo play, and multiplayer
is not finished** -- this is the half that can be built and checked before two
people are in a mission together.

### The mod now has a host role and a client role

- Previously the mod refused to run anywhere but a solo session, because a
  client running the stock buff system would be sent buff ids it does not have
  -- a crash on their machine, caused by the host's. Both sides now run the
  same buff manager, which is what makes that safe.
- Internally, "the buff system is live" and "I am the one who decides" were the
  same flag and are now three separate tests. Fourteen guards were re-read one
  at a time and split between them; the solo regression suite was exercised
  afterwards with no changes in behaviour.

### Peers are checked before custom buffs cross the wire

- On a player-hosted session, every connected player publishes the network ids
  it assigned to this mod's custom buffs, and they are compared entry by entry.
  Comparing ids rather than version strings is deliberate: two players on the
  same version still disagree if another mod claimed ids first, and that
  disagreement is what crashes people.
- If any connected player has not matched -- wrong version, different ids, or
  simply not answered yet -- **custom buffs are withheld from the pools for
  that mission** rather than risking a crash on someone else's machine. They
  come back on their own once everyone matches.
- `/cw_peers` shows your version, your ids, every connected player and whether
  they match.

### Commands

- `/cw_peers` -- connected players and whether their buff ids match yours.
- `/cw_arm` -- marks a run as started without launching one, so a mission
  started any other way is taken over. This exists for multiplayer testing; the
  mission chain cannot yet survive the session reset that a normal launch
  performs while Realms is loaded.
- `/cw_status` now leads with which role you are in and whether you hold
  authority.

### Known limits

- **The mission chain does not work with Realms loaded.** Launching a run is
  refused with an explanation while it is, because the hop tears down and
  rebuilds the host's listen server mid-transition. Use `/cw_arm` plus a
  SoloPlay launch for multiplayer, or remove Realms for a normal chained run.
- The client role has been written and reviewed but not yet played. Expect to
  iterate.
- Everyone in a session needs the **same version of this mod**. The check above
  will tell you when you do not, but it withholds content rather than fixing
  it.

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
