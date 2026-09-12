local harness = ...
local HAVOC = "scripts/settings/circumstance/templates/havoc_circumstance_template"
local CIRCUMSTANCES = "scripts/settings/circumstance/circumstance_templates"
local MUTATORS = "scripts/settings/mutator/mutator_templates"

-- Real circumstance declarations with controlled mutator availability. Loading
-- the engine's mutator registry itself needs native Odin and engine enums.
local function fixture(a)
	a.truthy(harness.engine_loaded(HAVOC), "real Havoc catalogue loaded")
	local definitions = require(HAVOC)
	local registry = {}
	for _, template in pairs(definitions) do
		for _, id in ipairs(template.mutators) do registry[id] = {} end
	end
	local env = setmetatable({ math = table.shallow_copy(math) }, { __index = _G })
	env.require = function (path)
		if path == MUTATORS then return registry end
		if path == CIRCUMSTANCES then return definitions end
		return require(path)
	end
	local chunk = assert(loadfile(harness.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/difficulty.lua"))
	return setfenv(chunk, env)(), registry, env, definitions
end

return {
	{ "Havoc selections support all, one and no random modifiers", function (a)
		local difficulty = fixture(a)
		local pool = difficulty.havoc_circumstance_pool()
		harness.mod:set("havoc_theme_chance", 0)
		for _, id in ipairs(pool) do a.truthy(difficulty.is_havoc_circumstance_enabled(id)) end
		difficulty.set_havoc_circumstances_enabled(pool, false)
		local stored = harness.mod:get(difficulty.HAVOC_DISABLED_SETTING)
		a.eq(#stored, 0, "name-keyed settings, no mixed array")
		local _, _, _, none = difficulty.build_havoc_data(30, "km_enforcer")
		a.count(none, 1); a.eq(none[1], "mutator_highest_difficulty")
		difficulty.set_havoc_circumstances_enabled({ pool[1] }, true)
		a.nil_(harness.mod:get(difficulty.HAVOC_DISABLED_SETTING)[pool[1]])
		local _, _, _, one = difficulty.build_havoc_data(30, "km_enforcer")
		a.count(one, 2); a.eq(one[1], pool[1])
		difficulty.set_havoc_circumstances_enabled(pool, true)
		a.size(harness.mod:get(difficulty.HAVOC_DISABLED_SETTING), 0)
		local _, _, _, all = difficulty.build_havoc_data(30, "km_enforcer")
		a.count(all, 3); a.neq(all[1], all[2])
	end },
	{ "older loadouts reset Havoc exclusions and new loadouts restore them", function (a)
		local env = setmetatable({
			get_mod = function (name)
				if name == "DMF" then return { persistent_table = function () return { initialized = true } end } end
				return harness.mod
			end,
			Application = { user_setting = function () return { ChaosWastesAtHome = {} } end },
		}, { __index = _G })
		local chunk = assert(loadfile(harness.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/loadouts.lua"))
		local loadouts = setfenv(chunk, env)()
		local difficulty = fixture(a)
		local id = difficulty.havoc_circumstance_pool()[1]
		difficulty.set_havoc_circumstances_enabled({ id }, false)
		a.truthy(loadouts.snapshot().disabled_havoc_circumstances[id], "snapshot includes unflushed selector")
		a.truthy(loadouts.apply({ disabled_havoc_circumstances = {} }))
		a.truthy(difficulty.is_havoc_circumstance_enabled(id))
		a.truthy(loadouts.apply({ disabled_havoc_circumstances = { [id] = true } }))
		a.falsy(difficulty.is_havoc_circumstance_enabled(id))
		a.truthy(loadouts.apply({}))
		a.truthy(difficulty.is_havoc_circumstance_enabled(id))
	end },
	{ "Havoc pool includes every available non-environment circumstance", function (a)
		local difficulty, _, _, definitions = fixture(a)
		local pool = difficulty.havoc_circumstance_pool()
		a.gt(#pool, 4, "expanded beyond original pool")
		for id in pairs(definitions) do
			if id == "mutator_increased_difficulty" or id == "mutator_highest_difficulty" then
				a.not_contains(pool, id)
			else
				a.contains(pool, id, "available Havoc circumstance")
			end
		end
		for _, id in ipairs({ "mutator_havoc_rotten_armor", "mutator_stimmed_minions",
			"bolstering_minions_01", "mutator_havoc_enraged", "mutator_havoc_chaos_rituals",
			"mutator_encroaching_garden" }) do a.contains(pool, id, "newer modifier") end
	end },
	{ "Havoc excludes a circumstance when any required mutator is missing", function (a)
		local difficulty, registry = fixture(a)
		registry.mutator_no_witches = nil
		local pool = difficulty.havoc_circumstance_pool()
		a.not_contains(pool, "mutator_havoc_chaos_rituals", "partially available combination rejected")
		a.contains(pool, "mutator_encroaching_garden", "unrelated modifier retained")
		registry.mutator_no_witches = {}
		a.contains(difficulty.havoc_circumstance_pool(), "mutator_havoc_chaos_rituals", "registry changes respected")
	end },
	{ "every Havoc candidate can reach the serialized mission without duplicates", function (a)
		local difficulty, _, env = fixture(a)
		local pool = difficulty.havoc_circumstance_pool()
		harness.mod:set("havoc_theme_chance", 0)
		for index, id in ipairs(pool) do
			local calls = 0
			env.math.random = function ()
				calls = calls + 1
				-- First draw is faction; second selects the first circumstance.
				return calls == 2 and index or 1
			end
			local data, _, _, circumstances = difficulty.build_havoc_data(30, "km_enforcer")
			a.eq(circumstances[1], id, "candidate is reachable")
			a.neq(circumstances[1], circumstances[2], "two distinct modifiers")
			a.count(circumstances, 3, "two rolls plus Fading Light")
			a.eq(circumstances[3], "mutator_highest_difficulty")
			a.truthy(data:find(";default;", 1, true), "environment chance respected")
			a.truthy(data:find(";" .. table.concat(circumstances, ":") .. ";", 1, true), "serialized roll matches card")
		end
	end },
}
