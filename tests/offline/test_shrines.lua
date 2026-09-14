local harness = ...
local ROOT = harness.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/"
local SPAWNER = "mutator_live_event_saints_shrine_spawns"
local GAMEPLAY = "mutator_live_event_saints_shrine_gameplay"

local function fixture()
	local f = { hooks = {}, grants = {}, settings = { shrines_enabled = true, shrines_max = 6, shrines_grant = "legendary", shrines_chance = 100 }, authority = true, spawned = 0 }
	local classes = {}
	local methods = {
		MutatorManager = { "_load_mutators", "destroy", "update", "_on_minion_unit_spawned" },
		MutatorSpawnerNodeLevelInstance = { "_do_spawn" },
		MutatorGameplayLiveEventSaintsSimplified = { "_shrine_interaction_success", "destroy" },
		AutoEvent = { "start_auto_event", "stop_auto_event" },
		BuffVolume = { "update" }, MinionDeathManager = { "set_dead" },
	}
	for name, names in pairs(methods) do
		local class = { name = name }
		for _, method in ipairs(names) do class[method] = function () end end
		classes[name] = class
	end
	local components = { AutoEvent = classes.AutoEvent, BuffVolume = classes.BuffVolume }
	-- Same-spelled CLASS entries are not the engine component prototypes.
	classes.AutoEvent = { name = "WrongAutoEvent", start_auto_event = function () end }
	classes.BuffVolume = { name = "WrongBuffVolume", update = function () end }
	local mod = {
		get = function (_, id) return f.settings[id] end,
		is_enabled = function () return not f.disabled end,
		has_authority = function () return f.authority end,
		info = function () end, error = function () end,
	}
	mod.hook = function (_, class, method, fn) f.hooks[class.name .. "." .. method] = fn end
	mod.hook_safe = mod.hook
	local vector = setmetatable({}, { __add = function (a) return a end })
	local breeds = setmetatable({}, { __index = function (_, name)
		if name:find("twin") or name == "renegade_captain" then return { name = name, kind = "captain" } end
		if name == "chaos_plague_ogryn" or name == "chaos_spawn" or name == "chaos_beast_of_nurgle" then return { name = name, kind = "monster" } end
		return { name = name, kind = "horde" }
	end })
	f.manager = { _is_server = true, _nav_world = {}, _mutators = { existing_havoc = {} } }
	function f.manager:mutator(id) return self._mutators[id] end
	function f.manager:load_mutator_from_name(id) self._mutators[id] = {}; return self._mutators[id] end
	function f.manager:unload_mutator_from_name(id) self._mutators[id] = nil end
	local managers = { state = {
		mission = { mission = function () return { game_mode_name = "coop_complete_objective" } end },
		pacing = { current_faction = function () return "renegade" end },
		difficulty = { get_table_entry_by_resistance = function (_, t) return t[1] end },
		horde = { horde = function (_, _, _, _, _, composition) f.support = composition end },
		extension = { system = function () return { get_all_components = function () return {} end } end },
		minion_spawn = {
			request_param_table = function () return {} end,
			spawn_minion = function ()
				if f.fail_spawn then return nil end
				f.spawned = f.spawned + 1
				f.boss = { id = f.spawned }; f.alive[f.boss] = true
				return f.boss
			end,
		},
	} }
	f.alive = {}
	managers.state.mutator = f.manager
	local env = setmetatable({
		get_mod = function () return mod end, CLASS = classes, Components = components, Managers = managers, ALIVE = f.alive,
		Vector3 = function () return vector end,
		Vector3Box = function () return { unbox = function () return vector end } end,
		Quaternion = { identity = function () return {} end },
		Matrix4x4 = { translation = function () return vector end },
		Level = { units = function () return {} end, pose = function () return {} end },
		Unit = { level = function (u) return u.level end },
	}, { __index = _G })
	env.require = function (path)
		if path:find("settings/breed/breeds", 1, true) then return breeds end
		if path == "scripts/utilities/breed" then return { enemy_type = function (b) return b.kind end, unit_breed_or_nil = function () end } end
		if path:find("mutator_templates", 1, true) then return { [SPAWNER] = {}, [GAMEPLAY] = {} } end
		if path == "scripts/utilities/nav_queries" then return { position_on_mesh_guaranteed = function () return vector end } end
		return require(path)
	end
	env._G = env
	f.env = env
	local chunk = assert(loadfile(ROOT .. "shrines.lua"))
	f.shrines = setfenv(chunk, env)()
	f.shrines.configure({ is_launched = function () return not f.unlaunched end },
		{ fire = function (source, detail, settings) f.grants[#f.grants + 1] = { source = source, settings = settings } end },
		function () return f.role or "host" end)
	f.setup = function () f.hooks["MutatorManager._load_mutators"](function () end, f.manager) end
	f.activate = function (level)
		local instance = { _level = level, _get_enemy_composition = function () return { renegade = { { { breeds = {
			{ name = "chaos_plague_ogryn", amount = { 2, 3 } }, { name = "chaos_poxwalker", amount = { 5, 5 } },
		} } } } } end }
		f.hooks["MutatorGameplayLiveEventSaintsSimplified._shrine_interaction_success"](function () f.stock_called = true end, instance, level)
	end
	f.destroy_module = function (level)
		local original = function () f.module_destroyed = true end
		local hook = f.hooks["MutatorGameplayLiveEventSaintsSimplified.destroy"]
		if hook then hook(original, { _level = level }) else original() end
	end
	return f
end

local function reward_fixture()
	local f = { settings = { max_family_buffs = 1, max_legendary_choices = 1 }, events = {}, hooks = {}, deaths = 0 }
	local persistent = {
		get_legendary_buffs_available_for_player = function () return { pool = { "a", "b", "c" } } end,
		get_player_priority_family_buffs_available = function () return { "family" } end,
		get_player_family_buffs_available = function () return {} end,
	}
	local mod = {
		get = function (_, id) return f.settings[id] end,
		has_authority = function () return true end,
		info = function () end, debug_log = function () end,
		manager = { _mission_buffs_handler = { _persistent_data = persistent },
			get_buff_family_selected_by_player = function () return "family" end },
		shrines = { boss_died = function () f.deaths = f.deaths + 1 end },
	}
	mod.hook = function (_, _, name, callback)
		assert(not f.hooks[name], "duplicate hook")
		f.hooks[name] = callback
	end
	mod.hook_safe = mod.hook
	local env = setmetatable({
		get_mod = function () return mod end,
		require = function () return {} end,
		Managers = { player = { local_player_safe = function () return {} end },
			event = { trigger = function (_, event) f.events[#f.events + 1] = event end } },
	}, { __index = _G })
	f.triggers = setfenv(assert(loadfile(ROOT .. "triggers.lua")), env)()
	return f
end

return {
	{ "normal altar activation survives immediate interaction-module destruction", function (a)
		local f = fixture(); f.setup(); local level = {}
		f.activate(level); f.destroy_module(level)
		a.truthy(f.module_destroyed); a.eq(f.shrines.status().pending, 1)
		f.shrines.tick(1); a.eq(f.spawned, 1)
		a.truthy(f.shrines.boss_died(f.boss)); a.eq(#f.grants, 1)
		f.activate(level); f.shrines.tick(1)
		a.eq(f.spawned, 1); a.eq(#f.grants, 1)
	end },
	{ "death dispatch reaches shrines with kill-count rewards disabled", function (a)
		local f = reward_fixture()
		f.hooks.set_dead({}, {})
		a.eq(f.deaths, 1); a.eq(f.triggers.stats().kills, 0)
	end },
	{ "shrine snapshots preserve zero chance and share fallback budgets", function (a)
		local f = reward_fixture(); f.settings.shrines_chance = 100
		a.falsy(f.triggers.fire("shrines", "zero chance", { grant = "legendary", chance = 0 }))
		a.eq(#f.events, 0)
		a.truthy(f.triggers.fire("shrines", "boss 1", { grant = "legendary", chance = 100 }))
		a.truthy(f.triggers.fire("shrines", "boss 2", { grant = "legendary", chance = 100 }))
		a.falsy(f.triggers.fire("shrines", "boss 3", { grant = "random", chance = 100 }))
		a.eq(f.triggers.stats().legendary_granted, 1); a.eq(f.triggers.stats().family_granted, 1)
		a.eq(#f.events, 2)
	end },
	{ "mission teardown forgets shrines without visiting deleted engine levels", function (a)
		local f = fixture(); f.setup(); f.activate({}); f.shrines.tick(1)
		local calls = 0
		f.env.Level.units = function () calls = calls + 1; error("deleted level") end
		f.hooks["MutatorManager.destroy"](function () end, f.manager)
		a.eq(calls, 0); a.eq(f.shrines.status().alive, 0)
		a.falsy(f.shrines.boss_died(f.boss)); a.eq(#f.grants, 0)
	end },
	{ "shrines add to existing mutators, clamp counts, and respect host activation", function (a)
		local f = fixture(); f.settings.shrines_max = 100; f.setup()
		a.truthy(f.manager._mutators.existing_havoc); a.truthy(f.manager:mutator(GAMEPLAY))
		a.eq(f.manager:mutator(SPAWNER)._num_to_spawn, 20)
		a.eq(f.shrines.limit(-1), 1); a.eq(f.shrines.limit(6.9), 6)
		f = fixture(); f.settings.shrines_enabled = false; f.setup(); a.nil_(f.manager:mutator(SPAWNER))
		f = fixture(); f.unlaunched = true; f.setup(); a.nil_(f.manager:mutator(SPAWNER))
		f = fixture(); f.role = "client"; f.settings.shrines_enabled = false; f.manager._is_server = false; f.setup()
		a.truthy(f.manager:mutator(SPAWNER)); a.falsy(f.shrines.status().enabled)
	end },
	{ "all shipped shrine compositions isolate one reward boss without changing source data", function (a)
		local f = fixture()
		local path = harness.ENGINE .. "scripts/settings/live_event/live_event_enemy_compositions/live_event_saints_enemy_compositions.lua"
		local file = assert(io.open(path)); local text = file:read("*a"); file:close()
		text = text:gsub("^\239\187\191", "")
		local compositions = assert(loadstring(text))()
		local checked = 0
		for _, factions in pairs(compositions) do for _, variants in pairs(factions) do
			for _, tiers in ipairs(variants) do for _, composition in ipairs(tiers) do
				local count = #composition.breeds
				local support, boss = f.shrines.split_composition(composition)
				a.truthy(boss); a.eq(#composition.breeds, count)
				for _, entry in ipairs(support.breeds) do
					a.falsy(entry.name:find("captain")); a.neq(entry.name, "chaos_plague_ogryn")
					a.neq(entry.name, "chaos_spawn"); a.neq(entry.name, "chaos_beast_of_nurgle")
				end
				checked = checked + 1
			end end
		end end
		a.truthy(checked >= 80)
	end },
	{ "only the assigned boss pays once with activation settings while support remains", function (a)
		local f = fixture(); f.setup(); local level = {}; f.activate(level); f.activate(level)
		a.eq(f.shrines.status().pending, 1)
		f.shrines.tick(1); a.eq(f.spawned, 1); a.eq(#f.support.breeds, 1)
		a.falsy(f.shrines.boss_died({})); a.eq(#f.grants, 0)
		f.settings.shrines_grant = "family"; f.settings.shrines_chance = 0
		a.truthy(f.shrines.boss_died(f.boss)); a.falsy(f.shrines.boss_died(f.boss))
		a.eq(#f.grants, 1); a.eq(f.grants[1].source, "shrines")
		a.eq(f.grants[1].settings.grant, "legendary"); a.eq(f.grants[1].settings.chance, 100)
		f.shrines.tick(60); a.eq(f.spawned, 1)
	end },
	{ "failed spawns retry, despawns replace bosses, and overlapping shrines stay independent", function (a)
		local f = fixture(); f.setup(); f.activate({}); f.fail_spawn = true
		f.shrines.tick(1); a.eq(f.spawned, 0); a.eq(#f.grants, 0)
		f.fail_spawn = false; f.shrines.tick(3); a.eq(f.spawned, 1)
		local first = f.boss; f.activate({}); f.shrines.tick(1); local second = f.boss
		a.neq(first, second); a.truthy(f.shrines.boss_died(first)); a.eq(#f.grants, 1)
		f.alive[second] = nil; f.shrines.tick(3); a.eq(f.spawned, 3); a.eq(#f.grants, 1)
		a.truthy(f.shrines.boss_died(f.boss)); a.eq(#f.grants, 2)
		f.shrines.reset(); a.eq(f.shrines.status().completed, 0)
	end },
	{ "area volume always sweeps exits and switches off after its boss dies", function (a)
		local f = fixture(); f.setup(); local level = {}; f.activate(level); f.shrines.tick(1)
		local volume = { _heroes_buff_template_name = "live_event_saints_in_area_buff", _leaving_buff_template_name = "unwanted" }
		local sweeps, disabled, updates = 0, 0, 0
		function volume:_update_buffs(_, _, _, count) a.eq(count, 0); sweeps = sweeps + 1 end
		function volume:disable_buffs() self._buffs_enabled = false; disabled = disabled + 1 end
		local original = function () updates = updates + 1 end
		local update = f.hooks["BuffVolume.update"]
		update(original, volume, { level = level }, 1, 1)
		a.eq(sweeps, 1); a.eq(updates, 1); a.nil_(volume._leaving_buff_template_name)
		a.truthy(volume._buffs_enabled)
		f.shrines.boss_died(f.boss)
		update(original, volume, { level = level }, 1, 2)
		a.eq(updates, 1); a.eq(disabled, 1); a.falsy(volume._buffs_enabled)
		update(original, volume, { level = {} }, 1, 3); a.eq(updates, 2)
	end },
}
