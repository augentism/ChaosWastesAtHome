local mod = get_mod("ChaosWastesAtHome")

local MatchmakingConstants = require("scripts/settings/network/matchmaking_constants")

local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")

-- Required, not read off _G. MatchmakingConstants is a module and has never been
-- a global -- reading it from _G silently gave nil, which made every "is this
-- one of our missions" test answer false. The escape button still appeared
-- (SoloPlay patches the same entry) so the only visible symptom was the strike
-- team being left anyway.
local HOST_TYPES = MatchmakingConstants.HOST_TYPES

-- Puts "Leave Mission" back in the escape menu.
--
-- A mission started with boot_singleplayer_session has NO WAY OUT through the
-- escape menu, because both exits are hidden for different reasons
-- (system_view_content_list.lua):
--
--   "Leave Mission"       validation_is_in_standard_mission returns true only
--                         for HOST_TYPES.mission_server. We are singleplay.
--   "Exit to Main Menu"   only shown in prologue / hub / training_grounds /
--                         shooting_range. We are coop_complete_objective.
--
-- SoloPlay patches this today, which is why runs have been escapable so far.
-- Launching our own sessions means owning it.

local escape = {}

local CONTENT_LIST_PATH = "scripts/ui/views/system_view/system_view_content_list"
local LEAVE_MISSION_TEXT = "loc_leave_mission_display_name"

local patched = false

local function _in_our_mission()
	local session = Managers.multiplayer_session

	if not session then
		return false
	end

	local ok, host_type = pcall(session.host_type, session)

	if not ok or not host_type then
		return false
	end

	local singleplay = HOST_TYPES and HOST_TYPES.singleplay

	-- The literal is a fallback, not the primary test: the enum values are
	-- strings, so a future rename of the constant still leaves this working
	-- rather than silently disabling the whole file again.
	if host_type ~= singleplay and host_type ~= "singleplay" then
		return false
	end

	return run.is_launched()
end

escape.install = function ()
	if patched then
		return
	end

	patched = true

	mod:hook_require(CONTENT_LIST_PATH, function (content_list)
		if type(content_list) ~= "table" then
			return
		end

		-- The module does not return one list. It returns a table keyed by game
		-- state -- { StateMainMenu = ..., default = ... } -- each holding its own
		-- array of entries, so the entries have to be reached one level down.
		local patched_one = false

		-- "default" first, explicitly. The in-mission entries live there, and
		-- pairs() order is not defined -- leaving it to chance would mean which
		-- entry gets patched could differ between launches, which is how you get
		-- a bug that reproduces for one player and not another.
		local ordered = { "default" }

		for list_name in pairs(content_list) do
			if list_name ~= "default" then
				ordered[#ordered + 1] = list_name
			end
		end

		for _, list_name in ipairs(ordered) do
			local entries = content_list[list_name]

			if type(entries) == "table" then
				for _, entry in ipairs(entries) do
					-- Only the FIRST match, across all lists. There are two
					-- entries with this text in the default list -- the
					-- standard-mission one and the havoc one -- and patching
					-- both puts two identical "Leave Mission" buttons in the
					-- menu.
					if not patched_one and type(entry) == "table"
						and entry.text == LEAVE_MISSION_TEXT and entry.validation_function then
						local original = entry.validation_function

						-- Wrapped, not replaced: the vanilla rules still decide
						-- for every session that is not one of ours, so a normal
						-- mission keeps behaving exactly as it does now.
						entry.validation_function = function (...)
							if _in_our_mission() then
								return true
							end

							return original(...)
						end

						patched_one = true

						mod:info("escape menu: leave mission enabled for solo runs (list '%s')",
							tostring(list_name))
					end
				end
			end
		end

		if not patched_one then
			mod:error("escape menu: no '%s' entry found - players will not be able to leave a run",
				LEAVE_MISSION_TEXT)
		end
	end)
end

-- Whether a "leave_mission" should be downgraded to keep the strike team.
--
-- The two reasons differ in exactly one place, mechanism_left_session.lua:23:
-- "leave_mission" calls _leave_party(), "leave_mission_stay_in_party" does
-- nothing. The escape menu already carries its own "Leave Party" button, so
-- leaving a mission should not silently do both.
escape.should_keep_party = function (reason)
	return reason == "leave_mission" and _in_our_mission()
end

escape.KEEP_PARTY_REASON = "leave_mission_stay_in_party"

return escape
