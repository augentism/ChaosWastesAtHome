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
	state.restore_accum = 0

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

	-- Ask the game, not our own bookkeeping.
	--
	-- set_buff_family_for_player is NOT idempotent: it table.inserts the whole
	-- family into the player's offer pool every time it is called
	-- (mission_buffs_persistent_data.lua:281-300), so calling it twice leaves
	-- two of every family buff in there, and a hundred times leaves a hundred.
	-- A flag alone is too fragile a thing to hang that on -- it was lost once
	-- already -- so the real test is whether the player has a family at all.
	local handler = selector._mission_buffs_handler
	local ok_has, has_family = pcall(handler.does_player_have_family_selected, handler, player)

	if ok_has and has_family then
		record.family_restored = true

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
	state.restore_accum = nil
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

			-- Merged with what we already held, never replaced.
			--
			-- This mission's persistent data only knows what this mission gave
			-- out, so for anyone who was absent when the buffs were handed back
			-- it reads short -- or empty. Replacing on that reading is a wipe:
			-- an earlier version only guarded the empty case, which meant a
			-- rejoined player who then earned a single new buff had their whole
			-- carried set overwritten by that one buff.
			--
			-- Highest count wins per buff, because within a run buffs only ever
			-- accumulate. A lower reading is missing information, not a removal.
			local previous = state.players[key]

			if previous then
				for buff_name, stacks in pairs(previous.buffs) do
					if (record_buffs[buff_name] or 0) < stacks then
						record_buffs[buff_name] = stacks
					end
				end

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
				-- Carried like `restored`, and for a much sharper reason:
				-- dropping it made the reconciliation re-apply the family every
				-- second, and the engine APPENDS a family's buffs to the offer
				-- pool rather than replacing them. A mission's worth of that
				-- buries the pool in duplicates of what you already hold.
				family_restored = previous and previous.family_restored or nil,
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


-- Take carried buffs out of the pools they would otherwise be offered from
-- again.
--
-- The pools are rebuilt per mission and *popped* as buffs are handed out:
-- init_legendary_buffs_pool_for_player fills the legendary one at spawn,
-- set_buff_family_for_player fills the two family ones, and each offer removes
-- what it took. Restoring goes through give_buff_to_player, which records the
-- buff in buffs_received but pops nothing -- so every carried buff was still
-- sitting in the pool and could be offered a second time. Picking it does not
-- stack, so it is simply a dead choice.
--
-- Mutated in place through the public getters, which hand back the live tables.
--
-- Consequence worth knowing: the pools now deplete across a whole run rather
-- than resetting every mission, which is the same shape as one long mission and
-- is what carrying buffs forward is supposed to mean. triggers.grant_family
-- already checks for an exhausted family pool and skips, so running dry late in
-- a long run is handled rather than fatal.
local function _drop_from_pool(pool, taken)
	if type(pool) ~= "table" then
		return 0
	end

	local removed = 0

	for i = #pool, 1, -1 do
		if taken[pool[i]] then
			table.remove(pool, i)
			removed = removed + 1
		end
	end

	return removed
end

-- Idempotent, and called from two places for that reason: removing a name that
-- is no longer there costs nothing, and the alternative is depending on whether
-- the spawn hook's deferred pool init happened to land before run.restore.
run.trim_pools = function (manager, player)
	if not mod.is_host() then
		return 0
	end

	local key = _player_key(player)
	local record = key and state.players[key]

	if not record or next(record.buffs) == nil then
		return 0
	end

	local handler = manager and manager._mission_buffs_handler
	local persistent = handler and handler._persistent_data

	if not persistent then
		return 0
	end

	local taken = record.buffs
	local removed = 0

	local ok_priority, priority = pcall(persistent.get_player_priority_family_buffs_available, persistent, player)

	if ok_priority then
		removed = removed + _drop_from_pool(priority, taken)
	end

	local ok_family, family = pcall(persistent.get_player_family_buffs_available, persistent, player)

	if ok_family then
		removed = removed + _drop_from_pool(family, taken)
	end

	-- Legendary is a map of filter category -> array, not one flat list.
	local ok_legendary, legendary = pcall(persistent.get_legendary_buffs_available_for_player, persistent, player)

	if ok_legendary and type(legendary) == "table" then
		for _, category_pool in pairs(legendary) do
			removed = removed + _drop_from_pool(category_pool, taken)
		end
	end

	if removed > 0 then
		mod:info("took %d already-carried buff(s) out of %s's offer pools",
			removed, tostring(record.name))
	end

	return removed
end

