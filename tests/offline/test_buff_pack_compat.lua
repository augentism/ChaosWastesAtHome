-- Exercise the real addon entry points. Loading a catalogue installs effect
-- hooks, so count loads as well as registrations: rejecting duplicate IDs
-- after loading both catalogues would leave conflicting effects installed.
local harness = ...

local function scenario(installed, enabled, order, expected)
	return function (a)
		local previous_get_mod = get_mod
		local mods, loads, registrations = {}, {}, {}
		local core = { register_buffs = function () end }
		mods.ChaosWastesAtHome = core

		for _, name in ipairs(installed) do
			local addon = {}
			mods[name] = addon
			function addon:is_enabled()
				return enabled[name] ~= false
			end
			function addon:info() end
			function addon:error(message) error(message) end
			function addon:io_dofile(path)
				a.eq(path, name .. "/scripts/mods/" .. name .. "/catalogue", "catalogue path")
				loads[#loads + 1] = name
				return {
					register = function () registrations[#registrations + 1] = name end,
					legendary_upgrades = function () return {} end,
				}
			end
		end

		_G.get_mod = function (name) return mods[name] end
		local ok, err = pcall(function ()
			-- DMF executes all main scripts before any on_all_mods_loaded event.
			for _, name in ipairs(order) do
				harness.mod:io_dofile(name .. "/scripts/mods/" .. name .. "/" .. name)
			end
			for _, name in ipairs(order) do
				mods[name].on_all_mods_loaded()
			end
			a.count(loads, #expected, "effect catalogues loaded")
			a.count(registrations, #expected, "packs registered")
			for i, name in ipairs(expected) do
				a.eq(loads[i], name, "effect provider")
				a.eq(registrations[i], name, "buff provider")
				if name == "MourningBound" then
					a.eq(type(mods.MourningBound.legendary_upgrades), "function", "upgrade facade")
				end
			end
		end)
		_G.get_mod = previous_get_mod
		if not ok then error(err, 0) end
	end
end

local cw, mb = "CwahBuffs", "MourningBound"


return {
	{ "CwahBuffs works alone", scenario({ cw }, {}, { cw }, { cw }) },
	{ "MourningBound works alone", scenario({ mb }, {}, { mb }, { mb }) },
	{ "both catalogues load when CwahBuffs loads first", scenario({ cw, mb }, {}, { cw, mb }, { cw, mb }) },
	{ "both catalogues load when MourningBound loads first", scenario({ cw, mb }, {}, { mb, cw }, { mb, cw }) },
	{ "disabled MourningBound leaves CwahBuffs active", scenario({ cw, mb }, { [mb] = false }, { cw, mb }, { cw }) },
	{ "disabled CwahBuffs leaves MourningBound active", scenario({ cw, mb }, { [cw] = false }, { mb, cw }, { mb }) },
	{ "both disabled load no effects", scenario({ cw, mb }, { [cw] = false, [mb] = false }, { cw, mb }, {}) },
}
