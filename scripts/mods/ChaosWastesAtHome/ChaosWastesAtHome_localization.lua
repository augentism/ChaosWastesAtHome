return {
	mod_name = {
		en = "Chaos Wastes at Home",
		["zh-cn"] = "单人混沌荒原",
	},
	mod_description = {
		en = "Brings the Mortis Trials buff system into regular solo missions: pick a buff family on spawn, then earn family buffs and legendary card picks as you play. Singleplay sessions only.",
		["zh-cn"] = "将死灵试炼的增益体系移植到普通单人对局：开局选择增益派系，游玩过程中获取派系增益与传说卡牌，仅单人模式生效。",
	},

	-- The one menu key -------------------------------------------------------
	menu_keybind = {
		en = "Open the Chaos Wastes menu",
	},
	menu_keybind_description = {
		en = "One key for every screen. In the Mourningstar it opens the run launcher, with a tab across to the rollable-buff settings. In a mission it shows the buffs collected so far and pauses the game while it is open. Pressing it again closes whatever is open.",
	},
	open_menu = {
		en = "Open the menu",
	},
	open_menu_description = {
		en = "The same thing the keybind does, for anyone who has not bound a key.",
	},
	menu_open_now = {
		en = "Open it now",
	},
	tab_start_run = {
		en = "Start a Crusade",
	},
	tab_rollable_buffs = {
		en = "Rollable Buffs",
	},
	command_cw_menu = {
		en = "open the Chaos Wastes menu for where you are",
	},

	-- Run launcher ----------------------------------------------------------
	open_launch_view = {
		en = "Start a run",
	},
	open_launch_view_description = {
		en = "Opens the run launcher from the Mourningstar: pick a starting difficulty and one of three missions. A run only begins from here, so ordinary missions are left alone.",
	},
	launch_open_now = {
		en = "Open the launcher",
	},
	launch_view_title = {
		en = "Begin a Crusade",
	},
	launch_subtitle = {
		en = "Choose a starting difficulty and a mission.",
	},
	launch_selected = {
		en = "Next: %s",
	},
	launch_no_missions = {
		en = "No eligible missions found.",
	},
	launch_difficulty = {
		en = "Difficulty",
	},
	launch_reroll = {
		en = "Reroll missions",
	},
	launch_begin = {
		en = "Begin the run",
	},
	launch_hub_only = {
		en = "Chaos Wastes at Home: a run can only be started from the Mourningstar.",
	},
	command_cw_launch = {
		en = "open the run launcher",
	},

	-- Buff toggle menu ------------------------------------------------------
	open_buff_toggle_view = {
		en = "Rollable buffs",
	},
	open_buff_toggle_view_description = {
		en = "Opens a menu listing every buff that can be rolled, grouped by family and class. Everything is enabled by default; anything you switch off stops appearing in buff choices.",
	},
	buff_toggle_open_none = {
		en = "...",
	},
	buff_toggle_open_now = {
		en = "Open the menu",
	},
	buff_toggle_view_title = {
		en = "Rollable Buffs",
	},
	buff_group_legendary = {
		en = "Legendary",
	},
	buff_group_custom = {
		en = "Custom",
	},
	buff_group_archetype = {
		en = "Class: %s",
	},
	buff_state_on = {
		en = "ON",
	},
	buff_state_off = {
		en = "OFF",
	},
	buff_enable_all = {
		en = "Enable all shown",
	},
	buff_disable_all = {
		en = "Disable all shown",
	},
	buff_reset_all = {
		en = "Re-enable everything",
	},
	buff_kind_family = {
		en = "Family buff",
	},
	buff_kind_legendary = {
		en = "Legendary buff",
	},
	buff_no_description = {
		en = "No description available for this buff.",
	},
	buff_enable_this = {
		en = "Enable this buff",
	},
	buff_disable_this = {
		en = "Disable this buff",
	},
	buff_summary_all_on = {
		en = "All buffs enabled.",
	},
	buff_summary_disabled = {
		en = "%s buff(s) disabled and excluded from every roll.",
	},
	command_cw_buffs = {
		en = "open the rollable-buffs menu",
	},

	-- Collected buffs screen ------------------------------------------------
	buffs_view_keybind = {
		en = "Show collected buffs",
	},
	buffs_view_keybind_description = {
		en = "Opens a screen listing every buff the run has collected so far. Gameplay is paused for as long as it is open, and the same key closes it.",
	},
	buffs_view_title = {
		en = "Buffs Collected",
	},
	buffs_view_summary = {
		en = "%s buffs, %s stacks - family: %s",
	},
	buffs_view_empty = {
		en = "Nothing collected yet.",
	},
	buffs_view_not_in_run = {
		en = "Chaos Wastes at Home: not in a run - nothing to show.",
	},
	command_cw_buffs_held = {
		en = "show the buffs collected this run",
	},

	use_bots = {
		en = "Bring bots",
	},
	use_bots_description = {
		en = "Off by default: a run is solo, with no team. Turn this on to fill the squad with the game's bots. Tertium4Or5 is the recommended companion mod for this - it lets you pick which of your own characters take the bot slots, and can raise the team size. Leaving this off suppresses bots entirely, which the game would otherwise spawn on its own.",
	},

	difficulty_ramp = {
		en = "Ramp difficulty each mission",
		["zh-cn"] = "每局逐步提升难度",
	},
	difficulty_ramp_description = {
		en = "Each mission in a run is one rung harder than the last: up through the normal difficulties to Auric, then into Havoc at rank 25 and +5 per mission. Havoc missions roll two random modifiers and always carry the Emperor's Fading Light, which reaches its second tier at rank 30. Turn off to keep every mission at the run's starting difficulty.",
		["zh-cn"] = "连贯流程中每局难度升一档，逐级提升至黄金难度；达到25级后开启浩劫，每局浩劫段位+5。浩劫对局会随机两条词条，永久附带「帝皇之光渐微」，30级解锁二阶效果。关闭后所有对局保持开局难度不变。",
	},
	preload_horde_assets = {
		en = "Load Mortis assets",
		["zh-cn"] = "预加载荒原资源",
	},
	preload_horde_assets_description = {
		en = "Loads the Mortis mission package so buff icons and buff particle effects render properly. Without it the cards show placeholders and buff effects are skipped. Measured at about half a second on a warm cache, up to three seconds on the first load after launching the game. Paid once per run rather than per mission, and it streams in alongside the mission's own assets rather than holding up the load.",
	},
	end_screen_extra_seconds = {
		en = "Extra seconds on the end screen",
		["zh-cn"] = "结算界面额外停留时长",
	},
	end_screen_extra_seconds_description = {
		en = "Adds time before the end-of-round screen sends you on, so there is room to read the three missions and choose. The countdown on the continue button reflects the extra time. Only applies during a run; 0 keeps the stock timing.",
		["zh-cn"] = "延长结算等待时间，方便查看并选择下一局任务，继续按钮倒计时同步延长。仅连贯流程生效，填0为原版时长。",
	},
	custom_buff_weight = {
		en = "Custom buff frequency",
	},
	custom_buff_weight_description = {
		en = "How often buffs added by custom_buffs.lua come up in a legendary card pick, relative to the shipped categories (which sit around 1-5). 0 removes them entirely without deleting them.",
	},
	havoc_theme_chance = {
		en = "Havoc theme circumstance chance (%%)",
		["zh-cn"] = "浩劫专属场景概率(%%)",
	},
	havoc_theme_chance_description = {
		en = "How often a Havoc mission also gets its environmental theme - hunting grounds, ventilation purge or toxic gas - on top of its two rolled modifiers. 0 never, 100 always.",
		["zh-cn"] = "浩劫对局额外触发专属环境事件（狩猎场、浓雾、瘟疫毒气）的概率，0=永不触发，100=必定触发。",
	},
	debug_logging = {
		en = "Debug logging",
		["zh-cn"] = "输出调试日志",
	},
	debug_logging_description = {
		en = "Write verbose diagnostics to the console and log file. Off by default; turn it on before reproducing a problem so the log has something useful in it. Never prints to chat.",
		["zh-cn"] = "向控制台与日志文件输出详细诊断信息，默认关闭。复现BUG前开启方便排查，不会在聊天栏刷屏。",
	},

	-- Budget ---------------------------------------------------------------
	group_budget = {
		en = "Buffs per mission",
		["zh-cn"] = "单局增益获取上限",
	},
	pause_on_choice = {
		en = "Pause while choosing",
		["zh-cn"] = "选卡时暂停对局",
	},
	pause_on_choice_description = {
		en = "Freeze gameplay while a buff choice is on screen, so reading the cards cannot get you killed. The card's countdown is held for as long as the pause lasts, so nothing is auto-picked out from under you - take as long as you like. Turn this off to play with the stock 30 second timer instead.",
	},
	max_legendary_choices = {
		en = "Legendary card picks",
		["zh-cn"] = "传说卡牌抽取次数",
	},
	max_legendary_choices_description = {
		en = "How many three-card legendary choices a mission can hand out. Mortis gives 3 per island. Set to 0 to disable legendary picks entirely.",
		["zh-cn"] = "单局最多触发几次三选一传说卡牌，原版荒原每岛3次，填0完全关闭传说卡。",
	},
	max_family_buffs = {
		en = "Family buffs",
		["zh-cn"] = "派系基础增益数量",
	},
	max_family_buffs_description = {
		en = "How many automatic buffs from your chosen family a mission can hand out. Mortis gives 7 per island. Set to 0 to disable family buffs entirely.",
		["zh-cn"] = "单局最多自动获取所选派系的普通增益，原版荒原每岛7个，填0关闭派系增益。",
	},

	-- Objectives -----------------------------------------------------------
	group_objective = {
		en = "Trigger: mission objectives",
		["zh-cn"] = "触发条件：完成任务目标",
	},
	objective_enabled = {
		en = "Grant on objective complete",
		["zh-cn"] = "完成目标发放增益",
	},
	objective_enabled_description = {
		en = "Fires whenever a mission objective is completed. Paces with the mission itself and needs no tuning per map.",
		["zh-cn"] = "每完成一个任务目标触发奖励，适配所有地图，无需单独调整。",
	},
	objective_side_missions = {
		en = "Count side missions",
		["zh-cn"] = "计入支线目标",
	},
	objective_side_missions_description = {
		en = "Also fire for the optional side mission, not just main-path objectives.",
		["zh-cn"] = "除主线目标外，完成可选支线也会触发奖励。",
	},
	objective_grant = {
		en = "Grants",
		["zh-cn"] = "奖励类型",
	},
	objective_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
		["zh-cn"] = "该触发条件发放的奖励，若该类型已达单局上限则切换另一种。",
	},
	objective_chance = {
		en = "Chance (%%)",
		["zh-cn"] = "触发概率(%%)",
	},
	objective_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
		["zh-cn"] = "满足条件时实际发放奖励的几率。",
	},

	-- Kills ----------------------------------------------------------------
	group_kills = {
		en = "Trigger: kills",
		["zh-cn"] = "触发条件：击杀计数",
	},
	kills_enabled = {
		en = "Grant on kill count",
		["zh-cn"] = "累计击杀发放增益",
	},
	kills_enabled_description = {
		en = "Fires every time the kill counter reaches the threshold below. Predictable pacing, but it does reward farming.",
		["zh-cn"] = "击杀数达到设定阈值触发奖励，节奏稳定，但允许刷怪获取增益。",
	},
	kills_mode = {
		en = "Count",
		["zh-cn"] = "统计对象",
	},
	kills_mode_description = {
		en = "Which enemy deaths add to the counter.",
		["zh-cn"] = "选择计入击杀的敌人种类。",
	},
	kills_mode_all = {
		en = "All enemies",
		["zh-cn"] = "所有敌人",
	},
	kills_mode_elites_specials = {
		en = "Elites and specials",
		["zh-cn"] = "精英+特感",
	},
	kills_mode_specials = {
		en = "Specials only",
		["zh-cn"] = "仅特感",
	},
	kills_mode_monsters = {
		en = "Monsters and captains",
		["zh-cn"] = "巨兽+队长",
	},
	kills_threshold = {
		en = "Kills required",
		["zh-cn"] = "所需击杀数",
	},
	kills_threshold_description = {
		en = "How many counted kills between grants.",
		["zh-cn"] = "两次奖励之间需要累计的击杀数量。",
	},
	kills_grant = {
		en = "Grants",
		["zh-cn"] = "奖励类型",
	},
	kills_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
		["zh-cn"] = "该触发条件发放的奖励，若该类型已达单局上限则切换另一种。",
	},
	kills_chance = {
		en = "Chance (%%)",
		["zh-cn"] = "触发概率(%%)",
	},
	kills_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
		["zh-cn"] = "满足击杀条件时实际发放奖励的几率。",
	},

	-- Time -----------------------------------------------------------------
	group_time = {
		en = "Trigger: elapsed time",
		["zh-cn"] = "触发条件：计时周期",
	},
	time_enabled = {
		en = "Grant on a timer",
		["zh-cn"] = "定时发放增益",
	},
	time_enabled_description = {
		en = "Fires on a fixed clock for the whole mission. Fully deterministic, but disconnected from what you are doing.",
		["zh-cn"] = "对局内固定周期触发奖励，完全稳定，但和玩家操作无关。",
	},
	time_interval = {
		en = "Minutes between grants",
		["zh-cn"] = "奖励间隔分钟",
	},
	time_interval_description = {
		en = "How long between timer grants.",
		["zh-cn"] = "两次定时奖励的间隔时长。",
	},
	time_grant = {
		en = "Grants",
		["zh-cn"] = "奖励类型",
	},
	time_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
		["zh-cn"] = "该触发条件发放的奖励，若该类型已达单局上限则切换另一种。",
	},
	time_chance = {
		en = "Chance (%%)",
		["zh-cn"] = "触发概率(%%)",
	},
	time_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
		["zh-cn"] = "计时周期结束后实际发放奖励的几率。",
	},

	-- Terror events --------------------------------------------------------
	group_events = {
		en = "Trigger: event clears",
		["zh-cn"] = "触发条件：清除危机事件",
	},
	events_enabled = {
		en = "Grant on terror event cleared",
		["zh-cn"] = "完成危机事件发放增益",
	},
	events_enabled_description = {
		en = "Fires when the last active terror event ends - ambushes, monster spawns and scripted events. The closest thing a regular mission has to finishing a Mortis wave, but how often it happens varies a lot by map and difficulty.",
		["zh-cn"] = "伏击、巨兽刷新、剧情危机全部清除后触发，相当于普通地图的荒原清波，触发频率随地图与难度浮动。",
	},
	events_grant = {
		en = "Grants",
		["zh-cn"] = "奖励类型",
	},
	events_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
		["zh-cn"] = "该触发条件发放的奖励，若该类型已达单局上限则切换另一种。",
	},
	events_chance = {
		en = "Chance (%%)",
		["zh-cn"] = "触发概率(%%)",
	},
	events_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
		["zh-cn"] = "清除危机事件后实际发放奖励的几率。",
	},

	-- Shared dropdown options ----------------------------------------------
	grant_family = {
		en = "A family buff",
		["zh-cn"] = "派系普通增益",
	},
	grant_legendary = {
		en = "A legendary card pick",
		["zh-cn"] = "抽取传说卡牌",
	},
	grant_random = {
		en = "Either, at random",
		["zh-cn"] = "随机二选一",
	},

	-- Mission chain ---------------------------------------------------------
	picker_title = {
		en = "Continue the Run",
		["zh-cn"] = "继续本次流程",
	},
	picker_subtitle = {
		en = "Choose your next mission. Your buffs carry over.",
		["zh-cn"] = "选择下一局任务，当前所有增益全部保留。",
	},
	picker_default_note = {
		en = "The first is chosen unless you pick another.",
		["zh-cn"] = "未手动选择则默认第一项。",
	},
	picker_option_subtitle = {
		en = "Same difficulty and conditions",
		["zh-cn"] = "难度与当前流程保持一致",
	},
	picker_selected = {
		en = "Next: %s",
		["zh-cn"] = "下一局：%s",
	},

	-- Testing ---------------------------------------------------------------
	group_testing = {
		en = "Testing",
		["zh-cn"] = "测试功能",
	},
	debug_end_mission_won_keybind = {
		en = "End mission as a win",
		["zh-cn"] = "快捷键：胜利结算对局",
	},
	debug_end_mission_won_keybind_description = {
		en = "Instantly completes the current mission so the end screen and the next-mission picker appear. For testing the run chain without walking the whole map.",
		["zh-cn"] = "直接完成当前对局，弹出结算与选关界面，无需完整通关用于测试流程。",
	},
	debug_end_mission_lost_keybind = {
		en = "End mission as a loss",
		["zh-cn"] = "快捷键：失败终止流程",
	},
	debug_end_mission_lost_keybind_description = {
		en = "Instantly fails the current mission, which ends the run. For testing that losing aborts the chain.",
		["zh-cn"] = "直接判定对局失败，终止整套连贯流程，用于测试失败逻辑。",
	},
	debug_end_unavailable = {
		en = "Not in a Chaos Wastes at Home mission - nothing to end.",
		["zh-cn"] = "当前未开启单人荒原流程，无法结束对局。",
	},
	command_cw_win = {
		en = "end the current mission as a win (testing)",
		["zh-cn"] = "指令：胜利结束对局（测试用）",
	},
	command_cw_lose = {
		en = "end the current mission as a loss (testing)",
		["zh-cn"] = "指令：失败结束对局（测试用）",
	},

	-- Commands -------------------------------------------------------------
	command_cw_buff = {
		en = "grant a buff now - /cw_buff [family|legendary]",
		["zh-cn"] = "指令：立即获取增益 - /cw_buff [派系增益|传说卡]",
	},
	command_cw_status = {
		en = "show how many buffs this mission has handed out",
		["zh-cn"] = "指令：查看本局已发放增益数量",
	},
	command_cw_give = {
		en = "grant one buff by name - /cw_give [name or search text]",
	},
	command_cw_verify = {
		en = "check whether the custom buffs are attached and having an effect",
	},
	conflict_auto_restart = {
		en = "Chaos Wastes at Home: TrueSoloQoL's auto-restart is on, so losing will restart the mission instead of ending your run. Turn it off for runs to be loseable.",
		["zh-cn"] = "单人荒原提示：检测到TrueSoloQoL自动重开功能开启，失败只会重开本局而非终止流程，请关闭该功能以正常触发流程结束。",
	},
	command_not_active = {
		en = "Chaos Wastes at Home is not active - it only runs in solo missions.",
		["zh-cn"] = "单人荒原模组未激活，仅单人对局可用该指令。",
	},
	command_failed = {
		en = "Nothing granted: the mission budget is spent, or no buff family has been chosen yet.",
		["zh-cn"] = "发放失败：本局增益上限已用尽，或尚未选择增益派系。",
	},
}
