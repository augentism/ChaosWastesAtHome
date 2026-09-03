# Changelog

## 1.1.2

**Everyone in a session must be on this version.**

- **Fixed Contagion doing nothing for anyone but the host.** A guest could pick
  it and it never fired once -- silently, with nothing to say so. It now
  spreads status effects for whoever is carrying it.

## 1.1.1

- **Fixed the same small buff being handed out over and over.** The run was
  re-applying your buff family once a second for the whole mission, and the game
  adds a family's buffs to your pool rather than replacing them -- so the pool
  filled up with thousands of copies of the same ten buffs, and almost every
  grant after that was one you already had. Affects solo runs as much as
  multiplayer ones.

## 1.1.0

- **Start a run from character select, without loading the Mourningstar.** Pick
  your character, open the Chaos Wastes menu, choose a mission and press Begin --
  the run starts directly. Saves the hub load at the start of every run.
  The Mourningstar still works exactly as before if you would rather start
  there.

## 1.0.0

**The first release since 0.7.0.** Everything below arrived across the 0.8–0.15
development builds, which were never published on their own.

### Runs can be played with other people

- **Play a run with friends** through the **Realms** mod, which lets players
  connect directly to each other. Solo play is unchanged.
- **Everyone in the session must be on the same version of this mod.** It checks
  on connect and, if anyone does not match, withholds its own custom buffs from
  the whole session rather than risk crashing them. `/cw_peers` shows who has
  matched.
- **Everyone earns and keeps their own buffs**, and the run carries all of them
  from mission to mission -- including for a player who was disconnected when
  the last mission ended.
- **The party votes on the next mission.** Three maps go up shortly after each
  mission starts, shown full-size with every modifier and what it does written
  out. Open the vote screen with its keybind, click one, change your mind as
  often as you like. Everyone sees the running tally, and ties are settled by a
  rule you choose.
- **Reading is safe without pausing.** Pausing cannot work with other players
  connected -- stopping the clock disconnects them -- so instead, anyone looking
  at a buff card or the vote screen cannot be hurt and enemies ignore them. This
  also works solo if you would rather not pause.
- **Moving between missions reconnects players automatically.** It does not
  always land cleanly. Rejoining by hand costs nothing when it does not, because
  the host holds everyone's buffs -- see the README.

### Solo play

- **Buff choices no longer offer buffs you are already carrying.** The offer
  pools were rebuilt each mission without taking your carried buffs out of them,
  so from the second mission onwards a card could contain a pick that did
  nothing. Pools now deplete across a whole run rather than resetting.
- **The launcher remembers the difficulty you last played at**, instead of
  starting at Malice every time, and saves it with your loadout -- switching
  loadouts on the start screen moves the difficulty slider too.

### New commands

`/cw_vote_view`, `/cw_vote`, `/cw_votes`, `/cw_vote_open`, `/cw_vote_close`,
`/cw_peers`, `/cw_carry`, `/cw_rejoin_stop`, `/cw_modifiers`, `/cw_arm`. The
README lists what each one does.

---

*Everything below this line is the development history between 0.7.0 and 1.0.0.
None of it was released on its own, and the "known limits" noted in the 0.8 and
0.9 entries describe states that were superseded before 1.0.0 shipped. Kept for
reference rather than as a guide to the current version.*

## 0.15.3

- **Rejoining players no longer land in the Mourningstar on the way.** Moving a
  run on restarts the host's session twice -- once leaving the mission, once
  starting the next one -- and the gap between them was leaving the Mourningstar
  open to joins for the best part of a minute. It is closed for the whole of
  that window now, so players wait rather than arriving somewhere that is about
  to disappear.

## 0.15.2

- **Fixed rejoining players landing on the end-of-round screen** when the host
  was slower through it than they were. They were reconnecting to the session
  the host had not finished leaving, which is about to be destroyed -- so they
  were dropped again a moment later with nothing left trying to get them back.
  That screen is now treated as somewhere to wait, not somewhere to arrive.

## 0.15.1

- **Fixed players being left retrying forever when the host quits from a
  lobby.** Sitting in the host's lobby was not recognised as having rejoined --
  a lobby has no mission running, which looks the same as a level still
  loading -- so the rejoin stayed armed the whole time. When the host then left,
  it started trying to reconnect to nobody. Being back with the host now counts
  as done wherever it happens.
- **New command `/cw_rejoin_stop`** to give up rejoining. It is named in the
  message that appears while reconnecting, so it is there when you want it.

## 0.15.0

- **Rewrote the README for multiplayer.** It still said the mod was solo-only
  and refused to run in a hosted game, which stopped being true several
  releases ago. It now covers playing with other people, the vote, the version
  requirement, what happens between missions, and why pausing is replaced by
  protection. The commands and options tables were also missing about half of
  what exists.

## 0.14.3

**Everyone in a session must be on this version.**

- **Fixed the vote screen showing the previous mission's vote.** Opening it
  before this mission's vote had gone up offered the map you had just finished.
  It now says the vote has not opened yet, and fills itself in when it does --
  so you can leave it open and watch the choices arrive.
- The vote screen opens whether or not a vote is running, rather than the
  keybind appearing to do nothing.
- A vote cast with `/cw_vote` now shows as selected on the screen too, and
  reopening the screen still shows what you picked.

## 0.14.2

**Everyone in a session must be on this version.**

- **Fixed the host not being protected while reading the vote screen.** Everyone
  else was. The screen takes over your controls, so the one player who could not
  move was the one who could still be killed.
- `/cw_peers` no longer lists players who left the session.

