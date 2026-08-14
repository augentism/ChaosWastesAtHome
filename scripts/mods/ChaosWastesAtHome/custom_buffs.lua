local mod = get_mod("ChaosWastesAtHome")

local BuffSettings = require("scripts/settings/buff/buff_settings")
local BuffTemplates = require("scripts/settings/buff/buff_templates")
-- Deliberately required AFTER BuffTemplates. Loading BuffTemplates pulls in
-- hordes_legendary_psyker_buff_templates (buff_templates.lua:46), which requires
-- hordes_buffs_utilities and attack_settings -- so by the time we ask for them
-- they are already in package.loaded and these lines are cache hits rather than
-- fresh module executions during boot-time mod loading. Reordering them above
-- the BuffTemplates line would make them the first loader, which is the risky
-- position (see install_hooks for what a throwing require costs).
local AttackSettings = require("scripts/settings/damage/attack_settings")
local HordesBuffsUtilities = require("scripts/settings/buff/hordes_buffs/hordes_buffs_utilities")
-- NOT required here: see install_hooks. minion_buff_extension pulls in
-- buff_extension_base, which reads the `Network` global at file scope, and that
-- global does not exist yet while mods are loading at boot.
local CheckProcFunctions = require("scripts/settings/buff/helper_functions/check_proc_functions")
local HordesBuffsData = require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")
local MissionBuffsAllowedBuffs = require("scripts/managers/mission_buffs/mission_buffs_allowed_buffs")
local MissionBuffsSettings = require("scripts/managers/mission_buffs/mission_buffs_settings")
local Toughness = require("scripts/utilities/toughness/toughness")

local attack_types = AttackSettings.attack_types
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
-- its pool membership -- is derived from that entry by `register`. The worked
-- examples below cover the shapes worth copying, roughly in order of how much
-- machinery they need.
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

-- Two buffs carry enough machinery to deserve their own file. Their catalogue
-- entries still live here, so registration stays in one place and there is still
-- exactly one list of what this mod adds.
--
-- Loaded from here and NOWHERE else. mod:io_dofile re-executes the file on every
-- call rather than caching it, so a second loader anywhere in the mod would get
-- its own copy of these modules -- a second set of counters, and in multishot's
-- case a second registration of hooks that DMF would log as a rehook and drop.
--
-- Loaded after the requires above on purpose: both modules require engine
-- modules that are only safely in package.loaded because requiring BuffTemplates
-- pulled them in.
local arc_chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/arc_chain")
local multishot = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/multishot")

-- Its own category rather than reusing "regular".
--
-- filtering_categories is an enum whose metatable errors on unknown reads, so
-- this has to be registered before anything asks for it -- but the metatable
-- only guards __index, not __newindex, so adding the key is allowed and makes
-- every later read safe.
local CATEGORY = "custom"

MissionBuffsSettings.filtering_categories[CATEGORY] = CATEGORY

