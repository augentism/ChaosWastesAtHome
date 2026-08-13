local mod = get_mod("ChaosWastesAtHome")

local BuffSettings = require("scripts/settings/buff/buff_settings")
local BuffTemplates = require("scripts/settings/buff/buff_templates")
-- NOT required here: see install_hooks. minion_buff_extension pulls in
-- buff_extension_base, which reads the `Network` global at file scope, and that
-- global does not exist yet while mods are loading at boot.
local CheckProcFunctions = require("scripts/settings/buff/helper_functions/check_proc_functions")
local HordesBuffsData = require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")
local MissionBuffsAllowedBuffs = require("scripts/managers/mission_buffs/mission_buffs_allowed_buffs")
local MissionBuffsSettings = require("scripts/managers/mission_buffs/mission_buffs_settings")
local Toughness = require("scripts/utilities/toughness/toughness")

local buff_categories = BuffSettings.buff_categories
local proc_events = BuffSettings.proc_events
local stat_buffs = BuffSettings.stat_buffs

-- Custom buffs, in their own filtering category so they can be weighted
-- separately from the shipped Mortis ones.
--
-- Everything here works because the game's settings tables are plain and
-- mutable -- `settings()` is literally `return data_table`, no freezing -- so a
-- mod can add to BuffTemplates, HordesBuffsData and the allowed-buff pools at
-- load time and the buff system treats the result as native.
--
-- To add a buff: add ONE entry to CATALOGUE below. Everything a buff needs --
-- the template, its `name`, its network id, its card data, its loc strings and
-- its pool membership -- is derived from that entry by `register`. The five
-- worked examples cover the shapes worth copying.
--
-- The catalogue shape is lifted from Pilgrimage's bot-passive system, which had
-- the same problem and solved it well: declaring a buff in five places six
-- hundred lines apart is how you end up shipping one that crashes when picked.

local custom_buffs = {}

-- Bumped by proc buffs when they fire, so /cw_verify can prove an effect ran
-- rather than just that the buff is attached. A passive stat buff has nothing
-- to count -- its multiplier is read straight off the extension instead.
--
-- Parked on `mod` so it survives a mod reload, following the same pattern as
-- pause.lua. Not cosmetic: a reload rebuilds the buff template, but a buff
-- already applied to the player keeps the proc_func closure it was created
-- with. A fresh local table would leave that closure counting into an
-- orphaned table while the report read an empty one -- the counter would sit
-- at zero for a buff that was firing perfectly well.
local proc_counts = mod._custom_buff_procs or {}

mod._custom_buff_procs = proc_counts

-- Its own category rather than reusing "regular".
--
-- filtering_categories is an enum whose metatable errors on unknown reads, so
-- this has to be registered before anything asks for it -- but the metatable
-- only guards __index, not __newindex, so adding the key is allowed and makes
-- every later read safe.
local CATEGORY = "custom"

MissionBuffsSettings.filtering_categories[CATEGORY] = CATEGORY

-- Icons are reused from the shipped horde set. They are only loaded because the
-- mod pulls in the Mortis package -- a genuinely custom texture would need a
-- mod bundle, which is a much larger job.
local ICON_ROOT = "content/ui/textures/icons/buffs/hud/horde_buffs/small_buffs/"

-- Every buff this mod defines, in one list.
--
-- Entry fields:
--   id            required, and the BuffTemplates key
--   pool          true = offered in legendary picks. false/absent = a helper
--                 applied by another buff, which still needs a name and a
--                 network id but no card data and no pool membership
--   title         English name. The loc KEY is derived as loc_<id>_title, the
--   description   same way the game derives them in hordes_buffs_data.lua, so
--                 there is no second place for the two to disagree
--   icon          short name, appended to ICON_ROOT. Pool entries only
--   stat_buffs    shorthand for a plain passive buff
--   template      factory returning the full template, for anything else. Given
--                 a factory, `stat_buffs` is ignored -- put them in the table
--
-- Entries are appended by each example section below, so the file still reads
-- as five worked examples rather than one wall of data.
local CATALOGUE = {}

