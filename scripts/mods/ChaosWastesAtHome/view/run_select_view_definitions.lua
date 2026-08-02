local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")

local PANEL_WIDTH = 420
local OPTION_HEIGHT = 132
local OPTION_SPACING = 12
local NUM_OPTIONS = 3

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	panel = {
		vertical_alignment = "center",
		parent = "screen",
		horizontal_alignment = "right",
		size = { PANEL_WIDTH, NUM_OPTIONS * (OPTION_HEIGHT + OPTION_SPACING) + 90 },
		position = { -70, 0, 200 },
	},
	title = {
		vertical_alignment = "top",
		parent = "panel",
		horizontal_alignment = "center",
		size = { PANEL_WIDTH, 40 },
		position = { 0, 0, 2 },
	},
	subtitle = {
		vertical_alignment = "top",
		parent = "panel",
		horizontal_alignment = "center",
		size = { PANEL_WIDTH, 26 },
		position = { 0, 40, 2 },
	},
}

for i = 1, NUM_OPTIONS do
	scenegraph_definition["option_" .. i] = {
		vertical_alignment = "top",
		parent = "panel",
		horizontal_alignment = "center",
		size = { PANEL_WIDTH, OPTION_HEIGHT },
		position = { 0, 80 + (i - 1) * (OPTION_HEIGHT + OPTION_SPACING), 3 },
	}
end

local function _option_widget(scenegraph_id)
	return UIWidget.create_definition({
		{
			pass_type = "hotspot",
			content_id = "hotspot",
		},
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				color = { 200, 8, 8, 10 },
			},
			change_function = function (content, style)
				local hotspot = content.hotspot
				local highlight = hotspot.is_hover or hotspot.is_selected

				style.color[1] = highlight and 235 or 200
				style.color[2] = hotspot.is_selected and 60 or (hotspot.is_hover and 30 or 8)
				style.color[3] = hotspot.is_selected and 30 or 8
			end,
		},
		{
			pass_type = "text",
			value_id = "title",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 22,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				offset = { 20, 14, 4 },
				size = { PANEL_WIDTH - 40, 30 },
				text_color = UIFontSettings.header_2.text_color,
			},
		},
		{
			pass_type = "text",
			value_id = "subtitle",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 16,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				offset = { 20, 46, 4 },
				size = { PANEL_WIDTH - 40, 22 },
				text_color = { 255, 190, 190, 190 },
			},
		},
		{
			pass_type = "text",
			value_id = "modifiers",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 14,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				word_wrap = true,
				offset = { 20, 70, 4 },
				size = { PANEL_WIDTH - 40, 56 },
				text_color = { 255, 150, 140, 120 },
			},
		},
	}, scenegraph_id)
end

local widget_definitions = {
	title = UIWidget.create_definition({
		{
			pass_type = "text",
			value_id = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 28,
				text_horizontal_alignment = "center",
				text_vertical_alignment = "center",
				text_color = UIFontSettings.header_1.text_color,
			},
		},
	}, "title"),
	subtitle = UIWidget.create_definition({
		{
			pass_type = "text",
			value_id = "text",
			value = "",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 17,
				text_horizontal_alignment = "center",
				text_vertical_alignment = "center",
				text_color = { 255, 180, 180, 180 },
			},
		},
	}, "subtitle"),
}

for i = 1, NUM_OPTIONS do
	widget_definitions["option_" .. i] = _option_widget("option_" .. i)
end

return {
	scenegraph_definition = scenegraph_definition,
	widget_definitions = widget_definitions,
	num_options = NUM_OPTIONS,
}
