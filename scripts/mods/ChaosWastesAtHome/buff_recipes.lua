-- Text -> validated recipes -> native buff templates. No input is executed.
-- Keep this module free of hooks and file I/O so future editors use the same
-- parser/compiler, and malformed input can be tested without a running game.
local recipes = { triggers = {}, effects = {}, max_bytes = 65536, max_buffs = 64 }

local function trigger(id, event, check)
	recipes.triggers[id] = { event = event, check = check }
end

for _, id in ipairs({ "hit", "kill" }) do
	trigger(id, "on_" .. id)
	for _, kind in ipairs({ "melee", "ranged", "weakspot", "elite", "special", "elite_or_special" }) do
		-- There is no stock special-hit predicate; it is handled below.
		if kind ~= "special" or id ~= "hit" then
			trigger(kind .. "_" .. id, "on_" .. id, "on_" .. kind .. "_" .. id)
		end
	end
end
trigger("critical_hit", "on_hit", "on_crit")
trigger("melee_critical_hit", "on_hit", "on_crit_melee")
trigger("ranged_critical_hit", "on_hit", "on_crit_ranged")
trigger("noncritical_hit", "on_hit", function (p) return not p.is_critical_strike end)
trigger("critical_kill", "on_kill", "on_crit_kills")
trigger("heavy_hit", "on_hit", "on_heavy_hit")
trigger("backstab_hit", "on_hit", "is_backstab")
trigger("special_hit", "on_hit", function (p) return p.tags and p.tags.special end)
trigger("damage_taken", "on_damage_taken", function (p)
	return (p.damage_amount or 0) > 0 or (p.toughness_damage_amount or 0) > 0
end)
trigger("health_damage_taken", "on_damage_taken", function (p) return (p.damage_amount or 0) > 0 end)
trigger("block_broken", "on_block", "on_block_broken")
for id, event in pairs({
	ability_used = "on_combat_ability", grenade_thrown = "on_grenade_thrown",
	toughness_broken = "on_player_toughness_broken", successful_dodge = "on_successful_dodge",
	dodge = "on_dodge_start", slide = "on_slide_start", block = "on_block",
	perfect_block = "on_perfect_block", push = "on_push_finish",
	reload = "on_reload", reload_finished = "on_reload_finished",
	shoot = "on_shoot", melee_swing = "on_sweep_finish",
	wield_melee = "on_wield_melee", wield_ranged = "on_wield_ranged",
	ammo_pickup = "on_ammo_pickup",
}) do trigger(id, event) end

-- amount is always a positive percentage (percentage points for crit chance).
-- Types are explicit and checked against the installed settings: never guess
-- whether an engine stat wants 0.1, 1.1 or 0.9 for a ten-percent effect.
local function effect(id, stat, kind, limit, reduction)
	recipes.effects[id] = { stat = stat, kind = kind, limit = limit, reduction = reduction }
end
for _, id in ipairs({
	"damage", "melee_damage", "ranged_damage", "melee_heavy_damage",
	"weakspot_damage", "melee_weakspot_damage", "ranged_weakspot_damage",
	"critical_strike_damage", "melee_critical_strike_damage", "ranged_critical_strike_damage",
	"backstab_damage", "damage_vs_elites", "damage_vs_specials", "damage_vs_monsters",
	"damage_vs_horde", "damage_vs_bleeding", "damage_vs_burning", "damage_vs_electrocuted",
	"armored_damage", "super_armor_damage", "unarmored_damage", "warp_damage", "burning_damage",
	"melee_impact_modifier", "ranged_impact_modifier", "push_impact_modifier",
}) do effect(id, id, "additive_multiplier", 500) end
for _, id in ipairs({ "attack_speed", "melee_attack_speed", "ranged_attack_speed",
	"reload_speed", "wield_speed", "stamina_regeneration_modifier" }) do
	effect(id, id, "additive_multiplier", 200)
end
for _, id in ipairs({ "movement_speed", "sprint_movement_speed", "dodge_distance_modifier",
	"rending_multiplier", "melee_rending_multiplier", "ranged_rending_multiplier" }) do
	effect(id, id, "additive_multiplier", 100)
end
for _, id in ipairs({ "critical_strike_chance", "melee_critical_strike_chance", "ranged_critical_strike_chance" }) do
	effect(id, id, "value", 100)
