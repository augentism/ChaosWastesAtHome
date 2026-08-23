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

-- Derived rather than picked, so a font change cannot silently push one row of
-- text onto the next the way the title did.
local TITLE_H = 46
local SUBTITLE_TOP = 10 + TITLE_H + 2
local MODIFIERS_TOP = SUBTITLE_TOP + 22

-- Lifted clear of the bottom of the screen so the end-of-round chat does not
-- sit on top of the cards, and raised again to make room for the hover detail
-- underneath. The panel is centre-aligned, so this is an offset from the middle
-- rather than an absolute position.
local PANEL_Y = -200

-- Sized for the worst case the game can hand us: circumstance descriptions run
-- 37 to 221 characters and a Havoc card carries up to three of them.
--
-- BELOW the cards rather than beside them. It started to the left, where there
-- was more room -- but that is where scoreboard mods draw, and most players run
-- one, so the panel was invisible for exactly the people it was added for.
-- Underneath keeps it inside the column this view already owns.
local DETAIL_WIDTH = PANEL_WIDTH
local DETAIL_HEIGHT = 240
local DETAIL_PAD = 16

-- Heading, then a gap, then the body. Derived so the body cannot end up under
-- the heading if either changes size.
local DETAIL_HEADING_H = 24
local DETAIL_GAP = 18
local DETAIL_BODY_TOP = DETAIL_PAD + DETAIL_HEADING_H + DETAIL_GAP
local CARDS_TOP = 80
local CARDS_BOTTOM = CARDS_TOP + NUM_OPTIONS * (OPTION_HEIGHT + OPTION_SPACING)

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

	-- The hover detail, to the LEFT of the card panel rather than on it.
	--
	-- The cards are 132px with a thumbnail taking half their width, so there is
	-- no room on them for a couple of hundred characters of modifier text -- and
	-- growing them is what would push the panel off the bottom of the screen.
	-- The space left of the panel is empty, so the detail goes there and nothing
	-- has to move.
	--
	-- Parented to the panel so it tracks with it: the panel is right-aligned and
	-- lifted clear of the end-of-round chat, and a screen-parented box would
	-- drift away from the cards at other resolutions.
	detail = {
		vertical_alignment = "top",
		parent = "panel",
		horizontal_alignment = "center",
		size = { DETAIL_WIDTH, DETAIL_HEIGHT },
		position = { 0, CARDS_BOTTOM + 12, 4 },
	},
}

for i = 1, NUM_OPTIONS do
	scenegraph_definition["option_" .. i] = {
		vertical_alignment = "top",
		parent = "panel",
		horizontal_alignment = "center",
		size = { PANEL_WIDTH, OPTION_HEIGHT },
		position = { 0, CARDS_TOP + (i - 1) * (OPTION_HEIGHT + OPTION_SPACING), 3 },
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
				horizontal_alignment = "left",
				vertical_alignment = "center",
				size = { THUMB_W, OPTION_HEIGHT - 16 },
				offset = { 8, 0, 3 },
				material_values = {
					texture_map = "content/ui/textures/missions/quickplay",
				},
			},
		},
		-- Two lines of room, and a size down from 22.
		--
		-- The thumbnail leaves the text about 240px, and the longer mission names
		-- do not fit that on one line at 22 -- they wrapped into the difficulty
		-- line below, which had been given exactly one line's worth of space on
		-- the assumption they never would. Everything under it moved down to suit.
		{
			pass_type = "text",
			value_id = "title",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 20,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				offset = { TEXT_X, 10, 4 },
				size = { TEXT_W, TITLE_H },
				text_color = UIFontSettings.header_2.text_color,
			},
		},
		{
			pass_type = "text",
			value_id = "subtitle",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 15,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "top",
				offset = { TEXT_X, SUBTITLE_TOP, 4 },
				size = { TEXT_W, 20 },
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
				offset = { TEXT_X, MODIFIERS_TOP, 4 },
				size = { TEXT_W, OPTION_HEIGHT - MODIFIERS_TOP - 8 },
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

widget_definitions.detail = UIWidget.create_definition({
	{
		pass_type = "rect",
		style = {
			color = { 235, 8, 8, 10 },
		},
	},
	{
		pass_type = "text",
		value_id = "heading",
		value = "",
		style = {
			font_type = "proxima_nova_bold",
			font_size = 18,
			text_horizontal_alignment = "left",
			text_vertical_alignment = "top",
			offset = { DETAIL_PAD, DETAIL_PAD, 2 },
			size = { DETAIL_WIDTH - DETAIL_PAD * 2, DETAIL_HEADING_H },
			text_color = UIFontSettings.header_2.text_color,
		},
	},
	{
		pass_type = "text",
		value_id = "body",
		value = "",
		style = {
			font_type = "proxima_nova_medium",
			font_size = 15,
			text_horizontal_alignment = "left",
			text_vertical_alignment = "top",
			word_wrap = true,
			offset = { DETAIL_PAD, DETAIL_BODY_TOP, 2 },
			size = { DETAIL_WIDTH - DETAIL_PAD * 2, DETAIL_HEIGHT - DETAIL_BODY_TOP - DETAIL_PAD },
			text_color = { 255, 200, 195, 180 },
		},
	},
}, "detail")

for i = 1, NUM_OPTIONS do
	widget_definitions["option_" .. i] = _option_widget("option_" .. i)
end

return {
	scenegraph_definition = scenegraph_definition,
	widget_definitions = widget_definitions,
	num_options = NUM_OPTIONS,
}
