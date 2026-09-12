local mod = get_mod("ChaosWastesAtHome")

local BuffSettings = require("scripts/settings/buff/buff_settings")
local BuffTemplates = require("scripts/settings/buff/buff_templates")

local buff_categories = BuffSettings.buff_categories
local stat_buffs = BuffSettings.stat_buffs

-- What is left of this mod's own buff content, now that the blessings ship as
-- the CwahBuffs addon and register through the public API like anyone else's.
--
-- Two things stayed behind:
--
--   * the choice shield, which is a core mechanic rather than a card -- nothing
--     offers it, pause.lua and choice_shield.lua depend on it existing, and a
--     player who uninstalls the card pack must not lose it;
--   * the /cw_verify report, which reads the registry and therefore covers every
--     registrant rather than only ours.
--
-- Adding a BUFF belongs in CwahBuffs (or an addon of your own), not here. See
-- docs/adding-custom-buffs.md.

local custom_buffs = {}

-- The registry that does the actual registering, shared with any addon mod.
--
-- Loaded before the counter table below, because it adopts and republishes
-- mod._custom_buff_procs so this mod's proc counters and an addon's land in the
-- same table and the same report.
local registry = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/buff_registry")

-- Bumped by proc buffs when they fire, so /cw_verify can prove an effect ran
-- rather than just that the buff is attached. A passive stat buff has nothing
-- to count -- its multiplier is read straight off the extension instead.
--
-- Parked on `mod` so it survives a mod reload. Not cosmetic: a reload rebuilds
-- the buff template, but a buff already applied to the player keeps the
-- proc_func closure it was created with. A fresh local table would leave that
-- closure counting into an orphaned table while the report read an empty one --
-- the counter would sit at zero for a buff that was firing perfectly well.
local proc_counts = registry.counters()

-- The category this mod's own buffs -- and, by default, an addon's -- are filed
-- under. Registered here rather than written straight into filtering_categories,
-- so it goes through exactly the path an addon's does.
local CATEGORY = "custom"

registry.register_category(CATEGORY, {
	label = "Custom",
	owner = "ChaosWastesAtHome",
})

local CATALOGUE = {}

