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

pause.resume = function ()
	if not state.paused then
		return
	end

	state.paused = false

	local time = Managers.time

	if time then
		-- Restore whatever was there rather than forcing 1, so an existing
		-- manual pause (TrueSoloQoL's /pause) survives a card opening over it.
		pcall(time.set_local_scale, time, TIMER, state.saved_scale or 1)
	end

	state.saved_scale = nil

	mod:debug_log("gameplay resumed")
end

pause.update = function ()
	-- Two reasons, one pause. A buff choice honours the pause_on_choice option;
	-- the hold does not, because the player opened that screen deliberately and
	-- a menu that does not stop the world is a menu that gets you killed.
	local choice_pause = mod:get("pause_on_choice") and _choice_is_up()
	local want_pause = mod.manager and _is_server() and (choice_pause or state.hold)

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

	if not pcall(time.set_local_scale, time, TIMER, 0) then
		state.saved_scale = nil

		return
	end

	state.paused = true

	mod:debug_log("gameplay paused for buff choice")
end

return pause
