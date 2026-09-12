return {
	mod_name = {
		en = "Chaos Wastes at Home: Core Blessings",
		ru = "Пустоши Хаоса у нас дома: базовые благословения",
		["zh-cn"] = "单人混沌荒原：核心祝福",
	},
	mod_description = {
		en = "The nine blessings that ship with Chaos Wastes at Home, as a separate pack. Requires Chaos Wastes at Home. Turning this off removes its cards from the roll; it changes nothing else.",
		ru = "Девять благословений из Пустошей Хаоса у нас дома, отдельным набором. Требует Chaos Wastes at Home.",
		["zh-cn"] = "《单人混沌荒原》自带的九个祝福，独立成包。需要 Chaos Wastes at Home。",
	},

	-- Card titles and descriptions ---------------------------------------------
	--
	-- Keys are DERIVED from the buff id -- loc_<id>_title and loc_<id>_description
	-- -- exactly as hordes_buffs_data.lua derives them for the shipped buffs, so
	-- there is no second place for a key and a template to disagree.
	--
	-- These reach the card through DMF's GLOBAL localization database, which
	-- register_buffs writes them into. That database is one flat table shared by
	-- every mod and it refuses to overwrite a key it already holds, which is why
	-- the ids are namespaced and why editing a description needs a full restart
	-- rather than a reload to see.
	--
	-- Remember %% and not %: DMF runs every localization string through
	-- string.format, so a literal per-cent sign is read as a format specifier and
	-- the lookup silently returns nil -- the card then shows the raw key.
	loc_cwah_custom_damage_title = {
		en = "Wrath Unbound",
		["zh-cn"] = "无拘之怒",
	},

	loc_cwah_custom_damage_description = {
		en = "Increases all damage you deal by %s.",
		["zh-cn"] = "你的所有伤害提高%s。",
	},

	loc_cwah_custom_toughness_on_elite_kill_title = {
		en = "Bulwark",
		["zh-cn"] = "壁垒",
	},

	loc_cwah_custom_toughness_on_elite_kill_description = {
		en = "Killing an elite restores %s toughness.",
		["zh-cn"] = "击杀一名精英敌人恢复%s韧性。",
	},

	loc_cwah_crit_ramp_title = {
		en = "Building Fury",
		["zh-cn"] = "怒火积蓄",
	},

	loc_cwah_crit_ramp_description = {
		en = "Every hit that does not critically strike raises your critical chance by %s. Resets when you critically strike.",
		["zh-cn"] = "每一次非暴击命中都会提升%s暴击几率。触发暴击后重置。",
	},

	loc_cwah_attack_speed_ramp_title = {
		en = "Relentless",
		["zh-cn"] = "永不停歇",
	},

	loc_cwah_attack_speed_ramp_description = {
		en = "Every hit raises your attack speed by %s, up to %s. Resets after %s seconds without attacking.",
		["zh-cn"] = "每次命中提升%s攻击速度，最高%s。停止攻击%s秒后重置。",
	},

	loc_cwah_status_cascade_title = {
		en = "Contagion",
		["zh-cn"] = "疫病蔓延",
	},

	loc_cwah_status_cascade_description = {
		en = "Whenever you afflict an enemy with a status effect, they suffer a second one at random - soulblaze, fire, electrocution, bleed, chem toxin or brittleness.",
		["zh-cn"] = "每当你给敌人施加一种异常状态，会随机附加另一种异常：魂火、灼烧、电击、流血、化学毒素或脆化。",
	},

	loc_cwah_flayer_title = {
		en = "Flayer",
		["zh-cn"] = "碎颅者",
	},

	loc_cwah_flayer_description = {
		en = "Every hit has a %s chance to burst the target's skull.",
		["zh-cn"] = "每次命中有%s概率击碎目标头颅。",
	},

	loc_cwah_proliferation_title = {
		en = "Proliferation",
		["zh-cn"] = "扩散侵染",
	},

	loc_cwah_proliferation_description = {
		en = "When an enemy you have afflicted dies, every status effect on it spreads to nearby enemies.",
		["zh-cn"] = "被你施加异常的敌人死亡时，其身上全部异常状态会扩散至周围敌人。",
	},

	loc_cwah_arc_chain_title = {
		en = "Chain Lightning",
		["zh-cn"] = "连锁闪电",
	},

	loc_cwah_arc_chain_description = {
		en = "Hits have a %s chance to arc lightning through up to %s nearby enemies, damaging and electrocuting each. An enemy the lightning has just passed through cannot start another arc for %s second(s).",
		["zh-cn"] = "命中有%s概率释放闪电，最多连锁%s名附近敌人，造成伤害并施加电击。刚被闪电传导过的敌人%s秒内不会再次触发连锁。",
	},

	loc_cwah_multishot_title = {
		en = "Multishot",
		["zh-cn"] = "多重射击",
	},

	loc_cwah_multishot_description = {
		en = "Ranged weapons fire %s shots at once, fanned out horizontally, for the same ammunition.",
		["zh-cn"] = "远程武器一次消耗同等弹药，横向散射%s发子弹。",
	},
}
