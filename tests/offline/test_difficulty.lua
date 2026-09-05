-- The run's difficulty ladder: walk the game's own DangerSettings while there
-- is somewhere to climb, then move into Havoc.
--
-- Worth pinning because the steps are not uniform -- Damnation is 5/4 and Auric
-- is 5/5, so challenge alone does not identify a rung -- and because the Havoc
-- half is arithmetic with a cap and a rounding rule that are easy to get subtly
-- wrong in a way no mission would obviously show.

local harness = ...

local DANGER = "scripts/settings/difficulty/danger_settings"

local function load_difficulty()
	require(DANGER)
	require("scripts/settings/havoc_settings")
	require("scripts/settings/havoc/havoc_modifier_config")
	require("scripts/settings/mission/mission_templates")
	require("scripts/settings/circumstance/circumstance_templates")

	return harness.load("difficulty")
end

-- Hand-rolled rather than gmatch("[^;]*"), which yields an empty match between
-- every pair of separators in Lua 5.1 and doubles the field count. Empty fields
-- are preserved, because a positional format is exactly where one matters.
local function split(s)
	local out, from = {}, 1
	s = tostring(s)

	while true do
		local at = s:find(";", from, true)

		if not at then
			out[#out + 1] = s:sub(from)

			return out
		end

		out[#out + 1] = s:sub(from, at - 1)
		from = at + 1
	end
end

return {
	{ "the real danger settings loaded", function (a)
		a.truthy(harness.engine_loaded(DANGER), "danger_settings loaded")
		a.gt(#require(DANGER), 2, "danger rung count")
	end },

	{ "the ladder starts at Malice and ends at the Havoc cap", function (a)
		-- Sedition and Uprising are below the floor this mod is balanced
		-- around; a run that opens there spends its first legs with nothing to
		-- fight.
		local difficulty = load_difficulty()
		local rungs = difficulty.rungs()

		a.gt(#rungs, 0, "rung count")
		a.eq(rungs[1].challenge, 3, "first rung challenge")
		a.eq(rungs[#rungs].havoc_rank, 40, "last rung havoc rank")

		for _, rung in ipairs(rungs) do
			if rung.challenge then
				a.gt(rung.challenge, 2, "rung challenge above the floor")
			end
		end
	end },

	{ "the ladder is the danger rungs then the havoc ranks, in order", function (a)
		local difficulty = load_difficulty()
		local rungs = difficulty.rungs()
		local seen_havoc = false

		for _, rung in ipairs(rungs) do
			if rung.havoc_rank then
				seen_havoc = true
			else
				-- A danger rung after a havoc rung would mean the ladder goes
				-- backwards partway up.
				a.falsy(seen_havoc, "danger rung appearing after a havoc rung")
			end
		end

		a.truthy(seen_havoc, "ladder reaches havoc")
	end },

	{ "next walks the game's own danger rungs", function (a)
		local difficulty = load_difficulty()
		local danger = require(DANGER)

		for i = 1, #danger - 1 do
			local here = danger[i]
			local want = danger[i + 1]
			local got = difficulty.next({ challenge = here.challenge, resistance = here.resistance })

			a.truthy(got, "next from " .. here.challenge .. "/" .. here.resistance)
			a.eq(got.challenge, want.challenge, "challenge after " .. here.challenge .. "/" .. here.resistance)
			a.eq(got.resistance, want.resistance, "resistance after " .. here.challenge .. "/" .. here.resistance)
		end
	end },

	{ "the top danger rung moves into Havoc", function (a)
		local difficulty = load_difficulty()
		local danger = require(DANGER)
		local top = danger[#danger]

		local got = difficulty.next({ challenge = top.challenge, resistance = top.resistance })

		a.truthy(got, "next from the top rung")
		a.eq(got.havoc_rank, 25, "havoc entry rank")
		a.nil_(got.challenge, "challenge is not carried into a havoc rung")
	end },

	{ "havoc climbs five ranks a mission", function (a)
		local difficulty = load_difficulty()

		a.eq(difficulty.next({ havoc_rank = 25 }).havoc_rank, 30, "25 -> 30")
		a.eq(difficulty.next({ havoc_rank = 30 }).havoc_rank, 35, "30 -> 35")
		a.eq(difficulty.next({ havoc_rank = 35 }).havoc_rank, 40, "35 -> 40")
	end },

	{ "havoc stops at the cap instead of climbing past it", function (a)
		-- A run that gets this far keeps going at 40 rather than walking into
		-- ranks the ramp was never designed for.
		local difficulty = load_difficulty()

		a.eq(difficulty.next({ havoc_rank = 40 }).havoc_rank, 40, "40 -> 40")
		a.eq(difficulty.next({ havoc_rank = 55 }).havoc_rank, 40, "a start above the cap comes back to it")
	end },

	{ "an off-ladder havoc rank rounds up onto the ladder", function (a)
		local difficulty = load_difficulty()

		a.eq(difficulty.next({ havoc_rank = 26 }).havoc_rank, 30, "26 -> 30")
		a.eq(difficulty.next({ havoc_rank = 29 }).havoc_rank, 30, "29 -> 30")
		a.eq(difficulty.next({ havoc_rank = 31 }).havoc_rank, 35, "31 -> 35")
	end },

	{ "an unrecognised low pair still climbs", function (a)
		-- A mod-set combination that is not a real rung has to go somewhere.
		local difficulty = load_difficulty()
		local got = difficulty.next({ challenge = 3, resistance = 1 })

		a.eq(got.challenge, 4, "challenge")
		a.eq(got.resistance, 2, "resistance")
	end },

	{ "an unrecognised pair at Damnation level tops out into Havoc", function (a)
		local difficulty = load_difficulty()
		local got = difficulty.next({ challenge = 5, resistance = 1 })

		a.eq(got.havoc_rank, 25, "havoc entry rank")
	end },

	{ "next of nothing is nothing", function (a)
		local difficulty = load_difficulty()

		a.nil_(difficulty.next(nil), "next(nil)")
	end },

	-- The saved value must not be an index into rungs(): a game patch adding a
	-- difficulty shifts every index after it, and the player would silently
	-- land on a difficulty they never chose.
	{ "every rung round-trips through its key", function (a)
		local difficulty = load_difficulty()
		local rungs = difficulty.rungs()

		for i, rung in ipairs(rungs) do
			local key = difficulty.rung_key(rung)

			a.truthy(key, "key for rung " .. i)
			a.eq(difficulty.rung_index_for_key(key), i, "index for " .. tostring(key))
		end
	end },

	{ "rung keys name the two fields that identify a rung", function (a)
		local difficulty = load_difficulty()

		a.eq(difficulty.rung_key({ challenge = 5, resistance = 4 }), "danger:5:4", "danger key")
		a.eq(difficulty.rung_key({ havoc_rank = 30 }), "havoc:30", "havoc key")
	end },

	{ "an unusable rung or key yields nil rather than a guess", function (a)
		local difficulty = load_difficulty()

		a.nil_(difficulty.rung_key(nil), "rung_key(nil)")
		a.nil_(difficulty.rung_key("danger:5:4"), "rung_key(string)")
		a.nil_(difficulty.rung_key({}), "rung_key({})")
		a.nil_(difficulty.rung_index_for_key(nil), "rung_index_for_key(nil)")
		a.nil_(difficulty.rung_index_for_key(3), "rung_index_for_key(number)")
		a.nil_(difficulty.rung_index_for_key("havoc:999"), "rung_index_for_key of a dropped rank")
	end },

	-- havoc_data is a positional semicolon string that nobody reads correctly
	-- at a glance. Field 3 is the theme, and it is not cosmetic: the loader
	-- hands it to ThemePackage as the level's theme tag, so a mission tagged
	-- "darkness" loads with the lights out whether or not the matching
	-- circumstance came with it. That was a real bug.
	{ "havoc data puts the theme in field three", function (a)
		local difficulty = load_difficulty()

		-- Chance 0 makes the roll deterministic and must write "default",
		-- which is what the game writes for a Havoc mission with no
		-- environment. Anything else here is the lights-out bug returning.
		harness.mod:set("havoc_theme_chance", 0)

		local data, challenge, resistance = difficulty.build_havoc_data(30, "km_enforcer")
		local fields = split(data)

		a.eq(fields[1], "km_enforcer", "field 1 mission name")
		a.eq(fields[2], "30", "field 2 rank")
		a.eq(fields[3], "default", "field 3 theme")
		a.eq(fields[7], tostring(challenge), "field 7 challenge")
		a.eq(fields[8], tostring(resistance), "field 8 resistance")
	end },

	{ "havoc challenge and resistance follow the rank", function (a)
		-- Mirrors SoloPlay's mapping, so a mod-launched Havoc mission is
		-- configured the way SoloPlay would configure it.
		local difficulty = load_difficulty()

		harness.mod:set("havoc_theme_chance", 0)

		local _, c10, r10 = difficulty.build_havoc_data(10, "km_enforcer")
		local _, c20, r20 = difficulty.build_havoc_data(20, "km_enforcer")
		local _, c30, r30 = difficulty.build_havoc_data(30, "km_enforcer")
		local _, c40, r40 = difficulty.build_havoc_data(40, "km_enforcer")

		a.eq(c10 .. "/" .. r10, "3/3", "rank 10")
		a.eq(c20 .. "/" .. r20, "4/4", "rank 20")
		a.eq(c30 .. "/" .. r30, "5/4", "rank 30")
		a.eq(c40 .. "/" .. r40, "5/5", "rank 40")
	end },

	{ "the Fading Light tier steps up at rank 30", function (a)
		-- Always present on a Havoc mission; tier 2 from rank 30.
		local difficulty = load_difficulty()

		harness.mod:set("havoc_theme_chance", 0)

		local _, _, _, low = difficulty.build_havoc_data(25, "km_enforcer")
		local _, _, _, high = difficulty.build_havoc_data(30, "km_enforcer")

		a.contains(low, "mutator_increased_difficulty", "rank 25 circumstances")
		a.contains(high, "mutator_highest_difficulty", "rank 30 circumstances")
	end },
}
