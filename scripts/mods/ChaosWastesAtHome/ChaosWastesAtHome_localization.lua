return {
	mod_name = {
		en = "Chaos Wastes at Home",
	},
	mod_description = {
		en = "Brings the Mortis Trials buff system into regular solo missions: pick a buff family on spawn, then earn family buffs and legendary card picks as you play. Singleplay sessions only.",
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

	difficulty_ramp = {
		en = "Ramp difficulty each mission",
	},
	difficulty_ramp_description = {
		en = "Each mission in a run is one rung harder than the last: up through the normal difficulties to Auric, then into Havoc at rank 25 and +5 per mission. Havoc missions roll two random modifiers and always carry the Emperor's Fading Light, which reaches its second tier at rank 30. Turn off to keep every mission at the run's starting difficulty.",
	},
	preload_horde_assets = {
		en = "Load Mortis assets",
	},
	preload_horde_assets_description = {
		en = "Loads the Mortis mission package so buff icons and buff particle effects render properly. Without it the cards show placeholders and buff effects are skipped. Measured at around 3.5 seconds, paid once per run rather than per mission. Turn off if you would rather have the faster load than the artwork.",
	},
	end_screen_extra_seconds = {
		en = "Extra seconds on the end screen",
	},
	end_screen_extra_seconds_description = {
		en = "Adds time before the end-of-round screen sends you on, so there is room to read the three missions and choose. The countdown on the continue button reflects the extra time. Only applies during a run; 0 keeps the stock timing.",
	},
	custom_buff_weight = {
		en = "Custom buff frequency",
	},
	custom_buff_weight_description = {
		en = "How often buffs added by custom_buffs.lua come up in a legendary card pick, relative to the shipped categories (which sit around 1-5). 0 removes them entirely without deleting them.",
	},
	havoc_theme_chance = {
		en = "Havoc theme circumstance chance (%%)",
	},
	havoc_theme_chance_description = {
		en = "How often a Havoc mission also gets its environmental theme - hunting grounds, ventilation purge or toxic gas - on top of its two rolled modifiers. 0 never, 100 always.",
	},
	debug_logging = {
		en = "Debug logging",
	},
	debug_logging_description = {
		en = "Write verbose diagnostics to the console and log file. Off by default; turn it on before reproducing a problem so the log has something useful in it. Never prints to chat.",
	},

	-- Budget ---------------------------------------------------------------
	group_budget = {
		en = "Buffs per mission",
	},
	pause_on_choice = {
		en = "Pause while choosing",
	},
	pause_on_choice_description = {
		en = "Freeze gameplay while a buff choice is on screen, so reading the cards cannot get you killed. The card's countdown is held for as long as the pause lasts, so nothing is auto-picked out from under you - take as long as you like. Turn this off to play with the stock 30 second timer instead.",
	},
	max_legendary_choices = {
		en = "Legendary card picks",
	},
	max_legendary_choices_description = {
		en = "How many three-card legendary choices a mission can hand out. Mortis gives 3 per island. Set to 0 to disable legendary picks entirely.",
	},
	max_family_buffs = {
		en = "Family buffs",
	},
	max_family_buffs_description = {
		en = "How many automatic buffs from your chosen family a mission can hand out. Mortis gives 7 per island. Set to 0 to disable family buffs entirely.",
	},

	-- Objectives -----------------------------------------------------------
	group_objective = {
		en = "Trigger: mission objectives",
	},
	objective_enabled = {
		en = "Grant on objective complete",
	},
	objective_enabled_description = {
		en = "Fires whenever a mission objective is completed. Paces with the mission itself and needs no tuning per map.",
	},
	objective_side_missions = {
		en = "Count side missions",
	},
	objective_side_missions_description = {
		en = "Also fire for the optional side mission, not just main-path objectives.",
	},
	objective_grant = {
		en = "Grants",
	},
	objective_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
	},
	objective_chance = {
		en = "Chance (%%)",
	},
	objective_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
	},

	-- Kills ----------------------------------------------------------------
	group_kills = {
		en = "Trigger: kills",
	},
	kills_enabled = {
		en = "Grant on kill count",
	},
	kills_enabled_description = {
		en = "Fires every time the kill counter reaches the threshold below. Predictable pacing, but it does reward farming.",
	},
	kills_mode = {
		en = "Count",
	},
	kills_mode_description = {
		en = "Which enemy deaths add to the counter.",
	},
	kills_mode_all = {
		en = "All enemies",
	},
	kills_mode_elites_specials = {
		en = "Elites and specials",
	},
	kills_mode_specials = {
		en = "Specials only",
	},
	kills_mode_monsters = {
		en = "Monsters and captains",
	},
	kills_threshold = {
		en = "Kills required",
	},
	kills_threshold_description = {
		en = "How many counted kills between grants.",
	},
	kills_grant = {
		en = "Grants",
	},
	kills_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
	},
	kills_chance = {
		en = "Chance (%%)",
	},
	kills_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
	},

	-- Time -----------------------------------------------------------------
	group_time = {
		en = "Trigger: elapsed time",
	},
	time_enabled = {
		en = "Grant on a timer",
	},
	time_enabled_description = {
		en = "Fires on a fixed clock for the whole mission. Fully deterministic, but disconnected from what you are doing.",
	},
	time_interval = {
		en = "Minutes between grants",
	},
	time_interval_description = {
		en = "How long between timer grants.",
	},
	time_grant = {
		en = "Grants",
	},
	time_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
	},
	time_chance = {
		en = "Chance (%%)",
	},
	time_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
	},

	-- Terror events --------------------------------------------------------
	group_events = {
		en = "Trigger: event clears",
	},
	events_enabled = {
		en = "Grant on terror event cleared",
	},
	events_enabled_description = {
		en = "Fires when the last active terror event ends - ambushes, monster spawns and scripted events. The closest thing a regular mission has to finishing a Mortis wave, but how often it happens varies a lot by map and difficulty.",
	},
	events_grant = {
		en = "Grants",
	},
	events_grant_description = {
		en = "What this trigger hands out. If that kind is already used up for the mission, the other kind is given instead.",
	},
	events_chance = {
		en = "Chance (%%)",
	},
	events_chance_description = {
		en = "Probability that this trigger actually grants something when it fires.",
	},

	-- Shared dropdown options ----------------------------------------------
	grant_family = {
		en = "A family buff",
	},
	grant_legendary = {
		en = "A legendary card pick",
	},
	grant_random = {
		en = "Either, at random",
	},

	-- Mission chain ---------------------------------------------------------
	picker_title = {
		en = "Continue the Run",
	},
	picker_subtitle = {
		en = "Choose your next mission. Your buffs carry over.",
	},
	picker_default_note = {
		en = "The first is chosen unless you pick another.",
	},
	picker_option_subtitle = {
		en = "Same difficulty and conditions",
	},
	picker_selected = {
		en = "Next: %s",
	},

	-- Testing ---------------------------------------------------------------
	group_testing = {
		en = "Testing",
	},
	debug_end_mission_won_keybind = {
		en = "End mission as a win",
	},
	debug_end_mission_won_keybind_description = {
		en = "Instantly completes the current mission so the end screen and the next-mission picker appear. For testing the run chain without walking the whole map.",
	},
	debug_end_mission_lost_keybind = {
		en = "End mission as a loss",
	},
	debug_end_mission_lost_keybind_description = {
		en = "Instantly fails the current mission, which ends the run. For testing that losing aborts the chain.",
	},
	debug_end_unavailable = {
		en = "Not in a Chaos Wastes at Home mission - nothing to end.",
	},
	command_cw_win = {
		en = "end the current mission as a win (testing)",
	},
	command_cw_lose = {
		en = "end the current mission as a loss (testing)",
	},

	-- Commands -------------------------------------------------------------
	command_cw_buff = {
		en = "grant a buff now - /cw_buff [family|legendary]",
	},
	command_cw_status = {
		en = "show how many buffs this mission has handed out",
	},
	command_cw_give = {
		en = "grant one buff by name - /cw_give [name or search text]",
	},
	command_cw_verify = {
		en = "check whether the custom buffs are attached and having an effect",
	},
	conflict_auto_restart = {
		en = "Chaos Wastes at Home: TrueSoloQoL's auto-restart is on, so losing will restart the mission instead of ending your run. Turn it off for runs to be loseable.",
	},
	command_not_active = {
		en = "Chaos Wastes at Home is not active - it only runs in solo missions.",
	},
	command_failed = {
		en = "Nothing granted: the mission budget is spent, or no buff family has been chosen yet.",
	},
}
