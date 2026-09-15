#!/usr/bin/env bash
# Shared plumbing for the in-game tests. Sourced, not executed.
#
# These drive a running game through dt-cli, so they assert on things no offline
# harness can reach: whether the party actually changes mission, whether the
# custom buffs are registered where the network expects them, whether the
# activation gate lets us into a mission we did not launch.
#
# ---------------------------------------------------------------------------
# THE ONE RULE
# ---------------------------------------------------------------------------
# Never `mod:io_dofile` a module that registers hooks at file scope --
# multishot.lua, triggers.lua, or custom_buffs.lua, which pulls in multishot.
#
# io_dofile re-executes the file; DMF caches nothing. Every `mod:hook` in it
# runs again, DMF spots the duplicate, drops it, and logs
# "Attempting to rehook active hook [name]" at WARNING level -- which by default
# goes to the player's CHAT as well as the log. It looks exactly like a mod
# defect and it is not: it is the harness talking to itself.
#
# This cost most of a debugging session once. Read state through mod.* accessors
# instead; `mod.custom_buff_id_map` exists for precisely this reason, and
# net.lua carries a comment saying so.
#
# run.lua, buff_pool.lua and difficulty.lua register no hooks and are safe to
# io_dofile.
# ---------------------------------------------------------------------------

set -uo pipefail

WORKSPACE="${CWAH_TEST_ROOT:-/mnt/storage/workspace/modding/Darktide}"
CLI="$WORKSPACE/.agents/skills/darktide-dt-cli/scripts/dt-cli.sh"
INSTANCE="${DARKTIDE_INSTANCE:-main}"

PASS=0
FAIL=0
FAILURES=()

# --- dt-cli --------------------------------------------------------------

# dt-cli's JSON key order is NOT stable -- the same build emits both
# {"id",...,"output","ok"} and {"result",...,"ok","output","id"}. A sed pattern
# that assumes one order silently produces an EMPTY string against the other,
# which is far worse than an error: every assertion downstream compares against
# "" and the wait loops never see the state they are waiting for, so the suite
# looks hung while the game is doing exactly what it was told. That happened.
#
# So: parse it. python3 is on PATH inside the flake, which is how run_tests.py
# invokes this. The sed fallback exists for running a script directly outside
# the flake and handles either ordering.
PY="$(command -v python3 || true)"

_json_field() {
	local field="$1"
	if [ -n "$PY" ]; then
		"$PY" -c '
import json, sys
raw = sys.stdin.read()
try:
    doc = json.loads(raw)
except Exception:
    sys.stdout.write("")
    sys.exit(0)
value = doc.get(sys.argv[1])
sys.stdout.write("" if value is None else str(value))
' "$field"
	else
		sed -n "s/.*\"$field\":\"\([^\"]*\)\".*/\1/p" \
			| sed 's/\\n/\n/g; s/\\"/"/g; s|\\/|/|g'
	fi
}

# A call can come back "i/o timeout" while the game is loading or mid-frame.
# That is the pipe connecting and LuaExec not answering in time -- a busy
# signal, not an unreachable game -- so it is retried rather than failed.
dt() {
	local lua="$1" out attempt
	for attempt in 1 2 3 4 5 6 7 8; do
		out=$(timeout -k 3s 25s bash "$CLI" --instance "$INSTANCE" exec --stdin <<<"$lua" 2>&1)
		case "$out" in
			*'"ok":true'*)
				printf '%s' "$out" | _json_field output
				return 0
				;;
			*'i/o timeout'*)
				sleep 2
				;;
			*)
				# A real Lua error. Surface it rather than burning the retries.
				printf 'LUA-ERROR: %s' "$(printf '%s' "$out" | _json_field error)"
				return 1
				;;
		esac
	done
	printf 'CLI-UNREACHABLE: %s' "$out"
	return 1
}

game_is_up() {
	timeout -k 3s 25s bash "$CLI" --instance "$INSTANCE" exec 'return "up"' 2>&1 | grep -q '"ok":true'
}

# --- assertions ----------------------------------------------------------

ok() {
	PASS=$((PASS + 1))
	printf '  ok   %s\n' "$1"
}

bad() {
	FAIL=$((FAIL + 1))
	FAILURES+=("$1")
	printf '  FAIL %s\n' "$1"
	[ -n "${2:-}" ] && printf '         %s\n' "$2"
	return 0
}

assert_eq() {
	local got="$1" want="$2" what="$3"
	if [ "$got" = "$want" ]; then
		ok "$what"
	else
		bad "$what" "expected '$want', got '$got'"
	fi
}

