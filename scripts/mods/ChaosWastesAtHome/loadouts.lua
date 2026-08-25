local mod = get_mod("ChaosWastesAtHome")
local DMF = get_mod("DMF")

-- Named snapshots of the mod's configuration, one file each.
--
-- ---------------------------------------------------------------------------
-- WHERE THE FILES GO, AND WHY NOT THE MOD FOLDER
-- ---------------------------------------------------------------------------
--
-- %APPDATA%/Fatshark/Darktide/ChaosWastesAtHome/loadouts/
--
-- The obvious place is the mod's own folder, and it is wrong twice over.
-- Pilgrimage's fileio.lua records that os.execute("mkdir ...") did nothing when
-- it tried to create a directory there -- the game lives under Program Files and
-- the process cannot write to it. And even if it could, a mod update means
-- re-extracting that folder, which would take the player's loadouts with it.
--
-- APPDATA is writable, is where user_settings.config already lives, and survives
-- reinstalling the mod. peril_tracker writes its sessions there the same way and
-- has shipped doing so; this module is that approach with the serialisation
-- swapped.
--
-- ---------------------------------------------------------------------------
-- WHY LUA LITERALS AND NOT JSON
-- ---------------------------------------------------------------------------
--
-- cjson is not present on a normal install (Pilgrimage checked). JSON therefore
-- needs a hand-written encoder AND a hand-written decoder. A Lua table literal
-- needs only the encoder, because loadstring reads it back -- so it is half the
-- code and the half that is left is the easy half.
--
-- The cost is that loading a loadout executes it. These are files the player
-- wrote, in the player's own AppData, so that is the same trust level as the
-- rest of the mod folder -- but it is why load() runs them in a pcall and takes
-- only the fields it expects rather than trusting the shape.

local loadouts = {}

-- Copied out of Mods.lua once and parked in a DMF persistent table.
--
-- Both libraries are captured at load time rather than looked up per call
-- because `Mods` is not guaranteed to still be there later, and the persistent
-- table means a mod reload reuses the copy rather than depending on `Mods`
-- surviving to the reload. Same pattern as peril_tracker's libs/os.lua.
local _io = DMF:persistent_table("_cwah_io")

if not _io.initialized then
	local source = rawget(_G, "Mods")
	source = source and source.lua and source.lua.io

	if source then
		_io = DMF.deepcopy(source)
		_io.initialized = true
	end
end

local _os = DMF:persistent_table("_cwah_os")

if not _os.initialized then
	local source = rawget(_G, "Mods")
	source = source and source.lua and source.lua.os

	if source then
		_os = DMF.deepcopy(source)
		_os.initialized = true
	end
end

local MOD_NAME = "ChaosWastesAtHome"
local EXTENSION = ".lua"

-- Settings that must NOT travel in a snapshot.
--
-- This list is the real definition of what a loadout controls, and it mirrors
-- the split in the UI: everything on the Settings tab and the Rollable Buffs tab
-- belongs to the loadout, everything left in the DMF options menu is global. If
-- an option moves between the two, it moves here too.
--
-- GLOBAL, deliberately:
--   the keybinds              switching loadout must not rebind the player's keys
--   open_menu                 a dropdown that only fires an action, reset on read
--   preload_horde_assets      a load-time cost, not a way to play
--   end_screen_extra_seconds  a reading-speed preference, not a run setting
--
-- MACHINERY, and must be excluded or the feature eats itself:
--   active_loadout / default_loadout -- a loadout carrying these would rewrite
--   which loadout is active the moment it was applied, and the auto-save right
--   after would write that back into the file. A loop, not an edge case.
local EXCLUDED = {
	active_loadout = true,
	default_loadout = true,
	open_menu = true,

	menu_keybind = true,
	debug_end_mission_won_keybind = true,
	debug_end_mission_lost_keybind = true,
	preload_horde_assets = true,
	end_screen_extra_seconds = true,
	debug_logging = true,
}