-- Scratch buffer for broadphase queries, reused rather than allocated per call.
-- The engine's own buff templates each keep one of these at file scope for the
-- same reason; a proc that runs on every kill in a horde should not be handing
-- the collector a fresh table each time.
local BROADPHASE_RESULTS = {}

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
			--
			-- BOTH fields, and max_stacks is not the one that caps.
			-- `max_stacks` only makes a buff stackable at all --
			-- `can_stack = not not template.max_stacks` (buff_extension_base.lua:436).
			-- The limit is enforced by _check_max_stacks_cap, which returns
			-- "allowed" outright when max_stacks_cap is nil (line 565). Setting
			-- only max_stacks therefore gives an UNBOUNDED ramp that reports
			-- itself as "158/20 stacks".
			max_stacks = math.ceil(1 / CRIT_RAMP_STEP),
			max_stacks_cap = math.ceil(1 / CRIT_RAMP_STEP),
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
			-- See the crit ramp above: max_stacks_cap is the one that actually
			-- caps. Missing here it mattered more than there -- crit chance is
			-- clamped downstream so an unbounded crit ramp is merely wasteful,
			-- but nothing clamps attack speed.
			max_stacks = math.ceil(ATTACK_SPEED_CAP / ATTACK_SPEED_STEP),
			max_stacks_cap = math.ceil(ATTACK_SPEED_CAP / ATTACK_SPEED_STEP),
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

		-- Not just "is the mod on" -- is one of OUR missions running.
		--
		-- Hooks outlive missions. Toggling the mod off unhooks them, but
		-- finishing a run does not, so this kept firing for every buff applied
		-- to every enemy in whatever the player did next -- including a hosted
		-- multiplayer mission, where it has no business running at all. Nothing
		-- would have cascaded (nobody has the buff), but doing the work was
		-- wrong before it was also unsafe, and the guard below is only
		-- reachable because this one was missing.
		if not mod.manager or not mod:is_enabled() then
			return
		end

		-- Without an owner there is nobody to credit, and no way to tell our
		-- player's status effects from an enemy's or a hazard's.
		if not owner_unit or not HEALTH_ALIVE[owner_unit] then
			return
		end

		-- The owner must be OUR player, not merely something with a buff
		-- extension. Two reasons, and the second one is a crash:
		--
		-- 1. This mod is solo-only. Another player's status effects are not
		--    ours to cascade from even if we could see them.
		-- 2. In a hosted mission the owner is usually a remote player's HUSK,
		--    and PlayerHuskBuffExtension is a standalone class -- NOT a
		--    BuffExtensionBase subclass (player_husk_buff_extension.lua:4). It
		--    implements has_keyword, buffs and current_stacks but not
		--    has_buff_using_buff_template, so calling that on one is an
		--    "attempt to call method (a nil value)" error, once per status
		--    effect applied anywhere in the mission.
		--
		-- Identity is the right test rather than duck-typing the method: it
		-- states the actual requirement, and it is one comparison instead of a
		-- table lookup on a path that runs for every buff on every enemy.
		local local_player = Managers.player and Managers.player:local_player_safe(1)

		if not local_player or owner_unit ~= local_player.player_unit then
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
-- Example 6: borrowing a shipped effect wholesale
-- ---------------------------------------------------------------------------
--
-- A flat chance on any hit to Brain Burst the target. Notable for how little
-- there is to it: HordesBuffsUtilities.trigger_brain_burst_on_target
-- (hordes_buffs_utilities.lua:289) already resolves the target's head hit zone
-- and actor, runs Attack.execute with the smite profile and plays the impact
-- effect. Worth grepping the hordes directory before writing an effect --
-- several of them are exported like this.
--
-- Also the example of letting proc_events do the dice. The number in
-- proc_events is a chance, rolled by ProcBuff before check_proc_func is reached
-- (proc_buff.lua:330), so a percentage buff needs no math.random of its own.

local FLAYER_CHANCE = 0.1
local FLAYER_BUFF = "cwah_flayer"

-- Shared by the two ways this buff can fire, so they cannot drift apart.
local function _flayer_burst(player_unit, target_unit)
	if not target_unit or not HEALTH_ALIVE[target_unit] then
		return
	end

	HordesBuffsUtilities.trigger_brain_burst_on_target(target_unit, player_unit)

	proc_counts.cwah_flayer = (proc_counts.cwah_flayer or 0) + 1
end

