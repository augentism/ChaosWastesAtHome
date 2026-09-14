local mod = get_mod("CwahBuffs")
local cwah = get_mod("ChaosWastesAtHome")

-- The blessings that ship with Chaos Wastes at Home, as an addon rather than as
-- part of it.
--
-- Nothing here registers a buff itself. Every entry goes through
-- cwah.register_buffs, which is the same public call any third-party card pack
-- makes -- this pack exists partly to keep that call honest. If these nine
-- cannot be expressed through the API, nobody else's can either.
--
-- The ids are deliberately still cwah_*. They are persistence keys: a run
-- carries them, the Rollable Buffs menu stores them, and the peer handshake
-- compares them. Renaming them to match this mod would silently strand every
-- saved run and every toggle a player has set.

-- Deliberately required AFTER BuffTemplates. Loading BuffTemplates pulls in
-- hordes_legendary_psyker_buff_templates (buff_templates.lua:46), which requires
-- hordes_buffs_utilities and attack_settings -- so by the time we ask for them
-- they are already in package.loaded and these lines are cache hits rather than
-- fresh module executions during boot-time mod loading. Reordering them above
-- the BuffTemplates line would make them the first loader, which is the risky
-- position (see install_hooks for what a throwing require costs).
local BuffSettings = require("scripts/settings/buff/buff_settings")
local BuffTemplates = require("scripts/settings/buff/buff_templates")
local AttackSettings = require("scripts/settings/damage/attack_settings")
local flayer_burst = mod:io_dofile("CwahBuffs/scripts/mods/CwahBuffs/flayer_burst")
-- NOT required here: see install_hooks. minion_buff_extension pulls in
-- buff_extension_base, which reads the `Network` global at file scope, and that
-- global does not exist yet while mods are loading at boot.
local CheckProcFunctions = require("scripts/settings/buff/helper_functions/check_proc_functions")
local Toughness = require("scripts/utilities/toughness/toughness")

local attack_types = AttackSettings.attack_types
local buff_categories = BuffSettings.buff_categories
local proc_events = BuffSettings.proc_events
local stat_buffs = BuffSettings.stat_buffs

local pack = {}

-- The counter table Chaos Wastes at Home reports from, shared rather than our
-- own, so these procs appear in /cw_verify next to everything else.
--
-- Fetched through the API rather than reached for on the mod table: it is the
-- same object either way, but this is the supported name for it.
local proc_counts = cwah.buff_proc_counters()

-- Loaded from here and NOWHERE else. mod:io_dofile re-executes the file on every
-- call rather than caching it, so a second loader anywhere in this mod would get
-- its own copy -- a second set of counters, and in multishot's case a second
-- registration of hooks that DMF would log as a rehook and drop.
local arc_chain = mod:io_dofile("CwahBuffs/scripts/mods/CwahBuffs/arc_chain")
local multishot = mod:io_dofile("CwahBuffs/scripts/mods/CwahBuffs/multishot")

-- Scratch buffer for broadphase queries, reused rather than allocated per call.
-- The engine's own buff templates each keep one of these at file scope for the
-- same reason; a proc that runs on every kill in a horde should not be handing
-- the collector a fresh table each time.
local BROADPHASE_RESULTS = {}

-- Every buff this pack defines, in one list. The entry fields are documented in
-- ChaosWastesAtHome/docs/adding-custom-buffs.md.
local CATALOGUE = {}

