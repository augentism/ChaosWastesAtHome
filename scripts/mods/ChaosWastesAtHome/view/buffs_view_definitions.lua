local mod = get_mod("ChaosWastesAtHome")

local ScrollbarPassTemplates = require("scripts/ui/pass_templates/scrollbar_pass_templates")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local GRID_W = 920
local GRID_H = 620
local ROW_H = 92
local ICON = 72
local TEXT_X = ICON + 26
local SCROLLBAR_W = 10
local BLUR_EDGE = 8
local PANEL_TOP = 240

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,

	title = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 900, 50 },
		position = { 0, 140, 2 },
	},

	subtitle = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 1000, 30 },
		position = { 0, 195, 2 },
	},

	panel = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { GRID_W, GRID_H },
		position = { 0, PANEL_TOP, 1 },
	},

	grid_start = {
		vertical_alignment = "top",
		parent = "panel",
		horizontal_alignment = "left",
		size = { 0, 0 },
		position = { 0, 0, 0 },
	},

	grid_content_pivot = {
		vertical_alignment = "top",
		parent = "grid_start",
		horizontal_alignment = "left",
		size = { 0, 0 },
		position = { 0, 0, 1 },
	},

	grid_mask = {
		vertical_alignment = "center",
		parent = "panel",
		horizontal_alignment = "center",
		size = { GRID_W + BLUR_EDGE * 2, GRID_H + BLUR_EDGE * 2 },
		position = { 0, 0, 0 },
	},

	scrollbar = {
		vertical_alignment = "center",
		parent = "panel",
		horizontal_alignment = "right",
		size = { SCROLLBAR_W, GRID_H },
		position = { 26, 0, 1 },
	},
}

-- One row per collected buff: the icon the card showed, its name, how many
-- stacks are held, and the same parsed description.
local row_template = {
	size = { GRID_W - 20, ROW_H },

	pass_template = {
		{
			pass_type = "rect",
			style = { color = { 120, 10, 8, 8 }, offset = { 0, 0, 0 } },
		},
		-- Material value, not the texture: same container the buff card uses.
		{
			pass_type = "texture",
			style_id = "icon",
			value_id = "icon",
			value = "content/ui/materials/frames/talents/talent_icon_container",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "center",
				size = { ICON, ICON },
				offset = { 10, 0, 2 },
				material_values = {
					intensity = 0,
					saturation = 1,
				},
			},
		},
		{
			pass_type = "text",
			style_id = "title",
			value_id = "title",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 21,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				offset = { TEXT_X, 10, 3 },
				size = { GRID_W - TEXT_X - 120, 26 },
				text_color = UIFontSettings.header_2.text_color,
			},
		},
		{
			pass_type = "text",
			style_id = "stacks",
			value_id = "stacks",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 21,
				text_horizontal_alignment = "right",
				text_vertical_alignment = "top",
				offset = { -20, 10, 3 },
				size = { GRID_W - 40, 26 },
				text_color = { 255, 200, 180, 120 },
			},
		},
		{
			pass_type = "text",
			style_id = "description",
			value_id = "description",
			value = "",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 16,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				word_wrap = true,
				offset = { TEXT_X, 38, 3 },
				size = { GRID_W - TEXT_X - 40, ROW_H - 46 },
				text_color = { 255, 190, 190, 190 },
			},
		},
	},
}

local widget_definitions = {
	background = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = { 210, 0, 0, 0 } } },
	}, "screen"),

	title = UIWidget.create_definition({
		{
			pass_type = "text",
			value_id = "text",
			value = mod:localize("buffs_view_title"),
			style = {
				font_type = "proxima_nova_bold",
				font_size = 34,
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
				font_size = 19,
				text_horizontal_alignment = "center",
				text_vertical_alignment = "center",
				text_color = { 255, 180, 180, 180 },
			},
		},
	}, "subtitle"),

	scrollbar = UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar, "scrollbar"),

	grid_mask = UIWidget.create_definition({
		{
			value = "content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",
			pass_type = "texture",
			style = { color = { 255, 255, 255, 255 } },
		},
	}, "grid_mask"),
}

local legend_inputs = {
	{
		input_action = "back",
		on_pressed_callback = "cb_on_back_pressed",
		display_name = "loc_settings_menu_close_menu",
		alignment = "left_alignment",
	},
}

return {
	scenegraph_definition = scenegraph_definition,
	widget_definitions = widget_definitions,
	legend_inputs = legend_inputs,
	row_template = row_template,
	grid_spacing = { 0, 6 },
	shading_environment = "content/shading_environments/ui/system_menu",
}