_add({
	id = "cwah_flayer",
	pool = true,
	title = "Flayer",
	description = "Every hit has a " .. math.floor(FLAYER_CHANCE * 100)
		.. "%% chance to burst the target's skull.",
	icon = "hordes_buff_explode_enemies_on_critical_kill",
	template = function ()
		return {
			class_name = "server_only_proc_buff",
			max_stacks = 1,
			max_stacks_cap = 1,
			predicted = false,
			buff_category = buff_categories.hordes_buff,
			proc_events = {
				[proc_events.on_hit] = FLAYER_CHANCE,
			},
			-- The one remaining guard, and it became MORE important when this
			-- stopped being crit-gated rather than less. It is load-bearing
			-- twice over:
			--
			-- 1. Brain burst's own Attack.execute uses attack_types.buff, so
			--    without this a burst would roll to cause another burst on the
			--    same target, forever. The crit requirement used to make that
			--    rare; a flat chance on every hit would make it routine. The
			--    shipped hordes_buff_psyker_brain_burst_hits_nearby_enemies
			--    carries the same clause for the same reason.
			-- 2. It also rejects damage-over-time ticks -- burning, bleed, and
			--    the arc chain's own electrocution, which ticks every 0.3-0.8s
			--    per shocked enemy through the same attack type. Those are not
			--    hits in any sense the player would recognise, and without this
			--    a fight full of burning enemies would burst skulls on its own.
			--
			-- Arc damage is rejected here too, and NOT because it should not
			-- burst -- it should. It is handled on arc_chain's direct callback
			-- below instead, because the on_hit announcement it would otherwise
			-- arrive on is the first thing to go missing in a busy fight. Both
			-- paths firing would mean two rolls per arc.
			check_proc_func = function (params, template_data, template_context, t)
				return params.attack_type ~= attack_types.buff
					and params.damage_profile ~= arc_chain.DAMAGE_PROFILE
			end,
			proc_func = function (params, template_data, template_context)
				_flayer_burst(template_context.unit, params.attacked_unit)
			end,
		}
	end,
})

-- ---------------------------------------------------------------------------
-- Example 7: reading state off another unit
-- ---------------------------------------------------------------------------
--
-- A dying enemy's status effects spread to its neighbours. Structurally this is
-- the shipped hordes_buff_psyker_brain_burst_spreads_fire_on_hit
-- (hordes_legendary_psyker_buff_templates.lua:272) generalised from fire to
-- every status effect, which costs nothing because the Contagion buff above
-- already resolved BuffTemplates into `status_template_set`.
--
-- Two things here are worth copying rather than the buff itself: caching the
-- broadphase and the enemy side names in start_func (querying the extension
-- manager per proc is wasteful), and taking the origin position from
-- params.attacked_unit_position rather than POSITION_LOOKUP -- the unit is
-- dying, and the boxed position in the proc params is the reliable read.

local PROLIFERATION_RANGE = 5
local PROLIFERATION_MAX_TARGETS = 5

-- Stacks are copied, not multiplied -- but capped, because
-- add_internally_controlled_buff_with_stacks LOOPS, applying the buff once per
-- stack (buff_extension_base.lua:408). A ten-stack soulblaze spread to five
-- enemies is fifty applications, each of which also runs the Contagion hook.
-- Five is enough for the effect to read as "it spread" without that multiplying
-- out.
local PROLIFERATION_MAX_STACKS = 5

-- The seatbelt. Not a tuning knob: a proliferated enemy that dies of the
-- proliferated soulblaze credits the kill to the player, so on_kill fires again
-- and the spread can sustain itself through a horde. The recipient set below is
-- the real fix; this is what stops a hole in it from becoming a frozen game
-- rather than a buff that briefly feels weak. Do not raise it to make the buff
-- feel better.
local PROLIFERATIONS_PER_SECOND = 8

-- Units we have already spread ONTO. A death from this set does not spread
-- again, which is what breaks the self-sustaining chain.
--
-- Weak keys so despawned enemies drop out on their own -- otherwise this grows
-- by one entry per affected enemy for the whole mission and nothing ever clears
-- it. Parked on `mod` for the same reason as proc_counts: a live buff keeps the
-- closure it was created with, so a reload must not hand the old closure a
-- different table from the one the new one reads.
local proliferated = mod._cwah_proliferated

if not proliferated then
	proliferated = setmetatable({}, { __mode = "k" })
	mod._cwah_proliferated = proliferated
end

-- Scratch arrays for what the corpse was carrying, kept parallel and reused.
-- This proc runs on every kill, which in a horde is often enough that handing
-- the collector two fresh tables plus one per status effect each time is worth
-- avoiding.
local CARRIED_NAMES = {}
local CARRIED_STACKS = {}

