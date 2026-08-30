local mod = get_mod("ChaosWastesAtHome")

local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local SliderPassTemplates = require("scripts/ui/pass_templates/slider_pass_templates")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local strip = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/loadout_strip")
local tab_strip = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/tab_strip")

local _s = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/launch_view_settings")

local CARD_W = _s.card_size[1]
local CARD_SPACING = _s.card_spacing
local NUM_OPTIONS = 3
local BUTTON_H = _s.button_height

-- Card height is DERIVED from what goes in it, not picked.
--
-- It was a flat 300 with a 230px preview on top, which left the modifier list a
-- six-pixel box to wrap inside -- so it drew outside the card. Building the
-- height from the parts means adding a line of text cannot silently overflow
-- again.
local PREVIEW_H = math.floor(CARD_W * 0.5)
local TITLE_TOP = PREVIEW_H + 14
local TITLE_H = 34
local MODIFIERS_TOP = TITLE_TOP + TITLE_H + 8
-- Two wrapped lines at font size 15. A Havoc card lists two rolled modifiers
-- plus a theme circumstance, which is the longest case for the NAMES.
local MODIFIERS_H = 44
local DETAIL_TOP = MODIFIERS_TOP + MODIFIERS_H + 4

-- What the modifiers actually do, and the reason the card grew.
--
-- These are the game's own circumstance descriptions and they are long: 37 to
-- 221 characters, and a Havoc card can carry three of them. Sized for close to
-- that worst case at font 13 in a 416px box -- roughly 60 characters a line, so
-- twelve lines. Text that does not fit is drawn outside the card rather than
-- clipped, which is how the modifier list escaped its box the first time, so
-- this errs long deliberately.
local DETAIL_H = 168
local CARD_BOTTOM_PAD = 16
local CARD_H = DETAIL_TOP + DETAIL_H + CARD_BOTTOM_PAD

local ROW_WIDTH = NUM_OPTIONS * CARD_W + (NUM_OPTIONS - 1) * CARD_SPACING
local CARDS_TOP = 330

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,

	title = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 900, 50 },
		position = { 0, 150, 2 },
	},

	subtitle = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 1100, 30 },
		position = { 0, 205, 2 },
	},

	difficulty_slider = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = _s.slider_size,
		position = { 0, 260, 2 },
	},

	cards_row = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { ROW_WIDTH, CARD_H },
		position = { 0, CARDS_TOP, 1 },
	},

	-- Positioned off the row rather than a fixed y, so the buttons cannot end up
	-- underneath the cards when the card height changes.
	reroll_button = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 300, BUTTON_H },
		position = { -170, CARDS_TOP + CARD_H + 24, 2 },
	},

	begin_button = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 300, BUTTON_H },
		position = { 170, CARDS_TOP + CARD_H + 24, 2 },
	},
}

for i = 1, NUM_OPTIONS do
	scenegraph_definition["option_" .. i] = {
		vertical_alignment = "top",
		parent = "cards_row",
		horizontal_alignment = "left",
		size = { CARD_W, CARD_H },
		position = { (i - 1) * (CARD_W + CARD_SPACING), 0, 2 },
	}
end

-- The card, lifted from run_select_view_definitions so the launcher and the
-- end-of-round picker look like the same screen -- they are offering the same
-- thing at different moments.
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
		-- The map preview, filling the top of the card.
		--
		-- The artwork is a material value (texture_map), not the texture this pass
		-- draws. Handing the map path in as `value` renders a blank square.
		--
		-- The material is the engine's stock ui_default_base, NOT the mission
		-- board's texture_with_grid_effect that the real board uses. The grid one
		-- ships in packages/ui/views/mission_board_view, which is preloaded in the
		-- hub and NOT resident anywhere else -- so drawing with it worked in the
		-- launcher and hard-crashed the end-of-mission picker:
		--
		--   ui_renderer.lua:234: Error loading material '0'. Reason: 'Material
		--   '#ID[...]' not found.'
		--
		-- create_material throws from inside the draw, so there is nothing to
		-- pcall and no way to feature-test first. Depending on a package someone
		-- else preloads is the bug; ui_default_base is always resident and takes
		-- the same texture_map slot. Cost is the grid overlay.
		{
			pass_type = "texture",
			style_id = "preview",
			value_id = "preview",
			value = "content/ui/materials/base/ui_default_base",
			style = {
				horizontal_alignment = "center",
				vertical_alignment = "top",
				size = { CARD_W, PREVIEW_H },
				offset = { 0, 0, 2 },
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
				font_size = 24,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				offset = { 22, TITLE_TOP, 4 },
				size = { CARD_W - 44, TITLE_H },
				text_color = UIFontSettings.header_2.text_color,
			},
		},
		-- No difficulty line: the slider above already says what it is, and
		-- repeating it on all three cards told the player nothing.
		{
			pass_type = "text",
			value_id = "modifiers",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 15,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				word_wrap = true,
				offset = { 22, MODIFIERS_TOP, 4 },
				size = { CARD_W - 44, MODIFIERS_H },
				text_color = { 255, 150, 140, 120 },
			},
		},
		-- Smaller and dimmer than the names above on purpose: at the same size
		-- and colour a 200-character description buries the modifier it belongs
		-- to, which is the thing you are actually choosing between.
		{
			pass_type = "text",
			value_id = "modifier_detail",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 13,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				word_wrap = true,
				offset = { 22, DETAIL_TOP, 4 },
				size = { CARD_W - 44, DETAIL_H },
				text_color = { 200, 120, 115, 100 },
			},
		},
	}, scenegraph_id)
end

local widget_definitions = {
	background = UIWidget.create_definition({
		{ pass_type = "rect", style = { color = { 200, 0, 0, 0 } } },
	}, "screen"),

	title = UIWidget.create_definition({
		{
			pass_type = "text",
			value_id = "text",
			value = mod:localize("launch_view_title"),
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
				font_size = 18,
				text_horizontal_alignment = "center",
				text_vertical_alignment = "center",
				text_color = { 255, 180, 180, 180 },
			},
		},
	}, "subtitle"),

	-- The engine's own drag slider. Third argument is the LABEL area width; the
	-- track gets the remainder.
	difficulty_slider = UIWidget.create_definition(
		SliderPassTemplates.value_slider(_s.slider_size[1], _s.slider_size[2], _s.slider_label_width, true),
		"difficulty_slider"
	),

	reroll_button = UIWidget.create_definition(
		table.clone(ButtonPassTemplates.default_button), "reroll_button",
		{ original_text = mod:localize("launch_reroll") }
	),

	begin_button = UIWidget.create_definition(
		table.clone(ButtonPassTemplates.default_button), "begin_button",
		{ original_text = mod:localize("launch_begin") }
	),
}

for i = 1, NUM_OPTIONS do
	widget_definitions["option_" .. i] = _option_widget("option_" .. i)
end

local legend_inputs = {
	{
		input_action = "back",
		on_pressed_callback = "cb_on_back_pressed",
		display_name = "loc_settings_menu_close_menu",
		alignment = "left_alignment",
	},
}

tab_strip.extend(scenegraph_definition, widget_definitions)
strip.extend(scenegraph_definition, widget_definitions)

return {
	scenegraph_definition = scenegraph_definition,
	widget_definitions = widget_definitions,
	legend_inputs = legend_inputs,
	num_options = NUM_OPTIONS,
}
