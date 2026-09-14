local Attack = require("scripts/utilities/attack/attack")
local AttackSettings = require("scripts/settings/damage/attack_settings")
local DamageProfileTemplates = require("scripts/settings/damage/damage_profile_templates")
local DamageSettings = require("scripts/settings/damage/damage_settings")
local HitZone = require("scripts/utilities/attack/hit_zone")
local ImpactEffect = require("scripts/utilities/attack/impact_effect")

local burst = {}
local profile

-- Ported from songsintransmit's TEST7: pushing a Poxburster must not burst it.
burst.target_allowed = function (target_unit)
	if not target_unit or not HEALTH_ALIVE[target_unit] then return false end
	local data = ScriptUnit.has_extension(target_unit, "unit_data_system")
	local breed = data and data:breed()
	return not breed or breed.name ~= "chaos_poxwalker_bomber"
end

burst.damage_profile = function ()
	if not profile then
		-- Private identity for the host's proc events. Preserve the stock name
		-- for engine/network lookups and share its unmodified damage settings.
		profile = table.clone(DamageProfileTemplates.psyker_smite_kill)
	end
	return profile
end

burst.is_own_damage = function (damage_profile)
	return profile ~= nil and damage_profile == profile
end

-- Mirrors the stock Brain Burst helper's damage, head targeting and impact.
-- Only Flayer uses ranged classification; vanilla secondary bursts stay buff
-- attacks, retaining Infectious Headache's recursion guard.
burst.trigger = function (target_unit, player_unit)
	if not burst.target_allowed(target_unit) then return false end
	local player_pos = Unit.world_position(player_unit, 1)
	local target_pos = Unit.world_position(target_unit, 1)
	local unit_data = ScriptUnit.has_extension(target_unit, "unit_data_system")
	local breed = unit_data and unit_data:breed()
	local attack_direction = Vector3.normalize(target_pos - player_pos)
	local hit_world_position = target_pos
	local hit_zone_name, hit_actor
	if breed then
		local weakspots = breed.hit_zone_weakspot_types
		hit_zone_name = weakspots and (weakspots.head and "head" or next(weakspots)) or HitZone.hit_zone_names.center_mass
		local actors = HitZone.get_actor_names(target_unit, hit_zone_name)
		hit_actor = Unit.actor(target_unit, actors[1])
		hit_world_position = Unit.world_position(target_unit, Actor.node(hit_actor))
	end
	local damage_profile = burst.damage_profile()
	local damage_type = DamageSettings.damage_types.smite
	local damage, result, efficiency = Attack.execute(target_unit, damage_profile,
		"power_level", 500, "charge_level", 1, "hit_zone_name", hit_zone_name,
		"hit_actor", hit_actor, "attacking_unit", player_unit,
		"attack_type", AttackSettings.attack_types.ranged, "damage_type", damage_type)
	ImpactEffect.play(target_unit, hit_actor, damage, damage_type, hit_zone_name,
		result, hit_world_position, nil, attack_direction, player_unit, nil, nil, nil,
		efficiency, damage_profile)
	return true
end

return burst
