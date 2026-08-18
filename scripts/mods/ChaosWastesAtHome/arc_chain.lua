local mod = get_mod("ChaosWastesAtHome")

-- Chain Lightning: a chance on any hit to arc from the enemy you hit to nearby
-- enemies, damaging and electrifying each one.
--
-- The engine has a real chain-lightning implementation
-- (scripts/utilities/action/chain_lightning.lua plus chain_lightning_target.lua)
-- and this is deliberately NOT it. That one is a node tree with jump validation,
-- four-offset line-of-sight raycasts and per-node particle linking, driven by an
-- FX effect template -- all of which exists to draw the visible arc between
-- targets. We are not drawing one, so all of that machinery would buy nothing.
-- What is left is a broadphase walk and Attack.execute, which is exactly the
-- shape the shipped Mortis buffs use.
--
-- Visual feedback still happens, for free: hordes_ailment_shock carries a
-- minion_effects block that spawns a particle on the target's spine
-- (hordes_buff_templates.lua:616), so struck enemies visibly spark even though
-- nothing draws a beam between them.

local Attack = require("scripts/utilities/attack/attack")
local AttackSettings = require("scripts/settings/damage/attack_settings")
local BuffSettings = require("scripts/settings/buff/buff_settings")
local BuffTemplates = require("scripts/settings/buff/buff_templates")
local DamageProfileTemplates = require("scripts/settings/damage/damage_profile_templates")
local DamageSettings = require("scripts/settings/damage/damage_settings")

local attack_types = AttackSettings.attack_types
local buff_categories = BuffSettings.buff_categories
local damage_types = DamageSettings.damage_types
local proc_events = BuffSettings.proc_events

local arc_chain = {}

arc_chain.BUFF_NAME = "cwah_arc_chain"

-- Tuning.
local ARC_CHANCE = 0.25
local MAX_JUMPS = 3
local JUMP_RADIUS = 8
local ARC_POWER_LEVEL = 500

-- The status effect each arc target picks up: our own copy of the shipped
-- hordes_ailment_shock, with a shorter duration.
--
-- Started out applying the shipped buff directly, which was wrong for one
-- specific reason. The origin guard below asks "is this enemy already
-- electrified", and asking the *general* question meant every other source of
-- electrocution answered it too -- most damagingly the Contagion buff, which
-- rolls shock_grenade_interval out of its own pool. That buff lasts EIGHT
-- seconds and refreshes on reapply (weapon_buff_templates.lua:416), so a player
-- running both buffs had most of the horde permanently ineligible as a chain
-- origin and almost no arcs fired.
--
-- A private template makes the guard ask "did WE electrify this enemy", which is
-- the question it always meant. Arc rifles, shock mines, Contagion and the
-- electric family no longer suppress the buff.
--
-- Cloned rather than written from scratch so it keeps everything that made the
-- shipped one the right choice: buff_keywords.electrocuted (so it still counts
-- as electrocution for damage_vs_electrocuted, still feeds Contagion, still
-- reads as a status effect to Proliferation) and the minion_effects block that
-- sparks the target, which is the whole of our visuals. table.clone is a deep
-- copy, so the nested keywords/interval/minion_effects tables are ours to hold
-- and the interval_func comes across by reference and keeps working.
local SHOCK_BUFF = "cwah_arc_shock"

-- How long the same enemy stays ineligible as a chain origin, which is all this
-- duration controls now that it is private to us. Short: the point is to stop
-- one enemy being chained off over and over, not to take it out of play.
local SHOCK_DURATION = 1

arc_chain.SHOCK_BUFF_NAME = SHOCK_BUFF

