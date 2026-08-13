local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")

local PANEL_WIDTH = 420
local OPTION_HEIGHT = 132
local OPTION_SPACING = 12
local NUM_OPTIONS = 3

-- The map preview sits BESIDE the text here, not above it as on the launcher
-- cards. Three stacked cards with a banner each would make the panel taller
-- than the screen; a thumbnail keeps the card height exactly as it was.
local THUMB_W = 150
local TEXT_X = THUMB_W + 14
local TEXT_W = PANEL_WIDTH - TEXT_X - 16

-- Lifted clear of the bottom of the screen so the end-of-round chat does not
-- sit on top of the cards. The panel is centre-aligned, so this is an offset
-- from the middle rather than an absolute position.
local PANEL_Y = -150

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	panel = {
		vertical_alignment = "center",
		parent = "screen",
		horizontal_alignment = "right",
		size = { PANEL_WIDTH, NUM_OPTIONS * (OPTION_HEIGHT + OPTION_SPACING) + 90 },
		position = { -70, PANEL_Y, 200 },
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
		-- The artwork is a material value on the mission board's grid-effect
		-- material, not the texture this pass draws. Handing it the map path as
		-- `value` renders a blank square.
		{
			pass_type = "texture",
			style_id = "preview",
			value_id = "preview",
			value = "content/ui/materials/mission_board/texture_with_grid_effect",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "center",
				size = { THUMB_W, OPTION_HEIGHT - 16 },
				offset = { 8, 0, 3 },
				material_values = {
					texture_map = "content/ui/textures/missions/quickplay",
				},
			},
		},
		{
			pass_type = "text",
			value_id = "title",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 22,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				offset = { TEXT_X, 12, 4 },
				size = { TEXT_W, 28 },
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
				offset = { TEXT_X, 42, 4 },
				size = { TEXT_W, 22 },
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
				offset = { TEXT_X, 66, 4 },
				size = { TEXT_W, OPTION_HEIGHT - 74 },
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
