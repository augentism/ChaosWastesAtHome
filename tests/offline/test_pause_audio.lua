local h = ...
return {
	{ "pause silences firing loops and resumes only still-live enemy effects", function (a)
		local hooks, sounds = {}, {}
		local shared = { register = function (obj, name, _, fn) hooks[obj .. "." .. name] = fn end }
		shared.register_safe = shared.register
		local unit, world = {}, {}
		local template = { name = "cultist_assault_autogun", resources = { wwise_gun_start = "start", wwise_gun_stop = "stop" } }
		local effect = { is_running = true, template = template, template_data = { unit = unit, source_id = 1 } }
		local context = { wwise_world = world }
		local system = { _template_context = context, _effect_templates_handler = { _running_template_effects = { effect } } }
		local mod = { _pause_state = { paused = false }, is_enabled = function () return true end, error = function () end }
		local env = setmetatable({ get_mod = function () return mod end, ALIVE = { [unit] = true }, HEALTH_ALIVE = { [unit] = true },
			Managers = { state = { extension = { system = function () return system end } } },
			WwiseWorld = { has_source = function () return true end, trigger_resource_event = function (_, sound) sounds[#sounds+1] = sound end } }, { __index = _G })
		function mod:io_dofile(path)
			if path:find("shared_hooks", 1, true) then return shared end
			return setfenv(assert(loadfile(h.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/" .. path:match("([^/]+)$") .. ".lua")), env)()
		end
		local audio = mod:io_dofile("pause_audio")
		local stopped = 0
		local fx = { _looping_sounds = { ranged_shooting = { is_playing = true } },
			_looping_sound_trigger_data = { ranged_shooting = { should_trigger = true } },
			_trigger_looping_wwise_sound_stop_event = function () stopped = stopped + 1 end }
		hooks["PlayerUnitFxExtension.init"](fx)
		mod._pause_state.paused = true; audio.begin()
		a.eq(stopped, 1); a.falsy(fx._looping_sound_trigger_data.ranged_shooting.should_trigger)
		a.eq(sounds[1], "stop")
		local forwarded = 0
		hooks["PlayerUnitFxExtension.run_looping_sound"](function () forwarded = forwarded + 1 end, fx, "ranged_shooting")
		hooks["PlayerUnitFxExtension.run_looping_sound"](function () forwarded = forwarded + 1 end, fx, "other_audio")
		a.eq(forwarded, 1)
		mod._pause_state.paused = false; audio.finish(); a.eq(sounds[2], "start")
		mod._pause_state.paused = true; audio.begin(); env.HEALTH_ALIVE[unit] = nil
		mod._pause_state.paused = false; audio.finish(); a.eq(#sounds, 3, "dead enemy not restarted")
		env.HEALTH_ALIVE[unit] = true; audio.begin(); system._template_context = {}
		audio.finish(); a.eq(#sounds, 4, "old world not restarted")
	end },
}
