return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`ChaosWastesAtHome` encountered an error loading the Darktide Mod Framework.")

		new_mod("ChaosWastesAtHome", {
			mod_script       = "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/ChaosWastesAtHome",
			mod_data         = "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/ChaosWastesAtHome_data",
			mod_localization = "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/ChaosWastesAtHome_localization",
		})
	end,
	packages = {},
}
