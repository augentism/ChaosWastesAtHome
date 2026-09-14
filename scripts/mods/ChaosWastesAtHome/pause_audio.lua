-- PAUSE2: silence player/bot and enemy firing loops, preserving other audio.
-- Native fixed-update timestamps cannot expire a firing loop while gameplay
-- time is frozen. Stop only those local events and let the firing action
-- request them again naturally when gameplay resumes.
local mod = get_mod("ChaosWastesAtHome")
local shared = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/shared_hooks")
local api = {}
local minions = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/pause_minion_audio")
mod._pause_audio_fx = mod._pause_audio_fx or setmetatable({}, { __mode = "k" })
local tracked = mod._pause_audio_fx
local firing = { ranged_shooting = true, ranged_braced_shooting = true }
local function paused()
	return mod._pause_state and mod._pause_state.paused == true and mod:is_enabled()
end
local function stop(extension)
	for alias in pairs(firing) do
		local data = extension._looping_sounds and extension._looping_sounds[alias]
		if data and data.is_playing then
			-- Native force-stop uses the playing ID; it needs no live source
			-- attachment and emits no multiplayer RPC or weapon stop-tail.
			extension:_trigger_looping_wwise_sound_stop_event(alias, true, false)
		end
		local trigger = extension._looping_sound_trigger_data and extension._looping_sound_trigger_data[alias]
		if trigger then trigger.should_trigger = false end
	end
end
shared.register_safe("PlayerUnitFxExtension", "init", "pause_audio", function(self)
	tracked[self] = true
	if paused() then stop(self) end
end)
shared.register_safe("PlayerUnitFxExtension", "destroy", "pause_audio", function(self)
	tracked[self] = nil
end)
shared.register("PlayerUnitFxExtension", "run_looping_sound", "pause_audio", function(original, self, alias, ...)
	if paused() and firing[alias] then return end
	return original(self, alias, ...)
end)
shared.register("PlayerUnitFxExtension", "_trigger_looping_wwise_sound_start_event", "pause_audio", function(original, self, alias, ...)
	if paused() and firing[alias] then
		local trigger = self._looping_sound_trigger_data and self._looping_sound_trigger_data[alias]
		if trigger then trigger.should_trigger = false end
		return
	end
	return original(self, alias, ...)
end)
function api.begin()
	minions.begin()
	for extension in pairs(tracked) do
		local ok, message = pcall(stop, extension)
		if not ok then
			-- Do not retry a broken/despawned sound source every paused frame.
			tracked[extension] = nil
			mod:error("Pause firing sound stop failed: %s", tostring(message))
		end
	end
end
function api.finish()
	minions.finish()
end
return api
