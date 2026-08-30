local mod = get_mod("ChaosWastesAtHome")

local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")

local strip = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/loadout_strip")
local tab_strip = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/tab_strip")

-- The Settings tab: everything a loadout carries except the buff pool.
--
-- Writes go through mod:set with notify TRUE. That is what makes editing here
-- save to the selected loadout: notify fires on_setting_changed, which marks the
-- active loadout dirty, which the debounced writer flushes a moment later. A
-- write with notify false would change the setting and never persist it to the
-- loadout, which is the kind of bug that only shows up after a restart.

local VIEW_NAME = "chaos_wastes_settings_view"

local SettingsView = class("ChaosWastesSettingsView", "BaseView")

SettingsView.init = function (self, settings_arg, context)
	self._definitions = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/settings_view_definitions")

	self._sliders = {}

	SettingsView.super.init(self, self._definitions, settings_arg, context)

	self._pass_input = false
	self._pass_draw = false
end

SettingsView.on_enter = function (self)
	SettingsView.super.on_enter(self)

	self._input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)

	for _, leg in ipairs(self._definitions.legend_inputs) do
		local cb = leg.on_pressed_callback and callback(self, leg.on_pressed_callback)

		self._input_legend_element:add_entry(leg.display_name, leg.input_action, nil, cb, leg.alignment)
	end

	local widgets_by_name = self._widgets_by_name

	widgets_by_name.title.content.text = mod:localize("settings_title")

	tab_strip.attach(self, "settings")

	for i = 1, #self._definitions.checkboxes do
		widgets_by_name["check_" .. i].content.hotspot.pressed_callback = callback(self, "cb_toggle", i)
	end

	for i = 1, #self._definitions.cycles do
		widgets_by_name["cycle_" .. i].content.hotspot.pressed_callback = callback(self, "cb_cycle", i)
	end

	for i = 1, #self._definitions.headers do
		widgets_by_name["header_" .. i].content.text = mod:localize(self._definitions.headers[i])
	end

	self:_init_sliders()

	strip.attach(self)

	self:_refresh()
end

-- ---------------------------------------------------------------------------
-- Sliders
-- ---------------------------------------------------------------------------

-- Set up once, then polled. The slider template owns its own drag handling and
-- only reports a normalised 0..1 in content.slider_value, so the mapping to the
-- setting's real range lives here -- the same shape as the launcher's difficulty
-- slider.
SettingsView._init_sliders = function (self)
	for i = 1, #self._definitions.sliders do
		local spec = self._definitions.sliders[i]
		local widget = self._widgets_by_name["slider_" .. i]
		local content = widget.content
		local steps = math.max(1, math.floor((spec.max - spec.min) / spec.step))

		content.min_value = spec.min
		content.max_value = spec.max
		content.step_size = 1 / steps
		content.label = mod:localize(spec.id)

		self._sliders[i] = { spec = spec, widget = widget }
	end
end

-- The VALUE only, never the name.
--
-- The slider template draws two things: content.label on the left through its
-- list_header sub-template, and value_text right-aligned in a box only
-- LABEL_WIDTH wide. Putting the name in both -- which is what this did, and what
-- the launcher's difficulty slider does -- prints it twice and wraps the long
-- ones inside that narrow box.
SettingsView._slider_display = function (self, spec, value)
	local text

	if spec.decimals then
		text = string.format("%." .. spec.decimals .. "f", value)
	else
		text = string.format("%d", value)
	end

	return spec.suffix and (text .. spec.suffix) or text
end

-- Pushes the stored value into the slider. Only called when the view opens or
-- the loadout changes -- writing it every frame would fight the player's drag.
SettingsView._set_slider_from_setting = function (self, entry)
	local spec = entry.spec
	local content = entry.widget.content
	local value = mod:get(spec.id)

	if type(value) ~= "number" then
		value = spec.min
	end

	local range = spec.max - spec.min

	content.slider_value = range > 0 and (value - spec.min) / range or 0
	content.applied_value = value
	content.value_text = self:_slider_display(spec, value)
end

SettingsView._read_sliders = function (self)
	for i = 1, #self._sliders do
		local entry = self._sliders[i]
		local spec = entry.spec
		local content = entry.widget.content
		local range = spec.max - spec.min
		local raw = spec.min + (content.slider_value or 0) * range

		-- Snapped to the setting's step before comparing, so a drag that moves
		-- the handle without crossing a step does not write the file.
		local snapped = spec.min + math.floor((raw - spec.min) / spec.step + 0.5) * spec.step

		snapped = math.max(spec.min, math.min(spec.max, snapped))

		if snapped ~= content.applied_value then
			content.applied_value = snapped
			content.value_text = self:_slider_display(spec, snapped)

			mod:set(spec.id, snapped, true)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Description panel
