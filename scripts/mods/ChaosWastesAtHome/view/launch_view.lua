local mod = get_mod("ChaosWastesAtHome")

local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")

local chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/chain")
local difficulty = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/difficulty")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")

-- Starting a run from the Mourningstar.
--
-- A difficulty slider across the same ladder the ramp climbs, and three missions
-- rolled at the chosen rung. Choosing one and pressing Begin launches it -- the
-- launch itself is chain.launch, the same call the run already uses to hop from
-- mission to mission, so this screen only decides what to hand it.
--
-- No grid or offscreen renderer here, unlike the buff menu: three fixed cards
-- and a slider are plain widgets, and a scroll mask would be machinery for a
-- list that cannot scroll.

local VIEW_NAME = "chaos_wastes_launch_view"

local LaunchView = class("ChaosWastesLaunchView", "BaseView")

LaunchView.init = function (self, settings, context)
	self._definitions = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/launch_view_definitions")

	self._rungs = difficulty.rungs()
	self._rung_index = 1
	self._options = {}
	self._selected_index = nil
	self._launching = false

	LaunchView.super.init(self, self._definitions, settings, context)

	-- Both false so nothing underneath can be clicked while this is open.
	self._pass_input = false
	self._pass_draw = false
end

LaunchView.on_enter = function (self)
	LaunchView.super.on_enter(self)

	self._input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)

	for _, leg in ipairs(self._definitions.legend_inputs) do
		local cb = leg.on_pressed_callback and callback(self, leg.on_pressed_callback)

		self._input_legend_element:add_entry(leg.display_name, leg.input_action, nil, cb, leg.alignment)
	end

	local widgets_by_name = self._widgets_by_name

	widgets_by_name.reroll_button.content.hotspot.pressed_callback = callback(self, "cb_reroll")
	widgets_by_name.begin_button.content.hotspot.pressed_callback = callback(self, "cb_begin")

	-- The tab for this screen does nothing; the other one swaps views. Same
	-- close-then-open pattern the gambits preset editor uses to reach its
	-- assignments screen.
	widgets_by_name.tab_buffs.content.hotspot.pressed_callback = callback(self, "cb_tab_buffs")

	for i = 1, self._definitions.num_options do
		local widget = widgets_by_name["option_" .. i]

		widget.content.hotspot.pressed_callback = callback(self, "cb_option_pressed", i)
	end

	self:_init_slider()
	self:_reroll()
end

-- ---------------------------------------------------------------------------
-- Difficulty slider
-- ---------------------------------------------------------------------------

-- Slider handling copied from the gambits preset editor: the widget stores a
-- normalized 0-1 value, so the rung index has to be converted both ways and the
-- drag quantized, or a drag lands between rungs.
LaunchView._init_slider = function (self)
	local widget = self._widgets_by_name.difficulty_slider
	local content = widget.content
	local count = #self._rungs

	content.min_value = 1
	content.max_value = count
	content.label = mod:localize("launch_difficulty")
	content.step_size = count > 1 and 1 / (count - 1) or 1
	content.slider_value = 0
	content.applied_value = 1
	content.value_text = self:_slider_text(1)

	self._slider_widget = widget
end

LaunchView._slider_text = function (self, index)
	local rung = self._rungs[index]

	return string.format("%s  %s", mod:localize("launch_difficulty"), difficulty.describe(rung))
end

-- Returns the rung index if the slider moved this frame, else nil.
LaunchView._read_slider = function (self)
	local widget = self._slider_widget

	if not widget then
		return nil
	end

	local content = widget.content
	local range = content.max_value - content.min_value
	local raw = content.min_value + (content.slider_value or 0) * range
	local index = math.min(content.max_value, math.max(content.min_value, math.floor(raw + 0.5)))

	if index ~= content.applied_value then
		content.applied_value = index
		content.value_text = self:_slider_text(index)

		return index
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- Rolling
-- ---------------------------------------------------------------------------

LaunchView._params_for_rung = function (self)
	local rung = self._rungs[self._rung_index]

	if not rung then
		return nil
	end

	-- A copy, and no played_mission: from the hub there is no previous mission to
	-- exclude, and roll_options would otherwise treat a stale field as one.
	local params = {
		challenge = rung.challenge,
		resistance = rung.resistance,
		havoc_rank = rung.havoc_rank,
	}

	return params
end

