local mod = get_mod("ChaosWastesAtHome")
local difficulty = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/difficulty")
local Circumstances = require("scripts/settings/circumstance/circumstance_templates")

-- View adapter for the same catalogue and settings used by mission rolls.
local pool = {}
pool.is_enabled = difficulty.is_havoc_circumstance_enabled
pool.set_enabled = function (id, enabled)
	difficulty.set_havoc_circumstances_enabled({ id }, enabled)
end
pool.set_group_enabled = function (group, enabled)
	difficulty.set_havoc_circumstances_enabled(group.names, enabled)
end
pool.groups = function ()
	return { { id = "havoc", label = mod:localize("tab_havoc_modifiers"), names = difficulty.havoc_circumstance_pool() } }
end
pool.group_counts = function (group)
	local enabled = 0
	for _, id in ipairs(group.names) do
		if pool.is_enabled(id) then enabled = enabled + 1 end
	end
	return enabled, #group.names
end
pool.disabled_count = function ()
	local enabled, total = pool.group_counts(pool.groups()[1])
	return total - enabled
end
local function localized(key, fallback)
	if not key then return fallback end
	local ok, text = pcall(Localize, key)
	return ok and text and text ~= "" and text:sub(1, 1) ~= "<" and text or fallback
end
pool.title = function (id)
	local template = Circumstances[id]
	return localized(template and template.ui and template.ui.display_name, id)
end
pool.details = function (id)
	local template = Circumstances[id]
	if not template then return nil end
	local ui = template.ui or {}
	return {
		title = pool.title(id),
		description = localized(ui.description, mod:localize("buff_no_description")),
		icon = ui.icon,
	}
end

return pool
