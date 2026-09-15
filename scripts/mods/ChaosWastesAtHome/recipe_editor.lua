local mod = get_mod("ChaosWastesAtHome")
if mod.recipe_editor then return mod.recipe_editor end
local editor = { dirty = false }
mod.recipe_editor = editor
local fields = { "id", "name", "trigger", "effect", "amount", "max_stacks", "duration", "chance", "cooldown", "enabled" }
-- Retain the script-facing draft API; the visible editor now owns a local draft.
for key, value in pairs({id="new_buff",name="New buff",trigger="dodge",effect="movement_speed",amount=2,
	max_stacks=3,duration=10,chance=100,cooldown=0,enabled=true}) do
	if mod:get("recipe_editor_"..key)==nil then mod:set("recipe_editor_"..key,value,false) end
end

local function popup(message, options)
	editor.message = message
	if Managers and Managers.event then
		if editor.popup_id then Managers.event:trigger("event_remove_ui_popup", editor.popup_id); editor.popup_id = nil end
		Managers.event:trigger("event_show_ui_popup", {
			title_text_unlocalized = "Player Buff Editor", description_text_unlocalized = message,
			options = options or { { text = "loc_popup_button_close", close_on_pressed = true, hotkey = "back" } },
		}, function (id) editor.popup_id = id end)
	else mod:echo("%s", message:gsub("%%", "%%%%")) end
end

local function option(text, action)
	return { text = text, no_localization = true, close_on_pressed = true, callback = action }
end

local function discard_then(action)
	if not editor.dirty then return action() end
	popup("Discard unsaved changes to this draft?", {
		option("Discard draft", function () editor.dirty = false; action() end),
		{ text = "loc_popup_button_cancel", close_on_pressed = true, hotkey = "back" },
	})
end

editor.draft = function ()
	local draft = {}
	for _, field in ipairs(fields) do draft[field] = mod:get("recipe_editor_" .. field) end
	return draft
end

editor.select = function (definition, saved)
	for _, field in ipairs(fields) do mod:set("recipe_editor_" .. field, definition[field], false) end
	editor.original_id, editor.dirty = saved and definition.id or nil, false
end

editor.changed = function (setting_id)
	if setting_id:sub(1, 14) ~= "recipe_editor_" then return false end
	editor.dirty = true
	return true
end

editor.new = function ()
	discard_then(function ()
		editor.select({ id = "new_buff", name = "New buff", trigger = "dodge", effect = "movement_speed",
			amount = 2, max_stacks = 3, duration = 10, chance = 100, cooldown = 0, enabled = true }, false)
	end)
end

editor.load = function ()
	local id = mod:get("recipe_editor_id")
	discard_then(function ()
		for _, definition in ipairs(mod.user_buffs.definitions()) do
			if definition.id == id then editor.select(definition, true); return end
		end
		popup("No saved recipe has ID '" .. tostring(id) .. "'.")
	end)
end

editor.browse = function (page)
	local function show()
		local definitions, errors = mod.user_buffs.definitions()
		if #errors > 0 then popup(table.concat(errors, "\n")); return end
		if #definitions == 0 then popup("No saved buffs yet. Choose New buff to create one."); return end
		page = math.max(1, math.min(page or 1, math.ceil(#definitions / 5)))
		local options = {}
		for i = (page - 1) * 5 + 1, math.min(page * 5, #definitions) do
			local definition = definitions[i]
			options[#options + 1] = option(definition.name .. " [" .. definition.id .. "]" .. (definition.enabled and "" or " (disabled)"),
				function () editor.select(definition, true) end)
		end
		if page > 1 then options[#options + 1] = option("Previous page", function () editor.browse(page - 1) end) end
		if page * 5 < #definitions then options[#options + 1] = option("Next page", function () editor.browse(page + 1) end) end
		options[#options + 1] = { text = "loc_popup_button_close", close_on_pressed = true, hotkey = "back" }
		popup("Choose a saved buff (page " .. page .. "). This edits your personal file, never the host's catalogue.", options)
	end
	discard_then(show)
end

editor.preview = function ()
	local definition, message = mod.user_buffs.validate_definition(editor.draft())
	popup((definition and (definition.name .. "\n\n") or "Invalid buff\n\n") .. tostring(message))
end

editor.save = function ()
	local draft = editor.draft()
	local ok, message = mod.user_buffs.save_definition(draft, editor.original_id)
	if ok then editor.original_id, editor.dirty = draft.id, false end
	popup((ok and "" or "Could not save: ") .. tostring(message))
	return ok, message
end

editor.delete = function ()
	local id = editor.original_id
	if not id then popup("Browse and select a saved buff before deleting."); return end
	popup("Delete saved buff '" .. id .. "'? Its active session copy, if any, remains until that session ends.", {
		option("Delete buff", function ()
			local ok, message = mod.user_buffs.delete_definition(id)
			if ok then editor.dirty = false; editor.new() end
			popup((ok and "" or "Could not delete: ") .. tostring(message))
		end),
		{ text = "loc_popup_button_cancel", close_on_pressed = true, hotkey = "back" },
	})
end

editor.reload = function ()
	discard_then(function ()
		local ok, message = mod.user_buffs.reload()
		if ok then editor.original_id, editor.dirty = nil, false end
		popup((ok and "" or "Could not reload: ") .. tostring(message))
	end)
end

for _, action in ipairs({ "new", "browse", "load", "preview", "save", "delete", "reload" }) do
	mod["recipe_editor_" .. action] = editor[action]
end

return editor
