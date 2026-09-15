-- Native DMF controls, built before the main script runs. All values are drafts;
-- only the explicit Save button writes buffs.txt.
local mod = get_mod("ChaosWastesAtHome")
local recipes = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/buff_recipes")
local widgets = {}

widgets.labels = {
	recipe_editor = "Player Buff Editor",
	recipe_editor_description = "Build your own buffs. Save updates your personal file and menu; an open run or preparation lobby keeps its existing catalogue until you leave. Saves normalize the file and preserve its previous contents as buffs.txt.bak.",
	recipe_editor_new = "New buff", recipe_editor_browse = "Browse saved buffs",
	recipe_editor_load = "Load entered ID", recipe_editor_preview = "Validate / preview",
	recipe_editor_save = "Save buff", recipe_editor_delete = "Delete saved buff",
	recipe_editor_reload = "Reload from disk",
	recipe_editor_id = "Stable ID", recipe_editor_id_description = "1–48 lowercase letters, digits or underscores; start with a letter. Use Browse to edit an existing buff. Changing the ID renames the selected recipe.",
	recipe_editor_name = "Display name", recipe_editor_trigger = "Trigger",
	recipe_editor_effect = "Effect", recipe_editor_amount = "Strength per stack (%%)",
	recipe_editor_max_stacks = "Maximum stacks", recipe_editor_duration = "Duration (seconds)",
	recipe_editor_chance = "Trigger chance (%%)", recipe_editor_cooldown = "Trigger cooldown (seconds)",
	recipe_editor_enabled = "Include in your catalogue",
	recipe_editor_amount_description = "Percent bonus, or percentage points for critical chance. Total strength is validated against the chosen effect when saving.",
	recipe_editor_duration_description = "Each successful trigger adds one stack and refreshes the shared timer, including at the stack cap.",
}

local function options(kind)
	local out = {}
	for id in pairs(recipes[kind .. "s"]) do
		out[#out + 1] = { text = string.format("recipe_%s_%s", kind, id), value = id }
	end
	table.sort(out, function (a, b) return a.value < b.value end)
	return out
end

widgets.localizations = function ()
	local out = {}
	for key, label in pairs(widgets.labels) do out[key] = { en = label } end
	for _, kind in ipairs({ "trigger", "effect" }) do
		for id in pairs(recipes[kind .. "s"]) do
			out["recipe_" .. kind .. "_" .. id] = { en = id:gsub("_", " "):gsub("^%l", string.upper) }
		end
	end
	return out
end

widgets.group = function ()
	local rows = {}
	local function button(action)
		local key = "recipe_editor_" .. action
		rows[#rows + 1] = { setting_id = key, type = "button", button_text = key, button_trigger = "pressed", function_name = key }
	end
	button("browse"); button("new")
	for _, spec in ipairs({ { "id", "new_buff", 48 }, { "name", "New buff", 120 } }) do
		rows[#rows + 1] = { setting_id = string.format("recipe_editor_%s", spec[1]), type = "text", default_value = spec[2], max_length = spec[3] }
	end
	button("load")
	for _, spec in ipairs({ { "trigger", "dodge" }, { "effect", "movement_speed" } }) do
		rows[#rows + 1] = { setting_id = string.format("recipe_editor_%s", spec[1]), type = "dropdown", default_value = spec[2], options = options(spec[1]) }
	end
	for _, spec in ipairs({
		{ "amount", 2, 0.01, 500, 2 }, { "max_stacks", 3, 1, 31, 0 },
		{ "duration", 10, 0.1, 600, 1 }, { "chance", 100, 0.01, 100, 2 }, { "cooldown", 0, 0, 600, 1 },
	}) do
		rows[#rows + 1] = { setting_id = string.format("recipe_editor_%s", spec[1]), type = "numeric", default_value = spec[2],
			range = { spec[3], spec[4] }, decimals_number = spec[5] }
	end
	rows[#rows + 1] = { setting_id = "recipe_editor_enabled", type = "checkbox", default_value = true }
	button("preview"); button("save"); button("delete"); button("reload")
	return { setting_id = "recipe_editor", type = "group", sub_widgets = rows }
end

return widgets
