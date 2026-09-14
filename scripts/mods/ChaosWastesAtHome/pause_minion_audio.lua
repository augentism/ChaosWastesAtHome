-- Enemy automatic fire lives in EffectTemplatesHandler, not PlayerUnitFxExtension.
-- Suspend only the sound on its existing manual source. Keep the native effect,
-- particles, AI state, source parameters and network ID alive throughout pause.
local mod = get_mod("ChaosWastesAtHome")
local shared = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/shared_hooks")
local api = {}
local firing = {
	chaos_ogryn_gunner_heavy_stubber = true,
	cultist_assault_autogun = true,
	cultist_gunner_stubber = true,
	renegade_assault_lasgun_smg = true,
	renegade_gunner_hellgun = true,
	renegade_captain_hellgun = true,
	renegade_captain_hellgun_spray_and_pray = true,
}
mod._pause_minion_audio = mod._pause_minion_audio or setmetatable({}, { __mode = "k" })
local suspended = mod._pause_minion_audio
local function paused()
	return mod._pause_state and mod._pause_state.paused == true and mod:is_enabled()
end
local function current_system()
	local state = Managers and Managers.state
	local extension = state and state.extension
	return extension and extension:system("fx_system")
end
local function stop(effect, context)
	if suspended[effect] or not effect.is_running then return end
	local template = effect.template
	if not template or not firing[template.name] then return end
	local resources = template.resources or {}
	local start_event = resources.wwise_gun_start or resources.start_shoot_sound_event
	local stop_event = resources.wwise_gun_stop or resources.stop_shoot_sound_event
	local data = effect.template_data
	local source = data and data.source_id
	local world = context and context.wwise_world
	if not source or not world or not start_event or not stop_event then return end
	if not WwiseWorld.has_source(world, source) then return end
	WwiseWorld.trigger_resource_event(world, stop_event, source)
	suspended[effect] = { template = template, source = source, context = context, start_event = start_event }
end
local function stop_safely(effect, context)
	local ok, message = pcall(stop, effect, context)
	if not ok then mod:error("Pause enemy firing sound stop failed: %s", tostring(message)) end
end
shared.register_safe("EffectTemplatesHandler", "start_template_effect", "pause_minion_audio", function(self, lookup, context, effect)
	-- Buffer slots are reusable; an old suspended entry cannot own a new burst.
	suspended[effect] = nil
	if paused() then stop_safely(effect, context) end
end)
shared.register_safe("EffectTemplatesHandler", "stop_template_effect", "pause_minion_audio", function(self, context, effect)
	suspended[effect] = nil
end)
function api.begin()
	local system = current_system()
	if not system then return end
	for _, key in ipairs({ "_effect_templates_handler", "_player_effect_templates_handler", "_local_effect_templates_handler" }) do
		local handler = system[key]
		for _, effect in ipairs(handler and handler._running_template_effects or {}) do
			stop_safely(effect, system._template_context)
		end
	end
end
function api.finish()
	local system = current_system()
	local context = system and system._template_context
	for effect, record in pairs(suspended) do
		suspended[effect] = nil
		local data = effect.template_data
		-- Never restart a dead unit, ended burst, reused slot or previous world.
		if context == record.context and effect.is_running and effect.template == record.template
			and data and data.source_id == record.source and data.unit and ALIVE[data.unit] and HEALTH_ALIVE[data.unit] then
			local ok, message = pcall(function()
				if WwiseWorld.has_source(context.wwise_world, record.source) then
					WwiseWorld.trigger_resource_event(context.wwise_world, record.start_event, record.source)
				end
			end)
			if not ok then mod:error("Pause enemy firing sound resume failed: %s", tostring(message)) end
		end
	end
end
return api
