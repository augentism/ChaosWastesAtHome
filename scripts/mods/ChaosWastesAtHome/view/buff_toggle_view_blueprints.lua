local mod = get_mod("ChaosWastesAtHome")

local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UISoundEvents = require("scripts/settings/ui/ui_sound_events")

local _s = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view_settings")

local GROUP_ROW_W = _s.group_grid_size[1]
local BUFF_ROW_W = _s.buff_grid_size[1]
local ROW_H = 52

-- The on/off tint. Read at a glance down a long list, which a checkbox glyph at
-- this row height would not be.
local COLOR_ON = { 255, 190, 230, 190 }
local COLOR_OFF = { 255, 130, 110, 110 }

local hotspot_style = {
	on_hover_sound = UISoundEvents.default_mouse_hover,
	on_pressed_sound = UISoundEvents.default_click,
}

local function _row_passes(width, with_state)
	local title_style = table.clone(UIFontSettings.list_button)

	title_style.offset = { 14, 0, 2 }
	title_style.font_size = 20
	title_style.text_horizontal_alignment = "left"
	title_style.text_vertical_alignment = "center"
	title_style.size = { width - (with_state and 130 or 28), ROW_H }

	local passes = {
		{
			style_id = "hotspot",
			pass_type = "hotspot",
			content_id = "hotspot",
			content = { use_is_focused = true },
			style = hotspot_style,
		},
		{
			pass_type = "texture",
			style_id = "background_selected",
			value = "content/ui/materials/buttons/background_selected",
			style = { color = Color.ui_terminal(0, true), offset = { 0, 0, 0 } },
			change_function = function (content, style)
				local base = 255 * content.hotspot.anim_select_progress

				style.color[1] = content.is_selected and 255 or base
			end,
			visibility_function = ButtonPassTemplates.list_button_focused_visibility_function,
		},
		{
			pass_type = "texture",
			style_id = "highlight",
			value = "content/ui/materials/frames/hover",
			style = {
				hdr = true,
				scale_to_material = true,
				color = Color.ui_terminal(255, true),
				offset = { 0, 0, 3 },
				size_addition = { 0, 0 },
			},
			change_function = ButtonPassTemplates.list_button_highlight_change_function,
			visibility_function = ButtonPassTemplates.list_button_focused_visibility_function,
		},
		{
			pass_type = "text",
			style_id = "text",
			value_id = "text",
			value = "",
			style = title_style,
		},
	}

	if with_state then
		passes[#passes + 1] = {
			pass_type = "text",
			style_id = "state_text",
			value_id = "state_text",
			value = "",
			style = {
				font_type = "proxima_nova_bold",
				font_size = 20,
				text_color = table.clone(COLOR_ON),
				text_horizontal_alignment = "right",
				text_vertical_alignment = "center",
				size = { width - 28, ROW_H },
				offset = { 0, 0, 3 },
			},
		}
	end

	return passes
end

local blueprints = {
	-- Left list: one row per family / category.
	group_row = {
		size = { GROUP_ROW_W, ROW_H },
		pass_template = _row_passes(GROUP_ROW_W, true),

		init = function (parent, widget, entry, callback_name)
			local content = widget.content

			content.hotspot.pressed_callback = function ()
				callback(parent, callback_name, widget, entry)()
			end

			content.text = entry.title
			content.entry = entry
		end,
	},

	-- Right list: one row per buff, clicking toggles it.
	buff_row = {
		size = { BUFF_ROW_W, ROW_H },
		pass_template = _row_passes(BUFF_ROW_W, true),

		init = function (parent, widget, entry, callback_name)
			local content = widget.content

			content.hotspot.pressed_callback = function ()
				callback(parent, callback_name, widget, entry)()
			end

			content.text = entry.title
			content.entry = entry
		end,
	},
}

return settings("ChaosWastesBuffToggleViewBlueprints", {
	blueprints = blueprints,
	row_height = ROW_H,
	color_on = COLOR_ON,
	color_off = COLOR_OFF,
})
