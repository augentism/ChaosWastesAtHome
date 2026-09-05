#!/usr/bin/env bash
# The whole loop, for real: chat votes, and the map chat picked is the map that
# launches.
#
# The vote arrives the only way it can. There is no inject export on the DLL --
# the tally is fed by Twitch/YouTube and nothing else -- so the test posts into
# the channel with TW_SendChat and lets the message come back around over
# EventSub. That is genuinely end to end: mod -> Twitch -> EventSub -> tally ->
# CWaH -> the next mission.
#
# THIS POSTS IN THE STREAMER'S TWITCH CHAT. Two messages per run, "!2" and a
# note saying it was a test. Only run it against a channel you are happy to see
# that in.
#
# Also covers the Continue/Space hold. Space is the button players hammer to get
# through a scoreboard, and without the hold it resolves the vote the instant it
# is pressed -- so the common case would be a vote thrown away a second after it
# opened, looking exactly like the feature not working.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

MISSION_1="km_enforcer"
CHOICE=2

printf 'vox_map_vote_chat\n'

if ! game_is_up; then
	printf '  SKIP game is not reachable\n'
	exit 111
fi

# Connectivity, NOT external_vote_available: the run below takes minutes, and
# whether a vote can open *right now* says nothing about whether one can open at
# the end screen. Gating on availability here skipped the whole suite because an
# ordinary automatic vote happened to be mid-flight -- which is precisely the
# state the feature is expected to preempt.
connected=$(dt '
local vox = get_mod("VoxPopuli")
if not vox then return "absent" end
local native = vox:io_dofile("VoxPopuli/scripts/mods/VoxPopuli/logic/native")
local st = native.status()
if not st then return "no-status" end
local twitch = st.conn_state == native.ST_CONNECTED
local yt = st.youtube and st.youtube.conn_state == native.ST_CONNECTED
return (twitch or yt) and "ready" or "not-connected"
')
if [ "$connected" != "ready" ]; then
	printf '  SKIP VoxPopuli is not connected to a chat (%s)\n' "$connected"
	exit 111
fi

# --- launch and win ------------------------------------------------------

dt '
local mod = get_mod("ChaosWastesAtHome")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")
local chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/chain")
run.reset("in-game chat vote test")
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
depth_before=$(printf '%s' "$first" | sed -n 's/.*|d\([0-9]*\)|.*/\1/p')

dt 'get_mod("ChaosWastesAtHome").debug_end_mission_won() return "won"' >/dev/null

# --- the end screen ------------------------------------------------------

cards=""
for ((i = 1; i <= 90; i++)); do
	s=$(state)
	case "$s" in
		*end=true*)
			cards=$(dt '
local cw = get_mod("ChaosWastesAtHome")
local net = cw:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/net")
local c = net.vote_cards()
local names = {}
for i = 1, #c do names[i] = tostring(c[i].mission_name) end
return tostring(cw._chat_vote_token) .. "|" .. tostring(net.is_chat_owned())
  .. "|" .. table.concat(names, ",")
')
			break
			;;
	esac
	[ "$(ready_up)" = "readied" ] && printf '  --   readied up\n'
	sleep 1
done

if [ -z "$cards" ]; then
	bad "the end screen came up" "never saw end=true"
	summary; exit 1
fi

ok "the end screen came up"
printf '  --   %s\n' "$cards"
assert_not_contains "$cards" "nil|" "a chat vote opened"
assert_contains "$cards" "|true|" "chat owns the round"

WANTED=$(printf '%s' "$cards" | cut -d'|' -f3 | cut -d',' -f"$CHOICE")
printf '  --   option %s is %s\n' "$CHOICE" "$WANTED"

# --- chat votes ----------------------------------------------------------

dt 'return get_mod("VoxPopuli") and tostring(get_mod("VoxPopuli"):io_dofile("VoxPopuli/scripts/mods/VoxPopuli/logic/native").send_chat("!'"$CHOICE"'"))' >/dev/null
printf '  --   posted "!%s" to chat\n' "$CHOICE"

landed=no
for ((i = 1; i <= 20; i++)); do
	t=$(dt '
local cw = get_mod("ChaosWastesAtHome")
local counts = cw.vote_counts()
local parts = {}
for i = 1, 3 do parts[i] = tostring(counts[i] or 0) end
return table.concat(parts, ",")
')
	case "$t" in
		0,0,0) ;;
		*) landed=yes; printf '  --   tally: %s\n' "$t"; break ;;
	esac
	sleep 1
done
assert_eq "$landed" "yes" "the chat vote came back round and was counted"

# --- Space must not throw the vote away ----------------------------------

dt 'Managers.multiplayer_session:leave("skip_end_of_round") return "pressed"' >/dev/null
sleep 2
held=$(state)
assert_contains "$held" "end=true" "pressing Continue while chat votes is refused"

# --- let it finish, then Continue should work ----------------------------

for ((i = 1; i <= 40; i++)); do
	f=$(dt '
local cw  = get_mod("ChaosWastesAtHome")
local vox = get_mod("VoxPopuli")
local st = cw._chat_vote_token and vox.external_vote_status(cw._chat_vote_token)
if not st then return "gone" end
return st.finished and ("finished|" .. tostring(st.winner_index)) or "running"
')
	case "$f" in
		finished*) printf '  --   %s\n' "$f"; break ;;
		gone) break ;;
	esac
	sleep 2
done
assert_contains "$f" "finished|$CHOICE" "chat's choice won the vote"

dt 'Managers.multiplayer_session:leave("skip_end_of_round") return "pressed"' >/dev/null
printf '  --   pressed Continue again once the vote had closed\n'

# --- and that map is what launches ---------------------------------------

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
# `.name`, NOT `.mission_name`. On a mission TEMPLATE those two are opposites of
# what they read like: `name` is the internal id ("lm_scavenge") and
# `mission_name` is the localization key ("loc_mission_name_lm_scavenge"). A
# CWaH vote *card* means the internal id by `mission_name`, so comparing the two
# straight across fails with the right mission and the wrong spelling.
launched=$(dt '
local mm = Managers.state and Managers.state.mission
local m = mm and mm:mission()
return tostring(m and m.name)
')

assert_eq "$depth_after" "$((depth_before + 1))" "the run advanced a depth"
assert_eq "$launched" "$WANTED" "the map chat voted for is the map that launched"

dt 'get_mod("VoxPopuli"):io_dofile("VoxPopuli/scripts/mods/VoxPopuli/logic/native").send_chat("(automated test - ignore the vote above)")' >/dev/null

summary
