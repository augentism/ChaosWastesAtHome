local h = ...
return {
	{ "particle failures are cached per world and nil IDs have coherent results", function (a)
		local hooks = {}
		local api = { create_particles = true, destroy_particles = true, are_particles_playing = true, has_particles_material = true }
		local mod = { manager = {}, info = function () end, hook = function (_, _, name, fn) hooks[name] = fn end }
		local env = setmetatable({ World = api, get_mod = function () return mod end }, { __index = _G })
		env._G = env
		local guard = setfenv(assert(loadfile(h.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/particle_guard.lua")), env)()
		a.truthy(guard.install())
		local first, second, attempts = {}, {}, 0
		local function create(world)
			attempts = attempts + 1
			if world == first then error("Particle effect not loaded") end
			return 42
		end
		a.eq(hooks.create_particles(create, first, "missing"), nil)
		a.eq(hooks.create_particles(create, first, "missing"), nil)
		a.eq(attempts, 1)
		a.eq(hooks.create_particles(create, second, "missing"), 42)
		a.eq(guard.missing_effects()[1], "missing")
		local function native(_, id) return id or "native" end
		a.eq(hooks.are_particles_playing(native, first, nil), false)
		a.eq(hooks.has_particles_material(native, first, nil), false)
		a.eq(hooks.destroy_particles(native, first, nil), nil)
		a.eq(hooks.destroy_particles(native, first, 42), 42)
		mod.manager = nil
		a.eq(hooks.are_particles_playing(native, first, nil), "native")
		a.falsy(pcall(hooks.create_particles, create, first, "missing"))
	end },
}
