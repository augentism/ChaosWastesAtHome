local harness = ...

local function fixture(a)
	local function model(prefix)
		local group = { id = prefix, label = prefix, names = { prefix .. "_one", prefix .. "_two" } }
		local disabled = {}
		local m = { invalidate = function () end, groups = function () return { group } end }
		m.is_enabled = function (id) return not disabled[id] end
		m.set_enabled = function (id, enabled) disabled[id] = not enabled or nil end
		m.set_group_enabled = function (g, enabled)
			for _, id in ipairs(g.names) do m.set_enabled(id, enabled) end
		end
		m.group_counts = function ()
			local count = 0
			for _, id in ipairs(group.names) do if m.is_enabled(id) then count = count + 1 end end
			return count, #group.names
		end
		m.disabled_count = function () return #group.names - m.group_counts() end
		m.title = function (id) return id end
		m.details = function (id) return { title = id, description = id, icon = "icon" } end
		return m
	end
	local buffs, havoc = model("buff"), model("havoc")
	local mod = setmetatable({}, { __index = harness.mod })
	function mod:io_dofile(path)
		if path:match("/buff_pool$") then return buffs end
		if path:match("/havoc_pool$") then return havoc end
		if path:match("/asset_loader$") then return { request = function () end, is_loaded = function () return true end } end
		return { attach = function () end }
	end
	local env = setmetatable({
		get_mod = function () return mod end,
		class = function () return { super = { on_enter = function () end } } end,
		callback = function (self, name) return function (...) return self[name](self, ...) end end,
		require = function (path)
			if path:match("/ui_widget$") then return { create_definition = function () return {} end } end
			if path:match("/ui_widget_grid$") then
				return { new = function () return {
					set_render_scale = function () end, assign_scrollbar = function () end,
					set_scrollbar_progress = function () end,
				} end }
			end
			return {}
		end,
	}, { __index = _G })
	local chunk = assert(loadfile(harness.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view.lua"))
	local class = setfenv(chunk, env)()
	local function widget()
		return { content = { hotspot = {} }, style = { text = {}, state_text = {}, icon = { material_values = {} } } }
	end
	local widgets = {}
	for _, id in ipairs({ "subtab_buffs", "subtab_havoc", "subtab_editor", "title_text", "family_pick_button", "enable_all_button",
		"disable_all_button", "reset_all_button", "summary_text", "detail_panel", "detail_icon", "detail_modifier_icon",
		"detail_title", "detail_subtitle", "detail_description", "detail_toggle_button" }) do widgets[id] = widget() end
	local row = { pass_template = {}, size = {}, init = function (_, w, entry) w.content.entry = entry end }
	local view = setmetatable({
		_pool = buffs, _group_widgets = {}, _group_rows_by_id = {}, _buff_widgets = {},
		_widgets_by_name = widgets, _definitions = { legend_inputs = {} },
		_blueprints = { group_row = row, buff_row = row }, _view_settings = { grid_spacing = {} },
		_blueprint_data = { color_on = {}, color_off = {}, color_title = {} },
		_ui_scenegraph = {},
	}, { __index = class })
	local registered = {}
	function view:_create_widget(name)
		a.nil_(registered[name], "no duplicate registered rows")
		local w = widget(); w.name = name; registered[name] = w
		return w
	end
	function view:_unregister_widget_name(name) registered[name] = nil end
	function view:_add_element() return { add_entry = function () end } end
	view:on_enter()
	return view, buffs, havoc, registered
end

return {
	{ "Rollable preview shows stable ID without changing Havoc descriptions", function (a)
		local view, buffs = fixture(a)
		buffs.details = function () return {title="Recipe",description="Effect",stable_id="my_recipe",icon="icon"} end
		view._selected_buff="network_slot"
		view:_refresh_details()
		a.truthy(view._widgets_by_name.detail_description.content.text:find("my_recipe\n\nEffect",1,true))
		view:cb_subtab_havoc()
		view._selected_buff="havoc_one";view:_refresh_details()
		a.eq(view._widgets_by_name.detail_description.content.text,"havoc_one")
	end },
	{ "buff menu defaults to buffs and repeated subtab switches keep one set of rows", function (a)
		local view, buffs, havoc, registered = fixture(a)
		a.eq(view._pool, buffs); a.eq(view._subtab, "buffs")
		a.truthy(view._widgets_by_name.subtab_buffs.content.hotspot.disabled)
		for _ = 1, 3 do
			view:cb_subtab_havoc()
			a.eq(view._pool, havoc); a.eq(view._selected_buff, "havoc_one")
			a.falsy(view._widgets_by_name.family_pick_button.visible)
			a.truthy(view._widgets_by_name.detail_modifier_icon.visible)
			a.falsy(view._widgets_by_name.detail_icon.visible)
			a.size(registered, 3)
			view:cb_subtab_buffs()
			a.eq(view._pool, buffs); a.truthy(view._widgets_by_name.family_pick_button.visible)
			a.size(registered, 3)
		end
	end },
	{ "Havoc controls affect only Havoc and refresh details after bulk/loadout changes", function (a)
		local view, buffs, havoc = fixture(a)
		view:cb_subtab_havoc()
		view:cb_toggle_selected()
		a.falsy(havoc.is_enabled("havoc_one")); a.truthy(buffs.is_enabled("buff_one"))
		view:cb_disable_all()
		a.eq(havoc.group_counts(), 0); a.eq(buffs.group_counts(), 2)
		a.eq(view._widgets_by_name.detail_toggle_button.content.original_text, "havoc_enable_this")
		view:cb_reset_all()
		a.eq(havoc.group_counts(), 2)
		havoc.set_enabled("havoc_one", false)
		view:on_loadout_changed()
		a.eq(view._widgets_by_name.detail_toggle_button.content.original_text, "havoc_enable_this")
		view:cb_subtab_buffs(); view:cb_disable_all()
		a.eq(buffs.group_counts(), 0); a.eq(havoc.group_counts(), 1)
	end },
}
