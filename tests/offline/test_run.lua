-- run.lua holds what a player carries between missions and takes what they
-- already have out of the next mission's offer pools.
--
-- Both halves have shipped broken before, and both failures were silent: a
-- capture that replaced instead of merging wiped a rejoined player's whole set,
-- and pools rebuilt without trimming offered picks the player already held, so
-- a card could contain three buffs that did nothing.

local harness = ...

-- ---------------------------------------------------------------------------
-- Fakes
-- ---------------------------------------------------------------------------

local function player(account_id, name, opts)
	opts = opts or {}

	return {
		is_human_controlled = function () return opts.human ~= false end,
		account_id = function () return account_id end,
		peer_id = function () return opts.peer_id or "peer_" .. tostring(account_id) end,
		local_player_id = function () return opts.local_player_id or 1 end,
		name = function () return name or ("player_" .. tostring(account_id)) end,
	}
end

-- A bot: BotPlayer extends HumanPlayer, so account_id exists, is callable, and
-- answers nil. Keying on it without care is "table index is nil".
local function bot(name)
	return {
		is_human_controlled = function () return false end,
		account_id = function () return nil end,
		peer_id = function () return "host_peer" end,
		local_player_id = function () return 2 end,
		name = function () return name or "BOT" end,
	}
end

-- `given` maps a player to the buffs that player was handed this mission, as
-- the engine reports them: [buff_name] = { stacks = n }.
local function manager(given, families, pools)
	local persistent = {
		get_buffs_given_to_player = function (_self, p)
			return given and given[p] or nil
		end,
		get_player_priority_family_buffs_available = function (_self, p)
			return pools and pools.priority and pools.priority[p] or nil
		end,
		get_player_family_buffs_available = function (_self, p)
			return pools and pools.family and pools.family[p] or nil
		end,
		get_legendary_buffs_available_for_player = function (_self, p)
			return pools and pools.legendary and pools.legendary[p] or nil
		end,
	}

	return {
		_mission_buffs_handler = {
			_persistent_data = persistent,
			get_buff_family_selected_by_player = function (_self, p)
				return families and families[p] or nil
			end,
		},
	}
end

local function with_players(...)
	local list = { ... }

	_G.Managers.player.human_players = function ()
		return list
	end

	_G.Managers.player.local_player_safe = function ()
		return list[1]
	end

	return list
end

local function stacks(t)
	local out = {}

	for name, n in pairs(t) do
		out[name] = { stacks = n }
	end

	return out
end

