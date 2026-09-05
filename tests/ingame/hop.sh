#!/usr/bin/env bash
# The mission hop: a run moves the party straight from the end-of-round screen
# into the next mission, without anybody passing through the Mourningstar.
#
# BOTH end-screen exits are exercised, separately, because they do not meet:
#
#   timer expiry     StateGameScore.update -> MechanismManager.trigger_event
#                    "game_score_done"
#   Continue / Space EndView._trigger_current_presentation_skip ->
#                    MultiplayerSessionManager.leave "skip_end_of_round"
#
# The second never touches game_score_done. Testing only the timer is how you
# ship a mod where letting the clock run works and pressing Space drops the
# party -- which is exactly the shape of the bug a tester hit.
#
# This drives the game: it starts a run and forces wins. Do not fire it at a
# session you care about.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

MISSION_1="km_enforcer"

printf 'hop\n'

if ! game_is_up; then
	printf '  SKIP game is not reachable\n'
	exit 111
fi

# --- launch --------------------------------------------------------------

# Deliberately NOT asserted on the return value. chain.launch resets the
# multiplayer session and boots a new one, so the reply can be lost with the
# connection that was asked to carry it -- a launch that worked perfectly then
# reads as a failure. The observable outcome is the mission coming up, so that
# is what gets asserted.
dt '
local mod = get_mod("ChaosWastesAtHome")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")
local chain = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/chain")
run.reset("in-game hop test")
run.mark_launched()
run.state().params = { challenge = 3, resistance = 3, circumstance_name = "default" }
chain.launch({
  mission_name = "'"$MISSION_1"'", challenge = 3, resistance = 3,
  circumstance_name = "default", side_mission = "default",
})
return "requested"
' >/dev/null 2>&1

first=$(wait_for_mission 60)
assert_contains "$first" "coop_complete_objective" "mission 1 came up"
assert_contains "$first" "d0" "run starts at depth 0"
assert_contains "$first" "mgr=true" "the buff system came up with it"

# Two named buffs, so carry-over across each hop is checked against something
# specific rather than against "any cwah_ buff" -- the mod applies
# cwah_status_cascade itself, so a prefix match passes whether or not carry-over
# worked at all.
#
# Retried, and its result ASSERTED rather than discarded: a mission being live
# does not mean the player unit has spawned, and grant_named_buff needs one.
# Throwing the result away is how this came back "carried=0" while every
# assertion downstream still passed.
granted=""
for attempt in 1 2 3 4 5 6 7 8 9 10; do
	granted=$(dt '
local mod = get_mod("ChaosWastesAtHome")
-- custom_buffs pulls in multishot, which registers six hooks at file scope.
-- Reaching it through mod.* avoids re-running those. See the rule in lib.sh.
if type(mod.grant_named_buff) ~= "function" then return "no-accessor" end

local player = Managers.player and Managers.player:local_player_safe(1)

if not player or not player.player_unit then return "no-player-unit" end

local done = {}

for _, name in ipairs({ "cwah_flayer", "cwah_multishot" }) do
  local ok, granted = pcall(mod.grant_named_buff, name)
  done[#done + 1] = name .. "=" .. tostring(ok and granted)
end

return table.concat(done, " ")
')
	case "$granted" in
		*"cwah_flayer=true"*) break ;;
	esac
	sleep 3
done

assert_contains "$granted" "cwah_flayer=true" "granted a buff to carry across the hop"

# --- one exit -------------------------------------------------------------

# $1 label, $2 lua fired once the end screen is up ("" for the timer path)
exercise_exit() {
	local label="$1" fire="$2"
	local before depth_before mission_before saw_hub=no fired=no torn_down=no s i

	printf '\n  exit: %s\n' "$label"

	before=$(state)
	depth_before=$(printf '%s' "$before" | sed -n 's/.*|d\([0-9]*\)|.*/\1/p')
	mission_before=$(printf '%s' "$before" | cut -d'|' -f2)

	dt 'get_mod("ChaosWastesAtHome").debug_end_mission_won() return "won"' >/dev/null

	# Two phases, because "a mission is live" is TRUE for several seconds after
	# the win -- the mission we just finished is still up. Breaking on that
	# alone declares the hop finished before it started, passes "the next
	# mission is live" against the OLD mission, and then fails "depth advanced"
	# for a reason that has nothing to do with depth. That happened.
	#
	# So: first wait for the teardown (no game mode / no manager), and only then
	# for a mission to come back.
	for ((i = 1; i <= 60; i++)); do
		s=$(state)
		case "$s" in hub\|*) saw_hub=yes ;; esac

		# EVERY hop goes back through the Realms lobby, not just the first
		# launch: chain.continue_run's change_mechanism makes Realms re-arm the
		# phase machine through host_transition_started, so the next mission
		# waits on Ready exactly as the first one did. Readying only in
		# wait_for_mission gets the run started and then stalls at the first hop.
		if [ "$(ready_up)" = "readied" ]; then
			printf '  --   %s: readied up for the next mission\n' "$label"
		fi

		if [ "$fired" = no ] && [ -n "$fire" ]; then
			case "$s" in
				*end=true*)
					dt "$fire" >/dev/null
					fired=yes
					;;
			esac
		fi

		case "$s" in
			coop_complete_objective*mgr=true)
				# Only counts once the old mission has actually gone away.
				if [ "$torn_down" = yes ]; then break; fi
				;;
			*)
				torn_down=yes
				;;
		esac

		sleep 2
	done

	local after depth_after mission_after
	after=$(state)
	depth_after=$(printf '%s' "$after" | sed -n 's/.*|d\([0-9]*\)|.*/\1/p')
	mission_after=$(printf '%s' "$after" | cut -d'|' -f2)

	assert_eq "$torn_down" "yes" "$label: the finished mission was torn down"
	assert_contains "$after" "coop_complete_objective" "$label: the next mission is live"
	assert_eq "$saw_hub" "no" "$label: the Mourningstar was never seen"
	assert_eq "$depth_after" "$((depth_before + 1))" "$label: depth advanced"

	if [ "$mission_after" != "$mission_before" ]; then
		ok "$label: it is a different mission ($mission_before -> $mission_after)"
	else
		bad "$label: it is a different mission" "still on $mission_after"
	fi

	if [ -n "$fire" ]; then
		assert_eq "$fired" "yes" "$label: the skip actually fired"
	fi

	local buffs
	buffs=$(buffs_on_unit)
	assert_contains "$buffs" "cwah_flayer" "$label: the granted buff carried across"
}

exercise_exit "timer expiry" ""

exercise_exit "Continue / Space" \
	'Managers.multiplayer_session:leave("skip_end_of_round") return "left"'

summary "hop"
