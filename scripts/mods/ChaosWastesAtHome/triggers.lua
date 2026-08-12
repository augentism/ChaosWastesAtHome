local mod = get_mod("ChaosWastesAtHome")

local Breed = require("scripts/utilities/breed")
local BuffTemplates = require("scripts/settings/buff/buff_templates")
local HordesBuffsData = require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")
local MissionObjectiveSystem = require("scripts/extension_systems/mission_objective/mission_objective_system")
local MinionDeathManager = require("scripts/managers/minion/minion_death_manager")

-- Grant sources. Each source is independently toggleable, has its own roll
-- chance, and its own choice of what it hands out. Sources feed a single
-- arbiter (`triggers.fire`) so the per-mission budget is enforced in one place.

local triggers = {}

-- Mortis hands out its three legendary picks at waves 3/6/9, and the wave
-- number selects the category weighting for the pick (see
-- mission_buffs_settings.filtering_categories_pick_rate_per_wave -- wave 3
-- favours ability/grenade buffs, 6 is even, 9 favours jackpots). We rotate
-- through the same three so successive picks feel like a real Mortis run
-- rather than three rolls off one table.
local LEGENDARY_WAVE_ROTATION = { 3, 6, 9 }

local state

triggers.reset = function ()
	state = {
		kills = 0,
		time_accum = 0,
		family_granted = 0,
		legendary_granted = 0,
		legendary_index = 0,
		prev_terror_events = 0,
		family_requested = false,
		repump_accum = 0,
	}
end

triggers.reset()

triggers.stats = function ()
	return state
end

local function _local_player()
	return Managers.player and Managers.player:local_player_safe(1)
end

-- Family buffs are drawn from the family the player picked at mission start.
-- Asking for one before that choice is resolved makes the selector log an
-- error and hand out nothing, so we gate on it.
local NUM_OPTIONS_PER_CHOICE = 3

local function _persistent()
	local manager = mod.manager
	local handler = manager and manager._mission_buffs_handler

	return handler and handler._persistent_data
end

-- How many legendary buffs the player could still be offered.
--
-- Worth checking before spending budget: the selector needs three to build a
-- choice and, if it cannot find them, puts the ones it took back and logs an
-- error. Nothing reaches the player, but the event has already been fired --
-- so without this the grant looks successful, the budget is spent, and the
-- fallback to a family buff never runs.
local function _legendary_pool_size(player)
	local persistent = _persistent()

	if not persistent or not player then
		return 0
	end

	local ok, pools = pcall(persistent.get_legendary_buffs_available_for_player, persistent, player)

	if not ok or type(pools) ~= "table" then
		return 0
	end

	local total = 0

	for _, buffs in pairs(pools) do
		if type(buffs) == "table" then
			total = total + #buffs
		end
	end

	return total
end

-- Same idea for family buffs. Read straight off the persistent data rather
-- than through the handler, whose accessor logs an error when both pools are
-- empty -- which is a normal state late in a run, not a fault.
local function _family_pool_size(player)
	local persistent = _persistent()

	if not persistent or not player then
		return 0
	end

	local total = 0

	for _, getter in ipairs({ "get_player_priority_family_buffs_available", "get_player_family_buffs_available" }) do
		local ok, buffs = pcall(persistent[getter], persistent, player)

		if ok and type(buffs) == "table" then
			total = total + #buffs
		end
	end

	return total
end

local function _has_family(player)
	local manager = mod.manager

	if not manager or not player then
		return false
	end

	local ok, family = pcall(manager.get_buff_family_selected_by_player, manager, player)

	return ok and family ~= nil
end