-- ---------------------------------------------------------------------------

-- The setting the cursor is over, or nil.
--
-- Walks the three kinds in the order they were laid out. All of them carry a
-- plain `hotspot`; the slider's second hotspot, `track_hotspot`, covers only the
-- track, so using it would leave the label half of the row silent.
SettingsView._hovered_setting = function (self)
	local widgets_by_name = self._widgets_by_name
	local definitions = self._definitions

	for i = 1, #definitions.checkboxes do
		if widgets_by_name["check_" .. i].content.hotspot.is_hover then
			return definitions.checkboxes[i]
		end
	end

	for i = 1, #definitions.cycles do
		if widgets_by_name["cycle_" .. i].content.hotspot.is_hover then
			return definitions.cycles[i].id
		end
	end

	for i = 1, #definitions.sliders do
		if widgets_by_name["slider_" .. i].content.hotspot.is_hover then
			return definitions.sliders[i].id
		end
	end

	return nil
end

-- Held from the last hover rather than cleared when the cursor leaves.
--
-- Moving off a row to reach for its slider, or down the column past three other
-- rows, would otherwise flash the panel empty each time. It only changes when
-- the cursor is actually over something.
SettingsView._update_description = function (self)
	local id = self:_hovered_setting()

	if not id or id == self._description_id then
		return
	end

	self._description_id = id

	local widget = self._widgets_by_name.description_panel
	local description = mod:localize(id .. "_description")

	-- DMF returns "<key>" for a string it does not have
	-- (dmf/modules/core/localization.lua, DMFMod.localize), so that is the test
	-- for a setting nobody has written a description for yet.
	if description:sub(1, 1) == "<" then
		description = ""
	end

	widget.content.title = mod:localize(id)
	widget.content.text = description
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

SettingsView._refresh = function (self)
	local widgets_by_name = self._widgets_by_name

	for i = 1, #self._definitions.checkboxes do
		local id = self._definitions.checkboxes[i]
		local widget = widgets_by_name["check_" .. i]
		local on = mod:get(id) and true or false

		widget.content.label = mod:localize(id)
		widget.content.state = on and mod:localize("settings_on") or mod:localize("settings_off")
		widget.content.is_on = on
	end

	for i = 1, #self._definitions.cycles do
		local spec = self._definitions.cycles[i]
		local widget = widgets_by_name["cycle_" .. i]
		local current = mod:get(spec.id)
		local label = spec.labels[1]

		for j = 1, #spec.values do
			if spec.values[j] == current then
				label = spec.labels[j]

				break
			end
		end

		widget.content.label = mod:localize(spec.id)
		widget.content.state = mod:localize(label)
		widget.content.is_on = true
	end

	for i = 1, #self._sliders do
		self:_set_slider_from_setting(self._sliders[i])
	end
end

-- Called by the strip after a different loadout has been applied: every control
-- on this screen is now showing the outgoing loadout's values.
SettingsView.on_loadout_changed = function (self)
	self:_refresh()
end

SettingsView.cb_toggle = function (self, index)
	local id = self._definitions.checkboxes[index]

	mod:set(id, not mod:get(id), true)

	self:_refresh()
end

SettingsView.cb_cycle = function (self, index)
	local spec = self._definitions.cycles[index]
	local current = mod:get(spec.id)
	local next_index = 1

	for j = 1, #spec.values do
		if spec.values[j] == current then
			next_index = j % #spec.values + 1

			break
		end
	end

	mod:set(spec.id, spec.values[next_index], true)

	self:_refresh()
end

SettingsView.cb_on_back_pressed = function (self)
	Managers.ui:close_view(VIEW_NAME)
end

SettingsView.on_exit = function (self)
	if self._input_legend_element then
		self:_remove_element("input_legend")

		self._input_legend_element = nil
	end

	SettingsView.super.on_exit(self)
end

SettingsView.update = function (self, dt, t, input_service)
	self:_read_sliders()
	self:_update_description()

	strip.update(self, dt)

	return SettingsView.super.update(self, dt, t, input_service)
end

return SettingsView
