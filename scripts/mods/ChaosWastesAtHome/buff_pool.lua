local mod = get_mod("ChaosWastesAtHome")

local HordesBuffsData = require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")
local MissionBuffsAllowedBuffs = require("scripts/managers/mission_buffs/mission_buffs_allowed_buffs")

-- Which buffs are allowed into the roll pools, and the catalogue the toggle
-- view is built from.
--
-- Enabled is the default for almost everything, and defaults are not stored:
-- only explicit player choices are, so a fresh install persists nothing and a
-- buff added by a later patch arrives enabled rather than silently missing.
--
-- "Almost", because a buff can ship default-off (custom_buffs marks those). That
-- is why there are two stored sets rather than one. With only a disabled list
-- there is no way to tell "the player has never had an opinion about this" from
-- "the player switched it on", and a default-off buff needs those to differ --
-- otherwise enabling it would be forgotten the moment anything else was saved.

local buff_pool = {}

local SETTING_ID = "disabled_buffs"
local ENABLED_SETTING_ID = "enabled_buffs"
local CUSTOM_CATEGORY = "custom"

-- Group ids are persistence-free (they only drive the filter list), but the
-- buff names inside them are the save keys.
local GROUP_LEGENDARY = "legendary_generic"
local GROUP_CUSTOM = "custom"

local catalogue = nil

-- ---------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------

