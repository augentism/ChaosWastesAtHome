-- The end-of-round mission vote: tallying, and the three tiebreak rules.
--
-- The tie path is worth pinning because it is rare in play and easy to get
-- wrong in a way nobody notices -- a tie that resolves differently on different
-- runs looks like the vote being ignored, and it was exactly that once, when
-- the winner was read out of a hash whose iteration order is not guaranteed.

local harness = ...

local CARDS = {
	{ mission_name = "km_enforcer" },
	{ mission_name = "core_research" },
	{ mission_name = "dm_forge" },
}

local function load_net()
	require("scripts/settings/network/matchmaking_constants")

	return harness.load("net")
end

-- The host's own vote is keyed "host"; peers key by peer id. Written straight
-- into state so a tally can be arranged without pretending to have a network.
local function record(votes, order)
	local vote = harness.mod._net_state.vote

	for voter, index in pairs(votes) do
		vote.sequence = vote.sequence + 1
		vote.votes[voter] = index
		vote.order[voter] = (order and order[voter]) or vote.sequence
	end

	return vote
end

return {
	{ "a vote needs cards", function (a)
		local net = load_net()

		a.falsy(net.start_vote(nil), "start_vote(nil)")
		a.falsy(net.start_vote({}), "start_vote({})")
		a.falsy(net.start_vote("cards"), "start_vote(string)")
	end },

	{ "the token rises each round so a late vote cannot land in this one", function (a)
		local net = load_net()

		net.start_vote(CARDS)

		local first = net.vote_token()

		net.start_vote(CARDS)

		a.gt(net.vote_token(), first, "token after a second round")
	end },

	{ "a fresh vote has no counts", function (a)
		local net = load_net()

		net.start_vote(CARDS)

		a.size(net.vote_counts(), 0, "counts")
	end },

	{ "votes tally per option", function (a)
		local net = load_net()

		net.start_vote(CARDS)
		record({ host = 2, peer_a = 2, peer_b = 3 })

		local counts = net.vote_counts()

		a.eq(counts[2], 2, "counts[2]")
		a.eq(counts[3], 1, "counts[3]")
		a.nil_(counts[1], "counts[1]")
	end },

	{ "a voter changing their mind replaces their vote", function (a)
		local net = load_net()

		net.start_vote(CARDS)
		record({ peer_a = 1 })
		record({ peer_a = 3 })

		local counts = net.vote_counts()

		a.nil_(counts[1], "counts[1]")
		a.eq(counts[3], 1, "counts[3]")
	end },

	{ "a clear winner wins, and the cast count is reported", function (a)
		local net = load_net()

		net.start_vote(CARDS)
		record({ host = 2, peer_a = 2, peer_b = 3 })

		local winner, cast, note = net.vote_result()

		a.eq(winner, 2, "winner")
		a.eq(cast, 3, "cast")
		a.nil_(note, "no tiebreak note for a clear win")
	end },

	{ "an empty ballot falls to the first card", function (a)
		-- A run that stalls because nobody pressed anything is worse than a run
		-- that picks the first card.
		local net = load_net()

		net.start_vote(CARDS)

		local winner, cast = net.vote_result()

		a.eq(winner, 1, "winner")
		a.eq(cast, 0, "cast")
	end },

	{ "no open vote yields no result", function (a)
		local net = load_net()

		a.nil_(net.vote_result(), "vote_result with no vote")
		a.size(net.vote_counts(), 0, "counts with no vote")
	end },

	{ "the host's vote settles a tie under the host rule", function (a)
		local net = load_net()

		harness.mod:set("vote_tiebreak", "host")
		net.start_vote(CARDS)
		record({ host = 3, peer_a = 2 })

		local winner, cast, note = net.vote_result()

		a.eq(winner, 3, "winner")
		a.eq(cast, 2, "cast")
		a.truthy(note, "a tiebreak note was given")
	end },

	{ "the host rule falls back when the host is not among the leaders", function (a)
		local net = load_net()

		harness.mod:set("vote_tiebreak", "host")
		net.start_vote(CARDS)
		-- Host backs card 1; cards 2 and 3 tie above it.
		record({ host = 1, peer_a = 2, peer_b = 2, peer_c = 3, peer_d = 3 })

		local winner = net.vote_result()

		a.contains({ 2, 3 }, winner, "winner is one of the tied leaders")
		a.neq(winner, 1, "winner is not the host's losing card")
	end },

	{ "first past the post picks the card that filled up earliest", function (a)
		local net = load_net()

		harness.mod:set("vote_tiebreak", "first")
		net.start_vote(CARDS)

		-- Card 3 reaches two votes at sequence 2; card 2 not until sequence 4.
		record(
			{ peer_a = 3, peer_b = 3, peer_c = 2, peer_d = 2 },
			{ peer_a = 1, peer_b = 2, peer_c = 3, peer_d = 4 }
		)

		local winner, _, note = net.vote_result()

		a.eq(winner, 3, "winner")
		a.truthy(note, "a tiebreak note was given")
	end },

	{ "the random rule picks one of the tied leaders", function (a)
		local net = load_net()

		harness.mod:set("vote_tiebreak", "random")
		net.start_vote(CARDS)
		record({ peer_a = 2, peer_b = 3 })

		local winner, _, note = net.vote_result()

		a.contains({ 2, 3 }, winner, "winner is one of the tied leaders")
		a.truthy(note, "a tiebreak note was given")
	end },

	-- The bug this ordering exists to prevent: `counts` only holds indices
	-- somebody voted for, so with card 1 unvoted the remaining keys can sit in
	-- LuaJIT's hash part, where iteration order is not guaranteed. A tie would
	-- resolve differently between runs with nothing to explain it.
	{ "a tie resolves the same way every time", function (a)
		local net = load_net()

		harness.mod:set("vote_tiebreak", "host")

		local first

		for attempt = 1, 25 do
			harness.mod._net_state = nil

			local n = harness.load("net")

			n.start_vote(CARDS)
			-- Card 1 deliberately unvoted, which is what pushes the rest into
			-- the hash part.
			record({ peer_a = 2, peer_b = 3 })

			local winner = n.vote_result()

			if attempt == 1 then
				first = winner
			end

			a.eq(winner, first, "winner on attempt " .. attempt)
		end
	end },

	{ "resetting clears the vote", function (a)
		local net = load_net()

		net.start_vote(CARDS)
		record({ host = 2 })
		net.reset_vote()

		a.nil_(net.vote_result(), "vote_result after reset")
		a.size(net.vote_counts(), 0, "counts after reset")
	end },
}
