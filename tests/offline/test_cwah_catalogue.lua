-- Adapt the fork's catalogue/localization checks to the original CwahBuffs.
-- No MourningBound modules or buff definitions are loaded by these tests.
local harness = ...

local function with_catalogue(check)
	return function (a)
		local settings = require("scripts/settings/buff/buff_settings")
		local profiles = require("scripts/settings/damage/damage_profile_templates")
		local saved = {}
		for _, key in ipairs({ "stat_buffs", "buff_categories", "proc_events", "keywords" }) do
			saved[key] = settings[key]
			settings[key] = settings[key] or setmetatable({}, { __index = function (_, name) return name end })
		end
		local old_default, old_get_mod, old_class = profiles.default, get_mod, CLASS
		profiles.default, CLASS = profiles.default or {}, {}
		local entries, counts, calls = {}, {}, 0
		local core = {
			buff_proc_counters = function () return counts end,
			subscribe = function () end,
			register_buff_reading = function () end,
			is_host = function () return false end,
			register_buffs = function (_, catalogue)
				calls = calls + 1
				for _, entry in ipairs(catalogue) do
					a.nil_(entries[entry.id], "unique card/helper ID")
					entries[entry.id] = entry
				end
			end,
		}
		local addon = setmetatable({}, { __index = harness.mod })
		local modules = {}
		function addon:io_dofile(path)
			local result = harness.mod:io_dofile(path)
			modules[path:match("([^/]+)$")] = result
			return result
		end
		function addon:get_name() return "CwahBuffs" end
		get_mod = function (name)
			if name == "CwahBuffs" then return addon end
			if name == "ChaosWastesAtHome" then return core end
			error("unexpected addon dependency: " .. name)
		end
		local ok, err = pcall(function ()
			local pack = harness.mod:io_dofile("CwahBuffs/scripts/mods/CwahBuffs/catalogue")
			pack.register()
			pack.register()
			a.eq(calls, 1, "repeat registration is idempotent")
			check(a, entries, counts, modules)
		end)
		for key in pairs({ stat_buffs = true, buff_categories = true, proc_events = true, keywords = true }) do settings[key] = saved[key] end
		profiles.default, get_mod, CLASS = old_default, old_get_mod, old_class
		if not ok then error(err, 0) end
	end
end

