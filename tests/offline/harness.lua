-- Enough of Darktide and DMF to load this mod's pure-logic modules under a
-- plain LuaJIT, with no game running.
--
-- The point is to test against the game's REAL data rather than a hand-written
-- imitation of it. `require` is redirected at the decompiled source tree, so
-- `hordes_buffs_data` hands back its actual 154 buff templates and
-- `mission_buffs_allowed_buffs` its actual seven families. A test that asserts
-- "every buff we offer is a real buff" therefore means something.
--
-- The cost is that the decompile is NOT the shipped build. CLAUDE.md records
-- that for engine method signatures; data tables drift far more slowly, but a
-- test here can still pass against stale data after a game patch. The in-game
-- tier is the authority; this tier is the fast filter.

local harness = {}

-- ---------------------------------------------------------------------------
-- Roots
-- ---------------------------------------------------------------------------

-- Set by run_tests.py. The fallback lets `luajit offline/run.lua` work from the
-- tests directory while poking at a single test by hand.
local ROOT = os.getenv("CWAH_TEST_ROOT")

if not ROOT or ROOT == "" then
	ROOT = "../../.."
end

ROOT = ROOT:gsub("/$", "") .. "/"

local ENGINE = ROOT .. "references/source/Darktide-Source-Code/"

harness.ROOT = ROOT
harness.ENGINE = ENGINE

-- ---------------------------------------------------------------------------
-- Engine globals the settings files reach for at load
-- ---------------------------------------------------------------------------

-- `settings()` creates no global -- foundation/utilities/settings.lua is
-- literally `return data_table`, which is why Breeds and friends are
-- require-only. Modelling it as identity is exactly right.
_G.settings = function (_name, t)
	return t
end

_G.upairs = pairs

local function _shallow_copy(t)
	local out = {}

	for k, v in pairs(t) do
		out[k] = v
	end

	return out
end

table.make_unique = table.make_unique or function (t)
	return t
end

table.shallow_copy = table.shallow_copy or _shallow_copy
table.clone = table.clone or _shallow_copy

