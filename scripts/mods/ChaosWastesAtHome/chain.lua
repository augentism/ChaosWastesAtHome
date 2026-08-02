local mod = get_mod("ChaosWastesAtHome")

local MissionTemplates = require("scripts/settings/mission/mission_templates")
local Promise = require("scripts/foundation/utilities/promise")

local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")
local difficulty = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/difficulty")

-- Rolling the next set of missions, and launching the one you pick.
--
-- Launching mid-session is SoloPlay's trick: reset the multiplayer session,
-- boot a fresh singleplayer one, then change mechanism with a mission context.
-- That is how SoloPlay starts a mission from inside a running one, so we are
-- on a path the game already supports rather than inventing a transition.

local chain = {}

local NUM_OPTIONS = 3

-- The pool the mod itself applies to: regular adventure missions running
-- coop_complete_objective. Operations and the horde/psykhanium missions run
-- other game modes, which this mod does not hook.
local function _is_eligible(mission)
	return mission.mechanism_name == "adventure"
		and mission.game_mode_name == "coop_complete_objective"
		and mission.mission_type ~= "operations"
		and mission.level ~= nil
end

chain.eligible_missions = function ()
	local names = {}

	for name, mission in pairs(MissionTemplates) do
		if _is_eligible(mission) then
			names[#names + 1] = name
		end
	end

	table.sort(names)

	return names
end

-- Difficulty and circumstance of the mission being played, so the next one in
-- the chain matches. Kept in one place because ramping difficulty later means
-- changing only this function.
chain.current_params = function ()
	local difficulty = Managers.state and Managers.state.difficulty
	local circumstance = Managers.state and Managers.state.circumstance
	local mission_manager = Managers.state and Managers.state.mission

	if not difficulty then
		return nil
	end

	-- Initial, not current. Circumstances and mutators call modify_resistance
	-- at runtime, so get_resistance() returns a value that already includes
	-- the circumstance's bump. Copying that forward while also re-applying the
	-- same circumstance stacks the modifier again every hop -- difficulty
	-- climbing silently until a base-game table indexed by difficulty runs off
	-- its end (health stations crash at 6). The initial values are the run's
	-- true baseline, and the circumstance then applies once, as designed.
	local ok_c, challenge = pcall(difficulty.get_initial_challenge, difficulty)
	local ok_r, resistance = pcall(difficulty.get_initial_resistance, difficulty)

	if not ok_c or not ok_r then
		return nil
	end

	local circumstance_name = "default"

	if circumstance then
		local ok, name = pcall(circumstance.circumstance_name, circumstance)

		if ok and name then
			circumstance_name = name
		end
	end

	local played

	if mission_manager then
		local ok, name = pcall(mission_manager.mission_name, mission_manager)

		played = ok and name or nil
	end

	-- Belt and braces on top of using the initial values. Several base-game
	-- tables are indexed by a difficulty derived from these two and are sized
	-- for the 1-5 range; anything above that is a nil index and a hard crash
	-- during level init, long after the value that caused it was chosen.
	local clamped_challenge = math.max(1, math.min(5, challenge))
	local clamped_resistance = math.max(1, math.min(5, resistance))

	if clamped_challenge ~= challenge or clamped_resistance ~= resistance then
		mod:debug_log("clamped run difficulty from challenge", challenge, "resistance", resistance,
			"to challenge", clamped_challenge, "resistance", clamped_resistance)
	end

	local params = {
		challenge = clamped_challenge,
		resistance = clamped_resistance,
		circumstance_name = circumstance_name,
		played_mission = played,
	}

	-- A Havoc mission's rank is the rung, not its challenge/resistance -- those
	-- are derived from it. Carrying the rank through is what lets the ramp
	-- continue climbing once the run is past Auric.
	local current = difficulty.current()

	if current and current.havoc_rank then
		params.havoc_rank = current.havoc_rank
	end

	return params
end

-- Three distinct missions at the run's difficulty and circumstance, excluding
-- the one just played so the chain always moves somewhere new.
chain.roll_options = function (params)
	params = params or chain.current_params()

	if not params then
		return nil
	end

	local pool = {}

	for _, name in ipairs(chain.eligible_missions()) do
		if name ~= params.played_mission then
			pool[#pool + 1] = name
		end
	end

	-- Options are rolled at the difficulty the *next* mission will run at, so
	-- the ramp is visible on the picker rather than being a surprise on load.
	local target = params

	if mod:get("difficulty_ramp") then
		target = difficulty.next(params) or params
	end

	local options = {}

	for _ = 1, math.min(NUM_OPTIONS, #pool) do
		local index = math.random(#pool)
		local mission_name = pool[index]
		local option

		if target.havoc_rank then
			-- Havoc missions carry their whole configuration in havoc_data --
			-- rank, theme, faction, circumstances -- and the mechanism reads
			-- challenge/resistance from there, so the two are built together.
			local havoc_data, challenge, resistance = difficulty.build_havoc_data(target.havoc_rank, mission_name)

			option = {
				mission_name = mission_name,
				challenge = challenge,
				resistance = resistance,
				havoc_data = havoc_data,
			}
		else
			option = {
				mission_name = mission_name,
				challenge = target.challenge,
				resistance = target.resistance,
				circumstance_name = params.circumstance_name,
			}
		end

		option.difficulty_label = difficulty.describe(target)
		options[#options + 1] = option

		table.remove(pool, index)
	end

	return options
end

chain.mission_display_name = function (mission_name)
	local mission = MissionTemplates[mission_name]
	local loc_key = mission and mission.mission_name

	if not loc_key then
		return mission_name
	end

	local ok, display = pcall(Localize, loc_key)

	if not ok or not display or display == "" or string.starts_with(display, "<") then
		return mission_name
	end

	return display
end

-- Launches a mission context, replacing the current session. Mirrors
-- SoloPlay.start_game: the session has to finish tearing down before
-- change_mechanism will take, hence the poll.
chain.launch = function (mission_context)
	local mission = MissionTemplates[mission_context.mission_name]

	if not mission then
		mod:error("cannot launch unknown mission '%s'", tostring(mission_context.mission_name))

		return false
	end

	local mechanism_name = mission.mechanism_name

	mod:info("launching '%s' (challenge %s, resistance %s, %s)",
		tostring(mission_context.mission_name),
		tostring(mission_context.challenge),
		tostring(mission_context.resistance),
		mission_context.havoc_data
			and ("havoc_data " .. tostring(mission_context.havoc_data))
			or ("circumstance " .. tostring(mission_context.circumstance_name)))

	Managers.multiplayer_session:reset("ChaosWastesAtHome run continuing")
	Managers.multiplayer_session:boot_singleplayer_session()

	Promise.until_true(function ()
		local session = Managers.multiplayer_session

		if not session._session_boot or not session._session_boot.leaving_game_session then
			return false
		end

		return true
	end):next(function ()
		Managers.mechanism:change_mechanism(mechanism_name, mission_context)
		Managers.mechanism:trigger_event("all_players_ready")
	end)

	return true
end

return chain
