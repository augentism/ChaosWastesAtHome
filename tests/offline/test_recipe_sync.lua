local harness = ...

local function with_host(test)
	local mod = harness.mod
	local old_get, old_managers, old_lookup, old_hook = get_mod, Managers, NetworkLookup, mod.hook
	local hooks, receive, sent = {}, nil, {}
	local waiting, ready = true, false
	local peer_ids = { [9] = "peer" }
	local connection = {
		connected_peers = function () return peer_ids end,
		can_accept_peer = function () return true end,
	}
	local prep = {
		is_waiting = function () return waiting end, is_finalizing = function () return false end,
		local_ready = function () return ready end, mission_name = function () return "km_enforcer" end,
		is_started = function () return not waiting end,
	}
	local r = {
		_preparation = prep,
		_session = { is_active_host = function () return true end, is_active_client = function () return false end,
			is_active = function () return true end },
		network_register = function (_, _, callback) receive = callback; return true end,
		network_on_peer_left = function () end,
		network_send = function (_, _, peer, payload) sent[#sent + 1] = { peer, payload }; return true end,
	}
	get_mod = function (name) if name == "Realms" then return r end; return old_get(name) end
	Managers = { state = {}, connection = { _connection_host = connection } }
	NetworkLookup = { buff_templates = { "base" } }
	mod.hook = function (_, _, name, callback) hooks[name] = callback end
	mod.custom_buff_id_map = function () return {} end
	mod._user_buffs = { deferred = true, local_text = "", saved_count = 3, count = 0 }
	mod.user_buffs = { install_text = function () return true end, allowed_session = function () return false end }
	local ok, err = pcall(function ()
		local sync = harness.load("recipe_sync")
		sync.update(1)
		test(sync, hooks, function (payload, sender) receive(sender or "peer", payload) end,
			sent, connection, function (value) waiting = value end, peer_ids)
	end)
	get_mod, Managers, NetworkLookup, mod.hook = old_get, old_managers, old_lookup, old_hook
	if not ok then error(err, 0) end
end

return {
	{ "clients lock a catalogue per connection but accept a different host after reconnect", function (a)
		with_host(function (sync, _, receive, sent)
			local r = get_mod("Realms")
			local manifest = sent[1][2]
			r._session.is_active_host = function () return false end
			r._session.is_active_client = function () return true end
			Managers.connection._connection_host = nil
			Managers.connection._connection_client = {}
			Managers.connection.host = function () return "host_a" end
			local installs = 0
			harness.mod.user_buffs.install_text = function () installs = installs + 1; return true end
			sync.update(1)
			a.falsy(sync.ready())
			receive(manifest, "stranger"); a.eq(installs, 0)
			receive(manifest, "host_a"); a.truthy(sync.ready()); a.eq(installs, 1)
			local different = table.shallow_copy(manifest)
			different.text = "b"
			-- The same rolling fingerprint as the protocol, for one byte.
			different.revision = "1:229:1057"
			receive(different, "host_a"); a.falsy(sync.ready()); a.eq(installs, 1)
			receive(different, "host_a"); a.eq(installs, 1, "failure does not unlock a live connection")
			Managers.connection._connection_client = {}
			Managers.connection.host = function () return "host_b" end
			sync.update(1)
			receive(different, "host_a"); a.eq(installs, 1, "old host ignored")
			receive(different, "host_b"); a.truthy(sync.ready()); a.eq(installs, 2)
		end)
	end },
	{ "ready button and host finalization wait for exact peer acknowledgement", function (a)
		with_host(function (sync, hooks, receive, sent)
			a.falsy(sync.ready()); a.eq(sent[1][1], "peer")
			local calls = 0
			local function original() calls = calls + 1; return true end
			a.falsy(hooks.perform_action(original)); hooks.update(original); a.eq(calls, 0)
			receive({kind="ack",revision="wrong",mapping="wrong"}); a.falsy(sync.ready())
			local manifest = sent[1][2]
			receive({kind="ack",revision=manifest.revision,mapping=manifest.mapping}, "stranger")
			a.falsy(sync.ready())
			receive({kind="ack",revision=manifest.revision,mapping=manifest.mapping})
			a.truthy(sync.ready()); a.truthy(hooks.perform_action(original)); a.eq(calls, 1)
		end)
	end },
	{ "recipe hosts refuse in-progress admission and new peers close the barrier", function (a)
		with_host(function (sync, _, receive, sent, connection, set_waiting, peers)
			local manifest = sent[1][2]
			receive({kind="ack",revision=manifest.revision,mapping=manifest.mapping})
			a.truthy(sync.ready()); a.truthy(connection:can_accept_peer("peer"))
			peers[10] = "new_peer"; a.falsy(sync.ready())
			set_waiting(false)
			local allowed, reason = connection:can_accept_peer("new_peer")
			a.falsy(allowed); a.eq(reason, "realms_server_private")
		end)
	end },
}