LaunchView._reroll = function (self)
	local params = self:_params_for_rung()

	if not params then
		return
	end

	-- skip_ramp: the slider says where the run starts, so the first mission must
	-- be at exactly that rung. The ramp takes over from the second one onward.
	local options = chain.roll_options(params, true) or {}

	self._options = options
	self._selected_index = #options > 0 and 1 or nil

	self:_refresh_cards()
	self:_refresh_subtitle()
end

-- The map goes into the grid-effect material as texture_map. Where the material
-- values live depends on how the widget was built, so both shapes are handled
-- rather than assuming one -- the same defensive shape the buff card uses.
LaunchView._set_preview = function (self, widget, texture)
	if not texture then
		return
	end

	local content_preview = widget.content and widget.content.preview

	if type(content_preview) == "table" and content_preview.material_values then
		content_preview.material_values.texture_map = texture

		return
	end

	local style_preview = widget.style and widget.style.preview

	if style_preview and style_preview.material_values then
		style_preview.material_values.texture_map = texture
	end
end

LaunchView._refresh_cards = function (self)
	local widgets_by_name = self._widgets_by_name

	for i = 1, self._definitions.num_options do
		local widget = widgets_by_name["option_" .. i]
		local option = self._options[i]

		if option then
			widget.content.title = chain.mission_display_name(option.mission_name)
			widget.content.modifiers = option.modifiers_label or ""
			widget.content.hotspot.is_selected = i == self._selected_index

			self:_set_preview(widget, chain.mission_preview_texture(option.mission_name))

			widget.visible = true
		else
			widget.visible = false
		end
	end
end

LaunchView._refresh_subtitle = function (self)
	local widget = self._widgets_by_name.subtitle

	if not widget then
		return
	end

	if #self._options == 0 then
		widget.content.text = mod:localize("launch_no_missions")

		return
	end

	local option = self._selected_index and self._options[self._selected_index]

	widget.content.text = option
		and mod:localize("launch_selected", chain.mission_display_name(option.mission_name))
		or mod:localize("launch_subtitle")
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

LaunchView.cb_option_pressed = function (self, index)
	if not self._options[index] then
		return
	end

	self._selected_index = index

	self:_refresh_cards()
	self:_refresh_subtitle()
end

LaunchView.cb_reroll = function (self)
	self:_reroll()
end

LaunchView.cb_begin = function (self)
	if self._launching then
		return
	end

	local option = self._selected_index and self._options[self._selected_index]

	if not option then
		return
	end

	self._launching = true

	-- Marked before the level starts loading. The gate in _should_activate reads
	-- this to decide whether the mission is ours, and it has to already be true
	-- by the time the next mission's game mode initialises.
	run.reset("starting a new run")
	run.mark_launched()
	run.state().params = {
		challenge = option.challenge,
		resistance = option.resistance,
		havoc_rank = option.havoc_rank,
		circumstance_name = option.circumstance_name,
	}

	mod:info("starting a run: %s", tostring(option.mission_name))

	-- Close first, launch once the view is really gone. Launching inline from an
	-- open view crashes -- SoloPlay hit this and waits the same way.
	Managers.ui:close_view(VIEW_NAME)

	local Promise = require("scripts/foundation/utilities/promise")

	Promise.until_true(function ()
		return not Managers.ui:view_active(VIEW_NAME)
	end):next(function ()
		chain.launch({
			mission_name = option.mission_name,
			challenge = option.challenge,
			resistance = option.resistance,
			circumstance_name = option.circumstance_name,
			havoc_data = option.havoc_data,
			side_mission = "default",
		})
	end)
end

LaunchView.cb_tab_buffs = function (self)
	Managers.ui:close_view(VIEW_NAME)
	Managers.ui:open_view("chaos_wastes_buff_toggle_view")
end

LaunchView.cb_on_back_pressed = function (self)
	Managers.ui:close_view(VIEW_NAME)
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------

LaunchView.update = function (self, dt, t, input_service)
	local index = self:_read_slider()

	if index and index ~= self._rung_index then
		self._rung_index = index

		self:_reroll()
	end

	return LaunchView.super.update(self, dt, t, input_service)
end

LaunchView.on_exit = function (self)
	if self._input_legend_element then
		self:_remove_element("input_legend")

		self._input_legend_element = nil
	end

	LaunchView.super.on_exit(self)
end

return LaunchView
