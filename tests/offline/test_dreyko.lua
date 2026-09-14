local h = ...
local function fixture()
	local f = { active = 0, enabled = true, chance = 100, grants = 0 }
	local hooks = {}
	local manager = { num_active_events = function () if f.read_error then error("transient") end; return f.active end }
	local mod = { manager = {}, has_authority = function () return true end,
		get = function (_, k) if k == "events_enabled" then return f.enabled elseif k == "events_chance" then return f.chance elseif k == "events_grant" then return "family" end end,
		info = function () end, debug_log = function () end,
		hook = function (_, _, method, fn) hooks[method] = fn end,
		hook_safe = function (_, _, method, fn) hooks[method] = fn end }
	local env = setmetatable({ get_mod = function () return mod end, require = function () return {} end,
		Managers = { state = { terror_event = manager } } }, { __index = _G })
	f.t = setfenv(assert(loadfile(h.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/triggers.lua")), env)()
	f.t.grant_family = function () f.grants = f.grants + 1; return true end
	f.start = function (name) hooks._start_event(manager, name); f.active = 1; f.t.poll_terror_events() end
	f.finish = function () f.active = 0; f.t.poll_terror_events() end
	return f
end
return {
	{ "Dreyko extraction pays once across all repeat wave names and resets next mission", function (a)
		local f = fixture()
		for _, name in ipairs({ "event_habs_escape", "event_habs_escape_stoppers", "event_habs_escape_guard" }) do f.start(name); f.finish() end
		a.eq(f.grants, 1); a.eq(f.t.stats().event_repeat_blocked, 2)
		f.t.reset(); f.start("event_habs_escape"); f.finish(); a.eq(f.grants, 2)
	end },
	{ "a missed extraction reward cannot be rerolled by changing settings", function (a)
		local f = fixture(); f.chance = 0; f.start("event_habs_escape"); f.finish()
		f.chance = 100; f.start("event_habs_escape_guard"); f.finish(); a.eq(f.grants, 0)
	end },
	{ "missing samples do not fabricate clears and ordinary encounters stay independent", function (a)
		local f = fixture(); f.start("ordinary"); f.read_error = true; f.finish(); a.eq(f.grants, 0)
		f.read_error = false; f.finish(); a.eq(f.grants, 1)
		f.start("another"); f.finish(); a.eq(f.grants, 2)
	end },
}
