#!/usr/bin/env bash
# The live counterpart of the offline pool tests: what the game's own offer
# pools actually contain, after our exclusion pass has run against them.
#
# The offline tier proves run.trim_pools removes the right names from a table we
# built. This proves the real pools, filled by the real buff system, do not
# contain a buff the player is already carrying -- which is the difference
# between "the function works" and "the feature works".
#
# Also checks the family pool has not run away. Dropping the family_restored
# flag once made the reconciliation re-apply the family every second, and the
# engine APPENDS a family's buffs to the pool rather than replacing them: 1,422
# entries in one mission, every card after that a duplicate of something already
# held.
#
# Read-only: this asserts against whatever run is currently live. Run it from
# inside a mission, ideally after a hop or two.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

printf 'buff_pool\n'

if ! game_is_up; then
	printf '  SKIP game is not reachable\n'
	exit 111
fi

s=$(state)

case "$s" in
	coop_complete_objective*mgr=true) ;;
	*)
		printf '  SKIP not in a live run (%s)\n' "$s"
		exit 111
		;;
esac

report=$(dt '
local mod = get_mod("ChaosWastesAtHome")
local run = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/run")

local manager = mod.manager
local handler = manager and manager._mission_buffs_handler
local persistent = handler and handler._persistent_data
local player = Managers.player and Managers.player:local_player_safe(1)

if not persistent or not player then return "NO-PERSISTENT-DATA" end

local carried = {}
local carried_n = 0

for name in pairs(run.state().buffs or {}) do
  carried[name] = true
  carried_n = carried_n + 1
end

-- Every pool the player can be offered from, flattened. The legendary side is a
-- map of filter category to array, not one flat list.
local pooled, pool_n, dupes, offered_carried = {}, 0, 0, {}

local function scan(list)
  if type(list) ~= "table" then return end
  for _, name in ipairs(list) do
    pool_n = pool_n + 1
    if pooled[name] then dupes = dupes + 1 else pooled[name] = true end
    if carried[name] then offered_carried[#offered_carried + 1] = name end
  end
end

local ok_p, priority = pcall(persistent.get_player_priority_family_buffs_available, persistent, player)
local ok_f, family = pcall(persistent.get_player_family_buffs_available, persistent, player)
local ok_l, legendary = pcall(persistent.get_legendary_buffs_available_for_player, persistent, player)

local family_n = 0

if ok_p then scan(priority) end
if ok_f then
  scan(family)
  family_n = type(family) == "table" and #family or 0
end
if ok_l and type(legendary) == "table" then
  for _, cat in pairs(legendary) do scan(cat) end
end

return string.format("carried=%d pool=%d dupes=%d family=%d offered_carried=%d | %s",
  carried_n, pool_n, dupes, family_n, #offered_carried,
  table.concat(offered_carried, ","))
')

printf '  %s\n' "$report"

case "$report" in
	NO-*|LUA-ERROR:*|CLI-*)
		bad "the offer pools are readable" "$report"
		summary "buff_pool"
		exit $?
		;;
esac

# Anchored at the start of the line. `.*carried=` is greedy and matches the
# LAST occurrence, which is `offered_carried=` -- so an unanchored pattern
# silently reports the wrong number and the summary contradicts the report line
# printed directly above it.
carried=$(printf '%s' "$report" | sed -n 's/^carried=\([0-9]*\).*/\1/p')
family=$(printf '%s' "$report" | sed -n 's/.* family=\([0-9]*\).*/\1/p')

# The headline assertion: nothing you already hold is still on offer.
assert_contains "$report" "offered_carried=0" "no carried buff is still in an offer pool"

# A pool with the same name in it more than once is the append bug in progress.
assert_contains "$report" "dupes=0" "no buff appears twice in the offer pools"

# 1,422 was the observed runaway. A real family pool is tens of entries, so a
# few hundred already means something is appending in a loop.
#
# An empty pool is reported rather than passed: before a family is chosen there
# is nothing to run away, and "0 is less than 200" is a pass that looked at
# nothing.
if [ "${family:-0}" -eq 0 ]; then
	printf '  --   the family pool is empty; no family chosen yet, so the size check is vacuous\n'
elif [ "${family:-0}" -lt 200 ]; then
	ok "the family pool is a sane size ($family)"
else
	bad "the family pool is a sane size" \
		"$family entries -- the family is being re-applied in a loop"
fi

if [ "${carried:-0}" -gt 0 ]; then
	ok "the run is carrying buffs to check against ($carried)"
else
	printf '  --   nothing carried yet; the exclusion assertions above are vacuous\n'
fi

summary "buff_pool"
