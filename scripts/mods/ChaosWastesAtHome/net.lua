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
local RPC_TALLY = "cwah_tally"

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

-- One ballot. The sequence is what makes "first past the post" possible: a
-- changed vote takes a new number, because moving to another card is a fresh
-- commitment to it, not a retroactive one.
local function _record_vote(vote, voter, index)
	vote.sequence = vote.sequence + 1
	vote.votes[voter] = index
	vote.order[voter] = vote.sequence
end

-- Host: push the running tally to everyone.
--
-- The host owns the count -- clients send their votes to it and hear nothing
-- back -- so without this each player could only ever see their own choice, and
-- a vote nobody can watch is not really a vote.
--
-- Sent on change rather than on a timer: a party produces a handful of votes per
-- mission, so this is a few messages, not a stream. Dense array of exactly one
-- entry per card, because a sparse table would arrive with holes and read as
-- fewer options than were offered.
local function _broadcast_tally()
	local vote = state.vote

	if not vote then
		return
	end

	local realms = _realms()

	if not realms then
		return
	end

	local ok, available = pcall(realms.network_is_available)

	if not ok or not available then
		return
	end

	local counts = _vote_counts(vote)
	local dense = {}

	for i = 1, #vote.cards do
		dense[i] = counts[i] or 0
	end

	realms.network_send(mod, RPC_TALLY, "others", {
		token = vote.token,
		counts = dense,
	})
end

