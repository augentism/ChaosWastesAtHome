local mod = get_mod("ChaosWastesAtHome")
local DMF = get_mod("DMF")
local recipes = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/buff_recipes")
local store = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/recipe_store")
local HOST_TYPES = require("scripts/settings/network/matchmaking_constants").HOST_TYPES

-- Capture at boot, like loadouts.lua: Mods.lua is not guaranteed later.
local source = rawget(_G, "Mods")
local file_io = source and source.lua and source.lua.io
file_io = file_io and DMF.deepcopy(file_io)
local file_os = source and source.lua and source.lua.os
local ffi = source and source.lua and source.lua.ffi

local function replace_file(from, to)
	if ffi and ffi.os == "Windows" then
		if not pcall(ffi.typeof, "CwahRecipeFileWChar") then
			ffi.cdef[[typedef unsigned short CwahRecipeFileWChar;
			int MultiByteToWideChar(unsigned int, unsigned long, const char*, int, CwahRecipeFileWChar*, int);
			int MoveFileExW(const CwahRecipeFileWChar*, const CwahRecipeFileWChar*, unsigned long);]]
		end
		local kernel = ffi.load("kernel32")
		local function wide(text)
			local count = kernel.MultiByteToWideChar(65001, 0, text, -1, nil, 0)
			if count <= 0 then error("Invalid recipe file path") end
			local buffer = ffi.new("CwahRecipeFileWChar[?]", count)
			if kernel.MultiByteToWideChar(65001, 0, text, -1, buffer, count) == 0 then error("Invalid recipe file path") end
			return buffer
		end
		return kernel.MoveFileExW(wide(from), wide(to), 9) ~= 0, "Windows file replacement failed"
	end
	if file_os and file_os.rename then return file_os.rename(from, to) end
	return false, "Atomic file replacement unavailable"
end

local state = mod._user_buffs or { loaded = false, names = {}, count = 0, errors = {} }
mod._user_buffs = state
local user_buffs = {}
local active_registry, active_pool

local function slot_id(index, kind)
	return string.format("player_slot_%02d_%s", index, kind)
end

local function dormant_slots()
	local entries = {}
	for i = 1, recipes.max_buffs do
		for _, kind in ipairs({ "recipe", "stack" }) do
			entries[#entries + 1] = { id = slot_id(i, kind), user_recipe = true,
				definition_signature = "recipe-slot-v2/empty", template = function ()
					return { class_name = "buff", predicted = false, max_stacks = 1, max_stacks_cap = 1 }
				end }
		end
	end
	return entries
end

-- Network names never depend on personal recipe IDs. Only their contents do.
user_buffs.name = function (id, kind)
	local index = state.ids and state.ids[id]
	return index and active_registry.buff_id(mod, slot_id(index, kind or "recipe")) or nil
end

user_buffs.menu_entries = function ()
	local sync = mod.recipe_sync
	local r = get_mod("Realms")
	if not (r and r.network_register) and mod.manager and state.session_menu then return state.session_menu end
	return sync and sync.ready() and state.session_menu or state.saved_menu or {}
end

user_buffs.menu_changed = function () if active_pool then active_pool.invalidate() end end

