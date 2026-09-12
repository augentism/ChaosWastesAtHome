-- Adapted from fork/korean-modpack validation/test_multishot.lua. Execute the
-- current CwahBuffs hooks; the fork's chance rolls and upgraded tiers do not apply.
local harness = ...

local function fixture()
	local f = { hooks = {}, counts = {}, errors = {}, owned = true, unit = {} }
	local mod = {}
	function mod:hook(class, method, fn) f.hooks[class .. "." .. method] = fn end
	mod.hook_safe = mod.hook
	function mod:info() end
	function mod:error(...) f.errors[#f.errors + 1] = { ... } end
	f.core = { manager = {}, buff_proc_counters = function () return f.counts end }
	f.extension = { has_buff_using_buff_template = function (_, id)
		return f.owned and id == "cwah_multishot"
	end }
	f.env = setmetatable({
		get_mod = function (name) return name == "CwahBuffs" and mod or f.core end,
		require = function () return { buff_categories = { hordes_buff = "hordes_buff" } } end,
		HEALTH_ALIVE = { [f.unit] = true },
		ScriptUnit = {
			has_extension = function () return f.extension end,
			extension = function (unit) return unit.locomotion end,
		},
		-- Scalar yaw model: checks argument flow, not engine quaternion math.
		Quaternion = {
			axis_angle = function (_, angle) return angle end,
			multiply = function (x, y) return x + y end,
			rotate = function (angle, direction) return direction + angle end,
		},
		Vector3 = { up = function () return 0 end },
	}, { __index = _G })
	local chunk = assert(loadfile(harness.source_path("CwahBuffs/scripts/mods/CwahBuffs/multishot.lua")))
	f.module = setfenv(chunk, f.env)()
	f.action = { _player_unit = f.unit, _action_component = { shooting_rotation = 1 } }
	return f
end

local function near(a, got, want)
	a.truthy(math.abs(got - want) < 1e-10, "fan angle")
end

local cases = {}
for _, class in ipairs({ "ActionShootHitScan", "ActionShootProjectile" }) do
	cases[#cases + 1] = { class .. " fires five shots, aimed last, preserving arguments", function (a)
		local f, rotations = fixture(), {}
		local result = f.hooks[class .. "._shoot"](function (self, pos, rotation, power, charge, t, config)
			a.eq(self, f.action); a.eq(pos, "position"); a.eq(power, 7)
			a.eq(charge, 0.5); a.eq(t, 10); a.eq(config, "config")
			rotations[#rotations + 1] = rotation
			if class == "ActionShootProjectile" then a.eq(self._action_component.shooting_rotation, rotation) end
			return "aimed result"
		end, f.action, "position", 1, 7, 0.5, 10, "config")
		a.eq(result, "aimed result"); a.count(rotations, 5)
		for i, degrees in ipairs({ -10, -5, 5, 10, 0 }) do near(a, rotations[i], 1 + degrees * math.pi / 180) end
		a.eq(f.action._action_component.shooting_rotation, 1)
		a.eq(f.counts.cwah_multishot, 1); a.eq(f.counts.cwah_multishot_shots, 4)
	end }
	cases[#cases + 1] = { class .. " guards inactive, unowned, dead and unsupported units", function (a)
		for _, change in ipairs({
			function (f) f.core.manager = nil end,
			function (f) f.owned = false end,
			function (f) f.env.HEALTH_ALIVE[f.unit] = false end,
			function (f) f.action._player_unit = nil end,
			function (f) f.extension = nil end,
			function (f) f.extension = {} end,
		}) do
			local f, calls = fixture(), 0
			change(f)
			f.hooks[class .. "._shoot"](function () calls = calls + 1 end, f.action, 0, 1)
			a.eq(calls, 1); a.nil_(f.counts.cwah_multishot)
		end
	end }
	cases[#cases + 1] = { class .. " error restores aim and permits the next volley", function (a)
		local f, calls = fixture(), 0
		local hook = f.hooks[class .. "._shoot"]
		hook(function (_, _, rotation)
			calls = calls + 1
			if calls == 1 then error("injected extra shot failure") end
			a.eq(rotation, 1)
		end, f.action, 0, 1)
		a.eq(calls, 2); a.count(f.errors, 1); a.nil_(f.counts.cwah_multishot)
		a.eq(f.action._action_component.shooting_rotation, 1)
		calls = 0
		hook(function () calls = calls + 1 end, f.action, 0, 1)
		a.eq(calls, 5); a.eq(f.counts.cwah_multishot, 1)
	end }
end

cases[#cases + 1] = { "recursive shots do not generate another fan", function (a)
	local f, calls = fixture(), 0
	local hook = f.hooks["ActionShootHitScan._shoot"]
	hook(function ()
		calls = calls + 1
		if calls == 1 then hook(function () calls = calls + 1 end, f.action, 0, 1) end
	end, f.action, 0, 1)
	a.eq(calls, 6); a.eq(f.counts.cwah_multishot, 1)
end }

local function staff(f)
	local action = f.action
	action._is_server = true
	action._critical_strike_component = { is_active = true }
	action._projectile_units = { {} }
	action._projectiles_fire_offsets = { 0 }
	action._projectiles_fired = { false }
	action._projectile_locomotion_extensions = { {} }
	function action:_spawn_projectile_unit(critical)
		return { critical = critical, locomotion = {} }
	end
	return action
end

cases[#cases + 1] = { "staff appends four simultaneous projectiles and preserves critical state", function (a)
	local f = fixture()
	local action = staff(f)
	f.hooks["ActionSpawnProjectile.start"](action, {}, 0)
	for _, key in ipairs({ "_projectile_units", "_projectiles_fire_offsets", "_projectiles_fired", "_projectile_locomotion_extensions" }) do a.count(action[key], 5) end
	a.nil_(action._cwah_fan_angles[action._projectile_units[1]])
	for i, degrees in ipairs({ -10, -5, 5, 10 }) do
		local unit = action._projectile_units[i + 1]
		a.truthy(unit.critical); a.eq(action._projectiles_fire_offsets[i + 1], 0)
		a.eq(action._projectiles_fired[i + 1], false)
		a.eq(action._projectile_locomotion_extensions[i + 1], unit.locomotion)
		near(a, action._cwah_fan_angles[unit], degrees * math.pi / 180)
	end
	a.eq(f.counts.cwah_multishot_shots, 4)
end }

cases[#cases + 1] = { "staff guards client, ability and inactive actions and clears stale angles", function (a)
	for _, mode in ipairs({ "client", "ability", "inactive", "unowned", "empty" }) do
		local f = fixture()
		local action, settings = staff(f), {}
		action._cwah_fan_angles = { stale = true }
		if mode == "client" then action._is_server = false end
		if mode == "ability" then settings.ability_type = "grenade" end
		if mode == "inactive" then f.core.manager = nil end
		if mode == "unowned" then f.owned = false end
		if mode == "empty" then action._projectile_units = {} end
		local count = #action._projectile_units
		f.hooks["ActionSpawnProjectile.start"](action, settings, 0)
		a.count(action._projectile_units, count); a.nil_(action._cwah_fan_angles)
		a.nil_(f.counts.cwah_multishot)
	end
end }

cases[#cases + 1] = { "staff launch rotates extras, removes homing and clears angle after errors", function (a)
	local f = fixture()
	local action = staff(f)
	f.hooks["ActionSpawnProjectile.start"](action, {}, 0)
	local fire = f.hooks["ActionSpawnProjectile._fire_projectile"]
	local manual = f.hooks["ProjectileUnitLocomotionExtension._switch_to_manual_state_helper"]
	local physics = f.hooks["ProjectileUnitLocomotionExtension.switch_to_engine_physics"]
	local function launch(angle)
		manual(function (_, pos, rot, dir, speed, angular, target, target_pos)
			a.eq(pos, "pos"); near(a, rot, 1 + angle); near(a, dir, 2 + angle)
			a.eq(speed, 3); a.eq(angular, 4)
			a.eq(target, angle == 0 and "target" or nil)
			a.eq(target_pos, angle == 0 and "target_pos" or nil)
		end, {}, "pos", 1, 2, 3, 4, "target", "target_pos")
		physics(function (_, pos, rot, velocity, momentum)
			a.eq(pos, "pos"); near(a, rot, 1 + angle); near(a, velocity, 2 + angle); a.eq(momentum, 4)
		end, {}, "pos", 1, 2, 4)
	end
	for _, unit in ipairs(action._projectile_units) do
		fire(function () launch(action._cwah_fan_angles[unit] or 0) end, action, 0, unit)
	end
	-- Assertions in a production pcall are reported through mod:error.
	a.count(f.errors, 0)
	fire(function () error("injected launch failure") end, action, 0, action._projectile_units[2])
	a.count(f.errors, 1)
	launch(0)
end }

return cases
