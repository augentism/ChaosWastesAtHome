local mod = get_mod("ChaosWastesAtHome")

mod.version = "0.4.0"

-- Required rather than reached through CLASS: these are loaded lazily by the
-- game (the game mode when a mission starts, the constant element by the UI
-- manager), so CLASS may not have them yet when mods load. Requiring pulls
-- them in and hands back the class table to hook directly.
local MatchmakingConstants = require("scripts/settings/network/matchmaking_constants")
local HordeMissionBuffsManager = require("scripts/managers/mission_buffs/horde_mission_buffs_manager")
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
local particle_guard = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/particle_guard")
local spawn_guard = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/spawn_guard")
local asset_loader = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/asset_loader")
local custom_buffs = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/custom_buffs")
local buff_pool = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/buff_pool")
local escape = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/escape")
local solo = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/solo")

local RUN_SELECT_VIEW = "chaos_wastes_run_select_view"
local BUFF_TOGGLE_VIEW = "chaos_wastes_buff_toggle_view"
local LAUNCH_VIEW = "chaos_wastes_launch_view"
local BUFFS_VIEW = "chaos_wastes_buffs_view"

-- Set for the lifetime of a mission we have taken over; everything else in the
-- mod treats a non-nil `mod.manager` as "the Mortis buff system is live".
mod.manager = nil
mod.game_mode = nil

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

particle_guard.install()
spawn_guard.install()
escape.install()
custom_buffs.register()

-- Singleplay only, and not negotiable. On a hosted session the buff system
-- sends rpc_client_mission_buffs_* to every remote player, and a client
-- running the stock MissionBuffsManager has never registered those events --
-- the mod would break other people's game, not just this one.
local function _should_activate(game_mode, game_mode_name)
	if game_mode_name == "hub" or game_mode_name == "prologue_hub" then
		return false
	end

	-- Opt-in. Without this the mod takes over every mission that happens to be
	-- singleplay, which for anyone running SoloPlay is all of their solo play --
	-- the "boons in normal matches" reports. A run has to be started from our
	-- own launcher, and the flag rides along through every hop of the chain.
	if not run.is_launched() then
		return false
	end

	if not game_mode._is_server then
		return false
	end

	local session_manager = Managers.multiplayer_session

	if not session_manager or session_manager:host_type() ~= HOST_TYPES.singleplay then
		return false
	end

	return true
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

	if not _should_activate(self, game_mode_name) then
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

	triggers.reset()
	asset_loader.request()
	custom_buffs.register_network_lookup()
	-- Retried here because the load-time attempt declines at boot: the engine
	-- module it hooks cannot be required until the game is further along.
	custom_buffs.install_hooks()
	custom_buffs.apply_weight()
	custom_buffs.reset_counters()

	_warn_about_conflicts()

	mod:info("Mortis buff system active in game mode '%s'", _escape(game_mode_name))
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

mod:hook(HordeMissionBuffsManager, "_manage_player_spawn", function (func, self, player, is_respawn)
	if mod.manager ~= self or not player then
		return func(self, player, is_respawn)
	end

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

	self._backend_buffs_to_exclude = exclude
	self._backend_weighted_randomization = {
		buff_family_weights = {},
	}

	mod:debug_log("skipped the hordes backend request; using even family weights;",
		carried, "buff(s) already owned this run and", switched_off,
		"switched off in the toggle menu excluded from the pools")
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

-- Only from the hub.
--
-- chain.launch waits on _session_boot.leaving_game_session, and that flag is
-- only ever set when a live Managers.state.game_session exists. From the hub or
-- a mission it flips; from the main menu it never does and the promise waits
-- forever. Mid-mission launching is the chain's job, not this screen's.
local function _can_open_launcher()
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
local OUR_VIEWS = { LAUNCH_VIEW, BUFF_TOGGLE_VIEW, BUFFS_VIEW }

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

	local end_result = Managers.mechanism and Managers.mechanism:end_result()

	if end_result ~= "won" then
		mod:info("run failed after %d mission(s)", run.depth())
		run.reset("mission lost")

		return
	end

	local options = chain.roll_options(run.state().params)

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
	run.state().next_mission = options[1]

	mod:debug_log("defaulting to", options[1].mission_name, "until another card is chosen")

	Managers.ui:open_view(RUN_SELECT_VIEW, nil, nil, nil, nil, {
		options = options,
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

		return
	end

	local game_mode = Managers.state and Managers.state.game_mode
	local game_mode_name = game_mode and game_mode:game_mode_name()
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
local function _update_run()
	if not mod.manager then
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

	if not restored_this_mission and run.should_restore() then
		restored_this_mission = run.restore()
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

-- The hold is released in the view's on_exit, but on_exit is not guaranteed --
-- a mod reload with the screen open, or a mission tearing down underneath it,
-- both skip it. A stranded hold means the gameplay timer stays at zero for the
-- rest of the session, so the state is reconciled against the view every frame
-- rather than trusted.
local function _release_orphaned_pause_hold()
	if not pause.is_held() then
		return
	end

	if Managers.ui and Managers.ui:view_active(BUFFS_VIEW) then
		return
	end

	pause.set_hold(false)

	mod:debug_log("released an orphaned pause hold")
end

mod.update = function (dt)
	_update_pending_launch(dt)
	_update_run()
	_update_pending_pool_init(dt)
	_release_orphaned_pause_hold()
	triggers.update(dt)
	pause.update()
	custom_buffs.update(dt)
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

	if not mod.manager then
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

mod:command("cw_win", mod:localize("command_cw_win"), mod.debug_end_mission_won)
mod:command("cw_lose", mod:localize("command_cw_lose"), mod.debug_end_mission_lost)

mod:command("cw_buff", mod:localize("command_cw_buff"), function (kind)
	if not mod.manager then
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

	local stats = triggers.stats()

	mod:echo(string.format("Chaos Wastes at Home: %d family buffs, %d legendary picks granted this mission",
		stats.family_granted, stats.legendary_granted))

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
