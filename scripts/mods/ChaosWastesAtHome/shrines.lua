local mod = get_mod("ChaosWastesAtHome")
local Breeds = require("scripts/settings/breed/breeds")
local Breed = require("scripts/utilities/breed")
local MutatorTemplates = require("scripts/settings/mutator/mutator_templates")
local NavQueries = require("scripts/utilities/nav_queries")

local shrines = {}
local SPAWNER = "mutator_live_event_saints_shrine_spawns"
local GAMEPLAY = "mutator_live_event_saints_shrine_gameplay"
local PERMANENT = "mutator_live_event_saints_mission_buffs"
local SHRINE_LEVEL = "content/levels/live_events/saints/live_event_saints_shrine_01"
local AREA_BUFF = "live_event_saints_in_area_buff"
local FALLBACK_BOSS = "chaos_plague_ogryn"
local installed = {}
local run, triggers, session_role
local state = { encounters = {}, bosses = {}, levels = {}, serial = 0 }

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

shrines.limit = function (value)
	value = tonumber(value) or 6
	if value ~= value then value = 6 end
	return math.max(1, math.min(20, math.floor(value)))
end

-- The boss has its own synchronous spawn, outside the flood queue. This
-- prevents a capped or abandoned flood from silently omitting the reward target.
shrines.split_composition = function (composition)
	local support = copy(composition or { breeds = {} })
	support.breeds = {}
	local boss
	for _, entry in ipairs(composition and composition.breeds or {}) do
		local breed = Breeds[entry.name]
		local kind = breed and Breed.enemy_type(breed)
		if kind == "monster" or kind == "captain" then
			-- Twin captains require additional event/inventory setup. Use a
			-- normal monster instead when an event composition selects a twin.
			if not boss and not string.find(entry.name, "twin", 1, true) then boss = entry.name end
		elseif breed then
			support.breeds[#support.breeds + 1] = copy(entry)
		end
	end
	return support, boss or FALLBACK_BOSS
end

local function live()
	return state.enabled and mod:is_enabled() and mod.has_authority()
end

local function components(level, callback)
	local extension = Managers.state and Managers.state.extension
	local system = extension and extension:system("component_system")
	if not system or not level then return end
	-- Instanced levels can be deleted before the mutator's destroy callback.
	local ok, units = pcall(Level.units, level)
	if not ok then return end
	for _, unit in ipairs(units) do
		for _, component in ipairs(system:get_all_components(unit)) do callback(component, unit) end
	end
end

local function disable_area(level)
	components(level, function (component)
		if component:name() == "BuffVolume" and component._heroes_buff_template_name == AREA_BUFF then
			component._leaving_buff_template_name = nil
			component:disable_buffs()
		end
	end)
end

shrines.reset = function (world_destroyed)
	if not world_destroyed and state.manager == (Managers.state and Managers.state.mutator) then
		for level in pairs(state.levels) do disable_area(level) end
	end
	state = { encounters = {}, bosses = {}, levels = {}, serial = 0 }
end

shrines.status = function ()
	local pending, alive, completed = 0, 0, 0
	for _, encounter in pairs(state.encounters) do
		if encounter.completed then completed = completed + 1
		elseif encounter.boss then alive = alive + 1
		else pending = pending + 1 end
	end
	return { enabled = state.enabled == true, limit = state.limit, pending = pending, alive = alive, completed = completed }
end

-- Called at the common loader boundary, before its package-loading wait and
-- spawn-point generation. Existing Maelstrom/Havoc mutators remain untouched.
local function setup(manager)
	shrines.reset()
	if not mod:is_enabled() or not session_role then return end
	local mission = Managers.state.mission and Managers.state.mission:mission()
	if not mission or mission.game_mode_name ~= "coop_complete_objective" then return end
	local role = session_role()
	if not role or (role == "host" and not run.is_launched()) then return end
	local enabled = role == "host" and mod:get("shrines_enabled") == true
	if role == "host" and not enabled then return end
	if not MutatorTemplates[SPAWNER] or not MutatorTemplates[GAMEPLAY] then
		mod:error("shrines unavailable: game shrine templates are missing")
		return
	end
	state.enabled = enabled
	state.manager = manager
	state.limit = shrines.limit(mod:get("shrines_max"))
	-- Guests load the same asset packages regardless of their own settings.
	-- Only the host spawner selects locations; level instances replicate them.
	for _, id in ipairs({ SPAWNER, GAMEPLAY }) do
		local instance = manager:mutator(id)
		if not instance then instance = manager:load_mutator_from_name(id) end
		if id == SPAWNER and instance and manager._is_server then
			instance._num_to_spawn = state.limit
		end
	end
	if enabled and manager:mutator(PERMANENT) then manager:unload_mutator_from_name(PERMANENT) end
	mod:info("shrines prepared: role=%s enabled=%s maximum=%d", role, tostring(enabled), state.limit)
end

local function try_boss(encounter)
	local spawn_manager = Managers.state.minion_spawn
	if not spawn_manager or not Breeds[encounter.breed] then return false end
	local nav_world = state.manager and state.manager._nav_world
	if not nav_world then return false end
	local center = encounter.position:unbox()
	local position
	-- A ring around the altar, snapped onto navmesh; no stale cached vectors.
	for i = 1, 8 do
		local angle = (i + encounter.attempts) * math.pi / 4
		local candidate = center + Vector3(math.cos(angle) * 7, math.sin(angle) * 7, 0)
		position = NavQueries.position_on_mesh_guaranteed(nav_world, candidate, 3, 3)
		if position then break end
	end
	if not position then return false end
	local params = spawn_manager:request_param_table()
	params.optional_aggro_state = "aggroed"
	-- Synchronous: there is never an untracked queued retry which can later
	-- produce a second boss. The hook below also records a partially completed
	-- spawn before an exception in a later spawn callback can escape.
	state.spawning = encounter
	local ok, unit = pcall(spawn_manager.spawn_minion, spawn_manager, encounter.breed, position, Quaternion.identity(), 2, params)
	state.spawning = nil
	if ok and unit then
		encounter.boss = unit
		state.bosses[unit] = encounter
	end
	if encounter.boss then
		mod:info("shrine boss spawned: shrine=%d breed=%s attempt=%d", encounter.id, encounter.breed, encounter.attempts)
		return true
	end
	return false
end

local function activate(instance, level)
	if instance._level ~= level or state.encounters[level] then return end
	state.levels[level] = true
	local compositions = instance:_get_enemy_composition()
	local faction = Managers.state.pacing:current_faction()
	local options = compositions[faction] or compositions.renegade or compositions.cultist
	local composition = options and Managers.state.difficulty:get_table_entry_by_resistance(options[math.random(1, #options)])
	local support, boss = shrines.split_composition(composition)
	state.serial = state.serial + 1
	local encounter = {
		id = state.serial, level = level, breed = boss, attempts = 0, retry_in = 0,
		support = support,
		position = Vector3Box(Matrix4x4.translation(Level.pose(level))),
		settings = { grant = mod:get("shrines_grant") or "legendary", chance = mod:get("shrines_chance") or 100 },
	}
	state.encounters[level] = encounter
	mod:info("shrine activated: shrine=%d boss=%s reward=%s chance=%s", encounter.id, boss, encounter.settings.grant, tostring(encounter.settings.chance))
end

shrines.boss_died = function (unit)
	local encounter = state.bosses[unit]
	if not live() or not encounter or encounter.completed then return false end
	encounter.completed = true
	state.bosses[unit] = nil
	disable_area(encounter.level)
	mod:info("shrine boss defeated: shrine=%d breed=%s", encounter.id, encounter.breed)
	triggers.fire("shrines", string.format("shrine=%d boss=%s", encounter.id, encounter.breed), encounter.settings)
	return true
end

local function hook(class_name, method, callback, safe)
	local key = class_name .. "." .. method
	-- Components have their own registry; CLASS entries with the same spelling
	-- are not the tables used by ComponentExtension's cached update callbacks.
	local registry = (class_name == "BuffVolume" or class_name == "AutoEvent") and rawget(_G, "Components") or CLASS
	local class = registry and registry[class_name]
	if installed[key] or not class or type(class[method]) ~= "function" then return end
	if safe then mod:hook_safe(class, method, callback) else mod:hook(class, method, callback) end
	installed[key] = true
end

shrines.install = function ()
	hook("MutatorManager", "_load_mutators", function (func, self, ...)
		func(self, ...)
		setup(self)
	end)
	hook("MutatorManager", "destroy", function (func, self)
		-- Mission cleanup has already removed the shrine levels and players.
		if state.manager == self then shrines.reset(true) end
		return func(self)
	end)
	hook("MutatorManager", "update", function (self, dt)
		if state.manager == self then shrines.tick(dt) end
	end, true)
	hook("MutatorSpawnerNodeLevelInstance", "_do_spawn", function (self)
		if not state.enabled then return end
		for _, data in ipairs(self._spawned_instanced_levels or {}) do
			if data.name == SHRINE_LEVEL then state.levels[data.level] = true end
		end
	end, true)
	hook("MutatorGameplayLiveEventSaintsSimplified", "_shrine_interaction_success", function (func, self, level)
		if not live() then return func(self, level) end
		activate(self, level)
	end)
	-- The altar stops its interaction module immediately after activation.
	-- Encounters belong to the mission, not that short-lived module: retain
	-- pending spawns, boss tracking and completion deduplication until reset.
	-- Some versions of the shrine level retain an AutoEvent component. Its
	-- injected enemies must not create an additional untracked boss encounter.
	hook("AutoEvent", "start_auto_event", function (func, self, unit)
		if state.enabled and state.levels[self._owning_level] then return end
		return func(self, unit)
	end)
	hook("AutoEvent", "stop_auto_event", function (func, self, unit)
		if state.enabled and state.levels[self._owning_level] and not self._auto_event_id then return end
		return func(self, unit)
	end)
	hook("BuffVolume", "update", function (func, self, unit, dt, t)
		local level = state.enabled and Unit.level(unit)
		if not level or not state.levels[level] or self._heroes_buff_template_name ~= AREA_BUFF then return func(self, unit, dt, t) end
		local encounter = state.encounters[level]
		self._leaving_buff_template_name = nil
		if not live() or not encounter or encounter.completed then
			self:disable_buffs()
			return true
		end
		self._buffs_enabled = true
		-- Stock update returns early when broadphase finds nobody, leaving the
		-- last player buffed outside the shrine. Always perform the exit sweep.
		self:_update_buffs(unit, dt, t, 0)
		return func(self, unit, dt, t)
	end)
	hook("MutatorManager", "_on_minion_unit_spawned", function (self, unit)
		local encounter = state.spawning
		local breed = encounter and Breed.unit_breed_or_nil(unit)
		if encounter and breed and breed.name == encounter.breed then
			encounter.boss = unit
			state.bosses[unit] = encounter
		end
	end, true)
end

shrines.configure = function (run_module, trigger_module, role_function)
	run, triggers, session_role = run_module, trigger_module, role_function
	shrines.install()
end

-- Run spawning in gameplay update, where the engine's cached player positions
-- are valid. DMF mod.update and dt-cli execute outside that lifetime.
shrines.tick = function (dt)
	if not live() then return end
	for _, encounter in pairs(state.encounters) do
		if not encounter.completed then
			if encounter.support then
				local support = encounter.support
				encounter.support = nil
				if #support.breeds > 0 then
					local ok = pcall(Managers.state.horde.horde, Managers.state.horde, "flood_horde", "flood_horde", 2, 1, support)
					if not ok then mod:info("shrine supporting horde failed: shrine=%d; boss reward remains available", encounter.id) end
				end
			end
			if encounter.boss and not ALIVE[encounter.boss] then
				state.bosses[encounter.boss] = nil
				encounter.boss = nil
				encounter.retry_in = 2
			end
			if not encounter.boss then
				encounter.retry_in = encounter.retry_in - (dt or 0)
				if encounter.retry_in <= 0 then
					encounter.attempts = encounter.attempts + 1
					if not try_boss(encounter) then
						encounter.retry_in = math.min(30, 2 * encounter.attempts)
						mod:info("shrine boss pending: shrine=%d attempt=%d retry_seconds=%d", encounter.id, encounter.attempts, encounter.retry_in)
					end
				end
			end
		end
	end
end

shrines.update = function ()
	shrines.install()
	if state.enabled and not mod:is_enabled() then shrines.reset() end
end

return shrines
