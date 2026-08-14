local mod = get_mod("ChaosWastesAtHome")

local BuffSettings = require("scripts/settings/buff/buff_settings")

local buff_categories = BuffSettings.buff_categories

-- Multishot: ranged weapons fire five shots in a horizontal fan instead of one.
--
-- This is the one buff in the mod that is not really a buff. The buff system has
-- no concept of "how many projectiles does this weapon produce" -- there is no
-- stat buff for it, only minion_num_shots_modifier for enemies -- so the buff
-- template below carries nothing at all and exists purely to be pickable and to
-- be asked about. The behaviour is two weapon-action hooks, and the buff is the
-- switch they read. Same shape as Contagion.

local multishot = {}

multishot.BUFF_NAME = "cwah_multishot"

-- Four extra shots either side of the aimed one, five degrees apart.
local EXTRA_SHOTS = 4
local FAN_STEP_DEGREES = 5

multishot.DESCRIPTION = "Ranged weapons fire " .. (EXTRA_SHOTS + 1)
	.. " shots at once, fanned out horizontally, for the same ammunition."

-- Precomputed yaw offsets for the extra shots: the aimed shot is fired
-- separately, so this is -2, -1, +1, +2 steps for the default of four.
local FAN_OFFSETS = {}

do
	local half = math.floor(EXTRA_SHOTS / 2)
	local step = FAN_STEP_DEGREES * math.pi / 180

	for i = -half, half do
		if i ~= 0 then
			FAN_OFFSETS[#FAN_OFFSETS + 1] = i * step
		end
	end
end

-- Guards our own recursive calls: every extra shot re-enters the hooked method.
local firing = false

local proc_counts = mod._custom_buff_procs or {}

mod._custom_buff_procs = proc_counts

-- Rotate around the LOCAL up axis by post-multiplying, which is how the game
-- builds its own yaw spread (action_spawn_projectile.lua:568). Fanning around
-- world up instead would make the spread wrong whenever the player is not
-- looking at the horizon.
local function _fan(rotation, angle)
	return Quaternion.multiply(rotation, Quaternion.axis_angle(Vector3.up(), angle))
end

-- These hooks are global -- they fire for every shot by every player unit,
-- including bots -- so the buff has to be checked on the unit doing the
-- shooting, not on the local player.
local function _wants_multishot(action)
	-- Is one of OUR missions running. Hooks outlive missions -- finishing a run
	-- does not unhook anything -- so without this these keep inspecting every
	-- shot fired by anyone in whatever the player does next, including hosted
	-- multiplayer. Nobody would have the buff, but the work is wrong and the
	-- inspection itself is not free of risk (see below).
	if not mod.manager then
		return false
	end

	local player_unit = action._player_unit

	if not player_unit or not HEALTH_ALIVE[player_unit] then
		return false
	end

	local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")

	-- Duck-typed rather than assumed. Not every buff extension is a
	-- BuffExtensionBase: PlayerHuskBuffExtension is its own class and
	-- implements only part of the interface, so has_buff_using_buff_template is
	-- nil on remote players' units. The Contagion hook learned that the noisy
	-- way. Identity against the local player is the tighter test used there,
	-- but this hook legitimately fires for bot units too, so the method check
	-- is the right shape here.
	if not buff_extension or not buff_extension.has_buff_using_buff_template then
		return false
	end

	return buff_extension:has_buff_using_buff_template(multishot.BUFF_NAME)
end

local function _count(jumps)
	proc_counts.cwah_multishot = (proc_counts.cwah_multishot or 0) + 1
	proc_counts.cwah_multishot_shots = (proc_counts.cwah_multishot_shots or 0) + jumps
end

-- Hooked by class NAME, not by a table read out of CLASS.
--
-- Weapon action classes are loaded lazily, so at mod load neither of these
-- exists yet. DMF handles that itself: it hooks the global `class` function
-- (dmf/modules/core/hooks.lua:549) and re-applies any delayed hook when the
-- class is finally declared. Reaching into CLASS here would need a retry loop
-- and would still race the first shot of the session.
--
-- mod:hook rather than mod:hook_safe -- we need `func` in order to call it more
-- than once, which is the entire trick. Neither method is hooked anywhere else
-- in this mod, so the one-hook-per-mod-per-method rule is not in play.
--
-- Three classes are hooked, because "a ranged weapon fires a shot" is three
-- unrelated mechanisms:
--
--   ActionShootHitScan     lasguns, autoguns, stubbers, bolters
--   ActionShootProjectile  plasma, knives thrown from a weapon slot
--   ActionSpawnProjectile  force staffs (see further down)
--
-- ActionShootPellets is deliberately NOT hooked. It shares the signature but
-- fires `pellets_per_frame` pellets per call and accumulates num_pellets_fired
-- in a networked component until it reaches num_pellets
-- (action_shoot_pellets.lua:162), so calling it five times would push that
-- accumulator past the total and corrupt the shot rather than multiply it.
-- Shotguns already fire a spread anyway.

-- Hitscan: lasguns, autoguns, stubbers, bolters. `_shoot` honours the rotation
-- it is handed, so this is just five calls with five rotations.
--
-- The aimed shot is fired LAST on purpose. `self._shot_result` is cleared by the
-- caller and read afterwards for hit statistics (action_shoot.lua:311), so
-- whichever call runs last is the one that gets reported -- and that should be
-- the shot the player actually aimed.
mod:hook("ActionShootHitScan", "_shoot", function (func, self, position, rotation, power_level, charge_level, t, fire_config)
	if firing or not _wants_multishot(self) then
		return func(self, position, rotation, power_level, charge_level, t, fire_config)
	end

	firing = true

	local ok, err = pcall(function ()
		for i = 1, #FAN_OFFSETS do
			func(self, position, _fan(rotation, FAN_OFFSETS[i]), power_level, charge_level, t, fire_config)
		end
	end)

	firing = false

	if not ok then
		mod:error("multishot could not fan a hitscan shot: %s", tostring(err))
	else
		_count(#FAN_OFFSETS)
	end

	return func(self, position, rotation, power_level, charge_level, t, fire_config)
end)

-- Projectiles: plasma, force staff projectiles, throwing knives.
--
-- ActionShootProjectile._shoot IGNORES the rotation it is passed and re-reads
-- self._action_component.shooting_rotation instead
-- (action_shoot_projectile.lua:51), so handing it a fanned rotation does
-- nothing. The component field has to be written around each call.
--
-- That is less alarming than it sounds: shooting_rotation is a plain
-- "Quaternion" component entry (player_unit_data_component_config.lua:869) that
-- the game itself assigns directly at action_shoot.lua:449. What matters is that
-- it is restored on every path, including the failure one -- leaving it fanned
-- would send the player's NEXT shot off at an angle, with nothing on screen to
-- explain why.
mod:hook("ActionShootProjectile", "_shoot", function (func, self, position, rotation, power_level, charge_level, t, fire_config)
	if firing or not _wants_multishot(self) then
		return func(self, position, rotation, power_level, charge_level, t, fire_config)
	end

	local action_component = self._action_component

	if not action_component then
		return func(self, position, rotation, power_level, charge_level, t, fire_config)
	end

	local aimed_rotation = action_component.shooting_rotation

	firing = true

	local ok, err = pcall(function ()
		for i = 1, #FAN_OFFSETS do
			local fanned = _fan(aimed_rotation, FAN_OFFSETS[i])

			action_component.shooting_rotation = fanned

			func(self, position, fanned, power_level, charge_level, t, fire_config)
		end
	end)

	action_component.shooting_rotation = aimed_rotation
	firing = false

	if not ok then
		mod:error("multishot could not fan a projectile shot: %s", tostring(err))
	else
		_count(#FAN_OFFSETS)
	end

	return func(self, position, rotation, power_level, charge_level, t, fire_config)
end)

-- Force staffs. A third class and a third mechanism, which is why hooking the
-- two above did nothing for them: staff primaries are `kind = "spawn_projectile"`
-- (forcestaff_p1_m1.lua:281), which is ActionSpawnProjectile -- not a subclass of
-- ActionShoot and with no `_shoot` method at all.
--
-- It works completely differently. Projectiles are spawned up front in `start`
-- into four parallel arrays (action_spawn_projectile.lua:136) and launched later
-- by `fixed_update` as each one's time offset elapses. So "fire more" here means
-- appending to those arrays, not calling something repeatedly.
--
-- That the game already supports multiple projectiles is what makes this
-- tractable: `num_projectiles` and the `critical_strike_second_projectile`
-- keyword both feed the same arrays, and `finish` already relinquishes and
-- deletes any entry that never fired (line 286). Appending to the same arrays
-- means our extras inherit that cleanup rather than leaking network units.
--
-- Fire offsets are 0 rather than the game's staggered `(ii - 1) * 0.1`, so the
-- volley leaves together instead of trickling out.
--
-- Grenades and combat abilities use this class too -- throwing knives are
-- spawn_projectile as well -- and are excluded on `action_settings.ability_type`,
-- which weapons do not set. Five krak grenades per throw is not what this buff
-- is for.
mod:hook_safe("ActionSpawnProjectile", "start", function (self, action_settings, t, ...)
	self._cwah_fan_angles = nil

	-- Mirrors the original's own guard: the spawn arrays only exist server-side.
	if not self._is_server then
		return
	end

	if not action_settings or action_settings.ability_type then
		return
	end

	if not _wants_multishot(self) then
		return
	end

	local units = self._projectile_units

	if not units or #units == 0 then
		return
	end

	local is_critical_strike = self._critical_strike_component and self._critical_strike_component.is_active
	local angles = {}

	local ok, err = pcall(function ()
		for i = 1, #FAN_OFFSETS do
			local projectile_unit = self:_spawn_projectile_unit(is_critical_strike)
			local locomotion = ScriptUnit.extension(projectile_unit, "locomotion_system")
			local index = #self._projectile_units + 1

			self._projectiles_fire_offsets[index] = 0
			self._projectiles_fired[index] = false
			self._projectile_units[index] = projectile_unit
			self._projectile_locomotion_extensions[index] = locomotion

			angles[projectile_unit] = FAN_OFFSETS[i]
		end
	end)

	if ok then
		self._cwah_fan_angles = angles

		_count(#FAN_OFFSETS)
	else
		mod:error("multishot could not spawn extra staff projectiles: %s", tostring(err))
	end
end)

-- Aiming the extras.
--
-- Unlike the other two paths there is no rotation to hand in: _fire_projectile
-- derives its direction entirely from self._first_person_component.rotation plus
-- template-driven random offsets (action_spawn_projectile.lua:548), with no
-- per-projectile input anywhere.
--
-- Writing that component is NOT the answer, however tempting the symmetry with
-- shooting_rotation is. `first_person` is a read-only component and the engine
-- hard-errors on the write:
--
--   player_unit_data_extension.lua:501: Trying to write to "rotation" in read
--   only component "first_person"
--
-- Which is the right call anyway -- that field is the player's actual view, read
-- by the camera and half the animation system, and borrowing it for a frame was
-- always going to be the most invasive thing in this file.
--
-- Instead we let the direction be computed normally and rotate it at the point
-- it stops being a component read and becomes a plain argument:
-- ProjectileUnitLocomotionExtension._switch_to_manual_state_helper receives
-- (position, rotation, direction, ...) as values. Rotating a direction vector by
-- a yaw is the game's own idiom for fanning projectiles
-- (action_throw_grenade.lua:145).
--
-- The angle is handed over in a module local rather than as an argument because
-- it has to cross a call we do not control. That is sound here and only here:
-- _fire_projectile calls switch_to_* synchronously, once, with nothing
-- interleaved, and the local is cleared on every path out.
local pending_fan_angle = nil

local function _fan_direction(direction, angle)
	return Quaternion.rotate(Quaternion.axis_angle(Vector3.up(), angle), direction)
end

-- Only our own extras carry an angle. The aimed projectile, and every projectile
-- of every action we did not add to, goes through untouched -- which is what
-- keeps the shot you aimed going where you aimed it.
mod:hook("ActionSpawnProjectile", "_fire_projectile", function (func, self, t, projectile_unit, time_difference_from_paying, projectile_locomotion_extension, offset)
	local angles = self._cwah_fan_angles
	local angle = angles and angles[projectile_unit]

	if not angle then
		return func(self, t, projectile_unit, time_difference_from_paying, projectile_locomotion_extension, offset)
	end

	pending_fan_angle = angle

	local ok, err = pcall(func, self, t, projectile_unit, time_difference_from_paying,
		projectile_locomotion_extension, offset)

	pending_fan_angle = nil

	if not ok then
		mod:error("multishot could not fan a staff projectile: %s", tostring(err))
	end
end)

-- Both switch_to_manual_physics and switch_to_true_flight funnel through this
-- helper (projectile_unit_locomotion_extension.lua:329-337), so one hook covers
-- the two launch modes staffs actually use. The projectile's visual rotation is
-- turned with the direction so the model does not fly sideways.
mod:hook("ProjectileUnitLocomotionExtension", "_switch_to_manual_state_helper", function (func, self, position, rotation, direction, speed, angular_velocity, target_unit, target_position)
	if not pending_fan_angle then
		return func(self, position, rotation, direction, speed, angular_velocity, target_unit, target_position)
	end

	-- A fanned shot is no longer aimed at the thing the aimed shot was aimed at,
	-- so the homing target is dropped -- true_flight would otherwise curve every
	-- projectile back onto the same enemy and undo the spread entirely.
	return func(self, position, Quaternion.multiply(Quaternion.axis_angle(Vector3.up(), pending_fan_angle), rotation),
		_fan_direction(direction, pending_fan_angle), speed, angular_velocity, nil, nil)
end)

-- The third launch mode. Takes a velocity rather than a direction and speed, so
-- the whole vector is turned; magnitude is preserved by rotation.
mod:hook("ProjectileUnitLocomotionExtension", "switch_to_engine_physics", function (func, self, position, rotation, velocity, angular_momentum)
	if not pending_fan_angle then
		return func(self, position, rotation, velocity, angular_momentum)
	end

	return func(self, position, Quaternion.multiply(Quaternion.axis_angle(Vector3.up(), pending_fan_angle), rotation),
		_fan_direction(velocity, pending_fan_angle), angular_momentum)
end)

mod:info("multishot hooks registered")

-- Carries nothing. See the note at the top of the file.
multishot.template = function ()
	return {
		class_name = "buff",
		max_stacks = 1,
		max_stacks_cap = 1,
		predicted = false,
		buff_category = buff_categories.hordes_buff,
	}
end

return multishot