-- Name search, for the "I know roughly what it is called" case.
--
-- Searches HordesBuffsData rather than BuffTemplates: the latter holds every
-- buff in the game, thousands of talent and weapon entries included, and none
-- of those are meant to be handed out as mission buffs.
triggers.find_buff_names = function (needle)
	local matches = {}

	for name in pairs(HordesBuffsData) do
		if not needle or needle == "" or string.find(name, needle, 1, true) then
			matches[#matches + 1] = name
		end
	end

	table.sort(matches)

	return matches
end

-- Grant one specific buff by name, bypassing the pools and the budget.
--
-- A testing tool, not a trigger: it does not touch the per-mission budget and
-- does not roll. It does save to persistent data like a real grant, so the buff
-- carries into the next mission of a run and stops being offered again.
--
-- Returns ok, reason -- the caller reports, this stays quiet.
triggers.grant_named = function (buff_name)
	if not buff_name or buff_name == "" then
		return false, "no buff name given"
	end

	local manager = mod.manager
	local handler = manager and manager._mission_buffs_handler

	if not handler then
		return false, "the buff system is not running"
	end

	local player = _local_player()

	if not player or not player.player_unit then
		return false, "no local player unit"
	end

	local template = BuffTemplates[buff_name]

	if not template then
		return false, string.format("no buff template called '%s'", buff_name)
	end

	-- Same trap as the custom buffs: a template with no name crashes on apply,
	-- deep inside the buff extension. Cheap to close here for any template that
	-- reaches this path, whoever defined it.
	if not template.name then
		template.name = buff_name
	end

	-- pcall because this is reachable from chat with arbitrary input, and the
	-- failure modes downstream are hard errors rather than return values.
	local ok, err = pcall(handler.give_buff_to_player, handler, player, buff_name, false, false)

	if not ok then
		return false, tostring(err)
	end

	mod:debug_log("granted '%s' by name", buff_name)

	return true
end

triggers.grant_family = function ()
	if not mod.manager then
		return false
	end

	local budget = mod:get("max_family_buffs") or 0

	if budget > 0 and state.family_granted >= budget then
		return false
	end

	local player = _local_player()

	if not _has_family(player) then
		return false
	end

	local available = _family_pool_size(player)

	if available < 1 then
		mod:debug_log("family pool exhausted for this run - no family buff to give")

		return false
	end

	Managers.event:trigger("mission_buffs_event_request_family_buff_for_all")

	state.family_granted = state.family_granted + 1

	mod:debug_log("granted family buff (%d)", state.family_granted)

	return true
end

triggers.grant_legendary = function ()
	if not mod.manager then
		return false
	end

	local budget = mod:get("max_legendary_choices") or 0

	if budget > 0 and state.legendary_granted >= budget then
		return false
	end

	local available = _legendary_pool_size(_local_player())

	if available < NUM_OPTIONS_PER_CHOICE then
		mod:debug_log("legendary pool exhausted -", available, "left, need", NUM_OPTIONS_PER_CHOICE,
			"- falling back to a family buff")

		return false
	end

	state.legendary_index = state.legendary_index + 1

	local wave_num = LEGENDARY_WAVE_ROTATION[(state.legendary_index - 1) % #LEGENDARY_WAVE_ROTATION + 1]

	Managers.event:trigger("mission_buffs_event_request_legendary_buff_choice", wave_num, 3)

	state.legendary_granted = state.legendary_granted + 1

	mod:debug_log("granted legendary choice (%d) using wave weighting %d", state.legendary_granted, wave_num)

	return true
end

local function _roll(chance)
	chance = chance or 100

	return chance >= 100 or chance > 0 and math.random(1, 100) <= chance
end

-- Runs a source's roll and hands out whatever it is configured for. If that
-- kind is already exhausted for the mission we fall back to the other one, so
-- a trigger never silently does nothing while budget remains.
triggers.fire = function (source)
	if not mod.manager then
		return false
	end

	if not _roll(mod:get(source .. "_chance")) then
		mod:debug_log("%s trigger rolled a miss", source)

		return false
	end

	local kind = mod:get(source .. "_grant")

	if kind == "random" then
		kind = math.random(1, 2) == 1 and "family" or "legendary"
	end

	local granted

	if kind == "legendary" then
		granted = triggers.grant_legendary() or triggers.grant_family()
	else
		granted = triggers.grant_family() or triggers.grant_legendary()
	end

	if not granted then
		mod:debug_log("%s trigger fired but the mission budget is spent", source)
	end

	return granted
end

-- ---------------------------------------------------------------------------
-- Source: mission objectives
-- ---------------------------------------------------------------------------

-- Hooked rather than hook_safe'd because end_mission_objective deletes the
-- objective on its way out -- we have to read it before the original runs.
mod:hook(MissionObjectiveSystem, "end_mission_objective", function (func, self, objective_name, group_id)
	local should_fire = false

	if mod.manager and mod:get("objective_enabled") then
		local ok, objective = pcall(self.active_objective, self, objective_name, group_id)

		if ok and objective then
			local is_side = false
			local side_ok, side_result = pcall(objective.is_side_mission, objective)

			if side_ok then
				is_side = side_result
			end

			should_fire = not is_side or mod:get("objective_side_missions")
		end
	end

	func(self, objective_name, group_id)

	if should_fire then
		mod:debug_log("objective completed: %s", tostring(objective_name))
		triggers.fire("objective")
	end
end)

-- ---------------------------------------------------------------------------
-- Source: kills
-- ---------------------------------------------------------------------------

local function _kill_counts(unit)
	local mode = mod:get("kills_mode")

	if mode == "all" then
		return true
	end

	local breed = Breed.unit_breed_or_nil(unit)

	if not breed then
		return false
	end

	local enemy_type = Breed.enemy_type(breed)

	if mode == "elites_specials" then
		return enemy_type == "elite" or enemy_type == "special"
	elseif mode == "specials" then
		return enemy_type == "special"
	elseif mode == "monsters" then
		return enemy_type == "monster" or enemy_type == "captain"
	end

	return false
end

mod:hook_safe(MinionDeathManager, "set_dead", function (self, unit)
	if not mod.manager or not mod:get("kills_enabled") then
		return
	end

	local ok, counts = pcall(_kill_counts, unit)

	if not ok or not counts then
		return
	end

	state.kills = state.kills + 1

	local threshold = mod:get("kills_threshold") or 0

	if threshold > 0 and state.kills >= threshold then
		state.kills = 0

		triggers.fire("kills")
	end
end)

-- ---------------------------------------------------------------------------
-- Sources: elapsed time, terror event clears
--
-- Both are polled from mod.update rather than hooked. Terror events usually
-- end inside TerrorEventManager.update (the event's own completion check),
-- not through stop_event -- stop_event is only the forced-stop path -- so
-- watching the active count drop to zero is the only signal that catches a
-- naturally finished event.
-- ---------------------------------------------------------------------------

-- Opens the mission's family choice. Mortis does this from GameModeSurvival
-- during wave-0 setup; a coop mission has no equivalent moment, so we do it
-- ourselves once the player is on their feet.
--
-- This is load-bearing, not cosmetic: the event sets
-- `should_have_buff_family_selected` on the persistent data, and until that
-- flag is set `check_player_buff_family_state` reports that the player does
-- NOT need a family. _manage_player_spawn then skips creating the choice, and
-- no card is ever queued -- the whole mod silently does nothing.
--
-- Waiting for the player unit matters too: the UI manager refuses to show a
-- choice notification while the player is not alive, and nothing would retry.
local function _request_family_choice()
	if state.family_requested then
		return
	end

	local player = Managers.player and Managers.player:local_player_safe(1)

	if not player or not player.player_unit then
		return
	end

	Managers.event:trigger("mission_buffs_event_request_family_buff_choice", 3)

	state.family_requested = true

	mod:debug_log("requested opening buff family choice")
end

-- The UI manager drops notifications it cannot show right now (player dead,
-- downed, or a choice already up) and leaves them queued. Mortis re-pumps the
-- queue at every wave boundary; we have no wave boundaries, so without this a
-- buff earned while downed would never be presented.
local function _repump_notifications(dt)
	state.repump_accum = state.repump_accum + dt

	if state.repump_accum < 1 then
		return
	end

	state.repump_accum = 0

	pcall(mod.manager.try_show_new_ui_notification, mod.manager)
end

triggers.update = function (dt)
	if not mod.manager then
		return
	end

	_request_family_choice()
	_repump_notifications(dt)

	if mod:get("time_enabled") then
		state.time_accum = state.time_accum + dt

		local interval = (mod:get("time_interval") or 0) * 60

		if interval > 0 and state.time_accum >= interval then
			state.time_accum = 0

			triggers.fire("time")
		end
	end

	if mod:get("events_enabled") then
		local terror_manager = Managers.state and Managers.state.terror_event
		local active = 0

		if terror_manager then
			local ok, num = pcall(terror_manager.num_active_events, terror_manager)

			if ok and num then
				active = num
			end
		end

		if state.prev_terror_events > 0 and active == 0 then
			mod:debug_log("terror event cleared")
			triggers.fire("events")
		end

		state.prev_terror_events = active
	end
end

return triggers
