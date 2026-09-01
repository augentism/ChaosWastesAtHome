local mod = get_mod("ChaosWastesAtHome")

local SliderPassTemplates = require("scripts/ui/pass_templates/slider_pass_templates")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local strip = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/loadout_strip")
local tab_strip = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/tab_strip")

-- Everything a loadout controls, other than which buffs can roll.
--
-- Laid out by TOPIC, in two columns, with a gap and a heading between sections.
-- The first version of this screen grouped by control type -- every toggle in
-- one column, every slider in the other -- which made the layout trivial and the
-- screen unreadable: "kills grant buffs" and "how many kills" ended up in
-- different columns with nine unrelated rows between them. Settings that belong
-- to the same decision now sit together whatever kind of control they need.
--
-- Built from the LAYOUT table below rather than by hand: positions are walked
-- down each column, so inserting a setting or a section cannot leave a stale
-- offset behind it. That is the same reasoning as the derived card heights in
-- the launcher and picker.

local ROW_W = 620
local ROW_H = 44
local SLIDER_H = 44
local SLIDER_LABEL_W = 300
local SLIDER_VALUE_W = 84
local HEADER_H = 34
local ITEM_SPACING = 4
local SECTION_GAP = 24
local COLUMN_GAP = 48

local CONTENT_TOP = 196
local LEFT_X = strip.WIDTH + 90
local RIGHT_X = LEFT_X + ROW_W + COLUMN_GAP

local LAYOUT = {
	{
		{ kind = "header", key = "settings_section_run" },
		{ kind = "check", id = "difficulty_ramp" },
		{ kind = "check", id = "use_bots" },

		{ kind = "header", key = "settings_section_buffs" },
		{ kind = "check", id = "pause_on_choice" },
		{ kind = "check", id = "sync_pause_multiplayer" },
		{ kind = "check", id = "ignore_buff_family" },
		{ kind = "slider", id = "starting_legendary_picks", min = 0, max = 12, step = 1 },
		{ kind = "slider", id = "starting_family_buffs", min = 0, max = 24, step = 1 },
		{ kind = "slider", id = "custom_buff_weight", min = 0, max = 10, step = 1 },
		{ kind = "slider", id = "max_legendary_choices", min = 0, max = 12, step = 1 },
		{ kind = "slider", id = "max_family_buffs", min = 0, max = 24, step = 1 },

		{ kind = "header", key = "settings_section_havoc" },
		{ kind = "slider", id = "havoc_theme_chance", min = 0, max = 100, step = 5, suffix = "%" },
	},
	{
		{ kind = "header", key = "settings_section_sources" },
		{ kind = "check", id = "objective_enabled" },
		{ kind = "check", id = "objective_side_missions" },
		{ kind = "check", id = "kills_enabled" },
		{
			kind = "cycle",
			id = "kills_mode",
			values = { "all", "elites_specials", "specials", "monsters" },
			labels = {
				"kills_mode_all",
				"kills_mode_elites_specials",
				"kills_mode_specials",
				"kills_mode_monsters",
			},
		},
		{ kind = "slider", id = "kills_threshold", min = 1, max = 500, step = 1 },
		{ kind = "check", id = "time_enabled" },
		{ kind = "slider", id = "time_interval", min = 0.5, max = 20, step = 0.5, decimals = 1 },
		{ kind = "check", id = "events_enabled" },
	},
}

local function _row_widget(scenegraph_id)
	return UIWidget.create_definition({
		{
			pass_type = "hotspot",
			content_id = "hotspot",
		},
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				color = { 150, 8, 8, 10 },
			},
			change_function = function (content, style)
				style.color[1] = content.hotspot.is_hover and 220 or 150
				style.color[2] = content.hotspot.is_hover and 26 or 8
			end,
		},
		{
			pass_type = "text",
			value_id = "label",
			value = "",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 19,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "center",
				offset = { 16, 0, 3 },
				size = { ROW_W - 190, ROW_H },
				text_color = UIFontSettings.list_button.text_color,
			},
		},
		{
			pass_type = "text",
			value_id = "state",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 19,
				text_horizontal_alignment = "right",
				text_vertical_alignment = "center",
				offset = { -16, 0, 3 },
				size = { ROW_W - 32, ROW_H },
				text_color = { 255, 190, 230, 190 },
			},
			change_function = function (content, style)
				-- Green when on, muted when off, so a column reads at a glance
				-- rather than word by word.
				local on = content.is_on

				style.text_color[2] = on and 190 or 130
				style.text_color[3] = on and 230 or 110
				style.text_color[4] = on and 190 or 110
			end,
		},
	}, scenegraph_id)
