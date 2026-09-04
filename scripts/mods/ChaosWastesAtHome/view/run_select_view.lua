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

	-- With other players connected this screen is a ballot rather than a
	-- decision: a click votes, the counts on the cards are everyone's, and the
	-- host settles it when the screen ends. Solo it behaves exactly as it
	-- always has.
	self._vote = context and context.vote or false

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

		-- In a vote nothing is selected yet -- _refresh_votes takes over on the
		-- first frame and says so. Claiming a pick here would show every player
		-- card 1 as "chosen" before anyone had voted.
		if not self._vote then
			widgets_by_name.subtitle.content.text = mod:localize(
				self._locked and "picker_voted" or "picker_selected",
				chain.mission_display_name(default_option.mission_name))
		end
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

	if self._vote then
		-- A ballot, not a choice. Nothing is decided until the screen ends, so
		-- the card can be changed as often as the player likes; the highlight
		-- and the counts are refreshed from the shared tally each frame rather
		-- than from this click.
		if mod.cast_vote then
			pcall(mod.cast_vote, index)
		end

		mod:info("voted for %s", tostring(option.mission_name))

		return
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

-- The running tally, redrawn every frame while a vote is on.
--
-- Read through the facade rather than by loading net.lua: this file re-executes
-- on every open and net.lua holds the vote state, so a second copy would count
-- into a table nobody resolves. The selected card comes from mod.my_vote rather
-- than from the last click, so a vote cast with /cw_vote shows too and
-- reopening the screen still shows what you picked.
RunSelectView._refresh_votes = function (self)
	if not self._vote or not mod.vote_counts then
		return
	end

	local ok, counts = pcall(mod.vote_counts)

	if not ok or type(counts) ~= "table" then
		return
	end

	local voted = mod.my_vote and mod.my_vote() or nil
	local total = 0

	for i = 1, #self._options do
		total = total + (counts[i] or 0)
	end

	for i = 1, definitions.num_options do
		local widget = self._widgets_by_name["option_" .. i]
		local option = self._options[i]

		if widget and option then
			local votes = counts[i] or 0

			widget.content.subtitle = votes > 0
				and mod:localize("picker_card_votes", votes, option.difficulty_label or "")
				or (option.difficulty_label or "")

			widget.content.hotspot.is_selected = i == voted
		end
	end

	local mine = voted and self._options[voted]

	self._widgets_by_name.subtitle.content.text = mine
		and mod:localize("picker_vote_yours",
			chain.mission_display_name(mine.mission_name), total)
		or mod:localize("picker_vote_subtitle", total)
end

RunSelectView.update = function (self, dt, t, input_service)
	self:_refresh_detail()
	self:_refresh_votes()

	return RunSelectView.super.update(self, dt, t, input_service)
end

RunSelectView.on_exit = function (self)
	RunSelectView.super.on_exit(self)
end

return RunSelectView
