local mod = get_mod("ChaosWastesAtHome")

mod.version = "0.9.8"

-- Required rather than reached through CLASS: these are loaded lazily by the
-- game (the game mode when a mission starts, the constant element by the UI
-- manager), so CLASS may not have them yet when mods load. Requiring pulls
-- them in and hands back the class table to hook directly.
local MatchmakingConstants = require("scripts/settings/network/matchmaking_constants")
local HordeMissionBuffsManager = require("scripts/managers/mission_buffs/horde_mission_buffs_manager")
-- Safe at file scope: horde_mission_buffs_manager above requires both of these,
-- so by the time we ask they are already in package.loaded.
local MissionBuffsHandler = require("scripts/managers/mission_buffs/mission_buffs_handler")
local MissionBuffsAllowedBuffs = require("scripts/managers/mission_buffs/mission_buffs_allowed_buffs")
local MissionBuffsSelector = require("scripts/managers/mission_buffs/mission_buffs_selector")
local GameModeCoopCompleteObjective = require("scripts/managers/game_mode/game_modes/game_mode_coop_complete_objective")
local ConstantElementMissionBuffs = require("scripts/ui/constant_elements/elements/mission_buffs/constant_element_mission_buffs")
local HOST_TYPES = MatchmakingConstants.HOST_TYPES

local MechanismAdventure = require("scripts/managers/mechanism/mechanisms/mechanism_adventure")
local StateGameScore = require("scripts/game_states/game/state_game_score")
local ProgressionManager = require("scripts/managers/progression/progression_manager")
local MultiplayerSessionManager = require("scripts/managers/multiplayer/multiplayer_session_manager")

local shim = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/game_mode_shim")
local triggers = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/triggers")
local pause = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/pause")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")
local chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/chain")
local difficulty = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/difficulty")
local particle_guard = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/particle_guard")
local spawn_guard = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/spawn_guard")
local asset_loader = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/asset_loader")
local custom_buffs = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/custom_buffs")
local buff_pool = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/buff_pool")
local escape = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/escape")
local solo = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/solo")
local loadouts = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/loadouts")
local net = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/net")

local SETTINGS_VIEW = "chaos_wastes_settings_view"
local RUN_SELECT_VIEW = "chaos_wastes_run_select_view"
local BUFF_TOGGLE_VIEW = "chaos_wastes_buff_toggle_view"
local LAUNCH_VIEW = "chaos_wastes_launch_view"
local BUFFS_VIEW = "chaos_wastes_buffs_view"

-- Set for the lifetime of a mission we have taken over; everything else in the
-- mod treats a non-nil `mod.manager` as "the Mortis buff system is live".
mod.manager = nil
mod.game_mode = nil

-- Which side of the session we are playing.
--
-- "host" covers both a solo mission (host with no peers) and the host of a
-- Realms session. "client" is a remote peer in a Realms session, where the
-- buff manager exists to *receive* rather than to decide.
--
-- This exists because `mod.manager` used to carry two meanings at once -- "the
-- buff system is live" and "I am the one who decides" -- and those come apart
-- the moment a client runs the mod at all. Forty call sites read the old flag;
-- each one is now explicitly one or the other.
mod.role = nil

local ROLES = {
	host = "host",
	client = "client",
}

-- Three tests, and picking the wrong one is how a client ends up granting
-- itself buffs the host never issued:
--
--   mod.manager ~= nil   the buff system is live, either role. Presentation,
--                        HUD, menus, local effects -- anything that only needs
--                        to know the mod is running here. Unchanged meaning,
--                        which is why most of the existing guards stay as they
--                        are.
--   mod.is_host()        we are the host, including plain solo. Lifecycle work
--                        that has to survive teardown.
--   mod.has_authority()  we are the host AND the game session is live. In-
--                        mission acts.

-- Host, without requiring a live game session.
--
-- Separate from has_authority because the run snapshot is captured during
-- _destroy_buff_system, when the session is already going away. Gating that on
-- a live session would silently lose the carryover at exactly the moment it is
-- needed -- the failure would look like "buffs stopped carrying between
-- missions" and point nowhere near here.
function mod.is_host()
	return mod.manager ~= nil and mod.role == ROLES.host
end

-- We are the one who decides. Granting buffs, spawning, counting kills toward
-- a trigger -- anything a client must never do.
--
-- Stricter than is_host() on purpose. The game-session manager is absent
-- during setup and teardown, and a hook firing in those windows would
-- otherwise act with an authority it does not have. Realms' own integration
-- docs prescribe the same test for authoritative logic.
function mod.has_authority()
	if not mod.is_host() then
		return false
	end

	local game_session = Managers.state and Managers.state.game_session

	if not game_session then
		return false
	end

	local ok, is_server = pcall(game_session.is_server, game_session)

	return ok and is_server or false
end

-- True only while our HordeMissionBuffsManager is being constructed, so the
-- backend hook below can tell our instance apart from a real Mortis one before
-- mod.manager has been assigned.
local constructing = false

-- Declared up here, not next to _update_run: the _destroy_buff_system hook
-- below assigns it, and a local declared after that hook would leave the
-- assignment writing to a global instead.
local restored_this_mission = false
local capture_accum = 0
local params_this_mission = false

-- Error text can contain a literal '%', which crashes the logging path when it
-- gets re-formatted downstream.
local function _escape(value)
	return (tostring(value):gsub("%%", "%%%%"))
end