end

-- value_slider draws the VALUE and nothing else.
--
-- SliderPassTemplates._slider, which is what value_slider builds, has no label
-- pass at all -- unlike _settings_slider, which carries a list_header. The
-- launcher's difficulty slider works around that by concatenating the name into
-- value_text, but that box is right-aligned and only value_width wide, so a long
-- name wraps inside it. Give the row its own left-aligned label pass instead,
-- styled like the checkbox rows so a column of mixed controls reads as one list.
--
-- The two share the SLIDER_LABEL_W band to the left of the track: the label runs
-- from the left inset, the value is right-aligned at the far end of it, and
-- SLIDER_VALUE_W is the gap between them.
local function _slider_widget(scenegraph_id)
	local passes = SliderPassTemplates.value_slider(ROW_W, SLIDER_H, SLIDER_LABEL_W, true)

	passes[#passes + 1] = {
		pass_type = "text",
		value_id = "label",
		value = "",
		style = {
			font_type = "proxima_nova_medium",
			font_size = 19,
			text_horizontal_alignment = "left",
			text_vertical_alignment = "center",
			offset = { 16, 0, 8 },
			size = { SLIDER_LABEL_W - SLIDER_VALUE_W - 16, SLIDER_H },
			text_color = UIFontSettings.list_button.text_color,
		},
	}

	return UIWidget.create_definition(passes, scenegraph_id)
end

local function _header_widget(scenegraph_id)
	return UIWidget.create_definition({
		{
			pass_type = "text",
			value_id = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 22,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "bottom",
				offset = { 2, -6, 3 },
				size = { ROW_W, HEADER_H },
				text_color = UIFontSettings.header_2.text_color,
			},
		},
		-- A rule under the heading, which is what actually separates the sections
		-- once there are two columns of them.
		{
			pass_type = "rect",
			style = {
				vertical_alignment = "bottom",
				size = { ROW_W, 2 },
				offset = { 0, 0, 2 },
				color = { 90, 190, 180, 160 },
			},
		},
	}, scenegraph_id)
end

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,

	title = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 900, 50 },
		position = { 0, 140, 2 },
	},
}

local widget_definitions = {
	title = UIWidget.create_definition({
		{
			pass_type = "text",
			value_id = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 32,
				text_horizontal_alignment = "center",
				text_vertical_alignment = "center",
				text_color = UIFontSettings.header_1.text_color,
			},
		},
	}, "title"),
}

-- Walk each column, placing items and numbering them per kind.
--
-- The per-kind numbering is what the view indexes by (check_1, slider_1, ...),
-- so the lists it iterates are built here too rather than repeated there -- one
-- place decides both where a setting sits and what it is called.
local checkboxes, sliders, cycles, headers = {}, {}, {}, {}
local content_bottom = CONTENT_TOP

