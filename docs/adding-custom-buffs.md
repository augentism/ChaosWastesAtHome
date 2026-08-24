# Adding custom Mortis buffs from a mod

How ChaosWastesAtHome adds its own buffs to the Mortis Trials buff pool, and
every trap that cost a test cycle getting there.

Working reference: `scripts/mods/ChaosWastesAtHome/custom_buffs.lua`.
Line numbers refer to the decompiled source in
`references/source/Darktide-Source-Code/`.

---

## Why this is possible at all

The game's settings tables are plain and mutable — `settings()` is literally
`return data_table`, nothing is frozen. So a mod can write into `BuffTemplates`,
`HordesBuffsData` and the allowed-buff pools at load time and the buff system
treats the result as native.

You are not writing a buff system. You are adding rows to four tables.

---

## In this mod: add one catalogue entry

`custom_buffs.lua` drives everything from a single `CATALOGUE` list, so adding a
buff means writing one entry and nothing else:

```lua
_add({
    id         = "cwah_custom_damage",
    pool       = true,                   -- false/absent = a helper, never offered
    icon       = "hordes_buff_damage_increase",
    values     = { _pct(DAMAGE_MULTIPLIER - 1) },   -- fills the description's %s
    stat_buffs = { [stat_buffs.damage] = DAMAGE_MULTIPLIER },
})
```

plus its two strings in `ChaosWastesAtHome_localization.lua`:

```lua
loc_cwah_custom_damage_title = { en = "Wrath Unbound" },
loc_cwah_custom_damage_description = { en = "Increases all damage you deal by %s." },
```

Anything past a plain passive supplies `template = function () return {...} end`
instead. `register` then does all five registrations below for you, and derives
the loc keys as `loc_<id>_title` / `loc_<id>_description` — the same convention
`hordes_buffs_data.lua` uses for the shipped buffs, so there is no second place
for a key and a template to disagree. See **Where the card text lives** at the
end for why the wording is over there and the numbers are over here.

The rest of this document is what that loop is doing, and why each step exists.
You need it when writing a `template` factory, when something crashes, or when
porting the idea to another mod.

## The five registrations

Miss any of these and the buff fails in a different, mostly silent way.

| # | What | Where | If you skip it |
|---|---|---|---|
| 1 | The template | `BuffTemplates[name]` | nothing exists |
| 2 | `template.name` | must equal the table key | **crash on apply** |
| 3 | Network id | `NetworkLookup.buff_templates` | **crash on apply** |
| 4 | Card data | `HordesBuffsData[name]` | no title, icon or description |
| 5 | Pool membership | `MissionBuffsAllowedBuffs.legendary_buffs.generic` | never offered |

Note that **2 and 3 both crash only when the buff is applied, never when it is
offered** — the card renders perfectly, then kills the mission when you pick it.
That is the single most important thing to know here.

### 1 & 4 — template and card data

```lua
BuffTemplates.cwah_custom_damage = {
    class_name = "buff",
    max_stacks = 1,
    max_stacks_cap = 1,
    predicted = false,
    buff_category = buff_categories.hordes_buff,
    stat_buffs = {
        [stat_buffs.damage] = 1.15,
    },
}

HordesBuffsData.cwah_custom_damage = {
    title = "loc_cwah_custom_damage_title",
    description = "loc_cwah_custom_damage_description",
    icon = ICON_ROOT .. "hordes_buff_damage_increase",
    is_family_buff = false,
    filter_category = CATEGORY,   -- MANDATORY, see pitfall 4
}
```

### 2 — `template.name` must match the key

