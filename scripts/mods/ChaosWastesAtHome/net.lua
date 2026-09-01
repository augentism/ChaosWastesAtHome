local mod = get_mod("ChaosWastesAtHome")

local MatchmakingConstants = require("scripts/settings/network/matchmaking_constants")
local HOST_TYPES = MatchmakingConstants.HOST_TYPES

-- Peer identity check, over Realms' public mod-network API.
--
-- The problem it solves: this mod appends its own buff templates to
-- NetworkLookup.buff_templates, and the host sends those ids to clients as
-- plain integers. A client that lacks the mod, runs a different version, or
-- assigned different ids reads a NetworkLookup key it does not have -- and
-- that lookup's __index errors, so it is a hard crash on *their* machine,
-- caused by ours. With a friend joining rather than a second local instance,
-- that is somebody else's evening.
--
-- So before any custom buff can be offered, every connected peer has to prove
-- it computed the same ids for the same names. Nothing here grants or blocks
-- by itself: it publishes a verdict, and buff_pool's exclusion pass acts on it.
--
-- Degrades to "safe" with no Realms and no peers, which is the solo case and
-- the overwhelmingly common one.

local net = {}

local RPC_IDENT = "cwah_ident"
local RPC_IDENT_REPLY = "cwah_ident_reply"
local RPC_OPTIONS = "cwah_options"
local RPC_VOTE = "cwah_vote"
local RPC_CHOOSING = "cwah_choosing"
local RPC_HOP = "cwah_hop"

-- Re-sent on a timer as well as on becoming available: Realms' bus comes up
-- asynchronously after a peer connects, and a send into a channel that is not
-- ready yet is refused rather than queued.
local RETRY_SECONDS = 3

-- State lives on the mod table, not in file locals. io_dofile re-executes this
-- file on every call and a mod reload rebuilds it, but a Realms session and its
-- peers outlive both -- file locals would silently forget who had been verified
-- and the pool would reopen to an unverified peer.
local state = mod._net_state

if not state then
	state = {
		-- [peer_id] = { status = "pending"|"ok"|"mismatch", detail = string }
		peers = {},
		registered = false,
		accum = 0,
		local_entries = nil,
		announced = false,
		-- The open vote, host side. token rises per round so a late vote for
		-- the previous mission cannot land in this one.
		vote = nil,
		-- [peer_id] = os-free timestamp-less flag: is that peer still on a card
		choosing = {},
		local_choosing = false,
		choosing_hold = 0,
		-- Client side: an announced re-host we are waiting to follow.
		hop = nil,
		-- Host side: the ConnectionHost we have closed to joins, if any. The
		-- object and not a boolean, because a listen host is destroyed and
		-- rebuilt on every hop and a plain flag would outlive the thing it
		-- described -- claiming a fresh, wide-open lobby was already shut.
		admission_held_host = nil,
	}
	mod._net_state = state
end

local function _realms()
	local realms = get_mod and get_mod("Realms")

	if not realms or not realms.network_register then
		return nil
	end

	return realms
end

-- The map this machine computed, as "name=id" strings.
--
-- Read through mod.custom_buff_id_map rather than io_dofile'ing custom_buffs:
-- that file re-executes per call and holds registration state, so a second
-- loader would be a second registration. The main script owns the one instance
-- and parks the accessor.
local function _local_entries()
	if not mod.custom_buff_id_map then
		return nil
	end

	local ok, entries = pcall(mod.custom_buff_id_map)

	if not ok or type(entries) ~= "table" then
		return nil
	end

	return entries
end

local function _same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end

	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end

	return true
end