_add({
	id = "cwah_proliferation",
	pool = true,
	title = "Proliferation",
	description = "When an enemy you have afflicted dies, every status effect on it spreads to nearby enemies.",
	icon = "hordes_buff_burning_damage_per_burning_enemy",
	template = function ()
		return {
			class_name = "server_only_proc_buff",
			max_stacks = 1,
			max_stacks_cap = 1,
			predicted = false,
			buff_category = buff_categories.hordes_buff,
			proc_events = {
				[proc_events.on_kill] = 1,
			},
			start_func = function (template_data, template_context)
				local extension_manager = Managers.state and Managers.state.extension

				if not extension_manager then
					return
				end

				local broadphase_system = extension_manager:system("broadphase_system")

				template_data.broadphase = broadphase_system and broadphase_system.broadphase

				local side_system = extension_manager:system("side_system")
				local side = side_system and side_system.side_by_unit[template_context.unit]

				template_data.enemy_side_names = side and side:relation_side_names("enemy")

				template_data.window_start = 0
				template_data.window_count = 0
			end,
			proc_func = function (params, template_data, template_context, t)
				local broadphase = template_data.broadphase
				local enemy_side_names = template_data.enemy_side_names
				local victim = params.attacked_unit

				if not broadphase or not enemy_side_names or not victim then
					return
				end

				-- Do not spread from something we spread onto.
				if proliferated[victim] then
					return
				end

				if t - template_data.window_start >= 1 then
					template_data.window_start = t
					template_data.window_count = 0
				end

				if template_data.window_count >= PROLIFERATIONS_PER_SECOND then
					return
				end

				local victim_extension = ScriptUnit.has_extension(victim, "buff_system")

				if not victim_extension or not status_template_set then
					return
				end

				-- What the corpse was carrying. current_stacks is a single hash
				-- lookup per name, so walking the whole status set is cheaper
				-- than it looks and avoids depending on the private buff list.
				local carried_count = 0

				for template_name in pairs(status_template_set) do
					local stacks = victim_extension:current_stacks(template_name)

					if stacks > 0 then
						carried_count = carried_count + 1
						CARRIED_NAMES[carried_count] = template_name
						CARRIED_STACKS[carried_count] = math.min(stacks, PROLIFERATION_MAX_STACKS)
					end
				end

				proc_counts.cwah_proliferation_deaths = (proc_counts.cwah_proliferation_deaths or 0) + 1

				if carried_count == 0 then
					return
				end

				local position = params.attacked_unit_position and params.attacked_unit_position:unbox()

				if not position then
					return
				end

				local player_unit = template_context.unit

				table.clear(BROADPHASE_RESULTS)

				local num_hits = broadphase.query(broadphase, position, PROLIFERATION_RANGE,
					BROADPHASE_RESULTS, enemy_side_names)
				local spread_to = 0

				for i = 1, num_hits do
					local target = BROADPHASE_RESULTS[i]

					if target ~= victim and HEALTH_ALIVE[target] then
						local target_extension = ScriptUnit.has_extension(target, "buff_system")

						if target_extension then
							for j = 1, carried_count do
								pcall(target_extension.add_internally_controlled_buff_with_stacks,
									target_extension, CARRIED_NAMES[j], CARRIED_STACKS[j], t,
									"owner_unit", player_unit)
							end

							proliferated[target] = true
							spread_to = spread_to + 1

							if spread_to >= PROLIFERATION_MAX_TARGETS then
								break
							end
						end
					end
				end

				if spread_to > 0 then
					template_data.window_count = template_data.window_count + 1

					proc_counts.cwah_proliferation = (proc_counts.cwah_proliferation or 0) + 1

					mod:debug_log("proliferation: %d status effect(s) spread to %d enemies",
						carried_count, spread_to)
				end
			end,
		}
	end,
})

-- ---------------------------------------------------------------------------
-- Examples 8 and 9: behaviour that lives in its own file
-- ---------------------------------------------------------------------------
--
-- Both of these carry enough logic that inlining them here would bury the
-- catalogue. The entries stay, so there is still one list of everything this mod
-- adds and one registration path; only the bodies moved.