-- Console/log-file only, never chat, and silent unless Debug Logging is on.
--
-- Accepts both call styles on purpose: a format string with arguments, or a
-- loose list of values joined with spaces. Verbose logging is only useful if
-- adding a line is frictionless, and a mismatched specifier should never be
-- the thing that breaks a debugging session -- so a failed format quietly
-- falls back to joining, and the result is always %-escaped because DMF
-- re-formats whatever it is handed.
function mod:debug_log(...)
	if not mod:get("debug_logging") then
		return
	end

	local count = select("#", ...)
	local first = select(1, ...)
	local message

	if count > 1 and type(first) == "string" and first:find("%%") then
		local ok, formatted = pcall(string.format, ...)

		message = ok and formatted or nil
	end

	if not message then
		local parts = {}

		for i = 1, count do
			parts[#parts + 1] = tostring((select(i, ...)))
		end

		message = table.concat(parts, " ")
	end

	mod:info(_escape(message))
end

-- TrueSoloQoL's auto-restart hooks evaluate_end_conditions and, on a failure,
-- calls restart_level() and returns false instead of letting the mission end.
-- That silently breaks this mod's central rule that losing ends the run: you
-- would simply respawn into the same mission and the chain would never break.
--
-- Not something to fix from here -- it is the other mod doing exactly what it
-- says -- but the interaction is invisible unless someone points at it, so say
-- it once per session rather than letting a run quietly become unloseable.
local warned_about_conflicts = false

local function _warn_about_conflicts()
	if warned_about_conflicts then
		return
	end

	warned_about_conflicts = true

	local true_solo = get_mod and get_mod("TrueSoloQoL")

	if not true_solo then
		return
	end

	local ok, auto_restart = pcall(true_solo.get, true_solo, "auto_restart")

	if ok and auto_restart then
		mod:echo(mod:localize("conflict_auto_restart"))
		mod:info("TrueSoloQoL auto_restart is enabled - losing will restart the mission instead of ending the run")
	end
end

-- ---------------------------------------------------------------------------
-- Loadouts
-- ---------------------------------------------------------------------------

-- Auto-save is debounced rather than written on the spot.
--
-- on_setting_changed fires once per setting, and the options menu fires a burst
-- of them -- dragging a numeric slider is one call per step. Writing the file
-- per call would mean hundreds of writes for one drag. A dirty flag plus a short
-- delay in mod.update collapses that into one, the same shape as the pending
-- pool init below.
local LOADOUT_SAVE_DELAY = 1
local loadout_dirty = false
local loadout_save_accum = 0

-- Suppressed while a loadout is being applied: apply() writes every setting, and
-- each write would otherwise mark the file dirty and save it straight back.
local applying_loadout = false

local function _save_active_loadout()
	local slug = mod:get(loadouts.ACTIVE_SETTING)

	if not slug or slug == "" then
		return
	end

	local existing = loadouts.read(slug)

	-- Name and icon are read back and re-written rather than tracked in memory:
	-- auto-save rewrites the whole file, so anything not carried forward here is
	-- silently dropped the first time a setting changes.
	loadouts.write(slug, {
		name = existing and existing.name or slug,
		icon = existing and existing.icon or nil,
		settings = loadouts.snapshot(),
	})
end

local function _mark_loadout_dirty()
	if applying_loadout then
		return
	end

	if not mod:get(loadouts.ACTIVE_SETTING) then
		return
	end

	loadout_dirty = true
	loadout_save_accum = 0
end

local function _update_loadout_save(dt)
	if not loadout_dirty then
		return
	end

	loadout_save_accum = loadout_save_accum + dt

	if loadout_save_accum < LOADOUT_SAVE_DELAY then
		return
	end

	loadout_dirty = false
	loadout_save_accum = 0

	_save_active_loadout()
end

-- Everything the loadout view needs, so the view never touches DMF settings or
-- the filesystem directly.
mod.loadouts = {
	list = function ()
		return loadouts.list()
	end,

	active = function ()
		return mod:get(loadouts.ACTIVE_SETTING)
	end,

	default = function ()
		return mod:get(loadouts.DEFAULT_SETTING)
	end,

	select = function (slug)
		local data = loadouts.read(slug)

		if not data then
			return false
		end

		-- The outgoing loadout is flushed first, or edits made since its last
		-- save are lost by switching away from it.
		if loadout_dirty then
			loadout_dirty = false
			loadout_save_accum = 0

			_save_active_loadout()
		end

		applying_loadout = true

		local ok = pcall(loadouts.apply, data.settings)

		applying_loadout = false

		if not ok then
			return false
		end

		mod:set(loadouts.ACTIVE_SETTING, slug, false)
		buff_pool.invalidate()

		return true
	end,

	create = function ()
		local existing = loadouts.list()
		local name = string.format("Loadout %d", #existing + 1)
		local slug = loadouts.slugify(name)

		-- Numbering off the count collides as soon as anything has been
		-- deleted, and a collision would silently overwrite a loadout rather
		-- than making a new one.
		local suffix = 1

		while loadouts.read(slug) do
			suffix = suffix + 1
			name = string.format("Loadout %d", #existing + suffix)
			slug = loadouts.slugify(name)
		end

		-- First icon nobody is using, so a new loadout is distinguishable at a
		-- glance without the player having to pick one. They can change it.
		local taken = {}

		for i = 1, #existing do
			if existing[i].icon then
				taken[existing[i].icon] = true
			end
		end

		local icon = loadouts.ICONS[1]

		for i = 1, #loadouts.ICONS do
			if not taken[loadouts.ICONS[i]] then
				icon = loadouts.ICONS[i]

				break
			end
		end

		if not loadouts.write(slug, { name = name, icon = icon, settings = loadouts.snapshot() }) then
			return nil
		end

		loadouts.index_add(slug)
		mod:set(loadouts.ACTIVE_SETTING, slug, false)

		return slug
	end,

	set_default = function (slug)
		mod:set(loadouts.DEFAULT_SETTING, slug, false)
	end,

	delete = function (slug)
		if not loadouts.delete(slug) then
			return false
		end

		loadouts.index_remove(slug)

		-- Clearing the pointers matters more than the file: an active slug with
		-- no file behind it means every later auto-save recreates the loadout
		-- the player just deleted.
		if mod:get(loadouts.ACTIVE_SETTING) == slug then
			mod:set(loadouts.ACTIVE_SETTING, nil, false)
		end

		if mod:get(loadouts.DEFAULT_SETTING) == slug then
			mod:set(loadouts.DEFAULT_SETTING, nil, false)
		end

		return true
	end,

	available = function ()
		return loadouts.available()
	end,

	-- Explicit, because it is the only path left that spawns a process.
	rescan = function ()
		return loadouts.rescan()
	end,

	icons = function ()
		return loadouts.ICONS
	end,

	set_icon = function (slug, icon)
		local data = loadouts.read(slug)

		if not data then
			return false
		end

		return loadouts.write(slug, { name = data.name, icon = icon, settings = data.settings })
	end,
}

-- First run: adopt whatever the player already has rather than starting empty.
--
-- Runs at load, before anything can have changed the settings, so the snapshot
-- is genuinely their existing configuration. Also applies the default, which is
-- the whole of what "default" means -- one apply, at startup.
-- Defaults for the options that moved to the Settings tab.
--
-- DMF stamps a default only for settings that still have a widget in the data
-- file (initialize_default_settings_and_keybinds walks the option tree). Moving
-- an option out of that file therefore removes its default too, and a fresh
-- install would read nil for every one of them -- which for a checkbox reads as
-- "off" and for a numeric crashes whatever divides by it.
--
-- Applied with notify false: this runs before any loadout exists, and notifying
-- would mark a loadout dirty for values nobody chose.
local MOVED_DEFAULTS = {
	difficulty_ramp = true,
	use_bots = false,
	ignore_buff_family = false,
	pause_on_choice = true,
	sync_pause_multiplayer = false,
	objective_enabled = true,
	objective_side_missions = true,
	kills_enabled = false,
	time_enabled = false,
	events_enabled = false,
	custom_buff_weight = 1,
	havoc_theme_chance = 50,
	max_legendary_choices = 3,
	-- Empty, meaning every family may be offered. Present rather than nil so it
	-- reaches the loadout files: snapshot() enumerates the settings that exist,
	-- and a setting nobody has touched yet does not exist to enumerate.
	disabled_families = {},
	starting_legendary_picks = 0,
	starting_family_buffs = 0,
	max_family_buffs = 7,
	kills_threshold = 25,
	time_interval = 5,
	kills_mode = "elites_specials",
}

local function _apply_moved_defaults()
	for id, value in pairs(MOVED_DEFAULTS) do
		-- nil, not falsiness: a checkbox saved as false is a real choice.
		if mod:get(id) == nil then
			mod:set(id, value, false)
		end
	end
end

-- Loadouts written before family exclusions existed have no disabled_families
-- in them, and applying one therefore leaves whatever was last set in place --
-- so an old loadout silently inherits another's exclusions until the player
-- edits it. Stamped as empty, meaning every family offered, which is what those
-- loadouts meant when they were saved.
--
-- No flag guarding it: it only rewrites a file that is actually missing the key,
-- so the second run finds nothing to do. A flag would be one more thing to get
-- wrong for no benefit.
local function _migrate_loadout_families()
	local rows = loadouts.list()
	local migrated = 0

	for i = 1, #rows do
		local row = rows[i]

		if type(row.settings) == "table" and row.settings.disabled_families == nil then
			row.settings.disabled_families = {}

			if loadouts.write(row.slug, { name = row.name, icon = row.icon, settings = row.settings }) then
				migrated = migrated + 1
			end
		end
	end

	if migrated > 0 then
		mod:info("added the family-pick setting to %d loadout(s) saved before it existed", migrated)
	end
end

local function _init_loadouts()
	if not loadouts.available() then
		mod:info("file access unavailable - loadouts are disabled this session")

		return
	end

	if #loadouts.list() == 0 then
		local name = "Default"
		local slug = loadouts.slugify(name)

		if loadouts.write(slug, { name = name, settings = loadouts.snapshot() }) then
			loadouts.index_add(slug)
			mod:set(loadouts.ACTIVE_SETTING, slug, false)
			mod:set(loadouts.DEFAULT_SETTING, slug, false)
			mod:info("created the first loadout from your current settings")
		end

		return
	end

	-- Before the default is applied, so the loadout being applied already has
	-- the key and does not inherit the live value.
	_migrate_loadout_families()

	local default_slug = mod:get(loadouts.DEFAULT_SETTING)
	local data = default_slug and loadouts.read(default_slug)

	if not data then
		return
	end

	applying_loadout = true

	pcall(loadouts.apply, data.settings)

	applying_loadout = false

	mod:set(loadouts.ACTIVE_SETTING, default_slug, false)
	mod:info("applied the default loadout '%s'", _escape(data.name))
end

particle_guard.install()
spawn_guard.install()
escape.install()
custom_buffs.register()

-- Parked here rather than reached for: net.lua must not io_dofile custom_buffs,
-- which re-executes and would be a second registration.
mod.custom_buff_id_map = custom_buffs.network_id_map

-- Same reason: pause.lua asks this rather than loading net.lua itself.
-- Any connection at all, ready or not. The pause has to respect a client that
-- is still loading just as much as one that is playing -- more, in fact, since
-- that is the one a stray pause kills.
mod.has_peers = function ()
	return net.connected_count() > 0
end

-- ...and whether they can actually receive a synchronised timescale yet.
mod.peers_syncable = function ()
	return net.all_peers_ready()
end

-- Both halves of "is anyone still on a buff card": we tell the others about
-- ours, and ask about theirs. Parked for pause.lua for the same reason as
-- above -- it must not load net.lua and get a second copy.
mod.report_choosing = function (choosing)
	net.set_local_choosing(choosing)
end

mod.peers_choosing = function (dt)
	return net.any_peer_choosing(dt)
end

-- Same again for chain.lua, which is io_dofile'd and must not carry its own
-- copy of net.lua either.
--
-- Two callers, and they cover different launches. This one is the mid-mission
-- one -- the launcher's "End run & begin" -- where the bus is still up at the
-- moment of the reset. The chain's own hop cannot use it: chain.launch runs
-- from the hub by then, long after the game session and the bus are gone, so
-- that announcement goes out from the complete_game_mode hook instead.
mod.announce_hop = function (mission_name)
	return net.announce_hop(mission_name)
end
_apply_moved_defaults()
_init_loadouts()

-- Which role, if any, this mod plays in the session we are in.
--
-- Three shapes qualify:
--   singleplay    -- the solo case: host with no peers. The original.
--   Realms host   -- HOST_TYPES.player and we own the connection host.
--   Realms client -- HOST_TYPES.player and we are the remote peer.
--
-- nil for everything else, and that still includes a real Fatshark mission
-- server. Widening this to cover Realms is not permission to run in matchmade
-- play: there the server is somebody else's and the buff system would be
-- talking to three strangers running the stock manager.
--
-- HOST_TYPES.player plus Managers.connection:is_host()/:is_client() is the
-- detection Realms' own integration docs prescribe for other mods, so this
-- reads the supported surface rather than a private field.
local function _session_role()
	local session_manager = Managers.multiplayer_session

	if not session_manager then
		return nil
	end

	local ok, host_type = pcall(session_manager.host_type, session_manager)

	if not ok then
		return nil
	end

	if host_type == HOST_TYPES.singleplay then
		return ROLES.host
	end

	if host_type ~= HOST_TYPES.player then
		return nil
	end

	local connection = Managers.connection

	if not connection then
		return nil
	end

	local host_ok, is_host = pcall(connection.is_host, connection)

	if host_ok and is_host then
		return ROLES.host
	end

	local client_ok, is_client = pcall(connection.is_client, connection)

	if client_ok and is_client then
		return ROLES.client
	end

	return nil
end

-- Returns a role string, or nil for "stay out of this mission".
--
-- A role rather than a boolean so no caller can forget which side it is on --
-- getting that wrong is a client granting itself buffs the host never issued.
--
-- Why a client activates at all: the host runs HordeMissionBuffsManager and a
-- vanilla client runs the stock MissionBuffsManager, which registers neither
-- rpc_client_mission_buffs_buff_choices_received nor any of this mod's custom
-- buff ids. The first card offered would be an unhandled network event and the
-- first custom buff granted would be a read of a NetworkLookup key the client
-- does not have -- a crash on their machine, caused by ours. Both sides
-- running the same manager is what makes that safe, and the engine already
-- supports it: HordeMissionBuffsManager.init handles is_server = false by
-- registering the client RPCs and skipping the handler and selector.
local function _should_activate(game_mode, game_mode_name)
	if game_mode_name == "hub" or game_mode_name == "prologue_hub" then
		return nil
	end

	local role = _session_role()

	if not role then
		return nil
	end

	-- Host-only preconditions, because a client can answer neither: it never
	-- opened our launcher, and it is not the server by definition.
	if role == ROLES.host then
		-- Opt-in. Without this the mod takes over every mission that happens to
		-- be singleplay, which for anyone running SoloPlay is all of their solo
		-- play -- the "boons in normal matches" reports. A run has to be started
		-- from our own launcher, and the flag rides along through every hop of
		-- the chain.
		if not run.is_launched() then
			return nil
		end

		if not game_mode._is_server then
			return nil
		end
	end

	return role
end

-- Every non-hub game mode already builds a MissionBuffsManager here, which is
-- why the buffs, the network lookups and the card UI all exist in a regular
-- mission. Swapping in the survival subclass is what turns that dormant
-- plumbing into the full Mortis experience: families, legendary pools,
-- per-archetype filtering, the choice UI and its timeout, and persistence
-- across downs and respawns.
mod:hook(GameModeCoopCompleteObjective, "_init_buff_system", function (func, self, game_mode_name, network_event_delegate)
	-- Reaching the hub means the chain was not continued -- you lost, quit, or
	-- ignored the picker. Either way the run is over, which is also how
	-- "leaving the mission" aborts it: the launch path goes mission ->
	-- mission and never passes through the hub.
	if game_mode_name == "hub" or game_mode_name == "prologue_hub" then
		-- A pending launch means the chain is mid-hop, not over: the run
		-- passes through the Morningstar on its way to the next mission and
		-- must survive the trip. Without a pending mission, arriving here
		-- means the run is done -- lost, quit, or the picker was ignored.
		if not run.state().pending_launch then
			run.reset("returned to the Morningstar")
		end
	end

	local role = _should_activate(self, game_mode_name)

	if not role then
		return func(self, game_mode_name, network_event_delegate)
	end

	shim.install(self)

	local missing = shim.missing_members(self)

	if #missing > 0 then
		mod:error("game mode is missing %s - using the stock buff system instead", _escape(table.concat(missing, ", ")))

		return func(self, game_mode_name, network_event_delegate)
	end

	constructing = true

	local ok, manager = pcall(function ()
		return HordeMissionBuffsManager:new(self._is_server, self, game_mode_name, network_event_delegate)
	end)

	constructing = false

	if not ok then
		mod:error("could not start the Mortis buff system: %s", _escape(manager))

		return func(self, game_mode_name, network_event_delegate)
	end

	self._mission_buffs_manager = manager
	mod.manager = manager
	mod.game_mode = self
	mod.role = role

	-- Both roles.
	--
	-- The network lookup especially: the ids this mod appends have to agree on
	-- every peer, and a client that skipped it would crash on the first custom
	-- buff the host granted -- which is the whole reason a client activates.
	custom_buffs.register_network_lookup()
	asset_loader.request()

	if role == ROLES.host then
		-- depth is missions_completed, incremented when a mission ends, so the
		-- first mission of a run is the one that reads 0.
		triggers.reset(run.depth() == 0)
		custom_buffs.apply_weight()
		custom_buffs.reset_counters()

		-- Host-only because the status cascade *applies* buffs to enemies,
		-- which is a server act. On a client it would be writing to units it
		-- does not own -- and its own owner check would make it a silent no-op
		-- anyway, which is worse than not installing it.
		--
		-- Retried here because the load-time attempt declines at boot: the
		-- engine module it hooks cannot be required until the game is further
		-- along.
		custom_buffs.install_hooks()
	end

	_warn_about_conflicts()

	mod:info("Mortis buff system active in game mode '%s' as %s",
		_escape(game_mode_name), role)
end)

-- Mortis asks the title backend for buff-family weights and a deactivated-buff
-- list. A solo mission has no session to ask, and a synchronous failure in
-- there would take the whole manager down before it is built, so we install
-- the same defaults the stock catch handler uses and never make the request.
--
-- Deliberately NOT calling _manage_delayed_data_initialization_for_players()
-- the way the real callbacks do: this runs from inside init, before
-- _players_needing_data_initialization exists. Setting the fields is enough --
-- _manage_player_spawn checks them directly and proceeds.
-- ---------------------------------------------------------------------------
-- Legendary pool timing
-- ---------------------------------------------------------------------------

-- Restores the ordering our backend bypass accidentally removed.
--
-- The legendary pool is filtered by the player's EQUIPPED abilities:
-- _get_valid_legendary_buffs_for_player_setup reads
-- ability_extension:equipped_abilities() and indexes
-- legendary_buffs[class].grenade_ability[<equipped blitz>]. Build it too early
-- and that lookup answers with whatever the extension holds at that instant,
-- which is how an Adamant with no shock mine ends up being offered
-- hordes_buff_adamant_mine_explosion.
--
-- Stock Mortis never builds it at spawn. _manage_player_spawn checks whether
-- the backend exclusion list has arrived, and on the first spawn it has not --
-- so the player is parked in _players_needing_data_initialization and the pool
-- is built later, from _manage_delayed_data_initialization_for_players, once
-- the round trip finishes. We answer that request synchronously, so the list is
-- already present on the very first spawn and the deferral never happens.
--
-- So we re-add a deferral of our own: hold the first call per player until the
-- ability extension can actually answer, then let it through unchanged.
local pending_pool_init = mod._pending_pool_init or {}

mod._pending_pool_init = pending_pool_init

-- A backstop, not a schedule. If abilities never resolve we would rather hand
-- out a slightly wrong pool than no buffs at all for the whole mission.
local POOL_INIT_TIMEOUT = 5

local function _resolved_abilities(player)
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		return nil
	end

	local extension = ScriptUnit.has_extension(unit, "ability_system")

	if not extension then
		return nil
	end

	local ok, abilities = pcall(extension.equipped_abilities, extension)

	if not ok or type(abilities) ~= "table" then
		return nil
	end

	-- Read exactly the way the selector reads them, so what is logged is what
	-- the pool will be built from -- note grenade uses `name` and combat uses
	-- `ability_group`.
	local grenade = abilities.grenade_ability and abilities.grenade_ability.name
	local combat = abilities.combat_ability and abilities.combat_ability.ability_group

	if not grenade and not combat then
		return nil
	end

	return { grenade = grenade, combat = combat }
end

-- "Ignore buff families": earn from every family's pool, not just the one picked.
--
-- A family normally locks the run to its own ~10 small buffs, putting the other
-- six families' ~60 permanently out of reach. This is the one place that
-- decides: set_buff_family_for_player is handed the chosen family's priority and
-- regular lists, and persistent_data copies them into the player's available
-- pools (mission_buffs_persistent_data.lua). Substituting the regular list here
-- is the whole feature.
--
-- Family buffs are NOT archetype-filtered -- nothing in that path looks at the
-- player's class, so merging them is safe. Class restriction only applies to
-- LEGENDARY buffs, which are keyed to the blitz and combat ability you actually
-- have equipped; those are untouched, and a Veteran will not start being offered
-- Psyker ability buffs that would do nothing.
--
-- The priority list is left alone, so the family you pick still decides the buff
-- you get immediately. The other families' priority buffs are folded into the
-- regular pool instead of being granted -- otherwise they would be the only
-- seven buffs in the game still unreachable with the option on.
--
-- Nothing here needs to re-apply the Rollable Buffs toggles: the handler passes
-- buffs_to_exclude down and persistent_data filters against it, so a merged pool
-- is filtered exactly like an unmerged one.
-- Families switched off in Rollable Buffs never reach the opening choice.
--
-- The engine fills the three options straight out of
-- MissionBuffsAllowedBuffs.available_family_builds, so the least invasive place
-- to filter is that list: swapped for a filtered copy for the duration of the
-- call and put back afterwards, including when the original throws. Editing it
-- permanently would leak into every other reader of that table, this mod's and
-- other mods' alike.
mod:hook(MissionBuffsSelector, "create_buff_family_choice_for_player", function (func, self, player, num_choices)
	-- The choke point. Every family card in the game is created here, so a
	-- player whose family we are carrying is given it back instead of being
	-- asked to choose again -- whatever asked.
	--
	-- Handling this at the spawn hook alone was not enough:
	-- create_buff_family_choice_for_all walks human_players() and offers to
	-- anyone without a family, which catches a client who has connected but not
	-- yet spawned. Suppressing here covers that producer and any other.
	--
	-- Returning without calling func is the point -- the card must not be built
	-- at all. A player we hold nothing for falls straight through.
	if run.restore_family(self, player) then
		return
	end

	local offered = buff_pool.offered_families()

	-- Nothing switched off, or everything switched off: leave the engine alone.
	-- An empty pool would mean a choice with no options, which is the mod
	-- silently doing nothing for the rest of the run. The toggle is a
	-- preference, not a way to break a mission.
	if #offered == 0 or #offered == buff_pool.family_count() then
		if #offered == 0 then
			mod:debug_log("every family is switched off - offering all of them instead")
		end

		return func(self, player, num_choices)
	end

	-- A short pool repeats itself, which is fine and deliberately left alone --
	-- with two families left there is nothing else to offer. The COUNT is
	-- capped separately, in save_buff_family_choice_for_player below.
	local original = MissionBuffsAllowedBuffs.available_family_builds

	MissionBuffsAllowedBuffs.available_family_builds = offered

	local ok, err = pcall(func, self, player, num_choices)

	MissionBuffsAllowedBuffs.available_family_builds = original

	if not ok then
		mod:error("family choice failed: %s", _escape(tostring(err)))
	end
end)

-- Three options, however short the pool is.
--
-- The top-up APPENDS rather than filling to a total: the weighted pass takes
-- what it can from the pool, and if that came up short -- only possible once we
-- have filtered below three -- the second pass adds up to three MORE from a
-- fresh copy of the same pool. Two enabled families therefore produced a card
-- with four buttons, and one produced two. Truncating the finished list is the
-- robust place to fix that: it depends only on the shape of the array, not on
-- the engine's internal use of num_choices.
--
-- Repeats within those three are left alone, so two families give
-- "Fire / Cowboy / Fire" rather than a card with a button missing.
local MAX_FAMILY_OPTIONS = 3

mod:hook(MissionBuffsHandler, "save_buff_family_choice_for_player", function (func, self, player, family_name_choices)
	if type(family_name_choices) ~= "table" or #family_name_choices <= MAX_FAMILY_OPTIONS then
		return func(self, player, family_name_choices)
	end

	local trimmed = {}

	for i = 1, MAX_FAMILY_OPTIONS do
		trimmed[i] = family_name_choices[i]
	end

	mod:debug_log("family choice came back with %d options - trimmed to %d",
		#family_name_choices, MAX_FAMILY_OPTIONS)

	return func(self, player, trimmed)
end)

mod:hook(MissionBuffsHandler, "set_buff_family_for_player", function (func, self, player, family_name, priority_family_buffs, family_buffs, from_choice)
	if not mod.has_authority() or not mod:get("ignore_buff_family") then
		return func(self, player, family_name, priority_family_buffs, family_buffs, from_choice)
	end

	local families = MissionBuffsAllowedBuffs.buff_families

	if type(families) ~= "table" then
		mod:error("buff_families is missing - families cannot be merged")

		return func(self, player, family_name, priority_family_buffs, family_buffs, from_choice)
	end

	local merged, seen = {}, {}

	local function _take(list)
		if type(list) ~= "table" then
			return
		end

		for i = 1, #list do
			local name = list[i]

			if not seen[name] then
				seen[name] = true
				merged[#merged + 1] = name
			end
		end
	end

	-- The chosen family first, so its buffs keep the ordering they had.
	_take(family_buffs)

	for name, build in pairs(families) do
		if name ~= family_name then
			_take(build.buffs)
			_take(build.priority_buffs)
		end
	end

	mod:info("ignoring buff families: pool widened from %d to %d small buff(s)",
		type(family_buffs) == "table" and #family_buffs or 0, #merged)

	return func(self, player, family_name, priority_family_buffs, merged, from_choice)
end)

mod:hook(HordeMissionBuffsManager, "_manage_player_spawn", function (func, self, player, is_respawn)
	if mod.manager ~= self or not player then
		return func(self, player, is_respawn)
	end

	-- Ahead of every path below, including the ones that return immediately.
	--
	-- The original decides here whether to put a family card up, and for anyone
	-- rejoining a run in progress the answer is yes -- they have no family in
	-- this mission's data and the mission has already opened its choice. Setting
	-- the carried family first makes that check answer no. See run.restore_family
	-- for why this cannot wait for run.restore.
	--
	-- Safe for bots and for players we hold nothing for: run.restore_family keys
	-- through _player_key, which answers nil for anything not human-controlled.
	run.restore_family(self._mission_buffs_selector, player)

	local handler = self._mission_buffs_handler
	local ok, has_pool = pcall(handler.does_player_have_legendary_buffs_pool, handler, player)

	-- Only the call that would build the pool is held. Respawns and every later
	-- call go straight through, so nothing else about spawn handling changes.
	if not ok or has_pool then
		return func(self, player, is_respawn)
	end

	-- Bots reach this hook too -- bot_gameplay.lua:36 calls the same
	-- spawn_player -- and holding their pool init serves no purpose: this
	-- deferral exists so the LOCAL player's blitz and combat ability have
	-- resolved before the legendary pool is filtered against them, and nobody
	-- ever sees a bot's cards.
	--
	-- It also crashed. BotPlayer extends HumanPlayer, so account_id() exists and
	-- looks safe; it just returns nil, because bots are built without one
	-- (bot_player.lua:8 passes no account id to the constructor). Using that as
	-- a table key is "table index is nil" -- a hard crash, not a caught hook
	-- error, because it happens in our own hook body rather than inside a pcall.
	if not player.is_human_controlled or not player:is_human_controlled() then
		return func(self, player, is_respawn)
	end

	-- unique_id() rather than account_id(): every player class has one and it is
	-- the first constructor argument for humans, remotes and bots alike. The nil
	-- check stays regardless -- the cost of being wrong here is a crash, and the
	-- fallback (no deferral) is exactly the behaviour that shipped before it.
	local id = player.unique_id and player:unique_id()

	if not id then
		return func(self, player, is_respawn)
	end

	local entry = pending_pool_init[id]

	if not entry then
		entry = { player = player, is_respawn = is_respawn, elapsed = 0, manager = self }
		pending_pool_init[id] = entry
	end

	local abilities = _resolved_abilities(player)

	if not abilities and entry.elapsed < POOL_INIT_TIMEOUT then
		return
	end

	pending_pool_init[id] = nil

	mod:info("building legendary pool for %s - blitz '%s', ability '%s'%s",
		_escape(player:archetype_name()),
		_escape(abilities and abilities.grenade or "unresolved"),
		_escape(abilities and abilities.combat or "unresolved"),
		abilities and "" or " (timed out)")

	return func(self, player, entry.is_respawn)
end)

mod:hook(HordeMissionBuffsManager, "_fetch_backend_data_needed_before_player_data_initialization", function (func, self)
	if not constructing then
		return func(self)
	end

	-- Doubles as the run's "already owned" list.
	--
	-- Mortis never repeats a buff because it is one continuous mission: the
	-- pools live in per-player data and buffs are removed as they are handed
	-- out. Every mission in a chain builds a fresh manager with fresh pools,
	-- so without this the run would keep re-offering buffs you already have.
	--
	-- This one table covers both pools: init_legendary_buffs_pool_for_player
	-- filters the legendary pool through it, and set_buff_family_for_player
	-- filters the priority and regular family pools through it as well. Both
	-- read it back via manager:get_buffs_to_exclude(), and both run after this
	-- point -- pool init at spawn, the family pools during our restore.
	-- Only already-owned buffs are excluded. Buffs whose particle effects are
	-- missing stay in the pool: particle_guard makes those effects render
	-- nothing instead of crashing, so there is no reason to cost the player
	-- the buff itself.
	local exclude = {}
	local carried = 0

	if run.should_restore() then
		for buff_name in pairs(run.state().buffs) do
			exclude[buff_name] = true
			carried = carried + 1
		end
	end

	-- Buffs switched off in the toggle view join the same list. Applied after
	-- the carried ones and additively, so the two cannot clobber each other.
	local switched_off = buff_pool.apply_exclusions(exclude)

	-- And every custom buff, if any connected peer has not proved it computed
	-- the same network ids we did.
	--
	-- This is the enforcement half of the handshake in net.lua. Offering a
	-- custom buff to a peer whose NetworkLookup lacks that id is a hard crash
	-- on their machine, so the pool closes rather than gambling. It reopens by
	-- itself the moment they identify -- there is nothing to undo.
	local suppressed = 0

	if not net.custom_buffs_safe() then
		local map = custom_buffs.network_id_map() or {}

		for i = 1, #map do
			local name = string.match(map[i], "^([^=]+)=")

			if name and not exclude[name] then
				exclude[name] = true
				suppressed = suppressed + 1
			end
		end

		mod:error("a connected peer has not verified its custom buff ids - %d custom buff(s) suppressed this mission (/cw_peers)",
			suppressed)
	end

	self._backend_buffs_to_exclude = exclude
	self._backend_weighted_randomization = {
		buff_family_weights = {},
	}

	mod:debug_log("skipped the hordes backend request; using even family weights;",
		carried, "buff(s) already owned this run and", switched_off,
		"switched off in the toggle menu, and", suppressed, "suppressed for an unverified peer, excluded from the pools")
end)

mod:hook_safe(GameModeCoopCompleteObjective, "_destroy_buff_system", function (self)
	if mod.game_mode ~= self then
		return
	end

	-- Before clearing mod.manager: pause.update() bails out once the manager
	-- is gone, so a mission torn down while a card was open (mission failed,
	-- disconnect, quit to hub) would otherwise strand the gameplay timer at
	-- scale 0 with nothing left running to restore it.
	pause.resume()

	-- Also before clearing it: the buff data we carry into the next mission
	-- lives on the manager that is about to be destroyed. The end screen runs
	-- after this point, so this is the last chance to read it.
	run.capture()

	mod.manager = nil
	mod.game_mode = nil
	mod.role = nil
	restored_this_mission = false
	capture_accum = 0

	-- Only the flag: run.state().params must survive teardown for the end
	-- screen to roll the next mission's options from.
	params_this_mission = false

	triggers.reset()
end)

-- The card UI is registered for every in_mission session and its package is
-- loaded at UIManager init, so the only thing keeping it off screen here is
-- this game-mode check. Everything below it is driven by generic events.
-- Holds the choice card's timers while the world is paused or before the
-- card is on screen.
--
-- The card's timer is not gameplay time. StateGame feeds Managers.ui the raw
-- frame dt rather than the gameplay timer -- which is exactly what makes the
-- card still animate and accept clicks while the world is stopped -- so
-- scaling "gameplay" to zero does nothing to the 30 seconds ticking away
-- behind it. In solo there is nothing to race: the timer exists so a
-- four-player game is not held hostage by one person reading a card.
--
-- Two timers are held, and only one of them is the one you can see.
--
-- _texts_timer is the number printed on the card. _buffs_timer looks like a
-- presentation timer and is not: _update_buffs_state treats it running out as
-- the auto-pick deadline and calls _force_choice_resolution, which picks a
-- random card (constant_element_mission_buffs.lua:628). Holding only the
-- visible one gave a frozen number over a countdown that was still running --
-- the card would sit there apparently paused and then choose for you.
--
-- Safe to hold both because _update_timers_state runs immediately before
-- _update_buffs_state in the same _update_view_state pass (line 441), so the
-- restore lands before the state machine ever reads the value. _blur_timer is
-- left alone; that one really is presentation.
--
-- The unresolved test is made here rather than relying on pause.is_paused()
-- alone. That flag is recomputed once per frame from mod.update, so on the
-- frame the player actually picks it can still read true -- and restoring
-- _buffs_timer after _handle_choice_resolution had cleared it would leave the
-- card unable to close.
--
-- With "Pause while choosing" off the pause never engages, but the timers
-- are still held while the card is off screen; once it appears the stock
-- 30-second auto-pick behaves exactly as before.
mod:hook(ConstantElementMissionBuffs, "_update_timers_state", function (func, self, dt, ui_renderer)
	local context = self._context
	local unresolved = context and context.is_choice and not context.buff_chosen
	local hold = unresolved and (pause.is_paused() or not self:should_draw())
	local held_texts = hold and self._texts_timer
	local held_buffs = hold and self._buffs_timer

	func(self, dt, ui_renderer)

	if held_texts then
		self._texts_timer = held_texts
		-- Kept in step with the current value: the pair is compared to detect
		-- the countdown crossing a whole second, and leaving them apart would
		-- re-fire that every frame.
		self._previous_texts_timer = held_texts
	end

	if held_buffs then
		self._buffs_timer = held_buffs
	end
end)

mod:hook(ConstantElementMissionBuffs, "_is_player_in_mission", function (func, self)
	if mod.manager and self._current_game_mode == "coop_complete_objective" then
		return true
	end

	return func(self)
end)

-- ---------------------------------------------------------------------------
-- Solo sessions
-- ---------------------------------------------------------------------------

mod.on_all_mods_loaded = function ()
	solo.load_end_view_package()
end

-- Hooked by class NAME rather than by requiring the module, which is how
-- Tertium4Or5 hooks this same class. DMF resolves the name when the class
-- exists, so nothing is executed early during boot -- the failure mode that
-- poisoned minion_buff_extension for the whole session.
-- BOTH spawn paths, and both clear the queue rather than just declining to run.
--
-- _queued_bots_n is the count of bots the game still wants, filled by
-- _validate_bot_backfill from _num_available_bot_slots. _handle_initial_bot_spawning
-- drains it at mission start; _handle_bot_spawning drains it one per frame from
-- PlayerUnitSpawnManager.update (player_unit_spawn_manager.lua:85).
--
-- Skipping the initial call alone -- which is what this did at first -- suppressed
-- nothing. The counter was left untouched, so the per-frame path spawned exactly
-- the same bots a frame later, and the only visible effect was that they arrived
-- slightly late. Zeroing the queue is what actually stops them, and doing it in
-- the per-frame hook as well means a mid-mission re-validation (a client joining
-- or leaving re-runs _validate_bot_backfill) cannot quietly refill it.
--
-- Still at the spawn functions rather than at _num_available_bot_slots:
-- Tertium4Or5 hooks that one and returns func(...) + 3, so a 0 from us would come
-- back out as 3. Discarding the queue is order-independent.
local function _suppress_bot_spawning(func, self, ...)
	if solo.should_suppress_bots() then
		if (self._queued_bots_n or 0) > 0 then
			mod:debug_log("solo run - discarding %d queued bot(s)", self._queued_bots_n)
		end

		self._queued_bots_n = 0

		return
	end

	return func(self, ...)
end

mod:hook("PlayerUnitSpawnManager", "_handle_initial_bot_spawning", _suppress_bot_spawning)
mod:hook("PlayerUnitSpawnManager", "_handle_bot_spawning", _suppress_bot_spawning)

-- ---------------------------------------------------------------------------
-- What the mission you just entered actually applied
-- ---------------------------------------------------------------------------

-- Reported once per mission load, from every mission -- not just the mod's.
--
-- MutatorManager.on_gameplay_post_init is the earliest point where all three
-- sources the report reads are populated: the difficulty manager has parsed
-- havoc_data, the mutator manager has built its mutators from the
-- circumstances, and the level's themes have been created. Hooking the game
-- mode instead would run before the mutators exist and report an empty list.
--
-- Logged unconditionally rather than behind Diagnostics because the thing it
-- is here to catch -- an environmental modifier the player did not pick -- is
-- noticed after the fact, and a player who has to turn logging on and
-- reproduce it has already lost the run that showed it. One block of six
-- lines per mission load is cheap, and mod:info is log-only under DMF's
-- defaults, so none of it reaches chat or notifications.
mod:hook_safe("MutatorManager", "on_gameplay_post_init", function (self)
	if not mod:is_enabled() then
		return
	end

	local context = run.is_active()
		and string.format("run active, mission %d", run.depth() + 1)
		or "no run"

	difficulty.log_active_mission(context)
end)

-- The same report on demand, for a player who is already standing in the
-- mission and did not think to grab the log.
mod:command("cw_modifiers", mod:localize("command_cw_modifiers"), function ()
	for _, line in ipairs(difficulty.describe_active_mission()) do
		mod:echo(line)
	end
end)

-- ---------------------------------------------------------------------------
-- Collected buffs screen
-- ---------------------------------------------------------------------------

mod:add_require_path("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buffs_view")
mod:register_view({
	view_name = BUFFS_VIEW,
	view_settings = {
		init_view_function = function (ingame_ui_context)
			return true
		end,
		state_bound = true,
		path = "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buffs_view",
		class = "ChaosWastesBuffsView",
		disable_game_world = false,
		load_always = true,
		load_in_hub = false,
		game_world_blur = 1.1,
	},
	view_transitions = {},
	view_options = {
		close_all = false,
		close_previous = false,
	},
})

-- The keybind that opens this lives further down, after the launcher's own
-- helpers exist -- see mod.toggle_menu.

-- ---------------------------------------------------------------------------
-- Run launcher
-- ---------------------------------------------------------------------------

mod:add_require_path("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/launch_view")
mod:register_view({
	view_name = LAUNCH_VIEW,
	view_settings = {
		init_view_function = function (ingame_ui_context)
			return true
		end,
		state_bound = true,
		path = "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/launch_view",
		class = "ChaosWastesLaunchView",
		disable_game_world = false,
		load_always = true,
		load_in_hub = true,
		game_world_blur = 1.1,
	},
	view_transitions = {},
	view_options = {
		close_all = false,
		close_previous = false,
	},
})

-- The Mourningstar, or one of our own missions. Never the main menu.
--
-- The real requirement is chain.launch's: it waits on
-- _session_boot.leaving_game_session, and that flag is only ever set when a
-- live Managers.state.game_session exists. From the hub or a mission it flips;
-- from the main menu it never does and the promise waits forever.
--
-- A mission qualifies only if it is one of ours -- mod.manager, the same "is
-- my thing live" test everything else gates on. Relaunching out of somebody
-- else's game, or out of a mission this mod is not running, is not something
-- this screen should offer.
--
-- Launching straight out of a live mission is a path the chain itself never
-- takes -- every hop goes mission -> end screen -> hub, and _update_pending_launch
-- waits for the hub to settle before it calls chain.launch, because that
-- teardown killed the game once. Going direct from a mission was therefore an
-- assumption when this gate was widened. It has since been tested in game and
-- works: the mechanism is `adventure` rather than `hub`, so nothing is mid-
-- transition reading an extension manager that is about to disappear.
local function _can_open_launcher()
	-- is_host, not just "a mission is running": a client pressing Begin would
	-- reset a run it does not own and relaunch the session it is a guest in.
	if mod.is_host() then
		return true
	end

	local game_mode_manager = Managers.state and Managers.state.game_mode

	if not game_mode_manager then
		return false
	end

	local ok, game_mode_name = pcall(game_mode_manager.game_mode_name, game_mode_manager)

	return ok and (game_mode_name == "hub" or game_mode_name == "prologue_hub")
end

local function _open_launcher()
	if not Managers.ui or Managers.ui:view_active(LAUNCH_VIEW) then
		return
	end

	if not _can_open_launcher() then
		mod:echo(mod:localize("launch_hub_only"))

		return
	end

	Managers.ui:open_view(LAUNCH_VIEW)
end

mod:command("cw_launch", mod:localize("command_cw_launch"), _open_launcher)

-- ---------------------------------------------------------------------------
-- The one keybind
-- ---------------------------------------------------------------------------

-- Which screen you get is decided by where you are, because in each place there
-- is only one useful answer: in the Mourningstar you are setting a run up, in a
-- mission you are looking at what you have. The two hub screens are tabs of each
-- other, so neither needs a binding of its own.
--
-- Toggling rather than opening: the same key puts it away again, which is what
-- anyone tries first and saves reaching for escape while the world is stopped.
--
-- Defined here rather than beside the buffs view because it calls
-- _open_launcher, and a local referenced before its declaration compiles to a
-- global read -- silently nil at runtime.
local OUR_VIEWS = { LAUNCH_VIEW, BUFF_TOGGLE_VIEW, SETTINGS_VIEW, BUFFS_VIEW }

local function _close_open_view()
	local ui_manager = Managers.ui

	if not ui_manager then
		return false
	end

	for _, view_name in ipairs(OUR_VIEWS) do
		if ui_manager:view_active(view_name) then
			ui_manager:close_view(view_name)

			return true
		end
	end

	return false
end

mod.toggle_menu = function ()
	if not Managers.ui then
		return
	end

	-- Any of ours being open means the key is being used to dismiss it, whichever
	-- one it is.
	if _close_open_view() then
		return
	end

	if mod.manager then
		Managers.ui:open_view(BUFFS_VIEW)

		return
	end

	_open_launcher()
end

mod:command("cw_menu", mod:localize("command_cw_menu"), mod.toggle_menu)

-- ---------------------------------------------------------------------------
-- Buff toggle menu
-- ---------------------------------------------------------------------------

mod:add_require_path("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/settings_view")
mod:register_view({
	view_name = SETTINGS_VIEW,
	view_settings = {
		init_view_function = function (ingame_ui_context)
			return true
		end,
		state_bound = true,
		path = "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/settings_view",
		class = "ChaosWastesSettingsView",
		disable_game_world = false,
		load_always = true,
		load_in_hub = true,
		game_world_blur = 1.1,
	},
	view_transitions = {},
	view_options = {
		close_all = false,
		close_previous = false,
	},
})

mod:add_require_path("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view")
mod:register_view({
	view_name = BUFF_TOGGLE_VIEW,
	view_settings = {
		init_view_function = function (ingame_ui_context)
			return true
		end,
		state_bound = true,
		path = "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view",
		class = "ChaosWastesBuffToggleView",
		disable_game_world = false,
		load_always = true,
		load_in_hub = true,
		game_world_blur = 1.1,
	},
	view_transitions = {},
	view_options = {
		-- The mod options view stays open underneath so closing this one returns
		-- to it with its state intact. It cannot be seen or clicked meanwhile
		-- because the view reports _pass_input and _pass_draw false.
		close_all = false,
		close_previous = false,
	},
})

-- Opened from a dropdown because DMF has no button widget type:
-- _type_template_map in dmf/modules/ui/options/mod_options.lua maps only
-- header/group/checkbox/dropdown/keybind/numeric/text_input.
--
-- The dropdown resets itself afterwards with notify=false -- notify=true would
-- re-enter this handler -- and the reset also makes the same entry pickable
-- again, since the widget re-reads its displayed value from mod:get each frame.
mod.on_setting_changed = function (setting_id)
	-- Every change marks the active loadout dirty, not just the one below --
	-- "any edits while one is selected save to that preset" means all of them.
	_mark_loadout_dirty()

	if setting_id ~= "open_menu" then
		return
	end

	if mod:get(setting_id) ~= "open" then
		return
	end

	-- notify=false, or this re-enters. The reset also makes the same entry
	-- pickable again, since the dropdown re-reads its value from mod:get.
	mod:set(setting_id, "none", false)

	mod.toggle_menu()
end

mod:command("cw_buffs", mod:localize("command_cw_buffs"), function ()
	if Managers.ui and not Managers.ui:view_active(BUFF_TOGGLE_VIEW) then
		Managers.ui:open_view(BUFF_TOGGLE_VIEW)
	end
end)

-- ---------------------------------------------------------------------------
-- Mission chaining
-- ---------------------------------------------------------------------------

mod:add_require_path("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/run_select_view")
mod:register_view({
	view_name = RUN_SELECT_VIEW,
	view_settings = {
		init_view_function = function (ingame_ui_context)
			return true
		end,
		state_bound = true,
		path = "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/run_select_view",
		class = "ChaosWastesRunSelectView",
		disable_game_world = false,
		load_always = true,
		load_in_hub = false,
		game_world_blur = 0,
	},
	view_transitions = {},
	view_options = {
		-- Must not close the end-of-round view underneath: the picker sits
		-- beside the scoreboard rather than replacing it.
		close_all = false,
		close_previous = false,
	},
})

-- Buys time on the end screen so the picker can actually be read.
--
-- One hook covers both halves of the timeout because both read the same value:
-- StateGameScore.update compares it against server time to fire game_score_done,
-- and EndView renders the countdown on the continue button from it. Extending
-- it here keeps the displayed timer honest instead of leaving it counting down
-- to a deadline that no longer applies.
--
-- Only while a run is live -- a plain mission keeps the stock pacing.
mod:hook(ProgressionManager, "game_score_end_time", function (func, self)
	local end_time = func(self)

	if not end_time or not run.is_active() then
		return end_time
	end

	local extra_seconds = mod:get("end_screen_extra_seconds") or 0

	if extra_seconds <= 0 then
		return end_time
	end

	-- The accessor returns milliseconds.
	return end_time + extra_seconds * 1000
end)

-- Offer the next mission when the end screen opens on a won round. A loss is
-- the end of the run, so no picker.
mod:hook_safe(StateGameScore, "_present_end_of_round_view", function (self)
	if not run.is_active() then
		return
	end

	-- Consumed here whatever happens next, a loss included: a vote belongs to
	-- the mission it was opened in, and one left behind would hand a later
	-- picker three missions rolled for a run that is already over.
	local voted_options = mod._vote_options
	local voted_winner = mod._vote_winner
	local voted_binding = mod._vote_binding

	mod._vote_options = nil
	mod._vote_winner = nil
	mod._vote_binding = nil

	local end_result = Managers.mechanism and Managers.mechanism:end_result()

	if end_result ~= "won" then
		mod:info("run failed after %d mission(s)", run.depth())
		run.reset("mission lost")

		return
	end

	-- What the party voted on, if they did. Rolling a fresh set here instead
	-- would put three unrelated missions in front of the host and silently
	-- discard the vote -- and the vote is the only thing the clients got a say
	-- in, because during the mission is the only time there is a channel.
	local options = voted_options
	local default = voted_winner

	if not options or #options == 0 then
		options = chain.roll_options(run.state().params)
		default = nil
	end

	if not options or #options == 0 then
		mod:error("no eligible missions to continue the run with")

		return
	end

	-- Pre-select the first option, rather than treating "nothing chosen" as a
	-- decision to end the run.
	--
	-- The end screen can finish before a click lands -- spamming continue
	-- fires game_score_done early, the interception sees no selection, the
	-- stock exit runs, and the click that arrives a moment later sets a value
	-- nothing will ever read. The run dies to a race rather than to a choice.
	--
	-- Selecting up front removes the race outright instead of papering over
	-- it: the state is already correct when the screen opens, so it no longer
	-- matters whether the player clicks, clicks late, or never clicks at all.
	-- Clicking a different card simply replaces the default.
	run.state().next_mission = default or options[1]

	mod:debug_log("defaulting to", run.state().next_mission.mission_name,
		default and "(the vote winner)" or "until another card is chosen")

	-- The view is told which card, not left to infer it. It used to hardcode
	-- the first one as selected, so a vote that won on card 3 opened a screen
	-- claiming card 1 -- and any click at all replaced the winner.
	local selected_index = 1

	for i = 1, #options do
		if options[i] == default then
			selected_index = i

			break
		end
	end

	Managers.ui:open_view(RUN_SELECT_VIEW, nil, nil, nil, nil, {
		options = options,
		selected_index = selected_index,
		locked = default ~= nil and voted_binding or false,
	})
end)

-- The exact point the run gets redirected.
--
-- Both ways out of the end screen -- pressing continue and the presentation
-- timer expiring -- call trigger_event("game_score_done"), which lands here.
-- Normally this sets data.game_score_done, the "score" state sees the flag and
-- advances to mission_server_exit, and wanted_transition sends you to the
-- Morningstar. Swallowing it means that flag is never set, the mechanism stays
-- put, and chain.launch replaces the mechanism outright with the next mission.
--
-- Hooked here rather than on MechanismManager.trigger_event because that is a
-- generic dispatcher for every mechanism event in the game; this is the one
-- function that actually means "the end screen is done".
-- Moves the chosen mission from "selected" to "queued for the hub". Shared,
-- because the end screen has two exits and they do not meet: the timer path
-- goes through game_score_done, while pressing continue calls
-- multiplayer_session:leave("skip_end_of_round") and never touches the
-- mechanism event at all.
local function _queue_next_mission(via)
	local next_mission = run.state().next_mission

	if not next_mission then
		return false
	end

	run.state().next_mission = nil
	run.state().pending_launch = next_mission
	run.state().missions_completed = run.state().missions_completed + 1

	run.arm_restore()

	mod:debug_log("queued launch through hub:", next_mission.mission_name,
		"| via", via, "| run depth now", run.state().missions_completed)

	if Managers.ui and Managers.ui:view_active(RUN_SELECT_VIEW) then
		Managers.ui:close_view(RUN_SELECT_VIEW)
	end

	return true
end

-- Pressing continue on the end screen leaves the session directly. The leave
-- still happens -- we are not trying to keep the session alive -- we just
-- record the choice first, so the hub relaunch picks it up exactly as it does
-- on the timer path.
-- One hook doing two jobs, because it has to be one.
--
-- A second mod:hook* on the same method from the same mod is logged as a rehook
-- and silently dropped, so the strike-team fix cannot be added alongside the
-- end-of-round handling -- it has to live inside it. It is also a full hook
-- rather than hook_safe: hook_safe runs after the original and cannot change
-- the arguments, and rewriting the reason is the entire fix.
mod:hook(MultiplayerSessionManager, "leave", function (func, self, reason)
	-- Leaving a mission should not also leave the strike team. The escape menu
	-- has a separate button for that, and the two reasons differ only in whether
	-- mechanism_left_session calls _leave_party.
	if escape.should_keep_party(reason) then
		mod:info("leaving the mission but staying in the strike team")

		reason = escape.KEEP_PARTY_REASON
	end

	local result = func(self, reason)

	-- After the original, preserving the ordering the previous hook_safe had.
	if reason == "skip_end_of_round" then
		_queue_next_mission("continue pressed")
	end

	return result
end)

mod:hook_safe(MechanismAdventure, "game_score_done", function (self)
	_queue_next_mission("end screen timed out")
end)

-- Fires the queued mission once the hub has settled. Polled rather than hooked
-- because "the hub is ready to launch from" is a state, not an event, and
-- launching too early silently does nothing.
local hub_settle_accum = 0

-- The four conditions below are the real gate; this is the margin for whatever
-- they do not cover. Tested fine at 0.2s, but only on warm hub loads -- the
-- crash this guards against appeared when the hub loaded slowly, which those
-- runs never reproduced. 1s costs a second per hop and covers the case the
-- testing could not.
local HUB_SETTLE_SECONDS = 1

-- Fires the queued mission once the hub is genuinely ready.
--
-- "Ready" is stricter than it looks. Being in the hub game mode only means the
-- game mode object exists -- the hub may still be loading its level and its
-- mechanism may still be mid-transition. Launching there calls
-- multiplayer_session:reset(), which tears down Managers.state.extension while
-- MechanismHub.wanted_transition is about to read it, and the game dies inside
-- the engine's own transition rather than anywhere near this mod.
--
-- Hence four conditions plus a settle timer. The timer is the honest part: it
-- is not possible to enumerate every manager the hub still needs, so requiring
-- the conditions to hold continuously for a moment is what actually makes this
-- safe, rather than a longer list of checks that might still miss one.
local function _update_pending_launch(dt)
	local state = run.state()

	if not state.pending_launch then
		hub_settle_accum = 0

		-- Cheap no-op unless it is actually held, which it only is between
		-- queueing a launch and making it.
		net.hold_admission(false)

		return
	end

	local game_mode = Managers.state and Managers.state.game_mode
	local game_mode_name = game_mode and game_mode:game_mode_name()

	-- Shut the door as soon as we are in the hub, before the settle timer
	-- rather than after it.
	--
	-- With SoloMourningstar the hub is a listen server on the same address the
	-- party joined, so for the whole of this window a reconnecting client can
	-- land here instead of in the mission we are about to launch. The client
	-- re-arms itself if that happens, but not colliding at all is better than
	-- recovering from it.
	if game_mode_name == "hub" then
		net.hold_admission(true)
	end
	local session = Managers.multiplayer_session
	local mechanism = Managers.mechanism

	local ready = game_mode_name == "hub"
		-- The exact field the crash tripped over: gameplay systems are up.
		and Managers.state.extension ~= nil
		and session ~= nil
		and not session:is_booting_session()
		and not session:is_leaving()
		-- Not still swapping in from left_session.
		and (not mechanism or mechanism:mechanism_name() == "hub")

	if not ready then
		hub_settle_accum = 0

		return
	end

	hub_settle_accum = hub_settle_accum + (dt or 0)

	if hub_settle_accum < HUB_SETTLE_SECONDS then
		return
	end

	local mission_context = state.pending_launch

	state.pending_launch = nil
	hub_settle_accum = 0

	mod:debug_log("hub settled for", HUB_SETTLE_SECONDS, "s, launching queued mission", mission_context.mission_name)

	if not chain.launch(mission_context) then
		run.reset("launch failed")
	end
end

-- Runs before triggers.update on purpose. run.restore() sets the carried buff
-- family, and the family-choice request that triggers.update fires skips any
-- player who already has one -- so restoring first is what stops a continued
-- run from re-prompting you to pick a family every mission.
local function _update_run(dt)
	if not mod.is_host() then
		return
	end

	local state = run.state()

	if not state.active then
		state.active = true
		state.missions_completed = state.missions_completed or 0
	end

	-- Refreshed once per mission while the mission is live, and deliberately
	-- NOT cleared at teardown.
	--
	-- Two constraints pull against each other: the ramp needs this to follow
	-- the mission actually being played, but the end screen reads it after the
	-- game mode is gone -- and once Managers.state.difficulty is destroyed it
	-- cannot be recomputed. Refreshing in-mission and letting the value
	-- outlive the mission satisfies both; clearing it on destroy left the
	-- picker with nothing to roll from.
	if not params_this_mission then
		local params = chain.current_params()

		if params then
			state.params = params
			params_this_mission = true

			mod:debug_log("run difficulty for this mission:", chain.describe_params(params))
		end
	end

	-- Keeps being called until run.restore says everyone is in, not until it
	-- first does something. A client reconnecting after a hop arrives minutes
	-- after the host, and the single-shot version would have finished long
	-- before they spawned.
	if not restored_this_mission and run.should_restore() then
		restored_this_mission = run.restore(dt)
	end

	-- Keep the carry-over snapshot fresh while the mission runs, rather than
	-- taking it once during teardown.
	--
	-- The _destroy_buff_system hook was the only capture point and it produced
	-- nothing: by the time it ran the manager was already gone, so every
	-- capture silently returned false and the next mission started from
	-- scratch. Snapshotting live means the data is already in hand whenever
	-- the mission ends, however it ends -- won, lost, quit or crashed -- and
	-- the teardown capture becomes a best-effort refresh instead of the one
	-- chance to get it right.
	capture_accum = capture_accum + 1

	if capture_accum >= 60 then
		capture_accum = 0

		run.capture(true)
	end
end

-- Retries any spawn held above. The hook itself only runs when the game calls
-- it, and it will not call again on its own -- so without this the held player
-- would simply never get a pool.
local function _update_pending_pool_init(dt)
	if not next(pending_pool_init) then
		return
	end

	for id, entry in pairs(pending_pool_init) do
		entry.elapsed = entry.elapsed + dt

		local manager = entry.manager

		if mod.manager ~= manager then
			-- The mission ended underneath us; drop it rather than calling into
			-- a torn-down manager.
			pending_pool_init[id] = nil
		else
			-- Re-entering the hook is the point: it re-tests the abilities and
			-- clears the entry itself once they resolve or the timeout expires.
			pcall(manager._manage_player_spawn, manager, entry.player, entry.is_respawn)
		end
	end
end

-- The hold is derived, not trusted.
--
-- Two reasons it cannot be left to the views. First, on_exit is not
-- guaranteed: a mod reload with the screen open, or a mission tearing down
-- underneath it, both skip it, and a stranded hold means the gameplay timer
-- stays at zero for the rest of the session. Second, the tabs -- moving from
-- the collected-buffs screen to Settings closes one view and opens another,
-- and if the hold belonged to whichever view last ran a callback, the world
-- would start moving again the moment you changed tab. Any of our screens
-- being open is the condition, so it is computed from that every frame.
local function _reconcile_pause_hold()
	local ui_manager = Managers.ui
	local want_hold = false

	if ui_manager then
		for _, view_name in ipairs(OUR_VIEWS) do
			if ui_manager:view_active(view_name) then
				want_hold = true

				break
			end
		end
	end

	if want_hold == pause.is_held() then
		return
	end

	pause.set_hold(want_hold)

	mod:debug_log(want_hold and "holding the pause for an open menu"
		or "released the pause hold; no menu open")
end

mod.update = function (dt)
	_update_pending_launch(dt)
	_update_run(dt)
	_update_pending_pool_init(dt)
	_reconcile_pause_hold()
	_update_loadout_save(dt)
	triggers.update(dt)
	pause.update(dt)
	custom_buffs.update(dt)
	net.update(dt)
end

-- ---------------------------------------------------------------------------
-- Testing helpers
-- ---------------------------------------------------------------------------

-- Ends the current mission immediately. Goes through complete_game_mode /
-- fail_game_mode rather than poking _set_end_conditions_met directly: those
-- set the mode's own completion flags and let its normal end-condition
-- evaluation run, so the outro, the end screen and the picker all behave
-- exactly as they would after a real mission.
local function _end_mission(won)
	local game_mode_manager = Managers.state and Managers.state.game_mode

	if not game_mode_manager then
		mod:echo(mod:localize("debug_end_unavailable"))

		return false
	end

	if not mod.has_authority() then
		mod:echo(mod:localize("debug_end_unavailable"))

		return false
	end

	-- The keybind is easy to fire two or three times before the outro starts,
	-- which re-completes an already-finished mission and clutters the log at
	-- exactly the moment you are trying to read it.
	if game_mode_manager:end_conditions_met() then
		mod:debug_log("mission already ending, ignoring repeat request")

		return false
	end

	local method = won and game_mode_manager.complete_game_mode or game_mode_manager.fail_game_mode
	local ok, err = pcall(method, game_mode_manager, "chaos_wastes_debug")

	if not ok then
		mod:error("could not end the mission: %s", _escape(err))

		return false
	end

	mod:debug_log("mission ended for testing, outcome:", won and "won" or "lost")

	return true
end

mod.debug_end_mission_won = function ()
	_end_mission(true)
end

mod.debug_end_mission_lost = function ()
	_end_mission(false)
end

-- Arms a run without launching one.
--
-- _should_activate needs three things to take a mission over: run.is_launched(),
-- the host role, and game_mode._is_server. chain.launch is only how the first
-- of those usually gets set -- nothing requires it, and requiring it is what
-- makes multiplayer testing awkward, because the chain cannot survive a
-- session reset under Realms yet (see chain.lua's launch guard).
--
-- So: arm here, then start the mission with SoloPlay. The mod activates
-- exactly as if the launcher had done it, and no session reset happens. That
-- matters because SoloPlay launches under Realms are known good -- three clean
-- ones during the port measurement -- while the chain's own path is the one
-- that locked a machine.
--
-- Must be run in the Mourningstar, before the mission loads: activation is
-- decided in _init_buff_system during mission init, and the flag has to be set
-- by then. Arriving at the hub clears it (the hub branch of the same hook), so
-- arm after you get there, not before.
--
-- Leaves run.state().params nil on purpose. chain.roll_options falls back to
-- chain.current_params() when it is, which reads the difficulty off the
-- mission actually being played -- more accurate here than anything this
-- command could guess.
-- Who is connected, whether they match, and whether custom buffs are live.
--
-- The question this answers is asked from both ends of a session, so it
-- deliberately works the same in either role and needs no arguments.
-- Open a vote on the next mission, host side.
--
-- Rolls the same three options the end screen would and puts them to the party
-- while the mission is still being played -- which is not a stylistic choice.
-- StateGameScore is a top-level game state, so the gameplay session and Realms'
-- bus are both gone by the time the end-of-round screen appears. During the
-- mission is the only window there is.
--
-- Takes an explicit command for now so it can be exercised without playing a
-- mission to completion; the automatic trigger comes when the commit hook does.
-- Resolve the open vote into the run's own next-mission slot.
--
-- This used to hand the winner straight to Realms with change_mechanism, on the
-- theory that Realms would defer it, keep the party and skip the reconnect. It
-- does not: Preparation only reaches its completing transition from the
-- `waiting` phase, which only a host re-boot can set, so a bare mechanism change
-- dead-ends in a loading screen that never resolves. chain.lua carries the
-- reasoning. The hop is a re-host, and the clients come back to it.
--
-- So all this does now is decide which mission, and it decides it here rather
-- than at the end screen because during the mission is the only time there is a
-- channel to have voted over.
--
-- Returns a reason string when it declines, because every one of them is a thing
-- worth seeing in a log rather than a silent no-op.
local function _resolve_vote()
	if not mod.is_host() then
		return "not the host"
	end

	local options = mod._vote_options

	if type(options) ~= "table" or #options == 0 then
		return "no vote was opened"
	end

	local index, cast = net.vote_result()

	if not index then
		return "no vote is open"
	end

	local option = options[index]

	if not option then
		return "the winning option no longer exists"
	end

	mod:info("vote resolved: option %d (%s) with %d vote(s) cast",
		index, tostring(option.mission_name), cast)

	-- Left in mod._vote_options on purpose. The end screen reads all three back
	-- so the picker shows the missions the party voted on, with this one
	-- selected, instead of rolling a fresh unrelated set.
	mod._vote_winner = option

	-- Whether the picker may still be overridden.
	--
	-- Solo, the vote is a debug command and the picker is the real interface --
	-- locking it would take the choice away from the only person making one.
	-- With anyone else connected the vote *is* the decision, and a host quietly
	-- clicking past it on a screen nobody else can see is the whole reason the
	-- vote exists.
	mod._vote_binding = net.connected_count() > 0

	return nil
end

-- The last moment there is a bus.
--
-- complete_game_mode runs inside gameplay; StateGameScore is a top-level game
-- state, so by the end-of-round screen MissionCleanupUtilies has disconnected
-- the game session and Realms' mod network is gone with it. Anything the clients
-- need to be told about what happens next has to be said here.
--
-- Two things are said: the vote is resolved, and the hop is announced. The
-- announcement is not conditional on the vote -- a host who never opened one
-- still re-hosts, and the clients still have to know to follow.
--
-- hook_safe: the original must run whatever happens here. Ending the mission is
-- not ours to prevent.
mod:hook_safe("GameModeManager", "complete_game_mode", function (self, reason, triggered_from_flow)
	if not mod.has_authority() or not run.is_active() then
		return
	end

	local declined = _resolve_vote()

	if declined then
		mod:info("no vote to resolve: %s", declined)
	end

	-- The name is for the clients' log line and echo only; the host is still
	-- free to pick a different card on the end screen, and nothing on the client
	-- side reads it back. What matters is that a drop is coming and it is ours.
	local winner = mod._vote_winner

	net.announce_hop(winner and winner.mission_name or nil)
end)

-- Resolve the vote on demand, so the first time this runs is a moment you chose
-- rather than the end of a real mission.
--
-- Does not announce a hop: there is no hop until the mission ends, and telling
-- clients to reconnect while everyone is still playing would drop them for
-- nothing.
mod:command("cw_vote_close", mod:localize("command_cw_vote_close"), function ()
	local declined = _resolve_vote()

	if declined then
		mod:echo(string.format("Chaos Wastes at Home: %s", declined))

		return
	end

	mod:echo(mod:localize("vote_closed", chain.mission_display_name(mod._vote_winner.mission_name)))
end)

mod:command("cw_vote_open", mod:localize("command_cw_vote_open"), function ()
	if not mod.is_host() then
		mod:echo(mod:localize("vote_host_only"))

		return
	end

	local options = chain.roll_options(run.state().params)

	if not options or #options == 0 then
		mod:echo(mod:localize("vote_no_options"))

		return
	end

	local labels = {}

	for i = 1, #options do
		labels[i] = chain.mission_display_name(options[i].mission_name)
	end

	mod._vote_options = options

	if not net.start_vote(labels) then
		mod:echo(mod:localize("vote_no_options"))

		return
	end

	mod:echo(mod:localize("vote_opened"))

	for _, line in ipairs(net.vote_report()) do
		mod:echo(line)
	end
end)

-- Cast a vote, either role. On the host it records locally; on a client it goes
-- to the host, which owns the tally.
mod:command("cw_vote", mod:localize("command_cw_vote"), function (index)
	local ok, err = net.cast_vote(index)

	if not ok then
		mod:echo(string.format("Chaos Wastes at Home: %s", tostring(err)))

		return
	end

	for _, line in ipairs(net.vote_report()) do
		mod:echo(line)
	end
end)

-- The tally so far, from either end.
mod:command("cw_votes", mod:localize("command_cw_votes"), function ()
	for _, line in ipairs(net.vote_report()) do
		mod:echo(line)
	end
end)

-- What the run is holding for whom.
--
-- The peer id is printed next to each person so this lines up with /cw_peers:
-- the carry-over is keyed by account id (see run.lua's _player_key), which is
-- the right key and the wrong one to read a log with.
mod:command("cw_carry", mod:localize("command_cw_carry"), function ()
	local state = run.state()
	local any = false

	mod:echo(string.format("Chaos Wastes at Home: run depth %d, restore %s",
		run.depth(), state.restore_pending and "pending" or "not pending"))

	for _, record in pairs(state.players) do
		any = true

		local count = 0
		local names = {}

		for buff_name, stacks in pairs(record.buffs) do
			count = count + stacks
			names[#names + 1] = stacks > 1
				and string.format("%s x%d", buff_name, stacks)
				or buff_name
		end

		table.sort(names)

		mod:echo(string.format("  %s (peer %s): %d stack(s), family %s%s",
			tostring(record.name), tostring(record.peer_id), count,
			tostring(record.family), record.restored and " [restored]" or ""))

		if #names > 0 then
			mod:echo("    " .. table.concat(names, ", "))
		end
	end

	if not any then
		mod:echo("  nothing carried yet")
	end
end)

mod:command("cw_peers", mod:localize("command_cw_peers"), function ()
	for _, line in ipairs(net.report()) do
		mod:echo(line)
	end
end)

mod:command("cw_arm", mod:localize("command_cw_arm"), function ()
	run.reset("arming a test run")
	run.mark_launched()

	mod:echo(mod:localize("arm_done"))
	mod:info("run armed by /cw_arm - next mission will be taken over without going through chain.launch")
end)

mod:command("cw_win", mod:localize("command_cw_win"), mod.debug_end_mission_won)
mod:command("cw_lose", mod:localize("command_cw_lose"), mod.debug_end_mission_lost)

mod:command("cw_buff", mod:localize("command_cw_buff"), function (kind)
	if not mod.has_authority() then
		mod:echo(mod:localize("command_not_active"))

		return
	end

	local granted

	if kind == "family" then
		granted = triggers.grant_family()
	else
		granted = triggers.grant_legendary()
	end

	if not granted then
		mod:echo(mod:localize("command_failed"))
	end
end)

-- Grant one named buff, bypassing the pools. `/cw_give` with no name, or with
-- a name that does not exist, searches instead of failing -- the buff names are
-- long and easy to mistype, and a bare "unknown buff" would send you to the
-- source to find the spelling.
local MAX_SUGGESTIONS = 12

mod:command("cw_give", mod:localize("command_cw_give"), function (buff_name)
	local function suggest(needle, header)
		local matches = triggers.find_buff_names(needle)

		if #matches == 0 then
			mod:echo(string.format("no buff name contains '%s'", _escape(needle)))

			return
		end

		mod:echo(string.format("%s (%d):", header, #matches))

		for i = 1, math.min(#matches, MAX_SUGGESTIONS) do
			mod:echo("  " .. matches[i])
		end

		if #matches > MAX_SUGGESTIONS then
			mod:echo(string.format("  ... and %d more - narrow the search", #matches - MAX_SUGGESTIONS))
		end
	end

	if not buff_name or buff_name == "" then
		mod:echo("custom buffs:")

		for _, name in ipairs(custom_buffs.buff_names()) do
			mod:echo("  " .. name)
		end

		mod:echo("usage: /cw_give <buff_name> - pass part of a name to search")

		return
	end

	-- Any template can be granted, including one another mod added, so the
	-- network id has to be guaranteed here rather than assumed from boot.
	custom_buffs.ensure_network_id(buff_name)

	local ok, reason = triggers.grant_named(buff_name)

	-- Escaped: both the name and the failure reason reach here from outside,
	-- and mod:echo re-formats its message -- a literal % in either would crash
	-- the echo instead of reporting the problem.
	if ok then
		mod:echo(string.format("granted '%s'", _escape(buff_name)))
	else
		mod:echo(string.format("could not grant '%s': %s", _escape(buff_name), _escape(reason or "unknown reason")))
		suggest(buff_name, "closest matches")
	end
end)

-- Deliberately not gated on mod.manager: the most useful time to run this is
-- when you suspect the buff system did not come up at all.
mod:command("cw_verify", mod:localize("command_cw_verify"), function ()
	for _, line in ipairs(custom_buffs.report()) do
		mod:echo(line)
	end
end)

mod:command("cw_status", mod:localize("command_cw_status"), function ()
	if not mod.manager then
		mod:echo(mod:localize("command_not_active"))

		return
	end

	-- The role first, and in chat rather than the log.
	--
	-- Activation announces itself with mod:info, which under DMF's defaults is
	-- log-only -- so "did it take the mission over, and as what" was a question
	-- you could only answer by reading a file. That is the wrong shape for a
	-- question asked once per test launch, and it will be asked a lot more once
	-- there is a client role to confirm as well.
	mod:echo(string.format("Chaos Wastes at Home: active as %s (authority: %s)",
		tostring(mod.role), tostring(mod.has_authority())))

	local stats = triggers.stats()

	-- Totals, then the part of them that was free -- otherwise a run with a
	-- starting hand reports more picks than the limit allows and reads as a bug.
	mod:echo(string.format("Chaos Wastes at Home: %d family buffs, %d legendary picks granted this mission",
		stats.family_granted, stats.legendary_granted))

	if stats.starting_family_given > 0 or stats.starting_legendary_given > 0 then
		mod:echo(string.format("  of those, %d family buffs and %d legendary picks were the starting hand, which does not count against the run's limits",
			stats.starting_family_given, stats.starting_legendary_given))
	end

	local missing = particle_guard.missing_effects()

	if #missing > 0 then
		mod:echo(string.format("%d particle effect(s) unavailable and silently skipped: %s",
			#missing, table.concat(missing, ", ")))
	end

	local spawn_failures = spawn_guard.failure_count()

	if spawn_failures > 0 then
		mod:echo(string.format("%d horde spawn quer%s failed and were skipped",
			spawn_failures, spawn_failures == 1 and "y" or "ies"))
	end
end)
