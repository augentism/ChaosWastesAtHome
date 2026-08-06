local mod = get_mod("ChaosWastesAtHome")

-- Stops an unloaded particle effect from crashing the game.
--
-- Several hordes buffs spawn particles from a proc. In Mortis those effects
-- ship with the horde mission content; in a regular mission they are absent
-- and World.create_particles raises "Particle effect not loaded" from inside a
-- fixed update -- fatal, and only when the buff happens to proc, so the crash
-- lands long after the pick that caused it.
--
-- Guarding the call rather than removing the buffs keeps every buff pickable
-- and does the right thing for effects nobody has enumerated: the buff works,
-- it just renders nothing.

local particle_guard = {}

-- Effects already known to be missing. The first failure is caught by pcall;
-- after that the name is skipped outright, so a buff proccing every swing does
-- not pay for a protected call it is guaranteed to fail.
local failed_effects = {}

particle_guard.install = function ()
	local world_api = rawget(_G, "World")

	if not world_api or not world_api.create_particles then
		mod:error("World.create_particles unavailable - cannot guard against unloaded particle effects")

		return false
	end

	mod:hook(world_api, "create_particles", function (func, world, effect_name, ...)
		-- Scoped to our missions. This is a hot, engine-wide function and
		-- every particle in the game passes through it; outside a run there is
		-- nothing to protect against and it should cost nothing.
		if not mod.manager then
			return func(world, effect_name, ...)
		end

		if failed_effects[effect_name] then
			return nil
		end

		local ok, id = pcall(func, world, effect_name, ...)

		if ok then
			return id
		end

		failed_effects[effect_name] = true

		mod:info("particle effect not loaded, rendering nothing: %s", tostring(effect_name))

		return nil
	end)

	-- Returning nil from create_particles means callers now hold a nil id, and
	-- every one of these takes an id as its second argument. Guarding only the
	-- obvious cleanup pair would have relocated the crash rather than removing
	-- it: a caller that creates and then immediately links would die at the
	-- link instead, in a place that points away from the missing asset.
	--
	-- The defaults are what each call would mean for an effect that is not
	-- playing, so callers reading a result get a coherent answer rather than a
	-- nil they were not expecting either.
	local FALSE_ON_NIL = {
		are_particles_playing = true,
		has_particles_material = true,
	}

	-- Every one of these was checked to take the particle id as argument two.
	--
	-- find_particles_variable is deliberately absent: its second argument is an
	-- effect *name*, not an id, so it can never receive our nil. The index it
	-- returns is consumed by set_particles_variable, which is guarded -- so the
	-- chain is covered without hooking a function whose shape does not match.
	local ID_FUNCTIONS = {
		"stop_spawning_particles",
		"destroy_particles",
		"link_particles",
		"move_particles",
		"set_particles_variable",
		"set_particles_material_vector",
		"set_particles_material_scalar",
		"are_particles_playing",
		"set_particles_use_custom_fov",
		"set_particles_emit_rate_multiplier",
		"set_particles_surface_effect",
		"has_particles_material",
		"set_particles_life_time",
	}

	for _, name in ipairs(ID_FUNCTIONS) do
		if world_api[name] then
			local returns_false = FALSE_ON_NIL[name]

			mod:hook(world_api, name, function (func, world, id, ...)
				if id == nil and mod.manager then
					return returns_false and false or nil
				end

				return func(world, id, ...)
			end)
		end
	end

	return true
end

particle_guard.missing_effects = function ()
	local names = {}

	for name in pairs(failed_effects) do
		names[#names + 1] = name
	end

	table.sort(names)

	return names
end

return particle_guard