local function _add(entry)
	CATALOGUE[#CATALOGUE + 1] = entry

	return entry
end

-- ---------------------------------------------------------------------------
-- Example 1: a passive stat buff
-- ---------------------------------------------------------------------------

-- The `stat_buffs` shorthand: register builds a plain passive template from it.
-- `filter_category` is written for you, which matters -- omitting it is a
-- nil-index crash at mission start, a long way from the buff that caused it.
_add({
	id = "cwah_custom_damage",
	pool = true,
	title = "Wrath Unbound",
	description = "Increases all damage you deal by 15%%.",
	icon = "hordes_buff_damage_increase",
	stat_buffs = {
		[stat_buffs.damage] = 1.15,
	},
})

-- ---------------------------------------------------------------------------
-- Example 2: a proc buff that reacts to an event
-- ---------------------------------------------------------------------------

local TOUGHNESS_PER_ELITE_KILL = 15

-- Anything past a plain stat buff supplies a `template` factory instead.
_add({
	id = "cwah_custom_toughness_on_elite_kill",
	pool = true,
	title = "Bulwark",
	description = "Killing an elite restores " .. TOUGHNESS_PER_ELITE_KILL .. "%% toughness.",
	icon = "hordes_buff_toughness_on_melee_kills",
	template = function ()
		return {
			-- server_only_proc_buff, not proc_buff: the effect changes
			-- authoritative state (toughness), so it must not run predicted on
			-- the client as well.
			class_name = "server_only_proc_buff",
			max_stacks = 1,
			max_stacks_cap = 1,
			predicted = false,
			buff_category = buff_categories.hordes_buff,
			proc_events = {
				[proc_events.on_kill] = 1,
			},
			check_proc_func = CheckProcFunctions.on_elite_kill,
			proc_func = function (params, template_data, template_context)
				Toughness.replenish_percentage(template_context.unit, TOUGHNESS_PER_ELITE_KILL / 100, false)

				proc_counts.cwah_custom_toughness_on_elite_kill =
					(proc_counts.cwah_custom_toughness_on_elite_kill or 0) + 1

				mod:debug_log("cwah_custom_toughness_on_elite_kill proc #%d",
					proc_counts.cwah_custom_toughness_on_elite_kill)
			end,
		}
	end,
})

-- ---------------------------------------------------------------------------
-- Example 3: a pair of templates -- ramp a stat, reset it on a condition
-- ---------------------------------------------------------------------------
--
-- Crit chance climbs with every non-critical hit and resets the moment you
-- crit. Modelled directly on the game's own `broker_passive_non_crits_increase_crit`
-- (broker_buff_templates.lua:3253), which is the same mechanic restricted to
-- melee -- worth reading side by side if you want to build something similar.
--
-- The shape to copy is the split into two templates. A buff cannot vary its own
-- stat_buffs at runtime, so ramping means *stacking*: one template holds one
-- step's worth of the stat and stacks, and a second template watches for the
-- event that adds a stack. Trying to do it in a single template with a counter
-- in template_data does not work -- nothing would read the counter.

local CRIT_RAMP_STEP = 0.05

-- The controller. `pool = true` -- this is the one offered; it holds no stats
-- itself and exists only to add a stack on every non-critical hit.
_add({
	id = "cwah_crit_ramp",
	pool = true,
	title = "Building Fury",
	description = "Every hit that does not critically strike raises your critical chance by "
		.. math.floor(CRIT_RAMP_STEP * 100) .. "%%. Resets when you critically strike.",
	icon = "hordes_buff_critical_chance_on_dodge",
	template = function ()
		return {
			class_name = "proc_buff",
			max_stacks = 1,
			predicted = false,
			buff_category = buff_categories.hordes_buff,
			proc_events = {
				[proc_events.on_hit] = 1,
			},
			check_proc_func = function (params, template_data, template_context, t)
				return not params.is_critical_strike
			end,
			start_func = function (template_data, template_context)
				template_data.buff_extension = ScriptUnit.extension(template_context.unit, "buff_system")
			end,
			proc_func = function (params, template_data, template_context, t)
				template_data.buff_extension:add_internally_controlled_buff("cwah_crit_ramp_stack", t)

				proc_counts.cwah_crit_ramp = (proc_counts.cwah_crit_ramp or 0) + 1
			end,
		}
	end,
})

-- The stat carrier. `pool` absent, so it is registered but never offered -- it
-- is only ever added by the controller. It still gets a name and a network id,
-- which is the whole reason helpers belong in the catalogue rather than in a
-- second list someone can forget to update.
--
-- `remove_on_proc` is what makes the reset work, and it is the whole reason
-- this template procs at all: on a crit the engine calls force_finish on the
-- buff, dropping every stack at once. Removing stacks by hand would need a
-- loop and a nil guard, because remove_internally_controlled_buff_stack
-- indexes _stacking_buffs without checking the buff is there.
-- No buff_category on purpose, matching the shipped equivalent: this is an
-- internal stat carrier, not something the mission-buffs UI should enumerate as
-- a buff the player was granted.
_add({
	id = "cwah_crit_ramp_stack",
	template = function ()
		return {
			class_name = "proc_buff",
			predicted = false,
			remove_on_proc = true,
			always_show_in_hud = true,
			-- A base-game icon on purpose: this one shows in the HUD whether or
			-- not the Mortis package is loaded, unlike the horde buff artwork.
			hud_icon = "content/ui/textures/icons/buffs/hud/zealot/zealot_ability_chastise_the_wicked",
			hud_icon_gradient_map = "content/ui/textures/color_ramps/talent_ability",
			hud_priority = 1,
			proc_events = {
				[proc_events.on_hit] = 1,
			},
			check_proc_func = CheckProcFunctions.on_crit,
			stat_buffs = {
				[stat_buffs.critical_strike_chance] = CRIT_RAMP_STEP,
			},
			-- Cap the ramp at exactly +100%, however the step is tuned.
			-- Straight from the shipped version. Crit chance is clamped to 1
			-- anyway (utilities/attack/critical_strike.lua:33) so stacks past
			-- this point would be silently wasted rather than wrong.
			max_stacks = math.ceil(1 / CRIT_RAMP_STEP),
		}
	end,
})

-- ---------------------------------------------------------------------------
-- Example 4: the same ramp shape, reset by going idle
-- ---------------------------------------------------------------------------
--
-- Attack speed climbs with every hit and resets once you stop fighting.
-- Structurally the crit ramp again -- controller plus stat carrier -- so the
-- only new problem is expiring on time rather than on an event.
--
-- Stacks are added by *hits*, but the idle timer is refreshed by *attacks*: a
-- swing that connects with nothing is still fighting, so it holds the stacks it
-- has without granting more. That split is why this cannot simply be a
-- `duration` on the stat carrier -- duration is refreshed by gaining a stack
-- (refresh_duration_on_stack), which would make a whiffed swing let the buff
-- expire underneath you.

local ATTACK_SPEED_STEP = 0.02
local ATTACK_SPEED_CAP = 0.2
local ATTACK_SPEED_IDLE_RESET = 2

_add({
	id = "cwah_attack_speed_ramp",
	pool = true,
	title = "Relentless",
	description = "Every hit raises your attack speed by " .. math.floor(ATTACK_SPEED_STEP * 100)
		.. "%%, up to " .. math.floor(ATTACK_SPEED_CAP * 100) .. "%%. Resets after "
		.. ATTACK_SPEED_IDLE_RESET .. " seconds without attacking.",
	icon = "hordes_buff_improved_dodge_speed_and_distance",
	template = function ()
		return {
			class_name = "proc_buff",
			max_stacks = 1,
			predicted = false,
			buff_category = buff_categories.hordes_buff,
			proc_events = {
				[proc_events.on_hit] = 1,
			},
			start_func = function (template_data, template_context)
				template_data.buff_extension = ScriptUnit.extension(template_context.unit, "buff_system")
			end,
			proc_func = function (params, template_data, template_context, t)
				template_data.buff_extension:add_internally_controlled_buff("cwah_attack_speed_ramp_stack", t)

				proc_counts.cwah_attack_speed_ramp = (proc_counts.cwah_attack_speed_ramp or 0) + 1
			end,
		}
	end,
})

_add({
	id = "cwah_attack_speed_ramp_stack",
	template = function ()
		return {
			class_name = "proc_buff",
			predicted = false,
			always_show_in_hud = true,
			hud_icon = "content/ui/textures/icons/buffs/hud/cryptic/cryptic_melee_attacks_give_melee_attack_speed",
			hud_icon_gradient_map = "content/ui/textures/color_ramps/talent_ability",
			hud_priority = 1,
			-- Every way of swinging or firing, hit or miss. on_sweep_finish
			-- closes a melee swing whether or not it connected, on_shoot closes
			-- a shot the same way, and on_hit covers damage arriving through
			-- neither.
			proc_events = {
				[proc_events.on_hit] = 1,
				[proc_events.on_shoot] = 1,
				[proc_events.on_sweep_finish] = 1,
			},
			stat_buffs = {
				-- The bonus, not the multiplier: attack_speed is an
				-- additive_multiplier with a base of 1, so shipped buffs write
				-- 0.2 to mean +20%.
				[stat_buffs.attack_speed] = ATTACK_SPEED_STEP,
			},
			start_func = function (template_data, template_context)
				template_data.last_action_t = template_context.buff:start_time()
			end,
			-- No check_proc_func: the point is that the attack happened at all.
			proc_func = function (params, template_data, template_context, t)
				template_data.last_action_t = t
			end,
			-- Returning true sets _finished, and the extension then drops one
			-- stack per frame until the buff is gone -- a full reset rather than
			-- a slow decay, because _finished is never cleared once set on a
			-- buff with no duration.
			conditional_exit_func = function (template_data, template_context, dt, t)
				return ATTACK_SPEED_IDLE_RESET < t - template_data.last_action_t
			end,
			max_stacks = math.ceil(ATTACK_SPEED_CAP / ATTACK_SPEED_STEP),
		}
	end,
})

-- ---------------------------------------------------------------------------
-- Example 5: reacting to something the buff system has no event for
-- ---------------------------------------------------------------------------
--
-- Applying a status effect to an enemy also applies a second, random one.
--
-- Status effects are not a first-class concept in the engine -- there is no
-- status_effect system and no "debuff applied" proc event. A status effect is
-- just a buff living on the *enemy* that carries a keyword (burning, bleeding,
-- electrocuted, toxin), so nothing on the player's own buff extension ever
-- sees it happen. That is why this one needs a hook where the others did not.
--
-- The hook goes on MinionBuffExtension.add_internally_controlled_buff, which is
-- where a buff actually lands on an enemy, whatever put it there.
--
-- BuffUtils.add_proc_debuff looks like the tidier chokepoint and is a trap:
-- weapon traits route through it, but the Mortis buffs do not use it at all
-- (there is not one target_buff_data in the whole hordes directory) -- they
-- call victim_buff_extension:add_internally_controlled_buff_with_stacks
-- directly. Hooking it caught none of the buffs this mod exists to combine.
-- The extension method is the one point every path has to pass through.
--
-- The cost is that this fires for every buff applied to every enemy, so the
-- first guard is a single hash lookup and everything expensive sits behind it.

local CASCADE_BUFF = "cwah_status_cascade"

-- What makes a buff a "status effect". Keyword-based rather than a name list
-- because the same effect ships under several names -- bleed on a weapon trait
-- is `bleed`, the Mortis version is `hordes_ailment_minion_bleed` -- and both
-- carry buff_keywords.bleeding.
local STATUS_KEYWORDS = {
	bleeding = true,
	burning = true,
	electrocuted = true,
	electrocuted_chain_lightning = true,
	electrocuted_shock_mine = true,
	toxin = true,
	warp_fire = true,
}

-- Resolved once from BuffTemplates into a name -> true set, so the hot path is
-- a hash lookup instead of a keyword walk per application.
local status_template_set = nil

-- The pool to roll from. Left as data because which effects feel fair together
-- is a tuning question, not a structural one -- add or remove freely.
local STATUS_EFFECTS = {
	{ label = "soulblaze",     buff = "warp_fire" },
	{ label = "fire",          buff = "flamer_assault" },
	{ label = "electrocution", buff = "shock_grenade_interval" },
	{ label = "bleed",         buff = "bleed" },
	{ label = "chem toxin",    buff = "neurotoxin_interval_buff" },
	{ label = "brittleness",   buff = "rending_debuff" },
}

-- Carries nothing itself. All the behaviour lives in the hook, which checks
-- whether the attacking player has this buff -- so the template exists purely
-- to be pickable and to be asked about.
_add({
	id = CASCADE_BUFF,
	pool = true,
	title = "Contagion",
	description = "Whenever you afflict an enemy with a status effect, they suffer a second one at random - "
		.. "soulblaze, fire, electrocution, bleed, chem toxin or brittleness.",
	icon = "hordes_buff_rending_on_ranged_critical_hit",
	template = function ()
		return {
			class_name = "buff",
			max_stacks = 1,
			max_stacks_cap = 1,
			predicted = false,
			buff_category = buff_categories.hordes_buff,
		}
	end,
})

-- Deliberately "some other effect", never the one that just landed.
--
-- Matching on the name alone is not enough: the effect that triggered this may
-- be `hordes_ailment_minion_bleed` while the pool holds `bleed`, and rolling
-- that would hand back the same status under a different name. So a candidate
-- is excluded if it shares a status keyword with what was just applied.
local function _shares_status_keyword(template_a, template_b)
	local keywords_a = template_a and template_a.keywords
	local keywords_b = template_b and template_b.keywords

	if not keywords_a or not keywords_b then
		return false
	end

	for i = 1, #keywords_a do
		local keyword = keywords_a[i]

		if STATUS_KEYWORDS[keyword] then
			for j = 1, #keywords_b do
				if keywords_b[j] == keyword then
					return true
				end
			end
		end
	end

	return false
end

local function _roll_other_status(applied_buff_name)
	local applied_template = BuffTemplates[applied_buff_name]
	local candidates = {}

	for _, entry in ipairs(STATUS_EFFECTS) do
		local candidate = BuffTemplates[entry.buff]

		if candidate and entry.buff ~= applied_buff_name and not _shares_status_keyword(applied_template, candidate) then
			candidates[#candidates + 1] = entry.buff
		end
	end

	if #candidates == 0 then
		return nil
	end

	return candidates[math.random(#candidates)]
end

-- Scan BuffTemplates once for anything carrying a status keyword.
local function _build_status_template_set()
	local set = {}

	for template_name, template in pairs(BuffTemplates) do
		local keywords = type(template) == "table" and template.keywords

		if keywords then
			for i = 1, #keywords do
				if STATUS_KEYWORDS[keywords[i]] then
					set[template_name] = true

					break
				end
			end
		end
	end

	-- The pool's own entries, so a rolled effect always counts as a status
	-- effect even if it carries no keyword -- rending_debuff is pure stat_buffs.
	for _, entry in ipairs(STATUS_EFFECTS) do
		set[entry.buff] = true
	end

	return set
end

-- The applier passes ("owner_unit", unit, "source_item", item) as varargs.
local function _owner_from_varargs(...)
	for i = 1, select("#", ...) - 1 do
		if select(i, ...) == "owner_unit" then
			return select(i + 1, ...)
		end
	end

	return nil
end

-- Who applied a status effect that is already on this enemy.
--
-- The refresh path carries no owner -- refresh_duration_of_stacking_buff takes
-- only (buff_name, t) -- so it has to be recovered from the stack that is
-- already there, which the same player applied.
local function _owner_of_existing_buff(victim_extension, template_name)
	local ok, buffs = pcall(victim_extension.buffs, victim_extension)

	if not ok or type(buffs) ~= "table" then
		return nil
	end

	for i = 1, #buffs do
		local instance = buffs[i]
		local template = instance:template()

		if template and template.name == template_name then
			local context = instance:template_context()

			return context and context.owner_unit
		end
	end

	return nil
end

-- Cascades are deliberately not rate-limited.
--
-- Worth knowing what that means, because it is not one cascade per hit:
-- add_internally_controlled_buff_with_stacks loops, calling the hooked method
-- once *per stack* (buff_extension_base.lua:408), so a four-stack bleed rolls
-- four extra effects. Sustained sources compound it -- a flamer re-applies
-- burning every frame it is on target, and a capped stack still refreshes.
-- That volume is the intended behaviour here; tracking state per enemy to damp
-- it is what would cost memory, so nothing is tracked.
--
-- `cascading` is a plain boolean and the only state this hook keeps. It exists
-- to stop our own application from re-entering the hook, not to throttle.
local hooks_installed = false
local cascading = false

-- Deferred until something calls this from inside a mission, never at mod load.
--
-- The class is read from the CLASS registry rather than required. Two separate
-- reasons, and the second one is the dangerous one:
--
-- 1. minion_buff_extension executes buff_extension_base, which does
--    `Network.type_info("buff_index_array")` at file scope. During boot-time
--    mod loading the `Network` global does not exist yet, so the require
--    throws.
--
-- 2. A require that throws is not recoverable, and pcall does not make it so.
--    Lua leaves a sentinel in package.loaded, and *every later require of that
--    module fails for the rest of the session* with "loop or previous error
--    loading module". So a speculative pcall(require, ...) at boot does not
--    merely fail -- it poisons the module for the game itself, which then
--    crashes when it loads its extension systems. Retrying a require is not a
--    thing that works.
--
-- CLASS is populated when the game loads the class normally, so this is simply
-- nil until then, and nil is safe to test for. Same idiom as AutoMark.
custom_buffs.install_hooks = function ()
	if hooks_installed then
		return true
	end

	local MinionBuffExtension = rawget(_G, "CLASS")
	MinionBuffExtension = MinionBuffExtension and MinionBuffExtension.MinionBuffExtension

	if not MinionBuffExtension then
		mod:debug_log("MinionBuffExtension not registered yet - deferring status cascade hook")

		return false
	end

	hooks_installed = true

	-- Shared by both entry points below.
	local function try_cascade(victim_extension, template_name, owner_unit, t)
		-- Cheapest test first: this runs for every buff on every enemy.
		if cascading or not status_template_set or not status_template_set[template_name] then
			return
		end

		if not mod:is_enabled() then
			return
		end

		-- Without an owner there is nobody to credit, and no way to tell our
		-- player's status effects from an enemy's or a hazard's.
		if not owner_unit or not HEALTH_ALIVE[owner_unit] then
			return
		end

		local owner_buffs = ScriptUnit.has_extension(owner_unit, "buff_system")

		if not owner_buffs or not owner_buffs:has_buff_using_buff_template(CASCADE_BUFF) then
			return
		end

		-- Counted before the roll: this is "a status effect you applied that we
		-- would cascade from". Comparing it with the cascade count separates a
		-- cascade that is being suppressed from a trigger that simply is not
		-- firing as often as it looks like it should.
		proc_counts.cwah_status_trigger = (proc_counts.cwah_status_trigger or 0) + 1

		local extra = _roll_other_status(template_name)

		if not extra then
			return
		end

		-- Applied to the victim's own extension, which we are already holding,
		-- so the enemy unit never needs to be resolved. The re-entry this causes
		-- is what the `cascading` guard is for.
		cascading = true

		local ok, err = pcall(victim_extension.add_internally_controlled_buff_with_stacks, victim_extension,
			extra, 1, t, "owner_unit", owner_unit)

		cascading = false

		if ok then
			proc_counts.cwah_status_cascade = (proc_counts.cwah_status_cascade or 0) + 1

			mod:debug_log("status cascade: %s -> %s", template_name, extra)
		else
			mod:error("status cascade could not apply '%s': %s", extra, tostring(err))
		end
	end

	-- hook_safe, so the original effect lands first and a fault here cannot
	-- stop a buff from being applied. hook_safe callbacks receive the hooked
	-- method's own arguments -- self included, no leading `func`.
	mod:hook_safe(MinionBuffExtension, "add_internally_controlled_buff", function (self, template_name, t, ...)
		try_cascade(self, template_name, _owner_from_varargs(...), t)
	end)

	-- The capped case, and the reason it needs its own hook: when the stacks are
	-- already at max, BuffUtils.add_proc_debuff stops calling the method above
	-- and calls this instead (buff_utils.lua:66), so a maxed-out bleed refreshed
	-- for the tenth time never reached the cascade at all.
	--
	-- Hooking the name on MinionBuffExtension rather than BuffExtensionBase,
	-- where it is actually defined: assigning to the subclass shadows the
	-- inherited method for enemies only, leaving players' own status effects
	-- alone.
	mod:hook_safe(MinionBuffExtension, "refresh_duration_of_stacking_buff", function (self, buff_name, t)
		try_cascade(self, buff_name, _owner_of_existing_buff(self, buff_name), t)
	end)

	mod:info("status cascade hooks installed")

	return true
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

-- Loc keys are DERIVED from the id -- loc_<id>_title and loc_<id>_description --
-- exactly as hordes_buffs_data.lua derives them for the shipped buffs. There is
-- no second place for a key and a template to disagree.
--
-- Descriptions are run through Managers.localization:localize, so literal text
-- in HordesBuffsData renders as a missing-key marker; DMF's global database is
-- what makes a mod-defined key resolve like a shipped one.
--
-- Remember %% not %: DMF runs every localization string through string.format,
-- so a literal per-cent sign is read as a format specifier and the lookup
-- silently returns nil.
local function _title_key(id)
	return "loc_" .. id .. "_title"
end

local function _description_key(id)
	return "loc_" .. id .. "_description"
end

do
	local strings = {}

	for _, entry in ipairs(CATALOGUE) do
		if entry.pool then
			strings[_title_key(entry.id)] = { en = entry.title or entry.id }
			strings[_description_key(entry.id)] = { en = entry.description or "" }
		end
	end

	mod:add_global_localize_strings(strings)
end

-- Every template also needs an entry in the network lookup.
--
-- NetworkLookup.buff_templates is built once at boot from whatever is in
-- BuffTemplates at that moment, and mods load afterwards -- so a template added
-- by a mod is never in it. PlayerUnitBuffExtension._add_rpc_synced_buff reads
-- the id unconditionally, *before* it checks whether the player is even remote,
-- and the lookup's metatable errors on an unknown key rather than returning
-- nil. So applying a custom buff crashes in solo too, despite nothing ever
-- going over the wire.
--
-- The lookup is bidirectional -- lookup[i] = name and lookup[name] = i -- and
-- only __index is guarded, so appending is allowed. Membership has to be tested
-- with rawget: a plain read of a missing key is the crash itself.
--
-- Solo-only *today*, but deliberately not solo-only by construction.
--
-- The id is an index into a table no vanilla peer has, so it must never be
-- transmitted -- which holds because a solo session has no remote players. If a
-- peer-to-peer path ever exists and every peer runs this mod, the indices only
-- agree if every machine computes the same one for the same name. So the names
-- are appended in SORTED order (see register_network_lookup), which makes an
-- index a pure function of the name set rather than of catalogue order.
--
-- What that still does not survive: peers on different mod versions (different
-- name sets), or another mod appending to the same lookup, since the base offset
-- then depends on mod_load_order.txt. Both would need a version handshake.
--
-- Idempotent, and called again per mission in case the mod loaded before
-- NetworkLookup existed.
custom_buffs.ensure_network_id = function (buff_name)
	local network_lookup = rawget(_G, "NetworkLookup")
	local buff_lookup = network_lookup and network_lookup.buff_templates

	if not buff_lookup then
		mod:error("NetworkLookup.buff_templates missing - custom buffs will crash when applied")

		return false
	end

	if not rawget(buff_lookup, buff_name) then
		local index = #buff_lookup + 1

		buff_lookup[index] = buff_name
		buff_lookup[buff_name] = index

		mod:debug_log("network lookup: %s = %d", buff_name, index)
	end

	return true
end

-- Every template the mod defines, pickable or not, sorted.
--
-- Sorted rather than catalogue order so the network ids assigned below are a
-- pure function of the name set. Reordering the catalogue then cannot change an
-- id, which is what a future peer-to-peer path would need.
local function _all_template_names()
	local names = {}

	for _, entry in ipairs(CATALOGUE) do
		names[#names + 1] = entry.id
	end

	table.sort(names)

	return names
end

-- Just the pickable ones, in catalogue order -- this only drives the pool and
-- the menu, where the author's ordering is the useful one.
local function _pool_names()
	local names = {}

	for _, entry in ipairs(CATALOGUE) do
		if entry.pool then
			names[#names + 1] = entry.id
		end
	end

	return names
end

custom_buffs.register_network_lookup = function ()
	local ok = true

	for _, buff_name in ipairs(_all_template_names()) do
		ok = custom_buffs.ensure_network_id(buff_name) and ok
	end

	return ok
end

local registered = false

custom_buffs.register = function ()
	if registered then
		return
	end

	registered = true

	-- Build every template from its catalogue entry, then everything the buff
	-- system needs alongside it. One loop, so a new entry cannot be half
	-- registered.
	for _, entry in ipairs(CATALOGUE) do
		local template

		if entry.template then
			template = entry.template()
		elseif entry.stat_buffs then
			-- The shorthand: a plain passive buff.
			template = {
				class_name = "buff",
				max_stacks = 1,
				max_stacks_cap = 1,
				predicted = false,
				buff_category = buff_categories.hordes_buff,
				stat_buffs = entry.stat_buffs,
			}
		else
			mod:error("catalogue entry '%s' has neither a template nor stat_buffs - skipped",
				tostring(entry.id))
		end

		if template then
			-- Every template needs a `name` matching its key.
			--
			-- The game sets this for shipped buffs when it assembles
			-- BuffTemplates (`template.name = template.name or name`), so a
			-- template added straight into the table never gets one.
			-- BuffExtensionBase._add_buff then uses it as a table key for stack
			-- tracking, and a nil key crashes the moment the buff is applied --
			-- not when it is offered, so the card looks fine right up until you
			-- pick it.
			template.name = template.name or entry.id

			BuffTemplates[entry.id] = template

			-- Card data for the pickable ones only. filter_category is mandatory
			-- and easy to forget by hand: init_legendary_buffs_pool_for_player
			-- indexes the pool table by it and inserts into the result, so
			-- omitting it is a nil-index crash at mission start, a long way from
			-- the buff that caused it.
			if entry.pool then
				HordesBuffsData[entry.id] = {
					title = _title_key(entry.id),
					description = _description_key(entry.id),
					icon = entry.icon and (ICON_ROOT .. entry.icon) or nil,
					is_family_buff = entry.is_family_buff or false,
					filter_category = CATEGORY,
				}
			end
		end
	end

	custom_buffs.register_network_lookup()

	-- The cascade pool names shipped templates rather than ones we define, so a
	-- game patch renaming one would otherwise show up as a status effect that
	-- silently never rolls. Checked once, loudly.
	for _, entry in ipairs(STATUS_EFFECTS) do
		if not BuffTemplates[entry.buff] then
			mod:error("status effect '%s' points at missing buff template '%s' - it will never be rolled",
				entry.label, entry.buff)
		end
	end

	status_template_set = _build_status_template_set()

	local status_count = 0

	for _ in pairs(status_template_set) do
		status_count = status_count + 1
	end

	mod:info("status cascade recognises %d status-effect template(s)", status_count)

	custom_buffs.install_hooks()

	local generic = MissionBuffsAllowedBuffs.legendary_buffs.generic
	local pool = _pool_names()

	for _, buff_name in ipairs(pool) do
		local already = false

		for _, existing in ipairs(generic) do
			if existing == buff_name then
				already = true

				break
			end
		end

		if not already then
			generic[#generic + 1] = buff_name
		end
	end

	mod:info("registered %d custom buff(s) in category '%s' (%d template(s) total)",
		#pool, CATEGORY, #CATALOGUE)
end

-- How often the custom category comes up relative to the shipped ones.
--
-- _pop_legendary_buff_from_players_pool weights categories per wave and falls
-- back to 1 for anything it does not recognise, so this only needs to write the
-- entries it wants to differ. Applied per mission because the setting can
-- change between them.
custom_buffs.apply_weight = function ()
	local weight = mod:get("custom_buff_weight") or 1

	for _, rates in pairs(MissionBuffsSettings.filtering_categories_pick_rate_per_wave) do
		rates[CATEGORY] = weight
	end

	mod:debug_log("custom buff category weight set to", weight)
end

-- Answers "is this buff actually doing anything", which the HUD cannot.
--
-- Attachment and effect are separate questions, so both get reported: a buff
-- can be listed on the player and still do nothing if its stat key is wrong or
-- its check_proc_func never passes.
-- Report lines are echoed to chat, and mod:echo runs its message through
-- string.format -- so any literal % we produce (crit percentages, here) has to
-- be doubled or the echo crashes instead of printing. Applied at every exit so
-- a later line cannot reintroduce the bug.
local function _echo_safe(lines)
	for i = 1, #lines do
		lines[i] = (lines[i]:gsub("%%", "%%%%"))
	end

	return lines
end

custom_buffs.report = function ()
	local lines = {}
	local player = Managers.player and Managers.player:local_player_safe(1)
	local player_unit = player and player.player_unit

	if not player_unit or not Unit.alive(player_unit) then
		return _echo_safe({ "no local player unit - are you in a mission?" })
	end

	local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")

	if not buff_extension then
		return _echo_safe({ "no buff extension on the player unit" })
	end

	-- Attached: walks the live buff instances, so it reflects what the buff
	-- system believes, not what the mod asked for.
	for _, buff_name in ipairs(_pool_names()) do
		local active = buff_extension:has_buff_using_buff_template(buff_name)

		lines[#lines + 1] = string.format("%s: %s", buff_name, active and "ACTIVE" or "not active")
	end

	-- Effect, buff 1: the multiplier the damage pipeline will actually read.
	-- Base is 1, so 1.15 means the stat buff landed. Other sources stack into
	-- the same number, so read it as "at least ours", not "only ours".
	local player_stat_buffs = buff_extension:stat_buffs()
	local damage_multiplier = player_stat_buffs and player_stat_buffs[stat_buffs.damage]

	lines[#lines + 1] = string.format("damage stat_buff multiplier: %s (1.0 = no bonus)",
		damage_multiplier and string.format("%.3f", damage_multiplier) or "unreadable")

	-- Effect, buff 2: procs only count elite kills, so trash kills prove nothing.
	lines[#lines + 1] = string.format("toughness-on-elite-kill procs: %d",
		proc_counts.cwah_custom_toughness_on_elite_kill or 0)

	-- Effect, buff 3: stacks are the mechanic, so report them rather than the
	-- crit chance -- the chance is clamped to 1 downstream and would stop moving
	-- long before the stacks do.
	local ramp_stacks = buff_extension:current_stacks("cwah_crit_ramp_stack")
	local ramp_max = BuffTemplates.cwah_crit_ramp_stack.max_stacks

	lines[#lines + 1] = string.format("crit ramp: %d/%d stacks (+%.0f%% crit), %d non-crit hits counted",
		ramp_stacks, ramp_max, ramp_stacks * CRIT_RAMP_STEP * 100, proc_counts.cwah_crit_ramp or 0)

	-- Effect, buff 4: same reading, and the hit count is the useful half -- if
	-- stacks sit at 0 while hits climb, the reset is firing when it should not.
	local speed_stacks = buff_extension:current_stacks("cwah_attack_speed_ramp_stack")
	local speed_max = BuffTemplates.cwah_attack_speed_ramp_stack.max_stacks

	lines[#lines + 1] = string.format("attack speed ramp: %d/%d stacks (+%.0f%% attack speed), %d hits counted",
		speed_stacks, speed_max, speed_stacks * ATTACK_SPEED_STEP * 100, proc_counts.cwah_attack_speed_ramp or 0)

	-- Effect, buff 5: a zero here with the buff ACTIVE means the hook never
	-- fired, which points at the detection rather than at the buff.
	lines[#lines + 1] = string.format("status cascades: %d applied / %d triggers seen (pool of %d)",
		proc_counts.cwah_status_cascade or 0, proc_counts.cwah_status_trigger or 0, #STATUS_EFFECTS)

	return _echo_safe(lines)
end

custom_buffs.category = CATEGORY

-- Per mission, so the count answers "did it fire in this one" rather than
-- accumulating across a whole run and looking healthy on stale numbers.
custom_buffs.reset_counters = function ()
	table.clear(proc_counts)
end

custom_buffs.buff_names = function ()
	return _pool_names()
end

return custom_buffs
