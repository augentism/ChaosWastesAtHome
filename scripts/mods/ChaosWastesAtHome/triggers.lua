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

-- first_mission is passed in rather than worked out here.
--
-- Only the starting hand cares, and it is a property of the RUN, not of the
-- mission: everything else this resets is deliberately per-mission. The caller
-- already holds the run module, so it decides once at mission start instead of
-- this file reaching across for it every frame.
--
-- Defaults to false, so the file-scope call below and the teardown call do not
-- arm a hand. A mod reload mid-mission therefore skips the hand for the rest of
-- that mission, which is the right way round: by then it has already been dealt.
triggers.reset = function (first_mission)
	state = {
		first_mission = first_mission == true,
		kills = 0,
		time_accum = 0,
		family_granted = 0,
		legendary_granted = 0,
		legendary_index = 0,
		prev_terror_events = 0,
		terror_event_names = {},
		event_groups_attempted = {},
		event_repeat_blocked = 0,
		family_requested = false,
		repump_accum = 0,
		starting_legendary_given = 0,
		starting_family_given = 0,
		starting_legendary_tried = 0,
		starting_family_tried = 0,
		starting_accum = 0,
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
-- Returns ok, reason. Successful grants are also recorded in the console log.
triggers.grant_named = function (buff_name, source)
	if not buff_name or buff_name == "" then
		return false, "no buff name given"
	end
	if mod.user_buffs and not mod.user_buffs.can_grant(buff_name) then
		return false, "player-created buffs require a singleplay CWaH run (disable Realms hosting)"
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

	mod:info("reward granted: source=%s kind=named buff=%s", source or "named_api", buff_name)

	return true
end

-- off_budget: a starting buff, which is extra rather than an advance on the
-- run's allowance. It neither checks the budget nor consumes it.
--
-- family_granted still counts every one of them, because it is the honest total
-- of what the player received and /cw_status reports it. The budget is measured
-- against that total minus the ones that came free, so the run's own triggers
-- still get their full allowance afterwards.
local function _log_reward(source, kind, off_budget, detail)
	mod:info("reward requested: source=%s kind=%s off_budget=%s family_total=%d legendary_total=%d detail=%s",
		source or (off_budget and "starting_hand" or "direct_api"), kind,
		tostring(not not off_budget), state.family_granted, state.legendary_granted, detail or "none")
end

triggers.grant_family = function (off_budget, source, detail)
	if not mod.has_authority() then
		return false
	end

	local budget = mod:get("max_family_buffs") or 0

	if not off_budget and budget > 0
		and state.family_granted - state.starting_family_given >= budget then
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

	if off_budget then
		state.starting_family_given = state.starting_family_given + 1
	end

	_log_reward(source, "family", off_budget, detail)

	return true
end

-- off_budget as above: a starting pick, extra rather than an advance.
triggers.grant_legendary = function (off_budget, source, detail)
	if not mod.has_authority() then
		return false
	end

	local budget = mod:get("max_legendary_choices") or 0

	if not off_budget and budget > 0
		and state.legendary_granted - state.starting_legendary_given >= budget then
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

	if off_budget then
		state.starting_legendary_given = state.starting_legendary_given + 1
	end

	_log_reward(source, "legendary_choice", off_budget, detail)

	return true
end

local function _roll(chance)
	chance = chance or 100

	return chance >= 100 or chance > 0 and math.random(1, 100) <= chance
end

-- Runs a source's roll and hands out whatever it is configured for. If that
-- kind is already exhausted for the mission we fall back to the other one, so
-- a trigger never silently does nothing while budget remains.
triggers.fire = function (source, detail, settings)
	if not mod.has_authority() then
		return false
	end

	-- TEST7 extraction guard: spend the encounter's attempt before chance or
	-- budget checks, so repeat waves and changed settings cannot farm rewards.
	local group = source == "events" and state.event_reward_group
	if group then
		detail = group .. ":" .. (detail or "unnamed")
		if state.event_groups_attempted[group] then
			state.event_repeat_blocked = state.event_repeat_blocked + 1
			mod:info("reward blocked: source=events reason=repeat_encounter group=%s", group)
			return false
		end
		state.event_groups_attempted[group] = true
	end

	local chance = settings and settings.chance or mod:get(source .. "_chance")
	local configured = settings and settings.grant or mod:get(source .. "_grant")
	if not _roll(chance) then
		mod:debug_log("%s trigger rolled a miss", source)

		return false
	end

	local kind = configured

	if kind == "random" then
		kind = math.random(1, 2) == 1 and "family" or "legendary"
	end

	local granted
	local context = string.format("configured=%s selected=%s chance=%s %s",
		tostring(configured), tostring(kind),
		tostring(chance or 100), detail or "")

	if kind == "legendary" then
		granted = triggers.grant_legendary(false, source, context) or triggers.grant_family(false, source, context)
	else
		granted = triggers.grant_family(false, source, context) or triggers.grant_legendary(false, source, context)
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

	if mod.has_authority() and mod:get("objective_enabled") then
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
		triggers.fire("objective", string.format("objective=%s group=%s", tostring(objective_name), tostring(group_id)))
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
	-- One DMF hook owns death dispatch. Shrine rewards also work when the
	-- independent kill-counter source is disabled.
	if mod.shrines then mod.shrines.boss_died(unit) end
	if not mod.has_authority() or not mod:get("kills_enabled") then
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

		triggers.fire("kills", string.format("mode=%s threshold=%s", tostring(mod:get("kills_mode")), tostring(threshold)))
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

local EXTRACTION_EVENT_GROUPS = {
	event_habs_escape = "cm_habs_extraction",
	event_habs_escape_stoppers = "cm_habs_extraction",
	event_habs_escape_guard = "cm_habs_extraction",
}

local function _observe_terror_event(event_name)
	if type(event_name) ~= "string" then return end
	state.terror_event_names[event_name] = true
	local group = EXTRACTION_EVENT_GROUPS[event_name]
	if group and not state.event_reward_group then
		state.event_reward_group = group
		mod:info("encounter reward guard armed: group=%s event=%s", group, event_name)
	end
end

-- Hook the class table shared by the engine, avoiding a second delayed hook
-- namespace. Capture identity only; spawning, enemy AI and level flow remain
-- entirely native. The extraction lock lives until triggers.reset next map.
mod:hook_safe("TerrorEventManager", "_start_event", function (self, event_name)
	if mod.manager and mod.has_authority() then _observe_terror_event(event_name) end
end)

triggers.poll_terror_events = function ()
	local manager = Managers.state and Managers.state.terror_event
	if manager ~= state.terror_manager then
		state.terror_manager = manager
		state.prev_terror_events = 0
	end
	if not manager then return end
	local ok, active = pcall(manager.num_active_events, manager)
	-- Missing managers and read errors are NOT completed encounters. Preserve
	-- the previous valid sample so a transient failure cannot manufacture zero.
	if not ok or type(active) ~= "number" or active < 0 or active ~= active then return end
	for _, event in ipairs(manager._active_events or {}) do
		_observe_terror_event(event.name)
	end
	if state.prev_terror_events > 0 and active == 0 then
		local names = {}
		for name in pairs(state.terror_event_names) do names[#names + 1] = name end
		table.sort(names)
		local context = #names > 0 and table.concat(names, ",") or "unnamed_or_trickle"
		state.terror_event_names = {}
		if mod:get("events_enabled") then triggers.fire("events", context) end
	end
	state.prev_terror_events = active
end

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
	mod:info("reward requested: source=mission_start kind=family_choice")

	mod:debug_log("requested opening buff family choice")
end

-- The UI manager drops notifications it cannot show right now (player dead,
-- downed, or a choice already up) and leaves them queued. Mortis re-pumps the
-- queue at every wave boundary; we have no wave boundaries, so without this a
-- buff earned while downed would never be presented.
-- The opening hand: a burst of picks the moment the run is under way.
--
-- Handed out one at a time rather than all at once. Firing the whole burst in a
-- single frame does queue -- the UI manager holds what it cannot show -- but
-- grant_legendary's pool check reads a pool nothing has spent yet, so three
-- requests can all pass a check only two can actually satisfy. Pacing them
-- keeps every check honest, and gives the ordering the option describes:
-- the card picks first, then the family buffs.
--
-- Two gates, because neither alone is enough. _choice_is_up covers the player
-- deliberating over a card, but reads false in the frames between asking for a
-- card and it appearing; the minimum gap covers that window, and is also what
-- paces the family buffs, which grant outright and never put a card up.
local STARTING_GRANT_GAP = 1.5

local function _grant_starting_buffs(dt)
	-- Once per run, not once per mission. triggers.reset runs at the start of
	-- every mission in the chain -- that is what the per-mission budgets need --
	-- so the burst's own counters were clear again each time and the hand was
	-- being dealt at the top of every mission.
	if not state.first_mission then
		return
	end

	local want_legendary = mod:get("starting_legendary_picks") or 0
	local want_family = mod:get("starting_family_buffs") or 0

	-- Attempts, not grants. A refused pick still counts as attempted so it is
	-- dropped rather than retried; the *given* counters are owned by the grant
	-- functions and only move on success, which is what the budget maths needs.
	if state.starting_legendary_tried >= want_legendary
		and state.starting_family_tried >= want_family then
		return
	end

	-- Nothing before the opening family choice is resolved: grant_family refuses
	-- outright without a family, and a card offered over the family card would
	-- only be queued behind it.
	if not _has_family(_local_player()) then
		return
	end

	state.starting_accum = state.starting_accum + dt

	-- Falls back to the gap alone if the predicate is somehow not there yet:
	-- treating "cannot tell" as "a card is up" would stall the burst forever.
	local choice_up = mod.choice_is_up and mod.choice_is_up() or false

	if state.starting_accum < STARTING_GRANT_GAP or choice_up then
		return
	end

	state.starting_accum = 0

	-- Counted whether or not the grant lands. The per-run budget or an exhausted
	-- pool can refuse one, and retrying a refused pick every frame for the rest
	-- of the mission is worse than dropping it: one attempt per configured pick.
	if state.starting_legendary_tried < want_legendary then
		state.starting_legendary_tried = state.starting_legendary_tried + 1

		if triggers.grant_legendary(true) then
			return
		end
	end

	if state.starting_family_tried < want_family then
		state.starting_family_tried = state.starting_family_tried + 1

		triggers.grant_family(true)
	end
end

local function _repump_notifications(dt)
	state.repump_accum = state.repump_accum + dt

	if state.repump_accum < 1 then
		return
	end

	state.repump_accum = 0

	pcall(mod.manager.try_show_new_ui_notification, mod.manager)
end

triggers.update = function (dt)
	if not mod.has_authority() then
		return
	end

	_request_family_choice()
	_repump_notifications(dt)
	_grant_starting_buffs(dt)

	if mod:get("time_enabled") then
		state.time_accum = state.time_accum + dt

		local interval = (mod:get("time_interval") or 0) * 60

		if interval > 0 and state.time_accum >= interval then
			state.time_accum = 0

			triggers.fire("time", string.format("interval_seconds=%s", tostring(interval)))
		end
	end

	triggers.poll_terror_events()

end

return triggers
