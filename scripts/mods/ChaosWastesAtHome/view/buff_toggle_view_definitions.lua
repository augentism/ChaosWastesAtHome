local mod = get_mod("ChaosWastesAtHome")

local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local ScrollbarPassTemplates = require("scripts/ui/pass_templates/scrollbar_pass_templates")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local _s = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view_settings")

local scrollbar_width = _s.scrollbar_width
local group_grid_size = _s.group_grid_size
local buff_grid_size = _s.buff_grid_size
local blur_edge = _s.grid_blur_edge_size

local detail_panel_size = _s.detail_panel_size

local GROUP_X = 140
local PANEL_TOP = 250
local BUFF_X = GROUP_X + group_grid_size[1] + 60
local DETAIL_X = BUFF_X + buff_grid_size[1] + 40
local BUTTON_H = 44
local ICON_SIZE = 96

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,

	-- The same pair the launcher carries, in the same place, so switching does
	-- not move the controls under the cursor.
	tab_start = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 280, 40 },
		position = { -145, 84, 3 },
	},

	tab_buffs = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 280, 40 },
		position = { 145, 84, 3 },
	},

	title_divider = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = { 335, 18 },
		position = { GROUP_X, 145, 1 },
	},

	title_text = {
		vertical_alignment = "bottom",
		parent = "title_divider",
		horizontal_alignment = "left",
		size = { 1200, 50 },
		position = { 0, -35, 1 },
	},

	summary_text = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = { buff_grid_size[1], 30 },
		position = { GROUP_X, PANEL_TOP - 46, 2 },
	},

	-- Left: filter list
	group_panel = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = group_grid_size,
		position = { GROUP_X, PANEL_TOP, 1 },
	},

	group_grid_start = {
		vertical_alignment = "top",
		parent = "group_panel",
		horizontal_alignment = "left",
		size = { 0, 0 },
		position = { 0, 0, 0 },
	},

	group_grid_content_pivot = {
		vertical_alignment = "top",
		parent = "group_grid_start",
		horizontal_alignment = "left",
		size = { 0, 0 },
		position = { 0, 0, 1 },
	},

	group_grid_mask = {
		vertical_alignment = "center",
		parent = "group_panel",
		horizontal_alignment = "center",
		size = { group_grid_size[1] + blur_edge[1] * 2, group_grid_size[2] + blur_edge[2] * 2 },
		position = { 0, 0, 0 },
	},

	group_scrollbar = {
		vertical_alignment = "center",
		parent = "group_panel",
		horizontal_alignment = "right",
		size = { scrollbar_width, group_grid_size[2] },
		position = { 24, 0, 1 },
	},

	-- Right: buffs in the selected group
	buff_panel = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = buff_grid_size,
		position = { BUFF_X, PANEL_TOP, 1 },
	},

	buff_grid_start = {
		vertical_alignment = "top",
		parent = "buff_panel",
		horizontal_alignment = "left",
		size = { 0, 0 },
		position = { 0, 0, 0 },
	},

	buff_grid_content_pivot = {
		vertical_alignment = "top",
		parent = "buff_grid_start",
		horizontal_alignment = "left",
		size = { 0, 0 },
		position = { 0, 0, 1 },
	},

	buff_grid_mask = {
		vertical_alignment = "center",
		parent = "buff_panel",
		horizontal_alignment = "center",
		size = { buff_grid_size[1] + blur_edge[1] * 2, buff_grid_size[2] + blur_edge[2] * 2 },
		position = { 0, 0, 0 },
	},

	buff_scrollbar = {
		vertical_alignment = "center",
		parent = "buff_panel",
		horizontal_alignment = "right",
		size = { scrollbar_width, buff_grid_size[2] },
		position = { 24, 0, 1 },
	},

	-- Right: the selected buff's card. Plain widgets rather than a grid -- it is
	-- one buff at a time and never scrolls.
	detail_panel = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = detail_panel_size,
		position = { DETAIL_X, PANEL_TOP, 1 },
	},

	detail_icon = {
		vertical_alignment = "top",
		parent = "detail_panel",
		horizontal_alignment = "center",
		size = { ICON_SIZE, ICON_SIZE },
		position = { 0, 24, 2 },
	},

	detail_title = {
		vertical_alignment = "top",
		parent = "detail_panel",
		horizontal_alignment = "center",
		size = { detail_panel_size[1] - 40, 40 },
		position = { 0, 24 + ICON_SIZE + 16, 2 },
	},

	detail_subtitle = {
		vertical_alignment = "top",
		parent = "detail_panel",
		horizontal_alignment = "center",
		size = { detail_panel_size[1] - 40, 26 },
		position = { 0, 24 + ICON_SIZE + 58, 2 },
	},

	detail_description = {
		vertical_alignment = "top",
		parent = "detail_panel",
		horizontal_alignment = "center",
		size = { detail_panel_size[1] - 48, 320 },
		position = { 0, 24 + ICON_SIZE + 96, 2 },
	},

	detail_toggle_button = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = { detail_panel_size[1], BUTTON_H },
		position = { DETAIL_X, PANEL_TOP + detail_panel_size[2] + 12, 2 },
	},

	-- Bulk controls, parented to screen rather than the masked panel so a click
	-- cannot fall through onto a clipped-but-still-interactive row.
	enable_all_button = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = { (buff_grid_size[1] - 10) * 0.5, BUTTON_H },
		position = { BUFF_X, PANEL_TOP + buff_grid_size[2] + 12, 2 },
	},

	disable_all_button = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = { (buff_grid_size[1] - 10) * 0.5, BUTTON_H },
		position = { BUFF_X + (buff_grid_size[1] - 10) * 0.5 + 10, PANEL_TOP + buff_grid_size[2] + 12, 2 },
	},

	reset_all_button = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = { group_grid_size[1], BUTTON_H },
		position = { GROUP_X, PANEL_TOP + group_grid_size[2] + 12, 2 },
	},
}

