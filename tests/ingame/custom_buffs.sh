#!/usr/bin/env bash
# Custom buff registration. Read-only: this starts nothing and changes nothing.
#
# A mod-added buff template needs TWO registrations, and each missing piece
# crashes only when the buff is APPLIED -- never when it is offered. So a card
# renders perfectly right up until you pick it, which is the worst possible time
# to find out.
#
#   1. template.name must equal its key in BuffTemplates. The game does this
#      itself in _create_entry, which a mod-added table bypasses, and
#      BuffExtensionBase._add_buff uses it as a key into _stacking_buffs --
#      a nil key is "table index is nil".
#   2. The name must be in NetworkLookup.buff_templates. _add_rpc_synced_buff
#      reads the id BEFORE it checks player.remote, so this crashes in solo too.
#
# That lookup is bidirectional and only __index is guarded, so membership must
# be tested with rawget: a plain read of a missing key IS the crash.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

printf 'custom_buffs\n'

if ! game_is_up; then
	printf '  SKIP game is not reachable\n'
	exit 111
fi

# mod.custom_buff_id_map is the parked accessor; custom_buffs.lua itself must
# not be io_dofile'd from here.
report=$(dt '
local mod = get_mod("ChaosWastesAtHome")

-- Two things about this accessor that are easy to get wrong, and both fail
-- QUIETLY rather than loudly:
--
--   1. It is a FUNCTION, not a table. Read as a table you get a function
--      reference, pairs() over it yields nothing, and every check below runs
--      zero times and reports a clean pass.
--   2. It returns an ARRAY OF "name=id" STRINGS, not a name -> id hash. It is
--      built for the peer handshake and the log. Iterating it as a hash gives
--      you the array indices 1..13 as "names" -- and since the NetworkLookup is
--      bidirectional, rawget(lookup, 1) answers a real buff name, so the
--      membership checks pass against numbers that were never buff names.
local ok_ids, raw = pcall(mod.custom_buff_id_map)

if not ok_ids or type(raw) ~= "table" then
  return "NO-ID-MAP"
end

local ids = {}

for _, entry in ipairs(raw) do
  local name, id = tostring(entry):match("^(.-)=(.*)$")

  if name then
    ids[name] = tonumber(id)
  end
end

if next(ids) == nil then
  return "ID-MAP-UNPARSEABLE"
end

-- BuffTemplates is NOT a global. settings() creates none -- it is literally
-- `return data_table` -- so BuffTemplates, Breeds and the rest exist only as
-- module return values. rawget(_G, "BuffTemplates") is nil, and a guard written
-- against it passes vacuously.
--
-- Requiring it here is safe where it would not be at boot: the game is fully
-- loaded and the module is already in package.loaded, so this returns the cache
-- without executing anything. A speculative require during mod load is the one
-- that poisons the module permanently.
local ok_templates, templates = pcall(require, "scripts/settings/buff/buff_templates")

-- NetworkLookup, by contrast, really is a global, built once at boot.
local network_lookup = rawget(_G, "NetworkLookup")
local lookup = network_lookup and network_lookup.buff_templates

if not ok_templates or type(templates) ~= "table" then return "NO-BUFF-TEMPLATES" end
if not lookup then return "NO-NETWORK-LOOKUP" end

local total, bad_name, missing_id, mismatched, wrong_id = 0, {}, {}, {}, {}

for name, mod_id in pairs(ids) do
  total = total + 1

  local template = templates[name]

  if not template then
    bad_name[#bad_name + 1] = name .. "(no template)"
  elseif template.name ~= name then
    bad_name[#bad_name + 1] = name .. "(name=" .. tostring(template.name) .. ")"
  end

  -- rawget, deliberately: the lookup metatable errors on an unknown key, so a
  -- plain read here would be the crash this test exists to prevent.
  local id = rawget(lookup, name)

  if id == nil then
    missing_id[#missing_id + 1] = name
  else
    -- Bidirectional: t[i] = name and t[name] = i. Both directions have to
    -- agree, or a peer decoding our id lands on a different buff.
    if rawget(lookup, id) ~= name then
      mismatched[#mismatched + 1] = name
    end

    -- And the id the mod published to peers must be the id actually in the
    -- lookup. A disagreement here is the crash the handshake exists to stop.
    if mod_id ~= nil and mod_id ~= id then
      wrong_id[#wrong_id + 1] = string.format("%s(published %s, lookup %s)",
        name, tostring(mod_id), tostring(id))
    end
  end
end

return string.format("total=%d bad_name=%d missing_id=%d mismatched=%d wrong_id=%d | %s | %s | %s | %s",
  total, #bad_name, #missing_id, #mismatched, #wrong_id,
  table.concat(bad_name, ","), table.concat(missing_id, ","),
  table.concat(mismatched, ","), table.concat(wrong_id, ","))
')

printf '  %s\n' "$report"

case "$report" in
	NO-*|LUA-ERROR:*|CLI-*)
		bad "custom buff registration is readable" "$report"
		summary "custom_buffs"
		exit $?
		;;
esac

total=$(printf '%s' "$report" | sed -n 's/.*total=\([0-9]*\).*/\1/p')

if [ "${total:-0}" -gt 0 ]; then
	ok "custom buffs are registered ($total)"
else
	bad "custom buffs are registered" "the id map is empty"
fi

assert_contains "$report" "bad_name=0" "every template.name matches its table key"
assert_contains "$report" "missing_id=0" "every custom buff is in NetworkLookup.buff_templates"
assert_contains "$report" "mismatched=0" "the lookup round-trips name -> id -> name"
assert_contains "$report" "wrong_id=0" "the ids published to peers match the live lookup"

# The mod's own self-check, which knows about things this script does not.
verify=$(dt '
local mod = get_mod("ChaosWastesAtHome")
local custom_buffs = mod._custom_buffs_report
if type(custom_buffs) == "function" then return custom_buffs() end
return "NO-REPORT-ACCESSOR"
')

case "$verify" in
	NO-REPORT-ACCESSOR)
		printf '  --   /cw_verify has no parked accessor; skipping its report\n'
		;;
	*)
		assert_not_contains "$verify" "MISSING" "the mod's own buff report is clean"
		;;
esac

summary "custom_buffs"
