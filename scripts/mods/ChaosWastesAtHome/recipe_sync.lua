local mod = get_mod("ChaosWastesAtHome")
if mod.recipe_sync then return mod.recipe_sync end

local sync = {}
mod.recipe_sync = sync
local state = { peers = {}, ready = false, elapsed = 0, status = "waiting for preparation lobby" }
mod._recipe_sync = state
local RPC_NAME = "cwah_recipes_v2"

-- Compatibility fingerprints, not authentication. Sender identity comes from
-- Realms; text is always validated data, never executable source.
local function fingerprint(text)
	local a, b = 1, 7
	for i = 1, #text do
		local byte = text:byte(i)
		a = (a * 131 + byte) % 2147483647
		b = (b * 137 + byte) % 2147483629
	end
	return string.format("%d:%d:%d", #text, a, b)
end

local function lookup_signature(base)
	local lookup = NetworkLookup and NetworkLookup.buff_templates
	if not lookup then return nil end
	return fingerprint(table.concat(lookup, "\n") .. (base and "" or
		("\n--cwah--\n" .. table.concat(mod.custom_buff_id_map(), "\n"))))
end

local function realms()
	return get_mod("Realms")
end

local function fail(message)
	message = tostring(message):sub(1, 512)
	if state.status ~= message then mod:error("recipe sync: %s", message:gsub("%%", "%%%%")) end
	state.status = message
	state.ready = false
end

local function waiting(r)
	return r._preparation.is_waiting() and not r._preparation.is_finalizing()
		and r._preparation.mission_name() ~= "hub_ship"
		and not (Managers.state and Managers.state.game_session)
end

local function host_peers()
	local connection = Managers.connection and Managers.connection._connection_host
	return connection and connection:connected_peers() or {}
end

local function install(text, base)
	local saved = mod._user_buffs
	if not saved or not saved.deferred then return false, "Restart with deferred recipe registration enabled" end
	state.base = lookup_signature(true)
	if not state.base or state.base ~= base then return false, "Base buff lookup differs; matching mod packs are required" end
	local ok, err = mod.user_buffs.install_text(text)
	if not ok then return false, err end
	state.text = text
	state.mapping = lookup_signature()
	state.revision = fingerprint(text)
	return true
end

local function send_manifest(peer)
	local r = realms()
	if state.text == nil or not state.mapping then return end
	return r.network_send(mod, RPC_NAME, peer, {
		kind = "manifest", protocol = 2, version = mod.version, text = state.text,
		base = state.base, mapping = state.mapping, revision = state.revision,
	})
end

local function receive(sender, payload)
	local r = realms()
	if not mod:is_enabled() or type(payload) ~= "table" then return end
	if r._session.is_active_client() then
		local host = Managers.connection:host()
		if tostring(sender):lower() ~= tostring(host):lower() or payload.kind ~= "manifest" then return end
		if not waiting(r) then return end
		if payload.protocol ~= 2 or payload.version ~= mod.version or type(payload.text) ~= "string" or #payload.text > 65536
			or type(payload.base) ~= "string" or #payload.base > 80
			or type(payload.mapping) ~= "string" or #payload.mapping > 80
			or payload.revision ~= fingerprint(payload.text) then
			fail("Invalid or incompatible recipe manifest")
			return
		end
		if state.locked_text and state.locked_text ~= payload.text then
			fail("Host changed recipes within an existing session; reconnect required")
			return
		end
		local ok, err = install(payload.text, payload.base)
		if not ok or state.mapping ~= payload.mapping then
			fail(err or "Registered recipe IDs do not match host; restart required")
			r.network_send(mod, RPC_NAME, "host", { kind = "reject", error = state.status })
			return
		end
		state.ready = true
		state.locked_text = payload.text
		if mod.user_buffs.menu_changed then mod.user_buffs.menu_changed() end
		state.status = "host catalogue installed and verified"
		r.network_send(mod, RPC_NAME, "host", { kind = "ack", revision = state.revision, mapping = state.mapping })
	elseif r._session.is_active_host() then
		local present = false
		for _, peer in pairs(host_peers()) do if tostring(peer) == tostring(sender) then present = true end end
		if not present then return end
		if payload.kind == "ack" and payload.revision == state.revision and payload.mapping == state.mapping then
			state.peers[sender] = state.revision
			if mod.user_buffs.menu_changed then mod.user_buffs.menu_changed() end
		elseif payload.kind == "request" and waiting(r) then
			send_manifest(sender)
		elseif payload.kind == "reject" then
			state.peers[sender] = nil
			local message = type(payload.error) == "string" and payload.error:sub(1, 512) or "client rejected catalogue"
			state.status = message
		end
	end
end

sync.ready = function ()
	local r = realms()
	if not r or not r._session.is_active() or not state.ready then return false end
	if r._session.is_active_host() then
		for _, peer in pairs(host_peers()) do
			if state.peers[peer] ~= state.revision then return false end
		end
	end
	return true
end

sync.active = function ()
	local r = realms()
	return r ~= nil and state.ready and r._session.is_active()
		and r._preparation.is_started() and mod:is_enabled()
end

sync.status = function () return state.status end

sync.update = function (dt)
	local r = realms()
	local saved = mod._user_buffs
	if not r or not r.network_register or not saved or not saved.deferred then return end
	if not state.registered then
		local ok = r.network_register(mod, RPC_NAME, receive)
		if not ok then return end
		r.network_on_peer_left(mod, function (peer) state.peers[peer] = nil end)
		state.registered = true
		-- Cover the real ready button AND host countdown/finalization. Merely
		-- guarding the automated test would leave manual ready-up unsafe.
		mod:hook(r._preparation, "perform_action", function (func, ...)
			if r._preparation.is_waiting() and not r._preparation.local_ready() and not sync.ready() then
				mod:echo("Player buffs are still synchronizing. Use /cw_recipes for status.")
				return false
			end
			return func(...)
		end)
		mod:hook(r._preparation, "update", function (func, ...)
			sync.update(0)
			if r._session.is_active_host() and r._preparation.is_waiting() and not sync.ready() then return end
			return func(...)
		end)
	end
	local connection = Managers.connection and (Managers.connection._connection_host or Managers.connection._connection_client)
	if state.connection ~= connection then
		state.connection = connection
		state.ready = false
		state.peers = {}
		state.status = "waiting for host catalogue"
		state.text, state.mapping, state.revision = nil, nil, nil
		state.locked_text = nil
		if mod.user_buffs.menu_changed then mod.user_buffs.menu_changed() end
	end
	if r._session.is_active_host() and connection and not connection._cwah_recipe_admission_guard then
		connection._cwah_recipe_admission_guard = true
		local original = connection.can_accept_peer
		connection.can_accept_peer = function (self, ...)
			-- The native connection may open first; reject engine admission before
			-- any gameplay units/buff IDs can reach an unsynchronized hot joiner.
			if ((saved.saved_count or 0) > 0 or (saved.count or 0) > 0)
				and (not waiting(r) or r._preparation.local_ready()) then
				return false, "realms_server_private"
			end
			return original(self, ...)
		end
	end
	if not mod:is_enabled() then state.ready = false; return end
	if not r._session.is_active() and mod.user_buffs.allowed_session() then
		state.base = lookup_signature(true)
		local ok, err = mod.user_buffs.install_text(saved.local_text or "")
		if not ok then fail(err) end
		return
	end
	if not waiting(r) then return end
	if r._session.is_active_host() and not state.ready then
		local run = mod._run
		local text = run and run.recipe_catalogue or saved.local_text or ""
		local ok, err = install(text, lookup_signature(true))
		if not ok then fail(err); return end
		state.ready = true
		if mod.user_buffs.menu_changed then mod.user_buffs.menu_changed() end
		state.status = "host catalogue registered; waiting for client acknowledgements"
	end
	state.elapsed = state.elapsed + (dt or 0)
	if state.elapsed < 1 then return end
	state.elapsed = 0
	if r._session.is_active_host() then
		local present = {}
		for _, peer in pairs(host_peers()) do
			present[peer] = true
			if state.peers[peer] ~= state.revision then send_manifest(peer) end
		end
		for peer in pairs(state.peers) do if not present[peer] then state.peers[peer] = nil end end
		if sync.ready() then state.status = "all clients verified" end
	elseif r._session.is_active_client() and not state.ready then
		r.network_send(mod, RPC_NAME, "host", { kind = "request" })
	end
end

return sync
