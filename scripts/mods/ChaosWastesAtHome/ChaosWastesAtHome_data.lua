local mod = get_mod("ChaosWastesAtHome")

-- Builds a fresh options table per widget on purpose: DMF localizes dropdowns
-- in place (option.text = mod:localize(option.text)), so a table shared
-- between widgets would get localized twice and the second pass would be
-- looking up an already-translated string.
local function grant_options(default_value)
	return {
		default_value = default_value,
		options = {
			{ text = "grant_family",    value = "family" },
			{ text = "grant_legendary", value = "legendary" },
			{ text = "grant_random",    value = "random" },
		},
	}
end

local function grant_widget(setting_id, default_value)
	local options = grant_options(default_value)

	return {
		setting_id    = setting_id,
		type          = "dropdown",
		default_value = options.default_value,
		options       = options.options,
	}
end

local function chance_widget(setting_id)
	return {
		setting_id    = setting_id,
		type          = "numeric",
		default_value = 100,
		range         = { 0, 100 },
	}
end

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			-- One keybind for every screen. Which one opens depends on where you
			-- are: the launcher in the Mourningstar, the collected buffs in a
			-- mission, and the two hub screens are tabs of each other.
			{
				setting_id      = "menu_keybind",
				type            = "keybind",
				default_value   = {},
				keybind_trigger = "pressed",
				keybind_type    = "function_call",
				function_name   = "toggle_menu",
			},
			-- Separate from menu_keybind rather than another context of it: the
			-- vote screen is the one thing you want to open *while* a mission is
			-- being played, and the mission context of that key is already the
			-- collected-buffs screen.
			{
				setting_id      = "vote_keybind",
				type            = "keybind",
				default_value   = {},
				keybind_trigger = "pressed",
				keybind_type    = "function_call",
				function_name   = "toggle_vote",
			},
			-- The same thing from the options menu, for anyone who has not bound
			-- a key. A dropdown, not a button: DMF has no button widget type.
			-- on_setting_changed resets it to "none" so it can be picked again.
			{
				setting_id    = "open_menu",
				type          = "dropdown",
				default_value = "none",
				options = {
					{ text = "buff_toggle_open_none", value = "none" },
					{ text = "menu_open_now",         value = "open" },
				},
			},
			{
				setting_id    = "preload_horde_assets",
				type          = "checkbox",
				default_value = true,
			},
			{
				setting_id    = "end_screen_extra_seconds",
				type          = "numeric",
				default_value = 30,
				range         = { 0, 180 },
			},
			{
				setting_id = "group_testing",
				type = "group",
				sub_widgets = {
					{
						setting_id    = "debug_logging",
						type          = "checkbox",
						default_value = false,
					},
					{
						setting_id      = "debug_end_mission_won_keybind",
						type            = "keybind",
						default_value   = {},
						keybind_trigger = "pressed",
						keybind_type    = "function_call",
						function_name   = "debug_end_mission_won",
					},
					{
						setting_id      = "debug_end_mission_lost_keybind",
						type            = "keybind",
						default_value   = {},
						keybind_trigger = "pressed",
						keybind_type    = "function_call",
						function_name   = "debug_end_mission_lost",
					},
				},
			},
		},
	},
}
