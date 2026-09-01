local mod = get_mod("ChaosWastesAtHome")

-- Protection while a buff card is on screen.
--
-- Pausing was the original answer and cannot be the answer in multiplayer:
-- stopping the host's clock disconnects everyone else (see pause.lua), so with
-- other players connected the pause is skipped and a player reading three cards
-- is a player standing still in a fight they cannot see.
--
-- So instead of stopping the world, the player is taken out of it: invulnerable,
-- damage immune and unperceivable for exactly as long as their own card is up.
-- The buff template lives in custom_buffs.lua like every other one this mod
-- defines, which is what makes its network id part of the peer handshake.
--
-- Host-only, by necessity rather than preference. The server decides whether an
-- attack lands, so the buff has to exist on the host's copy of the unit; a
-- client applying it to itself would change nothing that matters.

local shield = {}

-- Spelled out rather than read from custom_buffs.CHOICE_SHIELD_BUFF: that file
-- re-executes on every io_dofile and holds registration state, so loading it
-- here would be a second registration. The name is checked by the same peer
-- handshake as every other template, so the two cannot drift apart silently --
-- a mismatch would show up as an unverified peer, not as a quiet no-op.
local BUFF = "cwah_choice_shield"

-- State on the mod table, not in file locals: this file re-executes on every
-- io_dofile and a mod reload rebuilds it, but the buffs it has handed out are on
-- units that outlive both. Losing the handles would leave players permanently
-- invulnerable with nothing holding a reference to undo it.
local state = mod._choice_shield

if not state then
	state = {
		-- [unique_id] = { unit, local_index, component_index }
		handles = {},
	}
	mod._choice_shield = state
end

local function _buff_extension(player_unit)
	if not player_unit or not Unit.alive(player_unit) then
		return nil
	end

	if not ScriptUnit.has_extension(player_unit, "buff_system") then
		return nil
	end

	return ScriptUnit.extension(player_unit, "buff_system")
end

-- Is this player looking at a card right now?
--
-- Two sources, because the host cannot see a remote card. Its own comes from
-- pause.lua, which already computes it; everyone else's arrives over the
-- cwah_choosing RPC that the synchronised pause introduced. Both are parked as
-- facade functions rather than reached for, so this file loads neither pause.lua
-- nor net.lua and cannot end up with a second copy of their state.
local function _is_choosing(player, local_player)
	if player == local_player then
		-- local_choosing, not choice_is_up: the vote screen counts as well as a
		-- buff card, and this is the side that used to miss it.
		if not mod.local_choosing then
			return false
		end

		local ok, up = pcall(mod.local_choosing)

		return ok and up or false
	end

	if not mod.peer_choosing then
		return false
	end

	local ok_peer, peer_id = pcall(player.peer_id, player)

	if not ok_peer or not peer_id then
		return false
	end

	local ok, choosing = pcall(mod.peer_choosing, tostring(peer_id))

	return ok and choosing or false
end

local function _apply(player, unit, key)
	local extension = _buff_extension(unit)

	if not extension then
		return
	end

	local t = Managers.time and Managers.time:time("gameplay")

	if not t then
		return
	end

	local ok, _, local_index, component_index =
		pcall(extension.add_externally_controlled_buff, extension, BUFF, t)

	-- nil indices mean the add did not happen -- the usual cause being that this
	-- machine is not the server. Recording a handle for it would log a
	-- protection that does not exist and make the removal below a silent no-op.
	if not ok or local_index == nil then
		mod:error("could not shield %s while choosing: %s",
			tostring(player:name()), ok and "no buff indices returned" or "add threw")

		return
	end

	state.handles[key] = {
		unit = unit,
		local_index = local_index,
		component_index = component_index,
	}

	mod:debug_log("shielded %s while their card is up", tostring(player:name()))
end

-- Resolved from the handle's own unit, never from the player's current one.
--
-- The indices are only meaningful against the extension that issued them. After
-- a respawn the player has a new unit with a rebuilt extension, and removing
-- these indices there could take off an unrelated buff -- one of their curios or
-- a talent -- or throw.
local function _clear(key)
	local handle = state.handles[key]

	-- Dropped first, so a failure below cannot leave a stale handle that blocks
	-- the player ever being shielded again.
	state.handles[key] = nil

	if not handle then
		return
	end

	local extension = _buff_extension(handle.unit)

	if not extension then
		return
	end

	pcall(extension.remove_externally_controlled_buff, extension,
		handle.local_index, handle.component_index)
end

shield.clear_all = function ()
	for key in pairs(state.handles) do
		_clear(key)
	end
end

shield.update = function (dt)
	-- Not has_authority(): this must also unwind cleanly on the frame the game
	-- session goes away, and has_authority is false by then.
	if not mod.is_host() or not mod.manager then
		shield.clear_all()

		return
	end

	if not mod:get("protect_while_choosing") then
		shield.clear_all()

		return
	end

	local player_manager = Managers.player
	local players = player_manager and player_manager:human_players()

	if not players then
		return
	end

	local local_player = player_manager:local_player_safe(1)
	local live = {}

	for _, player in pairs(players) do
		-- unique_id, not account_id: this is within-session bookkeeping that
		-- never has to survive a mission change, which is the one thing
		-- unique_id cannot do (see run.lua's _player_key).
		local ok_id, key = pcall(player.unique_id, player)
		local unit = player.player_unit

		if ok_id and key and unit then
			live[key] = true

			local handle = state.handles[key]
			local want = _is_choosing(player, local_player)

			if want and not handle then
				_apply(player, unit, key)
			elseif want and handle.unit ~= unit then
				-- Respawned mid-card. The old indices belong to a dead
				-- extension, so drop them and shield the new unit.
				_clear(key)
				_apply(player, unit, key)
			elseif not want and handle then
				_clear(key)

				mod:debug_log("unshielded %s; their card is gone", tostring(player:name()))
			end
		end
	end

	-- Anyone who left while shielded. Their unit is gone, so the removal is a
	-- no-op, but the handle would otherwise sit here forever and stop them being
	-- shielded again if they came back.
	for key in pairs(state.handles) do
		if not live[key] then
			_clear(key)
		end
	end
end

return shield
