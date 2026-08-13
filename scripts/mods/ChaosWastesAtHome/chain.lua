local mod = get_mod("ChaosWastesAtHome")

local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
local MissionTemplates = require("scripts/settings/mission/mission_templates")
local MutatorTemplates = require("scripts/settings/mutator/mutator_templates")
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

-- Missions excluded by id, on top of the type filter below.
--
-- Ids, not display names, because the names are localized. Confirmed against
-- the localization export rather than guessed: the loc key is
-- loc_mission_name_<id>, so "The Orthus Offensive" resolves to km_enforcer_twins
-- -- the Karnak Twins map, typed `assassination`, which is exactly why the
-- operations filter below never caught it.
--
-- All three are long, scripted, multi-stage maps built around a full team, and
-- none of them belong in a rolled run. Pilgrimage independently denylists
-- km_enforcer_twins and reserves the other two.
local MISSION_DENYLIST = {
	km_enforcer_twins = true, -- The Orthus Offensive
	op_train = true, -- Rolling Steel
	op_no_mans_land = true, -- No Man's Land
}

-- The pool the mod itself applies to: regular adventure missions running
-- coop_complete_objective. Operations and the horde/psykhanium missions run
-- other game modes, which this mod does not hook.
local function _is_eligible(mission, name)
	return mission.mechanism_name == "adventure"
		and mission.game_mode_name == "coop_complete_objective"
		and mission.mission_type ~= "operations"
		and mission.level ~= nil
		and not MISSION_DENYLIST[name]
end