-- The allowed-buff tables nest differently per archetype -- generic is a flat
-- array, grenade_ability and combat_ability are keyed by ability name -- so the
-- leaves are gathered rather than walked at fixed depths. Anything that is a
-- string is a buff name.
local function _collect_names(node, out, seen)
	if type(node) == "string" then
		if not seen[node] then
			seen[node] = true
			out[#out + 1] = node
		end

		return
	end

	if type(node) ~= "table" then
		return
	end

	for _, child in pairs(node) do
		_collect_names(child, out, seen)
	end
end

local function _new_group(id, label)
	return { id = id, label = label, names = {}, seen = {} }
end

local function _add(group, name)
	if not group.seen[name] then
		group.seen[name] = true
		group.names[#group.names + 1] = name
	end
end

local function _is_custom(name)
	local data = HordesBuffsData[name]

	return data ~= nil and data.filter_category == CUSTOM_CATEGORY
end

local function _build_catalogue()
	local groups = {}
	local by_name = {}

	-- Families, in the game's own order rather than alphabetical -- this is the
	-- order the player sees them offered in.
	local families = MissionBuffsAllowedBuffs.buff_families or {}

	for _, family_id in ipairs(MissionBuffsAllowedBuffs.available_family_builds or {}) do
		local family = families[family_id]

		if family then
			local group = _new_group("family_" .. family_id, family.name or family_id)

			for _, name in ipairs(family.priority_buffs or {}) do
				_add(group, name)
			end

			for _, name in ipairs(family.buffs or {}) do
				_add(group, name)
			end

			groups[#groups + 1] = group
		end
	end

	local legendary = MissionBuffsAllowedBuffs.legendary_buffs or {}
	local generic_group = _new_group(GROUP_LEGENDARY, mod:localize("buff_group_legendary"))
	local custom_group = _new_group(GROUP_CUSTOM, mod:localize("buff_group_custom"))

	-- Custom buffs live in legendary_buffs.generic alongside the shipped ones
	-- (that is how they become rollable), so they are split back out here by
	-- their filter_category to give them a filter tab of their own.
	for _, name in ipairs(legendary.generic or {}) do
		_add(_is_custom(name) and custom_group or generic_group, name)
	end

	groups[#groups + 1] = generic_group

	local archetypes = {}

	for key, value in pairs(legendary) do
		if key ~= "generic" and type(value) == "table" then
			archetypes[#archetypes + 1] = key
		end
	end

	table.sort(archetypes)

	for _, archetype in ipairs(archetypes) do
		local group = _new_group("archetype_" .. archetype, mod:localize("buff_group_archetype", archetype))
		local names, seen = {}, {}

		_collect_names(legendary[archetype], names, seen)

		for _, name in ipairs(names) do
			_add(group, name)
		end

		if #group.names > 0 then
			groups[#groups + 1] = group
		end
	end

	if #custom_group.names > 0 then
		groups[#groups + 1] = custom_group
	end

	-- Titles are resolved here rather than at load: Managers.localization does
	-- not exist while mods are loading.
	for _, group in ipairs(groups) do
		group.seen = nil

		for _, name in ipairs(group.names) do
			if not by_name[name] then
				by_name[name] = buff_pool.display_name(name)
			end
		end
	end

	return { groups = groups, titles = by_name }
end

buff_pool.display_name = function (name)
	local data = HordesBuffsData[name]
	local key = data and data.title

	if key and Managers.localization then
		local ok, text = pcall(Managers.localization.localize, Managers.localization, key)

		if ok and text and text ~= "" and text ~= key then
			return text
		end
	end

	-- Falls back to the raw name rather than blanking the row: an unlocalized
	-- entry is still togglable and still needs to be identifiable.
	return name
end

local parser = nil

-- The description is not a plain localization key.
--
-- Localizing it directly renders literal "{time}" and "{damage}" placeholders:
-- the numbers live in a separate buff_stats table on the entry and are
-- substituted -- and coloured -- by the game's own parser. This is the same
-- call the buff card and the tactical overlay make
-- (constant_element_mission_buffs.lua:145), so the text here matches what the
-- player sees when the buff is actually offered.
--
-- Required at call time rather than at file scope: this module loads while mods
-- are loading, and pulling UI modules in that early is how the status-cascade
-- hook poisoned itself. By the time a view asks for a description the module
-- loads normally.
local function _parser()
	if not parser then
		parser = require("scripts/ui/constant_elements/elements/mission_buffs/utilities/mission_buffs_parser")
	end

	return parser
end

-- Everything the detail card needs. Nil when the buff has no data entry at all,
-- which is the caller's cue to show nothing rather than an empty card.
buff_pool.details = function (name)
	local data = HordesBuffsData[name]

	if not data then
		return nil
	end

	local description

	local ok, text = pcall(function ()
		return _parser().get_formated_buff_description(data, Color.ui_terminal(255, true))
	end)

	if ok and type(text) == "string" and text ~= "" then
		description = text
	end

	return {
		title = buff_pool.display_name(name),
		description = description,
		icon = data.icon,
		is_family_buff = data.is_family_buff and true or false,
	}
end

-- Rebuilt on demand so a mod reload or a newly registered custom buff shows up.
buff_pool.invalidate = function ()
	catalogue = nil
end

buff_pool.groups = function ()
	if not catalogue then
		catalogue = _build_catalogue()
	end

	return catalogue.groups
end

buff_pool.title = function (name)
	if not catalogue then
		catalogue = _build_catalogue()
	end

	return catalogue.titles[name] or buff_pool.display_name(name)
end

-- ---------------------------------------------------------------------------
-- Enabled / disabled state
-- ---------------------------------------------------------------------------

local function _disabled_table()
	local stored = mod:get(SETTING_ID)

	return type(stored) == "table" and stored or {}
end

-- Names the player has explicitly switched ON. Only meaningful for default-off
-- buffs; harmless and ignored for everything else.
local function _enabled_table()
	local stored = mod:get(ENABLED_SETTING_ID)

	return type(stored) == "table" and stored or {}
end

-- Read from `mod` rather than imported: custom_buffs publishes it there during
-- registration, and requiring that module from here would load a second copy of
-- it (mod:io_dofile re-executes rather than caching).
local function _is_default_off(name)
	local defaults = mod._default_off_buffs

	return defaults ~= nil and defaults[name] == true
end

-- Explicit choice wins in both directions; the catalogue default only decides
-- for names the player has never touched.
buff_pool.is_enabled = function (name)
	if _disabled_table()[name] then
		return false
	end

	if _is_default_off(name) then
		return _enabled_table()[name] == true
	end

	return true
end

-- Stored as a name -> true hash and never as an array: SJSON cannot serialize a
-- table with both array and hash parts, and DMF settings land in
-- user_settings.config through SJSON.
-- Both sides are written every time, so the two tables can never disagree about
-- a name.
--
-- Stored as name -> true hashes and never as arrays: SJSON cannot serialize a
-- table with both array and hash parts, and DMF settings land in
-- user_settings.config through SJSON.
local function _apply(names, enabled)
	enabled = enabled and true or false

	local disabled = _disabled_table()
	local explicit = _enabled_table()

	for i = 1, #names do
		local name = names[i]

		disabled[name] = not enabled or nil
		explicit[name] = enabled or nil
	end

	mod:set(SETTING_ID, disabled, false)
	mod:set(ENABLED_SETTING_ID, explicit, false)
end

local ONE = {}

buff_pool.set_enabled = function (name, enabled)
	ONE[1] = name

	_apply(ONE, enabled)
end

buff_pool.set_group_enabled = function (group, enabled)
	_apply(group.names, enabled)
end

buff_pool.group_counts = function (group)
	local on = 0

	for _, name in ipairs(group.names) do
		if buff_pool.is_enabled(name) then
			on = on + 1
		end
	end

	return on, #group.names
end

-- Counts what is actually off, which is no longer the same as the size of the
-- disabled table: a default-off buff nobody has touched is in neither table.
buff_pool.disabled_count = function ()
	local count = 0

	for _, group in ipairs(buff_pool.groups()) do
		for _, name in ipairs(group.names) do
			if not buff_pool.is_enabled(name) then
				count = count + 1
			end
		end
	end

	return count
end

-- ---------------------------------------------------------------------------
-- Applying to the pools
-- ---------------------------------------------------------------------------

-- Writes every disabled buff into the exclusion table the buff system already
-- filters both pools through -- init_legendary_buffs_pool_for_player for the
-- legendary pool, set_buff_family_for_player for the priority and regular
-- family pools. Nothing here needs to know which pool a name belongs to.
--
-- Deliberately additive: the same table carries the run's already-owned buffs,
-- and clobbering it would re-offer everything the player has.
-- Walks the catalogue rather than the stored table, because "off" is no longer
-- the same as "stored as disabled" -- a default-off buff the player has never
-- touched appears in neither set and would otherwise leak into the pool.
buff_pool.apply_exclusions = function (exclude)
	local count = 0

	for _, group in ipairs(buff_pool.groups()) do
		for _, name in ipairs(group.names) do
			if not buff_pool.is_enabled(name) then
				if not exclude[name] then
					exclude[name] = true
				end

				count = count + 1
			end
		end
	end

	return count
end

return buff_pool
