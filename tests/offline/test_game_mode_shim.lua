-- game_mode_shim grafts the survival-only API the mission-buffs system calls
-- onto a regular mission's game mode. `missing_members` is the guard that runs
-- before we hand the game mode over, so a missing member becomes a clean bail
-- instead of a crash mid-mission.
--
-- This is the canary for Fatshark moving one of those members: if the shim's
-- own contract stops holding, everything downstream fails somewhere less
-- obvious.

local harness = ...

local function complete_game_mode()
	return {
		get_current_wave = function () return 0 end,
		get_last_wave_completed = function () return 0 end,
		get_islands_completed = function () return 0 end,
		is_wave_in_progress = function () return false end,
		can_start_wave_one = function () end,
		wait_for_players_to_choose_family = function () end,
		_waves_completed = 0,
	}
end

local STUB_NAMES = {
	"get_current_wave",
	"get_last_wave_completed",
	"get_islands_completed",
	"is_wave_in_progress",
	"can_start_wave_one",
	"wait_for_players_to_choose_family",
}

return {
	{ "nil game mode reports exactly 'game_mode'", function (a)
		local shim = harness.load("game_mode_shim")
		local missing = shim.missing_members(nil)

		a.count(missing, 1, "missing")
		a.eq(missing[1], "game_mode", "missing[1]")
	end },

	{ "a complete game mode reports nothing missing", function (a)
		local shim = harness.load("game_mode_shim")

		a.count(shim.missing_members(complete_game_mode()), 0, "missing")
	end },

	{ "each absent member is named individually", function (a)
		local shim = harness.load("game_mode_shim")

		for _, name in ipairs(STUB_NAMES) do
			local gm = complete_game_mode()
			gm[name] = nil

			local missing = shim.missing_members(gm)

			a.count(missing, 1, "missing after dropping " .. name)
			a.eq(missing[1], name, "missing[1] after dropping " .. name)
		end
	end },

	{ "_waves_completed is checked as a field, not a function", function (a)
		local shim = harness.load("game_mode_shim")
		local gm = complete_game_mode()
		gm._waves_completed = nil

		a.contains(shim.missing_members(gm), "_waves_completed", "missing")
	end },

	{ "_waves_completed = 0 counts as present", function (a)
		-- Guarding on falsiness rather than nil would call 0 missing, and 0 is
		-- the value the shim itself installs.
		local shim = harness.load("game_mode_shim")
		local gm = complete_game_mode()
		gm._waves_completed = 0

		a.not_contains(shim.missing_members(gm), "_waves_completed", "missing")
	end },

	{ "install fills a bare game mode until nothing is missing", function (a)
		local shim = harness.load("game_mode_shim")
		local gm = shim.install({})

		a.truthy(gm, "install returned a game mode")
		a.count(shim.missing_members(gm), 0, "missing after install")
	end },

	{ "install returns nil for a nil game mode", function (a)
		local shim = harness.load("game_mode_shim")

		a.nil_(shim.install(nil), "install(nil)")
	end },

	{ "install does not clobber members the real class provides", function (a)
		-- The whole point of the nil check in install(): if Fatshark ever moves
		-- one of these up into GameModeBase, ours must stay out of the way.
		local shim = harness.load("game_mode_shim")
		local sentinel = function () return "real" end
		local gm = shim.install({ get_current_wave = sentinel })

		a.eq(gm.get_current_wave, sentinel, "get_current_wave")
		a.eq(gm.get_current_wave(), "real", "get_current_wave()")
	end },

	{ "install leaves a non-zero _waves_completed alone", function (a)
		local shim = harness.load("game_mode_shim")
		local gm = shim.install({ _waves_completed = 4 })

		a.eq(gm._waves_completed, 4, "_waves_completed")
	end },

	{ "the stubs report the pre-wave-1 state Mortis runs in", function (a)
		-- These values are load-bearing, not placeholders: wave 0 is what makes
		-- the notification gates and the "WAVE N COMPLETED" banner behave.
		local shim = harness.load("game_mode_shim")
		local gm = shim.install({})

		a.eq(gm.get_current_wave(), 0, "get_current_wave")
		a.eq(gm.get_last_wave_completed(), 0, "get_last_wave_completed")
		a.eq(gm.get_islands_completed(), 0, "get_islands_completed")
		a.eq(gm.is_wave_in_progress(), false, "is_wave_in_progress")
		a.eq(gm._waves_completed, 0, "_waves_completed")
	end },
}
