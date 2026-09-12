local mod = get_mod("CwahBuffs")

mod.version = "1.0.0"

-- The blessing pack that ships with Chaos Wastes at Home.
--
-- It is a separate mod for one reason: to prove the addon API can carry a real
-- card pack. Everything here goes through cwah.register_buffs, the same public
-- call a third-party pack makes, so if this pack works the API is sufficient --
-- and if it stops working, the API broke rather than the cards.
--
-- Registration happens in on_all_mods_loaded rather than at file scope, and that
-- is the whole trick to load order: by then get_mod resolves Chaos Wastes at
-- Home whatever the order in mod_load_order.txt, so this mod can sit anywhere in
-- the list. Registration on the other side is immediate rather than batched, so
-- there is nothing to wait for afterwards either.

-- Not a DMF method -- Chaos Wastes at Home defines its own, gated behind its
-- debug_logging setting. This forwards to it rather than adding a second switch
-- for a player to find, so turning that one on produces this pack's lines too.
function mod:debug_log(...)
	local cwah = get_mod("ChaosWastesAtHome")

	if cwah and cwah.debug_log then
		return cwah:debug_log(...)
	end
end

mod.on_all_mods_loaded = function ()
	if not mod:is_enabled() then
		return
	end

	local cwah = get_mod("ChaosWastesAtHome")

	-- Checked by feature, not by version: an older Chaos Wastes at Home has no
	-- addon API at all, and a newer one might have a different version number for
	-- reasons that do not concern us.
	if not cwah or type(cwah.register_buffs) ~= "function" then
		mod:error("Chaos Wastes at Home is missing or too old for the blessing API - no cards registered. Update it, or remove this mod.")

		return
	end

	-- Loaded here and NOWHERE else: mod:io_dofile re-executes rather than
	-- caching, so a second loader would get its own catalogue, its own copies of
	-- arc_chain and multishot, and a second registration of multishot's hooks
	-- that DMF would log as a rehook and drop.
	local pack = mod:io_dofile("CwahBuffs/scripts/mods/CwahBuffs/catalogue")

	pack.register()
end
