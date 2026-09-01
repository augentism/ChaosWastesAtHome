local mod = get_mod("ChaosWastesAtHome")

-- Freezes gameplay while a buff choice is on screen. The card takes long
-- enough to read that a horde can kill you while you are deciding, which turns
-- a reward into a punishment.
--
-- The pause itself is TrueSoloQoL's mechanism: scale the "gameplay" timer to
-- zero. The UI keeps running because StateGame feeds Managers.ui the raw frame
-- dt rather than the gameplay timer, so the card still animates, still counts
-- down, and still accepts clicks while the world is stopped.

local pause = {}

local TIMER = "gameplay"

-- Held on the mod table, not in file locals. DMF re-runs this file on a mod
-- reload but keeps the same mod object, so file locals would be wiped while
-- the gameplay timer stayed at scale 0 -- with `paused` reset to false,
-- nothing would ever restore it and the game would be frozen for good.
mod._pause_state = mod._pause_state or {
	paused = false,
	saved_scale = nil,
	-- Held open by something other than a buff choice -- the collected-buffs
	-- screen. Kept in the same state table so both reasons share one pause and
	-- one restore, rather than two systems fighting over the timer scale.
	hold = false,
}

local state = mod._pause_state

local function _element()
	local ui_manager = Managers.ui

	if not ui_manager or not ui_manager.ui_constant_elements then
		return nil
	end

	local constant_elements = ui_manager:ui_constant_elements()

	return constant_elements and constant_elements:element("ConstantElementMissionBuffs")
end

-- True while a choice card is up and unresolved. `buff_chosen` is set the
-- instant the choice resolves -- by click or by the timeout auto-pick -- so
-- this single predicate covers both ways out without hooking either path, and
-- self-corrects if the card disappears for some reason we did not anticipate.
-- Also gated on should_draw, so the pause does not engage before the card is
-- actually on screen (spawn-in intro, cutscene).
local function _choice_is_up()
	local element = _element()

	if not element then
		return false
	end

	local context = element._context

	if context == nil or context.is_choice ~= true or context.buff_chosen then
		return false
	end

	return element:should_draw()
end

-- Parked on the mod table rather than exported for a caller to io_dofile.
--
-- io_dofile re-executes the file on every call, so another module asking for
-- this file would get a second pause instance -- harmless here only because the
-- state lives on mod._pause_state, and exactly the duplicate-module shape that
-- has already caused one crash in this mod. One instance, reached by name.
mod.choice_is_up = _choice_is_up

local function _is_server()
	local game_session = Managers.state and Managers.state.game_session

	if not game_session then
		return false
	end

	local ok, is_server = pcall(game_session.is_server, game_session)

	return ok and is_server
end

pause.is_paused = function ()
	return state.paused
end

-- Requests a pause for as long as something is open. Applied by pause.update on
-- the next tick like any other reason, so nothing here has to know about timer
-- scales or about restoring them.
pause.set_hold = function (on)
	state.hold = on and true or false
end

pause.is_held = function ()
	return state.hold == true
end

-- Other players are connected, so the clock is not ours to stop.
--
-- Scaling the gameplay timer to zero is a purely local act: it stops the
-- host's simulation while every client keeps running. Realms only synchronises
-- time scale through FlowCallbacks.set_host_gameplay_timescale, which a direct
-- Managers.time:set_local_scale never reaches.
--
-- Measured 2026-08-31 with a real client attached: it does not merely desync,
-- it *disconnects them* -- the host stops feeding the session and the client is
-- dropped within seconds. So this is not a quality setting to weigh, it is a
-- hard incompatibility, and the pause loses.
--
-- mod.has_peers is parked by the main script rather than reached for, so this
-- file does not have to load net.lua and get a second copy of it. Absent (an
-- older main script, a partial reload) reads as "no peers", which restores the
-- previous solo behaviour rather than disabling the pause outright.
local function _peers_connected()
	if not mod.has_peers then
		return false
	end

	local ok, peers = pcall(mod.has_peers)

	return ok and peers or false
end

-- Writing the gameplay timer.
--
-- Purely local, and that is now the only route. Realms does expose a
-- synchronised one -- it hooks FlowCallbacks.set_host_gameplay_timescale and
-- forwards the value to every client -- and this mod shipped an experimental
-- setting that used it. It never worked: that channel was built for
-- level-scripted slow motion, and stopping the clock dead still dropped the
-- session. Two rounds of trying (0.9.0, then 0.9.1's ready-channel fix) did not
-- change that, so the setting is gone rather than left as a trap.
--
-- Protection while choosing is the answer instead -- see choice_shield.lua,
-- which makes the player untargetable and unkillable while their card is up
-- without stopping anything.
local function _set_scale(value)
	local time = Managers.time

	if not time then
		return false
	end

	return pcall(time.set_local_scale, time, TIMER, value)
end

pause.resume = function ()
	if not state.paused then
		return
	end

	state.paused = false

	local time = Managers.time

	if time then
		-- Restore whatever was there rather than forcing 1, so an existing
		-- manual pause (TrueSoloQoL's /pause) survives a card opening over it.
		_set_scale(state.saved_scale or 1)
	end

	state.saved_scale = nil

	mod:debug_log("gameplay resumed")
end


local warned_about_peers = false

pause.update = function (dt)
	-- Everyone reports their own card, in either role. A client cannot pause
	-- anything itself -- it takes the host's synchronised timescale -- but the
	-- host cannot see a remote card, so this is how it learns.
	-- Through the shared definition, not _choice_is_up directly: choice_shield
	-- reads the same one for the local player, and the two drifting apart is
	-- what left the host unprotected on the vote screen.
	--
	-- Falls back to the local card if the main script predates it, which is the
	-- behaviour this file shipped with.
	local mine = mod.local_choosing and mod.local_choosing() or _choice_is_up()

	if mod.report_choosing then
		pcall(mod.report_choosing, mine)
	end

	-- Two reasons, one pause. A buff choice honours the pause_on_choice option;
	-- the hold does not, because the player opened that screen deliberately and
	-- a menu that does not stop the world is a menu that gets you killed.
	--
	-- Only our own card, now that pausing is single-machine again. It used to
	-- wait on everyone's, which only made sense while the pause was synchronised
	-- -- and that wait had a sixty second cap whose expiry printed an error at
	-- players for a feature that no longer exists.
	local choice_pause = mod:get("pause_on_choice") and mine
	local blocked = _peers_connected()

	if blocked and not warned_about_peers and (choice_pause or state.hold) then
		warned_about_peers = true

		mod:echo(mod:localize("pause_disabled_multiplayer"))
		mod:info("pause suppressed: other players are connected and stopping the clock disconnects them")
	end

	local want_pause = mod.manager and _is_server() and not blocked
		and (choice_pause or state.hold)

	if want_pause == state.paused then
		return
	end

	if not want_pause then
		pause.resume()

		return
	end

	local time = Managers.time

	if not time then
		return
	end

	local ok, scale = pcall(time.local_scale, time, TIMER)

	if not ok then
		return
	end

	state.saved_scale = scale

	if not _set_scale(0) then
		state.saved_scale = nil

		return
	end

	state.paused = true

	mod:debug_log("gameplay paused for buff choice")
end

return pause
