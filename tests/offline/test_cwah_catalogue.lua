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
			check(a, entries, counts)
		end)
		for key in pairs({ stat_buffs = true, buff_categories = true, proc_events = true, keywords = true }) do settings[key] = saved[key] end
		profiles.default, get_mod, CLASS = old_default, old_get_mod, old_class
		if not ok then error(err, 0) end
	end
end

return {
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
