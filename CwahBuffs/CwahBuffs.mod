return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Chaos Wastes at Home: Core Blessings` encountered an error loading the Darktide Mod Framework.")

		new_mod("CwahBuffs", {
			mod_script       = "CwahBuffs/scripts/mods/CwahBuffs/CwahBuffs",
			mod_data         = "CwahBuffs/scripts/mods/CwahBuffs/CwahBuffs_data",
			mod_localization = "CwahBuffs/scripts/mods/CwahBuffs/CwahBuffs_localization",
		})
	end,
	packages = {},
}
