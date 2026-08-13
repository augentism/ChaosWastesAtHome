local mod = get_mod("ChaosWastesAtHome")

local DangerSettings = require("scripts/settings/difficulty/danger_settings")
local HavocSettings = require("scripts/settings/havoc_settings")
local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
local HavocModifierConfig = require("scripts/settings/havoc/havoc_modifier_config")

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

-- The ladder as an ordered list, for the launcher's difficulty slider.
--
-- Derived from the same DangerSettings walk and the same HAVOC_* constants the
-- ramp uses, so the slider cannot drift out of step with what difficulty.next
-- does between missions. Entries are the plain {challenge, resistance} or
-- {havoc_rank} shapes that chain.roll_options already consumes.
--
-- Starts at Malice: Sedition and Uprising are below the floor this mod is
-- balanced around, and a run that opens there spends its first legs with
-- nothing to fight.
local FIRST_RUNG_CHALLENGE = 3

difficulty.rungs = function ()
	local rungs = {}

	for _, danger in ipairs(DangerSettings) do
		if danger.challenge >= FIRST_RUNG_CHALLENGE then
			rungs[#rungs + 1] = {
				challenge = danger.challenge,
				resistance = danger.resistance,
			}
		end
	end

	for rank = HAVOC_ENTRY_RANK, HAVOC_MAX_RANK, HAVOC_STEP do
		rungs[#rungs + 1] = { havoc_rank = rank }
	end

	return rungs
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

-- The modifier loadout for a Havoc rank.
--
-- HavocModifierConfig is indexed by rank, and each entry lists the modifiers
-- introduced or upgraded at that rank -- so the active set is everything up to
-- your rank, taking the highest level seen for each. Rank 25 works out to 18
-- modifiers around level 3-4; rank 40 to the same 18 at level 5.
--
-- These are not rolled. Two players at the same Havoc rank face the same
-- modifiers; only the circumstances vary. Deriving them from the game's own
-- table rather than inventing a curve is what makes a mod-launched Havoc
-- mission as hard as the real thing.
local function _modifiers_for_rank(rank)
	local levels = {}
	local highest = math.min(rank, #HavocModifierConfig)

	for i = 1, highest do
		local entry = HavocModifierConfig[i]

		if entry then
			for name, level in pairs(entry) do
				if not levels[name] or levels[name] < level then
					levels[name] = level
				end
			end
		end
	end

	local parts = {}
	local lookup = NetworkLookup and NetworkLookup.havoc_modifiers

	for name, level in pairs(levels) do
		local id = lookup and lookup[name]

		if id then
			-- "id.level", the encoding SoloPlay and the mechanism both expect.
			parts[#parts + 1] = string.format("%d.%d", id, level)
		else
			mod:debug_log("no network id for havoc modifier", name, "- skipping")
		end
	end

	return table.concat(parts, ":"), #parts
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

	local tier = rank >= FADING_LIGHT_TIER_2_RANK and 2 or 1

	-- The theme circumstance (hunting grounds, ventilation purge, toxic gas)
	-- is rolled rather than guaranteed, so not every Havoc mission carries an
	-- environmental hazard on top of its modifiers. Its harsher second variant
	-- comes in at the same rank the Fading Light escalates.
	--
	-- The theme *name* still goes into havoc_data either way: the field is
	-- positional and must stay well-formed, and it is only parsed, never acted
	-- on -- the hazard itself comes from the circumstance we may have skipped.
	local theme_chance = mod:get("havoc_theme_chance") or 100
	local per_theme = HavocSettings.circumstances_per_theme[theme]

	if per_theme and (theme_chance >= 100 or theme_chance > 0 and math.random(1, 100) <= theme_chance) then
		circumstances[#circumstances + 1] = per_theme[tier] or per_theme[1]
	end

	circumstances[#circumstances + 1] = FADING_LIGHT[tier]

	local modifiers, modifier_count = _modifiers_for_rank(rank)

	local data = string.format("%s;%d;%s;%s;%s;%s;%s;%s",
		mission_name,
		rank,
		theme,
		faction,
		table.concat(circumstances, ":"),
		modifiers,
		challenge,
		resistance)

	mod:debug_log("havoc rank", rank, "theme", theme, "faction", faction,
		"| modifiers:", modifier_count,
		"| circumstances:", table.concat(circumstances, ", "))

	return data, challenge, resistance, circumstances
end

-- Player-facing names for a list of circumstance ids, so the picker can show
-- what a Havoc mission actually rolled rather than just its rank. Havoc
-- circumstance templates are folded into the global CircumstanceTemplates and
-- each carries a ui.display_name loc key; anything without one falls back to
-- its raw id, which is still more use than showing nothing.
difficulty.describe_circumstances = function (circumstances)
	if not circumstances or #circumstances == 0 then
		return nil
	end

	local names = {}

	-- Fading Light is on every Havoc mission at a rank-determined tier, so
	-- listing it on all three cards tells you nothing about which to pick.
	local skip = {
		[FADING_LIGHT[1]] = true,
		[FADING_LIGHT[2]] = true,
	}

	for _, id in ipairs(circumstances) do
		if not skip[id] then
			local template = CircumstanceTemplates[id]
			local loc_key = template and template.ui and template.ui.display_name
			local label = id

			if loc_key then
				local ok, localized = pcall(Localize, loc_key)

				if ok and localized and localized ~= "" and not string.starts_with(localized, "<") then
					label = localized
				end
			end

			names[#names + 1] = label
		end
	end

	if #names == 0 then
		return nil
	end

	return table.concat(names, ", ")
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

	if danger then
		-- display_name, not name. The `name` field is the internal id and is
		-- lowercase ("malice"); display_name is a loc key resolving to "Malice"
		-- -- already capitalised, and translated, which hand-capitalising the id
		-- would not be.
		local loc_key = danger.display_name

		if loc_key then
			local ok, localized = pcall(Localize, loc_key)

			if ok and localized and localized ~= "" and not string.starts_with(localized, "<") then
				return localized
			end
		end

		-- Only if the lookup fails: capitalise the id rather than showing it raw.
		if danger.name then
			return danger.name:sub(1, 1):upper() .. danger.name:sub(2)
		end
	end

	return string.format("challenge %s / resistance %s",
		tostring(params.challenge), tostring(params.resistance))
end

return difficulty
