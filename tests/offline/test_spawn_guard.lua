local h = ...
return {
	{ "spawn visibility recovers stale positions without changing shared side data", function (a)
		local hooks = {}
		local queries, horde = { occluded_positions_in_group = true }, {}
		local shared = { register = function (_, name, _, fn) hooks[name] = fn end }
		local unit, fresh, origin = {}, {}, {}
		local mod = { manager = {}, info = function () end, io_dofile = function () return shared end }
		local env = setmetatable({ get_mod = function () return mod end,
			require = function (path) return path:find("spawn_point_queries", 1, true) and queries or horde end,
			Managers = { state = { game_session = { is_server = function () return true end } } },
			ALIVE = { [unit] = true }, Unit = { world_position = function () return fresh end },
			Vector3 = { length_squared = function (p) if type(p) ~= "table" then error("Vector3 expected") end return 1 end },
		}, { __index = _G })
		local guard = setfenv(assert(loadfile(h.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/spawn_guard.lua")), env)()
		a.truthy(guard.install())
		local side = { valid_enemy_player_units = { unit }, valid_enemy_player_units_positions = { "stale" }, marker = "inherited" }
		local calls = 0
		local function native(_, from, candidate, filter)
			calls = calls + 1
			a.eq(from, origin); a.eq(candidate.marker, "inherited"); a.eq(filter, "filter")
			if candidate.valid_enemy_player_units_positions[1] == "stale" then error("Vector3 expected") end
			a.eq(candidate.valid_enemy_player_units_positions[1], fresh)
			return false
		end
		local los = hooks.position_has_line_of_sight_to_any_enemy_player
		a.eq(los(native, {}, origin, side, "filter"), false)
		a.eq(calls, 2); a.eq(side.valid_enemy_player_units_positions[1], "stale")
		env.ALIVE[unit] = nil
		a.eq(los(native, {}, origin, side, "filter"), true, "unrecoverable candidate is rejected")
		a.eq(guard.failure_count(), 1)
		a.falsy(pcall(los, function () error("unrelated failure") end, {}, origin, side))
		a.eq(los(function () return false end, {}, origin, side), false)
		local empty = hooks.occluded_positions_in_group(function () error("bad group") end, {}, {}, 1, {})
		a.eq(#empty, 0)
		mod.manager = nil
		a.falsy(pcall(los, native, {}, origin, side, "filter"))
	end },
}
