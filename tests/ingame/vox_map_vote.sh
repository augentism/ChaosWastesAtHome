#!/usr/bin/env bash
# The VoxPopuli compatibility layer: with VoxPopuli connected, the viewers pick
# the next mission instead of the players.
#
# Drives a real run to its end screen and asserts against the live seam, because
# the interesting failures are all in the handoff and none of them are reachable
# offline: whether CWaH can see VoxPopuli's API at all, whether the vote survives
# the mission gate closing (VoxPopuli cancels running votes when a mission ends,
# and this vote opens *because* a mission ended), and whether a player's click is
# really refused rather than merely uncounted.
#
# What it cannot do: make chat vote. The tally lives in the DLL and is fed by
# Twitch/YouTube, so with a silent chat every run of this exercises the
# zero-votes path -- which is the honest common case for an automated test and is
# a rule this mod cares about (random, never a fixed slot). The tally arithmetic
# and the resolution rules are pinned offline in VoxPopuli's
# check_recipient_flow.lua instead.
#
# This drives the game: it starts a run and forces a win. Do not fire it at a
# session you care about.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

MISSION_1="km_enforcer"

printf 'vox_map_vote\n'

if ! game_is_up; then
	printf '  SKIP game is not reachable\n'
	exit 111
fi

# --- the seam ------------------------------------------------------------

seam=$(dt '
local vox = get_mod("VoxPopuli")
if not vox then return "absent" end
if type(vox.start_external_vote) ~= "function" then return "no-api" end
local ok, why = vox.external_vote_available()
return "api|" .. tostring(ok) .. "|" .. tostring(why or "")
')

case "$seam" in
	absent)
		printf '  SKIP VoxPopuli is not loaded\n'
		exit 111
		;;
	no-api)
		bad "VoxPopuli exposes the external-vote API" "start_external_vote is missing"
		summary
		exit 1
		;;
esac

ok "CWaH can see VoxPopuli's external-vote API"
assert_contains "$seam" "api|true" "VoxPopuli is ready to be asked ($seam)"

# --- launch and win ------------------------------------------------------

dt '
local mod = get_mod("ChaosWastesAtHome")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")
local chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/chain")
run.reset("in-game vox map vote test")
run.mark_launched()
run.state().params = { challenge = 3, resistance = 3, circumstance_name = "default" }
chain.launch({
  mission_name = "'"$MISSION_1"'", challenge = 3, resistance = 3,
  circumstance_name = "default", side_mission = "default",
})
return "requested"
' >/dev/null 2>&1

first=$(wait_for_mission 60)
assert_contains "$first" "coop_complete_objective" "a mission came up"
mission_before=$(printf '%s' "$first" | cut -d'|' -f2)
depth_before=$(printf '%s' "$first" | sed -n 's/.*|d\([0-9]*\)|.*/\1/p')

dt 'get_mod("ChaosWastesAtHome").debug_end_mission_won() return "won"' >/dev/null

# --- catch the end screen ------------------------------------------------
#
# One batched probe rather than a call per assertion: the end screen is on a
# clock, and eight round trips through dt-cli would sample eight different
# moments of it.
PROBE='
local cw  = get_mod("ChaosWastesAtHome")
local vox = get_mod("VoxPopuli")
local net = cw:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/net")

local token = cw._chat_vote_token
local parts = { "token=" .. tostring(token) }

parts[#parts+1] = "chat_owned=" .. tostring(net.is_chat_owned())

-- Dense zeros prove chat owns the tally: the party path returns a SPARSE table
-- and with nobody having clicked that is empty, so a length of 3 could not come
-- from it.
local counts = cw.vote_counts()
local n, sum = 0, 0
for i = 1, 3 do
  if counts[i] ~= nil then n = n + 1; sum = sum + counts[i] end
end
parts[#parts+1] = "dense=" .. n .. " sum=" .. sum

-- A click must not be a ballot.
local cast, why = cw.cast_vote(2)
parts[#parts+1] = "cast=" .. tostring(cast) .. " (" .. tostring(why) .. ")"
parts[#parts+1] = "my_vote=" .. tostring(net.my_vote())

if token and vox and type(vox.external_vote_status) == "function" then
  local st = vox.external_vote_status(token)
  if st then
    parts[#parts+1] = "vox_state=" .. tostring(st.state)
    parts[#parts+1] = "left=" .. string.format("%.0f", st.seconds_left or -1)
  else
    parts[#parts+1] = "vox_state=GONE"
  end
end
return table.concat(parts, " ")
'

probe=""
for ((i = 1; i <= 90; i++)); do
	s=$(state)
	case "$s" in
		*end=true*)
			probe=$(dt "$PROBE")
			break
			;;
	esac
	[ "$(ready_up)" = "readied" ] && printf '  --   readied up\n'
	sleep 1
done

if [ -z "$probe" ]; then
	bad "the end screen came up" "never saw end=true"
	summary
	exit 1
fi

ok "the end screen came up"
printf '  --   %s\n' "$probe"

assert_not_contains "$probe" "token=nil"   "a chat vote opened for the next mission"
assert_contains     "$probe" "chat_owned=true" "the round belongs to chat, not the party"
assert_contains     "$probe" "dense=3"     "the cards read chat's tally, not the party's"
assert_contains     "$probe" "cast=false"  "a player's click is refused"
assert_contains     "$probe" "viewers are deciding" "and says why"
assert_contains     "$probe" "my_vote=nil" "so no card shows as the player's own"
assert_contains     "$probe" "vox_state=running" "VoxPopuli still has the vote open"
assert_not_contains "$probe" "vox_state=GONE" "the vote survived the mission gate closing"

# --- and it resolves into a real mission ---------------------------------

torn_down=no
for ((i = 1; i <= 90; i++)); do
	s=$(state)
	[ "$(ready_up)" = "readied" ] && printf '  --   readied up for the next mission\n'
	case "$s" in
		coop_complete_objective*mgr=true) [ "$torn_down" = yes ] && break ;;
		*) torn_down=yes ;;
	esac
	sleep 2
done

after=$(state)
depth_after=$(printf '%s' "$after" | sed -n 's/.*|d\([0-9]*\)|.*/\1/p')
mission_after=$(printf '%s' "$after" | cut -d'|' -f2)

assert_contains "$after" "coop_complete_objective" "chat's choice actually launched"
assert_eq "$depth_after" "$((depth_before + 1))" "the run advanced a depth"
assert_contains "$(dt 'return tostring(get_mod("ChaosWastesAtHome")._chat_vote_token)')" \
	"nil" "the vote token was consumed, not leaked"

printf '  --   %s -> %s\n' "$mission_before" "$mission_after"

summary
