local harness = ...
local recipes = harness.load("buff_recipes")
local BASE = [[
[momentum]
name = Momentum 100%
trigger = elite_kill
effect = attack_speed
amount = 2
max_stacks = 5
duration = 10
]]

-- Load the actual reference files in an isolated environment. The common
-- harness tolerates transitive require failures; that would leave buff_settings
-- half-built through breed_queries. Only its breed query / Script allocation
-- dependencies are stubbed here, never its stat types or event names.
local function engine_file(path, modules, globals)
	local file = assert(io.open(harness.ENGINE .. path .. ".lua", "rb"))
	local source = file:read("*a"); file:close()
	local env = setmetatable(globals or {}, { __index = _G })
	env.require = function (name)
		if modules and modules[name] ~= nil then return modules[name] end
		return require(name)
	end
	local chunk = assert(loadstring(source:gsub("^\239\187\191", ""), "@" .. path))
	setfenv(chunk, env)
	return chunk()
end

local engine_table = table.shallow_copy(table)
engine_table.enum = function (...)
	local result = {}
	for _, name in ipairs({ ... }) do result[name] = name end
	return result
end
local real_settings = engine_file("scripts/settings/buff/buff_settings", {
	["scripts/utilities/breed_queries"] = { minion_breeds_by_name = function () return {} end },
}, { Script = { new_map = function () return {} end }, table = engine_table })
local real_checks = engine_file("scripts/settings/buff/helper_functions/check_proc_functions", {
	["scripts/settings/buff/buff_settings"] = real_settings,
})

local function dependencies(a, active)
	a.truthy(real_settings.stat_buff_types.attack_speed, "real stat types")
	a.truthy(real_checks.on_elite_kill, "real predicates")
	return { settings = real_settings, checks = real_checks, active = active or function () return true end }
end

local function compile(a, text, deps)
	local parsed, errors = recipes.parse(text or BASE)
	a.count(errors, 0, "valid text")
	local entries, problems = recipes.compile(parsed, deps or dependencies(a))
	a.count(problems, 0, "available components")
	return entries
end

local function templates(a, text, deps)
	local entries = compile(a, text, deps)
	return entries[1].template({ resolve = function (id) return "test_" .. id end }), entries[2].template(), entries
end

