local mod = get_mod("ChaosWastesAtHome")

local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local UIWidget = require("scripts/managers/ui/ui_widget")

-- The row of tabs across the top of every one of this mod's screens.
--
-- It used to be three hand-rolled buttons copied verbatim into three
-- definition files, with each view disabling its own and wiring the other two
-- by name. That was survivable at three tabs on three screens; it is not at
-- four tabs on four, and the copies had already drifted -- launch_view carried
-- a tab_start node it never wired, because its own tab is the inert one.
--
-- So: one list, one layout, one set of callbacks. Same shape as
-- loadout_strip.lua next door -- extend() writes the definitions, attach()
-- wires them to a live view.

local tab_strip = {}

local TAB_W = 280
local TAB_H = 40
local TAB_GAP = 10
local TAB_Y = 84

-- Order is left-to-right on screen.
--
-- `mission_only` is the collected-buffs screen: it reads the run snapshot, and
-- outside a mission there is no run to read. Its view is also registered with
-- load_in_hub = false, so offering it there would be a tab that cannot open.
local TABS = {
	{
		id = "start",
		view = "chaos_wastes_launch_view",
		label = "tab_start_run",
	},
	{
		id = "buffs",
		view = "chaos_wastes_buff_toggle_view",
		label = "tab_rollable_buffs",
	},
	{
		id = "settings",
		view = "chaos_wastes_settings_view",
		label = "tab_settings",
	},
	{
		id = "collected",
		view = "chaos_wastes_buffs_view",
		label = "tab_collected",
		mission_only = true,
	},
}

tab_strip.TABS = TABS

-- ---------------------------------------------------------------------------
-- Definitions
-- ---------------------------------------------------------------------------

-- Every tab gets a node, whether or not this context shows it.
--
-- Position is left at zero and set in attach() instead, because the strip has
-- to centre a different number of tabs depending on where it is being drawn --
-- three in the Mourningstar, four in a mission. A scenegraph position is baked
-- at definition time and the definitions are shared, so the only place that
-- can know the count is the live view.
tab_strip.extend = function (scenegraph, widgets)
	for _, tab in ipairs(TABS) do
		local id = "tab_" .. tab.id

		scenegraph[id] = {
			vertical_alignment = "top",
			parent = "screen",
			horizontal_alignment = "center",
			size = { TAB_W, TAB_H },
			position = { 0, TAB_Y, 3 },
		}

		-- original_text, not text: default_button's change_function overwrites
		-- content.text every frame.
		widgets[id] = UIWidget.create_definition(
			table.clone(ButtonPassTemplates.default_button), id,
			{ original_text = mod:localize(tab.label) }
		)
	end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

-- In one of this mod's missions, as opposed to the hub or anyone else's game.
--
-- mod.manager is the buff manager, set when our game mode activates and
-- cleared when it tears down, so it is the same "is my thing live" test the
-- rest of the mod gates on.
local function _in_mission()
	return mod.manager ~= nil
end

local function _is_available(tab)
	return not tab.mission_only or _in_mission()
end

tab_strip._cb_open = function (self, view, tab)
	local ui_manager = Managers.ui

	if not ui_manager then
		return
	end

	-- Close ours first. Both views are state_bound with close_previous false,
	-- so opening on top of the current one would leave two of our screens
	-- stacked, and the lower one would keep drawing.
	ui_manager:close_view(view.view_name)
	ui_manager:open_view(tab.view)
end

-- Call from the view's init, after super.init has built _widgets_by_name.
--
-- active_id is this view's own tab, which is shown pressed-out and does
-- nothing -- clicking the tab you are already on should not tear the screen
-- down and rebuild it.
tab_strip.attach = function (view, active_id)
	local widgets_by_name = view._widgets_by_name
	local shown = {}

	for _, tab in ipairs(TABS) do
		local widget = widgets_by_name["tab_" .. tab.id]

		if widget then
			local available = _is_available(tab)

			widget.visible = available

			if available then
				shown[#shown + 1] = { tab = tab, widget = widget }
			end
		end
	end

	-- Centred as a group: with n tabs the i-th sits at (i - (n+1)/2) pitches
	-- from the middle, which puts an odd count's middle tab on the centre line
	-- and straddles it for an even one.
	local pitch = TAB_W + TAB_GAP
	local count = #shown

	for i = 1, count do
		local entry = shown[i]
		local widget = entry.widget

		widget.offset[1] = (i - (count + 1) * 0.5) * pitch

		if entry.tab.id == active_id then
			widget.content.hotspot.disabled = true
		else
			widget.content.hotspot.disabled = false
			widget.content.hotspot.pressed_callback = callback(tab_strip, "_cb_open", view, entry.tab)
		end
	end
end

return tab_strip
