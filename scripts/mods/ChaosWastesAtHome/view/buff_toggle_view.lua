local mod = get_mod("ChaosWastesAtHome")

local ScriptWorld = require("scripts/foundation/utilities/script_world")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWidgetGrid = require("scripts/ui/widget_logic/ui_widget_grid")
local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")

local asset_loader = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/asset_loader")
local buff_pool = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/buff_pool")

-- Which buffs are allowed to be rolled.
--
-- Left: families and legendary categories. Right: the buffs in the selected
-- one, each row a toggle. Everything is on by default; turning a row off adds
-- it to the exclusion table the buff system already filters both pools through.
--
-- Follows the priority-preset view in darktide-lua-gambits: offscreen renderer
-- plus UIWidgetGrid plus a mask, which is the workspace's pattern for a
-- scrollable list in a custom view.

local VIEW_NAME = "chaos_wastes_buff_toggle_view"

local BuffToggleView = class("ChaosWastesBuffToggleView", "BaseView")

BuffToggleView.init = function (self, settings_arg, context)
	self._definitions = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view_definitions")
	self._blueprint_data = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view_blueprints")
	self._blueprints = self._blueprint_data.blueprints
	self._view_settings = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view_settings")

	self._group_widgets = {}
	self._group_rows_by_id = {}
	self._buff_widgets = {}
	self._selected_group = nil
	self._selected_buff = nil
	self._group_grid = nil
	self._buff_grid = nil

	BuffToggleView.super.init(self, self._definitions, settings_arg, context)

	-- Both false so the engine stops here: UIViewHandler walks open views
	-- top-down and hands null_service to everything below the first view
	-- reporting pass_on_input false, which is what stops clicks landing on the
	-- mod options menu this was opened from.
	self._pass_input = false
	self._pass_draw = false

	self:_setup_offscreen_gui()
end

BuffToggleView._setup_offscreen_gui = function (self)
	local ui_manager = Managers.ui
	local class_name = self.__class_name

	self._offscreen_world = ui_manager:create_world(class_name .. "_world", 10, "ui", self.view_name)

	local viewport_name = class_name .. "_viewport"

	self._offscreen_viewport = ui_manager:create_viewport(
		self._offscreen_world, viewport_name, "overlay_offscreen", 1, self._view_settings.shading_environment
	)
	self._offscreen_viewport_name = viewport_name
	self._ui_offscreen_renderer = ui_manager:create_renderer(class_name .. "_renderer", self._offscreen_world)
end

BuffToggleView.on_enter = function (self)
	BuffToggleView.super.on_enter(self)

	self._input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)

	for _, leg in ipairs(self._definitions.legend_inputs) do
		local cb = leg.on_pressed_callback and callback(self, leg.on_pressed_callback)

		self._input_legend_element:add_entry(leg.display_name, leg.input_action, nil, cb, leg.alignment)
	end

	local widgets_by_name = self._widgets_by_name

	if widgets_by_name.enable_all_button then
		widgets_by_name.enable_all_button.content.hotspot.pressed_callback = callback(self, "cb_enable_all")
	end

	if widgets_by_name.disable_all_button then
		widgets_by_name.disable_all_button.content.hotspot.pressed_callback = callback(self, "cb_disable_all")
	end

	if widgets_by_name.reset_all_button then
		widgets_by_name.reset_all_button.content.hotspot.pressed_callback = callback(self, "cb_reset_all")
	end

	if widgets_by_name.detail_toggle_button then
		widgets_by_name.detail_toggle_button.content.hotspot.pressed_callback = callback(self, "cb_toggle_selected")
	end

	-- Only the other tab does anything; this screen's own tab is inert.
	if widgets_by_name.tab_start then
		widgets_by_name.tab_start.content.hotspot.pressed_callback = callback(self, "cb_tab_start")
	end

	-- The icons live in the Mortis package, which is only resident during one of
	-- our missions -- so in the Mourningstar every icon would be a placeholder.
	-- Requesting it here makes the menu usable from the hub, and it is the same
	-- package a run loads, so opening this mid-run costs nothing.
	--
	-- Honours the preload setting: someone who turned the package off to save
	-- load time has already accepted placeholder artwork on the real cards.
	asset_loader.request()

	self._assets_loaded = asset_loader.is_loaded()

	-- Rebuilt on open so custom buffs registered since the last visit appear.
	buff_pool.invalidate()

	self:_build_groups()

	local groups = buff_pool.groups()

	self:_select_group(groups[1])