The game sets this itself when it assembles `BuffTemplates`
(`buff_templates.lua`'s `_create_entry` does `template.name = template.name or name`).
A table written straight in bypasses that and has no name.
`BuffExtensionBase._add_buff` then uses it as a key into `_stacking_buffs`:

```
buff_extension_base.lua:502: table index is nil
```

Do it for every template you define, including helper templates that are never
offered:

```lua
for _, buff_name in ipairs(ALL_TEMPLATE_NAMES) do
    local template = BuffTemplates[buff_name]
    if template then
        template.name = template.name or buff_name
    end
end
```

### 3 — the network id

`NetworkLookup.buff_templates` is built **once at boot** from whatever is in
`BuffTemplates` at that moment (`network_lookup.lua:140`). Mods load afterwards,
so a mod-added template is never in it.

`PlayerUnitBuffExtension._add_rpc_synced_buff` reads the id at line 656 —
**before** it checks `player.remote` at line 668 — and the lookup's metatable
*errors* on an unknown key rather than returning nil. So it crashes in solo too,
despite nothing ever going over the wire:

```
network_lookup.lua:576: [NetworkLookup] Table buff_templates does not contain key: cwah_custom_damage
```

Append the entries yourself. Three things to get right:

```lua
local buff_lookup = rawget(_G, "NetworkLookup")
buff_lookup = buff_lookup and buff_lookup.buff_templates

if not rawget(buff_lookup, buff_name) then      -- rawget: see below
    local index = #buff_lookup + 1
    buff_lookup[index] = buff_name              -- bidirectional
    buff_lookup[buff_name] = index
end
```

- The table is **bidirectional** (`t[i] = name` and `t[name] = i`).
- Only `__index` is guarded, so appending is fine — but **membership must be
  tested with `rawget`**, because a plain read of a missing key *is* the crash.
- **Solo only today.** The id indexes a table no vanilla machine has, so it must
  never actually be transmitted. That holds in a singleplay session because
  there are no remote players.

### Keeping the door open for peer-to-peer

`_create_lookup` sorts names before appending, which is what makes every vanilla
client agree on every index. A runtime append preserves that property only if
every peer computes the same index for the same name, so **append in sorted
order** rather than in declaration order:

```lua
table.sort(names)   -- index becomes a pure function of the name SET
```

That much is free, and it means reordering your catalogue cannot silently change
an id. Two things it does not solve, both of which would need a version
handshake before any peer-to-peer path could use custom buffs:

- **Peers on different mod versions** have different name sets, so the same name
  lands on a different index.
- **Another mod appending to the same lookup** shifts the base offset, and the
  order of those appends follows `mod_load_order.txt`, which differs per user.

### 5 — pool membership

```lua
local generic = MissionBuffsAllowedBuffs.legendary_buffs.generic
generic[#generic + 1] = buff_name
```

Append only what should be *offered*. Helper templates applied by other buffs
stay out of the pool but still need registrations 2 and 3.

---

## A category of your own

Worth doing so your buffs can be weighted or disabled as a group:

```lua
MissionBuffsSettings.filtering_categories[CATEGORY] = CATEGORY

for _, rates in pairs(MissionBuffsSettings.filtering_categories_pick_rate_per_wave) do
    rates[CATEGORY] = weight
end
```

`filtering_categories` is a `table.enum`, whose metatable errors on unknown
**reads** but does not guard **writes** — so adding the key is allowed, and it
has to happen before anything asks for it.

---

## Buff shapes

### Passive stat buff

`class_name = "buff"` plus a `stat_buffs` table. That is the whole thing.

### Proc buff

```lua
class_name = "server_only_proc_buff",   -- not "proc_buff": changes authoritative state
proc_events = { [proc_events.on_kill] = 1 },
check_proc_func = CheckProcFunctions.on_elite_kill,
proc_func = function (params, template_data, template_context)
    Toughness.replenish_percentage(template_context.unit, 0.15, false)
end,
```

The number in `proc_events` is a **chance**, not a flag. `1` is every time;
plenty of shipped traits sit well below that, which is worth remembering when a
buff "seems slow" — it is usually the trigger's rate, not your code.

### Ramping stat — needs TWO templates

A buff cannot vary its own `stat_buffs` at runtime. Ramping means **stacking**,
which means splitting the job:

- a **controller** that procs on the event and adds a stack, and
- a **stat carrier** holding one step's worth, with `max_stacks`.

A counter in `template_data` is the intuitive approach and does nothing —
nothing reads it. The game's own
`broker_passive_non_crits_increase_crit` (`broker_buff_templates.lua:3253`) is
this exact pattern and is worth reading side by side.

Cap the ramp off the step so the two cannot drift — and set **both** fields:

```lua
BuffTemplates.cwah_crit_ramp_stack.max_stacks = math.ceil(1 / CRIT_RAMP_STEP)
BuffTemplates.cwah_crit_ramp_stack.max_stacks_cap = math.ceil(1 / CRIT_RAMP_STEP)
```

`max_stacks` is **not** the limit, despite the name. It only makes the buff
stackable at all — `can_stack = not not template.max_stacks`
(`buff_extension_base.lua:436`). The limit is enforced by `_check_max_stacks_cap`,
which returns "allowed" outright when `max_stacks_cap` is nil (line 565). Set
only `max_stacks` and you get an unbounded ramp that cheerfully reports itself as
`158/20 stacks`. Nothing errors, and the shipped templates set both, so this only
bites templates written by hand.

### Resetting a ramp

Two mechanisms, and the difference matters:

**On an event** — `remove_on_proc = true` on the carrier, with a
`check_proc_func` for the reset condition. The engine calls `force_finish`.

**On going idle** — `conditional_exit_func`, with the carrier itself proccing on
the relevant events to record the time:

```lua
proc_func = function (params, template_data, template_context, t)
    template_data.last_action_t = t
end,
conditional_exit_func = function (template_data, template_context, dt, t)
    return IDLE_RESET < t - template_data.last_action_t
end,
```

**Do not reach for `duration` to do this.** Duration is refreshed by *gaining a
stack* (`refresh_duration_on_stack`), so an action that does not grant a stack
lets the buff expire underneath you. Worse, `set_start_time` clears `_finished`
when the template has a duration (`buff.lua:628`), so an action landing mid-drain
strands you on partial stacks.

**Why it is a reset and not a decay:** setting `_finished` does not remove the
buff outright. `_remove_buff` takes **one stack per call**
(`buff_extension_base.lua:644`), and since `_finished` is never cleared on a
buff with no duration, it runs every frame until the buff is gone — about ten
frames, so a full wipe in a sixth of a second.

### Reacting to something with no proc event

Status effects have none: there is no status-effect system and no "debuff
applied" event. A status effect is just a buff on the *enemy* carrying a keyword
(`burning`, `bleeding`, `electrocuted`, `toxin`), so nothing on your own buff
extension ever sees it. That needs a hook, and **choosing the chokepoint is the
whole problem**:

- `BuffUtils.add_proc_debuff` looks like the tidy answer and is a **trap**.
  Weapon traits route through it, but the Mortis buffs do not use it at all —
  there is not one `target_buff_data` in the whole hordes directory. They call
  `victim_buff_extension:add_internally_controlled_buff_with_stacks` directly.
- `MinionBuffExtension.add_internally_controlled_buff` is where a buff actually
  lands on an enemy, whatever put it there. Hook that.

Two follow-on facts:

- Its neighbour `BuffUtils.add_debuff_on_hit_proc` is captured **by reference**
  into templates at load time, so replacing that field changes nothing.
  `add_proc_debuff` is looked up on the table at call time (`buff_utils.lua:84`),
  which is why it is hookable at all.
- `add_internally_controlled_buff_with_stacks` **loops**, calling the hooked
  method once per stack (`buff_extension_base.lua:408`). A four-stack bleed
  arrives as four separate applications, not one.

Detect status effects by **keyword, not name**: the same effect ships under
several names (`bleed` on a weapon trait, `hordes_ailment_minion_bleed` in
Mortis) and both carry `buff_keywords.bleeding`. Resolve `BuffTemplates` once
into a name set at load and keep the hot path to a hash lookup.

---

### Dealing damage of your own

`Attack.execute` is the entry point, and several shipped Mortis effects are
already exported as callable helpers — grep the hordes directory before writing
one. `HordesBuffsUtilities.trigger_brain_burst_on_target`
(`hordes_buffs_utilities.lua:289`) resolves the head hit zone and actor, executes
the attack and plays the impact effect; the whole of the Flayer buff is a call to
it.

**Damage you deal announces `on_hit` on your own buff extension**
(`attack.lua:605`), so a proc buff that responds to a hit by dealing damage
re-triggers itself. Not as stack recursion — proc events are queued and drained
by the buff system — so it does not blow up with a stack trace. The queue simply
grows every frame and the game slows to a halt with nothing in the log.

Two discriminators, and the choice matters:

- **`params.attack_type ~= attack_types.buff`.** One line, and what the shipped
  buffs use (`hordes_legendary_psyker_buff_templates.lua:152`). The cost is that
  everything you deal this way becomes invisible to *other* buffs that filter on
  ranged or melee.
- **Compare `params.damage_profile` against the exact table you passed.** A
  pointer comparison that identifies only your own damage, so your attacks stay
  ordinary hits to every other buff. Use this when the point of the effect is
  that it procs things.

**The proc queue is small, and it fails silently.** A buff extension holds
`MAX_PROC_EVENTS = 300` proc events per frame (`buff_settings.lua:67`). Past
that, `request_proc_event_param_table` returns nil and `Attack.execute` skips the
`on_hit` announcement entirely (`attack.lua:570`) — no error, one warning line
per drop, and every on-hit buff in the loadout quietly stops firing until the
fight thins out.

**Damage-over-time is what fills it.** Every tick of every burn, bleed and toxin
you have applied is a full `Attack.execute` attributed to you, so status-heavy
loadouts scale proc traffic by the number of afflicted enemies times the number
of effects on each. A measured mission with this mod's Contagion buff running
dropped **38,952** procs, peaking near 305 a second.

Two consequences worth designing around:

- **A buff that spreads status effects is also a proc-traffic multiplier.** That
  cost is invisible until it starts breaking unrelated buffs.
- **Do not build a feature on a proc event you generate yourself**, if it has to
  be reliable. The round trip is the first thing to break under exactly the
  conditions the feature exists for. Call the effect directly — this mod's arc
  chain publishes an `on_arc_hit` callback for that reason, and the buff that
  reacts to it rejects arc damage on the normal path so it cannot roll twice.

**Do not clone a damage profile to get a unique identity.**
`NetworkLookup.damage_profile_templates` is built once at boot from
`DamageProfileTemplates` (`network_lookup.lua:154`) — the same trap as
`buff_templates`. Reference a shipped profile instead; identity comparison
against it works just as well.

### Borrowing a status effect instead of inventing one

If an effect needs to mark an enemy, prefer a shipped template. `hordes_ailment_shock`
(`hordes_buff_templates.lua:569`) is the pattern: already in `BuffTemplates` and
therefore already in `NetworkLookup`, carries `buff_keywords.electrocuted` so
`MinionState.is_electrocuted` sees it, and ships a `minion_effects` block that
spawns a particle on the target — so it supplies the visuals too. A template of
your own needs all three built by hand.

That also gives you a free per-enemy cooldown. A rule like "this cannot trigger
off an already-electrified enemy" needs no table, no sweeping on death and no
state to lose across a reload: it lives on the enemy, in the game's own system,
and expires on the buff's own duration.

### Hooking a class the game loads lazily

`CLASS` is right for classes the game has already declared, but weapon action
classes (`ActionShootHitScan`, `ActionShootProjectile`, …) are loaded on demand
and are simply absent at mod load — and often still absent when a mission
starts.

**Pass the class name as a string instead** and let DMF do it:

```lua
mod:hook("ActionShootHitScan", "_shoot", function (func, self, ...) ... end)
```

DMF hooks the global `class` function (`dmf/modules/core/hooks.lua:549`) and
re-applies anything it had to delay once the class is declared. No retry loop,
and no race against the first shot of the session.

### Changing what a method sees

When you need an engine method to behave differently, there is usually a choice
between rewriting the state it reads and rewriting an argument it is handed.
**Prefer the argument, and check writability before assuming the other option
exists at all.**

Unit-data components look uniformly writable and are not. `shooting_rotation`
takes a write; `first_person.rotation` hard-errors —

```
player_unit_data_extension.lua:501: Trying to write to "rotation" in read only
component "first_person"
```

— which is a `ferror`, so it takes the game down rather than failing quietly.
There is no flag to test in advance; read the component config, or find a
different lever.

The different lever is usually one call further down, where a computed value
stops being a component read and becomes a plain argument. Direction is derived
from `first_person.rotation` inside `_fire_projectile`, but arrives at
`ProjectileUnitLocomotionExtension._switch_to_manual_state_helper` as a vector
you can simply rotate. Hooking there needs no writes at all.

If the angle has to cross a call you do not control, a module local set
immediately before and cleared immediately after is sound **only** when the
inner call is synchronous, happens once, and cannot re-enter. Clear it on every
path out, including the failure one.

## Units and clamps

Getting these wrong is a 100× error that looks like nothing happening.

- **Write the bonus, not the multiplier.** `attack_speed` is an
  `additive_multiplier` with a base of 1 (`buff_settings.lua:659`), and shipped
  buffs write `0.2` to mean +20%. Per-stack for a 2% ramp is `0.02`.
- **Crit chance is clamped to 1** (`critical_strike.lua:33`) and rounded to two
  decimals before rolling, so it is *guaranteed* from 99.5% and anything above
  that is dead stat weight. Conversion-to-damage builds read the already-clamped
  value, so they do not rescue the overflow either.

---

## Localization

Two rules, both silent when broken.

**Escape `%` as `%%`.** DMF runs every localization string through
`string.format`, and `safe_string_format` catches the error and returns **nil** —
so the widget title silently becomes nil, with one log line per lookup:

```lua
en = "Increases all damage you deal by 15%%.",
```

**Descriptions are not plain loc keys.** Localizing `HordesBuffsData.description`
directly renders literal `{time}` / `{damage}` placeholders. The numbers live in
a separate `buff_stats` table and are substituted and colour-tagged by the game's
parser — the same call the real card makes
(`constant_element_mission_buffs.lua:145`):

```lua
MissionBuffsParser.get_formated_buff_description(buff_data, Color.ui_terminal(255, true))
```

---

## Icons

Buff icons live in the Mortis level package and are **not resident in a normal
mission**, which is why cards show placeholder hexagons. Loading
`content/levels/horde/missions/mission_psykhanium` fixes both icons and buff
particle effects at the source — measured at about half a second warm, once per
run, streamed alongside the mission's own assets.

If you draw an icon in your own UI: it is a **material value**, not the texture
the pass draws. The pass draws a container material and the icon goes in as
`material_values.icon`. Passing the icon path as `value` renders a blank white
square.

---

## Verifying

Attachment and effect are **separate questions**, and a buff can be attached and
do nothing. This mod reports both, as a snapshot written to the log every ten
seconds whenever debug logging is on (and on demand via `/cw_verify`):

```
--- custom buffs ---
held: cwah_custom_damage, cwah_crit_ramp, cwah_arc_chain
damage stat_buff multiplier: 1.150 (1.0 = no bonus)
crit ramp: 7/20 stacks (+35% crit)
  cwah_arc_chain: 4
  cwah_arc_chain_attempts: 19
  cwah_arc_chain_jumps: 11
  cwah_crit_ramp: 7
```

Three things worth stealing from the shape of that:

**Log it passively rather than on demand.** The interesting failures are shapes
over time — a count that climbs while the player stands still, a guard that stops
rejecting once a fight gets dense. Those are obvious across a series of snapshots
and invisible in one, and the single snapshot you get by typing a command is
never taken at the moment things went wrong. Suppress unchanged snapshots so a
quiet stretch does not bury the log.

**Dump counters generically.** A hand-written line per buff is the thing that
rots the next time you add one. Iterate whatever the proc funcs bumped, sort it,
drop the zeroes; the raw keys read fine, and what a counter *means* belongs in a
comment next to the code that bumps it.

**Count both halves of anything conditional.** "How many times could we have
fired" against "how many times did we" separates a suppressed effect from a
trigger that is simply not firing as often as it looks like it should — which are
different bugs with the same symptom.

**Park debug counters on the `mod` table, not in file locals.** A live buff
instance keeps the `proc_func` closure it was created with; a mod reload rebuilds
the template but does not touch buffs already on the player, so a fresh local
would leave the old closure counting into an orphaned table. The symptom is a
working proc buff reporting zero.

---

## Never `require` an engine class to hook it

Read it from `CLASS` instead:

```lua
local MinionBuffExtension = rawget(_G, "CLASS")
MinionBuffExtension = MinionBuffExtension and MinionBuffExtension.MinionBuffExtension
```

Mods load during boot, before many engine globals exist, so a module touching one
at file scope throws — `minion_buff_extension` pulls in `buff_extension_base`,
which does `Network.type_info("buff_index_array")` at file scope.

**And a require that throws is permanently unrecoverable.** Lua leaves a sentinel
in `package.loaded` and every later require of that module fails for the rest of
the session with `loop or previous error loading module`. `pcall` does not save
you: a speculative `pcall(require, ...)` at boot poisons the module for the
*game*, which then crashes loading its extension systems. There is no retry.

Iterating hides all of this — a mid-session reload finds the module already
cached, so the require returns without executing anything and looks fine until a
cold boot.

---

## Pitfall index

| Symptom | Cause |
|---|---|
| `table index is nil` in `_add_buff` | `template.name` not set |
| `NetworkLookup ... does not contain key` | no network id appended |
| Crash at mission start, far from any buff | `filter_category` missing from the `HordesBuffsData` entry |
| Widget title is nil, one log line per lookup | unescaped `%` in a loc string |
| Card shows `<loc_cwah_x_title>` | key missing from the localization file, or never copied into DMF's global database |
| Card shows a literal `{token}` | `{}` expansion is unreachable for mod keys; use `%s` and format at registration |
| Description shows `{time}` / `{damage}` | localized directly instead of through `MissionBuffsParser` |
| Card art is a question-mark hexagon | Mortis package not resident |
| Icon is a blank white square | icon passed as the texture instead of a material value |
| Ramp does nothing | counter in `template_data` — needs a second, stacking template |
| Stat is 100× too strong or weak | wrote the multiplier where the bonus was wanted |
| Crit above ~99.5% does nothing | clamped to 1, by design |
| Proc counter reads zero on a working buff | closure state in a file local, lost on reload |
| Hook fires four times for one bleed | `..._with_stacks` loops per stack |
| Hook never fires for Mortis buffs | hooked `BuffUtils.add_proc_debuff`; they do not use it |
| Game crashes loading extension systems | a `pcall(require, ...)` poisoned the module at boot |
| Frame time slides to a halt, nothing in the log | a proc buff deals damage, which announces `on_hit`, which re-procs it |
| `NetworkLookup ... does not contain key` naming a damage profile | cloned a damage profile; the lookup is built at boot like `buff_templates` |
| Hook on a weapon action never fires | read from `CLASS` at load, where action classes do not exist yet — hook by string name |
| Shots after a fanned volley go off at an angle | wrote `action_component.shooting_rotation` and did not restore it on every path |
| `Trying to write to "x" in read only component "y"` | not every unit_data component is writable; find an argument to change instead |
| Four buff applications for one spread status effect | `..._with_stacks` loops per stack; clamp what you copy |
| A ramp reports `158/20 stacks` and never caps | set `max_stacks` but not `max_stacks_cap`; the latter is the real limit |
| On-hit buffs stop firing in big fights only | proc queue full (300/frame); grep the log for `Out of proc event tables` |
| `attempt to call method '...' (a nil value)` on a buff extension | it is a husk; `PlayerHuskBuffExtension` is not a `BuffExtensionBase` |
| A hook misbehaves in a mission your mod did not start | hooks outlive missions — gate on your own "is a run live" flag, not just `is_enabled()` |

---

## Where the card text lives

Titles and descriptions go in `ChaosWastesAtHome_localization.lua` under
`loc_<id>_title` / `loc_<id>_description`, not in the catalogue entry. Two
things make that less obvious than it sounds.

**The keys must reach the GLOBAL localization database.** A mod's own table is
only reachable through `mod:localize`, and the card is not drawn by you:
`MissionBuffsParser` renders it with `Managers.localization:localize`
(`mission_buffs_parser.lua:125`), the game's manager, which has never heard of
your mod. DMF hooks that manager and checks `_global_localization_database`
first (`dmf/modules/core/localization.lua:95`); `add_global_localize_strings` is
the only way in. So the strings live in the localization file *and* get copied
into the global database at load.

**`{token}` placeholders do not work for mod-added buffs.** The shipped cards
put `{time}` / `{damage}` in the string and let the parser fill them from a
`buff_stats` table — but that expansion happens in
`LocalizationManager._process_string`, and DMF's hook answers the lookup and
returns *before* the game's `localize` ever runs. A `{token}` in a
mod-registered string reaches the card verbatim.

Use `%s` and substitute at registration instead. That keeps numbers owned by the
code constants rather than duplicated into prose that silently goes stale when
you retune.

**Double every literal per-cent in a value you substitute.** DMF `string.format`s
the registered string again on its way out of the global lookup, so a lone `%`
there is an invalid specifier — which fails the whole lookup and puts the raw key
on the card. `_pct` in `custom_buffs.lua` returns `10%%` for exactly this reason.

**A reload will not update card text.** `add_global_localize_strings` refuses to
overwrite a key it already holds, so editing a description needs a full restart
to see.
