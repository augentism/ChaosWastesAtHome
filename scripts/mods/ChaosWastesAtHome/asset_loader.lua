local mod = get_mod("ChaosWastesAtHome")

-- Optionally pulls the Mortis mission package in alongside a normal mission's
-- assets, so the horde buff icons and particle effects are actually present
-- rather than being worked around.
--
-- The buff icons and VFX are not in any Lua-declared UI package -- every one
-- of those is already loaded and still lacks them. They ship with the Mortis
-- mission content, which is why a regular mission renders placeholder icons
-- and cannot spawn the buff effects.
--
-- Off by default because this is a *level* package: potentially geometry,
-- units and audio for the whole Psykhanium, not just the handful of textures
-- and effects we want. The cost is unknown until measured on real hardware,
-- so this is offered as a switch with timing reported rather than turned on
-- for everyone.

local asset_loader = {}

local HORDE_PACKAGE = "content/levels/horde/missions/mission_psykhanium"
local REFERENCE = "ChaosWastesAtHome"

-- Held on the mod table so a mod reload cannot lose the handle and leak the
-- package for the rest of the session.
mod._asset_state = mod._asset_state or {
	package_id = nil,
	loading = false,
	started_at = nil,
	failed = false,
}

local state = mod._asset_state

asset_loader.is_loaded = function ()
	return state.package_id ~= nil
end

asset_loader.request = function ()
	if not mod:get("preload_horde_assets") then
		return false
	end

	if state.package_id or state.loading or state.failed then
		return false
	end

	local package_manager = Managers.package

	if not package_manager then
		return false
	end

	-- Ask before loading: a package name that does not resolve would other-
	-- wise be a hard failure inside the package manager rather than something
	-- we can report and skip.
	if Application and Application.can_get_resource then
		local ok, exists = pcall(Application.can_get_resource, "package", HORDE_PACKAGE)

		if ok and not exists then
			state.failed = true

			mod:error("horde asset package not found (%s) - buff icons and effects will stay unavailable", HORDE_PACKAGE)

			return false
		end
	end

	state.loading = true
	state.started_at = os.clock()

	local ok, err = pcall(package_manager.load, package_manager, HORDE_PACKAGE, REFERENCE, function (package_id)
		state.package_id = package_id
		state.loading = false

		local elapsed = state.started_at and (os.clock() - state.started_at) or -1

		mod:info("horde assets loaded in %.1fs - buff icons and effects should now render", elapsed)
	end)

	if not ok then
		state.loading = false
		state.failed = true

		mod:error("could not load horde assets: %s", tostring(err))

		return false
	end

	mod:info("loading horde assets (%s) ...", HORDE_PACKAGE)

	return true
end

-- Released when the run ends rather than at every mission boundary: a chain
-- re-uses the same assets each hop, and unloading between missions would pay
-- the load cost repeatedly for no benefit.
asset_loader.release = function ()
	if not state.package_id then
		return false
	end

	local package_manager = Managers.package

	if not package_manager then
		return false
	end

	local ok, err = pcall(package_manager.release, package_manager, state.package_id)

	if not ok then
		mod:error("could not release horde assets: %s", tostring(err))
	end

	state.package_id = nil
	state.loading = false
	state.started_at = nil

	mod:debug_log("released horde assets")

	return ok
end

return asset_loader