_add({
	id = arc_chain.BUFF_NAME,
	pool = true,
	title = "Chain Lightning",
	description = arc_chain.DESCRIPTION,
	icon = "hordes_buff_shock_closest_enemy_on_interval",
	template = arc_chain.template,
})

-- The electrocution the arcs leave behind. No `pool`, so it is registered but
-- never offered -- same shape as the ramp stat carriers above, and registered
-- here for the same reason: a helper template still needs a name and a network
-- id, and both of those crash on apply rather than on offer.
_add({
	id = arc_chain.SHOCK_BUFF_NAME,
	template = arc_chain.shock_template,
})

-- Flayer, off arcs.
--
-- Deliberately wired here rather than inside arc_chain.lua: the arc buff has no
-- business knowing what Flayer is, and Flayer's odds and effect stay in one
-- place. arc_chain just publishes "an arc landed".
--
-- Assigned at file scope, so it is live whether or not either buff is held --
-- which is why the first thing it does is check the player actually has Flayer.
-- Cheap: at most MAX_JUMPS calls per chain, and chains are budgeted.
arc_chain.on_arc_hit = function (player_unit, target_unit, t)
	if math.random() >= FLAYER_CHANCE then
		return
	end

	local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")

	if not buff_extension or not buff_extension:has_buff_using_buff_template(FLAYER_BUFF) then
		return
	end

	_flayer_burst(player_unit, target_unit)

	proc_counts.cwah_flayer_from_arc = (proc_counts.cwah_flayer_from_arc or 0) + 1
end

_add({
	id = multishot.BUFF_NAME,
	pool = true,
	title = "Multishot",
	description = multishot.DESCRIPTION,
	icon = "hordes_buff_ranged_attacks_hit_mass_penetration_increased",
	template = multishot.template,
})

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

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------
--
-- Answers "is this buff actually doing anything", which the HUD cannot.
-- Attachment and effect are separate questions and both get reported: a buff can
-- be listed on the player and still do nothing if its stat key is wrong or its
-- check_proc_func never passes.
--
-- Written to the log passively behind the debug_logging setting, rather than
-- only when someone runs /cw_verify. Two reasons, and the second is the real
-- one:
--
-- 1. A line per buff stopped scaling once there were nine of them.
-- 2. The interesting failures are shapes over time, not single samples. A proc
--    count that climbs while the player stands still, or a guard that stops
--    rejecting once a fight gets dense, is obvious in a series of snapshots and
--    invisible in one -- and the one snapshot you get on demand is never taken
--    at the moment things went wrong. A player reporting a problem sends the log
--    anyway, so this costs them nothing to produce.

-- The readings that cannot be counters because they are live state rather than a
-- tally. Both ramps report stacks rather than the stat they produce: crit chance
-- is clamped to 1 downstream and would stop moving long before the stacks do.
local STACK_READINGS = {
	{ buff = "cwah_crit_ramp_stack", label = "crit ramp", step = CRIT_RAMP_STEP, of = "crit" },
	{ buff = "cwah_attack_speed_ramp_stack", label = "attack speed ramp", step = ATTACK_SPEED_STEP, of = "attack speed" },
}

