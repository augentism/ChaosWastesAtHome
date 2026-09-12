local harness = ...

local function scenario(reverse)
	return function (a)
		local templates = require("scripts/settings/buff/buff_templates")
		local data = require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")
		local generic = require("scripts/managers/mission_buffs/mission_buffs_allowed_buffs").legendary_buffs.generic
		local old_lookup = NetworkLookup
		NetworkLookup = { buff_templates = {} }
		local length = #generic
		local registry = harness.load("buff_registry")
		local owners = reverse and { "OtherPack", "TestPack" } or { "TestPack", "OtherPack" }
		local built, granted = {}, {}
		local ok, err = pcall(function ()
			for _, owner in ipairs(owners) do
				local entries = {
					{ id = "damage", pool = true, title = { en = owner }, description = { en = "A card." },
						template = function (context)
							built[owner] = (built[owner] or 0) + 1
							return { name = "damage", class_name = "buff", proc_func = function ()
								granted[owner] = context.resolve("helper")
							end }
						end },
					{ id = "helper", stat_buffs = {} },
					{ id = "upgrade", pool = true, upgrade_of = "damage", requires_all = { "helper" },
						requires_any = { "damage" }, stat_buffs = {}, title = { en = "Upgrade" }, description = { en = "Upgrade." } },
				}
				local count, problems = registry.register_buffs(owner, entries)
				a.eq(count, 3, "all entries accepted")
				a.count(problems, 0, "no collisions")
				a.eq(entries[1].id, "damage", "source catalogue unchanged")
				a.eq(entries[3].upgrade_of, "damage", "source prerequisite unchanged")
				a.eq(built[owner], 1, "factory invoked once")
			end
			for _, owner in ipairs(owners) do
				local id = registry.buff_id(owner, "damage")
				local helper = registry.buff_id(owner, "helper")
				local upgrade = registry.buff_id(owner, "upgrade")
				a.eq(templates[id].name, id, "template stacking identity")
				a.eq(NetworkLookup.buff_templates[NetworkLookup.buff_templates[id]], id, "network round trip")
				a.contains(generic, id, "card in pool")
				a.not_contains(generic, helper, "helper not offered")
				a.eq(harness.global_localization[data[id].title].en, owner, "independent title")
				templates[id].proc_func()
				a.eq(granted[owner], helper, "callback resolves own helper")
				a.truthy(registry.is_unlocked(upgrade, { [id] = true, [helper] = true }), "own prerequisite unlocks")
				local other = owner == "TestPack" and "OtherPack" or "TestPack"
				a.falsy(registry.is_unlocked(upgrade, {
					[registry.buff_id(other, "damage")] = true, [registry.buff_id(other, "helper")] = true,
				}), "other pack cannot unlock upgrade")
			end
			a.neq(registry.buff_id("a_b", "c"), registry.buff_id("a", "b_c"), "unambiguous owner boundary")
		end)
		for _, owner in ipairs(owners) do
			for _, local_id in ipairs({ "damage", "helper", "upgrade" }) do
				local id = registry.buff_id(owner, local_id)
				templates[id], data[id] = nil, nil
			end
		end
		for i = #generic, length + 1, -1 do generic[i] = nil end
		NetworkLookup = old_lookup
		if not ok then error(err, 0) end
	end
end

return {
	{ "same local IDs coexist with independent helpers, text and prerequisites", scenario(false) },
	{ "same local IDs also coexist in reverse registration order", scenario(true) },
}
