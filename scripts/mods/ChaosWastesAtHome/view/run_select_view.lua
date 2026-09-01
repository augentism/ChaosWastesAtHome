local mod = get_mod("ChaosWastesAtHome")

local definitions = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/run_select_view_definitions")
local chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/chain")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")

-- The next-mission picker shown alongside the end-of-round screen.
--
-- Deliberately a sibling view rather than widgets grafted into EndView:
-- EndView is a large view with its own presentation state machine, and
-- injecting into its widget tree would break on any patch that touches it.

local RunSelectView = class("ChaosWastesRunSelectView", "BaseView")

RunSelectView.init = function (self, settings, context)
	self._options = context and context.options or {}

	-- Which card the run is already pointing at, and whether that decision is
	-- the party's rather than this player's. Both default to the old behaviour
	-- when absent, so a redeployed view opened by a main script that predates
	-- them still works.
	self._selected_index = context and context.selected_index or nil
	self._locked = context and context.locked or false

	RunSelectView.super.init(self, definitions, settings, context)

	self._pass_input = true
	self._pass_draw = true
end

RunSelectView.on_enter = function (self)
	RunSelectView.super.on_enter(self)

	local widgets_by_name = self._widgets_by_name

	-- Hidden until update decides otherwise, so there is no chance of an empty
	-- box on the frame between entering and the first refresh.
	if widgets_by_name.detail then
		widgets_by_name.detail.visible = false
	end

	widgets_by_name.title.content.text = mod:localize("picker_title")
	widgets_by_name.subtitle.content.text = mod:localize("picker_subtitle")

	-- Clamped rather than trusted. A stale main script sends no index at all
	-- (this view re-executes on every open, the script that opens it only on a
	-- mod reload), and an index past the end would leave nothing looking
	-- selected -- the failure this whole block exists to prevent.
	local selected_index = tonumber(self._selected_index) or 1

	if selected_index < 1 or selected_index > #self._options then
		selected_index = 1
	end

	for i = 1, definitions.num_options do
		local widget = widgets_by_name["option_" .. i]
		local option = self._options[i]

		if option then
			widget.content.title = chain.mission_display_name(option.mission_name)
			widget.content.subtitle = option.difficulty_label or mod:localize("picker_option_subtitle")
			widget.content.modifiers = option.modifiers_label or ""
			-- Left nil when the party has already voted: a locked card that
			-- still lights up under the cursor and swallows a click reads as
			-- broken rather than as locked.
			if not self._locked then
				widget.content.hotspot.pressed_callback = callback(self, "_cb_option_pressed", i)
			end

			self:_set_preview(widget, chain.mission_preview_texture(option.mission_name))

			-- Whichever card is already the run's selection when this view opens
			-- has to look selected. Usually the first, but not when a vote
			-- decided it -- and an invisible default is worse than none: the run
			-- would continue somewhere the player had no idea they had agreed to,
			-- which is exactly what showing card 1 over a vote winner did.
			widget.content.hotspot.is_selected = i == selected_index

			widget.visible = true
		else
			widget.visible = false
		end
	end

	local default_option = self._options[selected_index]

	if default_option then
		self._selected_index = selected_index
		widgets_by_name.subtitle.content.text = mod:localize(
			self._locked and "picker_voted" or "picker_selected",
			chain.mission_display_name(default_option.mission_name))
	end
end

-- Both shapes handled rather than assuming which one the widget ended up with:
-- the game writes content.<id>.material_values, while the values are declared in
-- style. Guessing wrong is a nil index that only fires when a card is shown.
RunSelectView._set_preview = function (self, widget, texture)
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

RunSelectView._cb_option_pressed = function (self, index)
	local option = self._options[index]

	if not option or self._locked then
		return
	end

	self._selected_index = index

	for i = 1, definitions.num_options do
		local widget = self._widgets_by_name["option_" .. i]

		widget.content.hotspot.is_selected = i == index
	end

	-- Stored rather than launched: the run continues when the end screen would
	-- otherwise have sent us back to the Morningstar.
	run.state().next_mission = option

	-- Formatted by localize itself, not string.format afterwards: DMF runs
	-- every localization string through string.format, so fetching a string
	-- containing %s without supplying the argument errors on the fetch.
	self._widgets_by_name.subtitle.content.text =
		mod:localize("picker_selected", chain.mission_display_name(option.mission_name))

	mod:info("next mission selected: %s", tostring(option.mission_name))
end

-- The hover detail, refreshed every frame from whichever card the cursor is on.
--
-- Polled rather than driven by hover callbacks: the hotspot pass already tracks
-- is_hover for its own highlight, so reading it needs no extra wiring and cannot
-- fall out of step with what the card looks like. Three comparisons a frame.
--
-- Falls back to the SELECTED card when nothing is hovered, so the panel is
-- populated the moment the view opens rather than only once the player happens
-- to move the mouse over something.
RunSelectView._refresh_detail = function (self)
	local widget = self._widgets_by_name.detail

	if not widget then
		return
	end

	local index

	for i = 1, definitions.num_options do
		local option_widget = self._widgets_by_name["option_" .. i]
		local hotspot = option_widget and option_widget.visible and option_widget.content.hotspot

		if hotspot and hotspot.is_hover then
			index = i

			break
		end
	end

	index = index or self._selected_index

	local option = index and self._options[index]
	local detail = option and option.modifiers_detail

	-- Nothing worth reading is worse than an empty box: a mission with no
	-- maelstrom has no description, so the panel hides rather than showing a
	-- heading over blank space.
	if not option or not detail or detail == "" then
		widget.visible = false

		return
	end

	widget.content.heading = option.modifiers_label or ""
	widget.content.body = detail
	widget.visible = true
end

RunSelectView.update = function (self, dt, t, input_service)
	self:_refresh_detail()

	return RunSelectView.super.update(self, dt, t, input_service)
end

RunSelectView.on_exit = function (self)
	RunSelectView.super.on_exit(self)
end

return RunSelectView
