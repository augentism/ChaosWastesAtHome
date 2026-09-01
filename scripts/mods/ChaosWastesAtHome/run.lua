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
	-- [buff_name] = stack_count, for the local player. A mirror of the entry in
	-- `players` below, kept because the buffs view and the pool exclusion both
	-- read it and neither cares about anybody else.
	buffs = {},
	-- Everyone's carry-over, keyed as the engine keys its own:
	--   [account_id] = { buffs = {[name] = stacks}, family, peer_id, name, restored }
	-- See _player_key for why account_id and not peer_id or unique_id.
	players = {},
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
	return state.active
		and (state.family ~= nil or next(state.buffs) ~= nil or next(state.players) ~= nil)
end

-- How a player is recognised across a mission change.
--
-- account_id, because that is what the engine's own MissionBuffsPersistentData
-- keys on (`players_data[player:account_id()]`) -- so our snapshot and its
-- snapshot agree by construction rather than by a mapping of ours being right.
--
-- Not unique_id, despite that being the right key for a within-session player
-- table: PlayerManager._generate_unique_id appends a monotonically increasing
-- counter, so it changes every time a player is added and is worthless the
-- moment somebody reconnects.
--
-- Not peer_id either, though it is stable and is what /cw_peers reports: bots
-- share the host's peer_id, so it collides the host with its own bots. account_id
-- is nil for a bot, which excludes them exactly as give_buff_to_player's
-- is_human_controlled() gate already does.
--
-- The peer_id fallback is for a shape that should not happen -- a human player
-- with no account id -- and exists so that case degrades to "carried under a
-- worse key" instead of "silently dropped".
local function _player_key(player)
	if not player then
		return nil
	end

	local ok_human, human = pcall(player.is_human_controlled, player)

	if not ok_human or not human then
		return nil
	end

	local ok_account, account_id = pcall(player.account_id, player)

	if ok_account and type(account_id) == "string" and account_id ~= "" then
		return account_id
	end

	local ok_peer, peer_id = pcall(player.peer_id, player)

	if not ok_peer or not peer_id then
		return nil
	end

	local ok_local, local_player_id = pcall(player.local_player_id, player)

	return tostring(peer_id) .. ":" .. tostring(ok_local and local_player_id or 1)
end

-- Cross-reference for the logs: the id /cw_peers prints for the same person.
local function _player_peer_id(player)
	local ok, peer_id = pcall(player.peer_id, player)

	return ok and tostring(peer_id) or "?"
end

local function _player_name(player)
	local ok, name = pcall(player.name, player)

	if ok and type(name) == "string" and name ~= "" then
		return name
	end

	return "?"
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
	state.restore_elapsed = 0

	-- Every record is owed again. Without this the flags from the last mission
	-- would mark everyone as already done and the whole party would arrive with
	-- nothing.
	for _, record in pairs(state.players) do
		record.restored = nil
		record.family_restored = nil
	end
end

