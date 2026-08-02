local mod = get_mod("ChaosWastesAtHome")

local DangerSettings = require("scripts/settings/difficulty/danger_settings")
local HavocSettings = require("scripts/settings/havoc_settings")

-- The run's difficulty ladder.
--
-- Below Auric the game already has a ladder, so we walk DangerSettings rather
-- than incrementing numbers -- the steps are not uniform (damnation is 5/4,
-- auric is 5/5, so challenge alone does not describe a rung).
--
-- Past Auric there is nowhere left to climb in normal play, so the run moves
-- into Havoc: 25, then +5 a mission. Starting mid-Havoc rounds up to the next
-- multiple of 5, so an arbitrary starting rank lands back on the ladder.

local difficulty = {}

local HAVOC_ENTRY_RANK = 25
local HAVOC_STEP = 5
local HAVOC_MAX_RANK = 40
local FADING_LIGHT_TIER_2_RANK = 30
local NUM_ROLLED_CIRCUMSTANCES = 2

-- "The Emperor's Fading Light" -- always present on a Havoc mission, tier 2
-- from rank 30. Named for their icons (havoc_mutator_fading_light_1/_2)
-- rather than their loc keys, which are the less obvious
-- loc_havoc_increased_difficulty_name / loc_havoc_highest_difficulty_name.
local FADING_LIGHT = {
	[1] = "mutator_increased_difficulty",
	[2] = "mutator_highest_difficulty",
}

-- Havoc rank to challenge/resistance, mirroring SoloPlay's mapping so a
-- mod-launched Havoc mission is configured the way SoloPlay would configure it.
local function _havoc_challenge_resistance(rank)
	if rank <= 10 then
		return 3, 3
	elseif rank <= 20 then
		return 4, 4
	elseif rank <= 30 then
		return 5, 4
	end

	return 5, 5
end

local function _danger_index(challenge, resistance)
	for i, danger in ipairs(DangerSettings) do
		if danger.challenge == challenge and danger.resistance == resistance then
			return i
		end
	end

	return nil
end

-- Reads what the mission currently being played is set to.
difficulty.current = function ()
	local manager = Managers.state and Managers.state.difficulty

	if not manager then
		return nil
	end

	local havoc = manager.get_parsed_havoc_data and manager:get_parsed_havoc_data()

	if havoc and havoc.havoc_rank then
		return {
			havoc_rank = havoc.havoc_rank,
		}
	end

	local ok_c, challenge = pcall(manager.get_initial_challenge, manager)
	local ok_r, resistance = pcall(manager.get_initial_resistance, manager)

	if not ok_c or not ok_r then
		return nil
	end

	return {
		challenge = challenge,
		resistance = resistance,
	}
end

-- One rung up. This is the whole ramp; change it and the run's pacing changes.
difficulty.next = function (current)
	if not current then
		return nil
	end

	if current.havoc_rank then
		-- Capped at the top rung: a run that gets this far keeps going at
		-- Havoc 40 rather than climbing into ranks the ramp was never
		-- designed for. Also covers a player who started above the cap.
		local rank = math.floor(current.havoc_rank / HAVOC_STEP) * HAVOC_STEP + HAVOC_STEP

		return {
			havoc_rank = math.min(rank, HAVOC_MAX_RANK),
		}
	end

	local index = _danger_index(current.challenge, current.resistance)

	-- An unrecognised pair (a mod-set combination that is not a real rung)
	-- still needs somewhere to go: treat anything at or past Damnation-level
	-- challenge as topped out and move into Havoc.
	if not index then
		if (current.challenge or 0) >= 5 then
			return { havoc_rank = HAVOC_ENTRY_RANK }
		end

		return { challenge = (current.challenge or 1) + 1, resistance = (current.resistance or 1) + 1 }
	end

	local next_danger = DangerSettings[index + 1]

	if next_danger then
		return {
			challenge = next_danger.challenge,
			resistance = next_danger.resistance,
		}
	end

	return {
		havoc_rank = HAVOC_ENTRY_RANK,
	}
end

local function _roll_distinct(pool, count)
	local remaining = table.shallow_copy(pool)
	local picked = {}

	for _ = 1, math.min(count, #remaining) do
		local index = math.random(#remaining)

		picked[#picked + 1] = remaining[index]

		table.remove(remaining, index)
	end

	return picked
end

-- Builds the havoc_data string the mechanism expects. Format is positional and
-- comes from Havoc.parse_data:
--   mission;rank;theme;faction;circumstances;modifiers;challenge;resistance
-- with circumstances and modifiers colon-separated.
difficulty.build_havoc_data = function (rank, mission_name)
	local challenge, resistance = _havoc_challenge_resistance(rank)
	local theme = HavocSettings.themes[math.random(#HavocSettings.themes)]
	local faction = HavocSettings.factions[math.random(#HavocSettings.factions)]
	local circumstances = _roll_distinct(HavocSettings.circumstances, NUM_ROLLED_CIRCUMSTANCES)

	-- A theme is forced from rank 5 upward and the run only enters Havoc at
	-- 25, so there is always one. Its harsher second variant comes in at the
	-- same rank the Fading Light escalates.
	local per_theme = HavocSettings.circumstances_per_theme[theme]
	local tier = rank >= FADING_LIGHT_TIER_2_RANK and 2 or 1

	if per_theme then
		circumstances[#circumstances + 1] = per_theme[tier] or per_theme[1]
	end

	circumstances[#circumstances + 1] = FADING_LIGHT[tier]

	local data = string.format("%s;%d;%s;%s;%s;%s;%s;%s",
		mission_name,
		rank,
		theme,
		faction,
		table.concat(circumstances, ":"),
		"",
		challenge,
		resistance)

	mod:debug_log("havoc rank", rank, "theme", theme, "faction", faction,
		"circumstances", table.concat(circumstances, ", "))

	return data, challenge, resistance
end

difficulty.describe = function (params)
	if not params then
		return "unknown"
	end

	if params.havoc_rank then
		return "Havoc " .. tostring(params.havoc_rank)
	end

	local index = _danger_index(params.challenge, params.resistance)
	local danger = index and DangerSettings[index]

	if danger and danger.name then
		return danger.name
	end

	return string.format("challenge %s / resistance %s",
		tostring(params.challenge), tostring(params.resistance))
end

return difficulty
