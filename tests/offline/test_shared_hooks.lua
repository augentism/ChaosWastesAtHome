local h = ...
return {
	{ "shared hooks combine class names, replacements and protected after callbacks", function (a)
		local target, registrations, errors, callback = {}, 0, 0
		local mod = { hook = function (_, _, _, fn) registrations = registrations + 1; callback = fn end,
			error = function () errors = errors + 1 end }
		local env = setmetatable({ get_mod = function () return mod end, CLASS = { Target = target } }, { __index = _G })
		local chunk = assert(loadfile(h.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/shared_hooks.lua"))
		local hooks = setfenv(chunk, env)()
		local order = {}
		hooks.register("Target", "run", "one", function (next, x) order[#order+1] = "one"; return next(x+1) end)
		hooks.register(target, "run", "two", function (next, x) order[#order+1] = "two"; return next(x*2) end)
		hooks.register(target, "run", "one", function (next, x) order[#order+1] = "replaced"; return next(x+3) end)
		hooks.register_safe(target, "run", "bad", function () error("expected failure") end)
		hooks.register_safe(target, "run", "good", function (x) a.eq(x, 2); order[#order+1] = "after" end)
		local first, middle, last = callback(function (x) return x, nil, "last" end, 2)
		a.eq(first, 7); a.nil_(middle); a.eq(last, "last")
		a.eq(table.concat(order, ","), "two,replaced,after"); a.eq(registrations, 1)
		callback(function () end, 2); a.eq(errors, 1)
		a.eq(setfenv(chunk, env)(), hooks, "singleton")
	end },
}
