local mod = get_mod("ChaosWastesAtHome")

local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")

-- The pieces of a solo session that SoloPlay used to provide for us: keeping the
-- team empty, and making sure the end-of-round view exists.

local solo = {}

-- Not loaded for a singleplay session, and the whole mission chain runs off the
-- end screen -- without this the run has nowhere to continue from. Same package
-- and same reasoning as SoloPlay.on_all_mods_loaded.
local END_VIEW_PACKAGE = "packages/ui/views/end_player_view/end_player_view"
local PACKAGE_REFERENCE = "ChaosWastesAtHome"

solo.load_end_view_package = function ()
	local package_manager = Managers.package

	if not package_manager then
		return false
	end

	local ok, loading = pcall(package_manager.is_loading, package_manager, END_VIEW_PACKAGE)

	if not ok then
		return false
	end

	local has_ok, loaded = pcall(package_manager.has_loaded, package_manager, END_VIEW_PACKAGE)

	if loading or (has_ok and loaded) then
		return false
	end

	-- The trailing `true` keeps it resident rather than tying it to a level.
	local load_ok, err = pcall(package_manager.load, package_manager, END_VIEW_PACKAGE, PACKAGE_REFERENCE, nil, true)

	if not load_ok then
		mod:error("could not preload the end-of-round view: %s", tostring(err))

		return false
	end

	mod:info("preloaded the end-of-round view package")

	return true
end

-- ---------------------------------------------------------------------------
-- Bots
-- ---------------------------------------------------------------------------

-- Solo means suppressing bots, not omitting them.
--
-- coop_complete_objective ships bot_backfilling_allowed = true and max_bots = 3,
-- so the base game fills the team by itself the moment a singleplay session
-- starts. Nothing needs to be added for bots to appear; something has to be done
-- for them not to.
--
-- The suppression goes on the SPAWN call, not on _num_available_bot_slots.
-- Tertium4Or5 hooks that second function and returns `func(...) + 3`, so a hook
-- of ours returning 0 further down the chain would come back out as 3 and we
-- would get bots regardless. Skipping the spawn is order-independent, and when
-- the player opts in we do nothing at all, leaving Tertium4Or5's character
-- selection and its extra slots untouched.
solo.should_suppress_bots = function ()
	if mod:get("use_bots") then
		return false
	end

	-- Only ours. A mission the player started some other way keeps its bots.
	return run.is_launched()
end

return solo