assert_contains() {
	local haystack="$1" needle="$2" what="$3"
	case "$haystack" in
		*"$needle"*) ok "$what" ;;
		*) bad "$what" "expected to find '$needle' in: $haystack" ;;
	esac
}

assert_not_contains() {
	local haystack="$1" needle="$2" what="$3"
	case "$haystack" in
		*"$needle"*) bad "$what" "did not expect '$needle' in: $haystack" ;;
		*) ok "$what" ;;
	esac
}

assert_true() {
	assert_eq "$1" "true" "$2"
}

summary() {
	printf '\n%s: %d passed, %d failed\n' "${1:-ingame}" "$PASS" "$FAIL"
	if [ "$FAIL" -gt 0 ]; then
		printf 'failures:\n'
		for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
		return 1
	fi
	return 0
}

# --- shared game state readers -------------------------------------------

# One line describing where the run is. Everything here comes off mod.* and
# Managers.*; nothing is io_dofile'd except run.lua, which registers no hooks.
STATE_LUA='
local mod = get_mod("ChaosWastesAtHome")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")
local gm = Managers.state and Managers.state.game_mode
local mm = Managers.state and Managers.state.mission
-- The LOCALIZATION KEY, not the internal id: on a mission template
-- `mission_name` is "loc_mission_name_lm_scavenge" while `name` is
-- "lm_scavenge". Harmless here, since every comparison is against another
-- reading of this same field -- but do not match it against the
-- `mission_name` on a vote card, which means the internal id.
-- (No apostrophes in here: this Lua lives inside a single-quoted bash
-- string, so one would end the string and hand the rest to the shell.)
local mission = mm and mm:mission() and mm:mission().mission_name
-- end_screen_up is a FUNCTION, not a boolean. Comparing the field to true is
-- always false and silently skips whatever it was gating.
local on_end_screen = type(mod.end_screen_up) == "function" and mod.end_screen_up() or false
return string.format("%s|%s|d%s|end=%s|mgr=%s",
  tostring(gm and gm:game_mode_name()), tostring(mission), tostring(run.depth()),
  tostring(on_end_screen and true or false), tostring(mod.manager ~= nil))
'

state() {
	dt "$STATE_LUA"
}

# The mod's custom buffs currently on the local player's unit.
# player_unit is a FIELD, not a method: player:player_unit() throws
# "attempt to call method 'player_unit' (a userdata value)".
BUFFS_LUA='
local player = Managers.player and Managers.player:local_player_safe(1)
local unit = player and player.player_unit
if not unit then return "no-player-unit" end
local ext = ScriptUnit and ScriptUnit.has_extension(unit, "buff_system")
if not ext then return "no-buff-extension" end
local names = {}
for _, b in pairs(ext:buffs()) do
  local ok, n = pcall(b.template_name, b)
  if ok and type(n) == "string" and n:find("cwah_", 1, true) then names[#names+1] = n end
end
table.sort(names)
return "[" .. table.concat(names, ",") .. "]"
'

buffs_on_unit() {
	dt "$BUFFS_LUA"
}

# Press Ready in the Realms preparation lobby.
#
# With Realms hosting, chain.launch does not go straight to the level: it parks
# in RealmsPreparationState waiting for the host to ready up, and without this
# the suite sits there until its timeout while somebody presses a button by
# hand.
#
# Preparation.perform_action() is exactly what the view's button calls
# (preparation_view.lua reads Preparation.local_ready() to label it), reached
# through the `mod._preparation` handle Realms parks on its own mod table.
#
# Idempotent and safe to call on every poll: it reports and does nothing when
# there is no Realms, when the lobby is not waiting, or when we are already
# ready. Without the local_ready() guard it would TOGGLE -- perform_action is
# "ready or cancel ready", so calling it twice un-readies you.
ready_up() {
	dt '
local realms = get_mod("Realms")
local prep = realms and realms._preparation

if not prep or type(prep.perform_action) ~= "function" then
  return "no-preparation"
end

if not prep.is_waiting() then return "not-waiting" end
if prep.local_ready() then return "already-ready" end

return prep.perform_action() and "readied" or "refused"
'
}

wait_for_mission() {
	local tries="${1:-60}" i s r
	for ((i = 1; i <= tries; i++)); do
		s=$(state)
		case "$s" in
			coop_complete_objective*mgr=true) printf '%s' "$s"; return 0 ;;
		esac

		# The lobby is a stop on the way, not a destination.
		r=$(ready_up)
		[ "$r" = "readied" ] && printf '  --   readied up in the Realms lobby\n' >&2

		sleep 4
	done
	printf '%s' "$s"
	return 1
}