-- Host: open a vote on a rolled set of options.
--
-- Safe with no peers -- the host's own vote is the only one, and the result is
-- whatever it picked. That is also the solo path, which is why nothing here is
-- conditional on being in a session.
-- `cards` is one table per option, not just a name: the vote view draws the same
-- three mission cards the end screen does, and a client has no way to rebuild
-- difficulty or modifier text from a display name alone. Mission art is the
-- exception -- that resolves locally from MissionTemplates by mission_name.
net.start_vote = function (cards)
	if type(cards) ~= "table" or #cards == 0 then
		return false
	end

	local token = (state.vote and state.vote.token or 0) + 1

	state.vote = {
		token = token,
		cards = cards,
		votes = {},
		-- When each voter last committed, as a rising counter. Only the
		-- "first past the post" tiebreak reads it, but it has to be recorded as
		-- votes arrive -- it cannot be reconstructed afterwards.
		order = {},
		sequence = 0,
	}

	local names = {}

	for i = 1, #cards do
		names[i] = tostring(cards[i].label)
	end

	mod:info("vote %d opened on %d option(s): %s", token, #cards, table.concat(names, " | "))

	local realms = _realms()

	if realms then
		realms.network_send(mod, RPC_OPTIONS, "others", {
			token = token,
			cards = cards,
		})
	end

	-- Zeros, immediately. A client that has the cards but no tally would show
	-- blank counts until the first vote landed, which reads as broken rather
	-- than as empty.
	_broadcast_tally()

	return true
end

-- Host: the winning index, how many votes were cast, and how a tie was settled.
--
-- Three rules, because which one feels fair depends on the table and none of
-- them is obviously right. The setting picks:
--
--   host   -- the host's own ballot wins if it is among the leaders. Explainable
--             and stable, but with two players every split is a host win.
--   first  -- whichever tied mission reached the winning count first. Rewards
--             deciding early rather than who you are; needs the arrival order,
--             which is why votes are numbered as they land.
--   random -- an even coin among the tied. Nobody has an edge, at the cost of
--             the same votes not always giving the same mission.
--
-- All three fall back to the leftmost card, so there is always an answer.
--
-- Not left to iteration order, which is what this used to be: `counts` only
-- holds indices somebody voted for, so with card 1 unvoted the remaining keys
-- can sit in LuaJIT's hash part where order is not guaranteed. A tie could
-- resolve differently on different runs with nothing to explain it.
--
-- An empty ballot falls to option 1. A run that stalls because nobody pressed
-- anything is worse than a run that picks the first card.
net.vote_result = function ()
	local vote = state.vote

	if not vote then
		return nil, 0
	end

	local counts = _vote_counts(vote)
	local cast = 0
	local best_count = 0

	-- Over the cards, not over the counts: every option is considered whether or
	-- not anybody voted for it, in a fixed order.
	for i = 1, #vote.cards do
		local count = counts[i] or 0

		cast = cast + count

		if count > best_count then
			best_count = count
		end
	end

	if best_count == 0 then
		return 1, 0, nil
	end

	local leaders = {}

	for i = 1, #vote.cards do
		if (counts[i] or 0) == best_count then
			leaders[#leaders + 1] = i
		end
	end

	if #leaders == 1 then
		return leaders[1], cast, nil
	end

	local rule = mod:get("vote_tiebreak") or "host"

	if rule == "host" then
		local host_choice = vote.votes.host

		if host_choice and (counts[host_choice] or 0) == best_count then
			return host_choice, cast, "tied - settled by the host's vote"
		end
	elseif rule == "random" then
		return leaders[math.random(#leaders)], cast, "tied - settled at random"
	elseif rule == "first" then
		-- When each tied mission *reached* this count: the highest sequence
		-- among its current voters, since that is the vote that completed it.
		-- Earliest wins.
		local best_leader, best_seq

		for i = 1, #leaders do
			local index = leaders[i]
			local reached = 0

			for voter, choice in pairs(vote.votes) do
				if choice == index then
					local seq = vote.order[voter] or 0

					if seq > reached then
						reached = seq
					end
				end
			end

			if not best_seq or reached < best_seq then
				best_leader, best_seq = index, reached
			end
		end

		if best_leader then
			return best_leader, cast, "tied - settled by which filled up first"
		end
	end

	return leaders[1], cast, "tied - settled by card order"
end

-- Are we the client side of the vote?
--
-- Asked of the vote state, NOT of mod.role. Everything here now runs on the
-- end-of-round screen, and _destroy_buff_system nils mod.role before that
-- screen exists -- so a role test answers "neither" for everybody and every
-- branch below would silently take the host path. A client has a client_vote
-- and no vote; the host has the reverse.
local function _is_vote_client()
	return state.client_vote ~= nil and state.vote == nil
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
	if _is_vote_client() then
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

		-- Kept locally too. A client never hears the tally back, so without this
		-- its own vote would leave no trace on its own screen.
		vote.choice = index

		return true
	end

	-- Host: our own ballot.
	local vote = state.vote

	if not vote then
		return false, "no vote is open"
	end

	if index < 1 or index > #vote.cards then
		return false, "no such option"
	end

	_record_vote(vote, "host", index)

	_broadcast_tally()

	return true
end

-- The tally as an index -> count array, for the vote view's cards.
--
-- Both roles. The host owns the real tally; a client only knows its own choice,
-- so it reports that as a single vote rather than showing nothing. That is
-- honest about what a client can see -- it has no channel that carries the
-- others' votes back -- and still confirms the click landed.
net.vote_counts = function ()
	if _is_vote_client() then
		local client_vote = state.client_vote

		if not client_vote then
			return {}
		end

		-- The host's numbers when we have them. Our own vote only until the
		-- first tally arrives, so a click shows something immediately rather
		-- than appearing to do nothing for a round trip.
		if client_vote.counts then
			return client_vote.counts
		end

		local counts = {}

		if client_vote.choice then
			counts[client_vote.choice] = 1
		end

		return counts
	end

	local vote = state.vote

	if not vote then
		return {}
	end

	return _vote_counts(vote)
end

-- Forget the previous mission's vote.
--
-- Called when a mission starts, on both roles. Without it the old cards sat in
-- state.vote until a new vote replaced them, and the vote screen opened on the
-- mission the party had already played -- the token had moved on but nothing had
-- cleared what it pointed at.
--
-- At the start rather than at teardown on purpose: the end-of-round picker reads
-- mod._vote_options and mod._vote_winner, which are resolved during
-- complete_game_mode and consumed by the end screen. Clearing on the way out
-- would race that.
net.reset_vote = function ()
	state.vote = nil
	state.client_vote = nil
end

-- This player's own choice in the running vote, or nil.
--
-- Derived rather than remembered by the screen, so a vote cast with /cw_vote
-- shows as selected too -- and so reopening the screen still shows what you
-- picked instead of looking as though you had not voted.
net.my_vote = function ()
	if _is_vote_client() then
		return state.client_vote and state.client_vote.choice
	end

	return state.vote and state.vote.votes.host
end

-- Which round is running, or nil. The vote screen watches this so it can fill
-- itself in if the vote opens while it is already on screen.
net.vote_token = function ()
	if _is_vote_client() then
		return state.client_vote and state.client_vote.token
	end

	return state.vote and state.vote.token
end

-- The options as the vote view needs them, from whichever side is asking. Empty
-- when no vote is open, which the vote screen shows rather than refuses.
net.vote_cards = function ()
	if _is_vote_client() then
		return state.client_vote and state.client_vote.cards or {}
	end

	return state.vote and state.vote.cards or {}
end

net.vote_report = function ()
	local lines = {}
	local vote = state.vote

	if _is_vote_client() then
		local client_vote = state.client_vote

		if not client_vote then
			return { "no vote is open" }
		end

		for i = 1, #client_vote.cards do
			lines[#lines + 1] = string.format("  %d. %s", i, tostring(client_vote.cards[i].label))
		end

		lines[#lines + 1] = "vote with /cw_vote <number>"

		return lines
	end

	if not vote then
		return { "no vote is open" }
	end

	local counts = _vote_counts(vote)

	for i = 1, #vote.cards do
		lines[#lines + 1] = string.format("  %d. %s -- %d vote(s)",
			i, tostring(vote.cards[i].label), counts[i] or 0)
	end

	local winner, cast, note = net.vote_result()

	lines[#lines + 1] = string.format("leading: %d (%s), %d vote(s) cast%s",
		winner, tostring(vote.cards[winner] and vote.cards[winner].label), cast,
		note and (" - " .. note) or "")

	return lines
end

local function _on_options(sender_peer_id, payload)
	if type(payload) ~= "table" or type(payload.cards) ~= "table" then
		return
	end

	state.client_vote = {
		token = payload.token,
		cards = payload.cards,
		count = #payload.cards,
	}

	mod:info("vote %s opened by the host on %d option(s)",
		tostring(payload.token), #payload.cards)

	mod:echo(mod:localize("vote_opened"))

	for i = 1, #payload.cards do
		mod:echo(string.format("  %d. %s", i, tostring(payload.cards[i].label)))
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

	if not index or index < 1 or index > #vote.cards then
		return
	end

	_record_vote(vote, sender_peer_id, index)

	mod:info("%s voted for %d (%s)", tostring(sender_peer_id), index,
		tostring(vote.cards[index] and vote.cards[index].label))

	_broadcast_tally()
end

local function _on_tally(sender_peer_id, payload)
	local client_vote = state.client_vote

	if not client_vote or type(payload) ~= "table" or type(payload.counts) ~= "table" then
		return
	end

	-- A tally for a round we are not on is a message that overtook its own
	-- options, or arrived after we moved on. Either way it describes a different
	-- set of cards than the ones on screen.
	if payload.token ~= client_vote.token then
		return
	end

	client_vote.counts = payload.counts
end

-- ---------------------------------------------------------------------------
-- Who is still choosing a buff
-- ---------------------------------------------------------------------------
--
-- Each peer reports whether its own card is up, and the host acts on it.
--
-- Built for the synchronised pause, which is gone. It survives that because
-- choice_shield.lua needs exactly the same fact for a better reason: the host
-- has to know whose card is up in order to make that person untargetable while
-- they read it. The pause could only ever stop the whole world; this protects
-- one player at a time, which is what was actually wanted.
--
-- Reported on change rather than per frame: this is two or three messages per
-- card, not sixty a second.

-- Tell the others when our own card goes up or down.
--
-- This existed, was deleted in 0.11.2 along with the synchronised pause, and
-- nothing noticed for four releases: pause.lua calls it through `mod.report_choosing`
-- inside a pcall, so the nil call was swallowed once a frame rather than raised.
-- With no sender, `cwah_choosing` was never transmitted, `net.peer_choosing`
-- answered false for everyone, and choice_shield protected nobody but the
-- player running it. Peers were unprotected from 0.11.2 onward.
--
-- Sent on change, not per frame -- two or three messages per card.
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

	-- "all", not "others": the host is a recipient like anyone else, and a
	-- client's card only matters to the host, which is who acts on it.
	realms.network_send(mod, RPC_CHOOSING, "all", { choosing = choosing })
end

local function _on_choosing(sender_peer_id, payload)
	if type(payload) ~= "table" then
		return
	end

	state.choosing[sender_peer_id] = payload.choosing and true or false
end

-- Is one specific peer on a card? Who, not merely whether anyone is: the shield
-- protects the person reading, and nobody else.
net.peer_choosing = function (peer_id)
	return state.choosing[peer_id] == true
end

-- Forget a peer that has gone.
--
-- Written for the synchronised pause and then never called, which left every
-- peer this session ever saw listed in /cw_peers forever. Harmless to the buff
-- gate -- custom_buffs_safe only asks about peers Realms currently reports -- but
-- a support command that lists people who left an hour ago is worse than no
-- command.
--
-- Called from the sweep in net.update rather than from a disconnect hook: Realms
-- owns the disconnect callback and this mod does not, so comparing against its
-- peer list is the reachable answer.
net.forget_peer = function (peer_id)
	state.choosing[peer_id] = nil
	state.peers[peer_id] = nil
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
	local ok_g, err_g = realms.network_register(mod, RPC_TALLY, _on_tally)

	if not ok_g then
		mod:error("could not register the vote-tally RPC: %s", tostring(err_g))

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


	if not state.registered and not net.install() then
		return
	end

	local ok, available = pcall(realms.network_is_available)

	if not ok or not available then
		return
	end

	-- Drop anyone Realms no longer lists. Cheap: a handful of keys against a
	-- party of at most four.
	local present = {}
	local peers = net.peer_ids()

	for i = 1, #peers do
		present[peers[i]] = true
	end

	for peer_id in pairs(state.peers) do
		if not present[peer_id] then
			net.forget_peer(peer_id)
		end
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


	return lines
end

return net
