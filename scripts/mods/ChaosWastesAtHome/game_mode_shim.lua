local mod = get_mod("ChaosWastesAtHome")

-- The mission-buffs system is written against GameModeSurvival: the manager,
-- the UI manager and the handler all reach into the game mode for wave/island
-- bookkeeping. A regular mission has none of that, so we graft the missing
-- members onto the live GameModeCoopCompleteObjective instance.
--
-- The values below are not placeholders -- they are the state Mortis itself
-- runs in before wave 1, and that is exactly where we want to stay:
--
--   * check_if_can_show_choice_notification() early-returns true when the
--     current wave is 0, so notifications are never gated on a between-wave
--     pause that will never happen here.
--   * try_show_new_ui_notification() skips its "outside the pause between
--     waves" rejection while waves_completed is 0, and leaves wave_num nil,
--     so the "WAVE N COMPLETED" banner never renders.
--   * get_time_left_between_waves() looks up an objective_psykhanium_* mission
--     objective that does not exist in a regular mission, returns nil, and the
--     callers fall through to their 30s/20s/5s defaults.

local shim = {}

local STUBS = {
	get_current_wave = function ()
		return 0
	end,
	get_last_wave_completed = function ()
		return 0
	end,
	get_islands_completed = function ()
		return 0
	end,
	is_wave_in_progress = function ()
		return false
	end,
	can_start_wave_one = function ()
		return
	end,
	wait_for_players_to_choose_family = function ()
		return
	end,
}

-- Adds the survival-only API to `game_mode` without clobbering anything the
-- real class already provides (so this stays inert if Fatshark ever moves one
-- of these up into GameModeBase).
shim.install = function (game_mode)
	if not game_mode then
		return nil
	end

	for name, func in pairs(STUBS) do
		if game_mode[name] == nil then
			game_mode[name] = func
		end
	end

	if game_mode._waves_completed == nil then
		game_mode._waves_completed = 0
	end

	mod:debug_log("game mode shim installed")

	return game_mode
end

-- Verifies every member the buff system will call actually exists before we
-- hand the game mode to HordeMissionBuffsManager. Returns a list of whatever
-- is still missing so the caller can bail out instead of crashing mid-mission.
shim.missing_members = function (game_mode)
	local missing = {}

	if not game_mode then
		return { "game_mode" }
	end

	for name in pairs(STUBS) do
		if type(game_mode[name]) ~= "function" then
			missing[#missing + 1] = name
		end
	end

	if game_mode._waves_completed == nil then
		missing[#missing + 1] = "_waves_completed"
	end

	return missing
end

return shim
