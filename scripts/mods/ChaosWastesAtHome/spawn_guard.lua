local mod = get_mod("ChaosWastesAtHome")

local SpawnPointQueries = require("scripts/managers/main_path/utilities/spawn_point_queries")

-- Keeps a horde spawn-point query from taking the game down.
--
-- The observed crash:
--   spawn_point_queries.lua:261: bad argument #9 to 'get_occluded_points'
--   (Vector3 expected, got userdata)
--
-- GwNavSpawnPoints.get_occluded_points is an engine binding that flattens the
-- positions table into its argument list, so the trailing cost table lands at
-- argument #9 when four positions are passed. The engine wanted a Vector3
-- there, which means it expected more positions than the caller had -- driven
-- by how many player units are in the list, not by anything this mod touches.
--
-- This is a mitigation, not a fix: the root cause is still unknown, and the
-- guard is deliberately loud the first time so the diagnosis can continue with
-- real numbers rather than another reconstruction after the fact.

local spawn_guard = {}

local failures = 0
local reported = false

spawn_guard.install = function ()
	if not SpawnPointQueries or not SpawnPointQueries.occluded_positions_in_group then
		mod:error("SpawnPointQueries.occluded_positions_in_group unavailable - cannot guard horde spawn queries")

		return false
	end

	mod:hook(SpawnPointQueries, "occluded_positions_in_group", function (func, nav_world, nav_spawn_points, group_index, occluded_from_positions)
		-- Scoped to our missions: this runs inside horde pacing for every
		-- spawn attempt, and the rest of the game should not pay for a
		-- protected call on our account.
		if not mod.manager then
			return func(nav_world, nav_spawn_points, group_index, occluded_from_positions)
		end

		local ok, result = pcall(func, nav_world, nav_spawn_points, group_index, occluded_from_positions)

		if ok then
			return result
		end

		failures = failures + 1

		if not reported then
			reported = true

			-- The position count is the number worth having: if the engine
			-- wanted a fifth Vector3, this says how many it actually got.
			local count = type(occluded_from_positions) == "table" and #occluded_from_positions or -1

			mod:error("horde spawn query failed and was skipped (positions supplied: %s, group: %s) - %s",
				tostring(count), tostring(group_index), tostring(result))
			mod:info("further occurrences will be counted silently; /cw_status reports the total")
		end

		-- An empty list reads as "no spawn point in this group". Callers
		-- already handle that by trying other groups and, failing everything,
		-- skipping this horde -- so the worst case is a horde that does not
		-- arrive rather than a session that ends.
		return {}
	end)

	return true
end

spawn_guard.failure_count = function ()
	return failures
end

return spawn_guard
