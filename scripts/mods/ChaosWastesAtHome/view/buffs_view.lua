local mod = get_mod("ChaosWastesAtHome")

local ScriptWorld = require("scripts/foundation/utilities/script_world")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWidgetGrid = require("scripts/ui/widget_logic/ui_widget_grid")
local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")

local buff_pool = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/buff_pool")
local pause = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/pause")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")

-- Everything the run has collected so far, on a keybind, with the world stopped
-- while it is open.
--
-- Read from the run snapshot rather than from the buff extension: the snapshot
-- is what actually carries between missions, so this shows what you will still
-- have next leg -- which is the question being asked.

local VIEW_NAME = "chaos_wastes_buffs_view"

local BuffsView = class("ChaosWastesBuffsView", "BaseView")

BuffsView.init = function (self, settings, context)
	self._definitions = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buffs_view_definitions")

	self._row_widgets = {}
	self._grid = nil

	BuffsView.super.init(self, self._definitions, settings, context)

	self._pass_input = false
	self._pass_draw = false

	self:_setup_offscreen_gui()
end

BuffsView._setup_offscreen_gui = function (self)
	local ui_manager = Managers.ui
	local class_name = self.__class_name

	self._offscreen_world = ui_manager:create_world(class_name .. "_world", 10, "ui", self.view_name)

	local viewport_name = class_name .. "_viewport"

	self._offscreen_viewport = ui_manager:create_viewport(
		self._offscreen_world, viewport_name, "overlay_offscreen", 1, self._definitions.shading_environment
	)
	self._offscreen_viewport_name = viewport_name
	self._ui_offscreen_renderer = ui_manager:create_renderer(class_name .. "_renderer", self._offscreen_world)
end

BuffsView.on_enter = function (self)
	BuffsView.super.on_enter(self)

	self._input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)

	for _, leg in ipairs(self._definitions.legend_inputs) do
		local cb = leg.on_pressed_callback and callback(self, leg.on_pressed_callback)

		self._input_legend_element:add_entry(leg.display_name, leg.input_action, nil, cb, leg.alignment)
	end

	-- Held for as long as the screen is up. Released in on_exit, and pause.update
	-- restores the timer scale from there like any other reason.
	pause.set_hold(true)

	self:_build_rows()
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

BuffsView._collected = function (self)
	-- Refreshed on open rather than trusting the periodic snapshot: a buff
	-- picked seconds ago should be on this list.
	pcall(run.capture, true)

	local entries = {}

	for name, stacks in pairs(run.state().buffs or {}) do
		local details = buff_pool.details(name)

		entries[#entries + 1] = {
			name = name,
			stacks = stacks or 1,
			title = details and details.title or name,
			description = details and details.description or "",
			icon = details and details.icon,
		}
	end

	table.sort(entries, function (a, b)
		return a.title < b.title
	end)

	return entries
end

BuffsView._set_icon = function (self, widget, icon)
	if not icon then
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

BuffsView._build_rows = function (self)
	local template = self._definitions.row_template
	local def = UIWidget.create_definition(template.pass_template, "grid_content_pivot", nil, template.size)
	local entries = self:_collected()
	local total = 0

	for i, entry in ipairs(entries) do
		local widget = self:_create_widget("buff_row_" .. i, def)

		widget.content.title = entry.title
		widget.content.description = entry.description
		-- Only shown above one, so a list of single-stack buffs is not a column
		-- of "x1".
		widget.content.stacks = entry.stacks > 1 and ("x" .. tostring(entry.stacks)) or ""

		self:_set_icon(widget, entry.icon)

		self._row_widgets[#self._row_widgets + 1] = widget
		total = total + entry.stacks
	end

	if #self._row_widgets > 0 then
		self._grid = UIWidgetGrid:new(
			self._row_widgets, self._row_widgets, self._ui_scenegraph,
			"panel", "down", self._definitions.grid_spacing, nil, true
		)

		self._grid:set_render_scale(self._render_scale)

		local scrollbar = self._widgets_by_name.scrollbar

		if scrollbar then
			self._grid:assign_scrollbar(scrollbar, "grid_content_pivot", "panel")
			self._grid:set_scrollbar_progress(0)
		end
	end

	self:_refresh_subtitle(#entries, total)
end

BuffsView._refresh_subtitle = function (self, unique_count, total_stacks)
	local widget = self._widgets_by_name.subtitle

	if not widget then
		return
	end

	if unique_count == 0 then
		widget.content.text = mod:localize("buffs_view_empty")

		return
	end

	local family = run.state().family

	widget.content.text = mod:localize("buffs_view_summary",
		tostring(unique_count), tostring(total_stacks), tostring(family or "-"))
end

BuffsView.cb_on_back_pressed = function (self)
	Managers.ui:close_view(VIEW_NAME)
end

-- ---------------------------------------------------------------------------
-- Update / draw
-- ---------------------------------------------------------------------------

BuffsView.update = function (self, dt, t, input_service)
	if self._grid then
		self._grid:update(dt, t, input_service)
	end

	return BuffsView.super.update(self, dt, t, input_service)
end

BuffsView.draw = function (self, dt, t, input_service, layer)
	self:_draw_elements(dt, t, self._ui_renderer, self._render_settings, input_service)

	if #self._row_widgets > 0 then
		local ui_renderer = self._ui_offscreen_renderer

		UIRenderer.begin_pass(ui_renderer, self._ui_scenegraph, input_service, dt, self._render_settings)

		for _, widget in ipairs(self._row_widgets) do
			if widget.visible ~= false and (not self._grid or self._grid:is_widget_visible(widget)) then
				UIWidget.draw(widget, ui_renderer)
			end
		end

		UIRenderer.end_pass(ui_renderer)
	end

	BuffsView.super.draw(self, dt, t, input_service, layer)
end

BuffsView.on_exit = function (self)
	-- Released unconditionally. If this is missed the world stays stopped for
	-- the rest of the mission, so it happens before anything that could fail.
	pause.set_hold(false)

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

	BuffsView.super.on_exit(self)
end

return BuffsView