end
effect("dodge_speed", "dodge_speed_multiplier", "multiplicative_multiplier", 100)
for id, stat in pairs({
	damage_reduction = "damage_taken_multiplier",
	toughness_damage_reduction = "toughness_damage_taken_multiplier",
	melee_damage_reduction = "melee_damage_taken_multiplier",
	ranged_damage_reduction = "ranged_damage_taken_multiplier",
	block_cost_reduction = "block_cost_multiplier",
	sprint_cost_reduction = "sprinting_cost_multiplier",
	corruption_reduction = "corruption_taken_multiplier",
}) do effect(id, stat, "multiplicative_multiplier", 95, true) end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local fields = { name = true, trigger = true, effect = true, amount = true,
	max_stacks = true, duration = true, chance = true, cooldown = true, enabled = true, legendary = true }
local function finite(n) return n and n == n and n ~= math.huge and n ~= -math.huge end

-- Errors invalidate their entire block. Other blocks still load. Duplicate IDs
-- invalidate both blocks; choosing the first or last would conceal a typo.
recipes.parse = function (text)
	local out, errors, blocks, seen = {}, {}, {}, {}
	if type(text) ~= "string" or #text > recipes.max_bytes then
		return out, { "definitions must be text of at most 65536 bytes" }
	end
	text = text:gsub("^\239\187\191", ""):gsub("\r\n", "\n")
	local current
	local function problem(line, message)
		errors[#errors + 1] = string.format("line %d: %s", line, message)
		if current then current.invalid = true end
	end
	local line_number = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		line_number = line_number + 1
		line = trim(line)
		if line ~= "" and not line:match("^[#;]") then
			if line:sub(1, 1) == "[" then
				current = { line = line_number }
				local id = line:match("^%[([a-z][a-z0-9_]*)%]$")
				if not id or #id > 48 then
					problem(line_number, "expected [id] with 1-48 lowercase letters, digits or underscores; start with a letter")
				else
					current.id = id
					blocks[#blocks + 1] = current
					if seen[id] then
						seen[id].invalid = true
						problem(line_number, "duplicate buff id '" .. id .. "'")
					end
					seen[id] = current
				end
			else
				local key, value = line:match("^([a-z_]+)%s*=%s*(.-)%s*$")
				if not current then problem(line_number, "setting outside a [buff_id] block")
				elseif not key or not fields[key] then problem(line_number, "unknown field or malformed key=value")
				elseif current[key] ~= nil then problem(line_number, "duplicate field '" .. key .. "'")
				else current[key] = value end
			end
		end
	end
	if #blocks > recipes.max_buffs then return {}, { "at most 64 buff definitions are allowed" } end
	for _, block in ipairs(blocks) do
		current = block
		if not block.invalid then
			local function number(key, default, min, max, integer)
				local value = block[key] == nil and default or tonumber(block[key])
				if not finite(value) or value < min or value > max or (integer and value % 1 ~= 0) then
					problem(block.line, key .. " must be " .. (integer and "an integer " or "a number ") .. "from " .. min .. " to " .. max)
				else block[key] = value end
			end
			if not recipes.triggers[block.trigger] then problem(block.line, "unknown or missing trigger") end
			local spec = recipes.effects[block.effect]
			if not spec then problem(block.line, "unknown or missing effect") end
			number("amount", nil, 0.01, 500)
			number("max_stacks", nil, 1, 31, true)
			number("duration", nil, 0.1, 600)
			number("chance", 100, 0.01, 100)
			number("cooldown", 0, 0, 600)
			block.name = block.name or block.id
			if block.name == "" or #block.name > 120 or block.name:find("[%z\1-\31]") then
				problem(block.line, "name must contain 1-120 bytes with no control characters")
			end
			if block.enabled ~= nil and block.enabled ~= "true" and block.enabled ~= "false" then
				problem(block.line, "enabled must be true or false")
			end
			block.enabled = block.enabled ~= "false"
			if block.legendary ~= nil and block.legendary ~= "true" and block.legendary ~= "false" then
				problem(block.line, "legendary must be true or false")
			end
			block.legendary = block.legendary ~= "false"
			if not block.invalid and spec then
				local total = spec.reduction and block.amount or block.amount * block.max_stacks
				if total > spec.limit then
					problem(block.line, block.effect .. " allows at most " .. spec.limit ..
						(spec.reduction and " percent per stack" or " percentage points across all stacks"))
				end
			end
			if not block.invalid then out[#out + 1] = block end
		end
	end
	table.sort(out, function (a, b) return a.id < b.id end)
	return out, errors
end

-- deps contains the installed enums/predicates and the CWaH runtime gate.
-- Canonical, bounded data for host-owned session catalogues. Never send Lua.
recipes.serialize = function (definitions, include_disabled)
	local blocks = {}
	for _, recipe in ipairs(definitions) do
		if recipe.enabled or include_disabled then
			blocks[#blocks + 1] = string.format("[%s]\nname = %s\ntrigger = %s\neffect = %s\namount = %.17g\nmax_stacks = %d\nduration = %.17g\nchance = %.17g\ncooldown = %.17g\n",
				recipe.id, recipe.name, recipe.trigger, recipe.effect, recipe.amount,
				recipe.max_stacks, recipe.duration, recipe.chance, recipe.cooldown)
			if not recipe.enabled then blocks[#blocks] = blocks[#blocks] .. "enabled = false\n" end
			if recipe.legendary == false then blocks[#blocks] = blocks[#blocks] .. "legendary = false\n" end
		end
	end
	return table.concat(blocks, "\n")
end

recipes.compile = function (definitions, deps)
	local entries, errors = {}, {}
	local slot = 0
	for _, recipe in ipairs(definitions) do
		if recipe.enabled then
			slot = slot + 1
			local source = recipes.triggers[recipe.trigger]
			local effect_spec = recipes.effects[recipe.effect]
			local event = rawget(deps.settings.proc_events or {}, source.event)
			local stat = rawget(deps.settings.stat_buffs or {}, effect_spec.stat)
			local kind = rawget(deps.settings.stat_buff_types or {}, effect_spec.stat)
			local check = source.check
			if type(check) == "string" then check = deps.checks[check] end
			if not event or not stat or kind ~= effect_spec.kind or (source.check and type(check) ~= "function") then
				errors[#errors + 1] = recipe.id .. ": trigger/effect is unavailable or its engine stat type has changed"
			else
				local fraction = recipe.amount / 100
				local value = effect_spec.kind == "multiplicative_multiplier"
					and (effect_spec.reduction and 1 - fraction or 1 + fraction) or fraction
				-- ID stems separate cards from helpers even when a user names a
				-- second card foo_stacks. IDs are otherwise stable across edits.
				local card_id = deps.slot_id and deps.slot_id(slot, "recipe") or "recipe_" .. recipe.id
				local helper_id = deps.slot_id and deps.slot_id(slot, "stack") or "stack_" .. recipe.id
				local signature = table.concat({ "recipe-v1", recipe.trigger, recipe.effect,
					string.format("%.17g", recipe.amount), tostring(recipe.max_stacks),
					string.format("%.17g", recipe.duration), string.format("%.17g", recipe.chance),
					string.format("%.17g", recipe.cooldown), recipe.legendary == false and "family" or "legendary" }, "/")
				local description = string.format("%s: %.4g%% chance to gain one stack of %s (%.4g%% per stack). Maximum %d stacks. Lasts %.4gs; triggers refresh all stacks, including at the cap. Cooldown: %.4gs.",
					recipe.trigger:gsub("_", " "), recipe.chance, recipe.effect:gsub("_", " "),
					recipe.amount, recipe.max_stacks, recipe.duration, recipe.cooldown)
				entries[#entries + 1] = {
					id = card_id, pool = true, user_recipe = true, definition_signature = signature,
					is_family_buff = recipe.legendary == false,
					title = { en = recipe.name:gsub("%%", "%%%%") },
					description = { en = description:gsub("%%", "%%%%") },
					icon = "hordes_buff_damage_increase",
					template = function (context)
						local helper_name = context.resolve(helper_id)
						return {
							class_name = "server_only_proc_buff", predicted = false,
							buff_category = deps.settings.buff_categories.hordes_buff,
							max_stacks = 1, max_stacks_cap = 1,
							proc_events = { [event] = recipe.chance / 100 },
							check_proc_func = function (params, data, ctx, t)
								return deps.active() and (not data.next_proc_t or t >= data.next_proc_t)
									and (not check or check(params, data, ctx, t))
							end,
							proc_func = function (_, data, ctx, t)
								if not deps.active() then return end
								local extension = ScriptUnit.has_extension(ctx.unit, "buff_system")
								if extension then
									data.next_proc_t = t + recipe.cooldown
									extension:add_internally_controlled_buff(helper_name, t)
								end
							end,
						}
					end,
				}
				entries[#entries + 1] = {
					id = helper_id, user_recipe = true, definition_signature = signature,
					template = function ()
						return {
							class_name = "buff", predicted = false,
							max_stacks = recipe.max_stacks, max_stacks_cap = recipe.max_stacks,
							duration = recipe.duration, refresh_duration_on_stack = true,
							refresh_duration_on_remove_stack = false,
							conditional_stat_buffs = { [stat] = value },
							conditional_stat_buffs_func = deps.carrier_active or deps.active,
							always_show_in_hud = true,
							hud_icon = "content/ui/textures/icons/buffs/hud/zealot/zealot_ability_chastise_the_wicked",
							hud_icon_gradient_map = "content/ui/textures/color_ramps/talent_ability",
							hud_priority = 1,
						}
					end,
				}
			end
		end
	end
	return entries, errors
end

return recipes