local widget_definitions = {
	background = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = { 255, 0, 0, 0 } } },
	}, "screen"),

	title_divider = UIWidget.create_definition({
		{ pass_type = "texture", value = "content/ui/materials/dividers/skull_rendered_left_01" },
	}, "title_divider"),

	title_text = UIWidget.create_definition({
		{
			value_id = "text",
			style_id = "text",
			pass_type = "text",
			value = mod:localize("buff_toggle_view_title"),
			style = table.clone(UIFontSettings.header_1),
		},
	}, "title_text"),

	summary_text = UIWidget.create_definition({
		{
			value_id = "text",
			pass_type = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 20,
				text_color = { 255, 220, 200, 160 },
				text_horizontal_alignment = "left",
				text_vertical_alignment = "center",
				size = { buff_grid_size[1] + group_grid_size[1], 30 },
				offset = { 0, 0, 2 },
			},
		},
	}, "summary_text"),

	-- Detail card. Every pass is driven from content so the whole card can be
	-- hidden by setting widget.visible when nothing is selected.
	detail_panel = UIWidget.create_definition({
		{
			pass_type = "rect",
			style = { color = { 140, 8, 6, 6 }, offset = { 0, 0, 0 } },
		},
	}, "detail_panel"),

	-- The buff icon is not the texture this pass draws.
	--
	-- The pass draws a *container material*, and the icon goes into it as a
	-- material value -- which is what the real buff card does
	-- (constant_element_mission_buffs_blueprints.lua:175 and :558). Putting the
	-- icon path in `value` instead gives a blank white square: the engine is
	-- being handed a plain texture where it expects a material.
	--
	-- Only `icon` is overridden. The container's own frame and mask defaults are
	-- base-game assets, whereas the horde hex-frame textures the real card
	-- substitutes ship with the Mortis package, so leaving them alone keeps this
	-- card's dependency down to the one texture that has to be there anyway.
	detail_icon = UIWidget.create_definition({
		{
			pass_type = "texture",
			style_id = "icon",
			value_id = "icon",
			value = "content/ui/materials/frames/talents/talent_icon_container",
			style = {
				horizontal_alignment = "center",
				vertical_alignment = "top",
				size = { ICON_SIZE, ICON_SIZE },
				offset = { 0, 0, 2 },
				material_values = {
					intensity = 0,
					saturation = 1,
				},
			},
		},
	}, "detail_icon"),

	detail_title = UIWidget.create_definition({
		{
			value_id = "text",
			style_id = "text",
			pass_type = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 26,
				text_color = { 255, 230, 220, 190 },
				text_horizontal_alignment = "center",
				text_vertical_alignment = "top",
				size = { detail_panel_size[1] - 40, 40 },
				offset = { 0, 0, 2 },
			},
		},
	}, "detail_title"),

	detail_subtitle = UIWidget.create_definition({
		{
			value_id = "text",
			style_id = "text",
			pass_type = "text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 18,
				text_color = { 200, 160, 150, 130 },
				text_horizontal_alignment = "center",
				text_vertical_alignment = "top",
				size = { detail_panel_size[1] - 40, 26 },
				offset = { 0, 0, 2 },
			},
		},
	}, "detail_subtitle"),

	detail_description = UIWidget.create_definition({
		{
			value_id = "text",
			style_id = "text",
			pass_type = "text",
			value = "",
			style = {
				-- proxima_nova_medium, not "proxima_nova": the latter is not a
				-- real font type and crashes the renderer mid-draw.
				font_type = "proxima_nova_medium",
				font_size = 20,
				text_color = { 255, 200, 200, 200 },
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				size = { detail_panel_size[1] - 48, 320 },
				offset = { 0, 0, 2 },
				line_spacing = 1.1,
			},
		},
	}, "detail_description"),

	detail_toggle_button = UIWidget.create_definition(
		table.clone(ButtonPassTemplates.default_button), "detail_toggle_button",
		{ original_text = "" }
	),

	group_scrollbar = UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar, "group_scrollbar"),
	buff_scrollbar = UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar, "buff_scrollbar"),

	group_grid_mask = UIWidget.create_definition({
		{
			value = "content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",
			pass_type = "texture",
			style = { color = { 255, 255, 255, 255 } },
		},
	}, "group_grid_mask"),

	buff_grid_mask = UIWidget.create_definition({
		{
			value = "content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",
			pass_type = "texture",
			style = { color = { 255, 255, 255, 255 } },
		},
	}, "buff_grid_mask"),

	tab_start = UIWidget.create_definition(
		table.clone(ButtonPassTemplates.default_button), "tab_start",
		{ original_text = mod:localize("tab_start_run") }
	),

	tab_buffs = UIWidget.create_definition(
		table.clone(ButtonPassTemplates.default_button), "tab_buffs",
		{ original_text = mod:localize("tab_rollable_buffs") }
	),

	-- default_button reads its label from original_text, not text: a
	-- change_function overwrites content.text every frame.
	enable_all_button = UIWidget.create_definition(
		table.clone(ButtonPassTemplates.default_button), "enable_all_button",
		{ original_text = mod:localize("buff_enable_all") }
	),

	disable_all_button = UIWidget.create_definition(
		table.clone(ButtonPassTemplates.default_button), "disable_all_button",
		{ original_text = mod:localize("buff_disable_all") }
	),

	reset_all_button = UIWidget.create_definition(
		table.clone(ButtonPassTemplates.default_button), "reset_all_button",
		{ original_text = mod:localize("buff_reset_all") }
	),
}

local legend_inputs = {
	{
		input_action = "back",
		on_pressed_callback = "cb_on_back_pressed",
		display_name = "loc_settings_menu_close_menu",
		alignment = "left_alignment",
	},
}

return settings("ChaosWastesBuffToggleViewDefinitions", {
	legend_inputs = legend_inputs,
	widget_definitions = widget_definitions,
	scenegraph_definition = scenegraph_definition,
})
