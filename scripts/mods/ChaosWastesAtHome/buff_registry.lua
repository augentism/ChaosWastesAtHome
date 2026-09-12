local mod = get_mod("ChaosWastesAtHome")

-- Deliberately required in this order. Loading BuffTemplates pulls in
-- hordes_legendary_psyker_buff_templates (buff_templates.lua:46), which drags
-- most of the hordes tree into package.loaded with it -- so asking for the rest
-- afterwards is a cache hit rather than a fresh module execution during
-- boot-time mod loading. Being the FIRST loader of one of those is the risky
-- position: a require that throws at boot is permanently unrecoverable, because
-- Lua leaves a sentinel in package.loaded and every later require of that
-- module fails for the rest of the session.
local BuffTemplates = require("scripts/settings/buff/buff_templates")
local BuffSettings = require("scripts/settings/buff/buff_settings")
local HordesBuffsData = require("scripts/settings/buff/hordes_buffs/hordes_buffs_data")
local MissionBuffsAllowedBuffs = require("scripts/managers/mission_buffs/mission_buffs_allowed_buffs")
local MissionBuffsSettings = require("scripts/managers/mission_buffs/mission_buffs_settings")

-- Read at build time rather than captured at file scope.
--
-- buff_settings pulls in breed_queries and calls it while still loading, so it
-- is one of the modules that can come back half-built if something upstream of
-- it failed -- and a file-scope capture of a field that is nil at that instant
-- stays nil for the session even after the module recovers.
local function _hordes_buff_category()
	local categories = BuffSettings.buff_categories

	return categories and categories.hordes_buff
end

-- The registry every custom buff goes through -- this mod's own and any addon
-- mod's.
--
-- What this file is for: adding a buff to the Mortis pools means writing five
-- separate registrations, and missing any one of them fails in a different,
-- mostly silent way. Two of them (template.name and the network id) crash only
-- when the buff is APPLIED, never when it is offered -- so the card renders
-- perfectly and kills the mission when you pick it. docs/adding-custom-buffs.md
-- is the long version. This file is the short one: hand it a catalogue entry and
-- it does all five, or refuses the entry and says why.
--
-- Registration is IMMEDIATE, not batched into a later finalize step, and that is
-- what makes load order irrelevant. An addon calls register_buffs from its own
-- on_all_mods_loaded, where get_mod("ChaosWastesAtHome") resolves whatever the
-- order in mod_load_order.txt happens to be. There is deliberately no "you must
-- load above/below us" rule to get wrong -- crosshair_remap has one and it is
-- silent in both directions when broken.

-- State lives on the mod table; the functions below are rebuilt on every load.
--
-- mod:io_dofile re-executes this file on every call rather than caching it, so a
-- second caller would otherwise get its own registry -- a second set of entries,
-- a second counter table, and an addon that registered against the first one
-- invisible to the second. Keeping only the state on `mod` also means a
-- redeployed copy of this file takes effect the next time it is loaded, instead
-- of being pinned until a full mod reload.
local state = mod._buff_registry_state

if not state then
	state = {
		-- Registration order, for the pool and the menu, where the author's
		-- ordering is the useful one.
		entries = {},
		-- id -> entry, for collision checks and prerequisite lookups.
		by_id = {},
		-- id -> { label = string, owner = mod name }
		categories = {},
		-- Registration order of categories, so the toggle view's tabs are
		-- stable rather than pairs()-ordered.
		category_order = {},
		-- Buffs that exist and are listed in the menu but are not rolled unless
		-- the player switches them on.
		default_off = {},
		-- Shared counter table. Parked here rather than in a file local because
		-- a live buff instance keeps the proc_func closure it was created with:
		-- a mod reload rebuilds the template but does not touch buffs already on
		-- the player, so a fresh local would leave that closure counting into an
		-- orphaned table while the report read an empty one. The symptom is a
		-- working proc buff reporting zero.
		--
		-- Adopts the table custom_buffs.lua used before this registry existed,
		-- so a live reload onto this version does not strand closures that are
		-- already counting into it.
		counters = mod._custom_buff_procs or {},
		-- Live stack readings contributed by registrants, for /cw_verify.
		readings = {},
		-- [event][owner] = fn. Keyed by owner rather than appended, so an addon
		-- that reloads and subscribes again replaces its callback instead of
		-- stacking a second one that fires alongside the first.
		listeners = {},
	}

	mod._buff_registry_state = state
end

-- One table under both names, forever. custom_buffs.lua and any addon that took
-- a reference to mod._custom_buff_procs are counting into the same place the
-- report reads from.
mod._custom_buff_procs = state.counters