-- Names the first disagreement rather than reporting "they differ".
--
-- This is why the payload is strings and not a hash: the log line says which
-- buff and which two ids, which is the difference between "the handshake
-- failed" and "they are on 0.7.0 and you are on 0.8.0".
local function _describe_difference(ours, theirs)
	if type(theirs) ~= "table" then
		return "peer sent no id map"
	end

	if #ours ~= #theirs then
		return string.format("different buff counts: %d here, %d there", #ours, #theirs)
	end

	for i = 1, #ours do
		if ours[i] ~= theirs[i] then
			return string.format("first difference at entry %d: '%s' here, '%s' there",
				i, tostring(ours[i]), tostring(theirs[i]))
		end
	end

	return "maps differ"
end

local function _set_peer(peer_id, status, detail)
	local previous = state.peers[peer_id]

	state.peers[peer_id] = { status = status, detail = detail }

	if previous and previous.status == status then
		return
	end

	if status == "ok" then
		mod:info("peer %s verified: same version and the same %s buff ids",
			tostring(peer_id), tostring(detail))
	else
		mod:error("peer %s REJECTED for custom buffs: %s", tostring(peer_id), tostring(detail))
		mod:echo(mod:localize("net_peer_mismatch", tostring(peer_id)))
	end
end

-- ---------------------------------------------------------------------------
-- Message handlers
-- ---------------------------------------------------------------------------

-- Whoever receives an ident compares it and answers with their own, so the
-- exchange is symmetric and either side can be the one that notices.
local function _on_ident(sender_peer_id, payload)
	local ours = _local_entries()

	if not ours then
		return
	end

	if type(payload) ~= "table" then
		_set_peer(sender_peer_id, "mismatch", "malformed ident")

		return
	end

	local version_matches = tostring(payload.version) == tostring(mod.version)
	local matched = version_matches and _same(ours, payload.entries)

	if matched then
		_set_peer(sender_peer_id, "ok", #ours)
	else
		local detail = not version_matches
			and string.format("version %s here, %s there",
				tostring(mod.version), tostring(payload.version))
			or _describe_difference(ours, payload.entries)

		_set_peer(sender_peer_id, "mismatch", detail)
	end

	-- Only answer an opening ident, never a reply -- otherwise two peers ping
	-- each other forever.
	if payload.is_reply then
		return
	end

	local realms = _realms()

	if realms then
		realms.network_send(mod, RPC_IDENT_REPLY, sender_peer_id, {
			version = mod.version,
			entries = ours,
			accepted = matched,
			is_reply = true,
		})
	end
end

-- ---------------------------------------------------------------------------
-- Voting on the next mission
-- ---------------------------------------------------------------------------
--
-- Run entirely during gameplay, and it has to be: StateGameScore is a top-level
-- game state, not a gameplay sub-state (mechanism_settings.lua:77), so by the
-- time the end-of-round screen is up MissionCleanupUtilies has already called
-- game_session:disconnect() and Realms' bus is gone with it. There is no
-- channel at the end screen, none in the preparation lobby, and none in the
-- Mourningstar.
--
-- So the choice is made while the mission is still being played, and the host
-- carries the winner into the end-of-mission transition.

local function _vote_counts(vote)
	local counts = {}

	for _, index in pairs(vote.votes) do
		counts[index] = (counts[index] or 0) + 1
	end

	return counts
end

-- Host: open a vote on a rolled set of options.
--
-- Safe with no peers -- the host's own vote is the only one, and the result is
-- whatever it picked. That is also the solo path, which is why nothing here is
-- conditional on being in a session.
net.start_vote = function (labels)
	if type(labels) ~= "table" or #labels == 0 then
		return false
	end

	local token = (state.vote and state.vote.token or 0) + 1

	state.vote = {
		token = token,
		labels = labels,
		votes = {},
	}

	mod:info("vote %d opened on %d option(s): %s", token, #labels, table.concat(labels, " | "))

	local realms = _realms()

	if realms then
		realms.network_send(mod, RPC_OPTIONS, "others", {
			token = token,
			labels = labels,
		})
	end

	return true
end

-- Host: the winning index, and whether anyone actually voted.
--
-- Ties and an empty ballot both fall to option 1 rather than failing. A run
-- that stalls because nobody pressed a button is worse than a run that picks
-- the first mission on the card.
net.vote_result = function ()
	local vote = state.vote

	if not vote then
		return nil, 0
	end

	local counts = _vote_counts(vote)
	local best, best_count = 1, -1
	local cast = 0

	for index, count in pairs(counts) do
		cast = cast + count

		if count > best_count then
			best, best_count = index, count
		end
	end

	return best, cast
end

-- Either role: record a choice. On the host that is a local vote; on a client
-- it goes to the host.
net.cast_vote = function (index)
	index = tonumber(index)

	if not index then
		return false, "not a number"
	end

	local realms = _realms()

	-- Client: send it. The host owns the tally.
	if mod.role == "client" then
		if not realms or not realms.network_is_available() then
			return false, "no connection to the host"
		end

		local vote = state.client_vote

		if not vote then
			return false, "no vote is open"
		end

		if index < 1 or index > vote.count then
			return false, "no such option"
		end

		realms.network_send(mod, RPC_VOTE, "all", { token = vote.token, index = index })

		return true
	end

	-- Host: our own ballot.
	local vote = state.vote

	if not vote then
		return false, "no vote is open"
	end

	if index < 1 or index > #vote.labels then
		return false, "no such option"
	end

	vote.votes.host = index

	return true
end

net.vote_report = function ()
	local lines = {}
	local vote = state.vote

	if mod.role == "client" then
		local client_vote = state.client_vote

		if not client_vote then
			return { "no vote is open" }
		end

		for i = 1, #client_vote.labels do
			lines[#lines + 1] = string.format("  %d. %s", i, tostring(client_vote.labels[i]))
		end

		lines[#lines + 1] = "vote with /cw_vote <number>"

		return lines
	end

	if not vote then
		return { "no vote is open" }
	end

	local counts = _vote_counts(vote)

	for i = 1, #vote.labels do
		lines[#lines + 1] = string.format("  %d. %s -- %d vote(s)",
			i, tostring(vote.labels[i]), counts[i] or 0)
	end

	local winner, cast = net.vote_result()

	lines[#lines + 1] = string.format("leading: %d (%s), %d vote(s) cast",
		winner, tostring(vote.labels[winner]), cast)

	return lines
end

local function _on_options(sender_peer_id, payload)
	if type(payload) ~= "table" or type(payload.labels) ~= "table" then
		return
	end

	state.client_vote = {
		token = payload.token,
		labels = payload.labels,
		count = #payload.labels,
	}

	mod:info("vote %s opened by the host on %d option(s)",
		tostring(payload.token), #payload.labels)

	mod:echo(mod:localize("vote_opened"))

	for i = 1, #payload.labels do
		mod:echo(string.format("  %d. %s", i, tostring(payload.labels[i])))
	end
end

local function _on_vote(sender_peer_id, payload)
	local vote = state.vote

	if not vote or type(payload) ~= "table" then
		return
	end

	-- Stale ballots are dropped rather than counted into the current round.
	if payload.token ~= vote.token then
		mod:info("ignored a vote from %s for round %s; current round is %d",
			tostring(sender_peer_id), tostring(payload.token), vote.token)

		return
	end

	local index = tonumber(payload.index)

	if not index or index < 1 or index > #vote.labels then
		return
	end

	vote.votes[sender_peer_id] = index

	mod:info("%s voted for %d (%s)", tostring(sender_peer_id), index,
		tostring(vote.labels[index]))
end

-- ---------------------------------------------------------------------------
-- Who is still choosing a buff
-- ---------------------------------------------------------------------------
--
-- The pause used to read only the local card, so the host resumed the world the
-- moment it picked -- with a synchronised pause that means everyone else is
-- suddenly choosing under fire. Each peer reports whether its own card is up
-- and the host holds the pause until nobody's is.
--
-- Reported on change rather than per frame: this is two or three messages per
-- card, not sixty a second.

-- Longest the party can be held for someone else's card.
--
-- The card resolves itself on a timeout, so this should never fire. It exists
-- because "should never" and a frozen session are a bad pair, and a client that
-- crashes mid-choice never sends its "done" -- without a cap the rest of the
-- party would be stopped until they noticed and quit.
local CHOOSING_HOLD_MAX = 60

net.set_local_choosing = function (choosing)
	choosing = choosing and true or false

	if choosing == state.local_choosing then
		return
	end

	state.local_choosing = choosing

	local realms = _realms()

	if not realms then
		return
	end

	local ok, available = pcall(realms.network_is_available)

	if not ok or not available then
		return
	end

	realms.network_send(mod, RPC_CHOOSING, "all", { choosing = choosing })
end

-- Host: is anyone else still on a card?
net.any_peer_choosing = function (dt)
	local any = false

	for _, choosing in pairs(state.choosing) do
		if choosing then
			any = true

			break
		end
	end

	if not any then
		state.choosing_hold = 0

		return false
	end

	state.choosing_hold = state.choosing_hold + (dt or 0)

	if state.choosing_hold > CHOOSING_HOLD_MAX then
		-- Give up rather than hold the party indefinitely. Cleared outright so
		-- this cannot re-trigger every frame from the same stuck peer.
		for peer_id in pairs(state.choosing) do
			state.choosing[peer_id] = nil
		end

		state.choosing_hold = 0

		mod:error("held the pause for %ds waiting on another player's buff choice - giving up",
			CHOOSING_HOLD_MAX)

		return false
	end

	return true
end

local function _on_choosing(sender_peer_id, payload)
	if type(payload) ~= "table" then
		return
	end

	state.choosing[sender_peer_id] = payload.choosing and true or false
end

-- A peer that leaves is no longer choosing. Without this a disconnect during a
-- card would hold the pause until the cap above expired.
net.forget_peer = function (peer_id)
	state.choosing[peer_id] = nil
	state.peers[peer_id] = nil
end

-- ---------------------------------------------------------------------------
-- Following the host to the next mission
-- ---------------------------------------------------------------------------
--
-- A hop is a re-host. chain.launch resets the multiplayer session and boots a
-- new one, Realms turns that into a fresh listen server, and every client is
-- dropped on the way through -- see chain.lua for why the party-preserving
-- alternative does not exist.
--
-- So the clients have to come back by themselves, and the only thing they need
-- in order to do that is to know the drop was deliberate. That is this message.
-- Without it a reconnect loop would also fire when the host simply quits, which
-- is the one thing worse than not reconnecting at all.
--
-- Sent while the mission is still live, because that is the last moment there is
-- a channel: StateGameScore is a top-level game state, so the gameplay session
-- and Realms' bus are both gone by the end-of-round screen.

-- How long we will chase a host that has actually gone. Counted from the drop,
-- not from the announcement: the announcement lands at the end of the mission
-- and the host then has an outro, an end screen and a hub load to get through
-- before it resets anything, which on a slow load is minutes. Counting from the
-- announcement would expire the hop before the hop happened.
local HOP_WINDOW = 240

-- Backstop on the other half -- how long an announced-but-unexecuted hop stays
-- armed. A host who announces and then abandons the run would otherwise leave a
-- client that reconnects to a quit an hour later.
local HOP_ARMED_MAX = 900

-- Waited out after the connection actually drops, before the first attempt.
-- The host is mid-teardown at that point and has not called
-- Native.start_local_session yet, so an immediate attempt is guaranteed to miss.
local HOP_FIRST_DELAY = 5
local HOP_RETRY_SECONDS = 6
local HOP_MAX_ATTEMPTS = 20

-- Are we still attached to a Realms host right now?
--
-- host_type rather than the bus: ModNetwork.is_available() needs a live game
-- session, so it goes false at the end-of-round screen while the connection is
-- still perfectly good. Reading that as "dropped" would start reconnecting
-- before the host had gone anywhere.
local function _attached_to_host()
	local session_manager = Managers.multiplayer_session

	if not session_manager then
		return false
	end

	local ok, host_type = pcall(session_manager.host_type, session_manager)

	if not ok or host_type ~= HOST_TYPES.player then
		return false
	end

	local connection = Managers.connection

	if not connection then
		return false
	end

	local ok_client, is_client = pcall(connection.is_client, connection)

	return ok_client and is_client or false
end

-- What we are in, once we are in something. nil while loading, which is a
-- distinct answer from "a mission" and has to stay that way.
local function _current_game_mode_name()
	local game_mode = Managers.state and Managers.state.game_mode

	if not game_mode then
		return nil
	end

	local ok, name = pcall(game_mode.game_mode_name, game_mode)

	return ok and name or nil
end

-- Where to reconnect to, from Realms' own saved setting.
--
-- join_view.lua writes join_server_address on every edit of its address field,
-- so the last thing the player typed to get here is already on disk. Parsed
-- here rather than through Realms' JoinTarget module because that is a private
-- file path, while `host:port` (or `[v6]:port`) is the format the player is
-- shown and types.
--
-- The port survives the hop: measured 2026-08-30, a host re-listens on the same
-- port for the life of its process (60799 three times, 36093 twice), and a hop
-- does not restart the game. The announcement carries the host's current port
-- anyway, so a stale setting costs nothing.
local function _stored_join_target()
	local realms = _realms()

	if not realms or type(realms.get) ~= "function" then
		return nil
	end

	local ok, value = pcall(realms.get, realms, "join_server_address")

	if not ok or type(value) ~= "string" or value == "" then
		return nil
	end

	local address, port_text

	if string.sub(value, 1, 1) == "[" then
		address, port_text = string.match(value, "^%[([^%[%]]+)%]:([^:]+)$")
	else
		address, port_text = string.match(value, "^([^:]+):([^:]+)$")
	end

	if not address or address == "" or not port_text then
		return nil
	end

	local port = string.match(port_text, "^%d+$") and tonumber(port_text) or nil

	if not port or port < 1 or port > 65535 then
		return nil
	end

	return address, port
end

local function _stored_password()
	local realms = _realms()

	if not realms or type(realms.get) ~= "function" then
		return ""
	end

	local ok, value = pcall(realms.get, realms, "server_password")

	return (ok and type(value) == "string") and value or ""
end

-- Host: the port our listen server is on, so the announcement can carry it.
local function _local_host_port()
	local connection = Managers.connection
	local host = connection and connection._connection_host

	if not host or type(host.local_port) ~= "function" then
		return nil
	end

	local ok, port = pcall(host.local_port, host)

	return ok and port or nil
end

-- Host: tell everyone a re-host is coming.
--
-- Returns false when there is nobody to tell, which is the solo case and is not
-- an error -- the caller hops either way.
net.announce_hop = function (mission_name)
	local realms = _realms()

	if not realms then
		return false
	end

	local ok, available = pcall(realms.network_is_available)

	if not ok or not available then
		mod:info("not announcing the hop: no gameplay-control bus (nobody could hear it)")

		return false
	end

	local peers = net.peer_ids()

	if #peers == 0 then
		-- The solo case, and the one that looks like a bug when it is silent:
		-- there is a bus (Realms answers is_available for a host with no peers)
		-- but nobody on it. Logged so "did the hop announcement run?" has an
		-- answer either way.
		mod:info("no hop announcement sent: nobody is connected")

		return false
	end

	local port = _local_host_port()

	realms.network_send(mod, RPC_HOP, "others", {
		mission_name = mission_name,
		port = port,
		version = mod.version,
	})

	mod:info("announced the hop to %d peer(s): next mission '%s', reconnect port %s",
		#peers, tostring(mission_name), tostring(port))

	return true
end

local function _on_hop(sender_peer_id, payload)
	-- A host never follows anyone. Guarded rather than assumed, because a peer
	-- that mis-set its role would otherwise reset its own session mid-mission.
	if mod.role == "host" then
		return
	end

	local address, port = _stored_join_target()

	if type(payload) == "table" and tonumber(payload.port) then
		-- The host's live port beats whatever we last typed.
		port = tonumber(payload.port)
	end

	if not address then
		mod:error("the host is hopping to the next mission, but no join address is saved - reconnect by hand")
		mod:echo(mod:localize("hop_no_address"))

		return
	end

	state.hop = {
		address = address,
		port = port,
		password = _stored_password(),
		mission_name = type(payload) == "table" and payload.mission_name or nil,
		elapsed = 0,
		armed_for = 0,
		attempts = 0,
		cooldown = 0,
		waiting_for_drop = true,
	}

	mod:info("host announced a hop to '%s'; will rejoin %s:%s once this session drops",
		tostring(state.hop.mission_name), tostring(address), tostring(port))

	mod:echo(mod:localize("hop_incoming"))
end

local function _give_up_hop(why)
	local hop = state.hop

	state.hop = nil

	mod:error("stopped trying to follow the host: %s (%d attempt(s) over %ds)",
		why, hop and hop.attempts or 0, math.floor(hop and hop.elapsed or 0))

	mod:echo(mod:localize("hop_gave_up"))
end

local function _update_hop(dt)
	local hop = state.hop

	if not hop then
		return
	end

	hop.armed_for = hop.armed_for + (dt or 0)

	if hop.armed_for > HOP_ARMED_MAX then
		_give_up_hop("the host announced a hop and never made it")

		return
	end

	if _attached_to_host() then
		-- Still on a connection. Either the original one -- the host has not
		-- reset yet -- or one we just re-established.
		if hop.attempts == 0 then
			hop.waiting_for_drop = true

			return
		end

		local game_mode_name = _current_game_mode_name()

		if not game_mode_name then
			-- Mid-load. "Which session did we land in" is not answerable yet,
			-- and answering it early is how the hub gets mistaken for the
			-- mission.
			return
		end

		-- The Mourningstar is a stop on the way, not the destination.
		--
		-- The host passes through the hub between missions, and with
		-- SoloMourningstar installed that hub is a local session too -- so
		-- Realms stands a listen server up for it and it answers on the same
		-- address. A reconnect that lands there looks exactly like success,
		-- and would clear the hop moments before the host resets again for the
		-- real mission, dropping the client for good.
		--
		-- So a hub landing re-arms instead of finishing. The host also shuts
		-- that lobby to joins while a launch is pending (net.hold_admission),
		-- which should stop this being reachable at all; this is the half that
		-- does not depend on the host's timing.
		if game_mode_name == "hub" or game_mode_name == "prologue_hub" then
			if not hop.landed_in_hub then
				hop.landed_in_hub = true

				mod:info("reconnected into the host's Mourningstar rather than the next mission - staying armed for the real hop")
			end

			hop.waiting_for_drop = true
			hop.elapsed = 0

			return
		end

		mod:info("rejoined the host in '%s' after %d attempt(s)", game_mode_name, hop.attempts)
		mod:echo(mod:localize("hop_rejoined"))

		state.hop = nil

		return
	end

	-- Detached. Only now does the chase clock run -- see HOP_WINDOW.
	hop.elapsed = hop.elapsed + (dt or 0)

	if hop.elapsed > HOP_WINDOW then
		_give_up_hop("the host never came back")

		return
	end

	if hop.waiting_for_drop then
		hop.waiting_for_drop = false
		hop.cooldown = HOP_FIRST_DELAY

		mod:info("the host's session has gone; first reconnect attempt to %s:%s in %ds",
			tostring(hop.address), tostring(hop.port), HOP_FIRST_DELAY)

		mod:echo(mod:localize("hop_reconnecting"))

		return
	end

	hop.cooldown = hop.cooldown - (dt or 0)

	if hop.cooldown > 0 then
		return
	end

	hop.cooldown = HOP_RETRY_SECONDS

	local realms = _realms()
	local session = realms and realms._session

	if not session or type(session.start_client) ~= "function" then
		_give_up_hop("Realms exposes no _session.start_client")

		return
	end

	hop.attempts = hop.attempts + 1

	local ok, started, err = pcall(session.start_client, hop.address, hop.port, hop.password)

	if not ok then
		mod:error("reconnect attempt %d threw: %s", hop.attempts, tostring(started))
	elseif started then
		-- Accepted, not arrived: start_client only kicks the client boot off.
		-- Left armed on purpose, so a boot that then fails is retried; the
		-- attached branch above is what actually finishes the hop.
		mod:info("reconnect attempt %d accepted, joining %s:%s",
			hop.attempts, tostring(hop.address), tostring(hop.port))

		hop.cooldown = HOP_RETRY_SECONDS * 2
	else
		-- Expected for the first few: the host is still loading, or our own
		-- previous attempt is still in flight (error_join_already_pending).
		mod:info("reconnect attempt %d refused: %s", hop.attempts, tostring(err))
	end

	if hop.attempts >= HOP_MAX_ATTEMPTS then
		_give_up_hop("out of attempts")
	end
end

-- Host: shut the Mourningstar lobby while a launch is pending.
--
-- With SoloMourningstar installed the hub is a local session, so Realms turns it
-- into a listen server exactly like a mission -- same address, answering joins,
-- for the whole time the host is between missions. Anyone dialling in then lands
-- in the Mourningstar instead of the mission, which is a race a reconnecting
-- client can lose and a person typing an address can lose too.
--
-- Realms' own admission gate is the lever: can_accept_peer refuses with
-- SERVER_PRIVATE when accept_new_connections is false
-- (connection_host.lua:116-118), which is a clean refusal the client retries
-- past rather than a dropped connection.
--
-- Restored through Session.apply_settings rather than by remembering the old
-- value, so the reopen recomputes from the player's own Realms settings and
-- cannot get them wrong. Nothing is written to those settings at any point.
net.hold_admission = function (holding)
	holding = holding and true or false

	local host = Managers.connection and Managers.connection._connection_host

	-- Forget a hold that outlived its host. That is the normal ending, not an
	-- error: the launch this was protecting is what destroyed it, and its
	-- replacement booted open from the player's own settings.
	if state.admission_held_host and state.admission_held_host ~= host then
		state.admission_held_host = nil
	end

	if holding == (state.admission_held_host ~= nil) then
		return true
	end

	local realms = _realms()

	if not realms then
		return false
	end

	if not holding then
		state.admission_held_host = nil

		local session = realms._session

		if not session or type(session.apply_settings) ~= "function" then
			mod:error("could not reopen the lobby: Realms exposes no _session.apply_settings")

			return false
		end

		local ok = pcall(session.apply_settings)

		mod:info("lobby reopened to joins%s", ok and "" or " (Realms refused to reapply its settings)")

		return ok
	end

	if not host or type(host.set_admission_policy) ~= "function" then
		return false
	end

	-- set_admission_policy overwrites all three fields, so the two we do not
	-- mean to change have to be handed back as they are.
	local ok_max, max_members = pcall(host.max_members, host)
	local password = ""

	if type(realms.get) == "function" then
		local ok_password, value = pcall(realms.get, realms, "server_password")

		password = (ok_password and type(value) == "string") and value or ""
	end

	local ok = pcall(host.set_admission_policy, host, false, ok_max and max_members or 4, password)

	if not ok then
		mod:error("could not close the lobby to joins while the run moves on")

		return false
	end

	state.admission_held_host = host

	mod:info("Mourningstar lobby closed to joins until the next mission is up")

	return true
end

-- Client: cancel a pending follow. The host changed its mind, or the run ended.
net.cancel_hop = function (why)
	if not state.hop then
		return false
	end

	mod:info("cancelled the pending hop: %s", tostring(why))

	state.hop = nil

	return true
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

net.install = function ()
	if state.registered then
		return true
	end

	local realms = _realms()

	if not realms then
		return false
	end

	local ok_a, err_a = realms.network_register(mod, RPC_IDENT, _on_ident)
	local ok_b, err_b = realms.network_register(mod, RPC_IDENT_REPLY, _on_ident)
	local ok_c, err_c = realms.network_register(mod, RPC_OPTIONS, _on_options)
	local ok_d, err_d = realms.network_register(mod, RPC_VOTE, _on_vote)
	local ok_e, err_e = realms.network_register(mod, RPC_CHOOSING, _on_choosing)
	local ok_f, err_f = realms.network_register(mod, RPC_HOP, _on_hop)

	if not ok_f then
		mod:error("could not register the mission-hop RPC: %s", tostring(err_f))

		return false
	end

	if not ok_e then
		mod:error("could not register the buff-choice RPC: %s", tostring(err_e))

		return false
	end

	if not ok_c or not ok_d then
		mod:error("could not register the voting RPCs: %s / %s",
			tostring(err_c), tostring(err_d))

		return false
	end

	if not ok_a or not ok_b then
		mod:error("could not register the peer identity RPCs: %s / %s",
			tostring(err_a), tostring(err_b))

		return false
	end

	state.registered = true

	mod:info("peer identity RPCs registered with Realms")

	return true
end

net.update = function (dt)
	local realms = _realms()

	if not realms then
		return
	end

	-- Before the registration and availability gates below, both of which are
	-- false exactly when a hop is in progress -- there is no bus while the host
	-- is re-hosting, which is the whole point of the hop being announced in
	-- advance rather than negotiated at the time.
	_update_hop(dt)

	if not state.registered and not net.install() then
		return
	end

	local ok, available = pcall(realms.network_is_available)

	if not ok or not available then
		return
	end

	local entries = _local_entries()

	if not entries then
		return
	end

	if not state.announced then
		state.announced = true
		state.local_entries = entries

		mod:info("custom buff ids on this machine (%d): %s",
			#entries, table.concat(entries, " "))
	end

	state.accum = state.accum + (dt or 0)

	if state.accum < RETRY_SECONDS then
		return
	end

	state.accum = 0

	-- Broadcast rather than tracking who has answered. Realms filters the send
	-- against each peer's capability manifest, so a peer without this mod is
	-- skipped rather than errored, and re-identing a matched peer costs a few
	-- hundred bytes every few seconds.
	realms.network_send(mod, RPC_IDENT, "others", {
		version = mod.version,
		entries = entries,
	})
end

-- ---------------------------------------------------------------------------
-- The verdict
-- ---------------------------------------------------------------------------

-- False the moment any peer is unverified, including one we have not heard
-- from yet.
--
-- Deliberately fail-closed: "we have not finished checking" and "they are
-- wrong" get the same answer, because being wrong costs a crash on somebody
-- else's machine and being cautious costs a few seconds without custom buffs.
net.custom_buffs_safe = function ()
	if not _realms() then
		return true
	end

	local peers = net.peer_ids()

	if #peers == 0 then
		return true
	end

	for i = 1, #peers do
		local entry = state.peers[peers[i]]

		if not entry or entry.status ~= "ok" then
			return false
		end
	end

	return true
end

-- Who Realms says is connected and capable, which is the set that has to have
-- answered. A peer without this mod never appears here -- Realms filters its
-- manifest -- and so cannot hold the pool closed.
net.peer_ids = function ()
	local realms = _realms()
	local control = realms and realms._gameplay_control

	if not control or not control.ready_peer_ids then
		return {}
	end

	local ok, peers = pcall(control.ready_peer_ids)

	if not ok or type(peers) ~= "table" then
		return {}
	end

	return peers
end

-- Everyone attached to us, ready for our messages or not.
--
-- Distinct from peer_ids() on purpose. That one lists peers whose
-- gameplay-control channel has completed its handshake; this one counts raw
-- connections, including a client that is still loading into the mission.
--
-- The difference is the whole bug behind the synchronised pause: Realms'
-- send_to_clients only delivers to channels flagged `ready`
-- (gameplay_control.lua:329), so a loading client silently receives nothing.
-- Pausing on the strength of peer_ids() alone therefore froze the host while
-- the joining client kept running, and killed it on a black screen.
net.connected_count = function ()
	local connection = Managers.connection
	local host = connection and connection._connection_host
	local remotes = host and host._remote_connections

	if type(remotes) ~= "table" then
		return 0
	end

	local n = 0

	for _ in pairs(remotes) do
		n = n + 1
	end

	return n
end

-- Can every attached peer actually hear us right now?
--
-- False while anyone is connected but not yet ready, which is exactly the
-- window a joining client sits in. Anything that would change shared state has
-- to wait for this rather than for connected_count alone.
net.all_peers_ready = function ()
	local connected = net.connected_count()

	if connected == 0 then
		return false
	end

	return #net.peer_ids() >= connected
end

net.report = function ()
	local lines = {}
	local entries = state.local_entries or _local_entries()

	lines[#lines + 1] = string.format("version %s, %s custom buff id(s)",
		tostring(mod.version), entries and #entries or "no")

	if not _realms() then
		lines[#lines + 1] = "Realms is not loaded - no peers to check"

		return lines
	end

	local any = false

	for peer_id, entry in pairs(state.peers) do
		any = true
		lines[#lines + 1] = string.format("  %s: %s%s", tostring(peer_id),
			tostring(entry.status),
			entry.detail and (" - " .. tostring(entry.detail)) or "")
	end

	if not any then
		lines[#lines + 1] = "  no peers have identified yet"
	end

	lines[#lines + 1] = string.format("custom buffs %s",
		net.custom_buffs_safe() and "ENABLED" or "SUPPRESSED")

	local hop = state.hop

	if hop then
		lines[#lines + 1] = string.format("following the host to '%s' via %s:%s - %d attempt(s), %ds elapsed",
			tostring(hop.mission_name), tostring(hop.address), tostring(hop.port),
			hop.attempts, math.floor(hop.elapsed))
	end

	return lines
end

return net
