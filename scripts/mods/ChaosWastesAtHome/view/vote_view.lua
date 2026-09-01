local mod = get_mod("ChaosWastesAtHome")

local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")

local chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/chain")

-- The vote screen.
--
-- Deliberately thin: the cards are the launcher's, the options arrive already
-- built (the host rolls them and sends them, so a client draws the same three
-- without knowing how they were chosen), and the only behaviour here is "click a
-- card to vote" plus redrawing the tally.
--
-- Blocks input and drawing underneath, unlike the end-of-round picker. That is
-- safe mid-mission because the view reports itself as a choice in progress --
-- see mod.vote_view_open -- which is what makes choice_shield protect whoever
-- has it open, exactly as it does for a buff card.

local definitions = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/vote_view_definitions")

local VIEW_NAME = "chaos_wastes_vote_view"

local VoteView = class("ChaosWastesVoteView", "BaseView")

VoteView.init = function (self, settings, context)
	self._options = context and context.options or {}

	-- Which round the cards on screen belong to. Watched every frame so the
	-- screen can fill itself in when a vote opens while it is already up, and --
	-- the reason this exists -- so it cannot go on showing the previous
	-- mission's cards after the round has moved on.
	self._token = nil

	VoteView.super.init(self, definitions, settings, context)

	self._pass_input = false
	self._pass_draw = false
end

VoteView.on_enter = function (self)
	VoteView.super.on_enter(self)

	-- The close hint. Worth the four lines here more than on most screens: this
	-- one blocks input, so a player who does not know how to leave it is stuck
	-- standing still in a mission.
	self._input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)

	for _, leg in ipairs(definitions.legend_inputs) do
		local cb = leg.on_pressed_callback and callback(self, leg.on_pressed_callback)

		self._input_legend_element:add_entry(leg.display_name, leg.input_action, nil, cb, leg.alignment)
	end

	local widgets_by_name = self._widgets_by_name

	widgets_by_name.title.content.text = mod:localize("vote_view_title")

	self:_apply_options(self._options, mod.vote_token and mod.vote_token() or nil)
end

-- Draw a set of cards, or none.
--
-- Separate from on_enter because the options can arrive after the screen is
-- already open: the vote goes up a little after the mission starts, and a player
-- who opened this before that happened should watch it appear rather than have
-- to close and reopen.
VoteView._apply_options = function (self, options, token)
	self._options = options or {}
	self._token = token

	local widgets_by_name = self._widgets_by_name

	for i = 1, definitions.num_options do
		local widget = widgets_by_name["option_" .. i]
		local option = self._options[i]

		if option then
			widget.content.title = chain.mission_display_name(option.mission_name)
			widget.content.modifiers = option.modifiers_label or ""
			widget.content.modifier_detail = option.modifiers_detail or ""
			widget.content.votes = ""
			widget.content.hotspot.pressed_callback = callback(self, "_cb_option_pressed", i)

			self:_set_preview(widget, chain.mission_preview_texture(option.mission_name))

			widget.visible = true
		else
			widget.visible = false
		end
	end

	self:_refresh_votes()
end

-- Both shapes handled rather than assuming which one the widget ended up with:
-- the game writes content.<id>.material_values, while the values are declared in
-- style. Guessing wrong is a nil index that only fires when a card is shown.
VoteView._set_preview = function (self, widget, texture)
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

VoteView._cb_option_pressed = function (self, index)
	local option = self._options[index]

	if not option then
		return
	end

	if not mod.cast_vote then
		return
	end

	local ok, cast, err = pcall(mod.cast_vote, index)

	if not ok or not cast then
		mod:echo(string.format("Chaos Wastes at Home: %s", tostring(ok and err or "could not vote")))

		return
	end

	-- Left open on purpose. Nothing is decided until the mission ends, so the
	-- tally is worth watching and the choice worth changing; closing on the
	-- first click would hide both.
	mod:info("voted for %s", tostring(option.mission_name))
end

-- The tally, redrawn every frame.
--
-- Read through the facade rather than by loading net.lua: this file re-executes
-- on every open and net.lua holds the vote state, so a second copy would show a
-- tally nobody is voting into. Guarded because a view may only call facade
-- entries the running main script actually shipped.
VoteView._refresh_votes = function (self)
	local widgets_by_name = self._widgets_by_name

	if #self._options == 0 then
		widgets_by_name.subtitle.content.text = mod:localize("vote_view_waiting")

		return
	end

	local voted = mod.my_vote and mod.my_vote() or nil
	local counts = {}

	if mod.vote_counts then
		local ok, result = pcall(mod.vote_counts)

		if ok and type(result) == "table" then
			counts = result
		end
	end

	local total = 0

	for i = 1, #self._options do
		total = total + (counts[i] or 0)
	end

	for i = 1, definitions.num_options do
		local widget = widgets_by_name["option_" .. i]

		if widget and self._options[i] then
			local votes = counts[i] or 0

			widget.content.votes = votes > 0 and tostring(votes) or ""
			widget.content.hotspot.is_selected = i == voted
		end
	end

	local mine = voted and self._options[voted]

	widgets_by_name.subtitle.content.text = mine
		and mod:localize("vote_view_voted",
			chain.mission_display_name(mine.mission_name), total)
		or mod:localize("vote_view_subtitle", total)
end

VoteView.cb_on_back_pressed = function (self)
	Managers.ui:close_view(VIEW_NAME)
end

VoteView.on_exit = function (self)
	if self._input_legend_element then
		self:_remove_element("input_legend")

		self._input_legend_element = nil
	end

	VoteView.super.on_exit(self)
end

VoteView.update = function (self, dt, t, input_service)
	-- The round, not the cards: comparing tables would rebuild every frame, and
	-- the token is exactly "is this a different vote than the one drawn".
	local token = mod.vote_token and mod.vote_token() or nil

	if token ~= self._token then
		self:_apply_options(mod.vote_options and mod.vote_options() or {}, token)
	end

	self:_refresh_votes()

	return VoteView.super.update(self, dt, t, input_service)
end

return VoteView