local registry = {}

-- Icons that name no path are resolved against the shipped Mortis set. Those
-- are only loadable because the mod pulls in the Mortis package; a genuinely
-- custom texture needs a mod bundle, which is a much larger job.
local ICON_ROOT = "content/ui/textures/icons/buffs/hud/horde_buffs/small_buffs/"

local DEFAULT_CATEGORY = "custom"

-- How many individual rejection or warning lines one register_buffs call may
-- write before it stops naming them and just counts. See the report helper.
local LOG_LINE_CAP = 8

-- ---------------------------------------------------------------------------
-- Localization keys
-- ---------------------------------------------------------------------------

-- Derived from the id, exactly as hordes_buffs_data.lua derives them for the
-- shipped buffs, so there is no second place for a key and a template to
-- disagree.
local function _title_key(entry)
	return entry.title_key or ("loc_" .. entry.id .. "_title")
end

local function _description_key(entry)
	return entry.description_key or ("loc_" .. entry.id .. "_description")
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------
--
-- Every check here exists because the failure it catches is silent. None of
-- them produce an error you would notice in-game: the buff renders as a normal
-- card and then crashes on pick, or never rolls at all, or shows the raw
-- localization key. Rejecting the entry loudly at registration is the whole
-- point of having an API rather than a documentation page.

local function _is_string(value)
	return type(value) == "string" and value ~= ""
end

local function _owner_name(addon)
	if type(addon) == "table" and type(addon.get_name) == "function" then
		return addon:get_name()
	end

	return addon
end

-- Include the length so owner/id boundaries cannot collide even when either
-- contains underscores. Never choose a name based on who registered first.
local function _id_prefix(addon)
	local owner = _owner_name(addon)
	assert(_is_string(owner), "buff_id needs an addon name")
	return "cwah_addon_" .. #owner .. "_" .. owner .. "_"
end

registry.buff_id = function (addon, id)
	assert(_is_string(id), "buff_id needs a local buff id")

	return _id_prefix(addon) .. id
end

local function _prepare_entry(source, addon)
	if type(source) ~= "table" or not _is_string(source.id) then
		return source
	end

	-- Do not rewrite the author's catalogue in place: it may be registered
	-- again, or its factories may close over that very table.
	local entry = {}
	for key, value in pairs(source) do entry[key] = value end
	local function resolve(id) return registry.buff_id(addon, id) end
	entry.local_id = source.id
	entry.id = resolve(source.id)
	entry.context = { id = entry.id, resolve = resolve }
	for _, field in ipairs({ "upgrade_of", "unlock_after" }) do
		if _is_string(entry[field]) then entry[field] = resolve(entry[field]) end
	end
	for _, field in ipairs({ "requires_all", "requires_any" }) do
		if type(entry[field]) == "table" then
			entry[field] = {}
			for i, id in ipairs(source[field]) do
				entry[field][i] = _is_string(id) and resolve(id) or id
			end
		end
	end

	return entry
end