-- Put a carried family back at the moment the player spawns, ahead of the
-- engine's own spawn handling.
--
-- HordeMissionBuffsManager._manage_player_spawn creates a family choice when
-- check_player_buff_family_state says the player has none, and that check is
-- `should_have_buff_family_selected and buff_family_chosen == nil`
-- (mission_buffs_persistent_data.lua:57-70). A player rejoining mid-mission
-- meets both halves: the flag was set for everyone when the mission opened its
-- family choice, and their per-player data in this mission is empty. So they are
-- handed a fresh family card on top of a run they are already carrying, and
-- picking from it adds that family's buffs to the ones about to be restored.
--
-- run.restore cannot cover this. It runs from mod.update -- a frame later at the
-- very best, and for a reconnecting client far longer -- by which point the card
-- is already on their screen. The fix has to be ahead of the original call,
-- which is why this is separate from restore rather than part of it.
--
-- Called from two places, because _manage_player_spawn is not the only producer
-- of a family card. create_buff_family_choice_for_all walks human_players() and
-- makes one for anyone without a family (mission_buffs_selector.lua:332-342), so
-- a client who is connected but has not run their spawn handling yet gets caught
-- in that window -- which is exactly what 0.9.6 still did. The second call site
-- is create_buff_family_choice_for_player, which every producer funnels through
-- and is therefore the actual choke point.
--
-- Takes the selector rather than the manager so both call sites can pass what
-- they already have.
--
-- Only the family. The buffs stay with run.restore, which knows how to wait for
-- a player unit; the family is persistent data and needs none.
run.restore_family = function (selector, player)
	-- Deliberately NOT gated on should_restore().
	--
	-- That flag clears once everyone in the snapshot has been restored, or after
	-- RESTORE_WAIT_SECONDS -- so a player whose rejoin ran long would fall
	-- through it and be asked to pick a family after all. The record itself is
	-- the honest condition: we either hold a family for this person and have not
	-- given it back yet, or we do not. It cannot time out, and it cannot strand
	-- someone who joined the run late with nothing carried, because they have no
	-- record and fall straight through.
	if not mod.is_host() then
		return false
	end

	local key = _player_key(player)
	local record = key and state.players[key]

	if not record or not record.family or record.family_restored then
		return false
	end

	if not selector or type(selector.set_buff_family_for_player) ~= "function" then
		return false
	end

	local ok, err = pcall(selector.set_buff_family_for_player, selector, player, record.family, false)

	if not ok then
		mod:error("could not restore family '%s' at spawn: %s", tostring(record.family), tostring(err))

		return false
	end

	record.family_restored = true

	mod:info("restored family '%s' for %s (peer %s) at spawn, before a fresh choice could be offered",
		tostring(record.family), tostring(record.name), tostring(record.peer_id))

	return true
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
	state.players = {}
	state.restore_elapsed = nil
	state.next_mission = nil
	state.pending_launch = nil
	state.restore_pending = nil
	state.params = nil
	state.last_capture_signature = nil
end

-- Snapshot every human player's buffs before the game mode tears the manager
-- down. get_buffs_given_to_player returns [buff_name] = {stacks, buff_indexes};
-- only the name and stack count survive the mission, since buff_indexes refer
-- to a buff extension that is about to be destroyed.
--
-- Everyone, not just the local player: a hop drops the clients and they rejoin
-- into a mission whose buff manager has never heard of them, so whatever they
-- had earned is gone unless the host is holding it. The host is the only machine
-- that sees all of it -- MissionBuffsPersistentData lives server-side.
run.capture = function (quiet)
	local manager = mod.is_host() and mod.manager

	if not manager then
		if not quiet then
			mod:debug_log("capture skipped: no buff manager (mission already torn down?)")
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

	local players = Managers.player and Managers.player:human_players()

	if not players then
		if not quiet then
			mod:debug_log("capture skipped: no player manager")
		end

		return false
	end

	local captured_players = {}
	local total = 0
	local people = 0

	for _, player in pairs(players) do
		local key = _player_key(player)

		if key then
			local ok, buffs = pcall(persistent.get_buffs_given_to_player, persistent, player)
			local record_buffs = {}
			local count = 0

			if ok and buffs then
				for buff_name, buff_data in pairs(buffs) do
					local stacks = buff_data and buff_data.stacks or 1

					record_buffs[buff_name] = stacks
					count = count + stacks
				end
			end

			local family_ok, family = pcall(handler.get_buff_family_selected_by_player, handler, player)

			-- Carried forward rather than replaced when this mission has nothing
			-- to say about them. A client that is still loading, or that
			-- disconnected mid-mission, reads as zero buffs here -- and
			-- overwriting their record with that emptiness is how a hop would
			-- quietly wipe the person it exists to protect.
			local previous = state.players[key]

			if count == 0 and previous and next(previous.buffs) ~= nil then
				record_buffs = previous.buffs
				count = 0

				for _, stacks in pairs(record_buffs) do
					count = count + stacks
				end

				if not family_ok or not family then
					family = previous.family
				end
			end

			captured_players[key] = {
				buffs = record_buffs,
				family = family_ok and family or (previous and previous.family) or nil,
				peer_id = _player_peer_id(player),
				name = _player_name(player),
				restored = previous and previous.restored or nil,
			}

			total = total + count
			people = people + 1
		end
	end

	-- Anyone absent from this mission entirely -- a client that dropped and has
	-- not come back yet -- keeps their record. Losing it here is the same wipe
	-- as above, just at a different moment.
	for key, previous in pairs(state.players) do
		if not captured_players[key] then
			captured_players[key] = previous
		end
	end

	state.players = captured_players

	-- The local player's mirror, for the readers that only care about their own.
	local local_player = Managers.player and Managers.player:local_player_safe(1)
	local local_key = local_player and _player_key(local_player)
	local mine = local_key and captured_players[local_key]

	state.buffs = mine and mine.buffs or {}
	state.family = mine and mine.family or nil

	-- The periodic capture passes quiet=true so it does not spam a line every
	-- second, but staying silent entirely made the live snapshot impossible to
	-- observe. Logging whenever the snapshot actually changes gives one line
	-- per real event -- a buff granted, a family chosen -- which is what you
	-- want to see when checking whether carry-over has anything to carry.
	local signature = string.format("%d/%d/%s", total, people, tostring(state.family))

	if not quiet or signature ~= state.last_capture_signature then
		state.last_capture_signature = signature

		mod:debug_log("captured %d buff stack(s) across %d player(s), own family %s",
			total, people, tostring(state.family))
	end

	return true
