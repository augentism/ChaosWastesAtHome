local mod = get_mod("ChaosWastesAtHome")

local DangerSettings = require("scripts/settings/difficulty/danger_settings")
local HavocSettings = require("scripts/settings/havoc_settings")
local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
local HavocModifierConfig = require("scripts/settings/havoc/havoc_modifier_config")
local MissionTemplates = require("scripts/settings/mission/mission_templates")

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

-- Themes the game itself considers valid for a mission.
--
-- Vanilla picks the theme first and the mission from that theme's list
-- (Havoc.generate_havoc_data); here the mission is already chosen, so the
-- constraint has to run the other way. A theme whose list does not name this
-- mission has no theme packages for its level, so tagging the mission with it
-- asks the loader for assets that do not exist.
local function _themes_for_mission(mission_name)
	local out = {}

	for _, theme in ipairs(HavocSettings.themes) do
		local missions = HavocSettings.missions[theme]

		if missions then
			for i = 1, #missions do
				if missions[i] == mission_name then
					out[#out + 1] = theme

					break
				end
			end
		end
	end

	return out
end

-- Builds the havoc_data string the mechanism expects. Format is positional and
-- comes from Havoc.parse_data:
--   mission;rank;theme;faction;circumstances;modifiers;challenge;resistance
-- with circumstances and modifiers colon-separated.
difficulty.build_havoc_data = function (rank, mission_name)
	local challenge, resistance = _havoc_challenge_resistance(rank)
	local faction = HavocSettings.factions[math.random(#HavocSettings.factions)]
	local circumstances = _roll_distinct(HavocSettings.circumstances, NUM_ROLLED_CIRCUMSTANCES)

	local tier = rank >= FADING_LIGHT_TIER_2_RANK and 2 or 1

	-- The theme circumstance (darkness, ventilation purge, toxic gas) is
	-- rolled rather than guaranteed, so not every Havoc mission carries an
	-- environmental modifier on top of its modifiers. Its harsher second
	-- variant comes in at the same rank the Fading Light escalates.
	--
	-- The theme *field* is rolled along with it, and has to be, because it is
	-- not cosmetic: HostThemeState.init and LevelLoader.start_loading both
	-- read parsed_data.theme and hand it to
	-- ThemePackage.level_resource_dependency_packages as the level's theme
	-- tag. A mission tagged "darkness" therefore loads with the lights out
	-- whether or not the darkness circumstance came with it.
	--
	-- That was this function's bug, and it is exactly the "environmental
	-- modifier I never picked" symptom: with the chance at 0 the circumstance
	-- was skipped -- so nothing showed on the card and no mutator was loaded
	-- for it -- while a rolled theme still went out and the level was pitch
	-- black anyway. "default" is what the game writes when a Havoc mission
	-- has no environment, so that is what a skipped roll writes now.
	local theme_chance = mod:get("havoc_theme_chance") or 100
	local roll = math.random(1, 100)
	local wants_theme = theme_chance >= 100 or theme_chance > 0 and roll <= theme_chance
	local theme = "default"
	local theme_circumstance, theme_reason

	if not wants_theme then
		theme_reason = string.format("none, roll failed (chance %d%%%%, rolled %d)", theme_chance, roll)
	else
		local candidates = _themes_for_mission(mission_name)

		if #candidates > 0 then
			theme = candidates[math.random(#candidates)]

			local per_theme = HavocSettings.circumstances_per_theme[theme]

			theme_circumstance = per_theme and (per_theme[tier] or per_theme[1])
		end

		if theme_circumstance then
			circumstances[#circumstances + 1] = theme_circumstance
			theme_reason = string.format("%s via %s (chance %d%%%%, rolled %d)",
				theme, theme_circumstance, theme_chance, roll)
		else
			-- Rolled yes, but this mission supports no theme -- or the theme
			-- it supports has no circumstance. Either way the theme tag goes
			-- back to default rather than shipping on its own.
			theme = "default"
			theme_reason = string.format("none, no theme fits this mission (chance %d%%%%, rolled %d)",
				theme_chance, roll)
		end
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

	-- info, not debug_log: this is the line that answers "why did I get an
	-- environmental modifier I did not ask for", and asking a player to turn
	-- Diagnostics on and only then reproduce it costs a round trip. Three
	-- lines per picker roll is not enough traffic to be worth that, and info
	-- goes to the log file rather than chat.
	mod:info("havoc roll: %s at rank %d | theme field: %s | environment: %s | faction %s | %d modifiers | circumstances: %s",
		tostring(mission_name), rank, theme, theme_reason, tostring(faction), modifier_count,
		table.concat(circumstances, ", "))

	return data, challenge, resistance, circumstances
end

-- Player-facing names for a list of circumstance ids, so the picker can show
-- what a Havoc mission actually rolled rather than just its rank. Havoc
-- circumstance templates are folded into the global CircumstanceTemplates and
-- each carries a ui.display_name loc key; anything without one falls back to
-- its raw id, which is still more use than showing nothing.
-- Shared by the name and description lookups, which differ only in which ui
-- field they read and what they do with a missing one.
--
-- Fading Light is on every Havoc mission at a rank-determined tier, so listing
-- it on all three cards tells you nothing about which to pick.
local function _circumstance_ui_strings(circumstances, field, fallback_to_id)
	if not circumstances or #circumstances == 0 then
		return nil
	end

	local skip = {
		[FADING_LIGHT[1]] = true,
		[FADING_LIGHT[2]] = true,
	}

	local out = {}

	for _, id in ipairs(circumstances) do
		if not skip[id] then
			local template = CircumstanceTemplates[id]
			local loc_key = template and template.ui and template.ui[field]
			local text = fallback_to_id and id or nil

			if loc_key then
				local ok, localized = pcall(Localize, loc_key)

				-- Localize hands back "<loc_key>" for a miss rather than failing,
				-- so the marker has to be tested for explicitly.
				if ok and localized and localized ~= "" and not string.starts_with(localized, "<") then
					text = localized
				end
			end

			if text then
				out[#out + 1] = text
			end
		end
	end

	if #out == 0 then
		return nil
	end

	return out
end

-- What each modifier actually does, one per line.
--
-- Separate from the names rather than appended to them so the card can style
-- the two differently -- these run to a couple of hundred characters and would
-- swamp the names at the same size and colour.
--
-- Unlike the names there is no fallback to the raw id: a circumstance with no
-- description simply contributes nothing, because "high_flash_mission_07" as a
-- description line is worse than an absent one.
difficulty.describe_circumstance_details = function (circumstances)
	local details = _circumstance_ui_strings(circumstances, "description", false)

	return details and table.concat(details, "\n") or nil
end

difficulty.describe_circumstances = function (circumstances)
	local names = _circumstance_ui_strings(circumstances, "display_name", true)

	return names and table.concat(names, ", ") or nil
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
-- ---------------------------------------------------------------------------
-- What the mission you are actually standing in has applied
-- ---------------------------------------------------------------------------

-- The other half of the picture from build_havoc_data, read live.
--
-- The card describes what the mod *asked* for; this describes what the game
-- *did* with it, which is not the same thing and is where an unexplained
-- environmental modifier has to show up. Three independent sources, because
-- each can disagree with the others and the disagreement is the finding:
--
--   * the parsed havoc_data, which is the request as the game received it
--   * the theme tag, which loads the level's environment packages (darkness,
--     ventilation purge, toxic gas) independently of any circumstance
--   * the loaded mutators, which are what the circumstances actually became
--
-- Everything is pcall-guarded and every manager tested for: this runs during
-- mission init, and a missing manager must produce a short report rather than
-- take the mission down.
local function _safe(fn, ...)
	local ok, value = pcall(fn, ...)

	return ok and value or nil
end

-- The environment packages a theme tag pulls in for a level.
--
-- Required lazily rather than at file scope: this module is loaded during
-- boot, and a require that throws there is unrecoverable for the rest of the
-- session (Lua leaves a sentinel in package.loaded).
local function _theme_packages(level_name, theme_tag)
	if not level_name or not theme_tag then
		return nil
	end

	local ok, ThemePackage = pcall(require, "scripts/foundation/managers/package/utilities/theme_package")

	if not ok or not ThemePackage or not ThemePackage.level_resource_dependency_packages then
		return nil
	end

	local ok_pkgs, packages = pcall(ThemePackage.level_resource_dependency_packages, level_name, theme_tag)

	if not ok_pkgs or type(packages) ~= "table" then
		return nil
	end

	local names = {}

	for _, name in pairs(packages) do
		names[#names + 1] = tostring(name)
	end

	table.sort(names)

	return names
end

difficulty.describe_active_mission = function ()
	local lines = {}
	local state = Managers.state

	if not state then
		return { "no gameplay state - not in a mission" }
	end

	local mission_manager = state.mission
	local mission_name = mission_manager and _safe(mission_manager.mission_name, mission_manager)
	local level_name = mission_name and MissionTemplates[mission_name] and MissionTemplates[mission_name].level

	lines[#lines + 1] = string.format("mission: %s (level %s)",
		tostring(mission_name), tostring(level_name))

	local difficulty_manager = state.difficulty
	local havoc = difficulty_manager and difficulty_manager.get_parsed_havoc_data
		and _safe(difficulty_manager.get_parsed_havoc_data, difficulty_manager)

	if difficulty_manager then
		lines[#lines + 1] = string.format("difficulty: challenge %s / resistance %s (initial %s / %s)",
			tostring(_safe(difficulty_manager.get_challenge, difficulty_manager)),
			tostring(_safe(difficulty_manager.get_resistance, difficulty_manager)),
			tostring(_safe(difficulty_manager.get_initial_challenge, difficulty_manager)),
			tostring(_safe(difficulty_manager.get_initial_resistance, difficulty_manager)))
	end

	-- The theme tag is the one that can carry an environment nobody asked for,
	-- so it gets its own line whether or not it is "default".
	local theme_tag = havoc and havoc.theme

	if havoc then
		local names = {}

		for _, id in ipairs(havoc.circumstances or {}) do
			names[#names + 1] = tostring(id)
		end

		local modifiers = {}

		for _, entry in ipairs(havoc.modifiers or {}) do
			modifiers[#modifiers + 1] = string.format("%s.%s",
				tostring(entry.name), tostring(entry.level))
		end

		table.sort(modifiers)

		lines[#lines + 1] = string.format("havoc: rank %s, faction %s",
			tostring(havoc.havoc_rank), tostring(havoc.faction))
		lines[#lines + 1] = string.format("havoc circumstances (%d): %s",
			#names, #names > 0 and table.concat(names, ", ") or "none")
		lines[#lines + 1] = string.format("havoc modifiers (%d): %s",
			#modifiers, #modifiers > 0 and table.concat(modifiers, ", ") or "none")
	else
		lines[#lines + 1] = "havoc: not a havoc mission (no havoc_data)"

		local circumstance = state.circumstance
		local circumstance_name = circumstance and _safe(circumstance.circumstance_name, circumstance)
		local template = circumstance and _safe(circumstance.template, circumstance)

		lines[#lines + 1] = string.format("circumstance: %s", tostring(circumstance_name))

		theme_tag = template and template.theme_tag
	end

	local packages = _theme_packages(level_name, theme_tag)

	lines[#lines + 1] = string.format("theme tag: %s%s",
		tostring(theme_tag),
		packages and string.format(" -> %d environment package(s)%s",
			#packages, #packages > 0 and (": " .. table.concat(packages, ", ")) or "")
			or "")

	-- The ground truth. Circumstances are only a request; this is the list of
	-- mutators the game built from them, and anything acting on the mission
	-- that is not in here is not coming from a circumstance at all.
	local mutator_manager = state.mutator
	local mutators = mutator_manager and mutator_manager.all_activated_mutators
		and _safe(mutator_manager.all_activated_mutators, mutator_manager)

	if type(mutators) == "table" then
		local names = {}

		for name in pairs(mutators) do
			names[#names + 1] = tostring(name)
		end

		table.sort(names)

		lines[#lines + 1] = string.format("loaded mutators (%d): %s",
			#names, #names > 0 and table.concat(names, ", ") or "none")
	else
		lines[#lines + 1] = "loaded mutators: mutator manager not available"
	end

	return lines
end

difficulty.log_active_mission = function (context)
	for _, line in ipairs(difficulty.describe_active_mission()) do
		-- The line goes in as an argument, not as the format string, so a '%'
		-- in a package name lands in the output rather than in string.format.
		mod:info("mission entered [%s] %s", tostring(context or "?"), line)
	end
end

return difficulty