-- Registered through the catalogue in custom_buffs.lua as a non-pool helper, so
-- it picks up template.name and its network id like everything else. Both of
-- those crash on apply if missed, and neither is visible when the card is drawn.
arc_chain.shock_template = function ()
	local source = BuffTemplates.hordes_ailment_shock

	-- A patch renaming the shipped template would otherwise be a nil clone at
	-- mod load, which takes the whole registration down. Losing the sparks and
	-- the interval damage is survivable; the cooldown, which is the part the
	-- guard depends on, is carried by the template existing at all.
	if not source then
		mod:error("hordes_ailment_shock is missing - arc chain targets will not be electrified")

		source = {
			class_name = "buff",
			max_stacks = 1,
			max_stacks_cap = 1,
			predicted = false,
		}
	else
		source = table.clone(source)
	end

	source.name = nil
	source.duration = SHOCK_DURATION

	return source
end

-- The damage every arc deals.
--
-- Referenced, never cloned. NetworkLookup.damage_profile_templates is built once
-- at boot from DamageProfileTemplates (network_lookup.lua:154) -- the identical
-- trap that made mod-added buff templates crash the moment they were applied. A
-- cloned profile would not be in that lookup.
--
-- Using the shipped table also gives us the recursion guard for free: comparing
-- params.damage_profile against this exact table is a single pointer comparison
-- that identifies our own arcs. The only false positive is a Cryptic's actual
-- arc grenade chain jump, which will not start a chain of ours. Fine.
local ARC_DAMAGE_PROFILE = DamageProfileTemplates.arc_grenade_chain_jump_damage

arc_chain.DAMAGE_PROFILE = ARC_DAMAGE_PROFILE

-- Called once per arc that lands, as (player_unit, target_unit, t). Optional --
-- nothing here sets it; custom_buffs.lua does, to hang Flayer off arcs.
--
-- This exists because the obvious route does not survive a real fight. Arcs deal
-- damage as the player with attack_types.ranged, which announces on_hit, which
-- is how they are supposed to proc the player's other on-hit effects -- and that
-- works right up until the buff extension's proc queue fills. It holds
-- MAX_PROC_EVENTS = 300 entries per frame (buff_settings.lua:67); past that,
-- request_proc_event_param_table returns nil and Attack.execute silently skips
-- the announcement altogether (attack.lua:570). A status-effect-heavy loadout
-- saturates that constantly -- a measured 38,952 dropped procs in one mission,
-- peaking around 305 a second -- and arcs are then invisible to everything.
--
-- So anything that must reliably happen on an arc gets called directly, here,
-- rather than going back through a queue that is the first thing to break under
-- exactly the conditions the buff is for.
arc_chain.on_arc_hit = nil

-- The seatbelt, and the reason it is separate from the guards below.
--
-- The guards are game rules: they can be tuned, argued about, and can turn out
-- to be wrong. This is the thing that guarantees a hole in one of them shows up
-- as "the buff felt weak for a second" instead of a frame time collapse with
-- nothing in the log to explain it. Never raise it to make the buff feel better
-- -- change ARC_CHANCE or MAX_JUMPS for that.
local ARCS_PER_SECOND = 10

local BROADPHASE_RESULTS = {}

-- Parked on `mod` for the same reason as the other counters: a live buff keeps
-- the proc_func closure it was created with, so after a mod reload the old
-- closure and the new one must still be writing to one table or the report reads
-- zero on a buff that is working.
local proc_counts = mod._custom_buff_procs or {}

mod._custom_buff_procs = proc_counts

-- Why a hit did not arc, counted per reason.
--
-- Worth the four lines: "arcs fired" alone cannot distinguish a buff that is
-- broken from one that is working and simply never presented with an eligible
-- hit, and those want completely different fixes. The keys are constants rather
-- than built by concatenation because this runs on every hit that passes the
-- chance roll, which in a fight with burning enemies is a lot of them.
--
-- Note these only ever see a quarter of your hits: ProcBuff rolls the chance
-- BEFORE calling check_proc_func (proc_buff.lua:330), so the 75% that lose the
-- roll are never offered to us at all. Read the numbers against each other, not
-- against your actual hit count.
local BLOCKED_OWN_DAMAGE = "cwah_arc_chain_blocked_own_damage"
local BLOCKED_BUFF_DAMAGE = "cwah_arc_chain_blocked_buff_damage"
local BLOCKED_ELECTRIFIED = "cwah_arc_chain_blocked_already_electrified"
local BLOCKED_BUDGET = "cwah_arc_chain_blocked_budget"
local BLOCKED_NO_TARGET = "cwah_arc_chain_blocked_no_origin"

