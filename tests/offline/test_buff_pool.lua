-- buff_pool decides which buffs may be rolled, and builds the catalogue the
-- toggle view is drawn from. It runs against the game's real allowed-buff
-- tables, so these tests do too -- a hand-written fixture would happily agree
-- with a catalogue that had drifted away from the game.

local harness, a = ...

local ALLOWED = "scripts/managers/mission_buffs/mission_buffs_allowed_buffs"
local HORDES = "scripts/settings/buff/hordes_buffs/hordes_buffs_data"

-- Loading order matters: a dependency that fails while an outer module is
-- mid-load memoises as an empty table, and every later assertion then passes
-- vacuously against nothing.
local function load_pool()
	require(HORDES)
	require(ALLOWED)

	return harness.load("buff_pool")
end

local function any_name(pool)
	for _, group in ipairs(pool.groups()) do
		if group.names[1] then
			return group.names[1]
		end
	end
end

return {
	-- This one exists so the rest cannot lie. Every assertion below is about
	-- real game data; if that data did not load, they would all pass against
	-- empty tables and the suite would be worthless.
	{ "the real engine buff data actually loaded", function (a)
		a.truthy(harness.engine_loaded(HORDES), "hordes_buffs_data loaded")
		a.truthy(harness.engine_loaded(ALLOWED), "mission_buffs_allowed_buffs loaded")

		local hordes = require(HORDES)
		local count = 0

		for _ in pairs(hordes) do
			count = count + 1
		end

		a.gt(count, 100, "hordes_buffs_data entry count")
	end },

	{ "the catalogue builds and every group has buffs in it", function (a)
		local pool = load_pool()
		local groups = pool.groups()

		a.gt(#groups, 0, "group count")

		for _, group in ipairs(groups) do
			a.truthy(group.id, "group id")
			a.gt(#group.names, 0, "names in group " .. tostring(group.id))
		end
	end },

	-- The check that fires when a game patch renames or drops a buff: we would
	-- go on offering a name the game no longer knows, and the pick would do
	-- nothing.
	{ "every catalogued buff resolves to a real data entry", function (a)
		local pool = load_pool()
		local hordes = require(HORDES)
		local orphans = {}

		for _, group in ipairs(pool.groups()) do
			for _, name in ipairs(group.names) do
				if hordes[name] == nil then
					orphans[#orphans + 1] = group.id .. "/" .. name
				end
			end
		end

		a.count(orphans, 0, "catalogued names with no HordesBuffsData entry")
	end },

	{ "no group lists the same buff twice", function (a)
		local pool = load_pool()

		for _, group in ipairs(pool.groups()) do
			local seen, dupes = {}, {}

			for _, name in ipairs(group.names) do
				if seen[name] then
					dupes[#dupes + 1] = name
				end

				seen[name] = true
			end

			a.count(dupes, 0, "duplicates in group " .. tostring(group.id))
		end
	end },

	-- Custom buffs are injected into legendary_buffs.generic so the game will
	-- roll them; the catalogue splits them back out by filter_category. If that
	-- split broke, ours would show up in the stock legendary tab.
	{ "custom buffs are split out of the generic legendary group", function (a)
		-- The category has to be REGISTERED for the split to happen, not merely
		-- named on the buff's card data. A filter_category nobody registered
		-- belongs to no addon, so its buffs stay in the generic group rather
		-- than conjuring a tab out of a typo.
		harness.load("buff_registry").register_category("custom", { label = "Custom" })

		local hordes = require(HORDES)
		hordes.cwah_test_marker = { filter_category = "custom", title = "loc_marker" }

		local allowed = require(ALLOWED)
		local generic = allowed.legendary_buffs and allowed.legendary_buffs.generic

		a.truthy(generic, "legendary_buffs.generic")
		generic[#generic + 1] = "cwah_test_marker"

		local pool = load_pool()
		local custom_group, generic_group

		for _, group in ipairs(pool.groups()) do
			if group.id == "custom" then
				custom_group = group
			elseif group.id == "legendary_generic" then
				generic_group = group
			end
		end

		-- Clean up the shared engine table before asserting, so a failure here
		-- cannot leak the marker into another test.
		generic[#generic] = nil
		hordes.cwah_test_marker = nil

		a.truthy(custom_group, "custom group exists once a custom buff is registered")
		a.contains(custom_group.names, "cwah_test_marker", "custom group")
		a.not_contains(generic_group.names, "cwah_test_marker", "generic legendary group")
	end },

	{ "everything is enabled on a fresh profile, and nothing is stored", function (a)
		local pool = load_pool()

		for _, group in ipairs(pool.groups()) do
			for _, name in ipairs(group.names) do
				a.truthy(pool.is_enabled(name), name .. " enabled by default")
			end
		end

		a.nil_(harness.settings.disabled_buffs, "disabled_buffs before any choice")
		a.nil_(harness.settings.enabled_buffs, "enabled_buffs before any choice")
		a.eq(pool.disabled_count(), 0, "disabled_count")
	end },

	{ "disabling a buff records it in the disabled set only", function (a)
		local pool = load_pool()
		local name = any_name(pool)

		pool.set_enabled(name, false)

		a.falsy(pool.is_enabled(name), name .. " enabled")
		a.eq(harness.settings.disabled_buffs[name], true, "disabled_buffs[" .. name .. "]")
		a.nil_(harness.settings.enabled_buffs[name], "enabled_buffs[" .. name .. "]")
		a.eq(pool.disabled_count(), 1, "disabled_count")
	end },

	{ "re-enabling clears the disabled entry rather than storing false", function (a)
		-- Storing false would work for the toggle but breaks the "has the
		-- player ever had an opinion" question the two-set design exists to
		-- answer.
		local pool = load_pool()
		local name = any_name(pool)

		pool.set_enabled(name, false)
		pool.set_enabled(name, true)

		a.truthy(pool.is_enabled(name), name .. " enabled")
		a.nil_(harness.settings.disabled_buffs[name], "disabled_buffs[" .. name .. "]")
		a.eq(pool.disabled_count(), 0, "disabled_count")
	end },

	-- SJSON cannot serialize a table with both an array and a hash part, and
	-- these land in user_settings.config through SJSON. Storing them as arrays
	-- would write a file the game cannot read back.
	{ "stored sets are name-keyed hashes with no array part", function (a)
		local pool = load_pool()
		local name = any_name(pool)

		pool.set_enabled(name, false)

		a.eq(#harness.settings.disabled_buffs, 0, "disabled_buffs array part")
		a.eq(#harness.settings.enabled_buffs, 0, "enabled_buffs array part")
	end },

	{ "a default-off buff stays off until switched on explicitly", function (a)
		local pool = load_pool()
		local name = any_name(pool)

		-- Written through the registry, which is where "default off" lives now:
		-- an entry registered with default_off = true lands in this same table,
		-- whether it came from this mod or an addon.
		harness.load("buff_registry").default_off()[name] = true

		a.falsy(pool.is_enabled(name), name .. " enabled before any choice")
		a.eq(pool.disabled_count(), 1, "disabled_count counts an untouched default-off buff")

		pool.set_enabled(name, true)

		a.truthy(pool.is_enabled(name), name .. " enabled after switching on")
		a.eq(harness.settings.enabled_buffs[name], true, "enabled_buffs[" .. name .. "]")
		a.eq(pool.disabled_count(), 0, "disabled_count")
	end },

	{ "group_counts reports enabled against total", function (a)
		local pool = load_pool()
		local group = pool.groups()[1]
		local on, total = pool.group_counts(group)

		a.eq(on, #group.names, "all on initially")
		a.eq(total, #group.names, "total")

		pool.set_enabled(group.names[1], false)

		on, total = pool.group_counts(group)

		a.eq(on, #group.names - 1, "one off")
		a.eq(total, #group.names, "total unchanged")
	end },

	{ "set_group_enabled switches a whole group at once", function (a)
		local pool = load_pool()
		local group = pool.groups()[1]

		pool.set_group_enabled(group, false)

		local on = pool.group_counts(group)

		a.eq(on, 0, "enabled in group after disabling it")
		a.eq(pool.disabled_count(), #group.names, "disabled_count")
	end },

	-- This is the payload: the exclusion table is what the buff system filters
	-- both offer pools through, so a name missing from here is a buff the
	-- player switched off and gets offered anyway.
	{ "apply_exclusions writes every disabled buff into the exclusion table", function (a)
		local pool = load_pool()
		local group = pool.groups()[1]

		pool.set_group_enabled(group, false)

		local exclude = {}
		local count = pool.apply_exclusions(exclude)

		a.eq(count, #group.names, "reported exclusion count")

		for _, name in ipairs(group.names) do
			a.eq(exclude[name], true, "exclude[" .. name .. "]")
		end
	end },

	-- Regression, found by this suite on its first run. The game lists the same
	-- grenade buff under every archetype that has grenades -- 21 names appear in
	-- more than one group -- so counting per catalogue entry told a player who
	-- had switched off one buff that six were off.
	{ "a buff in several groups counts once, not once per group", function (a)
		local pool = load_pool()
		local groups = pool.groups()
		local where, shared = {}, nil

		for _, group in ipairs(groups) do
			for _, name in ipairs(group.names) do
				where[name] = (where[name] or 0) + 1

				if where[name] > 1 and not shared then
					shared = name
				end
			end
		end

		a.truthy(shared, "found a buff listed under more than one group")
		a.gt(where[shared], 1, "group appearances of " .. tostring(shared))

		pool.set_enabled(shared, false)

		a.eq(pool.disabled_count(), 1, "disabled_count for one multi-group buff")

		local exclude = {}

		a.eq(pool.apply_exclusions(exclude), 1, "apply_exclusions count")
		a.size(exclude, 1, "exclude")
	end },

	{ "apply_exclusions excludes an untouched default-off buff", function (a)
		-- Walking the stored table instead of the catalogue would miss this
		-- one: it is in neither set, so it would leak back into the pool.
		local pool = load_pool()
		local name = any_name(pool)

		harness.load("buff_registry").default_off()[name] = true

		local exclude = {}
		pool.apply_exclusions(exclude)

		a.eq(exclude[name], true, "exclude[" .. name .. "]")
	end },

	{ "apply_exclusions is additive, not a replacement", function (a)
		-- The same table carries the run's already-owned buffs. Clobbering it
		-- would re-offer everything the player is already holding, which is the
		-- exact "pool fills with picks you already have" failure.
		local pool = load_pool()
		local exclude = { hordes_buff_already_owned = true }

		pool.set_enabled(any_name(pool), false)
		pool.apply_exclusions(exclude)

		a.eq(exclude.hordes_buff_already_owned, true, "pre-existing exclusion survived")
	end },

	{ "nothing is excluded when the player has switched nothing off", function (a)
		local pool = load_pool()
		local exclude = {}

		a.eq(pool.apply_exclusions(exclude), 0, "exclusion count")
		a.size(exclude, 0, "exclude")
	end },

	{ "every family is offered by default", function (a)
		local pool = load_pool()
		local allowed = require(ALLOWED)
		local builds = allowed.available_family_builds

		a.truthy(builds, "available_family_builds")
		a.gt(#builds, 0, "family count")
		a.count(pool.offered_families(), #builds, "offered families")
		a.eq(pool.family_count(), #builds, "family_count")
	end },

	{ "disabling a family removes it from the offer, not from the total", function (a)
		-- family_count is the size of the game's list, deliberately -- the UI
		-- uses it as the denominator. offered_families is the one that shrinks.
		local pool = load_pool()
		local total = pool.family_count()
		local first = pool.offered_families()[1]

		pool.set_family_offered(first, false)

		a.falsy(pool.is_family_offered(first), first .. " offered")
		a.not_contains(pool.offered_families(), first, "offered families")
		a.count(pool.offered_families(), total - 1, "offered families")
		a.eq(pool.family_count(), total, "family_count is unchanged")
	end },

	{ "re-offering a family clears the stored entry", function (a)
		local pool = load_pool()
		local first = pool.offered_families()[1]

		pool.set_family_offered(first, false)
		pool.set_family_offered(first, true)

		a.truthy(pool.is_family_offered(first), first .. " offered")
		a.nil_(harness.settings[pool.FAMILY_SETTING_ID][first], "stored disabled entry")
		a.eq(#harness.settings[pool.FAMILY_SETTING_ID], 0, "array part")
	end },

	{ "offered families keep the game's own order", function (a)
		-- The order the player sees them offered in, not alphabetical.
		local pool = load_pool()
		local builds = require(ALLOWED).available_family_builds
		local offered = pool.offered_families()

		for i, family in ipairs(offered) do
			a.eq(family, builds[i], "offered_families[" .. i .. "]")
		end
	end },
}
