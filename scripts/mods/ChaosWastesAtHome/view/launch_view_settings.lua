local launch_view_settings = {
	-- Width only. The height is derived in the definitions file from the preview
	-- and the text that has to fit under it.
	card_size = { 460 },
	card_spacing = 40,
	slider_size = { 700, 44 },
	slider_label_width = 260,
	button_height = 44,
	shading_environment = "content/shading_environments/ui/system_menu",
}

return settings("ChaosWastesLaunchViewSettings", launch_view_settings)