return {
	{ "Flayer blocks direct recursion but allows the lightning callback during its burst", with_catalogue(function (a, entries, counts, modules)
		local attack = require("scripts/utilities/attack/attack")
		local impact = require("scripts/utilities/attack/impact_effect")
		local profiles = require("scripts/settings/damage/damage_profile_templates")
		local types = require("scripts/settings/damage/attack_settings").attack_types
		local damage_types = require("scripts/settings/damage/damage_settings").damage_types
		local old = { execute = attack.execute, play = impact.play, profile = profiles.psyker_smite_kill,
			alive = HEALTH_ALIVE, unit = Unit, script = ScriptUnit, vector = Vector3, random = math.random }
		local target, player = {}, {}
		local pos = setmetatable({}, { __sub = function (x) return x end })
		local calls, impacts = 0, 0
		local ok, err = pcall(function ()
			profiles.psyker_smite_kill = { name = "psyker_smite_kill", damage = {} }
			HEALTH_ALIVE = { [target] = true }
			Unit = { world_position = function () return pos end }
			Vector3 = { normalize = function (x) return x end }
			ScriptUnit = { has_extension = function (_, system)
				if system == "buff_system" then return {
					current_stacks = function () return 0 end,
					has_buff_using_buff_template = function (_, id) return id == "cwah_flayer" end,
				} end
			end }
			math.random = function () return 0 end
			local flayer = entries.cwah_flayer.template()
			local chain = entries.cwah_arc_chain.template()
			impact.play = function () impacts = impacts + 1 end
			attack.execute = function (unit, profile, ...)
				calls = calls + 1
				local args, params = { ... }, { attacked_unit = unit, damage_profile = profile }
				for i = 1, select("#", ...), 2 do params[args[i]] = args[i + 1] end
				a.neq(profile, profiles.psyker_smite_kill, "private profile")
				a.eq(profile.name, "psyker_smite_kill", "stock lookup name")
				a.eq(profile.damage, profiles.psyker_smite_kill.damage, "unchanged damage settings")
				a.eq(params.attack_type, types.ranged); a.eq(params.damage_type, damage_types.smite)
				a.eq(params.attacking_unit, player); a.eq(params.power_level, 500)
				a.falsy(flayer.check_proc_func(params), "direct self-proc rejected")
				a.truthy(chain.check_proc_func(params, { broadphase = {}, enemy_side_names = {},
					window_start = 0, window_count = 0 }, {}, 0), "Flayer may trigger lightning")
				if calls == 1 then modules.arc_chain.on_arc_hit(player, target, 0) end
				return 10, "damaged", 1
			end
			flayer.proc_func({ attacked_unit = target }, {}, { unit = player })
			a.eq(calls, 2, "arc callback can burst during another Flayer burst")
			a.eq(impacts, 2); a.eq(counts.cwah_flayer, 2)
			a.truthy(flayer.check_proc_func({ attacked_unit = target, attack_type = types.ranged, damage_profile = profiles.psyker_smite_kill }), "normal Brain Burst remains eligible")
			a.falsy(flayer.check_proc_func({ attack_type = types.buff }), "secondary bursts and DoTs remain excluded")
			local previous_extension = ScriptUnit.has_extension
			ScriptUnit.has_extension = function (unit, system)
				if system == "unit_data_system" then return { breed = function () return { name = "chaos_poxwalker_bomber" } end } end
				return previous_extension(unit, system)
			end
			a.falsy(flayer.check_proc_func({ attacked_unit = target, attack_type = types.ranged }), "Poxburster hit excluded")
			flayer.proc_func({ attacked_unit = target }, {}, { unit = player })
			modules.arc_chain.on_arc_hit(player, target, 0)
			a.eq(calls, 2, "neither hit nor arc can burst a Poxburster")
			a.eq(counts.cwah_flayer, 2, "excluded targets do not count as procs")
			ScriptUnit.has_extension = previous_extension
			HEALTH_ALIVE[target] = nil
			flayer.proc_func({ attacked_unit = target }, {}, { unit = player })
			a.eq(calls, 2, "dead target cannot burst")
		end)
		attack.execute, impact.play, profiles.psyker_smite_kill = old.execute, old.play, old.profile
		HEALTH_ALIVE, Unit, ScriptUnit, Vector3, math.random = old.alive, old.unit, old.script, old.vector, old.random
		if not ok then error(err, 0) end
	end) },
	{ "original nine cards and three hidden helpers remain available", with_catalogue(function (a, entries)
		a.size(entries, 12)
		for _, id in ipairs({ "custom_damage", "custom_toughness_on_elite_kill", "crit_ramp", "attack_speed_ramp",
			"status_cascade", "flayer", "proliferation", "arc_chain", "multishot" }) do
			a.truthy(entries["cwah_" .. id].pool, "offered card " .. id)
		end
		for _, id in ipairs({ "crit_ramp_stack", "attack_speed_ramp_stack", "arc_shock" }) do
			a.falsy(entries["cwah_" .. id].pool, "hidden helper " .. id)
		end
		a.truthy(entries.cwah_custom_damage.default_off, "damage remains opt-in")
	end) },
	{ "all original card translations survive both formatting passes", with_catalogue(function (a, entries)
		local expected = {
			custom_damage = { "15%" }, custom_toughness_on_elite_kill = { "15%" },
			crit_ramp = { "5%" }, attack_speed_ramp = { "2%", "20%", "2" },
			status_cascade = {}, flayer = { "10%" }, proliferation = {},
			arc_chain = { "25%", "3", "1" }, multishot = { "5" },
		}
		for id, values in pairs(expected) do
			local entry = entries["cwah_" .. id]
			for _, language in ipairs({ "en", "zh-cn" }) do
				a.truthy(entry.title[language]); a.truthy(entry.description[language])
			end
			for _, field in ipairs({ "title", "description" }) do
				for language, text in pairs(entry[field]) do
					local registered = entry.values and string.format(text, unpack(entry.values)) or text
					local rendered = string.format(registered)
					a.gt(#rendered, 0, id .. " " .. language)
					a.falsy(rendered:find("%%", 1, true), "escaped percentages resolved")
					if field == "description" then
						for _, value in ipairs(values) do a.truthy(rendered:find(value, 1, true), id .. " displays " .. value) end
					end
				end
			end
		end
	end) },
	{ "crit ramp accepts non-crits and configures a bounded resettable helper", with_catalogue(function (a, entries)
		local controller = entries.cwah_crit_ramp.template()
		local helper = entries.cwah_crit_ramp_stack.template()
		a.truthy(controller.check_proc_func({ is_critical_strike = false }))
		a.falsy(controller.check_proc_func({ is_critical_strike = true }))
		local added = {}
		controller.proc_func({}, { buff_extension = { add_internally_controlled_buff = function (_, id, t)
			added[#added + 1] = { id, t }
		end } }, {}, 7)
		a.eq(added[1][1], "cwah_crit_ramp_stack"); a.eq(added[1][2], 7)
		a.eq(helper.max_stacks, 20); a.eq(helper.max_stacks_cap, 20)
		a.eq(helper.stat_buffs.critical_strike_chance, 0.05)
		a.truthy(helper.remove_on_proc); a.nil_(helper.buff_category)
	end) },
	{ "attack speed ramp stays bounded and attacks refresh its idle reset", with_catalogue(function (a, entries)
		local helper = entries.cwah_attack_speed_ramp_stack.template()
		a.eq(helper.max_stacks, 10); a.eq(helper.max_stacks_cap, 10)
		a.eq(helper.stat_buffs.attack_speed, 0.02)
		local data, context = {}, { buff = { start_time = function () return 10 end } }
		helper.start_func(data, context)
		a.falsy(helper.conditional_exit_func(data, context, 0, 12), "exact boundary retained")
		a.truthy(helper.conditional_exit_func(data, context, 0, 12.01), "idle expires")
		for _, event in ipairs({ "on_hit", "on_shoot", "on_sweep_finish" }) do
			a.eq(helper.proc_events[event], 1, "attack refresh event")
			helper.proc_func({}, data, context, 20)
			a.falsy(helper.conditional_exit_func(data, context, 0, 21.99))
			a.truthy(helper.conditional_exit_func(data, context, 0, 22.01))
		end
	end) },
}
