return {
	mod_name = {
		en = "Chaos Wastes at Home",
		ru = "Пустоши Хаоса у нас дома",
		["zh-cn"] = "单人混沌荒原",
	},
	mod_description = {
		en = "Brings the Mortis Trials buff system into regular solo missions: pick a buff family on spawn, then earn family buffs and legendary card picks as you play. Singleplay sessions only.",
		ru = "Chaos Wastes at Home - Переносит систему усилений из Испытаний Мортис в обычные одиночные миссии: при входе выберите семейство усилений, затем получайте усиления семейства и легендарные карты по ходу игры. Только одиночная игра.",
		["zh-cn"] = "将死灵试炼的增益体系移植到普通单人对局：开局选择增益派系，游玩过程中获取派系增益与传说卡牌，仅单人模式生效。",
	},

	-- The one menu key -------------------------------------------------------
	menu_keybind = {
		en = "Open the Chaos Wastes menu",
		ru = "Открыть меню Пустошей Хаоса",
	},
	menu_keybind_description = {
		en = "One key for every screen. In the Mourningstar it opens the run launcher, with a tab across to the rollable-buff settings. In a mission it shows the buffs collected so far and pauses the game while it is open. Pressing it again closes whatever is open.",
		ru = "Одна клавиша для всех экранов. На Моунингстаре открывает запуск забега, с вкладкой настроек случайных усилений. В миссии показывает собранные усиления и ставит игру на паузу, пока меню открыто. Повторное нажатие закрывает текущее окно.",
	},
	open_menu = {
		en = "Open the menu",
		ru = "Открыть меню",
	},
	open_menu_description = {
		en = "The same thing the keybind does, for anyone who has not bound a key.",
		ru = "То же, что и клавиша, для тех, кто не назначил клавишу.",
	},
	menu_open_now = {
		en = "Open it now",
		ru = "Открыть сейчас",
	},
	tab_start_run = {
		en = "Start a Crusade",
		ru = "Начать поход",
	},
	tab_rollable_buffs = {
		en = "Rollable Buffs",
		ru = "Случайные усиления",
	},
	command_cw_menu = {
		en = "open the Chaos Wastes menu for where you are",
		ru = "открыть меню Пустошей Хаоса для текущего местоположения",
	},

	-- Run launcher ----------------------------------------------------------
	open_launch_view = {
		en = "Start a run",
		ru = "Начать забег",
	},
	open_launch_view_description = {
		en = "Opens the run launcher from the Mourningstar: pick a starting difficulty and one of three missions. A run only begins from here, so ordinary missions are left alone.",
		ru = "Открывает запуск забега с Моунингстара: выберите начальную сложность и одну из трёх миссий. Забег начинается только отсюда, обычные миссии не затрагиваются.",
	},
	launch_open_now = {
		en = "Open the launcher",
		ru = "Открыть запуск",
	},
	launch_view_title = {
		en = "Begin a Crusade",
		ru = "Начать поход",
	},
	launch_subtitle = {
		en = "Choose a starting difficulty and a mission.",
		ru = "Выберите начальную сложность и миссию.",
	},
	launch_selected = {
		en = "Next: %s",
		ru = "Далее: %s",
	},
	launch_no_missions = {
		en = "No eligible missions found.",
		ru = "Подходящих миссий не найдено.",
	},
	launch_difficulty = {
		en = "Difficulty",
		ru = "Сложность",
	},
	launch_reroll = {
		en = "Reroll missions",
		ru = "Заменить миссии",
	},
	launch_begin = {
		en = "Begin the run",
		ru = "Начать забег",
	},
	launch_hub_only = {
		en = "Chaos Wastes at Home: a run can only be started from the Mourningstar.",
		ru = "Пустоши Хаоса у нас дома: забег можно начать только с Моунингстар.",
	},
	command_cw_launch = {
		en = "open the run launcher",
		ru = "открыть запуск забега",
	},

	-- Buff toggle menu ------------------------------------------------------
	open_buff_toggle_view = {
		en = "Rollable buffs",
		ru = "Случайные усиления",
	},
	open_buff_toggle_view_description = {
		en = "Opens a menu listing every buff that can be rolled, grouped by family and class. Everything is enabled by default; anything you switch off stops appearing in buff choices.",
		ru = "Открывает меню со всеми доступными усилениями, сгруппированными по семействам и классам. По умолчанию всё включено; отключённые усиления перестанут появляться в выборе.",
	},
	buff_toggle_open_none = {
		en = "...",
		ru = "...",
	},
	buff_toggle_open_now = {
		en = "Open the menu",
		ru = "Открыть меню",
	},
	buff_toggle_view_title = {
		en = "Rollable Buffs",
		ru = "Случайные усиления",
	},
	buff_group_legendary = {
		en = "Legendary",
		ru = "Легендарные",
	},
	buff_group_custom = {
		en = "Custom",
		ru = "Пользовательские",
	},
	buff_group_archetype = {
		en = "Class: %s",
		ru = "Класс: %s",
	},
	buff_state_on = {
		en = "ON",
		ru = "ВКЛ",
	},
	buff_state_off = {
		en = "OFF",
		ru = "ВЫКЛ",
	},
	buff_enable_all = {
		en = "Enable all shown",
		ru = "Включить все показанные",
	},
	buff_disable_all = {
		en = "Disable all shown",
		ru = "Отключить все показанные",
	},
	buff_reset_all = {
		en = "Re-enable everything",
		ru = "Включить всё заново",
	},
	buff_kind_family = {
		en = "Family buff",
		ru = "Усиление из одного семейства",
	},
	buff_kind_legendary = {
		en = "Legendary buff",
		ru = "Легендарное усиление",
	},
	buff_no_description = {
		en = "No description available for this buff.",
		ru = "Для этого усиления нет описания.",
	},
	buff_enable_this = {
		en = "Enable this buff",
		ru = "Включить это усиление",
	},
	buff_disable_this = {
		en = "Disable this buff",
		ru = "Отключить это усиление",
	},
	buff_summary_all_on = {
		en = "All buffs enabled.",
		ru = "Все усиления включены.",
	},
	buff_summary_disabled = {
		en = "%s buff(s) disabled and excluded from every roll.",
		ru = "%s усиление(й) отключено и исключено из всех выборов.",
	},
	command_cw_buffs = {
		en = "open the rollable-buffs menu",
		ru = "открыть меню случайных усилений",
	},

	-- Collected buffs screen ------------------------------------------------
	buffs_view_keybind = {
		en = "Show collected buffs",
		ru = "Показать собранные усиления",
	},
	buffs_view_keybind_description = {
		en = "Opens a screen listing every buff the run has collected so far. Gameplay is paused for as long as it is open, and the same key closes it.",
		ru = "Открывает экран со всеми усилениями, собранными за текущий забег. Игра ставится на паузу, пока экран открыт; повторное нажатие закрывает его.",
	},
	buffs_view_title = {
		en = "Buffs Collected",
		ru = "Собранные усиления",
	},
	buffs_view_summary = {
		en = "%s buffs, %s stacks - family: %s",
		ru = "%s усилений, %s слоёв - семейство: %s",
	},
	buffs_view_empty = {
		en = "Nothing collected yet.",
		ru = "Пока ничего не собрано.",
	},
	buffs_view_not_in_run = {
		en = "Chaos Wastes at Home: not in a run - nothing to show.",
		ru = "Пустоши Хаоса у нас дома: вы не в забеге - нечего показывать.",
	},
	command_cw_buffs_held = {
		en = "show the buffs collected this run",
		ru = "показать усиления, собранные в этом забеге",
	},

	use_bots = {
		en = "Bring bots",
		ru = "Взять ботов",
	},
	use_bots_description = {
		en = "Off by default: a run is solo, with no team. Turn this on to fill the squad with the game's bots. Tertium4Or5 is the recommended companion mod for this - it lets you pick which of your own characters take the bot slots, and can raise the team size. Leaving this off suppresses bots entirely, which the game would otherwise spawn on its own.",
		ru = "По умолчанию выключено: забег полностью одиночный, без команды. Включите, чтобы заполнить отряд ботами игры. Рекомендуется использовать мод Tertium4Or5 - он позволяет выбрать, какие ваши персонажи займут слоты ботов, и может увеличить размер команды. Если оставить выключенным, боты не появятся совсем (в обычной игре они бы появились).",
	},

	difficulty_ramp = {
		en = "Ramp difficulty each mission",
		ru = "Повышать сложность с каждой миссией",
		["zh-cn"] = "每局逐步提升难度",
	},
	difficulty_ramp_description = {
		en = "Each mission in a run is one rung harder than the last: up through the normal difficulties to Auric, then into Havoc at rank 25 and +5 per mission. Havoc missions roll two random modifiers and always carry the Emperor's Fading Light, which reaches its second tier at rank 30. Turn off to keep every mission at the run's starting difficulty.",
		ru = "Каждая следующая миссия в забеге сложнее предыдущей: от обычных сложностей до золотого уровня, затем в Хаос ранг 25 и +5 за миссию. Миссии Хаоса получают два случайных модификатора и всегда несут «Угасающий свет Императора», достигающий второго уровня на ранге 30. Отключите, чтобы все миссии оставались на начальной сложности.",
		["zh-cn"] = "连贯流程中每局难度升一档，逐级提升至黄金难度；达到25级后开启浩劫，每局浩劫段位+5。浩劫对局会随机两条词条，永久附带「帝皇之光渐微」，30级解锁二阶效果。关闭后所有对局保持开局难度不变。",
	},
	preload_horde_assets = {
		en = "Load Mortis assets",
		ru = "Загрузить ресурсы Мортис",
		["zh-cn"] = "预加载荒原资源",
	},
	preload_horde_assets_description = {
		en = "Loads the Mortis mission package so buff icons and buff particle effects render properly. Without it the cards show placeholders and buff effects are skipped. Measured at about half a second on a warm cache, up to three seconds on the first load after launching the game. Paid once per run rather than per mission, and it streams in alongside the mission's own assets rather than holding up the load.",
		ru = "Загружает пакет миссий Мортис, чтобы иконки и визуальные эффекты усилений отображались корректно. Без этой загрузки карты показывают заглушки, а эффекты пропускаются. Занимает около половины секунды на готовом кэше или до 3 секунд при первом запуске после старта игры. Загружается один раз за забег, а не за миссию, и подгружается параллельно с ресурсами миссии, не задерживая загрузку.",
	},
	end_screen_extra_seconds = {
		en = "Extra seconds on the end screen",
		ru = "Дополнительные секунды на экране завершения",
		["zh-cn"] = "结算界面额外停留时长",
	},
	end_screen_extra_seconds_description = {
		en = "Adds time before the end-of-round screen sends you on, so there is room to read the three missions and choose. The countdown on the continue button reflects the extra time. Only applies during a run; 0 keeps the stock timing.",
		ru = "Добавляет время перед автоматическим переходом с экрана завершения, чтобы вы могли прочитать три миссии и выбрать. Обратный отсчёт на кнопке продолжения учитывает добавленное время. Работает только в забеге; 0 оставляет стандартное время.",
		["zh-cn"] = "延长结算等待时间，方便查看并选择下一局任务，继续按钮倒计时同步延长。仅连贯流程生效，填0为原版时长。",
	},
	custom_buff_weight = {
		en = "Custom buff frequency",
		ru = "Частота пользовательских усилений",
	},
	custom_buff_weight_description = {
		en = "How often buffs added by custom_buffs.lua come up in a legendary card pick, relative to the shipped categories (which sit around 1-5). 0 removes them entirely without deleting them.",
		ru = "Как часто усиления из custom_buffs.lua появляются в легендарных картах, относительно стандартных категорий (у них вес около 1–5). 0 полностью исключает их, не удаляя сами усиления.",
	},
	havoc_theme_chance = {
		en = "Havoc theme circumstance chance (%%)",
		ru = "Шанс тематического события Хавока (%%)",
		["zh-cn"] = "浩劫专属场景概率(%%)",
	},
	havoc_theme_chance_description = {
		en = "How often a Havoc mission also gets its environmental theme - hunting grounds, ventilation purge or toxic gas - on top of its two rolled modifiers. 0 never, 100 always.",
		ru = "Как часто миссия Хавока также получает тематическое окружение - охотничьи угодья, вентиляционную очистку или токсичный газ - в дополнение к двум модификаторам. 0 - никогда, 100 - всегда.",
		["zh-cn"] = "浩劫对局额外触发专属环境事件（狩猎场、浓雾、瘟疫毒气）的概率，0=永不触发，100=必定触发。",
	},
	debug_logging = {
		en = "Debug logging",
		ru = "Логирование отладки",
		["zh-cn"] = "输出调试日志",
	},
	debug_logging_description = {
		en = "Write verbose diagnostics to the console and log file. Off by default; turn it on before reproducing a problem so the log has something useful in it. Never prints to chat.",
		ru = "Записывает подробную диагностику в консоль и лог-файл. По умолчанию выключено; включайте перед воспроизведением проблемы, чтобы в логе была полезная информация. Никогда не пишет в чат.",
		["zh-cn"] = "向控制台与日志文件输出详细诊断信息，默认关闭。复现BUG前开启方便排查，不会在聊天栏刷屏。",
	},

	-- Budget ---------------------------------------------------------------
	group_budget = {
		en = "Buffs per mission",
		ru = "Усиления за миссию",
		["zh-cn"] = "单局增益获取上限",
	},
	pause_on_choice = {
		en = "Pause while choosing",
		ru = "Пауза при выборе",
		["zh-cn"] = "选卡时暂停对局",
	},
	pause_on_choice_description = {
		en = "Freeze gameplay while a buff choice is on screen, so reading the cards cannot get you killed. The card's countdown is held for as long as the pause lasts, so nothing is auto-picked out from under you - take as long as you like. Turn this off to play with the stock 30 second timer instead.",
		ru = "Замораживает игру, когда на экране выбор усилений, чтобы чтение карт не угрожало вашей жизни. Обратный отсчёт карты приостановлен, пока длится пауза, так что вы не потеряете выбор из-за таймера - берите столько времени, сколько нужно. Отключите, чтобы играть с обычным 30-секундным таймером.",
	},
	max_legendary_choices = {
		en = "Legendary card picks",
		ru = "Легендарные карты",
		["zh-cn"] = "传说卡牌抽取次数",
	},
	max_legendary_choices_description = {
		en = "How many three-card legendary choices a mission can hand out. Mortis gives 3 per island. Set to 0 to disable legendary picks entirely.",
		ru = "Сколько раз за миссию можно получить выбор из трёх легендарных карт. В Мортис - 3 за остров. Установите 0, чтобы полностью отключить легендарные карты.",
		["zh-cn"] = "单局最多触发几次三选一传说卡牌，原版荒原每岛3次，填0完全关闭传说卡。",
	},
	max_family_buffs = {
		en = "Family buffs",
		ru = "Усиления из одного семейства",
		["zh-cn"] = "派系基础增益数量",
	},
	max_family_buffs_description = {
		en = "How many automatic buffs from your chosen family a mission can hand out. Mortis gives 7 per island. Set to 0 to disable family buffs entirely.",
		ru = "Сколько автоматических усилений из выбранного семейства может выдать одна миссия. В Мортис - 7 за остров. Установите 0, чтобы полностью отключить семейные усиления.",
		["zh-cn"] = "单局最多自动获取所选派系的普通增益，原版荒原每岛7个，填0关闭派系增益。",
	},

	-- Objectives -----------------------------------------------------------
	group_objective = {
		en = "Trigger: mission objectives",
		ru = "Триггер: цели миссии",
		["zh-cn"] = "触发条件：完成任务目标",
	},
	objective_enabled = {
		en = "Grant on objective complete",
		ru = "Выдавать при выполнении цели",
		["zh-cn"] = "完成目标发放增益",
	},
	objective_enabled_description = {
		en = "Fires whenever a mission objective is completed. Paces with the mission itself and needs no tuning per map.",
		ru = "Срабатывает при выполнении любой цели миссии. Идёт в ногу с миссией и не требует настройки под каждую карту.",
		["zh-cn"] = "每完成一个任务目标触发奖励，适配所有地图，无需单独调整。",
	},
	objective_side_missions = {
		en = "Count side missions",
		ru = "Учитывать дополнительные задания",
		["zh-cn"] = "计入支线目标",
	},
	objective_side_missions_description = {
		en = "Also fire for the optional side mission, not just main-path objectives.",
		ru = "Срабатывает также для дополнительных заданий, а не только для основных целей.",
		["zh-cn"] = "除主线目标外，完成可选支线也会触发奖励。",
	},
	objective_grant = {
		en = "Grants",
		ru = "Выдаёт",
		["zh-cn"] = "奖励类型",
	},
	objective_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
		ru = "Что выдаёт этот триггер. Если этот тип уже исчерпан за миссию, вместо него будет выдан другой тип.",
		["zh-cn"] = "该触发条件发放的奖励，若该类型已达单局上限则切换另一种。",
	},
	objective_chance = {
		en = "Chance (%%)",
		ru = "Шанс (%%)",
		["zh-cn"] = "触发概率(%%)",
	},
	objective_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
		ru = "Вероятность, что при срабатывании триггер действительно выдаст награду.",
		["zh-cn"] = "满足条件时实际发放奖励的几率。",
	},

	-- Kills ----------------------------------------------------------------
	group_kills = {
		en = "Trigger: kills",
		ru = "Триггер: убийства",
		["zh-cn"] = "触发条件：击杀计数",
	},
	kills_enabled = {
		en = "Grant on kill count",
		ru = "Выдавать по счётчику убийств",
		["zh-cn"] = "累计击杀发放增益",
	},
	kills_enabled_description = {
		en = "Fires every time the kill counter reaches the threshold below. Predictable pacing, but it does reward farming.",
		ru = "Срабатывает каждый раз, когда счётчик убийств достигает заданного порога. Предсказуемый темп, но поощряет фарм.",
		["zh-cn"] = "击杀数达到设定阈值触发奖励，节奏稳定，但允许刷怪获取增益。",
	},
	kills_mode = {
		en = "Count",
		ru = "Учитывать",
		["zh-cn"] = "统计对象",
	},
	kills_mode_description = {
		en = "Which enemy deaths add to the counter.",
		ru = "Какие враги добавляются к счётчику.",
		["zh-cn"] = "选择计入击杀的敌人种类。",
	},
	kills_mode_all = {
		en = "All enemies",
		ru = "Все враги",
		["zh-cn"] = "所有敌人",
	},
	kills_mode_elites_specials = {
		en = "Elites and specials",
		ru = "Элитные и специалисты",
		["zh-cn"] = "精英+特感",
	},
	kills_mode_specials = {
		en = "Specials only",
		ru = "Только специалисты",
		["zh-cn"] = "仅特感",
	},
	kills_mode_monsters = {
		en = "Monsters and captains",
		ru = "Монстры и капитаны",
		["zh-cn"] = "巨兽+队长",
	},
	kills_threshold = {
		en = "Kills required",
		ru = "Требуется убийств",
		["zh-cn"] = "所需击杀数",
	},
	kills_threshold_description = {
		en = "How many counted kills between grants.",
		ru = "Сколько учтённых убийств между наградами.",
		["zh-cn"] = "两次奖励之间需要累计的击杀数量。",
	},
	kills_grant = {
		en = "Grants",
		ru = "Выдаёт",
		["zh-cn"] = "奖励类型",
	},
	kills_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
		ru = "Что выдаёт этот триггер. Если этот тип уже исчерпан за миссию, вместо него будет выдан другой тип.",
		["zh-cn"] = "该触发条件发放的奖励，若该类型已达单局上限则切换另一种。",
	},
	kills_chance = {
		en = "Chance (%%)",
		ru = "Шанс (%%)",
		["zh-cn"] = "触发概率(%%)",
	},
	kills_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
		ru = "Вероятность, что при срабатывании триггер действительно выдаст награду.",
		["zh-cn"] = "满足击杀条件时实际发放奖励的几率。",
	},

	-- Time -----------------------------------------------------------------
	group_time = {
		en = "Trigger: elapsed time",
		ru = "Триггер: время",
		["zh-cn"] = "触发条件：计时周期",
	},
	time_enabled = {
		en = "Grant on a timer",
		ru = "Выдавать по таймеру",
		["zh-cn"] = "定时发放增益",
	},
	time_enabled_description = {
		en = "Fires on a fixed clock for the whole mission. Fully deterministic, but disconnected from what you are doing.",
		ru = "Срабатывает по фиксированному расписанию на протяжении всей миссии. Полностью детерминировано, но не зависит от ваших действий.",
		["zh-cn"] = "对局内固定周期触发奖励，完全稳定，但和玩家操作无关。",
	},
	time_interval = {
		en = "Minutes between grants",
		ru = "Минуты между выдачами",
		["zh-cn"] = "奖励间隔分钟",
	},
	time_interval_description = {
		en = "How long between timer grants.",
		ru = "Интервал между срабатываниями таймера.",
		["zh-cn"] = "两次定时奖励的间隔时长。",
	},
	time_grant = {
		en = "Grants",
		ru = "Выдаёт",
		["zh-cn"] = "奖励类型",
	},
	time_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
		ru = "Что выдаёт этот триггер. Если этот тип уже исчерпан за миссию, вместо него будет выдан другой тип.",
		["zh-cn"] = "该触发条件发放的奖励，若该类型已达单局上限则切换另一种。",
	},
	time_chance = {
		en = "Chance (%%)",
		ru = "Шанс (%%)",
		["zh-cn"] = "触发概率(%%)",
	},
	time_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
		ru = "Вероятность, что при срабатывании триггер действительно выдаст награду.",
		["zh-cn"] = "计时周期结束后实际发放奖励的几率。",
	},

	-- Terror events --------------------------------------------------------
	group_events = {
		en = "Trigger: event clears",
		ru = "Триггер: завершение событий",
		["zh-cn"] = "触发条件：清除危机事件",
	},
	events_enabled = {
		en = "Grant on terror event cleared",
		ru = "Выдавать при завершении события ужаса",
		["zh-cn"] = "完成危机事件发放增益",
	},
	events_enabled_description = {
		en = "Fires when the last active terror event ends - ambushes, monster spawns and scripted events. The closest thing a regular mission has to finishing a Mortis wave, but how often it happens varies a lot by map and difficulty.",
		ru = "Срабатывает при завершении последнего активного события ужаса - засад, появления монстров и сценарных событий. Это ближайший аналог завершения волны в обычной миссии, но частота сильно зависит от карты и сложности.",
		["zh-cn"] = "伏击、巨兽刷新、剧情危机全部清除后触发，相当于普通地图的荒原清波，触发频率随地图与难度浮动。",
	},
	events_grant = {
		en = "Grants",
		ru = "Выдаёт",
		["zh-cn"] = "奖励类型",
	},
	events_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
		ru = "Что выдаёт этот триггер. Если этот тип уже исчерпан за миссию, вместо него будет выдан другой тип.",
		["zh-cn"] = "该触发条件发放的奖励，若该类型已达单局上限则切换另一种。",
	},
	events_chance = {
		en = "Chance (%%)",
		ru = "Шанс (%%)",
		["zh-cn"] = "触发概率(%%)",
	},
	events_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
		ru = "Вероятность, что при срабатывании триггер действительно выдаст награду.",
		["zh-cn"] = "清除危机事件后实际发放奖励的几率。",
	},

	-- Shared dropdown options ----------------------------------------------
	grant_family = {
		en = "A family buff",
		ru = "Усиление из семейства",
		["zh-cn"] = "派系普通增益",
	},
	grant_legendary = {
		en = "A legendary card pick",
		ru = "Легендарная карта",
		["zh-cn"] = "抽取传说卡牌",
	},
	grant_random = {
		en = "Either, at random",
		ru = "Случайное (любое)",
		["zh-cn"] = "随机二选一",
	},

	-- Mission chain ---------------------------------------------------------
	picker_title = {
		en = "Continue the Run",
		ru = "Продолжить забег",
		["zh-cn"] = "继续本次流程",
	},
	picker_subtitle = {
		en = "Choose your next mission. Your buffs carry over.",
		ru = "Выберите следующую миссию. Ваши усиления сохранятся.",
		["zh-cn"] = "选择下一局任务，当前所有增益全部保留。",
	},
	picker_default_note = {
		en = "The first is chosen unless you pick another.",
		ru = "Будет выбрана первая, если вы не выберете другую.",
		["zh-cn"] = "未手动选择则默认第一项。",
	},
	picker_option_subtitle = {
		en = "Same difficulty and conditions",
		ru = "Те же сложность и условия",
		["zh-cn"] = "难度与当前流程保持一致",
	},
	picker_selected = {
		en = "Next: %s",
		ru = "Далее: %s",
		["zh-cn"] = "下一局：%s",
	},

	-- Testing ---------------------------------------------------------------
	group_testing = {
		en = "Testing",
		ru = "Тестирование",
		["zh-cn"] = "测试功能",
	},
	debug_end_mission_won_keybind = {
		en = "End mission as a win",
		ru = "Завершить миссию победой",
		["zh-cn"] = "快捷键：胜利结算对局",
	},
	debug_end_mission_won_keybind_description = {
		en = "Instantly completes the current mission so the end screen and the next-mission picker appear. For testing the run chain without walking the whole map.",
		ru = "Мгновенно завершает текущую миссию, показывая экран завершения и выбор следующей миссии. Для тестирования цепочки забега без прохождения всей карты.",
		["zh-cn"] = "直接完成当前对局，弹出结算与选关界面，无需完整通关用于测试流程。",
	},
	debug_end_mission_lost_keybind = {
		en = "End mission as a loss",
		ru = "Завершить миссию поражением",
		["zh-cn"] = "快捷键：失败终止流程",
	},
	debug_end_mission_lost_keybind_description = {
		en = "Instantly fails the current mission, which ends the run. For testing that losing aborts the chain.",
		ru = "Мгновенно проваливает текущую миссию, завершая забег. Для тестирования, что поражение прерывает цепочку.",
		["zh-cn"] = "直接判定对局失败，终止整套连贯流程，用于测试失败逻辑。",
	},
	debug_end_unavailable = {
		en = "Not in a Chaos Wastes at Home mission - nothing to end.",
		ru = "Вы не в миссии Пустошей Хаоса в одиночку - нечего завершать.",
		["zh-cn"] = "当前未开启单人荒原流程，无法结束对局。",
	},
	command_cw_win = {
		en = "end the current mission as a win (testing)",
		ru = "завершить текущую миссию победой (тестирование)",
		["zh-cn"] = "指令：胜利结束对局（测试用）",
	},
	command_cw_lose = {
		en = "end the current mission as a loss (testing)",
		ru = "завершить текущую миссию поражением (тестирование)",
		["zh-cn"] = "指令：失败结束对局（测试用）",
	},

	-- Commands -------------------------------------------------------------
	command_cw_buff = {
		en = "grant a buff now - /cw_buff [family|legendary]",
		ru = "выдать усиление сейчас - /cw_buff [family|legendary]",
		["zh-cn"] = "指令：立即获取增益 - /cw_buff [派系增益|传说卡]",
	},
	command_cw_status = {
		en = "show how many buffs this mission has handed out",
		ru = "показать, сколько усилений выдано в этой миссии",
		["zh-cn"] = "指令：查看本局已发放增益数量",
	},
	command_cw_give = {
		en = "grant one buff by name - /cw_give [name or search text]",
		ru = "выдать одно усиление по имени - /cw_give [имя или текст поиска]",
	},
	command_cw_verify = {
		en = "check whether the custom buffs are attached and having an effect",
		ru = "проверить, подключены ли пользовательские усиления и работают ли они",
	},
	conflict_auto_restart = {
		en = "Chaos Wastes at Home: TrueSoloQoL's auto-restart is on, so losing will restart the mission instead of ending your run. Turn it off for runs to be loseable.",
		ru = "Пустоши Хаоса у нас дома: включена автоматическая перезагрузка из True Solo QoL, поэтому поражение перезапустит миссию вместо завершения забега. Отключите её, чтобы забег можно было проиграть.",
		["zh-cn"] = "单人荒原提示：检测到TrueSoloQoL自动重开功能开启，失败只会重开本局而非终止流程，请关闭该功能以正常触发流程结束。",
	},
	command_not_active = {
		en = "Chaos Wastes at Home is not active - it only runs in solo missions.",
		ru = "Пустоши Хаоса у нас дома не активны - мод работает только в одиночных миссиях.",
		["zh-cn"] = "单人荒原模组未激活，仅单人对局可用该指令。",
	},
	command_failed = {
		en = "Nothing granted: the mission budget is spent, or no buff family has been chosen yet.",
		ru = "Ничего не выдано: бюджет усилений на миссию исчерпан, или ещё не выбрано семейство усилений.",
		["zh-cn"] = "发放失败：本局增益上限已用尽，或尚未选择增益派系。",
	},

	-- Custom buff cards ------------------------------------------------------
	-- Titles and descriptions for the buffs this mod adds itself. The keys are
	-- derived from the buff id in custom_buffs.lua as loc_<id>_title and
	-- loc_<id>_description, so a key here with no matching catalogue entry (or
	-- the reverse) is logged as an error at load.
	--
	-- %s slots are filled from the mod's own tuning constants at load, in the
	-- order they appear -- keep them in the same order when translating, and
	-- write a literal per-cent as %%%%.
	loc_cwah_custom_damage_title = {
		en = "Wrath Unbound",
	},
	loc_cwah_custom_damage_description = {
		en = "Increases all damage you deal by %s.",
	},
	loc_cwah_custom_toughness_on_elite_kill_title = {
		en = "Bulwark",
	},
	loc_cwah_custom_toughness_on_elite_kill_description = {
		en = "Killing an elite restores %s toughness.",
	},
	loc_cwah_crit_ramp_title = {
		en = "Building Fury",
	},
	loc_cwah_crit_ramp_description = {
		en = "Every hit that does not critically strike raises your critical chance by %s. Resets when you critically strike.",
	},
	loc_cwah_attack_speed_ramp_title = {
		en = "Relentless",
	},
	loc_cwah_attack_speed_ramp_description = {
		en = "Every hit raises your attack speed by %s, up to %s. Resets after %s seconds without attacking.",
	},
	loc_cwah_status_cascade_title = {
		en = "Contagion",
	},
	loc_cwah_status_cascade_description = {
		en = "Whenever you afflict an enemy with a status effect, they suffer a second one at random - soulblaze, fire, electrocution, bleed, chem toxin or brittleness.",
	},
	loc_cwah_flayer_title = {
		en = "Flayer",
	},
	loc_cwah_flayer_description = {
		en = "Every hit has a %s chance to burst the target's skull.",
	},
	loc_cwah_proliferation_title = {
		en = "Proliferation",
	},
	loc_cwah_proliferation_description = {
		en = "When an enemy you have afflicted dies, every status effect on it spreads to nearby enemies.",
	},
	loc_cwah_arc_chain_title = {
		en = "Chain Lightning",
	},
	loc_cwah_arc_chain_description = {
		en = "Hits have a %s chance to arc lightning through up to %s nearby enemies, damaging and electrocuting each. An enemy the lightning has just passed through cannot start another arc for %s second(s).",
	},
	loc_cwah_multishot_title = {
		en = "Multishot",
	},
	loc_cwah_multishot_description = {
		en = "Ranged weapons fire %s shots at once, fanned out horizontally, for the same ammunition.",
	},
}
