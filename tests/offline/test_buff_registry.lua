-- The addon API. Registration writes into the game's own settings tables, so
-- these tests do too rather than against a fixture -- the whole point of the
-- registry is that the result is indistinguishable from a shipped buff, and a
-- hand-written stand-in would happily agree with a registration that had drifted.
--
-- Most of what is asserted here fails SILENTLY in the real game, and two of the
-- failures (a missing template.name, a missing network id) only crash when the
-- buff is picked -- long after the card rendered perfectly.

local harness, a = ...

local BUFFS = "scripts/settings/buff/buff_templates"
local HORDES = "scripts/settings/buff/hordes_buffs/hordes_buffs_data"
local ALLOWED = "scripts/managers/mission_buffs/mission_buffs_allowed_buffs"

local PREFIX = "testaddon_"

local function load_registry()
	require(BUFFS)
	require(HORDES)
	require(ALLOWED)

	return harness.load("buff_registry")
end

-- Everything registration touches is a table the game owns and every other test
-- shares, so each case runs inside a cleanup that puts them back. Anything
-- carrying the test prefix is ours by construction.
--
-- NetworkLookup is faked rather than skipped: "the id was appended, to both
-- directions of a bidirectional table" is one of the two assertions that stands
-- between a working card and a crash on pick.
local function sandboxed(fn)
	return function (assert_)
		local templates = require(BUFFS)
		local hordes = require(HORDES)
		local generic = require(ALLOWED).legendary_buffs.generic
		local generic_length = #generic

		_G.NetworkLookup = { buff_templates = {} }

		local ok, err = pcall(fn, assert_, {
			templates = templates,
			hordes = hordes,
			generic = generic,
			lookup = _G.NetworkLookup.buff_templates,
		})

		for i = #generic, generic_length + 1, -1 do
			generic[i] = nil
		end

		for name in pairs(templates) do
			if type(name) == "string" and name:sub(1, #PREFIX) == PREFIX then
				templates[name] = nil
			end
		end

		for name in pairs(hordes) do
			if type(name) == "string" and name:sub(1, #PREFIX) == PREFIX then
				hordes[name] = nil
			end
		end

		_G.NetworkLookup = nil

		if not ok then
			error(err, 0)
		end
	end
end

-- REMOVE is a sentinel because `{ stat_buffs = nil }` is simply an empty table
-- in Lua -- the key is not there to be iterated, so an override cannot delete a
-- field by setting it to nil.
local REMOVE = {}

local function entry(id, overrides)
	local base = {
		id = PREFIX .. id,
		pool = true,
		icon = "hordes_buff_damage_increase",
		title = { en = "Test Buff" },
		description = { en = "Does a thing." },
		stat_buffs = {},
	}

	for key, value in pairs(overrides or {}) do
		base[key] = value ~= REMOVE and value or nil
	end

	return base
end

local function register(registry, entries)
	return registry.register_buffs("TestAddon", entries, {
		prefix = PREFIX,
		category = "testaddon",
		category_label = "Test Addon",
	})
end

return {
	{ "a valid entry gets all five registrations", sandboxed(function (a, t)
		local registry = load_registry()
		local count = register(registry, { entry("basic") })

		a.eq(count, 1, "registered count")

		local name = PREFIX .. "basic"
		local template = t.templates[name]

		a.truthy(template, "BuffTemplates entry")

		-- Not cosmetic. BuffExtensionBase._add_buff uses this as a table key,
		-- and a nil key is "table index is nil" the moment the buff is applied.
		a.eq(template.name, name, "template.name matches its key")

		local data = t.hordes[name]

		a.truthy(data, "HordesBuffsData entry")

		-- init_legendary_buffs_pool_for_player indexes the pool table by this
		-- and inserts into the result, so a missing one is a nil-index crash at
		-- mission start, a long way from the buff that caused it.
		a.eq(data.filter_category, "testaddon", "filter_category")
		a.contains(t.generic, name, "legendary generic pool")

		-- Bidirectional, exactly as the engine builds it.
		a.eq(t.lookup[name], 1, "network id for the name")
		a.eq(t.lookup[1], name, "name for the network id")
	end) },

	{ "a short icon name is resolved against the shipped set, a path is left alone", sandboxed(function (a, t)
		local registry = load_registry()

		register(registry, {
			entry("short_icon"),
			entry("full_icon", { icon = "content/ui/textures/icons/talents/zealot/zealot_blitz_throwing_knife" }),
		})

		a.eq(t.hordes[PREFIX .. "short_icon"].icon,
			"content/ui/textures/icons/buffs/hud/horde_buffs/small_buffs/hordes_buff_damage_increase",
			"short name resolved")
		a.eq(t.hordes[PREFIX .. "full_icon"].icon,
			"content/ui/textures/icons/talents/zealot/zealot_blitz_throwing_knife",
			"full path left alone")
	end) },

	{ "card text reaches the global localization database with its values substituted", sandboxed(function (a)
		local registry = load_registry()

		register(registry, {
			entry("worded", {
				description = { en = "Increases damage by %s.", ko = "피해량이 %s 증가합니다." },
				values = { "15%%" },
			}),
		})

		local key = "loc_" .. PREFIX .. "worded_description"
		local translations = harness.global_localization[key]

		a.truthy(translations, "description in the global database")

		-- The %s is filled in at registration because {token} expansion is
		-- unreachable for a mod-registered key: DMF's hook answers the lookup
		-- and returns before the game's localize ever runs.
		a.eq(translations.en, "Increases damage by 15%%.", "English")

		-- Per language, because the sentence around the value differs and the
		-- value does not.
		a.eq(translations.ko, "피해량이 15%% 증가합니다.", "Korean")
	end) },

	{ "an un-namespaced id is refused", sandboxed(function (a, t)
		local registry = load_registry()
		local count, problems = registry.register_buffs("TestAddon", {
			{ id = "damage_boost", pool = true, stat_buffs = {}, title = { en = "x" }, description = { en = "y" } },
		}, { prefix = PREFIX, category = "testaddon" })

		a.eq(count, 0, "registered count")
		a.gt(#problems, 0, "problem count")
		a.nil_(t.templates.damage_boost, "BuffTemplates entry")
	end) },

	{ "an id that collides with an existing template is refused", sandboxed(function (a, t)
		-- Overwriting a template the game (or another addon) already owns is
		-- silent and catastrophic, so the guard is on BuffTemplates rather than
		-- on the registry's own list.
		--
		-- The colliding template is planted rather than borrowed from the loaded
		-- game data: buff_templates cannot fully load outside the game, so a
		-- test that picked a real shipped name would pass vacuously here and
		-- prove nothing.
		local registry = load_registry()
		local name = PREFIX .. "already_taken"

		t.templates[name] = { name = name, class_name = "buff" }

		local count, problems = register(registry, { entry("already_taken") })

		a.eq(count, 0, "registered count")
		a.gt(#problems, 0, "problem count")
		a.eq(t.templates[name].class_name, "buff", "the existing template is untouched")
	end) },

	{ "a stacking template with no cap warns but still registers", sandboxed(function (a)
		-- max_stacks is not the limit despite the name -- it only makes the buff
		-- stackable at all. Setting it alone gives an unbounded ramp that
		-- reports itself as 158/20 stacks with nothing in the log.
		--
		-- A warning and not a rejection, deliberately: it only matters for a
		-- template something adds repeatedly, and refusing the entry outright
		-- turned two of this mod's own working buffs off with no symptom beyond
		-- two cards that stopped being offered.
		local registry = load_registry()
		local count, problems, warnings = register(registry, {
			entry("uncapped", {
				stat_buffs = REMOVE,
				template = function ()
					return { class_name = "buff", max_stacks = 20 }
				end,
			}),
		})

		a.eq(count, 1, "registered count")
		a.count(problems, 0, "problems")
		a.gt(#warnings, 0, "warning count")
	end) },

	{ "a one-stack controller needs no cap and warns about nothing", sandboxed(function (a)
		-- The shape both ramp controllers in this mod use: max_stacks = 1, no
		-- cap, nothing ever adding a second stack.
		local registry = load_registry()
		local count, problems, warnings = register(registry, {
			entry("controller", {
				stat_buffs = REMOVE,
				template = function ()
					return { class_name = "proc_buff", max_stacks = 1 }
				end,
			}),
		})

		a.eq(count, 1, "registered count")
		a.count(problems, 0, "problems")
		a.count(warnings, 0, "warnings")
	end) },

	{ "card text problems warn but never cost you the card", sandboxed(function (a)
		-- Two separate faults, both cosmetic and both worth saying out loud: a
		-- lone %% makes DMF's safe_string_format return NIL so the title
		-- silently becomes nil, and a missing key renders the raw key.
		--
		-- Neither stops the buff working, so neither rejects it. Refusing a
		-- functioning gameplay card over its wording is the same over-strictness
		-- that briefly switched off two of this mod's own buffs -- and it turned
		-- 70 cards of a third-party pack off in one go before this was fixed.
		local registry = load_registry()

		local count, problems, warnings = register(registry, {
			entry("bad_format", { description = { en = "Increases damage by 15%." } }),
			entry("no_text_at_all", { title = REMOVE, description = REMOVE }),
		})

		a.eq(count, 2, "registered count")
		a.count(problems, 0, "problems")
		a.gt(#warnings, 0, "warning count")
	end) },

	{ "an entry marked skip is left alone entirely", sandboxed(function (a, t)
		-- How a pack keeps something in its catalogue that core already owns.
		local registry = load_registry()
		local count, problems = register(registry, {
			entry("wanted"),
			entry("not_wanted", { skip = true }),
		})

		a.eq(count, 1, "registered count")
		a.count(problems, 0, "problems - skipping is a decision, not a fault")
		a.nil_(t.templates[PREFIX .. "not_wanted"], "BuffTemplates entry")
	end) },

	{ "an entry with neither a template nor stat_buffs is refused", sandboxed(function (a)
		local registry = load_registry()
		local count = register(registry, { entry("empty", { stat_buffs = REMOVE }) })

		a.eq(count, 0, "registered count")
	end) },

	{ "one bad entry does not stop the others", sandboxed(function (a, t)
		local registry = load_registry()
		local count, problems = register(registry, {
			entry("good_one"),
			entry("bad_one", { id = "unprefixed_bad" }),
			entry("good_two"),
		})

		a.eq(count, 2, "registered count")
		a.eq(#problems, 1, "problem count")
		a.truthy(t.templates[PREFIX .. "good_one"], "first good entry")
		a.truthy(t.templates[PREFIX .. "good_two"], "second good entry")
	end) },

	{ "a helper buff is registered and networked but never offered", sandboxed(function (a, t)
		local registry = load_registry()
		local name = PREFIX .. "helper"

		register(registry, { entry("helper", { pool = false, title = REMOVE, description = REMOVE }) })

		a.truthy(t.templates[name], "BuffTemplates entry")
		a.truthy(t.lookup[name], "network id")
		a.nil_(t.hordes[name], "no card data")
		a.not_contains(t.generic, name, "legendary generic pool")
	end) },

	{ "registering again replaces rather than duplicating", sandboxed(function (a, t)
		-- A mod reload re-runs its registration against a registry that outlived
		-- it, because the state lives on the mod table. Appending a second copy
		-- would double the pool and the name list the peer handshake compares
		-- element by element.
		local registry = load_registry()

		register(registry, { entry("twice") })
		register(registry, { entry("twice") })

		local seen = 0

		for _, name in ipairs(registry.pool_names()) do
			if name == PREFIX .. "twice" then
				seen = seen + 1
			end
		end

		a.eq(seen, 1, "times listed in the pool")
		a.count(registry.all_template_names(), 1, "template names")
	end) },

	{ "network ids are assigned in sorted name order", sandboxed(function (a, t)
		-- An id has to be a pure function of the name SET, not of registration
		-- order, or two peers running the same mods disagree about what an id
		-- means -- and a mismatched id is a hard crash on the other machine.
		local registry = load_registry()

		register(registry, { entry("zebra"), entry("alpha") })

		a.eq(t.lookup[1], PREFIX .. "alpha", "first id")
		a.eq(t.lookup[2], PREFIX .. "zebra", "second id")
	end) },

	{ "a gated buff stays out of the pool until its prerequisite is held", sandboxed(function (a, t)
		local registry = load_registry()

		register(registry, {
			entry("base"),
			entry("upgrade", { upgrade_of = PREFIX .. "base" }),
		})

		local upgrade = PREFIX .. "upgrade"

		-- Registered like any other buff -- it needs its template and its
		-- network id whether or not it is currently offerable.
		a.truthy(t.templates[upgrade], "BuffTemplates entry")
		a.truthy(t.lookup[upgrade], "network id")

		-- But not in the pool, because the pool is built once per player at
		-- spawn and buffs are popped out of it as they are handed over.
		a.not_contains(t.generic, upgrade, "legendary generic pool")

		a.falsy(registry.is_unlocked(upgrade, {}), "unlocked with nothing held")
		a.truthy(registry.is_unlocked(upgrade, { [PREFIX .. "base"] = true }), "unlocked with the base held")
		a.eq(registry.locked_names({})[upgrade], true, "listed as locked")
		a.nil_(registry.locked_names({ [PREFIX .. "base"] = true })[upgrade], "not locked once the base is held")
	end) },

	{ "requires_any needs only one of its options", sandboxed(function (a)
		local registry = load_registry()

		register(registry, {
			entry("left"),
			entry("right"),
			entry("either", { requires_any = { PREFIX .. "left", PREFIX .. "right" } }),
		})

		local either = PREFIX .. "either"

		a.falsy(registry.is_unlocked(either, {}), "nothing held")
		a.truthy(registry.is_unlocked(either, { [PREFIX .. "left"] = true }), "left held")
		a.truthy(registry.is_unlocked(either, { [PREFIX .. "right"] = true }), "right held")
	end) },

	{ "newly_unlocked reports only what just became available", sandboxed(function (a)
		local registry = load_registry()

		register(registry, {
			entry("root"),
			entry("tier_one", { unlock_after = PREFIX .. "root" }),
		})

		local fresh = registry.newly_unlocked({ [PREFIX .. "root"] = true }, {})

		a.count(fresh, 1, "newly unlocked")
		a.eq(fresh[1].name, PREFIX .. "tier_one", "name")
		a.eq(fresh[1].category, "testaddon", "category")

		-- Already in the pool, so not new any more.
		a.count(registry.newly_unlocked({ [PREFIX .. "root"] = true }, { [PREFIX .. "tier_one"] = true }), 0,
			"newly unlocked when already pooled")
	end) },

	{ "has_any_prerequisites is false until something is gated", sandboxed(function (a)
		-- The per-frame unlock check early-outs on this, so it is the entire
		-- cost of the feature for an install with no upgrade cards.
		local registry = load_registry()

		register(registry, { entry("plain") })
		a.falsy(registry.has_any_prerequisites(), "with only ungated buffs")

		register(registry, { entry("gated", { unlock_after = PREFIX .. "plain" }) })
		a.truthy(registry.has_any_prerequisites(), "once one is gated")
	end) },

	{ "prerequisite_names lists only what something depends on", sandboxed(function (a)
		local registry = load_registry()

		register(registry, {
			entry("root"),
			entry("unrelated"),
			entry("child", { upgrade_of = PREFIX .. "root" }),
		})

		local names = registry.prerequisite_names()

		a.truthy(names[PREFIX .. "root"], "the depended-on buff")
		a.falsy(names[PREFIX .. "unrelated"], "a buff nothing depends on")
		a.falsy(names[PREFIX .. "child"], "the dependent itself")
	end) },

	{ "gated entries are listed for the toggle view even though they are unpooled", sandboxed(function (a, t)
		-- They are deliberately absent from legendary_buffs.generic, so a view
		-- built from that pool alone would never show an upgrade card and the
		-- player could not switch one off before it unlocked.
		local registry = load_registry()

		register(registry, {
			entry("base_card"),
			entry("upgrade_card", { unlock_after = PREFIX .. "base_card" }),
		})

		a.not_contains(t.generic, PREFIX .. "upgrade_card", "legendary generic pool")

		local gated = registry.gated_pool_entries()

		a.count(gated, 1, "gated pool entries")
		a.eq(gated[1].id, PREFIX .. "upgrade_card", "the gated entry")
	end) },

	{ "a registered category is reported, an unregistered one is not", sandboxed(function (a)
		local registry = load_registry()

		register(registry, { entry("categorised") })

		a.truthy(registry.is_registered_category("testaddon"), "registered category")
		a.eq(registry.category_label("testaddon"), "Test Addon", "label")
		a.falsy(registry.is_registered_category("nobody_registered_this"), "unregistered category")
		a.contains(registry.category_ids(), "testaddon", "category ids")
	end) },

	{ "template_exists sees shipped, registered and missing names apart", sandboxed(function (a)
		local registry = load_registry()

		register(registry, { entry("real") })

		a.truthy(registry.template_exists(PREFIX .. "real"), "a registered buff")
		a.falsy(registry.template_exists(PREFIX .. "never_registered"), "a name nothing defines")
	end) },

	{ "lifecycle callbacks fire, and one that throws does not stop the others", sandboxed(function (a)
		-- These fire from inside mission setup and teardown, where an uncaught
		-- error is a hard crash rather than a bad frame.
		local registry = load_registry()
		local seen = {}

		registry.subscribe("AddonOne", "run_start", function (payload)
			seen[#seen + 1] = "one"
		end)

		registry.subscribe("AddonTwo", "run_start", function ()
			error("deliberate")
		end)

		registry.subscribe("AddonThree", "run_start", function ()
			seen[#seen + 1] = "three"
		end)

		registry.notify("run_start")

		a.count(seen, 2, "callbacks that ran despite the thrower")
	end) },

	{ "subscribing again replaces the previous callback for that owner", sandboxed(function (a)
		local registry = load_registry()
		local calls = 0

		registry.subscribe("AddonOne", "mission_start", function ()
			calls = calls + 1
		end)

		registry.subscribe("AddonOne", "mission_start", function ()
			calls = calls + 1
		end)

		registry.notify("mission_start")

		a.eq(calls, 1, "callbacks run after re-subscribing")
	end) },

	{ "an unknown lifecycle event is refused", sandboxed(function (a)
		local registry = load_registry()

		a.falsy(registry.subscribe("AddonOne", "not_an_event", function () end), "subscribe result")
	end) },
}
