local mod = get_mod("ChaosWastesAtHome")

-- Run state for the mission chain: which buffs you are carrying, how deep you
-- are, and which mission you picked next.
--
-- Lives on the mod table rather than in file locals so a mod reload does not
-- silently wipe a run in progress -- the same reasoning as pause.lua.

local run = {}

mod._run = mod._run or {
	-- Set the moment the launcher commits, and the thing that makes a run
	-- opt-in. `active` cannot serve this purpose: it is set as a consequence of
	-- the buff system starting, so gating activation on it would be circular.
	-- This is set BEFORE the mission loads and survives the level change with
	-- the rest of the run state.
	launched = false,
	active = false,
	missions_completed = 0,
	family = nil,
	-- [buff_name] = stack_count
	buffs = {},
	-- mission context table chosen on the end screen, consumed at launch
	next_mission = nil,
	-- the difficulty/circumstance the run was started at, so every mission in
	-- the chain matches the first one
	params = nil,
}

local state = mod._run

run.state = function ()
	return state
end

run.is_active = function ()
	return state.active == true
end

-- Whether the player deliberately started a run. Checked by the activation gate,
-- so a mission the player launched any other way is left alone.
run.is_launched = function ()
	return state.launched == true
end

run.mark_launched = function ()
	state.launched = true
end

run.depth = function ()
	return state.missions_completed
end

run.has_carryover = function ()
	return state.active and (state.family ~= nil or next(state.buffs) ~= nil)
end

-- Whether the carried buffs belong to an *earlier* mission and still need
-- applying here.
--
-- Distinct from has_carryover on purpose. The live snapshot means the mission
-- that generates the buffs also holds them, so "we have carry-over data" went
-- true the instant you picked a family -- and restore fired into the very
-- mission that produced it, duplicating every buff and compounding the count
-- on each hop. Only a queued mission transition sets restore_pending, so the
-- data can only ever be applied in a mission that did not create it.
run.should_restore = function ()
	return state.active and state.restore_pending == true and run.has_carryover()
end

-- Marks the snapshot as belonging to the mission we are about to launch.
run.arm_restore = function ()
	state.restore_pending = true
end

run.reset = function (reason)
	if state.active or state.next_mission then
		mod:info("run ended (%s) after %d mission(s)", tostring(reason), state.missions_completed)
	end

	state.launched = false
	state.active = false
	state.missions_completed = 0
	state.family = nil
	state.buffs = {}
	state.next_mission = nil
	state.pending_launch = nil
	state.restore_pending = nil
	state.params = nil
	state.last_capture_signature = nil
end

-- Snapshot the local player's buffs before the game mode tears the manager
-- down. get_buffs_given_to_player returns [buff_name] = {stacks, buff_indexes};
-- only the name and stack count survive the mission, since buff_indexes refer
-- to a buff extension that is about to be destroyed.
run.capture = function (quiet)
	local manager = mod.manager

	if not manager then
		if not quiet then
			mod:debug_log("capture skipped: no buff manager (mission already torn down?)")
		end

		return false
	end

	local player = Managers.player and Managers.player:local_player_safe(1)

	if not player then
		if not quiet then
			mod:debug_log("capture skipped: no local player")
		end

		return false
	end

	local handler = manager._mission_buffs_handler
	local persistent = handler and handler._persistent_data

	if not persistent then
		if not quiet then
			mod:debug_log("capture skipped: no persistent buff data")
		end

		return false
	end

	local ok, buffs = pcall(persistent.get_buffs_given_to_player, persistent, player)

	if not ok or not buffs then
		if not quiet then
			mod:debug_log("capture skipped: could not read buffs -", tostring(buffs))
		end

		return false
	end

	local captured = {}
	local count = 0

	for buff_name, buff_data in pairs(buffs) do
		local stacks = buff_data and buff_data.stacks or 1

		captured[buff_name] = stacks
		count = count + stacks
	end

	state.buffs = captured

	local family_ok, family = pcall(handler.get_buff_family_selected_by_player, handler, player)

	state.family = family_ok and family or nil

	-- The periodic capture passes quiet=true so it does not spam a line every
	-- second, but staying silent entirely made the live snapshot impossible to
	-- observe. Logging whenever the snapshot actually changes gives one line
	-- per real event -- a buff granted, a family chosen -- which is what you
	-- want to see when checking whether carry-over has anything to carry.
	local signature = tostring(count) .. "/" .. tostring(state.family)

	if not quiet or signature ~= state.last_capture_signature then
		state.last_capture_signature = signature

		mod:debug_log("captured %d buff stack(s), family %s", count, tostring(state.family))
	end

	return true
end

-- Re-apply the carried family and buffs in the next mission. Called once the
-- player has spawned and the manager for the new mission exists.
run.restore = function ()
	local manager = mod.manager

	if not manager or not run.should_restore() then
		return false
	end

	local player = Managers.player and Managers.player:local_player_safe(1)

	if not player or not player.player_unit then
		return false
	end

	local selector = manager._mission_buffs_selector

	-- Set the family first. Family buffs are drawn from it, and until it is
	-- set the selector refuses to hand any out -- and the spawn handler would
	-- otherwise offer a fresh family choice mid-run.
	if state.family and selector then
		pcall(selector.set_buff_family_for_player, selector, player, state.family, false)
	end

	local restored = 0

	for buff_name, stacks in pairs(state.buffs) do
		for _ = 1, stacks do
			Managers.event:trigger("mission_buffs_event_add_externally_controlled_to_player", player, buff_name)

			restored = restored + 1
		end
	end

	-- Consumed: the snapshot now describes this mission's live state, so it
	-- must not be applied again until another transition arms it.
	state.restore_pending = nil

	mod:info("restored %d buff stack(s) for mission %d of the run", restored, state.missions_completed + 1)

	return true
end

return run