-- Counters are reported generically -- whatever the proc funcs happen to have
-- bumped, sorted, zeroes omitted. Deliberately NOT a hand-maintained table of
-- pretty labels: that is exactly the thing that goes stale the next time a buff
-- is added, and the raw keys are already readable. What a counter means belongs
-- in a comment next to the code that bumps it.
local function _report_lines()
	local player = Managers.player and Managers.player:local_player_safe(1)
	local player_unit = player and player.player_unit

	if not player_unit or not Unit.alive(player_unit) then
		return { "no local player unit - are you in a mission?" }
	end

	local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")

	if not buff_extension then
		return { "no buff extension on the player unit" }
	end

	local lines = {}

	-- Attached, on one line. Walks the live buff instances, so it reflects what
	-- the buff system believes rather than what the mod asked for.
	local held = {}

	for _, buff_name in ipairs(_pool_names()) do
		if buff_extension:has_buff_using_buff_template(buff_name) then
			held[#held + 1] = buff_name
		end
	end

	lines[#lines + 1] = "held: " .. (#held > 0 and table.concat(held, ", ") or "none")

	-- The multiplier the damage pipeline will actually read. Base is 1, so 1.15
	-- means the stat buff landed. Other sources stack into the same number, so
	-- read it as "at least ours", not "only ours".
	local player_stat_buffs = buff_extension:stat_buffs()
	local damage_multiplier = player_stat_buffs and player_stat_buffs[stat_buffs.damage]

	lines[#lines + 1] = string.format("damage stat_buff multiplier: %s (1.0 = no bonus)",
		damage_multiplier and string.format("%.3f", damage_multiplier) or "unreadable")

	for _, reading in ipairs(STACK_READINGS) do
		local template = BuffTemplates[reading.buff]
		local stacks = buff_extension:current_stacks(reading.buff)

		lines[#lines + 1] = string.format("%s: %d/%d stacks (+%.0f%% %s)",
			reading.label, stacks, template and template.max_stacks or 0,
			stacks * reading.step * 100, reading.of)
	end

	local keys = {}

	for key, value in pairs(proc_counts) do
		if value and value ~= 0 then
			keys[#keys + 1] = key
		end
	end

	table.sort(keys)

	if #keys == 0 then
		lines[#lines + 1] = "no custom buff has fired yet"
	else
		for _, key in ipairs(keys) do
			lines[#lines + 1] = string.format("  %s: %d", key, proc_counts[key])
		end
	end

	return lines
end

-- Report lines are echoed to chat, and mod:echo runs its message through
-- string.format -- so any literal % we produce (the ramp percentages) has to be
-- doubled or the echo crashes instead of printing.
--
-- Only the chat path needs this. mod:debug_log escapes whatever it is handed on
-- its way out, so the passive path below must pass the lines RAW -- escaping
-- them twice would print a literal %%.
local function _echo_safe(lines)
	for i = 1, #lines do
		lines[i] = (lines[i]:gsub("%%", "%%%%"))
	end

	return lines
end

custom_buffs.report = function ()
	return _echo_safe(_report_lines())
end

local REPORT_INTERVAL = 10
local report_accum = 0
local last_snapshot = nil

-- Called every frame; does almost nothing on almost all of them.
--
-- Only logs when the snapshot has actually changed, so a quiet stretch does not
-- fill the log with the same block over and over -- which matters because the
-- log is the artefact a player sends back, and a wall of identical lines makes
-- the moment something changed harder to find rather than easier.
custom_buffs.update = function (dt)
	if not mod.manager then
		return
	end

	report_accum = report_accum + dt

	if report_accum < REPORT_INTERVAL then
		return
	end

	report_accum = 0

	-- Checked after the interval, not before: building a report walks the buff
	-- extension, and with logging off there is nobody to read the result.
	if not mod:get("debug_logging") then
		return
	end

	local lines = _report_lines()
	local snapshot = table.concat(lines, "\n")

	if snapshot == last_snapshot then
		return
	end

	last_snapshot = snapshot

	mod:debug_log("--- custom buffs ---")

	for i = 1, #lines do
		mod:debug_log(lines[i])
	end
end

custom_buffs.category = CATEGORY

-- Per mission, so the count answers "did it fire in this one" rather than
-- accumulating across a whole run and looking healthy on stale numbers.
custom_buffs.reset_counters = function ()
	table.clear(proc_counts)

	-- Weak keys mean this drains on its own as enemies despawn, but a mission
	-- boundary is a natural point to drop the lot rather than wait for the
	-- collector.
	table.clear(proliferated)

	-- So the first report of a new mission is always written, rather than being
	-- suppressed for matching the last one of the previous mission.
	last_snapshot = nil
	report_accum = 0
end

custom_buffs.buff_names = function ()
	return _pool_names()
end

return custom_buffs
