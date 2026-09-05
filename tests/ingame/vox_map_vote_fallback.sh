#!/usr/bin/env bash
# The other half of a compatibility layer: what happens when the other mod
# cannot take the job.
#
# A layer that only works when everything is present is not a layer, it is a
# dependency -- and the failure it produces is the worst kind, because the end
# screen is a one-shot event. If the chat vote is skipped and nothing takes over,
# a run ends there.
#
# Exercised through end_screen_extra_seconds rather than by disabling VoxPopuli:
# a real setting, restored in a trap, and it drives the same branch
# (_start_chat_vote returning false) without touching DMF's mod-state machinery,
# which would leave the user's mod switched off if this aborted.
#
# With no end screen to spare, _chat_vote_duration() answers nil -- "a vote that
# closes after the screen does is one nobody sees the result of" -- and CWaH must
# fall back to deciding for itself.
#
# This drives the game: it starts a run and forces a win.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

MISSION_1="km_enforcer"

printf 'vox_map_vote_fallback\n'

if ! game_is_up; then
	printf '  SKIP game is not reachable\n'
	exit 111
fi

if [ "$(dt 'return get_mod("VoxPopuli") and "yes" or "no"')" != "yes" ]; then
	printf '  SKIP VoxPopuli is not loaded\n'
	exit 111
fi

# --- squeeze the end screen ----------------------------------------------

ORIGINAL=$(dt 'return tostring(get_mod("ChaosWastesAtHome"):get("end_screen_extra_seconds"))')
printf '  --   end_screen_extra_seconds was %s\n' "$ORIGINAL"

restore() {
	dt 'get_mod("ChaosWastesAtHome"):set("end_screen_extra_seconds", '"$ORIGINAL"', false) return "restored"' >/dev/null
	printf '  --   restored end_screen_extra_seconds to %s\n' "$ORIGINAL"
}
trap restore EXIT

dt 'get_mod("ChaosWastesAtHome"):set("end_screen_extra_seconds", 0, false) return "squeezed"' >/dev/null

# --- launch and win ------------------------------------------------------

dt '
local mod = get_mod("ChaosWastesAtHome")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")
local chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/chain")
run.reset("in-game vox fallback test")
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

PROBE='
local cw  = get_mod("ChaosWastesAtHome")
local vox = get_mod("VoxPopuli")
local net = cw:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/net")
return string.format("token=%s chat_owned=%s next=%s vox_idle=%s",
  tostring(cw._chat_vote_token), tostring(net.is_chat_owned()),
  tostring(cw:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run").state().next_mission ~= nil),
  tostring(select(1, vox.external_vote_available())))
'

probe=""
for ((i = 1; i <= 90; i++)); do
	s=$(state)
	case "$s" in
		*end=true*) probe=$(dt "$PROBE"); break ;;
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

assert_contains "$probe" "token=nil"       "no chat vote was opened"
assert_contains "$probe" "chat_owned=false" "the round did not go to chat"
assert_contains "$probe" "next=true"       "CWaH still has a mission selected"
assert_contains "$probe" "vox_idle=true"   "VoxPopuli was left idle, not holding a vote"

# --- and the run still continues -----------------------------------------

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

assert_contains "$after" "coop_complete_objective" "the run continued without chat"
assert_eq "$depth_after" "$((depth_before + 1))" "the run advanced a depth anyway"

summary