local function _add(entry)
	CATALOGUE[#CATALOGUE + 1] = entry

	return entry
end

-- Values substituted into a description's %s slots at registration time.
--
-- Doubled per-cent signs are not a typo. The string we register is run through
-- string.format once more on its way out of DMF's global lookup, and a lone %
-- there is an invalid specifier -- which fails the whole lookup and puts the raw
-- key on the card instead of the text.
local function _pct(fraction)
	return string.format("%d%%%%", math.floor(fraction * 100 + 0.5))
end

-- ---------------------------------------------------------------------------
-- Example 1: a passive stat buff
-- ---------------------------------------------------------------------------

-- The `stat_buffs` shorthand: register builds a plain passive template from it.
-- `filter_category` is written for you, which matters -- omitting it is a
-- nil-index crash at mission start, a long way from the buff that caused it.
local DAMAGE_MULTIPLIER = 1.15

_add({
	id = "cwah_custom_damage",
	pool = true,
	-- Off unless the player asks for it. A flat damage multiplier was the first
	-- thing built here to prove the registration path worked, and it stayed
	-- because it was already written -- but "everything hits harder" is exactly
	-- the kind of buff a run built around card picks does not want. Kept rather
	-- than deleted because it is still the clearest worked example of the plain
	-- stat-buff shape, and someone may want it.
	default_off = true,
	icon = "hordes_buff_damage_increase",
	values = { _pct(DAMAGE_MULTIPLIER - 1) },
	stat_buffs = {
		[stat_buffs.damage] = DAMAGE_MULTIPLIER,
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
	icon = "hordes_buff_toughness_on_melee_kills",
	values = { _pct(TOUGHNESS_PER_ELITE_KILL / 100) },
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
	icon = "hordes_buff_critical_chance_on_dodge",
	values = { _pct(CRIT_RAMP_STEP) },
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
	icon = "hordes_buff_improved_dodge_speed_and_distance",
	values = { _pct(ATTACK_SPEED_STEP), _pct(ATTACK_SPEED_CAP), ATTACK_SPEED_IDLE_RESET },
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
pack.install_hooks = function ()
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
		if not cwah.has_authority() or not cwah:is_enabled() or not mod:is_enabled() then
			return
		end

		-- Without an owner there is nobody to credit, and no way to tell our
		-- player's status effects from an enemy's or a hazard's.
		if not owner_unit or not HEALTH_ALIVE[owner_unit] then
			return
		end

		-- The owner must be a player -- any player in the party, not just this
		-- one.
		--
		-- It used to require the LOCAL player specifically, for two reasons that
		-- have both since expired. The first was that the mod was solo-only,
		-- which it is not. The second was the husk hazard: PlayerHuskBuffExtension
		-- is a standalone class, not a BuffExtensionBase subclass
		-- (player_husk_buff_extension.lua:4), so it has no
		-- has_buff_using_buff_template and calling it is an "attempt to call
		-- method (a nil value)" error.
		--
		-- That hazard cannot arise here. The husk extension is only ever added
		-- when `not is_server` (player_character_unit_template.lua:358), and this
		-- whole function is behind has_authority() -- which is game_session
		-- is_server. On the server every player unit, remote ones included, has
		-- the full PlayerUnitBuffExtension.
		--
		-- The cost of the old test was silent: a guest who picked Contagion had
		-- a buff that did nothing at all, with nothing logged to say so.
		local owner_player = Managers.player and Managers.player:player_by_unit(owner_unit)

		if not owner_player then
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
-- there is to it, with a private damage profile so vanilla Brain Burst
-- blessings accept the hit while Flayer can reject its own direct damage.
-- ProcBuff rolls the configured chance before invoking the filter.

local FLAYER_CHANCE = 0.1
local FLAYER_BUFF = "cwah_flayer"

-- Shared by the two ways this buff can fire, so they cannot drift apart.
local function _flayer_burst(player_unit, target_unit)
	if not target_unit or not HEALTH_ALIVE[target_unit] then
		return
	end

	flayer_burst.trigger(target_unit, player_unit)

	proc_counts.cwah_flayer = (proc_counts.cwah_flayer or 0) + 1
end

_add({
	id = "cwah_flayer",
	pool = true,
	icon = "hordes_buff_explode_enemies_on_critical_kill",
	values = { _pct(FLAYER_CHANCE) },
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
			-- Block only direct self-procs, buff/DoT damage, and the duplicate
			-- on_hit roll for arcs (their explicit callback rolls once instead).
			-- Flayer -> Chain Lightning -> Flayer is intentional; no global
			-- re-entry flag blocks the arc callback while a burst is executing.
			check_proc_func = function (params, template_data, template_context, t)
				return params.attack_type ~= attack_types.buff
					and not flayer_burst.is_own_damage(params.damage_profile)
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
	icon = "hordes_buff_shock_closest_enemy_on_interval",
	values = { _pct(arc_chain.CHANCE), arc_chain.MAX_JUMPS, arc_chain.SHOCK_DURATION },
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
	icon = "hordes_buff_ranged_attacks_hit_mass_penetration_increased",
	values = { multishot.SHOTS },
	template = multishot.template,
})

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

local LOCALIZATION_FILE = "CwahBuffs/scripts/mods/CwahBuffs/CwahBuffs_localization"

local function _title_key(id)
	return "loc_" .. id .. "_title"
end

local function _description_key(id)
	return "loc_" .. id .. "_description"
end

-- Card text lives in this mod's own localization file like every other string it
-- owns; this only carries the per-language tables onto the entries. The
-- substitution and the registration into DMF's global database both happen on
-- the other side of register_buffs.
local function _attach_card_strings()
	local ok, strings = pcall(mod.io_dofile, mod, LOCALIZATION_FILE)

	if not ok or type(strings) ~= "table" then
		mod:error("could not read the localization file for card text: %s", tostring(strings))

		return
	end

	for _, entry in ipairs(CATALOGUE) do
		if entry.pool then
			local title_key = _title_key(entry.id)
			local description_key = _description_key(entry.id)

			-- Loud, because the quiet version is a card in the wild reading
			-- "<loc_cwah_something_title>".
			if type(strings[title_key]) ~= "table" then
				mod:error("localization key '%s' is missing - its card will show the key instead", title_key)
			end

			if type(strings[description_key]) ~= "table" then
				mod:error("localization key '%s' is missing - its card will show the key instead", description_key)
			end

			entry.title = strings[title_key]
			entry.description = strings[description_key]
		end
	end
end

local registered = false

pack.register = function ()
	if registered then
		return
	end

	registered = true

	_attach_card_strings()

	-- prefix cwah_, not cwahbuffs_: see the note at the top of this file about
	-- ids being persistence keys. category "custom" for the same reason -- it is
	-- what the player's existing Rollable Buffs toggles are stored against.
	cwah.register_buffs(mod, CATALOGUE, {
		prefix = "cwah_",
		category = "custom",
		category_label = "Custom",
	})

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

	-- Live readings for /cw_verify. Both ramps report stacks rather than the stat
	-- they produce: crit chance is clamped to 1 downstream and would stop moving
	-- long before the stacks do.
	cwah.register_buff_reading({
		buff = "cwah_crit_ramp_stack", label = "crit ramp", step = CRIT_RAMP_STEP, of = "crit",
	})
	cwah.register_buff_reading({
		buff = "cwah_attack_speed_ramp_stack", label = "attack speed ramp", step = ATTACK_SPEED_STEP, of = "attack speed",
	})

	pack.install_hooks()
end

-- Per mission, because the load-time attempt above declines at boot: the engine
-- module the cascade hooks cannot be required until the game is further along.
-- Host only, because the cascade APPLIES buffs to enemies, which is a server
-- act -- on a client it would be writing to units it does not own.
cwah.subscribe(mod, "mission_start", function ()
	if cwah.is_host() then
		pack.install_hooks()
	end
end)

-- Weak keys mean this drains on its own as enemies despawn, but a mission
-- boundary is a natural point to drop the lot rather than wait for the
-- collector.
cwah.subscribe(mod, "mission_end", function ()
	if proliferated then
		table.clear(proliferated)
	end
end)

return pack