return {
	{ "family recipes supplement regular family pools without mutating or duplicating entries", function (a)
		local user = harness.load("user_buffs")
		local state = harness.mod._user_buffs
		local previous = state.session_menu
		state.session_menu = {{name="family_recipe",is_family_buff=true},{name="legendary_recipe",is_family_buff=false}}
		local original = {"base", "family_recipe"}
		local result = user.family_pool(original)
		state.session_menu = previous
		a.count(result, 2); a.eq(result[1], "base"); a.eq(result[2], "family_recipe")
		a.neq(result, original); a.count(original, 2)
	end },
	{ "reward kind defaults to legendary and family recipes survive canonical round trips", function (a)
		local old = compile(a, BASE)[1]
		a.falsy(old.is_family_buff)
		local definitions, errors = recipes.parse(BASE .. "legendary = false\n")
		a.count(errors, 0)
		local canonical = recipes.serialize(definitions)
		a.truthy(canonical:find("legendary = false", 1, true))
		local family = compile(a, canonical)[1]
		a.truthy(family.is_family_buff)
		a.neq(family.definition_signature, old.definition_signature)
		local _, bad = recipes.parse(BASE .. "legendary = maybe\n")
		a.truthy(#bad > 0)
	end },
	{ "editor saves, renames, deletes and reloads personal data without changing active recipes", function (a)
		local old_mods, old_get, old_require = Mods, get_mod, require
		local path = "/fake/buffs.txt"
		local files = { [path] = BASE .. BASE:gsub("momentum", "disabled") .. "enabled = false\n" }
		local io_lib = { open = function (name, mode)
			if mode == "rb" then
				if files[name] == nil then return nil, "missing", 2 end
				return { read = function (_, n) return files[name]:sub(1, n) end, close = function () return true end }
			end
			return { write = function (_, text) files[name] = text; return true end, close = function () return true end }
		end }
		Mods = { lua = { io = io_lib, os = { rename = function (from, to) files[to], files[from] = files[from], nil; return true end } } }
		get_mod = function (name)
			if name == "DMF" then return { deepcopy = table.shallow_copy } end
			if name == "Realms" then return { network_register = function () end } end
			return old_get(name)
		end
		require = function (name)
			if name == "scripts/settings/buff/buff_settings" then return real_settings end
			if name == "scripts/settings/buff/helper_functions/check_proc_functions" then return real_checks end
			return old_require(name)
		end
		local ok, err = pcall(function ()
			local user = harness.load("user_buffs")
			local registrations = 0
			user.load({ directory = function () return "/fake/loadouts/" end, ensure_dir = function () return true end }, {
				register_buffs = function (_, entries) registrations = registrations + 1; return #entries, {} end,
				buff_id = function (_, id) return id end,
			}, { invalidate = function () end })
			local original = files[path]
			local draft = recipes.parse(BASE)[1]
			draft.id, draft.name = "editor_buff", "Editor buff"
			a.truthy(user.save_definition(draft)); a.eq(registrations, 1, "save never rebinds slots")
			a.eq(files[path .. ".bak"], original)
			a.count(user.definitions(), 3)
			a.truthy(files[path]:find("enabled = false", 1, true), "disabled recipes survive serialization")
			a.falsy(user.save_definition(draft), "duplicate IDs require explicit edit")
			local run = harness.load("run")
			run.mark_launched()
			local frozen = harness.mod._run.recipe_catalogue
			draft.amount = 3
			local saved, message = user.save_definition(draft, draft.id)
			a.truthy(saved); a.truthy(message:find("next session", 1, true))
			a.eq(harness.mod._run.recipe_catalogue, frozen)
			a.neq(harness.mod._user_buffs.local_text, frozen)
			draft.id = "renamed"
			a.truthy(user.save_definition(draft, "editor_buff"))
			a.truthy(user.delete_definition("renamed")); a.count(user.definitions(), 2)
			files[path] = BASE:gsub("amount = 2", "amount = 4")
			a.falsy(user.save_definition(draft), "external changes block stale writes")
			a.truthy(user.reload()); a.eq(harness.mod._run.recipe_catalogue, frozen)
			a.eq(user.definitions()[1].amount, 4)
			local last_good = harness.mod._user_buffs.local_text
			files[path] = "malformed"
			a.falsy(user.reload()); a.eq(harness.mod._user_buffs.local_text, last_good)
			run.reset("test"); a.falsy(harness.mod._run.recipe_catalogue)
		end)
		Mods, get_mod, require = old_mods, old_get, old_require
		if not ok then error(err, 0) end
	end },
	{ "editor controls cover all components with valid labels and native button contracts", function (a)
		local ui = harness.load("recipe_editor_widgets")
		local labels = ui.localizations()
		for _, widget in ipairs(ui.group().sub_widgets) do
			a.truthy(labels[widget.setting_id], widget.setting_id)
			a.truthy(pcall(string.format, labels[widget.setting_id].en))
			if widget.type == "button" then
				a.eq(widget.button_trigger, "pressed"); a.truthy(labels[widget.button_text])
			elseif widget.type == "dropdown" then
				a.truthy(#widget.options > 1)
				for _, item in ipairs(widget.options) do a.truthy(labels[item.text], item.text) end
			end
		end
	end },
	{ "unreadable personal recipes do not prevent reserving session slots", function (a)
		local old_get, old_mods = get_mod, Mods
		Mods = nil
		get_mod = function (name)
			if name == "Realms" then return { network_register = function () end } end
			return old_get(name)
		end
		local ok, err = pcall(function ()
			local user = harness.load("user_buffs")
			local reserved = 0
			user.load({ directory = function () return nil end }, {
				register_buffs = function (_, entries) reserved = #entries; return #entries, {} end,
				buff_id = function (_, id) return id end,
			}, { invalidate = function () end })
			a.eq(reserved, 128); a.truthy(harness.mod._user_buffs.deferred)
			a.count(harness.mod._user_buffs.errors, 1)
		end)
		get_mod, Mods = old_get, old_mods
		if not ok then error(err, 0) end
	end },
	{ "Realms reserves stable slots, previews saved recipes and replaces catalogues only after teardown", function (a)
		local old_mods, old_get_mod, old_require, old_managers = Mods, get_mod, require, Managers
		local old_lookup = NetworkLookup
		NetworkLookup = { buff_templates = { "base", base = 1 } }
		Managers = { state = {} }
		Mods = { lua = { io = { open = function () return {
			read = function () return BASE end, close = function () end,
		} end } } }
		get_mod = function (name)
			if name == "DMF" then return { deepcopy = table.shallow_copy } end
			if name == "Realms" then return { network_register = function () end } end
			return old_get_mod(name)
		end
		require = function (name)
			if name == "scripts/settings/buff/buff_settings" then return real_settings end
			if name == "scripts/settings/buff/helper_functions/check_proc_functions" then return real_checks end
			return old_require(name)
		end
		local ok, err = pcall(function ()
			local user = harness.load("user_buffs")
			harness.mod.user_buffs = user
			local calls = 0
			local registry = harness.load("buff_registry")
			local register = registry.register_buffs
			registry.register_buffs = function (...) calls = calls + 1; return register(...) end
			local pool = harness.load("buff_pool")
			user.load({ directory = function () return "/fake/loadouts/" end, ensure_dir = function () return true end }, registry, pool)
			a.eq(calls, 1); a.eq(harness.mod._user_buffs.count, 0)
			local lookup_size = #NetworkLookup.buff_templates
			local preview = user.menu_entries()[1]
			a.eq(preview.title, "Momentum 100%")
			a.eq(pool.details(preview.name).title, "Momentum 100%")
			a.falsy(rawget(NetworkLookup.buff_templates, preview.name), "preview has no network ID")
			local found = false
			for _, group in ipairs(pool.groups()) do
				if group.id == "cwah_player_buffs" then found = true; a.eq(group.names[1], preview.name) end
			end
			a.truthy(found, "saved menu group exists before a lobby")
			local saved = harness.mod._user_buffs.local_text
			local host = recipes.serialize(recipes.parse(BASE:gsub("momentum", "host_only")
				.. BASE:gsub("momentum", "z_second") .. BASE:gsub("momentum", "z_third")))
			a.falsy(user.install_text("not a recipe")); a.eq(calls, 1)
			a.truthy(user.install_text(host)); a.eq(calls, 2)
			a.eq(harness.mod._user_buffs.local_text, saved)
			local slot = user.name("host_only")
			local old_tail = user.name("z_third")
			local id = NetworkLookup.buff_templates[slot]
			a.truthy(slot); a.falsy(user.name("momentum"))
			a.truthy(user.install_text(host)); a.eq(calls, 2, "idempotent acknowledgement retry")
			Managers.state.extension = {}
			a.falsy(user.install_text(saved)); a.eq(calls, 2, "live extensions block replacement")
			Managers.state.extension = nil
			Managers.state.game_session = {}
			a.falsy(user.install_text(saved), "live game session blocks replacement")
			Managers.state.game_session = nil
			harness.mod.manager = {}
			a.falsy(user.install_text(saved), "live CWaH manager blocks replacement")
			harness.mod.manager = nil
			pool.set_enabled(preview.name, false)
			a.truthy(user.install_text(saved)); a.eq(calls, 3)
			harness.mod.recipe_sync = { ready = function () return true end }
			a.falsy(pool.is_enabled(slot), "personal preference follows recipe, not slot")
			a.falsy(require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")[old_tail], "shrinking clears old tail cards")
			a.eq(user.name("momentum"), slot); a.falsy(user.name("host_only"))
			a.eq(NetworkLookup.buff_templates[slot], id)
			a.eq(#NetworkLookup.buff_templates, lookup_size)
			a.truthy(user.install_text("")); a.eq(harness.mod._user_buffs.count, 0)
			a.falsy(require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")[slot])
			for _, name in ipairs(require("scripts/managers/mission_buffs/mission_buffs_allowed_buffs").legendary_buffs.generic) do
				a.falsy(name == slot, "dormant slot removed from pool")
			end
			a.eq(NetworkLookup.buff_templates[slot], id)
		end)
		Mods, get_mod, require, Managers = old_mods, old_get_mod, old_require, old_managers
		NetworkLookup = old_lookup
		if not ok then error(err, 0) end
	end },
	{ "canonical recipe wire text round-trips and excludes disabled definitions", function (a)
		local definitions = recipes.parse(BASE .. BASE:gsub("momentum", "disabled") .. "enabled = false\n")
		local text = recipes.serialize(definitions)
		local parsed, errors = recipes.parse(text)
		a.count(parsed, 1); a.count(errors, 0)
		a.eq(recipes.serialize(parsed), text)
		a.eq(parsed[1].name, "Momentum 100%")
	end },
	{ "carrier session gate is independent of host-only trigger authority", function (a)
		local deps = dependencies(a, function () return false end)
		deps.carrier_active = function () return true end
		local controller, carrier = templates(a, nil, deps)
		a.falsy(controller.check_proc_func({}, {}, {}, 0))
		a.truthy(carrier.conditional_stat_buffs_func())
	end },
	{ "text parsing supports BOM, CRLF, defaults, plain names and stable ordering", function (a)
		local parsed, errors = recipes.parse("\239\187\191# comment\r\n; another\r\n" .. BASE:gsub("\n", "\r\n"))
		a.count(errors, 0); a.count(parsed, 1)
		a.eq(parsed[1].name, "Momentum 100%")
		a.eq(parsed[1].chance, 100); a.eq(parsed[1].cooldown, 0); a.truthy(parsed[1].enabled)
		parsed = recipes.parse(BASE .. BASE:gsub("momentum", "aaa"))
		a.eq(parsed[1].id, "aaa"); a.eq(parsed[2].id, "momentum")
	end },
	{ "bad blocks never partially load and do not discard unrelated valid blocks", function (a)
		for _, bad in ipairs({
			BASE .. "typo = 4\n", BASE .. "amount = 3\n", BASE:gsub("amount = 2", "amount = 1e999"),
			BASE:gsub("max_stacks = 5", "max_stacks = 5.5"), BASE:gsub("max_stacks = 5", "max_stacks = 32"),
			BASE:gsub("duration = 10", "duration = 0"), BASE:gsub("duration = 10", "duration = -1"),
			BASE:gsub("amount = 2", "amount = 99"), BASE:gsub("trigger = elite_kill", "trigger = typo"),
			BASE:gsub("effect = attack_speed", "effect = typo"), BASE .. "chance = 0\n",
			BASE .. "cooldown = -1\n", BASE .. "enabled = yes\n", BASE:gsub("amount = 2\n", ""),
			BASE:gsub("amount = 2", "amount = os.execute('bad')"),
			(BASE:gsub("%[momentum%]", "[../escape]")),
		}) do
			local parsed, errors = recipes.parse(bad .. BASE:gsub("momentum", "valid"))
			a.count(parsed, 1, bad); a.eq(parsed[1].id, "valid"); a.truthy(#errors > 0)
		end
		local parsed, errors = recipes.parse(BASE .. BASE)
		a.count(parsed, 0, "both duplicate IDs rejected"); a.truthy(#errors > 0)
		parsed, errors = recipes.parse(string.rep(BASE, 65))
		a.count(parsed, 0); a.truthy(#errors > 0)
		parsed, errors = recipes.parse(string.rep(" ", 65537))
		a.count(parsed, 0); a.truthy(#errors > 0)
	end },
	{ "every declared trigger and effect compiles against actual engine settings", function (a)
		local deps = dependencies(a)
		for id in pairs(recipes.triggers) do
			local entries = compile(a, BASE:gsub("trigger = elite_kill", "trigger = " .. id), deps)
			a.count(entries, 2, id)
		end
		for id in pairs(recipes.effects) do
			local entries = compile(a, BASE:gsub("effect = attack_speed", "effect = " .. id), deps)
			a.count(entries, 2, id)
		end
	end },
	{ "engine type drift rejects a recipe without running arbitrary input", function (a)
		local deps = dependencies(a)
		local copy = table.shallow_copy(deps.settings)
		copy.stat_buff_types = table.shallow_copy(copy.stat_buff_types)
		copy.stat_buff_types.attack_speed = "multiplicative_multiplier"
		deps.settings = copy
		local entries, errors = recipes.compile(recipes.parse(BASE), deps)
		a.count(entries, 0); a.count(errors, 1)
	end },
	{ "controller uses real elite checks, per-instance cooldown and session gating", function (a)
		local active = true
		local deps = dependencies(a, function () return active end)
		local controller, carrier = templates(a, BASE .. "cooldown = 2\nchance = 25\n", deps)
		a.eq(controller.proc_events[deps.settings.proc_events.on_kill], 0.25)
		local params = { attack_result = require("scripts/settings/damage/attack_settings").attack_results.died, tags = { elite = true } }
		local data, other, context = {}, {}, { unit = {} }
		a.truthy(controller.check_proc_func(params, data, context, 1))
		a.falsy(controller.check_proc_func({ tags = {} }, data, context, 1))
		local old_script, calls = ScriptUnit, {}
		ScriptUnit = { has_extension = function () return { add_internally_controlled_buff = function (_, name, t)
			calls[#calls + 1] = { name, t }
		end } end }
		local ok, err = pcall(function ()
			controller.proc_func(params, data, context, 1)
			a.eq(calls[1][1], "test_stack_momentum"); a.eq(calls[1][2], 1)
			a.falsy(controller.check_proc_func(params, data, context, 2.9))
			a.truthy(controller.check_proc_func(params, other, context, 2.9), "another player has its own timer")
			a.truthy(controller.check_proc_func(params, data, context, 3))
			active = false
			a.falsy(controller.check_proc_func(params, data, context, 4))
			controller.proc_func(params, data, context, 4)
			a.count(calls, 1); a.falsy(carrier.conditional_stat_buffs_func())
		end)
		ScriptUnit = old_script
		if not ok then error(err, 0) end
	end },
	{ "stat conversions use bonuses, percentage points and multiplicative reductions", function (a)
		local deps = dependencies(a)
		for effect, expected in pairs({ damage = 0.02, attack_speed = 0.02,
			critical_strike_chance = 0.02, dodge_speed = 1.02, damage_reduction = 0.98 }) do
			local controller, carrier = templates(a, BASE:gsub("effect = attack_speed", "effect = " .. effect), deps)
			local stat = deps.settings.stat_buffs[recipes.effects[effect].stat]
			a.eq(carrier.conditional_stat_buffs[stat], expected, effect)
			a.eq(controller.max_stacks_cap, 1, "card ownership is separate from effect stacks")
			a.eq(carrier.max_stacks, 5); a.eq(carrier.max_stacks_cap, 5)
			a.eq(carrier.duration, 10); a.truthy(carrier.refresh_duration_on_stack)
			a.falsy(carrier.refresh_duration_on_remove_stack)
		end
		a.count(compile(a, BASE .. "enabled = false\n"), 0)
	end },
	{ "cards and helpers register independently, preserve percent names and fingerprint values", function (a)
		local registry = harness.load("buff_registry")
		local old_lookup = NetworkLookup
		NetworkLookup = { buff_templates = {} }
		local buff_templates = require("scripts/settings/buff/buff_templates")
		local buff_data = require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")
		local pool = require("scripts/managers/mission_buffs/mission_buffs_allowed_buffs").legendary_buffs.generic
		local pool_length, ids = #pool, {}
		local ok, err = pcall(function ()
			local entries = compile(a, BASE .. BASE:gsub("momentum", "momentum_stacks"))
			local count, errors = registry.register_buffs("RecipeTest", entries)
			a.eq(count, 4); a.count(errors, 0)
			for _, entry in ipairs(entries) do
				local id = registry.buff_id("RecipeTest", entry.id)
				ids[#ids + 1] = id
				a.eq(buff_templates[id].name, id)
				a.eq(NetworkLookup.buff_templates[NetworkLookup.buff_templates[id]], id)
				if entry.pool then
					a.contains(pool, id)
					a.eq(string.format(harness.global_localization[buff_data[id].title].en), "Momentum 100%")
					a.truthy(pcall(string.format, harness.global_localization[buff_data[id].description].en))
				else a.not_contains(pool, id) end
			end
			local before = table.concat(registry.network_id_map(), "\n")
			registry.register_buffs("RecipeTest", compile(a, (BASE:gsub("amount = 2", "amount = 3"))))
			a.neq(table.concat(registry.network_id_map(), "\n"), before, "same IDs with different values fail peer identity")
		end)
		for _, id in ipairs(ids) do buff_templates[id], buff_data[id] = nil, nil end
		for i = #pool, pool_length + 1, -1 do pool[i] = nil end
		NetworkLookup = old_lookup
		if not ok then error(err, 0) end
	end },
	{ "real engine stack methods cap, refresh at cap, expire all stacks and restart cleanly", function (a)
		local active = true
		local _, carrier = templates(a, nil, dependencies(a, function () return active end))
		carrier.name = "recipe_test_carrier"
		local fixed = { get_latest_fixed_frame = function () return 1 end, get_latest_fixed_time = function () return 0 end }
		local engine_math = table.shallow_copy(math)
		engine_math.clamp = function (v, lo, hi) return math.max(lo, math.min(hi, v)) end
		engine_math.clamp01 = function (v) return engine_math.clamp(v, 0, 1) end
		local modules = {
			["scripts/settings/buff/buff_settings"] = real_settings,
			["scripts/utilities/fixed_frame"] = fixed,
			["scripts/extension_systems/buff/utility/buff_args"] = { add_args_to_context = function () end },
		}
		local Buff = engine_file("scripts/extension_systems/buff/buffs/buff", modules, {
			class = function () return {} end, math = engine_math,
			ScriptUnit = { has_extension = function () return nil end },
		})
		function Buff:new(context, template, t, id)
			local instance = setmetatable({}, { __index = self })
			instance:init(context, template, t, id)
			return instance
		end
		function Buff:delete() self.__deleted = true end
		modules["scripts/settings/buff/buff_classes"] = { buff = Buff }
		modules["scripts/extension_systems/buff/buff_extension_interface"] = {}
		local Extension = engine_file("scripts/extension_systems/buff/buff_extension_base", modules, {
			class = function () return {} end, implements = function () end,
			Script = { new_array = function () return {} end },
			Network = { type_info = function () return { max_size = 1000 } end }, Unit = {}, WwiseWorld = {},
		})
		local ext = setmetatable({
			_is_server = false, _is_hub = true, _index = 0, _buff_instance_id = 0,
			_stacking_buffs = {}, _buffs = {}, _buffs_by_index = {}, _buff_context = {},
			_proc_on_buff_event = function () end,
			_remove_internally_controlled_buff = Extension._remove_buff,
		}, { __index = Extension })
		local function add(t)
			if ext:_check_max_stacks_cap(carrier, t) then ext:_add_buff(carrier, t, false) end
		end
		add(0)
		local buff = ext._stacking_buffs[carrier.name]
		for t = 1, 4 do add(t) end
		a.eq(buff:stack_count(), 5)
		add(9)
		a.eq(buff:stack_count(), 5, "cap holds"); a.eq(buff:start_time(), 9, "cap refreshes timer")
		local stats = { attack_speed = 1, _modified_stats = {} }
		buff:update_stat_buffs(stats, 9)
		a.truthy(math.abs(stats.attack_speed - 1.1) < 1e-9, "five two-percent stacks yield ten percent")
		active = false
		stats = { attack_speed = 1, _modified_stats = {} }
		buff:update_stat_buffs(stats, 9)
		a.eq(stats.attack_speed, 1, "session gate removes stats")
		active = true
		ext:_update_buffs(0.1, 18.9, 1)
		a.eq(buff:stack_count(), 5, "no premature expiry")
		ext:_update_buffs(0.2, 19.1, 2)
		a.nil_(ext._stacking_buffs[carrier.name], "whole stack group expires")
		a.count(ext._buffs, 0)
		add(20)
		a.eq(ext._stacking_buffs[carrier.name]:stack_count(), 1, "new cycle starts with one stack")
	end },
	{ "text file IO creates only missing files, bounds reads and keeps existing input intact", function (a)
		local module = harness.load("user_buffs")
		local writes, closes = 0, 0
		local io_lib = { open = function (_, mode)
			if mode == "rb" then return nil, "missing", 2 end
			return { write = function (_, text)
				writes = writes + 1
				local parsed, errors = recipes.parse(text)
				a.count(parsed, 0, "starter grants no buffs"); a.count(errors, 0)
				return true
			end, close = function () closes = closes + 1; return true end }
		end }
		a.truthy(module.read_file(io_lib, "test.txt")); a.eq(writes, 1); a.eq(closes, 1)
		io_lib.open = function (_, mode)
			a.eq(mode, "rb", "permission failure never opens for writing")
			return nil, "denied", 13
		end
		local text, err = module.read_file(io_lib, "test.txt")
		a.nil_(text); a.eq(err, "denied")
		io_lib.open = function (_, mode)
			a.eq(mode, "rb")
			return { read = function (_, size) a.eq(size, 65537); return BASE end, close = function () end }
		end
		a.eq(module.read_file(io_lib, "test.txt"), BASE)
	end },
	{ "singleplay gates reject Realms even alone, disabled mods and teardown", function (a)
		local module = harness.load("user_buffs")
		local types = require("scripts/settings/network/matchmaking_constants").HOST_TYPES
		local old_session, old_enabled, old_authority, old_peers = Managers.multiplayer_session,
			harness.mod.is_enabled, harness.mod.has_authority, harness.mod.has_peers
		local current_type, enabled, authority, peers = types.singleplay, true, true, false
		Managers.multiplayer_session = { host_type = function () return current_type end }
		harness.mod.is_enabled = function () return enabled end
		harness.mod.has_authority = function () return authority end
		harness.mod.has_peers = function () return peers end
		harness.mod.manager = {}
		harness.mod._user_buffs.names.recipe_test = true
		local ok, err = pcall(function ()
			a.truthy(module.active()); a.truthy(module.can_grant("recipe_test"))
			for _, host_type in ipairs({ types.player, types.mission_server }) do
				current_type = host_type
				a.falsy(module.active()); a.falsy(module.can_grant("recipe_test"))
				local exclude = { unrelated = true }
				module.exclude(exclude)
				a.truthy(exclude.recipe_test); a.truthy(exclude.unrelated)
			end
			current_type = types.singleplay
			peers = true; a.falsy(module.active()); peers = false
			enabled = false; a.falsy(module.active()); enabled = true
			authority = false; a.falsy(module.active()); authority = true
			harness.mod.manager = nil; a.falsy(module.active())
			a.truthy(module.can_grant("normal_addon_buff"), "other buffs unaffected")
		end)
		Managers.multiplayer_session = old_session
		harness.mod.is_enabled, harness.mod.has_authority, harness.mod.has_peers = old_enabled, old_authority, old_peers
		if not ok then error(err, 0) end
	end },
	{ "startup reads once and singleplay installs saved recipes into reserved slots without reloads", function (a)
		local old_mods, old_get_mod, old_require = Mods, get_mod, require
		local reads, registrations, invalidations, registered = 0, 0, 0, {}
		Mods = { lua = { io = { open = function (path, mode)
			a.eq(path, "/fake/ChaosWastesAtHome/buffs.txt"); a.eq(mode, "rb")
			reads = reads + 1
			return { read = function () return BASE .. "\n[broken]\namount = nope\n" end, close = function () end }
		end } } }
		get_mod = function (name)
			if name == "DMF" then return { deepcopy = table.shallow_copy } end
			return old_get_mod(name)
		end
		require = function (path)
			if path == "scripts/settings/buff/buff_settings" then return real_settings end
			if path == "scripts/settings/buff/helper_functions/check_proc_functions" then return real_checks end
			return old_require(path)
		end
		local ok, err = pcall(function ()
			local module = harness.load("user_buffs")
			local registry = {
				register_buffs = function (_, entries, opts)
					registrations = registrations + 1
					a.eq(opts.category, "cwah_player_buffs"); a.count(entries, 128)
					for _, entry in ipairs(entries) do registered[entry.id] = entry end
					return #entries, {}
				end,
				buff_id = function (_, id) return id end,
				entry = function (id) return registered[id] end,
			}
			local loadouts = {
				directory = function () return "/fake/ChaosWastesAtHome/loadouts/" end,
				ensure_dir = function () return true end,
			}
			local pool = { invalidate = function () invalidations = invalidations + 1 end }
			module.load(loadouts, registry, pool)
			module.load(loadouts, registry, pool)
			a.eq(reads, 1); a.eq(registrations, 1); a.eq(invalidations, 1)
			module.can_replace = function () return true end
			module.update()
			a.eq(registrations, 2)
			a.eq(harness.mod._user_buffs.count, 1)
			a.truthy(#harness.mod._user_buffs.errors > 0)
			a.truthy(harness.mod._user_buffs.names.player_slot_01_recipe)
			a.truthy(harness.mod._user_buffs.names.player_slot_01_stack)
			a.falsy(module.can_grant(module.name("momentum")), "recipe cannot be granted outside a run")
		end)
		Mods, get_mod, require = old_mods, old_get_mod, old_require
		if not ok then error(err, 0) end
	end },
}