end

-- ---------------------------------------------------------------------------
-- Left list
-- ---------------------------------------------------------------------------

BuffToggleView._build_groups = function (self)
	local template = self._blueprints.group_row
	local def = UIWidget.create_definition(template.pass_template, "group_grid_content_pivot", nil, template.size)

	for i, group in ipairs(buff_pool.groups()) do
		local widget = self:_create_widget("group_row_" .. i, def)

		template.init(self, widget, { title = group.label, group = group }, "cb_group_pressed")
		self:_refresh_group_row(widget, group)

		self._group_widgets[#self._group_widgets + 1] = widget
		self._group_rows_by_id[group.id] = widget
	end

	if #self._group_widgets > 0 then
		self._group_grid = UIWidgetGrid:new(
			self._group_widgets, self._group_widgets, self._ui_scenegraph,
			"group_panel", "down", self._view_settings.grid_spacing, nil, true
		)

		self._group_grid:set_render_scale(self._render_scale)

		local scrollbar = self._widgets_by_name.group_scrollbar

		if scrollbar then
			self._group_grid:assign_scrollbar(scrollbar, "group_grid_content_pivot", "group_panel")
			self._group_grid:set_scrollbar_progress(0)
		end
	end
end

-- The "7/9" on a filter row, so a group with things switched off is visible
-- without opening it.
BuffToggleView._refresh_group_row = function (self, widget, group)
	local on, total = buff_pool.group_counts(group)

	widget.content.state_text = string.format("%d/%d", on, total)
	widget.style.state_text.text_color = table.clone(
		on == total and self._blueprint_data.color_on or self._blueprint_data.color_off
	)
end

-- ---------------------------------------------------------------------------
-- Right list
-- ---------------------------------------------------------------------------

BuffToggleView._clear_buffs = function (self)
	for _, widget in ipairs(self._buff_widgets) do
		pcall(function ()
			self:_unregister_widget_name(widget.name)
		end)
	end

	self._buff_widgets = {}
	self._buff_grid = nil
end

BuffToggleView._build_buffs = function (self, group)
	self:_clear_buffs()

	if not group then
		return
	end

	local template = self._blueprints.buff_row
	local def = UIWidget.create_definition(template.pass_template, "buff_grid_content_pivot", nil, template.size)

	for i, name in ipairs(group.names) do
		local widget = self:_create_widget("buff_row_" .. i, def)

		template.init(self, widget, { title = buff_pool.title(name), buff_name = name }, "cb_buff_pressed")
		self:_refresh_buff_row(widget, name)

		self._buff_widgets[#self._buff_widgets + 1] = widget
	end

	if #self._buff_widgets > 0 then
		self._buff_grid = UIWidgetGrid:new(
			self._buff_widgets, self._buff_widgets, self._ui_scenegraph,
			"buff_panel", "down", self._view_settings.grid_spacing, nil, true
		)

		self._buff_grid:set_render_scale(self._render_scale)

		local scrollbar = self._widgets_by_name.buff_scrollbar

		if scrollbar then
			self._buff_grid:assign_scrollbar(scrollbar, "buff_grid_content_pivot", "buff_panel")
			self._buff_grid:set_scrollbar_progress(0)
		end
	end
end

BuffToggleView._refresh_buff_row = function (self, widget, name)
	local enabled = buff_pool.is_enabled(name)

	widget.content.state_text = mod:localize(enabled and "buff_state_on" or "buff_state_off")
	widget.style.state_text.text_color = table.clone(
		enabled and self._blueprint_data.color_on or self._blueprint_data.color_off
	)
	widget.style.text.text_color = table.clone(
		enabled and self._blueprint_data.color_on or self._blueprint_data.color_off
	)
end

BuffToggleView._refresh_visible_buffs = function (self)
	local group = self._selected_group

	if not group then
		return
	end

	for i, widget in ipairs(self._buff_widgets) do
		local name = group.names[i]

		if name then
			self:_refresh_buff_row(widget, name)
		end
	end
end

BuffToggleView._select_group = function (self, group)
	self._selected_group = group

	for id, widget in pairs(self._group_rows_by_id) do
		widget.content.is_selected = group ~= nil and id == group.id
	end

	self:_build_buffs(group)

	-- Opens on the first buff rather than an empty card: there is always
	-- something to describe, and a blank right-hand third reads as broken.
	self:_select_buff(group and group.names[1] or nil)
	self:_refresh_summary()
end

-- ---------------------------------------------------------------------------
-- Detail card
-- ---------------------------------------------------------------------------

BuffToggleView._select_buff = function (self, name)
	self._selected_buff = name

	local group = self._selected_group

	if group then
		for i, widget in ipairs(self._buff_widgets) do
			widget.content.is_selected = group.names[i] == name
		end
	end

	self:_refresh_details()
end

-- Writes the icon into the container material.
--
-- Where the material values live depends on how the widget was built: the game
-- writes content.icon.material_values (blueprints.lua:558) while the value is
-- declared in style. Both shapes are handled rather than assuming one, because
-- guessing wrong is a nil index on a table that is only touched when a card is
-- shown -- i.e. it would look fine until someone opened the menu.
BuffToggleView._set_icon = function (self, widget, icon)
	if not widget or not icon then
		return
	end

	local content_icon = widget.content and widget.content.icon

	if type(content_icon) == "table" and content_icon.material_values then
		content_icon.material_values.icon = icon

		return
	end

	local style_icon = widget.style and widget.style.icon

	if style_icon and style_icon.material_values then
		style_icon.material_values.icon = icon
	end
end

BuffToggleView._refresh_details = function (self)
	local widgets_by_name = self._widgets_by_name
	local name = self._selected_buff
	local details = name and buff_pool.details(name)
	local visible = details ~= nil

	for _, id in ipairs({ "detail_panel", "detail_icon", "detail_title", "detail_subtitle", "detail_description", "detail_toggle_button" }) do
		local widget = widgets_by_name[id]

		if widget then
			widget.visible = visible
		end
	end

	if not visible then
		return
	end

	widgets_by_name.detail_title.content.text = details.title

	widgets_by_name.detail_subtitle.content.text = mod:localize(
		details.is_family_buff and "buff_kind_family" or "buff_kind_legendary"
	)

	-- Already parsed and colour-tagged by the game's own formatter, so it goes
	-- into the text pass verbatim.
	widgets_by_name.detail_description.content.text = details.description or mod:localize("buff_no_description")

	self:_set_icon(widgets_by_name.detail_icon, details.icon)

	local enabled = buff_pool.is_enabled(name)

	widgets_by_name.detail_toggle_button.content.original_text =
		mod:localize(enabled and "buff_disable_this" or "buff_enable_this")
end

BuffToggleView._refresh_summary = function (self)
	local widget = self._widgets_by_name.summary_text

	if not widget then
		return
	end

	local disabled = buff_pool.disabled_count()

	widget.content.text = disabled == 0 and mod:localize("buff_summary_all_on")
		or mod:localize("buff_summary_disabled", disabled)
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

BuffToggleView.cb_group_pressed = function (self, widget, entry)
	self:_select_group(entry.group)
end

-- Selecting, not toggling. Reading what a buff does should not change whether
-- it is enabled -- browsing a family would otherwise turn half of it off. The
-- card's own button is the only thing that toggles.
BuffToggleView.cb_buff_pressed = function (self, widget, entry)
	self:_select_buff(entry.buff_name)
end

BuffToggleView.cb_toggle_selected = function (self)
	local name = self._selected_buff

	if not name then
		return
	end

	buff_pool.set_enabled(name, not buff_pool.is_enabled(name))

	self:_refresh_visible_buffs()
	self:_refresh_group_counts()
	self:_refresh_summary()
	self:_refresh_details()
end

BuffToggleView.cb_enable_all = function (self)
	self:_set_group_enabled(true)
end

BuffToggleView.cb_disable_all = function (self)
	self:_set_group_enabled(false)
end

BuffToggleView._set_group_enabled = function (self, enabled)
	local group = self._selected_group

	if not group then
		return
	end

	buff_pool.set_group_enabled(group, enabled)
	self:_refresh_visible_buffs()
	self:_refresh_group_counts()
	self:_refresh_summary()
end

BuffToggleView.cb_reset_all = function (self)
	for _, group in ipairs(buff_pool.groups()) do
		buff_pool.set_group_enabled(group, true)
	end

	self:_refresh_visible_buffs()
	self:_refresh_group_counts()
	self:_refresh_summary()
end

-- Every group row, not just the selected one: the same buff can appear in more
-- than one group (grenade buffs are shared across abilities), so toggling once
-- can change the count on a row that is not currently open.
BuffToggleView._refresh_group_counts = function (self)
	for _, group in ipairs(buff_pool.groups()) do
		local widget = self._group_rows_by_id[group.id]

		if widget then
			self:_refresh_group_row(widget, group)
		end
	end
end

BuffToggleView.cb_tab_start = function (self)
	Managers.ui:close_view(VIEW_NAME)
	Managers.ui:open_view("chaos_wastes_launch_view")
end

BuffToggleView.cb_on_back_pressed = function (self)
	Managers.ui:close_view(VIEW_NAME)
end

-- ---------------------------------------------------------------------------
-- Update / draw
-- ---------------------------------------------------------------------------

BuffToggleView.update = function (self, dt, t, input_service)
	if self._group_grid then
		self._group_grid:update(dt, t, input_service)
	end

	if self._buff_grid then
		self._buff_grid:update(dt, t, input_service)
	end

	-- The package load is asynchronous, so the card is already on screen by the
	-- time the textures arrive. Nothing re-reads a material value on its own --
	-- one refresh when the load lands is what turns the placeholder into art.
	local loaded = asset_loader.is_loaded()

	if loaded ~= self._assets_loaded then
		self._assets_loaded = loaded

		self:_refresh_details()
	end

	return BuffToggleView.super.update(self, dt, t, input_service)
end

BuffToggleView.draw = function (self, dt, t, input_service, layer)
	self:_draw_elements(dt, t, self._ui_renderer, self._render_settings, input_service)

	if #self._group_widgets > 0 then
		self:_draw_grid(self._group_grid, self._group_widgets, dt, t, input_service)
	end

	if #self._buff_widgets > 0 then
		self:_draw_grid(self._buff_grid, self._buff_widgets, dt, t, input_service)
	end

	BuffToggleView.super.draw(self, dt, t, input_service, layer)
end

BuffToggleView._draw_grid = function (self, grid, widgets, dt, t, input_service)
	local ui_renderer = self._ui_offscreen_renderer

	UIRenderer.begin_pass(ui_renderer, self._ui_scenegraph, input_service, dt, self._render_settings)

	for _, widget in ipairs(widgets) do
		local visible = widget.visible ~= false and (not grid or grid:is_widget_visible(widget))

		if visible then
			UIWidget.draw(widget, ui_renderer)
		end
	end

	UIRenderer.end_pass(ui_renderer)
end

BuffToggleView.on_exit = function (self)
	-- Only when no mission of ours is running. During a run the package belongs
	-- to the run, and releasing it here would strip the icons off the real buff
	-- cards for the rest of it.
	if not mod.manager then
		asset_loader.release()
	end

	if self._input_legend_element then
		self:_remove_element("input_legend")

		self._input_legend_element = nil
	end

	if self._ui_offscreen_renderer then
		Managers.ui:destroy_renderer(self.__class_name .. "_renderer")
		ScriptWorld.destroy_viewport(self._offscreen_world, self._offscreen_viewport_name)
		Managers.ui:destroy_world(self._offscreen_world)

		self._ui_offscreen_renderer = nil
		self._offscreen_viewport = nil
		self._offscreen_viewport_name = nil
		self._offscreen_world = nil
	end

	BuffToggleView.super.on_exit(self)
end

return BuffToggleView