local function _add(entry)
	CATALOGUE[#CATALOGUE + 1] = entry

	return entry
end


-- ---------------------------------------------------------------------------
-- Not a pickable buff: the shield worn while a card is on screen
-- ---------------------------------------------------------------------------

-- Pausing cannot protect anyone in multiplayer -- stopping the host's clock
-- disconnects everybody else -- so a player reading three cards is otherwise
-- standing still in the middle of a fight. This makes them untargetable and
-- unkillable for exactly as long as their own card is up.
--
-- Keywords rather than stat buffs, and these three specifically:
--   invulnerable / damage_immune  -- nothing gets through
--   unperceivable                 -- nothing aims at them in the first place
--
-- `unperceivable` and not `invisible`: side_system's _is_valid_target rejects
-- either, but `invisible` also drives the stealth *presentation* -- the screen
-- colour grade and the ability sound, built for a five-second Veteran ability.
-- On something that flicks on and off with every card that fires constantly.
-- Established by SoloSandbox, whose stealth bestowment carries the same note.
--
-- No `pool` key, so it is registered and networked like every other template
-- here but never offered as a card. Being in the catalogue is what matters: the
-- registry's all_template_names covers it, so its network id is part of what the
-- peer handshake compares, and the ids cannot silently disagree.
--
-- predicted = false, matching the rest. SoloSandbox uses predicted = true to
-- stay out of NetworkLookup entirely, which is right for a client-side solo
-- mod and wrong here: the host applies this to *other people's* units, and the
-- server is what decides whether an attack lands.
local CHOICE_SHIELD_BUFF = "cwah_choice_shield"

custom_buffs.CHOICE_SHIELD_BUFF = CHOICE_SHIELD_BUFF

_add({
	id = CHOICE_SHIELD_BUFF,
	template = function ()
		local keywords = BuffSettings.keywords
		local wanted = { "invulnerable", "damage_immune", "unperceivable" }
		local resolved = {}

		-- Built by name and checked, rather than indexed blind. A keyword the
		-- game has renamed would otherwise leave a nil in the middle of the
		-- array, which silently shortens it -- so the shield would apply, report
		-- success, and protect against less than it claims.
		for i = 1, #wanted do
			local keyword = keywords and keywords[wanted[i]]

			if keyword then
				resolved[#resolved + 1] = keyword
			else
				mod:error("buff keyword '%s' no longer exists - the choice shield is weaker than it should be",
					wanted[i])
			end
		end

		return {
			class_name = "buff",
			max_stacks = 1,
			max_stacks_cap = 1,
			predicted = false,
			-- `generic`, NOT hordes_buff like every pickable buff above, and this
			-- is load-bearing rather than tidiness.
			--
			-- The tactical overlay (Tab) walks the player's buffs, and for
			-- anything categorised hordes_buff it does
			-- `HordeBuffsData[buff_name].is_family_buff`
			-- (hud_element_tactical_overlay.lua:366-368) -- unguarded, alone
			-- among that block's lines, every one of which is `buff_data and`.
			-- This buff is not pickable so it has no HordesBuffsData entry, so
			-- that is a nil index and a hard crash the moment anyone opens Tab
			-- while a card is up. It crashed a real player.
			--
			-- `generic` also makes the overlay skip it outright: its display gate
			-- (line 311) is "not generic and not weapon and ... or has_hud", and
			-- this has no HUD data either. Which is the right outcome anyway --
			-- an internal mechanism has no business in the buff list.
			buff_category = buff_categories.generic,
			keywords = resolved,
		}
	end,
})

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

-- Named delegates rather than inlining registry calls at their call sites: the
-- main script, net.lua and the chat commands all reach for these, and renaming
-- them would be churn for no gain.
custom_buffs.ensure_network_id = registry.ensure_network_id
custom_buffs.network_id_map = registry.network_id_map
custom_buffs.register_network_lookup = registry.register_network_lookup

-- Every pickable buff the registry knows about -- this mod's, and every addon's.
-- The report and the chat command both want the whole picture.
local _pool_names = registry.pool_names

local registered = false

custom_buffs.register = function ()
	if registered then
		return
	end

	registered = true

	-- No card text to attach: the one entry left here is not pickable. A pack
	-- that ships cards carries its own translations -- see CwahBuffs.
	registry.register_buffs(mod, CATALOGUE, {
		prefix = "cwah_",
		category = CATEGORY,
		category_label = "Custom",
	})
end

-- How often the custom category comes up relative to the shipped ones.
--
-- _pop_legendary_buff_from_players_pool weights categories per wave and falls
-- back to 1 for anything it does not recognise. Applied per mission because the
-- setting can change between them; the registry writes every registered category
-- in the same pass, so an addon's declared weight lands here too.
custom_buffs.apply_weight = function ()
	local weight = mod:get("custom_buff_weight") or 1

	registry.apply_weights(function (id)
		if id == CATEGORY then
			return weight
		end
	end)

	mod:debug_log("custom buff category weight set to %s", tostring(weight))
end

-- ---------------------------------------------------------------------------
-- Prerequisite unlocking
-- ---------------------------------------------------------------------------
--
-- The Mortis system has no notion of one buff unlocking another. The legendary
-- pool is built once per player at spawn (horde_mission_buffs_manager.lua:337)
-- and buffs are popped out of it as they are handed over, so a card that should
-- only appear after another has been taken has to be held out of that initial
-- build and put in later.
--
-- Done by polling rather than by hooking the grant. There is no single grant
-- path -- a card pick, a restore after a mission hop and /cw_grant all arrive
-- differently -- and hooking give_buff_to_player would spend this mod's one
-- allowed hook on that method for a check that costs nothing once a second.
--
-- Host only: these are the server's pools. A client editing them would be
-- writing to data the server will overwrite.

local UNLOCK_INTERVAL = 1
local unlock_accum = 0

local function _owned_prerequisites(player)
	local names = registry.prerequisite_names()
	local owned = {}

	if not next(names) then
		return owned
	end

	local player_unit = player and player.player_unit

	if not player_unit or not Unit.alive(player_unit) then
		return owned
	end

	local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")

	-- A remote player's extension is a PlayerHuskBuffExtension, which is NOT a
	-- BuffExtensionBase -- it implements part of the interface and this method
	-- is simply absent. Calling it is a hard error, not a nil result.
	if not buff_extension or type(buff_extension.has_buff_using_buff_template) ~= "function" then
		return owned
	end

	for name in pairs(names) do
		if buff_extension:has_buff_using_buff_template(name) then
			owned[name] = true
		end
	end

	return owned
end

-- is_enabled is buff_pool's, passed in rather than imported: this file must not
-- io_dofile buff_pool (that would be a second copy of it, with its own catalogue
-- cache), and the main script already holds both.
--
-- Without it, a gated card the player switched off in the Rollable Buffs menu
-- would be quietly put back into the pool the moment its prerequisite landed --
-- the toggle only filters the pool as it is BUILT, and this runs afterwards.
custom_buffs.update_unlocks = function (dt, is_enabled)
	if not mod.manager or not mod.is_host() then
		return
	end

	-- Most installs have no gated buffs at all; this is the whole cost for them.
	if not registry.has_any_prerequisites() then
		return
	end

	unlock_accum = unlock_accum + dt

	if unlock_accum < UNLOCK_INTERVAL then
		return
	end

	unlock_accum = 0

	local handler = mod.manager._mission_buffs_handler
	local persistent = handler and handler._persistent_data

	if not persistent then
		return
	end

	for _, player in pairs(Managers.player:human_players()) do
		local ok, pools = pcall(persistent.get_legendary_buffs_available_for_player, persistent, player)

		if ok and type(pools) == "table" then
			local in_pool = {}

			for _, list in pairs(pools) do
				if type(list) == "table" then
					for _, name in ipairs(list) do
						in_pool[name] = true
					end
				end
			end

			for _, fresh in ipairs(registry.newly_unlocked(_owned_prerequisites(player), in_pool)) do
				local list = pools[fresh.category]

				-- Switched off in the Rollable Buffs menu is not an error, and
				-- not worth a log line every second either.
				local switched_off = is_enabled and not is_enabled(fresh.name)

				if switched_off then -- luacheck: ignore
					-- nothing to do
				elseif list then
					list[#list + 1] = fresh.name

					mod:info("unlocked '%s' - its prerequisite is held", fresh.name)
				else
					-- The category bucket is built by
					-- init_legendary_buffs_pool_for_player from the registered
					-- categories, so a missing one means the category was
					-- registered after the pool was built -- worth saying rather
					-- than dropping the card silently.
					mod:error("cannot unlock '%s': no pool bucket for category '%s'",
						fresh.name, tostring(fresh.category))
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------
--
-- Answers "is this buff actually doing anything", which the HUD cannot.
-- Attachment and effect are separate questions and both get reported: a buff can
-- be listed on the player and still do nothing if its stat key is wrong or its
-- check_proc_func never passes.
--
-- Written to the log passively behind the debug_logging setting, rather than
-- only when someone runs /cw_verify. Two reasons, and the second is the real
-- one:
--
-- 1. A line per buff stopped scaling once there were nine of them.
-- 2. The interesting failures are shapes over time, not single samples. A proc
--    count that climbs while the player stands still, or a guard that stops
--    rejecting once a fight gets dense, is obvious in a series of snapshots and
--    invisible in one -- and the one snapshot you get on demand is never taken
--    at the moment things went wrong. A player reporting a problem sends the log
--    anyway, so this costs them nothing to produce.
--
-- Everything below reads the REGISTRY, not a list of this mod's own buffs, so an
-- addon's cards and counters are reported exactly like ours with no work on its
-- part beyond registering.
local function _report_lines()
	local player = Managers.player and Managers.player:local_player_safe(1)
	local player_unit = player and player.player_unit

	if not player_unit or not Unit.alive(player_unit) then
		return { "no local player unit - are you in a mission?" }
	end

	local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")

	if not buff_extension then
		return { "no buff extension on the player unit" }
	end

	local lines = {}

	-- Attached, on one line. Walks the live buff instances, so it reflects what
	-- the buff system believes rather than what the mod asked for.
	local held = {}

	for _, buff_name in ipairs(_pool_names()) do
		if buff_extension:has_buff_using_buff_template(buff_name) then
			held[#held + 1] = buff_name
		end
	end

	lines[#lines + 1] = "held: " .. (#held > 0 and table.concat(held, ", ") or "none")

	-- The multiplier the damage pipeline will actually read. Base is 1, so 1.15
	-- means a damage stat buff landed. Every source stacks into the same number,
	-- so read it as "at least ours", not "only ours".
	local player_stat_buffs = buff_extension:stat_buffs()
	local damage_multiplier = player_stat_buffs and player_stat_buffs[stat_buffs.damage]

	lines[#lines + 1] = string.format("damage stat_buff multiplier: %s (1.0 = no bonus)",
		damage_multiplier and string.format("%.3f", damage_multiplier) or "unreadable")

	-- Live readings contributed by registrants: state that cannot be a counter
	-- because it is a level rather than a tally, like a ramp's current stacks.
	for _, reading in ipairs(registry.readings()) do
		local template = BuffTemplates[reading.buff]
		local stacks = buff_extension:current_stacks(reading.buff)

		lines[#lines + 1] = string.format("%s: %d/%d stacks (+%.0f%% %s)",
			reading.label, stacks, template and template.max_stacks or 0,
			stacks * (reading.step or 0) * 100, tostring(reading.of))
	end

	-- Counters are reported generically -- whatever the proc funcs happen to have
	-- bumped, sorted, zeroes omitted. Deliberately NOT a hand-maintained table of
	-- pretty labels: that is exactly the thing that goes stale the next time a
	-- buff is added, and the raw keys are already readable. What a counter means
	-- belongs in a comment next to the code that bumps it.
	local keys = {}

	for key, value in pairs(proc_counts) do
		if value and value ~= 0 then
			keys[#keys + 1] = key
		end
	end

	table.sort(keys)

	if #keys == 0 then
		lines[#lines + 1] = "no custom buff has fired yet"
	else
		for _, key in ipairs(keys) do
			lines[#lines + 1] = string.format("  %s: %d", key, proc_counts[key])
		end
	end

	return lines
end

-- Report lines are echoed to chat, and mod:echo runs its message through
-- string.format -- so any literal % we produce (the ramp percentages) has to be
-- doubled or the echo crashes instead of printing.
--
-- Only the chat path needs this. mod:debug_log escapes whatever it is handed on
-- its way out, so the passive path below must pass the lines RAW -- escaping
-- them twice would print a literal %%.
local function _echo_safe(lines)
	for i = 1, #lines do
		lines[i] = (lines[i]:gsub("%%", "%%%%"))
	end

	return lines
end

custom_buffs.report = function ()
	return _echo_safe(_report_lines())
end

local REPORT_INTERVAL = 10
local report_accum = 0
local last_snapshot = nil

-- Called every frame; does almost nothing on almost all of them.
--
-- Only logs when the snapshot has actually changed, so a quiet stretch does not
-- fill the log with the same block over and over -- which matters because the
-- log is the artefact a player sends back, and a wall of identical lines makes
-- the moment something changed harder to find rather than easier.
custom_buffs.update = function (dt)
	if not mod.manager then
		return
	end

	report_accum = report_accum + dt

	if report_accum < REPORT_INTERVAL then
		return
	end

	report_accum = 0

	-- Checked after the interval, not before: building a report walks the buff
	-- extension, and with logging off there is nobody to read the result.
	if not mod:get("debug_logging") then
		return
	end

	local lines = _report_lines()
	local snapshot = table.concat(lines, "\n")

	if snapshot == last_snapshot then
		return
	end

	last_snapshot = snapshot

	mod:debug_log("--- custom buffs ---")

	for i = 1, #lines do
		mod:debug_log(lines[i])
	end
end

custom_buffs.category = CATEGORY

-- Per mission, so a count answers "did it fire in this one" rather than
-- accumulating across a whole run and looking healthy on stale numbers.
custom_buffs.reset_counters = function ()
	registry.reset_counters()

	-- So the first report of a new mission is always written, rather than being
	-- suppressed for matching the last one of the previous mission.
	last_snapshot = nil
	report_accum = 0
end

custom_buffs.buff_names = function ()
	return _pool_names()
end

return custom_buffs