-- Translations are { en = "...", ko = "..." }. Every value must survive
-- string.format, because DMF runs localization strings through it on the way
-- out and safe_string_format catches the error and returns NIL -- so a stray %
-- turns the card title into nil with one log line per lookup, and nothing else.
local function _check_translations(field, translations, values, problems, id)
	if type(translations) ~= "table" then
		problems[#problems + 1] = string.format(
			"%s: no '%s' text - the card will show its localization key", id, field)

		return
	end

	if not _is_string(translations.en) then
		problems[#problems + 1] = string.format("%s: '%s' has no English string, which is the fallback every other language relies on", id, field)
	end

	for language, text in pairs(translations) do
		if not _is_string(text) then
			problems[#problems + 1] = string.format("%s: '%s.%s' is not a string", id, field, tostring(language))
		else
			local ok, err = pcall(string.format, text, unpack(values or {}))

			if not ok then
				problems[#problems + 1] = string.format(
					"%s: '%s.%s' does not match its values (%s). A literal per-cent sign must be written %%%%",
					id, field, tostring(language), tostring(err))
			end
		end
	end
end

-- Returns a list of problems; empty means the entry is registrable.
--
-- owner_name matters for the collision check: re-registering an id you already
-- own is a RELOAD, which is normal and must succeed. Only another owner's id --
-- or a shipped one -- is a collision.
local function _validate(entry, prefix, owner_name, problems, warnings)
	if type(entry) ~= "table" then
		problems[#problems + 1] = "entry is not a table"

		return problems
	end

	local id = entry.id

	if not _is_string(id) then
		problems[#problems + 1] = "entry has no string 'id'"

		return problems
	end

	-- Namespacing is the collision defence, and it has to be enforced rather
	-- than recommended. Two things share a flat namespace here: BuffTemplates,
	-- where clobbering a shipped template would be catastrophic and completely
	-- silent, and DMF's _global_localization_database, which is one table with
	-- no mod prefix and first-write-wins.
	if prefix and id:sub(1, #prefix) ~= prefix then
		problems[#problems + 1] = string.format("%s: id must begin with '%s' so it cannot collide with another mod's", id, prefix)
	end

	local existing = state.by_id[id]

	if existing then
		if existing.owner ~= owner_name then
			problems[#problems + 1] = string.format("%s: already registered by %s", id, tostring(existing.owner))
		end
	elseif BuffTemplates[id] then
		-- Not ours and not previously registered: this is a shipped template.
		problems[#problems + 1] = string.format("%s: a game buff template already uses this name", id)
	end

	if entry.template ~= nil and type(entry.template) ~= "function" then
		problems[#problems + 1] = string.format("%s: 'template' must be a function returning the template table", id)
	end

	if entry.template == nil and type(entry.stat_buffs) ~= "table" then
		problems[#problems + 1] = string.format("%s: needs either a 'template' factory or a 'stat_buffs' table", id)
	end

	if entry.values ~= nil and type(entry.values) ~= "table" then
		problems[#problems + 1] = string.format("%s: 'values' must be an array of substitutions", id)
	end

	if entry.icon ~= nil and not _is_string(entry.icon) then
		problems[#problems + 1] = string.format("%s: 'icon' must be a string", id)
	end

	-- Card data, needed only by buffs that are actually offered. A helper
	-- template applied by another buff needs the template and the network id and
	-- nothing else.
	--
	-- Text problems are WARNINGS. A card with no name is ugly, not broken: it
	-- renders its localization key and works perfectly. Refusing to register it
	-- would take a functioning gameplay card away from the player over a
	-- cosmetic gap -- the same over-strictness that briefly turned off two of
	-- this mod's own buffs. Reject only what would crash or do nothing.
	if entry.pool then
		if not entry.title_key then
			_check_translations("title", entry.title, nil, warnings, id)
		end

		if not entry.description_key then
			_check_translations("description", entry.description, entry.values, warnings, id)
		end
	end

	for _, field in ipairs({ "upgrade_of", "unlock_after" }) do
		if entry[field] ~= nil and not _is_string(entry[field]) then
			problems[#problems + 1] = string.format("%s: '%s' must be a buff id", id, field)
		end
	end

	for _, field in ipairs({ "requires_all", "requires_any" }) do
		if entry[field] ~= nil and type(entry[field]) ~= "table" then
			problems[#problems + 1] = string.format("%s: '%s' must be an array of buff ids", id, field)
		end
	end

	return problems
end

-- Checked after the factory has run, because these live on the built template
-- rather than on the catalogue entry.
--
-- Note the split: a problem stops the entry registering, a warning does not.
-- The line between them is whether the buff would CRASH or be nonfunctional
-- (reject) or merely behave differently from what the author probably intended
-- (warn). Getting that wrong in the strict direction is its own silent failure
-- -- an over-eager check here refused two of this mod's own working buffs and
-- the only symptom was two cards that stopped being offered.
local function _validate_template(id, template, problems, warnings)
	if type(template) ~= "table" then
		problems[#problems + 1] = string.format("%s: the 'template' factory did not return a table", id)

		return
	end

	-- max_stacks is NOT the limit despite the name -- it only makes the buff
	-- stackable at all (can_stack = not not template.max_stacks). The limit is
	-- max_stacks_cap, and _check_max_stacks_cap returns "allowed" outright when
	-- it is nil. Setting only the first gives an unbounded ramp that cheerfully
	-- reports itself as 158/20 stacks, with nothing in the log.
	--
	-- A warning rather than a rejection: it is only wrong for a template that
	-- something actually adds repeatedly. A controller that sits at one stack is
	-- perfectly correct without a cap.
	if template.max_stacks and template.max_stacks > 1 and not template.max_stacks_cap then
		warnings[#warnings + 1] = string.format(
			"%s: has max_stacks=%d but no 'max_stacks_cap', so the ramp will never cap",
			id, template.max_stacks)
	end
end

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------

-- A category of one's own, so an addon's buffs can be weighted and toggled as a
-- group rather than being mixed into everyone else's.
--
-- filtering_categories is a table.enum whose metatable errors on unknown READS
-- but does not guard writes, so adding the key is allowed and makes every later
-- read safe. It has to happen before anything asks for it:
-- init_legendary_buffs_pool_for_player builds one bucket per registered
-- category and then indexes that table by each buff's filter_category, so an
-- unregistered category is a nil-index crash at mission start -- a long way from
-- the buff that caused it.
registry.register_category = function (id, opts)
	if not _is_string(id) then
		mod:error("register_category: id must be a non-empty string")

		return false
	end

	opts = opts or {}

	if state.categories[id] then
		return true
	end

	state.categories[id] = {
		id = id,
		label = opts.label or id,
		owner = opts.owner,
		-- How often this category comes up relative to the shipped ones.
		-- _pop_legendary_buff_from_players_pool picks a CATEGORY by weight first
		-- and then a buff uniformly inside it, so every extra category is extra
		-- non-vanilla share -- not extra cards competing for the same share.
		weight = opts.weight or 1,
	}

	state.category_order[#state.category_order + 1] = id

	MissionBuffsSettings.filtering_categories[id] = id

	return true
end

-- For an addon that exposes its own weight slider: register_category refuses to
-- overwrite an existing entry, so the setting needs a way to move the weight
-- afterwards. Takes effect at the next mission, where apply_weights runs.
registry.set_category_weight = function (id, weight)
	local category = state.categories[id]

	if not category then
		mod:error("set_category_weight: '%s' is not a registered category", tostring(id))

		return false
	end

	category.weight = weight or 1

	return true
end

registry.categories = function ()
	local out = {}

	for _, id in ipairs(state.category_order) do
		out[#out + 1] = state.categories[id]
	end

	return out
end

registry.category_ids = function ()
	return state.category_order
end

registry.is_registered_category = function (id)
	return state.categories[id] ~= nil
end

-- What the toggle view puts on the category's tab. Falls back to the raw id
-- rather than blanking the tab: an unlabelled category is still togglable and
-- still needs to be identifiable.
registry.category_label = function (id)
	local category = state.categories[id]

	return category and category.label or id
end

-- Applied per mission, because the weight settings can change between them.
--
-- Only writes the categories it wants to differ: the selector falls back to 1
-- for anything it does not recognise.
registry.apply_weights = function (weight_for)
	for _, rates in pairs(MissionBuffsSettings.filtering_categories_pick_rate_per_wave) do
		for _, id in ipairs(state.category_order) do
			local category = state.categories[id]
			local weight = weight_for and weight_for(id, category)

			rates[id] = weight or category.weight
		end
	end
end

-- ---------------------------------------------------------------------------
-- The network lookup
-- ---------------------------------------------------------------------------

-- Every template also needs an entry in NetworkLookup.buff_templates.
--
-- That table is built once at boot from whatever is in BuffTemplates at that
-- moment, and mods load afterwards -- so a template added by a mod is never in
-- it. PlayerUnitBuffExtension._add_rpc_synced_buff reads the id unconditionally,
-- *before* it checks whether the player is even remote, and the lookup's
-- metatable ERRORS on an unknown key rather than returning nil. So applying a
-- custom buff crashes in solo too, despite nothing ever going over the wire.
--
-- The lookup is bidirectional -- lookup[i] = name and lookup[name] = i -- and
-- only __index is guarded, so appending is allowed. Membership has to be tested
-- with rawget: a plain read of a missing key is the crash itself.
--
-- Idempotent, and called again per mission in case the mod loaded before
-- NetworkLookup existed.
registry.ensure_network_id = function (buff_name)
	local network_lookup = rawget(_G, "NetworkLookup")
	local buff_lookup = network_lookup and network_lookup.buff_templates

	if not buff_lookup then
		mod:error("NetworkLookup.buff_templates missing - custom buffs will crash when applied")

		return false
	end

	if not rawget(buff_lookup, buff_name) then
		local index = #buff_lookup + 1

		buff_lookup[index] = buff_name
		buff_lookup[buff_name] = index

		mod:debug_log("network lookup: %s = %d", buff_name, index)
	end

	return true
end

-- Every template registered, pickable or not, sorted.
--
-- Sorted rather than registration order so an id is a pure function of the name
-- SET. _create_lookup sorts before appending for exactly this reason, and it is
-- what makes every vanilla client agree on every index. Reordering a catalogue
-- -- or installing addons in a different order -- then cannot silently change an
-- id.
--
-- What that still does not survive: peers with different addons installed (a
-- different name set), or another mod appending to the same lookup, since the
-- base offset then depends on mod_load_order.txt. net.lua's ident handshake
-- catches both by comparing the assigned ids rather than a version string.
registry.all_template_names = function ()
	local names = {}

	for _, entry in ipairs(state.entries) do
		names[#names + 1] = entry.id
	end

	table.sort(names)

	return names
end

-- Just the pickable ones, in registration order -- this drives the pool and the
-- menu, where the author's ordering is the useful one.
registry.pool_names = function ()
	local names = {}

	for _, entry in ipairs(state.entries) do
		if entry.pool then
			names[#names + 1] = entry.id
		end
	end

	return names
end

registry.register_network_lookup = function ()
	local ok = true

	for _, buff_name in ipairs(registry.all_template_names()) do
		ok = registry.ensure_network_id(buff_name) and ok
	end

	return ok
end

-- The ids this machine assigned, in sorted name order: the thing two peers have
-- to agree on before a custom buff can cross the wire.
--
-- Names alone are not enough. An id is #buff_lookup + 1 at append time, so two
-- machines with identical mods still disagree if some OTHER mod appended first.
-- Comparing the assigned ids catches that; comparing a version string does not.
--
-- Returned as "name=id" strings rather than a hash so a mismatch names itself in
-- the log.
registry.network_id_map = function ()
	local network_lookup = rawget(_G, "NetworkLookup")
	local buff_lookup = network_lookup and network_lookup.buff_templates

	if not buff_lookup then
		return nil
	end

	local entries = {}

	for _, buff_name in ipairs(registry.all_template_names()) do
		entries[#entries + 1] = string.format("%s=%s", buff_name, tostring(rawget(buff_lookup, buff_name)))
	end

	return entries
end

-- ---------------------------------------------------------------------------
-- Prerequisites
-- ---------------------------------------------------------------------------
--
-- The Mortis system has no notion of one buff unlocking another: the legendary
-- pool is built once per player at spawn and buffs are popped out of it as they
-- are handed over. So a gated buff is held out of the initial pool and inserted
-- into the live one when its prerequisite lands.
--
-- Both halves already exist elsewhere in this mod -- the exclusion table the
-- pool is filtered through, and run.lua's _drop_from_pool, which mutates the
-- same per-player pools in the other direction.

local function _requirements(entry)
	local all = {}

	-- upgrade_of and unlock_after are the same mechanism with different names.
	-- Both read better than requires_all = { x } at the call site, and an
	-- upgrade card wants to say which card it upgrades.
	if entry.upgrade_of then
		all[#all + 1] = entry.upgrade_of
	end

	if entry.unlock_after then
		all[#all + 1] = entry.unlock_after
	end

	for _, id in ipairs(entry.requires_all or {}) do
		all[#all + 1] = id
	end

	return all, entry.requires_any
end

-- `owned` is a name -> anything table of what the player already holds.
registry.is_unlocked = function (buff_name, owned)
	local entry = state.by_id[buff_name]

	if not entry then
		return true
	end

	local all, any = _requirements(entry)

	for _, id in ipairs(all) do
		if not owned[id] then
			return false
		end
	end

	if any and #any > 0 then
		for _, id in ipairs(any) do
			if owned[id] then
				return true
			end
		end

		return false
	end

	return true
end

registry.has_prerequisites = function (buff_name)
	local entry = state.by_id[buff_name]

	if not entry then
		return false
	end

	local all, any = _requirements(entry)

	return #all > 0 or (any ~= nil and #any > 0)
end

-- Cheap early-out for the per-frame unlock check: most installs have no gated
-- buffs at all, and this saves walking players and pools for them.
registry.has_any_prerequisites = function ()
	for _, entry in ipairs(state.entries) do
		if entry.pool and registry.has_prerequisites(entry.id) then
			return true
		end
	end

	return false
end

-- Every name that something else depends on. This is the set worth asking a
-- player's buff extension about -- testing all of them is cheaper and steadier
-- than enumerating everything a player is holding.
registry.prerequisite_names = function ()
	local names = {}

	for _, entry in ipairs(state.entries) do
		local all, any = _requirements(entry)

		for _, id in ipairs(all) do
			names[id] = true
		end

		for _, id in ipairs(any or {}) do
			names[id] = true
		end
	end

	return names
end

-- Pickable buffs held out of the initial pool because they are gated. The
-- toggle view needs these: they are never in legendary_buffs.generic, so a view
-- built only from that pool would never show an upgrade card and the player
-- could not switch one off before it unlocked.
registry.gated_pool_entries = function ()
	local out = {}

	for _, entry in ipairs(state.entries) do
		if entry.pool and registry.has_prerequisites(entry.id) then
			out[#out + 1] = entry
		end
	end

	return out
end

-- Every registered buff whose prerequisites are not met, as a name -> true
-- table ready to be merged into the exclusion list the pools are filtered
-- through.
registry.locked_names = function (owned)
	local locked = {}

	for _, entry in ipairs(state.entries) do
		if entry.pool and not registry.is_unlocked(entry.id, owned) then
			locked[entry.id] = true
		end
	end

	return locked
end

-- Names that have just become available: gated, now unlocked, not already held
-- and not already in the pool. The caller inserts them into the live per-player
-- pool, which is why the category comes back with each one.
registry.newly_unlocked = function (owned, in_pool)
	local out = {}

	for _, entry in ipairs(state.entries) do
		if entry.pool
			and registry.has_prerequisites(entry.id)
			and not owned[entry.id]
			and not in_pool[entry.id]
			and registry.is_unlocked(entry.id, owned)
		then
			out[#out + 1] = { name = entry.id, category = entry.category }
		end
	end

	return out
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

-- Builds the template from the entry. The shorthand covers a plain passive; a
-- factory covers everything else.
local function _build_template(entry)
	if entry.template then
		return entry.template(entry.context)
	end

	return {
		class_name = "buff",
		max_stacks = 1,
		max_stacks_cap = 1,
		predicted = false,
		buff_category = _hordes_buff_category(),
		stat_buffs = entry.stat_buffs,
	}
end

-- Card text goes into DMF's GLOBAL localization database, not the owning mod's
-- private table.
--
-- A mod's own table is only reachable through mod:localize, and we are not the
-- ones drawing the card: MissionBuffsParser renders it with
-- Managers.localization:localize (mission_buffs_parser.lua:125) -- the game's
-- manager, which has never heard of a mod's private table. DMF hooks that
-- manager and consults _global_localization_database first, and
-- add_global_localize_strings is the only way into it.
--
-- Numbers are substituted HERE rather than left as {tokens} for the parser. The
-- shipped cards put {time} / {damage} in the string and let MissionBuffsParser
-- fill them from a buff_stats table, but that expansion happens inside
-- LocalizationManager._process_string and DMF's hook answers the lookup and
-- returns before the game's localize ever runs. A {token} in a mod-registered
-- string reaches the card verbatim.
--
-- Note the string DMF hands back is itself string.format'd on the way out,
-- which is why a literal per-cent in a substituted value has to be doubled.
local function _card_strings(entry)
	local globals = {}

	local function _take(key, translations, values)
		if not translations then
			return
		end

		if not values then
			globals[key] = translations

			return
		end

		-- Formatted per language: the values and their order are the same
		-- everywhere, the sentence around them is not.
		local formatted = {}

		for language, text in pairs(translations) do
			local ok, result = pcall(string.format, text, unpack(values))

			formatted[language] = ok and result or text
		end

		globals[key] = formatted
	end

	if not entry.title_key then
		_take(_title_key(entry), entry.title)
	end

	if not entry.description_key then
		_take(_description_key(entry), entry.description, entry.values)
	end

	return globals
end

-- Does all five registrations for one entry. Called with the entry already
-- validated.
local function _register_one(entry, owner_name, template)

	-- Every template needs a `name` matching its key.
	--
	-- The game sets this for shipped buffs when it assembles BuffTemplates
	-- (template.name = template.name or name), so a template written straight
	-- into the table never gets one. BuffExtensionBase._add_buff then uses it as
	-- a table key for stack tracking, and a nil key crashes the moment the buff
	-- is applied -- not when it is offered, so the card looks fine right up
	-- until you pick it.
	template.name = entry.id

	BuffTemplates[entry.id] = template

	-- Card data for the pickable ones only. filter_category is mandatory and
	-- easy to forget by hand: init_legendary_buffs_pool_for_player indexes the
	-- pool table by it and inserts into the result, so omitting it is a
	-- nil-index crash at mission start.
	if entry.pool then
		-- icon_path is taken verbatim; icon is a short name resolved against the
		-- shipped Mortis set unless it already looks like a path. Two fields
		-- rather than one because a pack that keeps its full paths in a separate
		-- field should not have them silently prefixed into nonsense.
		local icon = entry.icon_path or entry.icon

		if icon and not entry.icon_path and not icon:find("/", 1, true) then
			icon = ICON_ROOT .. icon
		end

		HordesBuffsData[entry.id] = {
			title = _title_key(entry),
			description = _description_key(entry),
			icon = icon,
			is_family_buff = entry.is_family_buff or false,
			filter_category = entry.category,
		}
	end

	-- Note what is NOT done here: assigning the network id. That happens once
	-- after the whole batch is in, walking the names in sorted order, because an
	-- id has to be a pure function of the name set rather than of the order the
	-- entries happened to be written in.
	entry.owner = owner_name

	-- Replaced in place rather than appended when the id is already known.
	-- A mod reload re-runs its registration against a registry that outlived it
	-- (the state table is parked on `mod`), so without this every reload would
	-- append a second copy of every entry -- doubling the pool and the network
	-- name list, which the ident handshake compares element by element.
	local previous = state.by_id[entry.id]

	if previous then
		for i = 1, #state.entries do
			if state.entries[i].id == entry.id then
				state.entries[i] = entry

				break
			end
		end
	else
		state.entries[#state.entries + 1] = entry
	end

	state.by_id[entry.id] = entry

	if entry.pool and entry.default_off then
		state.default_off[entry.id] = true
	end

	-- Pool membership. Gated buffs stay out until their prerequisite lands;
	-- everything else joins the generic legendary pool, which is what makes it
	-- rollable at all.
	if entry.pool and not registry.has_prerequisites(entry.id) then
		local generic = MissionBuffsAllowedBuffs.legendary_buffs.generic

		for _, existing in ipairs(generic) do
			if existing == entry.id then
				return
			end
		end

		generic[#generic + 1] = entry.id
	end
end

-- The public entry point.
--
--   register_buffs(my_mod, entries, { prefix = "mymod_", category = "mymod" })
--
-- Returns the number registered and an array of problem strings. Every entry is
-- validated and registered independently, and one bad entry never takes the rest
-- of the addon -- or this mod -- down with it.
registry.register_buffs = function (addon_mod, entries, opts)
	opts = opts or {}

	local owner_name = "unknown"

	if type(addon_mod) == "table" and addon_mod.get_name then
		local ok, name = pcall(addon_mod.get_name, addon_mod)

		owner_name = ok and name or owner_name
	elseif _is_string(addon_mod) then
		owner_name = addon_mod
	end

	if type(entries) ~= "table" then
		mod:error("register_buffs(%s): entries must be an array of catalogue entries", owner_name)

		return 0, { "entries must be an array" }
	end

	-- Explicit prefixes are the v1 contract for already shipped full IDs.
	-- New callers get owner-scoped names by default, including helper templates
	-- and derived localization keys. namespaced=true also opts legacy callers in.
	local namespaced = opts.namespaced == true or opts.prefix == nil
	local prefix = namespaced and _id_prefix(owner_name) or opts.prefix
	local category = opts.category or (namespaced and registry.buff_id(owner_name, "category") or DEFAULT_CATEGORY)

	registry.register_category(category, {
		label = opts.category_label or owner_name,
		owner = owner_name,
		weight = opts.category_weight,
	})

	local registered = 0
	local problems = {}
	local warnings = {}
	local globals = {}

	for i = 1, #entries do
		local entry = entries[i]
		if namespaced then entry = _prepare_entry(entry, owner_name) end
		local entry_problems = {}

		-- `skip` lets a pack keep an entry in its catalogue without registering
		-- it -- for something core already owns, or a card being held back.
		-- Silent by design: it is a decision, not a fault.
		local skipped = type(entry) == "table" and entry.skip

		if not skipped then
			_validate(entry, prefix, owner_name, entry_problems, warnings)
		end

		if not skipped and #entry_problems == 0 then
			entry.category = entry.category or category

			if not registry.is_registered_category(entry.category) then
				registry.register_category(entry.category, { label = owner_name, owner = owner_name })
			end

			-- The factory runs inside the pcall too: an addon's template
			-- function is arbitrary code and this is the boundary.
			local ok, err = pcall(function ()
				local template = _build_template(entry)

				_validate_template(entry.id, template, entry_problems, warnings)

				if #entry_problems == 0 then
					-- Register the table we validated; factories may have state
					-- and must not run twice for one registration.
					_register_one(entry, owner_name, template)

					for key, value in pairs(_card_strings(entry)) do
						globals[key] = value
					end

					registered = registered + 1
				end
			end)

			if not ok then
				entry_problems[#entry_problems + 1] = string.format("%s: registration failed: %s",
					tostring(entry.id), tostring(err))
			end
		end

		for _, problem in ipairs(entry_problems) do
			problems[#problems + 1] = problem
		end
	end

	-- Network ids last, and for the whole registry rather than just this batch,
	-- so they are assigned in sorted name order. Doing it per entry as they were
	-- registered would make an id depend on the order the catalogue was written
	-- in, and two peers whose catalogues agree would still disagree about what
	-- an id means -- which is a hard crash on the other machine.
	registry.register_network_lookup()

	-- One-way: add_global_localize_strings refuses to overwrite a key it already
	-- holds, so a mod reload keeps the card text from the first load and editing
	-- a description needs a full restart to see.
	if next(globals) then
		mod:add_global_localize_strings(globals)
	end

	-- Capped, then counted.
	--
	-- Loud is right for a rejected buff -- the quiet version is a card in the
	-- wild that crashes when somebody picks it -- but "loud" stops meaning
	-- anything at 140 lines. A pack of 190 entries with no card text produced
	-- exactly that, and it buried everything else in the log it was competing
	-- with. Enough lines to diagnose, then a number.
	local function _report(list, level, verb)
		local shown = math.min(#list, LOG_LINE_CAP)

		for i = 1, shown do
			level(mod, "[%s] %s", owner_name, list[i])
		end

		if #list > shown then
			level(mod, "[%s] ... and %d more %s not listed (there are %d in total)",
				owner_name, #list - shown, verb, #list)
		end
	end

	_report(problems, mod.error, "rejections")
	_report(warnings, mod.warning, "warnings")

	mod:info("registered %d buff(s) from %s in category '%s'%s%s",
		registered, owner_name, category,
		#problems > 0 and string.format(" - %d REJECTED", #problems) or "",
		#warnings > 0 and string.format(" - %d registered with a warning", #warnings) or "")

	return registered, problems, warnings
end

-- ---------------------------------------------------------------------------
-- Lifecycle events
-- ---------------------------------------------------------------------------
--
-- For an addon that carries per-run state of its own -- a currency, a
-- checkpoint, anything that has to start clean and be written down at the end.
-- Buffs themselves need none of this; the buff system already knows when to
-- apply them.
--
--   EVENTS = "run_start" | "run_end" | "mission_start" | "mission_end"
--
-- A callback that throws is caught and reported rather than being allowed to
-- take the run down with it: these fire from inside mission setup and teardown,
-- where an uncaught error is a hard crash rather than a bad frame.
local EVENTS = {
	run_start = true,
	run_end = true,
	mission_start = true,
	mission_end = true,
}

registry.subscribe = function (addon_mod, event, fn)
	if not EVENTS[event] then
		mod:error("subscribe: '%s' is not a lifecycle event", tostring(event))

		return false
	end

	if type(fn) ~= "function" then
		mod:error("subscribe(%s): callback must be a function", tostring(event))

		return false
	end

	local owner = "unknown"

	if type(addon_mod) == "table" and addon_mod.get_name then
		local ok, name = pcall(addon_mod.get_name, addon_mod)

		owner = ok and name or owner
	elseif _is_string(addon_mod) then
		owner = addon_mod
	end

	state.listeners[event] = state.listeners[event] or {}
	state.listeners[event][owner] = fn

	return true
end

registry.notify = function (event, ...)
	local listeners = state.listeners[event]

	if not listeners then
		return
	end

	for owner, fn in pairs(listeners) do
		local ok, err = pcall(fn, ...)

		if not ok then
			mod:error("[%s] '%s' callback failed: %s", tostring(owner), tostring(event), tostring(err))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Reading the registry back
-- ---------------------------------------------------------------------------

registry.entries = function ()
	return state.entries
end

registry.entry = function (buff_name)
	return state.by_id[buff_name]
end

registry.owns = function (buff_name)
	return state.by_id[buff_name] ~= nil
end

-- Whether a buff template exists at all -- shipped, ours or an addon's.
--
-- Asked by anything that has a buff NAME from outside the current session and
-- has to grant it: a carried run, a saved loadout. A name written down while an
-- addon was installed outlives the addon, and granting a missing template
-- crashes rather than doing nothing.
registry.template_exists = function (buff_name)
	return BuffTemplates[buff_name] ~= nil
end

registry.default_off = function ()
	return state.default_off
end

-- Shared counter table, so an addon's procs show up in /cw_verify alongside this
-- mod's own. Keys are free-form; what a counter means belongs in a comment next
-- to the code that bumps it, not in a label table here that goes stale.
registry.counters = function ()
	return state.counters
end

registry.count = function (key)
	state.counters[key] = (state.counters[key] or 0) + 1
end

-- Live state that cannot be a counter because it is a reading rather than a
-- tally -- a ramp's current stacks, say.
registry.register_reading = function (reading)
	state.readings[#state.readings + 1] = reading
end

registry.readings = function ()
	return state.readings
end

-- Per mission, so a count answers "did it fire in this one" rather than
-- accumulating across a run and looking healthy on stale numbers.
registry.reset_counters = function ()
	table.clear(state.counters)
end

return registry