chain.eligible_missions = function ()
	local names = {}

	for name, mission in pairs(MissionTemplates) do
		if type(mission) == "table" and _is_eligible(mission, name) then
			names[#names + 1] = name
		end
	end

	table.sort(names)

	return names
end

-- ---------------------------------------------------------------------------
-- Maelstrom
-- ---------------------------------------------------------------------------

-- Every non-Havoc mission gets one, rolled per option.
--
-- These are the mission board's Maelstrom modifiers: the game ships them as
-- circumstance templates in two tiers, the standard set and a harder set used at
-- Auric, and identifies them by a maelstrom icon rather than any category field.
-- Prefix is the only reliable handle, hence the scan.
local MAELSTROM_PREFIX = "flash_mission_"
local MAELSTROM_AURIC_PREFIX = "high_flash_mission_"

-- Auric is the top normal rung, so it takes the harder set.
local AURIC_CHALLENGE = 5
local AURIC_RESISTANCE = 5

local maelstrom_pools = nil

-- A circumstance naming a mutator the game no longer has is a crash when the
-- mission loads, not a warning. Fatshark removes mutators between patches and
-- the templates referencing them survive, so this is the same guard SoloPlay
-- applies (SoloPlaySettings.lua:221) and the only client-side way to spot one.
local function _mutators_exist(template)
	local mutators = template.mutators

	if not mutators then
		return true
	end

	for i = 1, #mutators do
		if not MutatorTemplates[mutators[i]] then
			return false
		end
	end

	return true
end

local function _build_maelstrom_pools()
	local standard, auric = {}, {}

	for name, template in pairs(CircumstanceTemplates) do
		if type(template) == "table" and _mutators_exist(template) then
			-- starts_with, not a substring match: six_one_flash_mission_* is a
			-- third, special-cased set that carries its own challenge scaling
			-- and must not be rolled in here.
			if string.starts_with(name, MAELSTROM_AURIC_PREFIX) then
				auric[#auric + 1] = name
			elseif string.starts_with(name, MAELSTROM_PREFIX) then
				standard[#standard + 1] = name
			end
		end
	end

	table.sort(standard)
	table.sort(auric)

	mod:info("maelstrom pools: %d standard, %d auric", #standard, #auric)

	return { standard = standard, auric = auric }
end

-- Rolled fresh per option so the three cards can offer different ones.
local function _roll_maelstrom(challenge, resistance)
	if not maelstrom_pools then
		maelstrom_pools = _build_maelstrom_pools()
	end

	local is_auric = challenge >= AURIC_CHALLENGE and resistance >= AURIC_RESISTANCE
	local pool = is_auric and maelstrom_pools.auric or maelstrom_pools.standard

	-- Falls back to the standard set rather than to nothing, so an empty auric
	-- pool costs the harder variant and not the modifier itself.
	if #pool == 0 then
		pool = maelstrom_pools.standard
	end

	if #pool == 0 then
		return nil
	end

	return pool[math.random(#pool)]
end

-- Difficulty and circumstance of the mission being played, so the next one in
-- the chain matches. Kept in one place because ramping difficulty later means
-- changing only this function.
chain.current_params = function ()
	-- Named difficulty_manager, not difficulty: this file imports a module
	-- called `difficulty`, and a local of that name here silently shadows it
	-- for the rest of the function.
	local difficulty_manager = Managers.state and Managers.state.difficulty
	local circumstance = Managers.state and Managers.state.circumstance
	local mission_manager = Managers.state and Managers.state.mission

	if not difficulty_manager then
		return nil
	end

	-- Initial, not current. Circumstances and mutators call modify_resistance
	-- at runtime, so get_resistance() returns a value that already includes
	-- the circumstance's bump. Copying that forward while also re-applying the
	-- same circumstance stacks the modifier again every hop -- difficulty
	-- climbing silently until a base-game table indexed by difficulty runs off
	-- its end (health stations crash at 6). The initial values are the run's
	-- true baseline, and the circumstance then applies once, as designed.
	local ok_c, challenge = pcall(difficulty_manager.get_initial_challenge, difficulty_manager)
	local ok_r, resistance = pcall(difficulty_manager.get_initial_resistance, difficulty_manager)

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
chain.describe_params = function (params)
	return difficulty.describe(params)
end

-- skip_ramp is for the launcher.
--
-- In the chain this rolls the mission AFTER the one being played, so it ramps a
-- rung first. From the hub the player has just picked the rung they want to
-- start at, and ramping there would hand them something one step harder than
-- the slider says.
chain.roll_options = function (params, skip_ramp)
	params = params or chain.current_params()

	if not params then
		-- Reached when the end screen has no stored params and the difficulty
		-- manager is already destroyed, so nothing can be recomputed. Worth
		-- naming, because the symptom (an empty roll) looks identical to
		-- having no eligible missions.
		mod:error("cannot roll missions: no run difficulty recorded and none readable now")

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

	if mod:get("difficulty_ramp") and not skip_ramp then
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
			local havoc_data, challenge, resistance, circumstances =
				difficulty.build_havoc_data(target.havoc_rank, mission_name)

			option = {
				mission_name = mission_name,
				challenge = challenge,
				resistance = resistance,
				havoc_data = havoc_data,
				modifiers_label = difficulty.describe_circumstances(circumstances),
			}
		else
			-- A fresh maelstrom per option rather than carrying the played
			-- mission's circumstance forward: the run is meant to keep throwing
			-- new conditions at you, and the three cards differing is what makes
			-- the choice interesting rather than cosmetic.
			local maelstrom = _roll_maelstrom(target.challenge, target.resistance)

			option = {
				mission_name = mission_name,
				challenge = target.challenge,
				resistance = target.resistance,
				circumstance_name = maelstrom or params.circumstance_name or "default",
				modifiers_label = maelstrom and difficulty.describe_circumstances({ maelstrom }) or nil,
			}
		end

		option.difficulty_label = difficulty.describe(target)
		options[#options + 1] = option

		table.remove(pool, index)
	end

	return options
end

-- The map preview the mission board draws, read straight off the template.
--
-- No shipped assets to duplicate: every mission template carries texture_small,
-- texture_medium and texture_big, and the mission board picks between the first
-- two by tile size (mission_board_view_blueprints.lua:1251). Medium is the right
-- one for a card this size.
chain.mission_preview_texture = function (mission_name)
	local mission = MissionTemplates[mission_name]

	if not mission then
		return nil
	end

	return mission.texture_medium or mission.texture_small or mission.texture_big
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