for column = 1, #LAYOUT do
	local x = column == 1 and LEFT_X or RIGHT_X
	local y = CONTENT_TOP

	for _, item in ipairs(LAYOUT[column]) do
		local id, height

		if item.kind == "header" then
			-- Space above a heading, except the first in a column: the gap is
			-- what separates one section from the previous, and there is nothing
			-- above the first one to separate it from.
			if y > CONTENT_TOP then
				y = y + SECTION_GAP
			end

			headers[#headers + 1] = item.key
			id = "header_" .. #headers
			height = HEADER_H

			scenegraph_definition[id] = {
				vertical_alignment = "top",
				parent = "screen",
				horizontal_alignment = "left",
				size = { ROW_W, HEADER_H },
				position = { x, y, 3 },
			}

			widget_definitions[id] = _header_widget(id)
		elseif item.kind == "slider" then
			sliders[#sliders + 1] = item
			id = "slider_" .. #sliders
			height = SLIDER_H

			scenegraph_definition[id] = {
				vertical_alignment = "top",
				parent = "screen",
				horizontal_alignment = "left",
				size = { ROW_W, SLIDER_H },
				position = { x, y, 3 },
			}

			widget_definitions[id] = _slider_widget(id)
		else
			local list = item.kind == "cycle" and cycles or checkboxes

			list[#list + 1] = item.kind == "cycle" and item or item.id
			id = (item.kind == "cycle" and "cycle_" or "check_") .. #list
			height = ROW_H

			scenegraph_definition[id] = {
				vertical_alignment = "top",
				parent = "screen",
				horizontal_alignment = "left",
				size = { ROW_W, ROW_H },
				position = { x, y, 3 },
			}

			widget_definitions[id] = _row_widget(id)
		end

		y = y + height + ITEM_SPACING
	end

	content_bottom = math.max(content_bottom, y - ITEM_SPACING)
end

-- The description of whatever the cursor is over.
--
-- These strings already existed for every setting -- DMF's own options menu
-- showed them on hover -- and moving the settings onto a tab of our own left
-- them written, translated and unreachable.
--
-- A fixed panel under the columns rather than a tooltip at the cursor: it needs
-- no cursor tracking, cannot clip off the edge of the screen, and does not sit
-- over the row being read. Placed from the measured bottom of the taller column
-- so adding a setting cannot push a row underneath it.
local DESCRIPTION_TOP = content_bottom + 28
local DESCRIPTION_W = ROW_W * 2 + COLUMN_GAP
local DESCRIPTION_H = 150
local DESCRIPTION_TITLE_H = 28

scenegraph_definition.description_panel = {
	vertical_alignment = "top",
	parent = "screen",
	horizontal_alignment = "left",
	size = { DESCRIPTION_W, DESCRIPTION_H },
	position = { LEFT_X, DESCRIPTION_TOP, 3 },
}

widget_definitions.description_panel = UIWidget.create_definition({
	-- A rule along the top, matching the one under each section heading, so the
	-- panel reads as part of the page rather than floating text.
	{
		pass_type = "rect",
		style = {
			vertical_alignment = "top",
			size = { DESCRIPTION_W, 2 },
			offset = { 0, 0, 2 },
			color = { 90, 190, 180, 160 },
		},
	},
	{
		pass_type = "text",
		value_id = "title",
		value = "",
		style = {
			font_type = "proxima_nova_bold",
			font_size = 20,
			text_horizontal_alignment = "left",
			text_vertical_alignment = "top",
			offset = { 0, 12, 3 },
			size = { DESCRIPTION_W, DESCRIPTION_TITLE_H },
			text_color = UIFontSettings.header_2.text_color,
		},
	},
	{
		pass_type = "text",
		value_id = "text",
		value = "",
		style = {
			-- proxima_nova_medium, not "proxima_nova": the latter is not a real
			-- font type and crashes the renderer mid-draw.
			font_type = "proxima_nova_medium",
			font_size = 18,
			text_horizontal_alignment = "left",
			text_vertical_alignment = "top",
			offset = { 0, 12 + DESCRIPTION_TITLE_H, 3 },
			size = { DESCRIPTION_W, DESCRIPTION_H - DESCRIPTION_TITLE_H - 12 },
			text_color = { 255, 200, 200, 200 },
			line_spacing = 1.1,
		},
	},
}, "description_panel")

-- The only tab with the loadout action buttons: they are as wide as their
-- labels, and LEFT_X above reserves that width. The other two tabs get the
-- icon column alone, which is why their content can start further left.
-- Escape reaches a view only through this.
--
-- BaseView has no back handling of its own: the other two tabs close on escape
-- because ViewElementInputLegend registers the "back" action and calls the
-- named callback. This tab had cb_on_back_pressed written and nothing wired to
-- fire it, so escape did nothing at all.
local legend_inputs = {
	{
		input_action = "back",
		on_pressed_callback = "cb_on_back_pressed",
		display_name = "loc_settings_menu_close_menu",
		alignment = "left_alignment",
	},
}

tab_strip.extend(scenegraph_definition, widget_definitions)
strip.extend(scenegraph_definition, widget_definitions, { actions = true })

return {
	legend_inputs = legend_inputs,
	scenegraph_definition = scenegraph_definition,
	widget_definitions = widget_definitions,
	checkboxes = checkboxes,
	sliders = sliders,
	cycles = cycles,
	headers = headers,
}
