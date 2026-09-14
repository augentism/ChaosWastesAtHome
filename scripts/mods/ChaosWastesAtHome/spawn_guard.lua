local mod = get_mod("ChaosWastesAtHome")
local SpawnPointQueries = require("scripts/managers/main_path/utilities/spawn_point_queries")
local HordeUtilities = require("scripts/managers/horde/utilities/horde_utilities")
local hooks = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/shared_hooks")
local spawn_guard = {}
local failures = 0
local reported = {}

local function report(kind, message, ...)
	if reported[kind] then return end
	reported[kind] = true
	mod:info("[spawn guard] " .. message, ...)
end

local function vector_error(err)
	return tostring(err):find("Vector3 expected", 1, true) ~= nil
end

local function valid_position(position)
	-- Lua type() reports both Vector3 and the invalid value as userdata.
	-- The native binding verifies the actual vector tag.
	local ok, length = pcall(Vector3.length_squared, position)
	return ok and type(length) == "number" and length == length and length < math.huge
end

local function refreshed_positions(side)
	-- SideSystem builds these unit/position arrays in matching order. Read
	-- live transforms only after a bad coordinate, never every frame.
	local units, old = side.valid_enemy_player_units, side.valid_enemy_player_units_positions
	if type(units) ~= "table" or type(old) ~= "table" or #units ~= #old then return nil end
	local fresh = {}
	for i = 1, #units do
		local unit = units[i]
		if not ALIVE[unit] then return nil end
		local ok, position = pcall(Unit.world_position, unit, 1)
		if not ok or not valid_position(position) then return nil end
		fresh[i] = position
	end
	return fresh
end

spawn_guard.install = function ()
	if not SpawnPointQueries or not SpawnPointQueries.occluded_positions_in_group then
		mod:error("SpawnPointQueries.occluded_positions_in_group unavailable - cannot guard horde spawn queries")
		return false
	end

	hooks.register(SpawnPointQueries, "occluded_positions_in_group", "cwah_spawn_query_guard", function (func, nav_world, nav_spawn_points, group_index, positions)
		if not mod.manager then return func(nav_world, nav_spawn_points, group_index, positions) end
		local ok, result = pcall(func, nav_world, nav_spawn_points, group_index, positions)
		if ok then return result end
		-- Keep the previous failed-group fallback; native callers try others.
		failures = failures + 1
		report("occlusion", "occluded spawn query skipped: positions=%s group=%s error=%s",
			type(positions) == "table" and #positions or -1, tostring(group_index), tostring(result))
		return {}
	end)

	hooks.register(HordeUtilities, "position_has_line_of_sight_to_any_enemy_player", "cwah_horde_los_guard", function (func, world, from, side, filter)
		local session = Managers.state and Managers.state.game_session
		if not mod.manager or not session or not session:is_server() then return func(world, from, side, filter) end
		local ok, result = pcall(func, world, from, side, filter)
		if ok then return result end
		if not vector_error(result) then error(result, 0) end

		local fresh = valid_position(from) and refreshed_positions(side)
		if fresh then
			-- Only this synchronous native query sees the corrected positions.
			-- Never mutate shared side arrays, including on exceptions.
			local proxy = setmetatable({valid_enemy_player_units_positions = fresh}, {__index = side})
			local retry_ok, retry_result = pcall(func, world, from, proxy, filter)
			if retry_ok then
				report("los_recovered", "horde visibility recovered using live player positions (%d); original error=%s", #fresh, tostring(result))
				return retry_result
			end
			if not vector_error(retry_result) then error(retry_result, 0) end
			result = retry_result
		end

		failures = failures + 1
		report("los_skipped", "horde candidate rejected: player visibility could not be verified; error=%s", tostring(result))
		-- Native callers accept a hidden spawn when this returns false.
		-- true rejects only this candidate and prevents visible enemy spawns.
		return true
	end)
	return true
end

spawn_guard.failure_count = function () return failures end
return spawn_guard
