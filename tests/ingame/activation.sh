#!/usr/bin/env bash
# The activation gate. Read-only: reports what the gate would decide from where
# the game currently is, without launching anything.
#
# Two directions matter and only one is obvious. The mod must come up in a
# mission the player launched through the run launcher -- and it must stay out
# of everything else, including somebody else's matchmade mission. The gate was
# widened when runs became startable from character select, and the risk of a
# widened gate is that it lets the mod into missions it has no business in.
#
# Hooks also outlive missions: toggling a mod off unhooks it, but a mission
# ending does not, so a hook gated only on is_enabled() keeps running in
# whatever the player does next. The run-state half of the gate is what stops
# that, which is why is_launched is asserted separately from is_active.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

printf 'activation\n'

if ! game_is_up; then
	printf '  SKIP game is not reachable\n'
	exit 111
fi

report=$(dt '
local mod = get_mod("ChaosWastesAtHome")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")
local gm = Managers.state and Managers.state.game_mode
local session = Managers.multiplayer_session

return string.format("game_mode=%s host_type=%s launched=%s active=%s manager=%s role=%s",
  tostring(gm and gm:game_mode_name()),
  tostring(session and session:host_type()),
  tostring(run.is_launched()),
  tostring(run.is_active()),
  tostring(mod.manager ~= nil),
  tostring(mod.role))
')

printf '  %s\n' "$report"

case "$report" in
	LUA-ERROR:*|CLI-*)
		bad "activation state is readable" "$report"
		summary "activation"
		exit $?
		;;
esac

launched=$(printf '%s' "$report" | sed -n 's/.*launched=\([a-z]*\).*/\1/p')
active=$(printf '%s' "$report" | sed -n 's/.*active=\([a-z]*\).*/\1/p')
manager=$(printf '%s' "$report" | sed -n 's/.*manager=\([a-z]*\).*/\1/p')
mode=$(printf '%s' "$report" | sed -n 's/game_mode=\([a-z_]*\).*/\1/p')

# The invariant that holds everywhere: the buff system is never up in a mission
# the player did not deliberately start. This is the one that keeps the mod out
# of a matchmade game.
if [ "$manager" = "true" ] && [ "$launched" != "true" ]; then
	bad "the buff system is never live without a launched run" \
		"manager is up but the run was never launched -- $report"
else
	ok "the buff system is never live without a launched run"
fi

# active implies launched, never the other way round: `active` is set as a
# consequence of the buff system starting, so gating activation on it would be
# circular.
if [ "$active" = "true" ] && [ "$launched" != "true" ]; then
	bad "an active run is always a launched run" "$report"
else
	ok "an active run is always a launched run"
fi

case "$mode" in
	hub|prologue_hub)
		assert_eq "$manager" "false" "the buff system is not live in the hub"
		;;
	coop_complete_objective)
		if [ "$launched" = "true" ]; then
			assert_eq "$manager" "true" "the buff system is live in our own mission"
		else
			assert_eq "$manager" "false" "the buff system stays out of a mission we did not launch"
		fi
		;;
	*)
		printf '  --   game mode is %s; nothing mode-specific to assert here\n' "$mode"
		;;
esac

summary "activation"