local function _blocked(key)
	proc_counts[key] = (proc_counts[key] or 0) + 1

	return false
end

-- Exported for the card text, which is written in the localization file and
-- formatted with these at registration. Tuning stays here; wording stays there.
arc_chain.CHANCE = ARC_CHANCE
arc_chain.MAX_JUMPS = MAX_JUMPS
arc_chain.SHOCK_DURATION = SHOCK_DURATION

-- The nearest living enemy to `from_position` that this chain has not already
-- hit.
--
-- Electrification is deliberately NOT checked here. Arcing *to* an already-lit
-- enemy is allowed; only arcing *from* one is blocked (see check_proc_func).
-- That asymmetry is the whole design: the "from" rule is what closes the
-- feedback loop, while leaving "to" open is what keeps the buff working for a
-- player who also runs Contagion or an arc weapon, both of which electrify
-- enemies we did not.
local function _next_target(broadphase, enemy_side_names, from_position, hit_units)
	table.clear(BROADPHASE_RESULTS)

	local num_hits = broadphase.query(broadphase, from_position, JUMP_RADIUS,
		BROADPHASE_RESULTS, enemy_side_names)
	local best, best_distance

	for i = 1, num_hits do
		local candidate = BROADPHASE_RESULTS[i]

		if not hit_units[candidate] and HEALTH_ALIVE[candidate] then
			local candidate_position = POSITION_LOOKUP[candidate]

			if candidate_position then
				local distance = Vector3.length_squared(candidate_position - from_position)

				if not best_distance or distance < best_distance then
					best, best_distance = candidate, distance
				end
			end
		end
	end

	return best
end