table.append = table.append or function (a, b)
	for _, v in ipairs(b or {}) do
		a[#a + 1] = v
	end

	return a
end

table.enum = table.enum or function (...)
	local e = {}

	for i, v in ipairs({ ... }) do
		e[v] = i
		e[i] = v
	end

	return e
end

table.merge = table.merge or function (a, b)
	for k, v in pairs(b or {}) do
		a[k] = v
	end

	return a
end

table.keys = table.keys or function (t)
	local out = {}

	for k in pairs(t) do
		out[#out + 1] = k
	end

	return out
end

table.size = table.size or function (t)
	local n = 0

	for _ in pairs(t or {}) do
		n = n + 1
	end

	return n
end

-- ---------------------------------------------------------------------------
-- require, pointed at the decompile
-- ---------------------------------------------------------------------------

local engine_cache = {}
local load_failures = {}

local function _read(path)
	local f = io.open(path, "rb")

	if not f then
		return nil
	end

	local src = f:read("*a")

	f:close()

	-- These files carry a UTF-8 BOM, which loadstring will not accept.
	return (src:gsub("^\239\187\191", ""))
end

-- Missing or broken modules resolve to an empty table rather than raising.
-- Most of the engine tree is irrelevant to us and only reachable because some
-- data file requires a sibling for one constant; failing hard on those would
-- mean stubbing half the game to test a list of buff names.
--
-- The failures are recorded rather than swallowed -- harness.load_failures()
-- lets a test assert that the module IT cares about actually loaded, so an
-- empty table can never be mistaken for a passing assertion.
_G.require = function (path)
	if engine_cache[path] ~= nil then
		return engine_cache[path]
	end

	-- Claim the slot before executing so a cycle terminates instead of
	-- recursing. Anything that requires us back mid-load sees an empty table,
	-- which is what the real loader would hand it too.
	engine_cache[path] = {}

	local src = _read(ENGINE .. path .. ".lua")

	if not src then
		load_failures[path] = "not found"

		return engine_cache[path]
	end

	local chunk, err = loadstring(src, "@" .. path)

	if not chunk then
		load_failures[path] = "syntax: " .. tostring(err)

		return engine_cache[path]
	end

	local ok, result = pcall(chunk)

	if not ok then
		load_failures[path] = "runtime: " .. tostring(result)

		return engine_cache[path]
	end

	if type(result) == "table" then
		engine_cache[path] = result
	end

	return engine_cache[path]
end

harness.load_failures = function ()
	return load_failures
end

-- True when the module loaded and produced something. Tests that depend on
-- real engine data should assert this first, so a silently-empty table shows up
-- as the failure it is rather than as a vacuous pass.
harness.engine_loaded = function (path)
	local t = _G.require(path)

	return load_failures[path] == nil and next(t) ~= nil
end

-- ---------------------------------------------------------------------------
-- The fake mod
-- ---------------------------------------------------------------------------

local mod = {}

harness.mod = mod
harness.log = {}

local function _record(level, message, ...)
	local text = tostring(message)

	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, text, ...)
		text = ok and formatted or text
	end

	harness.log[#harness.log + 1] = { level = level, text = text }
end

function mod:info(message, ...)
	_record("info", message, ...)
end

function mod:debug_log(message, ...)
	_record("debug", message, ...)
end

function mod:warning(message, ...)
	_record("warning", message, ...)
end

function mod:error(message, ...)
	_record("error", message, ...)
end

function mod:echo(message, ...)
	_record("echo", message, ...)
end

-- DMF namespaces settings per mod and returns nil for anything never written,
-- which several modules depend on to tell "no opinion" from "switched off".
local settings_store = {}

harness.settings = settings_store

-- DMF's global localization database, which is what makes a mod-registered card
-- key resolve through Managers.localization rather than only through
-- mod:localize. One flat table shared by every mod in the real thing, and it
-- refuses to overwrite a key it already holds -- both of which the registry
-- depends on, so the stub reproduces them rather than just recording the call.
harness.global_localization = {}

function mod:add_global_localize_strings(text_translations)
	for text_id, translations in pairs(text_translations) do
		if harness.global_localization[text_id] == nil then
			harness.global_localization[text_id] = translations
		end
	end
end

function mod:get(id)
	return settings_store[id]
end

function mod:set(id, value, _notify)
	settings_store[id] = value
end

function mod:localize(key, ...)
	if select("#", ...) > 0 then
		return tostring(key) .. "(" .. table.concat({ ... }, ",") .. ")"
	end

	return tostring(key)
end

-- Faithfully re-executes, because the real one does: DMF caches nothing, and
-- more than one bug in this mod has come from assuming otherwise.
-- Installed mod paths stay flat; the original blessing pack lives inside the
-- core repository in the source checkout.
function harness.source_path(path)
	if path:match("^CwahBuffs/") then
		return ROOT .. "ChaosWastesAtHome/" .. path
	end
	return ROOT .. path
end

function mod:io_dofile(path)
	local src = _read(harness.source_path(path .. ".lua"))

	if not src then
		error("io_dofile: no such file: " .. tostring(path), 2)
	end

	local chunk, err = loadstring(src, "@" .. path)

	if not chunk then
		error("io_dofile: " .. tostring(err), 2)
	end

	return chunk()
end

function mod:is_enabled()
	return true
end

function mod:get_name()
	return "ChaosWastesAtHome"
end

-- Hooks are a no-op here. Nothing in the offline tier tests a hook; the modules
-- that register them at file scope are excluded from this tier entirely.
function mod:hook() end
function mod:hook_safe() end
function mod:hook_origin() end
function mod:hook_require() end
function mod:command() end
function mod:add_require_path() end
function mod:register_view() end

mod.is_host = function ()
	return true
end

mod.has_authority = function ()
	return true
end

mod.manager = nil
mod.role = "host"
mod._default_off_buffs = nil
mod.custom_buff_id_map = {}

_G.get_mod = function (name)
	if name == "ChaosWastesAtHome" then
		return mod
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- Managers
-- ---------------------------------------------------------------------------

_G.Managers = {
	player = {
		human_players = function ()
			return {}
		end,
		local_player_safe = function ()
			return nil
		end,
	},
	localization = {
		localize = function (_self, key)
			return tostring(key)
		end,
	},
	event = {
		trigger = function () end,
	},
	state = {},
}

_G.Color = setmetatable({}, {
	__index = function ()
		return function ()
			return { 255, 255, 255, 255 }
		end
	end,
})

_G.Application = {
	user_setting = function ()
		return nil
	end,
}

-- ---------------------------------------------------------------------------
-- Reset between test files
-- ---------------------------------------------------------------------------

-- Each test file starts from a clean profile and a clean run. Without this a
-- test that disables a buff leaks that choice into whatever runs next, and the
-- suite's result depends on file order.
harness.reset = function ()
	for k in pairs(settings_store) do
		settings_store[k] = nil
	end

	for i = #harness.log, 1, -1 do
		harness.log[i] = nil
	end

	-- Both of these deliberately live on the mod table in the real thing, so
	-- io_dofile re-executing a file does not forget a run or a verified peer.
	-- That is exactly why they have to be cleared here.
	mod._run = nil
	mod._net_state = nil
	mod.manager = nil
	mod.role = "host"
	mod._default_off_buffs = nil
	mod.custom_buff_id_map = {}

	-- The buff registry is state-on-mod for the same reason, and it accumulates
	-- across registrations rather than being rebuilt -- so without this, one
	-- test's categories and default-off buffs are visible to the next.
	mod._buff_registry_state = nil
	mod._custom_buff_procs = nil
	mod._user_buffs = nil
	mod.user_buffs = nil
	mod.recipe_sync = nil
	mod._recipe_sync = nil

	for k in pairs(harness.global_localization) do
		harness.global_localization[k] = nil
	end

	mod.is_host = function ()
		return true
	end

	mod.has_authority = function ()
		return true
	end

	_G.Managers.player.human_players = function ()
		return {}
	end

	_G.Managers.player.local_player_safe = function ()
		return nil
	end

	-- Anything that samples is reproducible run to run.
	math.randomseed(20260904)
end

-- Loads one of this mod's modules fresh.
harness.load = function (name)
	return mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/" .. name)
end

harness.logged = function (needle)
	for _, entry in ipairs(harness.log) do
		if entry.text:find(needle, 1, true) then
			return entry
		end
	end

	return nil
end

return harness
