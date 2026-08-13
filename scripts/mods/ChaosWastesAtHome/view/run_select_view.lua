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
	self._selected_index = nil

	RunSelectView.super.init(self, definitions, settings, context)

	self._pass_input = true
	self._pass_draw = true
end

RunSelectView.on_enter = function (self)
	RunSelectView.super.on_enter(self)

	local widgets_by_name = self._widgets_by_name

	widgets_by_name.title.content.text = mod:localize("picker_title")
	widgets_by_name.subtitle.content.text = mod:localize("picker_subtitle")

	for i = 1, definitions.num_options do
		local widget = widgets_by_name["option_" .. i]
		local option = self._options[i]

		if option then
			widget.content.title = chain.mission_display_name(option.mission_name)
			widget.content.subtitle = option.difficulty_label or mod:localize("picker_option_subtitle")
			widget.content.modifiers = option.modifiers_label or ""
			widget.content.hotspot.pressed_callback = callback(self, "_cb_option_pressed", i)

			self:_set_preview(widget, chain.mission_preview_texture(option.mission_name))

			-- The first card is already the run's selection when this view
			-- opens, so it has to look selected. An invisible default would be
			-- worse than none: the run would continue somewhere the player had
			-- no idea they had agreed to.
			widget.content.hotspot.is_selected = i == 1

			widget.visible = true
		else
			widget.visible = false
		end
	end

	local default_option = self._options[1]

	if default_option then
		self._selected_index = 1
		widgets_by_name.subtitle.content.text =
			mod:localize("picker_selected", chain.mission_display_name(default_option.mission_name))
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

	if not option then
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

RunSelectView.update = function (self, dt, t, input_service)
	return RunSelectView.super.update(self, dt, t, input_service)
end

RunSelectView.on_exit = function (self)
	RunSelectView.super.on_exit(self)
end

return RunSelectView