arc_chain.template = function ()
	return {
		-- server_only: this deals damage and applies buffs to enemies, which is
		-- authoritative state and must not also run predicted on a client.
		class_name = "server_only_proc_buff",
		max_stacks = 1,
		max_stacks_cap = 1,
		predicted = false,
		buff_category = buff_categories.hordes_buff,
		-- The number IS the chance -- ProcBuff.update_proc_events rolls it
		-- (proc_buff.lua:330) before check_proc_func runs, so there is no dice
		-- roll to write here and the budget below only ever sees hits that
		-- already passed it.
		proc_events = {
			[proc_events.on_hit] = ARC_CHANCE,
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
			template_data.hit_units = {}
		end,
		-- Ordered cheapest first, and each rejection is doing a different job.
		check_proc_func = function (params, template_data, template_context, t)
			-- 1. Our own arc damage. This is the absolute recursion guard: arcs
			--    deal damage as the player, so every arc announces on_hit and
			--    would otherwise start a fresh chain. One pointer comparison.
			if params.damage_profile == ARC_DAMAGE_PROFILE then
				return _blocked(BLOCKED_OWN_DAMAGE)
			end

			-- 2. Buff-sourced damage -- including hordes_ailment_shock's own
			--    interval ticks, which we are applying to every target and which
			--    fire on_hit every 0.3-0.8s per electrified enemy.
			if params.attack_type == attack_types.buff then
				return _blocked(BLOCKED_BUFF_DAMAGE)
			end

			if not template_data.broadphase or not template_data.enemy_side_names then
				return false
			end

			local origin = params.attacked_unit

			if not origin or not HEALTH_ALIVE[origin] then
				return _blocked(BLOCKED_NO_TARGET)
			end

			local origin_extension = ScriptUnit.has_extension(origin, "buff_system")

			if not origin_extension then
				return _blocked(BLOCKED_NO_TARGET)
			end

			-- 3. The per-enemy cooldown. Every target an arc touches gets
			--    SHOCK_BUFF, so an enemy we just chained through cannot be the
			--    origin of a fresh chain until it wears off. Still no
			--    bookkeeping table, no sweeping and no state to lose on a
			--    reload -- it lives on the enemy, in the game's own system --
			--    but it now answers for OUR shock only. See the note on
			--    SHOCK_BUFF for why asking the general "is it electrified"
			--    question was a mistake.
			--
			--    Not the recursion guard, despite looking like one. Guard 1 is
			--    what makes recursion impossible; this is a game rule and can be
			--    tuned or removed without the buff eating itself.
			if origin_extension:current_stacks(SHOCK_BUFF) > 0 then
				return _blocked(BLOCKED_ELECTRIFIED)
			end

			proc_counts.cwah_arc_chain_attempts = (proc_counts.cwah_arc_chain_attempts or 0) + 1

			-- 4. The seatbelt.
			if t - template_data.window_start >= 1 then
				template_data.window_start = t
				template_data.window_count = 0
			end

			if template_data.window_count >= ARCS_PER_SECOND then
				return _blocked(BLOCKED_BUDGET)
			end

			return true
		end,
		-- The chain is walked here, in one call, rather than by letting each arc
		-- re-trigger the buff. That is not a style choice: re-entry is exactly
		-- what guard 3 blocks, so jumps have to come from a loop.
		proc_func = function (params, template_data, template_context, t)
			local player_unit = template_context.unit
			local broadphase = template_data.broadphase
			local enemy_side_names = template_data.enemy_side_names
			local hit_units = template_data.hit_units

			table.clear(hit_units)

			local source = params.attacked_unit

			hit_units[source] = true

			template_data.window_count = template_data.window_count + 1

			local jumps = 0

			for _ = 1, MAX_JUMPS do
				local source_position = POSITION_LOOKUP[source]

				if not source_position then
					break
				end

				local target = _next_target(broadphase, enemy_side_names, source_position, hit_units)

				if not target then
					break
				end

				hit_units[target] = true

				local target_extension = ScriptUnit.has_extension(target, "buff_system")

				-- Electrify BEFORE dealing damage. The damage announces on_hit,
				-- and that announcement is queued for a later buff-system pass
				-- rather than delivered inline -- but ordering it this way means
				-- the guard is satisfied no matter how that queue is drained.
				if target_extension then
					pcall(target_extension.add_internally_controlled_buff, target_extension,
						SHOCK_BUFF, t, "owner_unit", player_unit)
				end

				local target_position = POSITION_LOOKUP[target]
				local attack_direction = Vector3.normalize(target_position - source_position)

				-- attack_types.ranged rather than .buff on purpose: it is what
				-- makes arcs proc the player's other on-hit effects, which was
				-- the point of the buff. Guard 1 in check_proc_func is what
				-- makes that safe.
				local ok, err = pcall(Attack.execute, target, ARC_DAMAGE_PROFILE,
					"power_level", ARC_POWER_LEVEL,
					"charge_level", 1,
					"attacking_unit", player_unit,
					"attack_direction", attack_direction,
					"attack_type", attack_types.ranged,
					"damage_type", damage_types.arc_chain)

				if not ok then
					mod:error("arc chain could not damage a target: %s", tostring(err))

					break
				end

				-- After the damage, so anything hanging off an arc sees the same
				-- world state a normal on_hit subscriber would have. pcall'd
				-- because a fault in a subscriber must not truncate the chain.
				local on_arc_hit = arc_chain.on_arc_hit

				if on_arc_hit then
					local hit_ok, hit_err = pcall(on_arc_hit, player_unit, target, t)

					if not hit_ok then
						mod:error("arc chain on_arc_hit subscriber failed: %s", tostring(hit_err))
					end
				end

				jumps = jumps + 1
				source = target
			end

			if jumps > 0 then
				proc_counts.cwah_arc_chain = (proc_counts.cwah_arc_chain or 0) + 1
				proc_counts.cwah_arc_chain_jumps = (proc_counts.cwah_arc_chain_jumps or 0) + jumps

				mod:debug_log("arc chain: %d jump(s)", jumps)
			end
		end,
	}
end

return arc_chain