end


-- Re-apply the carried family and buffs in the next mission.
--
-- Incremental, and it has to be: this used to run once and be finished, which
-- was true when the only player was the one whose machine it ran on. After a hop
-- the clients are still reconnecting and loading while the host is already
-- playing, so "restore everyone now" would restore the host and write the rest
-- off. Each player is applied when their unit appears and marked done, and the
-- pending flag only clears once nobody is outstanding.
--
-- HOW LONG to keep waiting is the only judgement call. A player who never comes
-- back would otherwise hold the snapshot armed for the whole mission -- harmless
-- in itself, but it also holds `restored_this_mission` false, so this keeps
-- being called. The deadline gives up on absentees and lets the mission get on.
local RESTORE_WAIT_SECONDS = 240

run.restore = function (dt)
	local manager = mod.is_host() and mod.manager

	if not manager or not run.should_restore() then
		return false
	end

	local players = Managers.player and Managers.player:human_players()

	if not players then
		return false
	end

	local selector = manager._mission_buffs_selector
	local restored = 0
	local people = 0

	for _, player in pairs(players) do
		local key = _player_key(player)
		local record = key and state.players[key]

		if record and not record.restored and player.player_unit then
			-- Set the family first. Family buffs are drawn from it, and until it
			-- is set the selector refuses to hand any out -- and the spawn
			-- handler would otherwise offer a fresh family choice mid-run.
			-- Usually already done by restore_family at spawn. Kept for the
			-- path where that did not run -- a player who was present before
			-- the snapshot was armed, so no spawn ever fired for them.
			if record.family and not record.family_restored and selector then
				pcall(selector.set_buff_family_for_player, selector, player, record.family, false)

				record.family_restored = true
			end

			local count = 0

			for buff_name, stacks in pairs(record.buffs) do
				for _ = 1, stacks do
					Managers.event:trigger("mission_buffs_event_add_externally_controlled_to_player",
						player, buff_name)

					count = count + 1
				end
			end

			record.restored = true
			restored = restored + count
			people = people + 1

			mod:info("restored %d buff stack(s) for %s (peer %s), family %s",
				count, tostring(record.name), tostring(record.peer_id), tostring(record.family))
		end
	end

	-- Who is still owed. Absent players count -- that is the whole point of
	-- staying pending -- so this is over the snapshot, not over who is here.
	local outstanding = 0

	for _, record in pairs(state.players) do
		if not record.restored then
			outstanding = outstanding + 1
		end
	end

	if restored > 0 or people > 0 then
		mod:info("restored %d buff stack(s) for %d player(s) in mission %d of the run; %d still to arrive",
			restored, people, state.missions_completed + 1, outstanding)
	end

	if outstanding == 0 then
		-- Consumed: the snapshot now describes this mission's live state, so it
		-- must not be applied again until another transition arms it.
		state.restore_pending = nil
		state.restore_elapsed = nil

		return true
	end

	state.restore_elapsed = (state.restore_elapsed or 0) + (dt or 0)

	if state.restore_elapsed > RESTORE_WAIT_SECONDS then
		state.restore_pending = nil
		state.restore_elapsed = nil

		mod:info("stopped waiting for %d player(s) to rejoin; their buffs stay in the snapshot for the next mission",
			outstanding)

		return true
	end

	return false
end


return run