-- Recipes supplement the chosen family's regular pool, never its priority picks.
user_buffs.family_pool = function (original)
	local out, seen = {}, {}
	for _, name in ipairs(original or {}) do
		if not seen[name] then out[#out + 1] = name; seen[name] = true end
	end
	for _, entry in ipairs(state.session_menu or {}) do
		if entry.is_family_buff and not seen[entry.name] then
			out[#out + 1] = entry.name; seen[entry.name] = true
		end
	end
	return out
end

local function menu_entries(definitions, entries, session)
	local out, n = {}, 0
	local by_id = {}
	for _, entry in ipairs(entries) do by_id[entry.id] = entry end
	for _, definition in ipairs(definitions) do
		if definition.enabled then
			n = n + 1
			local entry = by_id[session and slot_id(n, "recipe") or "recipe_" .. definition.id]
			if entry then
				out[#out + 1] = {
					name = session and active_registry.buff_id(mod, entry.id)
						or active_registry.buff_id(mod, "recipe_" .. definition.id),
					preference = active_registry.buff_id(mod, "recipe_" .. definition.id),
					title = definition.name, description = entry.description.en:gsub("%%%%", "%%"),
					is_family_buff = definition.legendary == false,
					icon = "content/ui/textures/icons/buffs/hud/horde_buffs/small_buffs/hordes_buff_damage_increase",
				}
			end
		end
	end
	return out
end

local function compile(definitions, slots)
	return recipes.compile(definitions, {
		settings = require("scripts/settings/buff/buff_settings"),
		checks = require("scripts/settings/buff/helper_functions/check_proc_functions"),
		active = user_buffs.active, carrier_active = user_buffs.carrier_active,
		slot_id = slots and slot_id or nil,
	})
end

user_buffs.can_replace = function ()
	-- A lobby alone isn't enough: old extension systems must be gone too.
	local s = Managers and Managers.state
	return not mod.manager and not (s and (s.game_session or s.extension))
end

-- Realms recipes require the synchronized lobby catalogue. The fallback is
-- strictly singleplay, never a temporarily peerless unsynchronized Realms host.
user_buffs.allowed_session = function ()
	if not mod:is_enabled() then return false end
	local sync = mod.recipe_sync
	if sync and sync.active() then return true end
	local session = Managers.multiplayer_session
	if not session or type(session.host_type) ~= "function" then return false end
	local ok, host_type = pcall(session.host_type, session)
	return ok and host_type == HOST_TYPES.singleplay
		and not (mod.has_peers and mod.has_peers())
end

user_buffs.active = function ()
	return mod.manager ~= nil and mod.has_authority() and user_buffs.allowed_session()
end

user_buffs.carrier_active = function ()
	return mod.manager ~= nil and user_buffs.allowed_session()
end

user_buffs.can_grant = function (name)
	return not state.names[name] or user_buffs.active()
end

user_buffs.exclude = function (excluded)
	if not user_buffs.allowed_session() then
		for name in pairs(state.names) do excluded[name] = true end
	end
end

local STARTER = [[# Player-created CWaH buffs. Use Reload from disk in the Player Buff Editor after editing.
# One [stable_id] block per buff. Remove the # prefixes to enable the example.
# Amount/chance are percentages; cooldown/duration are seconds.
# One stack per trigger. Each trigger refreshes the shared timer, even at cap.
# Realms lobbies use the host's recipes, without changing your saved file.
# Full trigger/effect list: ChaosWastesAtHome/docs/player-buffs.md
#
# [momentum]
# name = Veteran's Momentum
# trigger = elite_kill
# effect = attack_speed
# amount = 2
# max_stacks = 5
# duration = 10
# chance = 100
# cooldown = 0
]]

-- Returns text/error; a missing file gets a commented example, never active
-- default buffs. Other I/O failures must never overwrite an existing file.
user_buffs.read_file = function (io_lib, path)
	local file, err, code = io_lib.open(path, "rb")
	if not file then
		if code ~= 2 then return nil, tostring(err) end
		local created, create_err = io_lib.open(path, "wb")
		if not created then return nil, tostring(create_err) end
		local written, write_err = created:write(STARTER)
		local closed, close_err = created:close()
		if not written or not closed then return nil, tostring(write_err or close_err) end
		return STARTER
	end
	local text, read_err = file:read(recipes.max_bytes + 1)
	file:close()
	if text == nil and read_err then return nil, tostring(read_err) end
	return text or ""
end

user_buffs.load = function (loadouts, registry, pool)
	active_registry, active_pool = registry, pool
	if state.loaded then return end
	state.loaded = true
	local directory = loadouts.directory()
	state.path = directory and (directory:gsub("/loadouts/$", "/") .. "buffs.txt")
	local function report(message)
		state.errors[#state.errors + 1] = message
		if #state.errors <= 8 then
			mod:error("player buffs: %s", message:gsub("%%", "%%%%"))
		elseif #state.errors == 9 then
			mod:error("player buffs: additional errors omitted; fix the reported blocks and restart")
		end
	end
	do
		-- Reserve independently of personal-file access/validation failures, so
		-- a client can still receive a host catalogue with an unreadable file.
		state.deferred = true
		local slots = dormant_slots()
		local count, errors = registry.register_buffs(mod, slots, {
			category = "cwah_player_buffs", category_label = "Player Buffs",
		})
		for _, problem in ipairs(errors) do report(problem) end
		if count ~= #slots then state.install_failed = "Could not reserve recipe slots; restart Darktide" end
		for _, entry in ipairs(slots) do state.names[registry.buff_id(mod, entry.id)] = true end
	end
	if not state.path or not file_io or not loadouts.ensure_dir() then
		report("cannot access the AppData configuration directory")
		return
	end
	local ok, text, err = pcall(user_buffs.read_file, file_io, state.path)
	if not ok or text == nil then report(tostring(ok and err or text)); return end
	local definitions, problems = recipes.parse(text)
	for _, problem in ipairs(problems) do report(problem) end
	state.local_text = recipes.serialize(definitions)
	state.source_text = text
	state.saved_count = #definitions
	do
		local preview, problems = compile(definitions, false)
		for _, problem in ipairs(problems) do report(problem) end
		state.saved_menu = menu_entries(definitions, preview, false)
		pool.invalidate()
		mod:info("loaded %d saved recipe(s) for the menu; reserved 64 dormant recipe slot pairs", #definitions)
		return
	end
end

user_buffs.pending = function ()
	local r = get_mod("Realms")
	return mod.manager ~= nil or (mod._run and mod._run.launched == true)
		or (r and r._preparation and r._preparation.is_waiting() and r._preparation.mission_name() ~= "hub_ship") or false
end

user_buffs.definitions = function ()
	return recipes.parse(state.source_text or "")
end

local function accept_saved(text, definitions, entries)
	state.source_text, state.local_text = text, recipes.serialize(definitions)
	state.saved_count, state.errors = #definitions, {}
	state.saved_menu = menu_entries(definitions, entries, false)
	user_buffs.menu_changed()
	return true, user_buffs.pending() and "Saved for the next session. Leave the current run/lobby before applying edits."
		or "Saved and reloaded. Your Player Buffs menu is up to date."
end

local function validated(text)
	local definitions, errors = recipes.parse(text)
	if #errors > 0 then return nil, table.concat(errors, "; ") end
	local entries, problems = compile(definitions, false)
	if #problems > 0 then return nil, table.concat(problems, "; ") end
	return definitions, entries
end

user_buffs.reload = function ()
	if not file_io or not state.path then return false, "Recipe file I/O unavailable" end
	local ok, text, err = pcall(store.read, file_io, state.path)
	if not ok or not text then return false, tostring(ok and err or text) end
	local definitions, entries = validated(text)
	if not definitions then return false, entries end
	return accept_saved(text, definitions, entries)
end

local fields = { "name", "trigger", "effect", "amount", "max_stacks", "duration", "chance", "cooldown", "enabled", "legendary" }
user_buffs.validate_definition = function (definition)
	if type(definition) ~= "table" or type(definition.id) ~= "string" or not definition.id:match("^[a-z][a-z0-9_]*$") then
		return nil, "ID must start with a lowercase letter and contain only lowercase letters, digits and underscores"
	end
	local lines = { "[" .. definition.id .. "]" }
	for _, key in ipairs(fields) do
		local value = definition[key]
		if value ~= nil then
			value = tostring(value)
			if value:find("[\r\n]") then return nil, "Fields cannot contain line breaks" end
			lines[#lines + 1] = key .. " = " .. value
		end
	end
	local definitions, entries = validated(table.concat(lines, "\n"))
	if not definitions then return nil, entries end
	return definitions[1], entries[1] and entries[1].description.en:gsub("%%%%", "%%") or "Disabled recipe; it will not be offered."
end

local function commit(definitions)
	local text = recipes.serialize(definitions, true)
	local parsed, entries = validated(text)
	if not parsed then return false, entries end
	if not file_io or not state.path then return false, "Recipe file I/O unavailable" end
	local ok, saved, err = pcall(store.save, file_io, replace_file, state.path, state.source_text, text)
	if not ok or not saved then return false, tostring(ok and err or saved) end
	return accept_saved(text, parsed, entries)
end

user_buffs.save_definition = function (definition, original_id)
	local parsed, err = user_buffs.validate_definition(definition)
	if not parsed then return false, err end
	local definitions, errors = user_buffs.definitions()
	if #errors > 0 then return false, "Fix errors in buffs.txt and reload before editing: " .. table.concat(errors, "; ") end
	local found = original_id == nil
	local output = {}
	for _, existing in ipairs(definitions) do
		if existing.id == original_id then found = true
		elseif existing.id == parsed.id then return false, "That ID already exists; load it before editing"
		else output[#output + 1] = existing end
	end
	if not found then return false, "The original recipe no longer exists; reload it before saving" end
	output[#output + 1] = parsed
	table.sort(output, function (a, b) return a.id < b.id end)
	return commit(output)
end

user_buffs.delete_definition = function (id)
	local definitions, errors = user_buffs.definitions()
	if #errors > 0 then return false, "Fix errors in buffs.txt and reload before deleting recipes" end
	for i, definition in ipairs(definitions) do
		if definition.id == id then table.remove(definitions, i); return commit(definitions) end
	end
	return false, "No saved recipe selected"
end

user_buffs.update = function ()
	local r = get_mod("Realms")
	if r and r.network_register then return end
	if not mod:is_enabled() or not state.loaded or not user_buffs.can_replace() then return end
	local text = mod._run and mod._run.recipe_catalogue or state.local_text or ""
	user_buffs.install_text(text)
end

-- Replace only dormant session contents; existing IDs are never removed/rebased.
user_buffs.install_text = function (text)
	if not active_registry then return false, "recipe loader is not ready" end
	if state.install_failed then return false, state.install_failed end
	if state.installed_text == text then return true end
	if not user_buffs.can_replace() then return false, "Previous gameplay is still tearing down" end
	local definitions, problems = recipes.parse(text)
	if #problems > 0 then return false, table.concat(problems, "; ") end
	if recipes.serialize(definitions) ~= text then return false, "noncanonical recipe catalogue" end
	local entries, errors = compile(definitions, true)
	if #errors > 0 then return false, table.concat(errors, "; ") end
	state.generation = (state.generation or 0) + 1
	local batch = dormant_slots()
	for i, entry in ipairs(entries) do
		entry.localization_suffix = "_catalogue_" .. state.generation
		batch[i] = entry
	end
	local count, registration_errors = 0, {}
	if #batch > 0 then
		count, registration_errors = active_registry.register_buffs(mod, batch, {
			category = "cwah_player_buffs", category_label = "Player Buffs",
		})
	end
	if count ~= #batch or #registration_errors > 0 then
		state.install_failed = "Recipe registration failed; restart Darktide: " .. table.concat(registration_errors, "; ")
		return false, state.install_failed
	end
	state.installed_text = text
	state.count = #definitions
	state.ids = {}
	for i, definition in ipairs(definitions) do state.ids[definition.id] = i end
	state.session_menu = menu_entries(definitions, entries, true)
	-- An old run's slot names must never become grants from the next host.
	if mod._run then
		for name in pairs(state.names) do
			if mod._run.buffs then mod._run.buffs[name] = nil end
			for _, player in pairs(mod._run.players or {}) do
				if player.buffs then player.buffs[name] = nil end
			end
		end
	end
	active_pool.invalidate()
	return true
end

user_buffs.report = function ()
	mod:echo("Player buffs: %d registered, %d error(s). File: %s", state.count, #state.errors,
		(state.path or "unavailable"):gsub("%%", "%%%%"))
	for i = 1, math.min(#state.errors, 8) do
		mod:echo("%s", state.errors[i]:gsub("%%", "%%%%"))
	end
	if state.deferred then
		mod:echo("Saved recipes: %d. Host catalogue status: %s", state.saved_count or 0,
			((mod.recipe_sync and mod.recipe_sync.status()) or "waiting for lobby"):gsub("%%", "%%%%"))
	end
end

return user_buffs