## 0.14.1

- **Fixed the settings screen running off the bottom.** The voting section was
  added to the left column, which pushed it past the edge of a 1080p screen. It
  has moved to the right, and the two columns are close to even again.
- The voting section had also been inserted into the middle of the buff
  settings, so five buff sliders were sitting under the "Voting" heading. They
  are back where they belong.
- Shortened "Open the vote this long after the mission starts", which wrapped
  onto three lines, to "Vote opens after" with the seconds on the slider.

## 0.14.0

**Everyone in a session must be on this version.**

- **New setting: "When a vote ties".** Three rules --
  *The host decides* (the host's own vote wins if it is one of the tied
  missions), *Whoever got there first* (the mission that reached the winning
  count earliest), or *Pick at random*.
  With only two players every disagreement is a tie, so this decides more often
  than it sounds like it would. A tie between missions nobody voted for always
  falls to the leftmost card.

## 0.13.3

**Everyone in a session must be on this version.**

- **Tied votes now have a rule.** Previously a tie was settled by whatever order
  the tally happened to be stored in, which could give different answers for the
  same votes. `/cw_votes` says when a tie decided it.

## 0.13.2

**Everyone in a session must be on this version.**

- **Everyone sees everyone's votes.** The host now sends the running tally out
  to the party, so the numbers on the cards are the same on every screen. Before
  this only the host could see the whole picture and everyone else saw just
  their own choice.

## 0.13.1

**Everyone in a session must be on this version.**

- **The vote opens shortly after each mission starts** and stays open until the
  mission ends, so there is a whole mission to look at the three maps, argue
  about them and change your mind -- rather than a decision to make while the
  map is at its busiest. The delay is a setting, and it waits a little longer on
  its own if someone is still loading in.
  This also replaces 0.13.0's guess at "near the end of the level": Darktide
  marks no objective as the last one, so that could only ever be approximated.
- **The vote screen is now its own screen**, laid out like the run launcher --
  full-size mission art, and every modifier with what it actually does written
  out on the card. All three are readable side by side without hovering over
  anything.

## 0.13.0

**Everyone in a session must be on this version.**

- **A vote screen for the next mission.** Bind a key to "Open the vote screen"
  and everyone in the party gets the same three mission cards the end-of-round
  picker shows, and clicks the one they want. The winner is what the end screen
  selects. You cannot be hurt or targeted while the screen is open.
  You cannot be hurt or targeted while the screen is open, so reading it
  mid-mission is safe.
- **The vote opened near the end of the level**, judged from how far along the
  level's main path the party had got. Replaced in 0.13.1.

## 0.12.0

**Everyone in a session must be on this version.**

- **The launcher remembers the difficulty you picked**, instead of starting at
  Malice every time. It is saved with the rest of your settings, so it is part
  of a loadout -- switching loadouts on the start screen moves the difficulty
  slider along with everything else.
  Stored by name rather than by slider position, so a game update that adds a
  difficulty or changes the Havoc ladder cannot quietly shift it.

## 0.11.2

**Everyone in a session must be on this version.** 0.11.0 can crash other
players -- please update rather than staying on it.

- **Fixed a crash for anyone who opened the tactical overlay (Tab) while a buff
  card was up.** The protection buff added in 0.11.0 was filed under the same
  category as the pickable buffs, and the overlay assumes anything in that
  category has card art to draw. It is now an internal buff the overlay ignores.
- **Removed "Pause everyone (experimental)".** It never worked -- Realms'
  synchronised timescale was built for slow motion, and stopping the clock dead
  still dropped the session. "Protect players while choosing" replaces it and
  does the job properly.
- **Removed the sixty-second "waiting for another player's buff choice"
  message.** It belonged to the synchronised pause and had nothing left to wait
  for.

## 0.11.1

**Everyone in a session must be on this version.**

- **Begin Run works normally with other players connected.** It always did from
  0.9.4 onwards; `/cw_arm` and a separate launcher were a workaround for a
  restriction that no longer exists, and the wording had not caught up. Start
  runs from the mod's own menu.
- If starting a run disconnects players who could not be warned first, the host
  is now told to ask them to rejoin, instead of them just vanishing.

## 0.11.0

**Everyone in a session must be on this version.**

- **New setting: "Protect players while choosing" (on by default).** While a
  buff card is on screen, that player cannot be hurt and enemies will not target
  them, until they pick. Each player is protected only while their own card is
  up.
  This exists because pausing cannot work with other players connected --
  stopping the clock disconnects them -- so without it, reading three cards
  means standing still in the middle of a fight. Safe to leave on alongside
  pausing; it has nothing to do when the game is already stopped.

## 0.10.0

**Everyone in a session must be on this version.**

- **Fixed a player who rejoins mid-mission losing the run's buffs.** They came
  back with nothing, and then the moment they earned a single new buff the run's
  record of what they were carrying was overwritten by just that one -- so the
  loss became permanent instead of lasting until the next mission.
- **Buffs are now kept topped up continuously** rather than handed back once.
  Whatever a player is short of what the run says they hold is given to them
  whenever they turn up, so a rejoin at any point puts them back where they
  were. Nobody gets anything twice: only the difference is handed over.

## 0.9.9

**Everyone in a session must be on this version.**

- **Buff choices no longer offer buffs you are already carrying.** The offer
  pools are rebuilt each mission, and carried buffs were not being taken out of
  them -- so on the second mission onwards a card could contain a pick that did
  nothing. Carried buffs are now removed from the pools, which also means a
  run's pools deplete across the whole run rather than resetting every mission.

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