-- Keep everyone holding what the run says they hold.
--
-- Written as a continuous reconciliation rather than a restore step, through
-- two rounds of getting it wrong:
--
--  1. Once per mission was only ever right when the single player was the one
--     whose machine it ran on. After a hop the clients are still reconnecting
--     while the host is already playing, so "restore everyone now" restores the
--     host and writes the rest off.
--  2. Once per player, marked done with a flag, was still wrong. A player who
--     drops and rejoins mid-mission is already marked done, so they come back
--     with nothing -- and worse, the next capture reads their near-empty data
--     and merges it, which used to overwrite their whole carried set.
--
-- So there is no "done". Every pass compares what each player holds against
-- what the run says they should and hands over the difference, which is a no-op
-- for anyone already whole. That makes it safe to run forever, and it covers
-- the initial hand-back, a rejoin, and a reconnect that lands mid-mission with
-- one mechanism instead of three.
--
-- The difference, rather than re-applying outright: the snapshot counts stacks,
-- so blindly re-adding would double any buff that does stack.
--
-- The deadline below is only about the *pending* flag -- how long a mission
-- waits before it stops considering itself mid-restore. Buffs are handed over
-- whenever their owner turns up, deadline or not.
local RESTORE_WAIT_SECONDS = 240

-- How often the party is checked against the snapshot. Not per frame: this
-- reads every player's buff data, which is what a capture costs.
local RECONCILE_SECONDS = 1

run.restore = function (dt)
	local manager = mod.is_host() and mod.manager

	if not manager or not state.active or next(state.players) == nil then
		return false
	end

	local players = Managers.player and Managers.player:human_players()

	if not players then
		return false
	end

	-- Throttled rather than run every frame: reconciling reads each player's
	-- buff data, which is the same cost as a capture, and nothing here needs to
	-- react faster than a person can notice.
	state.restore_accum = (state.restore_accum or 0) + (dt or 0)

	if state.restore_accum < RECONCILE_SECONDS then
		return not state.restore_pending
	end

	state.restore_accum = 0

	local handler = manager._mission_buffs_handler
	local persistent = handler and handler._persistent_data
	local selector = manager._mission_buffs_selector

	if not persistent then
		return false
	end

	local restored = 0
	local people = 0

	for _, player in pairs(players) do
		local key = _player_key(player)
		local record = key and state.players[key]

		if record and player.player_unit then
			-- What they are short by, not "have they been done once".
			--
			-- A flag was wrong in both directions: it left a player who rejoined
			-- mid-mission with nothing, because they had already been marked
			-- done; and re-applying blindly instead would double any buff that
			-- does stack, since the snapshot counts stacks. The difference
			-- against what they actually hold right now is exact, and is a no-op
			-- for anyone already whole -- so this can run as often as it likes.
			local held = {}
			local ok, current = pcall(persistent.get_buffs_given_to_player, persistent, player)

			if ok and current then
				for buff_name, buff_data in pairs(current) do
					held[buff_name] = buff_data and buff_data.stacks or 1
				end
			end

			-- Family first. Family buffs are drawn from it, and until it is set
			-- the selector refuses to hand any out.
			if record.family and not record.family_restored and selector then
				run.restore_family(selector, player)
			end

			local count = 0

			for buff_name, stacks in pairs(record.buffs) do
				local missing = stacks - (held[buff_name] or 0)

				for _ = 1, missing do
					Managers.event:trigger("mission_buffs_event_add_externally_controlled_to_player",
						player, buff_name)

					count = count + 1
				end
			end

			if count > 0 then
				run.trim_pools(manager, player)

				restored = restored + count
				people = people + 1

				mod:info("gave %s (peer %s) %d buff stack(s) they were short, family %s",
					tostring(record.name), tostring(record.peer_id), count, tostring(record.family))
			end

			record.restored = true
		end
	end

	if not state.restore_pending then
		return true
	end

	-- Who is still owed. Absent players count -- that is the whole point of
	-- staying pending -- so this is over the snapshot, not over who is here.
	local outstanding = 0

	for _, record in pairs(state.players) do
		if not record.restored then
			outstanding = outstanding + 1
		end
	end

	if restored > 0 then
		mod:info("restored %d buff stack(s) for %d player(s) in mission %d of the run; %d still to arrive",
			restored, people, state.missions_completed + 1, outstanding)
	end

	if outstanding == 0 then
		state.restore_pending = nil
		state.restore_elapsed = nil

		return true
	end

	state.restore_elapsed = (state.restore_elapsed or 0) + RECONCILE_SECONDS

	if state.restore_elapsed > RESTORE_WAIT_SECONDS then
		state.restore_pending = nil
		state.restore_elapsed = nil

		mod:info("stopped waiting for %d player(s) to arrive; they are still in the snapshot and will be topped up whenever they turn up",
			outstanding)

		return true
	end

	return false
end

return run