-- The icon set: the game's own 25 loadout preset symbols, and only those.
--
-- These are MATERIAL paths, so they go in as the texture pass's `value` -- the
-- same way view_element_profile_presets draws them, and the same way
-- BetterLoadouts does. They cannot go through ui_default_base's texture_map,
-- which takes a texture path, not a material.
--
-- This started as those 25 plus the 29 extras BetterLoadouts curated, on the
-- reasoning that a shipping mod already drew them. In game, only some of them
-- ever appeared. The 25 come from the inventory packages, which are loaded the
-- whole time you are in the Mourningstar -- verified live with
-- Managers.package:has_loaded. The extras came from the HUD, mission-board and
-- circumstance packages, which are not: BetterLoadouts draws its bar inside the
-- inventory views, where whatever it needs is already resident, and a
-- standalone view opened from the hub has no such guarantee. A material that is
-- not resident draws nothing and logs nothing, so the failure is silent.
--
-- Anything added here must be resident wherever this strip is drawn, which in
-- practice means: taken from a view that is open at the same time as ours.
loadouts.ICONS = {}

for i = 1, 25 do
	loadouts.ICONS[i] = "content/ui/materials/icons/presets/preset_" .. string.format("%02d", i)
end

loadouts.ACTIVE_SETTING = "active_loadout"
loadouts.DEFAULT_SETTING = "default_loadout"

-- ---------------------------------------------------------------------------
-- Paths
-- ---------------------------------------------------------------------------

loadouts.available = function ()
	return _io ~= nil and _io.open ~= nil and _os ~= nil and _os.getenv ~= nil
end

local function _dir()
	if not loadouts.available() then
		return nil
	end

	local ok, appdata = pcall(_os.getenv, "APPDATA")

	if not ok or not appdata or appdata == "" then
		return nil
	end

	return (appdata:gsub("\\", "/")) .. "/Fatshark/Darktide/" .. MOD_NAME .. "/loadouts/"
end

loadouts.directory = _dir

-- os.rename onto itself: succeeds for something that exists, and the error code
-- for "permission denied" also means it exists. Borrowed from peril_io, which
-- uses it for exactly this -- there is no stat() to call.
--
-- NOT wrapped in pcall, and that is the whole point. pcall reports whether the
-- call threw; os.rename does not throw, it returns nil plus a message and a code.
-- Wrapping it means reading pcall's success instead of rename's, which is true
-- every time -- so every directory looks like it exists, mkdir never runs, and
-- every write then fails against a folder that was never created.
local function _dir_exists(path)
	if not _os.rename then
		return false
	end

	local ok, _, code = _os.rename(path, path)

	if ok then
		return true
	end

	return code == 13
end

loadouts.ensure_dir = function ()
	local dir = _dir()

	if not dir then
		return false
	end

	if _dir_exists(dir) then
		return true
	end

	if not _os.execute then
		return false
	end

	-- Creates the intermediate ChaosWastesAtHome folder as well; mkdir on
	-- Windows does that for a nested path without needing a flag.
	pcall(_os.execute, 'mkdir "' .. dir:gsub("/", "\\") .. '"')

	return _dir_exists(dir)
end

-- ---------------------------------------------------------------------------
-- Serialisation
-- ---------------------------------------------------------------------------

local function _quote(text)
	return string.format("%q", tostring(text))
end

