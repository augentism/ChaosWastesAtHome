local localization = {
	recipe_reload_short = { en = "Reload file" },
	recipe_field_id = { en = "Stable ID" },
	recipe_field_name = { en = "Display name" },
	recipe_field_amount = { en = "Strength / stack (%%)" },
	recipe_field_max_stacks = { en = "Max stacks" },
	recipe_field_duration = { en = "Duration (s)" },
	recipe_field_chance = { en = "Chance (%%)" },
	recipe_field_cooldown = { en = "Cooldown (s)" },
	recipe_editor_new = { en = "New buff" },
	recipe_editor_save = { en = "Save buff" },
	recipe_editor_delete = { en = "Delete saved buff" },
	recipe_editor_reload = { en = "Reload from disk" },
	recipe_list_empty = { en = "No saved buffs yet.\nChoose New buff to begin." },
	recipe_fields = { en = "Buff definition" },
	recipe_live_preview = { en = "Live preview" },
	recipe_confirm = { en = "Confirm" },
	recipe_discard = { en = "Discard unsaved changes to this buff?" },
	recipe_delete_confirm = { en = "Delete saved buff '%s'? The active session copy is unchanged." },
	recipe_enabled = { en = "Included in your catalogue: Yes" },
	recipe_disabled = { en = "Included in your catalogue: No" },
	recipe_unsaved = { en = "Unsaved draft — Save to add these changes to your personal catalogue." },
	recipe_saved = { en = "No unsaved changes. Buffs must still be acquired as reward cards." },
	recipe_pending = { en = "This run's catalogue is locked. Saved changes apply next session; the host's active buffs are unchanged." },
	recipe_personal = { en = "Editing your personal catalogue. Save refreshes the menu; joining a host still uses their buffs. Reload picks up external file edits." },
	recipe_editor = { en = "Player Buff Editor" },
	recipe_editor_enabled = { en = "Include in your catalogue" },
	recipe_editor_legendary = { en = "Legendary card pick" },
	-- Stock popup keys are also declared here for the static localization audit.
	loc_popup_button_cancel = { en = "Cancel" },
	loc_popup_button_close = { en = "Close" },
	shrines_enabled = { en = "Grant from shrines" },
	shrines_enabled_description = { en = "Add shrines to new crusade missions on every difficulty, including Havoc. Each shrine summons a boss and supporting enemies. Defeat its boss to earn a reward; remaining enemies do not delay it. Takes effect next mission." },
	shrines_max = { en = "Maximum shrines per map" },
	shrines_max_description = { en = "Upper limit for new missions, reduced when a map has fewer usable locations. Takes effect next mission." },
	shrines_grant = { en = "Shrine reward" },
	shrines_grant_description = { en = "What defeating a shrine boss grants. Uses the shared mission budgets and falls back to the other reward kind when the selected kind is exhausted. Saved when the shrine is activated." },
	shrines_chance = { en = "Shrine reward chance (%%)" },
	shrines_chance_description = { en = "Chance of a reward when the shrine boss dies. Rolls once per shrine using the setting at activation. The shrine's area benefit is temporary; no permanent Atonement buff is awarded." },
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
		["zh-cn"] = "打开混沌荒原菜单",
	},
	menu_keybind_description = {
		en = "One key for every screen. In the Mourningstar it opens the run launcher, with a tab across to the rollable-buff settings. In a mission it shows the buffs collected so far and pauses the game while it is open. Pressing it again closes whatever is open.",
		ru = "Одна клавиша для всех экранов. На Моунингстаре открывает запуск забега, с вкладкой настроек случайных усилений. В миссии показывает собранные усиления и ставит игру на паузу, пока меню открыто. Повторное нажатие закрывает текущее окно.",
		["zh-cn"] = "单按键接管全部界面。哀星号上开启流程启动器，附带随机增益设置标签；任务内打开已收集增益列表并暂停游戏，再次按下关闭窗口。",
	},
	open_menu = {
		en = "Open the menu",
		ru = "Открыть меню",
		["zh-cn"] = "打开菜单",
	},
	open_menu_description = {
		en = "The same thing the keybind does, for anyone who has not bound a key.",
		ru = "То же, что и клавиша, для тех, кто не назначил клавишу.",
		["zh-cn"] = "功能等同于快捷键，供未绑定按键的玩家使用。",
	},
	menu_open_now = {
		en = "Open it now",
		ru = "Открыть сейчас",
		["zh-cn"] = "立即打开",
	},
	tab_start_run = {
		en = "Start a Crusade",
		ru = "Начать поход",
		["zh-cn"] = "开启远征",
	},
	tab_rollable_buffs = {
		en = "Rollable Buffs",
		ru = "Случайные усиления",
		["zh-cn"] = "随机增益",
	},
	tab_buffs_debuffs = {
		en = "Buffs / Debuffs",
		ru = "Усиления / Ослабления",
		["zh-cn"] = "增益 / 减益",
	},
	tab_havoc_modifiers = {
		en = "Havoc Modifiers",
		ru = "Модификаторы Хаоса",
		["zh-cn"] = "浩劫词缀",
	},
	havoc_modifier_kind = {
		en = "Random Havoc modifier",
		ru = "Случайный модификатор Хаоса",
		["zh-cn"] = "随机浩劫词缀",
	},
	havoc_enable_this = {
		en = "Enable this modifier",
		ru = "Включить модификатор",
		["zh-cn"] = "启用此词缀",
	},
	havoc_disable_this = {
		en = "Disable this modifier",
		ru = "Отключить модификатор",
		["zh-cn"] = "禁用此词缀",
	},
	havoc_pool_summary = {
		en = "%d / %d enabled. Changes apply to new mission rolls.",
		ru = "Включено: %d / %d. Изменения действуют при новом выборе миссий.",
		["zh-cn"] = "已启用 %d / %d。更改将在下次随机任务时生效。",
	},
	havoc_pool_none = {
		en = "No random modifiers. Environment and Fading Light still apply.",
		ru = "Без случайных модификаторов. Окружение и Угасающий свет остаются.",
		["zh-cn"] = "无随机词缀。环境效果与帝皇的黯淡之光仍会生效。",
	},
	tab_collected = {
		en = "Buffs Collected",
		ru = "Собранные усиления",
		["zh-cn"] = "已获取增益",
	},
	command_cw_menu = {
		en = "open the Chaos Wastes menu for where you are",
		ru = "открыть меню Пустошей Хаоса для текущего местоположения",
		["zh-cn"] = "指令：打开对应场景的混沌荒原菜单",
	},

	-- Run launcher ----------------------------------------------------------
	open_launch_view = {
		en = "Start a run",
		ru = "Начать забег",
		["zh-cn"] = "开启流程",
	},
	open_launch_view_description = {
		en = "Opens the run launcher from the Mourningstar: pick a starting difficulty and one of three missions. A run only begins from here, so ordinary missions are left alone.",
		ru = "Открывает запуск забега с Моунингстара: выберите начальную сложность и одну из трёх миссий. Забег начинается только отсюда, обычные миссии не затрагиваются.",
		["zh-cn"] = "在哀星号开启流程启动器，选择起始难度与三选一任务。仅由此处启动荒原流程，普通任务不受影响。",
	},
	launch_open_now = {
		en = "Open the launcher",
		ru = "Открыть запуск",
		["zh-cn"] = "打开启动器",
	},
	launch_view_title = {
		en = "Begin a Crusade",
		ru = "Начать поход",
		["zh-cn"] = "开启远征",
	},
	launch_subtitle = {
		en = "Choose a starting difficulty and a mission.",
		ru = "Выберите начальную сложность и миссию.",
		["zh-cn"] = "选择起始难度与任务。",
	},
	launch_selected = {
		en = "Next: %s",
		ru = "Далее: %s",
		["zh-cn"] = "下一局：%s",
	},
	launch_no_missions = {
		en = "No eligible missions found.",
		ru = "Подходящих миссий не найдено.",
		["zh-cn"] = "未找到可用任务。",
	},
	launch_difficulty = {
		en = "Difficulty",
		ru = "Сложность",
		["zh-cn"] = "难度",
	},
	launch_reroll = {
		en = "Reroll missions",
		ru = "Заменить миссии",
		["zh-cn"] = "刷新任务列表",
	},
	launch_begin = {
		en = "Begin the run",
		ru = "Начать забег",
		["zh-cn"] = "开始流程",
	},
	launch_begin_replace = {
		en = "End run & begin",
		ru = "Завершить забег и начать",
		["zh-cn"] = "终止旧流程并开启新流程",
	},
	launch_hub_only = {
		en = "Chaos Wastes at Home: a run can only be started from the Mourningstar or from one of this mod's own missions.",
		ru = "Пустоши Хаоса у нас дома: забег можно начать только с Моунингстар.",
		["zh-cn"] = "单人混沌荒原：仅可在哀星号或是模组生成的任务内开启流程。",
	},
	command_cw_launch = {
		en = "open the run launcher",
		ru = "открыть запуск забега",
		["zh-cn"] = "指令：打开流程启动器",
	},

	-- Buff toggle menu ------------------------------------------------------
	open_buff_toggle_view = {
		en = "Rollable buffs",
		ru = "Случайные усиления",
		["zh-cn"] = "随机增益",
	},
	open_buff_toggle_view_description = {
		en = "Opens a menu listing every buff that can be rolled, grouped by family and class. Everything is enabled by default; anything you switch off stops appearing in buff choices.",
		ru = "Открывает меню со всеми доступными усилениями, сгруппированными по семействам и классам. По умолчанию всё включено; отключённые усиления перестанут появляться в выборе.",
		["zh-cn"] = "打开增益列表，按派系、职业分组展示全部可刷出增益。默认全部启用，关闭后的增益将不再出现在选卡池。",
	},
	buff_toggle_open_none = {
		en = "...",
		ru = "...",
		["zh-cn"] = "...",
	},
	buff_toggle_open_now = {
		en = "Open the menu",
		ru = "Открыть меню",
		["zh-cn"] = "打开菜单",
	},
	buff_toggle_view_title = {
		en = "Rollable Buffs",
		ru = "Случайные усиления",
		["zh-cn"] = "随机增益",
	},
	buff_group_legendary = {
		en = "Legendary",
		ru = "Легендарные",
		["zh-cn"] = "传说",
	},
	buff_group_custom = {
		en = "Custom",
		ru = "Пользовательские",
		["zh-cn"] = "自定义",
	},
	buff_group_archetype = {
		en = "Class: %s",
		ru = "Класс: %s",
		["zh-cn"] = "职业：%s",
	},
	buff_state_on = {
		en = "ON",
		ru = "ВКЛ",
		["zh-cn"] = "开启",
	},
	buff_state_off = {
		en = "OFF",
		ru = "ВЫКЛ",
		["zh-cn"] = "关闭",
	},
	buff_enable_all = {
		en = "Enable all shown",
		ru = "Включить все показанные",
		["zh-cn"] = "启用全部显示项",
	},
	buff_disable_all = {
		en = "Disable all shown",
		ru = "Отключить все показанные",
		["zh-cn"] = "禁用全部显示项",
	},
	-- Named for what the button DOES, not for the state it is in. The state
	-- reads off the row itself -- an excluded family is dimmed in the list --
	-- and a button labelled with a state gives no clue that it can be clicked.
	family_pick_disable = {
		en = "Disable starting pick",
		["zh-cn"] = "禁用开局派系选择",
	},
	family_pick_enable = {
		en = "Enable starting pick",
		["zh-cn"] = "启用开局派系选择",
	},
	family_pick_unavailable = {
		en = "Select a family",
		["zh-cn"] = "选择一个增益派系",
	},
	buff_reset_all = {
		en = "Re-enable everything",
		ru = "Включить всё заново",
		["zh-cn"] = "全部重新启用",
	},
	buff_kind_family = {
		en = "Family buff",
		ru = "Усиление из одного семейства",
		["zh-cn"] = "派系增益",
	},
	buff_kind_legendary = {
		en = "Legendary buff",
		ru = "Легендарное усиление",
		["zh-cn"] = "传说增益",
	},
	buff_no_description = {
		en = "No description available for this buff.",
		ru = "Для этого усиления нет описания.",
		["zh-cn"] = "该增益暂无描述。",
	},
	buff_enable_this = {
		en = "Enable this buff",
		ru = "Включить это усиление",
		["zh-cn"] = "启用该增益",
	},
	buff_disable_this = {
		en = "Disable this buff",
		ru = "Отключить это усиление",
		["zh-cn"] = "禁用该增益",
	},
	buff_summary_all_on = {
		en = "All buffs enabled.",
		ru = "Все усиления включены.",
		["zh-cn"] = "全部增益已启用。",
	},
	buff_summary_disabled = {
		en = "%s buff(s) disabled and excluded from every roll.",
		ru = "%s усиление(й) отключено и исключено из всех выборов.",
		["zh-cn"] = "%s个增益已禁用，不再参与抽取。",
	},
	command_cw_buffs = {
		en = "open the rollable-buffs menu",
		ru = "открыть меню случайных усилений",
		["zh-cn"] = "指令：打开随机增益菜单",
	},

	-- Collected buffs screen ------------------------------------------------
	buffs_view_keybind = {
		en = "Show collected buffs",
		ru = "Показать собранные усиления",
		["zh-cn"] = "查看已获取增益",
	},
	buffs_view_keybind_description = {
		en = "Opens a screen listing every buff the run has collected so far. Gameplay is paused for as long as it is open, and the same key closes it.",
		ru = "Открывает экран со всеми усилениями, собранными за текущий забег. Игра ставится на паузу, пока экран открыт; повторное нажатие закрывает его.",
		["zh-cn"] = "打开当前流程全部已获得增益列表，打开时暂停对局，再次按下快捷键关闭界面。",
	},
	buffs_view_title = {
		en = "Buffs Collected",
		ru = "Собранные усиления",
		["zh-cn"] = "已获取增益",
	},
	buffs_view_summary = {
		en = "%s buffs, %s stacks - family: %s",
		ru = "%s усилений, %s слоёв - семейство: %s",
		["zh-cn"] = "增益数量：%s，层数：%s，派系：%s",
	},
	buffs_view_empty = {
		en = "Nothing collected yet.",
		ru = "Пока ничего не собрано.",
		["zh-cn"] = "尚未获取任何增益。",
	},
	buffs_view_not_in_run = {
		en = "Chaos Wastes at Home: not in a run - nothing to show.",
		ru = "Пустоши Хаоса у нас дома: вы не в забеге - нечего показывать.",
		["zh-cn"] = "单人混沌荒原：未处于荒原流程，无内容可展示。",
	},
	command_cw_buffs_held = {
		en = "show the buffs collected this run",
		ru = "показать усиления, собранные в этом забеге",
		["zh-cn"] = "指令：查看本次流程已获取增益",
	},

	use_bots = {
		en = "Bring bots",
		ru = "Взять ботов",
		["zh-cn"] = "携带AI队友",
	},
	use_bots_description = {
		en = "Off by default: a run is solo, with no team. Turn this on to fill the squad with the game's bots. Tertium4Or5 is the recommended companion mod for this - it lets you pick which of your own characters take the bot slots, and can raise the team size. Leaving this off suppresses bots entirely, which the game would otherwise spawn on its own.",
		ru = "По умолчанию выключено: забег полностью одиночный, без команды. Включите, чтобы заполнить отряд ботами игры. Рекомендуется использовать мод Tertium4Or5 - он позволяет выбрать, какие ваши персонажи займут слоты ботов, и может увеличить размер команды. Если оставить выключенным, боты не появятся совсем (в обычной игре они бы появились).",
		["zh-cn"] = "默认关闭：流程为纯单人无队友。开启后将由游戏AI填充小队。推荐搭配Tertium4Or5模组，可以指定自己的角色充当AI位并扩大队伍规模。关闭则完全屏蔽游戏原生AI生成。",
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
		["zh-cn"] = "加载死灵试炼资源包，保证增益图标与粒子特效正常显示。不开启会显示占位符，特效丢失。缓存就绪约0.5秒，游戏刚启动首次加载最多3秒。整个流程仅加载一次，与任务资源并行加载，不会拖慢读条。",
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
		["zh-cn"] = "自定义增益权重",
	},
	custom_buff_weight_description = {
		en = "How often buffs added by custom_buffs.lua come up in a legendary card pick, relative to the shipped categories (which sit around 1-5). 0 removes them entirely without deleting them.",
		ru = "Как часто усиления из custom_buffs.lua появляются в легендарных картах, относительно стандартных категорий (у них вес около 1–5). 0 полностью исключает их, не удаляя сами усиления.",
		["zh-cn"] = "控制 custom_buffs.lua 自定义增益在传说卡池的出现概率，原版类别权重1-5。填0会屏蔽自定义增益但不会删除配置。",
	},
	starting_legendary_picks = {
		en = "Starting card picks",
		["zh-cn"] = "开局传说卡牌抽取次数",
	},
	starting_legendary_picks_description = {
		en = "Card picks handed out right after you choose your buff family, before the run's own triggers start. They come first, then the starting family buffs. These are extra: they do not count against the run's card pick limit, so the triggers still hand out their full allowance afterwards.",
		["zh-cn"] = "选定增益派系后、流程触发机制启动前给予的抽卡次数。优先执行抽卡，再发放开局派系增益。属于额外奖励，不计入本局抽卡上限，后续触发仍可拿满额度。",
	},
	starting_family_buffs = {
		en = "Starting family buffs",
		["zh-cn"] = "开局派系增益数量",
	},
	starting_family_buffs_description = {
		en = "Family buffs granted right after the starting card picks. Extra, like the card picks: they do not count against the run's family buff limit.",
		["zh-cn"] = "完成开局抽卡后发放的派系增益。属于额外奖励，不计入本局派系增益上限。",
	},
	havoc_theme_chance = {
		en = "Environment chance",
		ru = "Шанс тематического события Хавока (%%)",
		["zh-cn"] = "浩劫专属场景概率(%%)",
	},
	havoc_theme_chance_description = {
		en = "How often a Havoc mission also gets an environmental modifier - darkness, ventilation purge or toxic gas - on top of its two rolled modifiers. This controls the level itself as well as the card, so at 0 no mission loads with one. 0 never, 100 always.",
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
	protect_while_choosing = {
		en = "Protect players while choosing",
		["zh-cn"] = "选卡期间保护玩家",
	},
	protect_while_choosing_description = {
		en = "While a buff card is on screen, that player cannot be hurt and enemies will not target them. Each player is protected only while their own card is up. This exists because pausing cannot work with other players connected - stopping the clock disconnects them - so without it, reading three cards means standing still in a fight. Safe to leave on alongside pausing; it simply has nothing to do when the game is already stopped.",
		["zh-cn"] = "弹出增益选卡界面时，该玩家免疫伤害，敌人不会锁定目标。仅自身选卡时生效。多人联机无法暂停，开启该功能避免选卡时暴毙；与暂停选项可同时开启，游戏已暂停时该保护不会额外生效。",
	},
	pause_on_choice = {
		en = "Pause while choosing",
		ru = "Пауза при выборе",
		["zh-cn"] = "选卡时暂停对局",
	},
	pause_on_choice_description = {
		en = "Freeze gameplay while a buff choice is on screen, so reading the cards cannot get you killed. The card's countdown is held for as long as the pause lasts, so nothing is auto-picked out from under you - take as long as you like. Turn this off to play with the stock 30 second timer instead.",
		ru = "Замораживает игру, когда на экране выбор усилений, чтобы чтение карт не угрожало вашей жизни. Обратный отсчёт карты приостановлен, пока длится пауза, так что вы не потеряете выбор из-за таймера - берите столько времени, сколько нужно. Отключите, чтобы играть с обычным 30-секундным таймером.",
		["zh-cn"] = "弹出增益选卡时冻结对局，不会被怪物击杀。选卡倒计时同步暂停，不会自动帮你选卡。关闭则使用原版30秒倒计时。",
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
		en = "Interval (minutes)",
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
		["zh-cn"] = "指令：按名称获取增益 - /cw_give [名称或搜索关键词]",
	},
	pause_disabled_multiplayer = {
		en = "Chaos Wastes at Home: pausing is disabled while other players are connected -- stopping the clock disconnects them.",
		["zh-cn"] = "单人混沌荒原：存在其他玩家连接时禁用暂停，暂停会导致队友断开连接。",
	},
	waiting_for_host = {
		en = "Chaos Wastes at Home: waiting for the host to start the next mission - you will be taken there automatically.",
		["zh-cn"] = "单人混沌荒原：等待房主开启下一局任务，将自动跳转。",
	},
	picker_card_votes = {
		en = "%s vote(s)  -  %s",
		["zh-cn"] = "%s票  —  %s",
	},
	picker_vote_subtitle = {
		en = "Vote for where the run goes next - %s vote(s) so far",
		["zh-cn"] = "投票选择下一局任务，当前票数：%s",
	},
	picker_vote_yours = {
		en = "You voted for %s - %s vote(s) so far",
		["zh-cn"] = "你已投票给 %s，当前票数：%s",
	},
	picker_voted = {
		en = "The party voted for %s.",
		["zh-cn"] = "队伍投票选定 %s。",
	},
	settings_section_vote = {
		en = "Voting on the next mission",
		["zh-cn"] = "下一局任务投票设置",
	},
	vote_tiebreak = {
		en = "When a vote ties",
		["zh-cn"] = "投票出现平票时",
	},
	vote_tiebreak_description = {
		en = "Which mission wins when two or more finish level. With only two players every disagreement is a tie, so this decides more often than it sounds like it would. Whichever is chosen, a tie between missions nobody voted for falls to the leftmost card.",
		["zh-cn"] = "多选项票数相同时如何判定。双人对局分歧极易产生平票，该选项生效频率很高；无任何人投票的选项平票，将直接选择最左侧卡片。",
	},
	vote_tiebreak_host = {
		en = "The host decides",
		["zh-cn"] = "由房主决定",
	},
	vote_tiebreak_first = {
		en = "Whoever got there first",
		["zh-cn"] = "优先选择最先出现的选项",
	},
	vote_tiebreak_random = {
		en = "Pick at random",
		["zh-cn"] = "随机抽取",
	},
	command_cw_vote = {
		en = "vote for the next mission - /cw_vote [1|2|3]",
		["zh-cn"] = "指令：为下一局投票 - /cw_vote [1|2|3]",
	},
	command_cw_votes = {
		en = "show the current vote",
		["zh-cn"] = "指令：查看当前投票情况",
	},
	-- VoxPopuli compatibility: the viewers choose the next mission.
	chat_vote_title = {
		en = "Next mission",
		["zh-cn"] = "下一个任务",
	},
	chat_vote_opened = {
		en = "Chaos Wastes: chat is choosing the next mission.",
		["zh-cn"] = "单人混沌荒原：观众正在投票选择下一个任务。",
	},
	chat_picks_mission = {
		en = "Let chat pick the next mission",
	},
	chat_picks_mission_description = {
		en = "With VoxPopuli installed and connected to a chat, the end-of-round vote is handed to the viewers instead of the players. Turn this off to keep choosing yourself; it does nothing without VoxPopuli.",
	},
	-- While the viewers are still voting. %s = the mission in the lead, %d = votes cast.
	picker_vote_chat_leading = {
		en = "Chat is leaning towards %s (%d vote(s))",
		["zh-cn"] = "观众目前倾向于%s（%d票）",
	},
	picker_vote_chat_waiting = {
		en = "Waiting for chat to vote",
		["zh-cn"] = "等待观众投票",
	},
	-- Shown under the cards once the viewers have settled it. %s = the mission.
	picker_vote_chat_won = {
		en = "Chat chose %s",
		["zh-cn"] = "观众选择了%s",
	},
	chat_vote_holding = {
		en = "Chaos Wastes: chat is still voting - the run continues when they are done.",
		["zh-cn"] = "单人混沌荒原：观众仍在投票，投票结束后继续本次流程。",
	},
	chat_vote_result = {
		en = "Chaos Wastes: chat chose %s.",
		["zh-cn"] = "单人混沌荒原：观众选择了%s。",
	},

	vote_opened = {
		en = "Chaos Wastes at Home: vote for the next mission with /cw_vote <number>",
		["zh-cn"] = "单人混沌荒原：使用 /cw_vote <数字> 为下一局任务投票",
	},
	command_cw_carry = {
		en = "show what the run is carrying over, and for whom",
		["zh-cn"] = "指令：查看流程携带的增益与归属玩家",
	},
	command_cw_peers = {
		en = "show connected peers and whether their custom buff ids match",
		["zh-cn"] = "指令：查看联机玩家，校验自定义增益ID一致性",
	},
	net_peer_mismatch = {
		en = "Chaos Wastes at Home: a connected player (%s) is running a different version or different buff ids. Custom buffs are suppressed until it matches - see /cw_peers.",
		["zh-cn"] = "单人混沌荒原：联机玩家(%s)模组版本或自定义增益ID不一致。自定义增益已临时屏蔽，可执行 /cw_peers 查看详情。",
	},
	command_cw_arm = {
		en = "arm a run without launching - for taking over a mission started some other way",
		["zh-cn"] = "指令：预激活荒原流程，接管外部方式开启的对局",
	},
	arm_done = {
		en = "Chaos Wastes at Home: run armed. The next mission you start by any means will be taken over as if the launcher had started it. You do not need this to start a normal run - use Begin Run.",
		["zh-cn"] = "单人混沌荒原：流程已预激活。下一个开启的任务将被接管，如同通过模组启动器开启。正常流程无需使用该指令，请直接使用「开始流程」。",
	},
	command_cw_modifiers = {
		en = "list the modifiers and environment this mission actually loaded",
		ru = "показать модификаторы и окружение, которые действительно загружены в этой миссии",
		["zh-cn"] = "指令：查看当前任务实际加载的词条与环境效果",
	},
	command_cw_verify = {
		en = "check whether the custom buffs are attached and having an effect",
		ru = "проверить, подключены ли пользовательские усиления и работают ли они",
		["zh-cn"] = "指令：校验自定义增益是否正常挂载生效",
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
	ignore_buff_family = {
		en = "Ignore buff families",
		["zh-cn"] = "忽略增益派系限制",
	},
	ignore_buff_family_description = {
		en = "You still choose a family and still get its opening buff, but the small buffs you earn afterwards are drawn from every family instead of only the one you picked - about seventy of them rather than ten. Buffs switched off in Rollable Buffs stay off.",
		["zh-cn"] = "你依旧可以选择一个派系并获得该派系的初始增益，但后续获取的小型增益将从全部派系中抽取，而非仅来自你所选派系——可选增益从10种扩充至约70种。在可刷新增益列表中关闭的增益依旧不会出现。",
	},
	-- Loadouts ---------------------------------------------------------------
	tab_loadouts = {
		en = "Loadouts",
		["zh-cn"] = "配置方案",
	},
	tab_settings = {
		en = "Settings",
		["zh-cn"] = "设置",
	},
	settings_section_run = {
		en = "The run",
		["zh-cn"] = "本局远征",
	},
	settings_section_buffs = {
		en = "Buffs",
		["zh-cn"] = "增益效果",
	},
	settings_section_havoc = {
		en = "Havoc",
		["zh-cn"] = "浩劫",
	},
	settings_section_sources = {
		en = "How buffs are earned",
		["zh-cn"] = "增益获取方式",
	},
	settings_title = {
		en = "Settings",
		["zh-cn"] = "设置",
	},
	settings_on = {
		en = "On",
		["zh-cn"] = "开启",
	},
	settings_off = {
		en = "Off",
		["zh-cn"] = "关闭",
	},
	loadout_change_icon = {
		en = "Change icon",
		["zh-cn"] = "更换图标",
	},
	loadout_title = {
		en = "Loadouts",
		["zh-cn"] = "配置方案",
	},
	loadout_subtitle = {
		en = "Click a loadout to load it. Anything you change afterwards is saved to it automatically.",
		["zh-cn"] = "点击配置方案即可加载。之后的所有改动都会自动保存至该方案。",
	},
	loadout_empty = {
		en = "No loadouts yet. Create one to save your current settings.",
		["zh-cn"] = "暂无配置方案。创建一个来保存你当前的设置。",
	},
	loadout_unavailable = {
		en = "Loadouts are unavailable: this session has no file access.",
		["zh-cn"] = "配置方案不可用：当前会话无法访问文件。",
	},
	loadout_create = {
		en = "New loadout",
		["zh-cn"] = "新建配置方案",
	},
	loadout_set_default = {
		en = "Make default",
		["zh-cn"] = "设为默认",
	},
	loadout_is_default = {
		en = "default",
		["zh-cn"] = "默认",
	},
	loadout_delete = {
		en = "Delete",
		["zh-cn"] = "删除",
	},
	loadout_delete_confirm = {
		en = "Sure?",
		["zh-cn"] = "确定删除？",
	},
}

local mod = get_mod("ChaosWastesAtHome")
local editor = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/recipe_editor_widgets")
for key, value in pairs(editor.localizations()) do localization[key] = value end
return localization