return {
	-- -----------------------------------------------------------------------
	-- State machine
	-- -----------------------------------------------------------------------

	{ "a fresh run is neither launched nor active", function (a)
		local run = harness.load("run")

		a.falsy(run.is_launched(), "is_launched")
		a.falsy(run.is_active(), "is_active")
		a.eq(run.depth(), 0, "depth")
		a.falsy(run.has_carryover(), "has_carryover")
	end },

	{ "launched and active are independent", function (a)
		-- Gating activation on `active` would be circular: it is set as a
		-- consequence of the buff system starting.
		local run = harness.load("run")

		run.mark_launched()

		a.truthy(run.is_launched(), "is_launched")
		a.falsy(run.is_active(), "is_active")
	end },

	{ "reset clears everything a run accumulated", function (a)
		local run = harness.load("run")
		local state = run.state()

		run.mark_launched()
		state.active = true
		state.missions_completed = 3
		state.family = "fire"
		state.buffs = { hordes_buff_a = 2 }
		state.players = { acct = {} }
		state.next_mission = { mission_name = "km_enforcer" }
		state.params = { challenge = 3 }
		state.restore_pending = true

		run.reset("test")

		a.falsy(run.is_launched(), "is_launched")
		a.falsy(run.is_active(), "is_active")
		a.eq(run.depth(), 0, "depth")
		a.nil_(state.family, "family")
		a.size(state.buffs, 0, "buffs")
		a.size(state.players, 0, "players")
		a.nil_(state.next_mission, "next_mission")
		a.nil_(state.params, "params")
		a.nil_(state.restore_pending, "restore_pending")
	end },

	{ "should_restore only fires for a queued transition", function (a)
		-- has_carryover goes true the moment you pick a family, in the very
		-- mission that produced it. Restoring on that duplicated every buff and
		-- compounded on each hop.
		local run = harness.load("run")
		local state = run.state()

		state.active = true
		state.buffs = { hordes_buff_a = 1 }

		a.truthy(run.has_carryover(), "has_carryover")
		a.falsy(run.should_restore(), "should_restore without restore_pending")

		state.restore_pending = true

		a.truthy(run.should_restore(), "should_restore with restore_pending")
	end },

	-- -----------------------------------------------------------------------
	-- Offer pools
	-- -----------------------------------------------------------------------

	{ "trim_pools takes carried buffs out of every pool", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		run.state().players.acct_1 = { buffs = { carried_a = 1, carried_b = 2 }, name = "Alice" }

		local pools = {
			priority = { [p] = { "carried_a", "fresh_1" } },
			family = { [p] = { "fresh_2", "carried_b", "fresh_3" } },
			legendary = { [p] = { generic = { "carried_a", "fresh_4" } } },
		}

		local removed = run.trim_pools(manager(nil, nil, pools), p)

		a.eq(removed, 3, "removed")
		a.eq(table.concat(pools.priority[p], ","), "fresh_1", "priority pool")
		a.eq(table.concat(pools.family[p], ","), "fresh_2,fresh_3", "family pool")
		a.eq(table.concat(pools.legendary[p].generic, ","), "fresh_4", "legendary generic pool")
	end },

	-- The legendary pool is a map of filter category to array, not one flat
	-- list. Treating it as flat silently trimmed nothing.
	{ "trim_pools walks every legendary category", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		run.state().players.acct_1 = { buffs = { carried = 1 }, name = "Alice" }

		local legendary = {
			generic = { "carried", "g1" },
			psyker = { "carried", "p1" },
			ogryn = { "o1" },
		}

		local removed = run.trim_pools(manager(nil, nil, { legendary = { [p] = legendary } }), p)

		a.eq(removed, 2, "removed")
		a.eq(table.concat(legendary.generic, ","), "g1", "generic")
		a.eq(table.concat(legendary.psyker, ","), "p1", "psyker")
		a.eq(table.concat(legendary.ogryn, ","), "o1", "ogryn untouched")
	end },

	{ "trim_pools leaves a pool alone when nothing is carried", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")
		local pool = { "a", "b", "c" }

		local removed = run.trim_pools(manager(nil, nil, { family = { [p] = pool } }), p)

		a.eq(removed, 0, "removed")
		a.count(pool, 3, "pool")
	end },

	{ "trim_pools is idempotent", function (a)
		-- Called from two places on purpose, so running twice must not differ
		-- from running once.
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		run.state().players.acct_1 = { buffs = { carried = 1 }, name = "Alice" }

		local pools = { family = { [p] = { "carried", "fresh" } } }
		local m = manager(nil, nil, pools)

		a.eq(run.trim_pools(m, p), 1, "first call")
		a.eq(run.trim_pools(m, p), 0, "second call")
		a.eq(table.concat(pools.family[p], ","), "fresh", "pool")
	end },

	{ "trim_pools does nothing for a client", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		harness.mod.is_host = function () return false end
		run.state().players.acct_1 = { buffs = { carried = 1 } }

		local pool = { "carried" }

		a.eq(run.trim_pools(manager(nil, nil, { family = { [p] = pool } }), p), 0, "removed")
		a.count(pool, 1, "pool untouched")
	end },

	-- -----------------------------------------------------------------------
	-- Capture
	-- -----------------------------------------------------------------------

	{ "capture records a player's buffs under their account id", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		with_players(p)
		harness.mod.manager = manager({ [p] = stacks({ buff_a = 1, buff_b = 2 }) }, { [p] = "fire" })

		a.truthy(run.capture(true), "capture")

		local record = run.state().players.acct_1

		a.truthy(record, "record under account id")
		a.eq(record.buffs.buff_a, 1, "buff_a stacks")
		a.eq(record.buffs.buff_b, 2, "buff_b stacks")
		a.eq(record.family, "fire", "family")
		a.eq(record.name, "Alice", "name")
	end },

	-- The wipe. This mission's persistent data only knows what this mission
	-- handed out, so for a player who was absent it reads short -- and an
	-- earlier version replaced on that reading.
	{ "capture merges with what was already held", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		with_players(p)

		harness.mod.manager = manager({ [p] = stacks({ buff_a = 1, buff_b = 1, buff_c = 1 }) })
		run.capture(true)

		a.size(run.state().players.acct_1.buffs, 3, "buffs after first capture")

		-- Second mission: the manager has only ever seen one of them.
		harness.mod.manager = manager({ [p] = stacks({ buff_d = 1 }) })
		run.capture(true)

		local buffs = run.state().players.acct_1.buffs

		a.size(buffs, 4, "buffs after second capture")
		a.eq(buffs.buff_a, 1, "buff_a survived")
		a.eq(buffs.buff_c, 1, "buff_c survived")
		a.eq(buffs.buff_d, 1, "buff_d added")
	end },

	{ "capture keeps the higher stack count", function (a)
		-- Within a run buffs only accumulate, so a lower reading is missing
		-- information rather than a removal.
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		with_players(p)

		harness.mod.manager = manager({ [p] = stacks({ buff_a = 5 }) })
		run.capture(true)

		harness.mod.manager = manager({ [p] = stacks({ buff_a = 2 }) })
		run.capture(true)

		a.eq(run.state().players.acct_1.buffs.buff_a, 5, "buff_a stacks")
	end },

	{ "capture with nothing given does not erase an existing record", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		with_players(p)

		harness.mod.manager = manager({ [p] = stacks({ buff_a = 3 }) })
		run.capture(true)

		harness.mod.manager = manager({ [p] = {} })
		run.capture(true)

		a.eq(run.state().players.acct_1.buffs.buff_a, 3, "buff_a stacks")
	end },

	{ "a player absent from this mission keeps their record", function (a)
		-- A client that dropped and has not come back yet.
		local run = harness.load("run")
		local alice = player("acct_1", "Alice")
		local bob = player("acct_2", "Bob")

		with_players(alice, bob)
		harness.mod.manager = manager({
			[alice] = stacks({ buff_a = 1 }),
			[bob] = stacks({ buff_b = 1 }),
		})
		run.capture(true)

		with_players(alice)
		harness.mod.manager = manager({ [alice] = stacks({ buff_a = 1 }) })
		run.capture(true)

		a.truthy(run.state().players.acct_2, "Bob's record survived his absence")
		a.eq(run.state().players.acct_2.buffs.buff_b, 1, "Bob's buff")
	end },

	-- The 1,422-append bug. Dropping this flag made the reconciliation re-apply
	-- the family every second, and the engine APPENDS a family's buffs to the
	-- offer pool rather than replacing them.
	{ "capture carries family_restored and restored across missions", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		with_players(p)
		harness.mod.manager = manager({ [p] = stacks({ buff_a = 1 }) })
		run.capture(true)

		run.state().players.acct_1.family_restored = true
		run.state().players.acct_1.restored = true

		run.capture(true)

		a.eq(run.state().players.acct_1.family_restored, true, "family_restored")
		a.eq(run.state().players.acct_1.restored, true, "restored")
	end },

	{ "capture keeps a previously chosen family when this mission reports none", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		with_players(p)
		harness.mod.manager = manager({ [p] = stacks({ buff_a = 1 }) }, { [p] = "critical" })
		run.capture(true)

		harness.mod.manager = manager({ [p] = stacks({ buff_a = 1 }) }, nil)
		run.capture(true)

		a.eq(run.state().players.acct_1.family, "critical", "family")
	end },

	{ "bots are not captured", function (a)
		-- BotPlayer extends HumanPlayer, so account_id exists, is callable and
		-- answers nil. Using it as a key is "table index is nil".
		local run = harness.load("run")
		local alice = player("acct_1", "Alice")

		with_players(alice, bot("BOT-1"))
		harness.mod.manager = manager({ [alice] = stacks({ buff_a = 1 }) })

		a.truthy(run.capture(true), "capture")
		a.size(run.state().players, 1, "captured players")
		a.truthy(run.state().players.acct_1, "Alice captured")
	end },

	{ "the local mirror follows the local player", function (a)
		local run = harness.load("run")
		local alice = player("acct_1", "Alice")
		local bob = player("acct_2", "Bob")

		with_players(alice, bob)
		harness.mod.manager = manager({
			[alice] = stacks({ mine = 1 }),
			[bob] = stacks({ theirs = 1 }),
		}, { [alice] = "fire" })

		run.capture(true)

		a.eq(run.state().buffs.mine, 1, "state.buffs carries my buff")
		a.nil_(run.state().buffs.theirs, "state.buffs does not carry Bob's")
		a.eq(run.state().family, "fire", "state.family")
	end },

	{ "capture refuses without a manager and says so", function (a)
		local run = harness.load("run")

		harness.mod.manager = nil

		a.falsy(run.capture(false), "capture")
		a.truthy(harness.logged("capture skipped"), "logged a reason")
	end },

	{ "capture refuses on a client", function (a)
		local run = harness.load("run")
		local p = player("acct_1", "Alice")

		with_players(p)
		harness.mod.is_host = function () return false end
		harness.mod.manager = manager({ [p] = stacks({ buff_a = 1 }) })

		a.falsy(run.capture(true), "capture")
		a.size(run.state().players, 0, "players")
	end },
}
