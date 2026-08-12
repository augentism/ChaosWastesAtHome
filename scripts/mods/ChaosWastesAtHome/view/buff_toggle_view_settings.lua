local buff_toggle_view_settings = {
	scrollbar_width = 10,
	-- left: the family / category filter list
	group_grid_size = { 320, 620 },
	-- middle: the buffs in the selected group
	buff_grid_size = { 620, 620 },
	-- right: the selected buff's card
	detail_panel_size = { 460, 620 },
	grid_spacing = { 0, 6 },
	grid_blur_edge_size = { 8, 8 },
	shading_environment = "content/shading_environments/ui/system_menu",
}

return settings("ChaosWastesBuffToggleViewSettings", buff_toggle_view_settings)