-- Only what a settings table can actually hold: strings, numbers, booleans and
-- nested tables of the same. Anything else is dropped rather than guessed at --
-- a settings value that is a function or userdata is a bug somewhere else, and
-- writing a broken file would turn it into a bug here.
local function _serialize(value, indent)
	local t = type(value)

	if t == "string" then
		return _quote(value)
	elseif t == "number" or t == "boolean" then
		return tostring(value)
	elseif t ~= "table" then
		return nil
	end

	local pad = string.rep("\t", indent)
	local inner_pad = string.rep("\t", indent + 1)
	local parts = {}

	-- Sorted so a file rewritten with identical settings is byte-identical.
	-- Without it the pairs() order shuffles and every save looks like a change,
	-- which makes the files useless for diffing or for sharing.
	local keys = {}

	for key in pairs(value) do
		if type(key) == "string" or type(key) == "number" then
			keys[#keys + 1] = key
		end
	end

	table.sort(keys, function (a, b)
		return tostring(a) < tostring(b)
	end)

	for i = 1, #keys do
		local key = keys[i]
		local encoded = _serialize(value[key], indent + 1)

		if encoded then
			local key_text

			if type(key) == "string" and key:match("^[%a_][%w_]*$") then
				key_text = key
			else
				key_text = "[" .. (type(key) == "number" and tostring(key) or _quote(key)) .. "]"
			end

			parts[#parts + 1] = inner_pad .. key_text .. " = " .. encoded .. ","
		end
	end

	if #parts == 0 then
		return "{}"
	end

	return "{\n" .. table.concat(parts, "\n") .. "\n" .. pad .. "}"
end

-- ---------------------------------------------------------------------------
-- Files
-- ---------------------------------------------------------------------------

-- Filenames come from player-typed names, so everything outside a safe set is
-- collapsed. The display name is kept inside the file, so a collapsed filename
-- costs nothing the player can see.
loadouts.slugify = function (name)
	local slug = tostring(name or ""):lower():gsub("[^%w%-_]+", "_"):gsub("^_+", ""):gsub("_+$", "")

	if slug == "" then
		slug = "loadout"
	end

	return slug:sub(1, 48)
end

local function _path(slug)
	local dir = _dir()

	return dir and (dir .. slug .. EXTENSION) or nil
end

loadouts.write = function (slug, data)
	if not loadouts.ensure_dir() then
		mod:error("could not create the loadouts folder - loadouts will not be saved")

		return false
	end

	local path = _path(slug)
	local body = _serialize(data, 0)

	if not path or not body then
		return false
	end

	local ok, file = pcall(_io.open, path, "w")

	if not ok or not file then
		mod:error("could not write loadout '%s'", tostring(slug))

		return false
	end

	local wrote = pcall(function ()
		file:write("-- ChaosWastesAtHome loadout. Edit `name` to rename it.\nreturn " .. body .. "\n")
		file:close()
	end)

	if not wrote then
		mod:error("could not write loadout '%s'", tostring(slug))

		return false
	end

	mod:debug_log("loadout saved: %s", tostring(slug))

	return true
end

loadouts.read = function (slug)
	local path = _path(slug)

	if not path then
		return nil
	end

	local ok, file = pcall(_io.open, path, "r")

	if not ok or not file then
		return nil
	end

	local read_ok, body = pcall(function ()
		local text = file:read("*all")

		file:close()

		return text
	end)

	if not read_ok or not body then
		return nil
	end

	local loadstring_fn = rawget(_G, "Mods")
	loadstring_fn = loadstring_fn and loadstring_fn.lua and loadstring_fn.lua.loadstring

	if not loadstring_fn then
		return nil
	end

	local chunk = loadstring_fn(body, slug)

	if not chunk then
		mod:error("loadout '%s' is not valid Lua and was skipped", tostring(slug))

		return nil
	end

	local exec_ok, data = pcall(chunk)

	-- Takes only the two fields it expects rather than trusting the shape: this
	-- is a file the player can hand-edit, and a malformed one should drop out of
	-- the list rather than poison everything downstream.
	if not exec_ok or type(data) ~= "table" or type(data.settings) ~= "table" then
		mod:error("loadout '%s' is malformed and was skipped", tostring(slug))

		return nil
	end

	return {
		slug = slug,
		name = type(data.name) == "string" and data.name or slug,
		icon = type(data.icon) == "string" and data.icon or nil,
		settings = data.settings,
	}
end

loadouts.delete = function (slug)
	local path = _path(slug)

	if not path or not _os.remove then
		return false
	end

	local ok = pcall(_os.remove, path)

	return ok and true or false
end

-- Which loadouts exist, from an index file rather than by listing the folder.
--
-- Listing means io.popen('dir ...'), which spawns cmd.exe. Measured at FIVE
-- SECONDS of hard stall the first time, on a directory that did not even exist
-- -- and it would run on every open of the view. Spawning a console process out
-- of a fullscreen DirectX game to find out what files are in a folder is not a
-- reasonable thing to do once, let alone per click.
--
-- The index is written whenever a loadout is created or deleted, so it stays in
-- step by construction. The cost is that a file someone hand-copies into the
-- folder is not noticed until a rescan, which is what loadouts.rescan is for --
-- deliberately an explicit action, so the process spawn is something the player
-- asks for rather than something they get for opening a menu.
local INDEX = "_index"

local function _read_index()
	local data = loadouts.read(INDEX)
	local slugs = data and data.settings and data.settings.slugs

	return type(slugs) == "table" and slugs or {}
end

local function _write_index(slugs)
	return loadouts.write(INDEX, { name = INDEX, settings = { slugs = slugs } })
end

loadouts.index_add = function (slug)
	local slugs = _read_index()

	for i = 1, #slugs do
		if slugs[i] == slug then
			return true
		end
	end

	slugs[#slugs + 1] = slug

	return _write_index(slugs)
end

loadouts.index_remove = function (slug)
	local slugs = _read_index()
	local kept = {}

	for i = 1, #slugs do
		if slugs[i] ~= slug then
			kept[#kept + 1] = slugs[i]
		end
	end

	return _write_index(kept)
end

loadouts.list = function ()
	local dir = _dir()

	if not dir or not _dir_exists(dir) then
		return {}
	end

	local slugs = _read_index()
	local result = {}

	for i = 1, #slugs do
		local data = loadouts.read(slugs[i])

		-- A slug in the index with no file behind it is a loadout deleted
		-- outside the game. Skipped rather than repaired here: list() is called
		-- from a draw path and should not be writing files.
		if data then
			result[#result + 1] = data
		end
	end

	table.sort(result, function (a, b)
		return a.name:lower() < b.name:lower()
	end)

	return result
end

-- The only thing that still spawns a process, and only when asked.
loadouts.rescan = function ()
	local dir = _dir()

	if not dir or not _io.popen or not _dir_exists(dir) then
		return false
	end

	local ok, pipe = pcall(_io.popen, 'dir "' .. dir:gsub("/", "\\") .. '" /b')

	if not ok or not pipe then
		return false
	end

	local found = {}

	pcall(function ()
		for entry in pipe:lines() do
			local slug = entry:match("^(.+)%" .. EXTENSION .. "$")

			if slug and slug ~= INDEX then
				found[#found + 1] = slug
			end
		end

		pipe:close()
	end)

	return _write_index(found)
end

-- ---------------------------------------------------------------------------
-- Snapshot and apply
-- ---------------------------------------------------------------------------

-- Ids from the engine's settings copy, VALUES from mod:get. Never values from
-- the engine copy -- it is stale, often by minutes.
--
-- `Application.user_setting("mods_settings")` is not DMF's settings table.
-- DMF reads it once into a local at load (settings.lua:12) and every mod:set
-- mutates only that local; the engine copy is refreshed in save_all_settings,
-- which runs on a game state change, when the options menu closes, and on
-- reload. Measured live mid-session: mod:get said 80 while the engine copy
-- still said 50.
--
-- That is what made every loadout converge. Applying a loadout writes through
-- mod:set, so the engine copy still held the OUTGOING loadout's values; the
-- auto-save a second later snapshotted those and wrote them into the newly
-- selected loadout. Switch away and back and the loadout had become a copy of
-- whichever one you were on before -- exactly the reported symptom.
--
-- The flush first is for the id list, not the values: a setting written this
-- session and never flushed does not appear in the engine copy at all, and a
-- key missing here is a setting silently absent from every loadout. Enumerating
-- rather than keeping a hand-written id list is still the point -- that list
-- would go stale the next time an option is added.
loadouts.snapshot = function ()
	local dmf = get_mod("DMF")

	if dmf and dmf.save_unsaved_settings_to_file then
		pcall(dmf.save_unsaved_settings_to_file)
	end

	local all = Application.user_setting("mods_settings")
	local mine = all and all[MOD_NAME]

	if type(mine) ~= "table" then
		return {}
	end

	local out = {}

	for key in pairs(mine) do
		if not EXCLUDED[key] then
			-- mod:get clones table settings, so the snapshot never aliases the
			-- live buff sets.
			out[key] = mod:get(key)
		end
	end

	return out
end

-- mod:set, never Application.set_user_setting. DMF caches its own copy of the
-- settings table at load; writing underneath it leaves the two disagreeing until
-- something else forces a reload.
--
-- notify = false on every write, then one notify at the end: on_setting_changed
-- is what triggers auto-save, and letting it fire per key would write the file
-- once per setting while applying a loadout.
loadouts.apply = function (settings)
	if type(settings) ~= "table" then
		return false
	end

	local applied = 0

	for key, value in pairs(settings) do
		if not EXCLUDED[key] then
			local ok = pcall(mod.set, mod, key, value, false)

			if ok then
				applied = applied + 1
			end
		end
	end

	mod:info("applied %d setting(s) from a loadout", applied)

	return true
end

return loadouts
