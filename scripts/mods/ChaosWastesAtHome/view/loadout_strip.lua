local mod = get_mod("ChaosWastesAtHome")

local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

-- The loadout column, shared by every tab.
--
-- Not a view of its own and not three copies: a module that adds its nodes and
-- widgets to whichever view is being built, then drives them. The selected
-- loadout is a mod setting, so it is the same on every tab without anything
-- having to be passed between them.
--
-- A view opts in with three calls:
--   definitions:  strip.extend(scenegraph_definition, widget_definitions)
--   on_enter:     strip.attach(self)
--   update:       strip.update(self, dt)
--
-- and gets one callback back: view:on_loadout_changed(), which fires after a
-- different loadout has been applied so the tab can re-read whatever it shows.

local strip = {}

local SLOT = 56
local SLOT_SPACING = 8
local STRIP_TOP = 140
local STRIP_X = 46

-- Wide enough for the labels at the button template's own font size.
--
-- These started at the width of the icon column, 88px, which wrapped "Create
-- from current" into three overlapping lines. A button has to be sized for its
-- text, not for the thing it happens to sit under.
local BUTTON_W = 176
local BUTTON_H = 38
local BUTTON_SPACING = 8

-- Fewer slots than the loadout list can hold. Ten fills the column at this
-- height; an eleventh would push the buttons off the bottom of the screen. Any
-- beyond ten still exist and still load -- they just have no icon in the strip,
-- which is a reason to keep the count sane rather than a reason to scroll.
local MAX_SLOTS = 10

-- The column claims the width of its WIDEST element, not the icons', so a view
-- laying its content out after the strip does not run into the buttons.
--
-- Only the tab that draws the buttons needs to reserve that much, and only that
-- tab reads this.
strip.WIDTH = BUTTON_W + 32
strip.MAX_SLOTS = MAX_SLOTS

-- Palette geometry. 54 icons at nine across is six rows.
local PALETTE_COLUMNS = 9
local PALETTE_CELL = 56
local PALETTE_SPACING = 8

local DELETE_ARM_SECONDS = 3

-- The game's own "add a preset" symbol, from the same folder -- and therefore
-- the same package -- as the 25 icons.
local ICON_ADD = "content/ui/materials/icons/presets/preset_new"

local function _icon_widget(scenegraph_id)
	return UIWidget.create_definition({
		{
			pass_type = "hotspot",
			content_id = "hotspot",
		},
		-- Drawn behind the icon so selection reads even on a dark symbol.
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				color = { 180, 8, 8, 10 },
			},
			change_function = function (content, style)
				local hotspot = content.hotspot

				style.color[1] = (hotspot.is_hover or hotspot.is_selected) and 245 or 180
				style.color[2] = hotspot.is_selected and 70 or (hotspot.is_hover and 34 or 8)
				style.color[3] = hotspot.is_selected and 34 or 8
			end,
		},
		{
			pass_type = "texture",
			style_id = "icon",
			value_id = "icon",
			-- A material path, not a texture: see the note on loadouts.ICONS.
			value = "content/ui/materials/icons/presets/preset_01",
			style = {
				horizontal_alignment = "center",
				vertical_alignment = "center",
				size = { SLOT - 14, SLOT - 14 },
				offset = { 0, 0, 3 },
				color = { 255, 255, 255, 255 },
			},
		},
		-- A corner pip rather than a word: the column is 56px wide and "default"
		-- does not fit in it at any readable size.
		{
			pass_type = "rect",
			style_id = "default_pip",
			style = {
				horizontal_alignment = "right",
				vertical_alignment = "top",
				size = { 10, 10 },
				offset = { -4, 4, 5 },
				color = { 255, 240, 200, 90 },
			},
			visibility_function = function (content)
				return content.is_default == true
			end,
		},
	}, scenegraph_id)
end

-- ---------------------------------------------------------------------------
-- Definitions
-- ---------------------------------------------------------------------------

strip.extend = function (scenegraph, widgets, options)
	for i = 1, MAX_SLOTS do
		scenegraph["loadout_slot_" .. i] = {
			vertical_alignment = "top",
			parent = "screen",
			horizontal_alignment = "left",
			size = { SLOT, SLOT },
			position = { STRIP_X, STRIP_TOP + (i - 1) * (SLOT + SLOT_SPACING), 6 },
		}

		widgets["loadout_slot_" .. i] = _icon_widget("loadout_slot_" .. i)
	end

	-- Buttons only on the tab that asks for them.
	--
	-- They are sized for their labels, which is far wider than the icon column,
	-- and on the buff tab that width ran straight into the list. Creating a
	-- loadout is the one action every tab needs, and it is a slot now rather
	-- than a button, so the other tabs carry the icons alone.
	--
	-- No icon button either: changing the icon is right-click on the loadout
	-- itself, which is how the game's own loadout menu does it.
	if options and options.actions then
		local buttons_top = STRIP_TOP + MAX_SLOTS * (SLOT + SLOT_SPACING) + 10
		local button_ids = { "loadout_default", "loadout_delete" }
		local button_labels = { "loadout_set_default", "loadout_delete" }

		for i = 1, #button_ids do
			scenegraph[button_ids[i]] = {
				vertical_alignment = "top",
				parent = "screen",
				horizontal_alignment = "left",
				size = { BUTTON_W, BUTTON_H },
				position = { STRIP_X, buttons_top + (i - 1) * (BUTTON_H + BUTTON_SPACING), 6 },
			}

			widgets[button_ids[i]] = UIWidget.create_definition(
				table.clone(ButtonPassTemplates.default_button), button_ids[i],
				{ original_text = mod:localize(button_labels[i]) }
			)
		end
	end

	-- Palette, hidden until asked for.
	--
	-- Full-screen backdrop first and at a lower layer than the cells, so a click
	-- anywhere outside a cell closes it. Without it the palette would be a grid
	-- floating over a live screen with no way out but Escape.
	scenegraph.loadout_palette_backdrop = {
		vertical_alignment = "center",
		parent = "screen",
		horizontal_alignment = "center",
		size = { 1920, 1080 },
		position = { 0, 0, 40 },
	}

	widgets.loadout_palette_backdrop = UIWidget.create_definition({
		{
			pass_type = "hotspot",
			content_id = "hotspot",
		},
		{
			pass_type = "rect",
			style = { color = { 220, 0, 0, 0 } },
		},
	}, "loadout_palette_backdrop")

	local icons = mod.loadouts.icons()
	local rows = math.ceil(#icons / PALETTE_COLUMNS)
	local grid_w = PALETTE_COLUMNS * PALETTE_CELL + (PALETTE_COLUMNS - 1) * PALETTE_SPACING
	local grid_h = rows * PALETTE_CELL + (rows - 1) * PALETTE_SPACING

	for i = 1, #icons do
		local column = (i - 1) % PALETTE_COLUMNS
		local row = math.floor((i - 1) / PALETTE_COLUMNS)

		scenegraph["loadout_palette_" .. i] = {
			vertical_alignment = "center",
			parent = "screen",
			horizontal_alignment = "center",
			size = { PALETTE_CELL, PALETTE_CELL },
			position = {
				-grid_w / 2 + PALETTE_CELL / 2 + column * (PALETTE_CELL + PALETTE_SPACING),
				-grid_h / 2 + PALETTE_CELL / 2 + row * (PALETTE_CELL + PALETTE_SPACING),
				41,
			},
		}

		widgets["loadout_palette_" .. i] = UIWidget.create_definition({
			{
				pass_type = "hotspot",
				content_id = "hotspot",
			},
			{
				pass_type = "rect",
				style_id = "background",
				style = { color = { 200, 12, 12, 14 } },
				change_function = function (content, style)
					style.color[1] = content.hotspot.is_hover and 255 or 200
					style.color[2] = content.hotspot.is_hover and 40 or 12
				end,
			},
			{
				pass_type = "texture",
				value_id = "icon",
				value = icons[i],
				style = {
					horizontal_alignment = "center",
					vertical_alignment = "center",
					size = { PALETTE_CELL - 12, PALETTE_CELL - 12 },
					offset = { 0, 0, 2 },
					color = { 255, 255, 255, 255 },
				},
			},
		}, "loadout_palette_" .. i)
	end

	scenegraph.loadout_hint = {
		vertical_alignment = "top",
		parent = "screen",
		horizontal_alignment = "left",
		size = { 260, 24 },
		position = { STRIP_X, STRIP_TOP - 28, 6 },
	}

	widgets.loadout_hint = UIWidget.create_definition({
		{
			pass_type = "text",
			value_id = "text",
			value = "",
			style = {
				font_type = "proxima_nova_medium",
				font_size = 15,
				text_horizontal_alignment = "left",
				text_vertical_alignment = "center",
				text_color = { 255, 160, 155, 145 },
			},
		},
	}, "loadout_hint")
end

-- ---------------------------------------------------------------------------
-- Behaviour
-- ---------------------------------------------------------------------------

strip.attach = function (view)
	local widgets_by_name = view._widgets_by_name

	view._strip = {
		rows = {},
		add_index = nil,
		base_hint = "",
		armed_delete = nil,
		armed_accum = 0,
		palette_open = false,
		palette_for = nil,
		palette_close_pending = false,
		blocked = nil,
	}

	for i = 1, MAX_SLOTS do
		local hotspot = widgets_by_name["loadout_slot_" .. i].content.hotspot

		hotspot.pressed_callback = callback(strip, "_cb_slot", view, i)

		-- Right-click opens the palette for THAT loadout, selected or not --
		-- ui_passes calls right_pressed_callback straight off hotspot content.
		hotspot.right_pressed_callback = callback(strip, "_cb_open_palette", view, i)
	end

	-- Absent on every tab but the one that asked for them.
	if widgets_by_name.loadout_default then
		widgets_by_name.loadout_default.content.hotspot.pressed_callback = callback(strip, "_cb_default", view)
		widgets_by_name.loadout_delete.content.hotspot.pressed_callback = callback(strip, "_cb_delete", view)
	end

	widgets_by_name.loadout_palette_backdrop.content.hotspot.pressed_callback =
		callback(strip, "_cb_close_palette", view)

	local icons = mod.loadouts.icons()

	for i = 1, #icons do
		widgets_by_name["loadout_palette_" .. i].content.hotspot.pressed_callback =
			callback(strip, "_cb_pick_icon", view, icons[i])
	end

	strip.refresh(view)
end

-- Membership tested here, against icons(), rather than asked of mod.loadouts.
--
-- View files are loaded with mod:io_dofile, which re-executes on every call, so
-- a view picks up newly deployed code the moment the menu is reopened -- while
-- the main script that builds the mod.loadouts facade only re-runs on an actual
-- mod reload. A view that calls a facade function added in the same edit is
-- therefore nil-calling it for anyone who reopens the menu without reloading,
-- which is a hard crash inside the draw path. That is not hypothetical: it is
-- what this function replaced. Views may only call facade entries that were
-- already shipped.
local function _known_icon(icon)
	if type(icon) ~= "string" then
		return nil
	end

	local icons = mod.loadouts.icons()

	for i = 1, #icons do
		if icons[i] == icon then
			return icon
		end
	end

	return nil
end

strip.refresh = function (view)
	local widgets_by_name = view._widgets_by_name
	local state = view._strip

	state.rows = mod.loadouts.available() and mod.loadouts.list() or {}

	local active = mod.loadouts.active()
	local default_slug = mod.loadouts.default()
	local selected

	-- The slot straight after the last loadout creates one. A slot rather than a
	-- button under the column, so it sits exactly where the loadout it makes
	-- will appear and walks down as they are added -- and so the two tabs that
	-- are not Settings need no buttons at all.
	state.add_index = (mod.loadouts.available() and #state.rows < MAX_SLOTS)
		and (#state.rows + 1) or nil

	for i = 1, MAX_SLOTS do
		local row = state.rows[i]
		local widget = widgets_by_name["loadout_slot_" .. i]

		if row then
			widget.content.icon = _known_icon(row.icon) or mod.loadouts.icons()[1]
			widget.content.hotspot.is_selected = row.slug == active
			widget.content.is_default = row.slug == default_slug
			widget.visible = true

			if row.slug == active then
				selected = row
			end
		elseif i == state.add_index then
			widget.content.icon = ICON_ADD
			widget.content.hotspot.is_selected = false
			widget.content.is_default = false
			widget.visible = true
		else
			widget.visible = false
		end
	end

	-- Every action below the strip acts on the selected loadout, so with nothing
	-- selected they are disabled rather than silently doing nothing.
	if widgets_by_name.loadout_delete then
		local has_selection = selected ~= nil

		widgets_by_name.loadout_delete.content.hotspot.disabled = not has_selection
		widgets_by_name.loadout_default.content.hotspot.disabled = not has_selection
			or (selected and selected.slug == default_slug) or false

		widgets_by_name.loadout_delete.content.original_text = state.armed_delete
			and mod:localize("loadout_delete_confirm")
			or mod:localize("loadout_delete")
	end

	-- The name has nowhere else to live now the strip is icons, so it goes above
	-- the column as a label for whatever is selected. Held rather than written
	-- straight out, because hovering the add slot borrows the same line.
	state.base_hint = selected and selected.name
		or (mod.loadouts.available() and mod:localize("loadout_empty") or mod:localize("loadout_unavailable"))

	widgets_by_name.loadout_hint.content.text = state.base_hint

	strip._set_palette_visible(view, state.palette_open)
end

-- Every hotspot the view owns, including the ones a grid holds.
--
-- UIWidgetGrid keeps its rows in its own list, so the buff tab's group and buff
-- rows never appear in view._widgets. Walked by duck-typing rather than by a
-- method on the view: the strip attaches to three views and only one of them
-- has grids.
--
-- Found from the PASSES rather than by reading content.hotspot, because
-- "hotspot" is only the usual name for one. A value_slider carries a second one
-- under content.track_hotspot -- that is the one its drag logic waits on for
-- on_pressed -- so looking only at content.hotspot left every slider live
-- underneath the palette while the checkboxes around it were properly blocked.
local function _each_hotspot(view, fn)
	local lists = { view._widgets }

	lists[#lists + 1] = view._group_widgets
	lists[#lists + 1] = view._buff_widgets

	for i = 1, #lists do
		local list = lists[i]

		for j = 1, #list do
			local widget = list[j]
			local passes = widget.passes

			for k = 1, passes and #passes or 0 do
				local pass = passes[k]

				if pass.pass_type == "hotspot" then
					local content = pass.content_id and widget.content[pass.content_id]

					if type(content) == "table" then
						fn(widget, content)
					end
				end
			end
		end
	end
end

-- Nothing else takes clicks while the palette is up.
--
-- Hotspots do not block one another: ui_passes.hotspot reads "left_pressed" off
-- the input service for EVERY hovered hotspot independently, so one click on a
-- palette cell also lands on whatever sits under it -- a checkbox on the
-- settings tab, a buff row on the buff tab, and the backdrop in both cases. The
-- backdrop hides the screen and does nothing whatever about the input.
--
-- Previous values are remembered rather than assumed false: several of these
-- are legitimately disabled already (the current tab's own button, the action
-- buttons with nothing selected).
local function _block_input(view, allowed)
	local state = view._strip

	if state.blocked then
		return
	end

	local blocked = {}

	_each_hotspot(view, function (widget, hotspot)
		if not allowed[widget] then
			blocked[hotspot] = hotspot.disabled or false
			hotspot.disabled = true
		end
	end)

	state.blocked = blocked
end

-- Called before the closing refresh, never after: refresh recomputes the action
-- buttons' disabled state, and restoring afterwards would put the values from
-- before the palette opened back over the fresh ones.
local function _unblock_input(view)
	local state = view._strip
	local blocked = state.blocked

	if not blocked then
		return
	end

	state.blocked = nil

	for hotspot, previous in pairs(blocked) do
		hotspot.disabled = previous
	end
end

strip._set_palette_visible = function (view, visible)
	local widgets_by_name = view._widgets_by_name
	local backdrop = widgets_by_name.loadout_palette_backdrop

	backdrop.visible = visible

	local icons = mod.loadouts.icons()
	local allowed = { [backdrop] = true }

	for i = 1, #icons do
		local widget = widgets_by_name["loadout_palette_" .. i]

		widget.visible = visible
		allowed[widget] = true
	end

	if visible then
		_block_input(view, allowed)
	end
end

strip.update = function (view, dt)
	local state = view._strip

	if not state then
		return
	end

	-- The add slot has no label of its own and the plus is the only thing in the
	-- column that is not a loadout, so hovering it says so on the line that
	-- otherwise names the selection.
	local hint = state.base_hint

	if state.add_index then
		local widget = view._widgets_by_name["loadout_slot_" .. state.add_index]

		if widget and widget.content.hotspot.is_hover then
			hint = mod:localize("loadout_create")
		end
	end

	view._widgets_by_name.loadout_hint.content.text = hint

	if state.palette_close_pending then
		strip._close_palette(view)
	end

	if not state.armed_delete then
		return
	end

	state.armed_accum = state.armed_accum + dt

	if state.armed_accum >= DELETE_ARM_SECONDS then
		state.armed_delete = nil

		strip.refresh(view)
	end
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

local function _selected(view)
	local active = mod.loadouts.active()

	for i = 1, #view._strip.rows do
		if view._strip.rows[i].slug == active then
			return view._strip.rows[i]
		end
	end

	return nil
end

strip._cb_slot = function (self, view, index)
	local state = view._strip
	local row = state.rows[index]

	state.armed_delete = nil

	-- Past the end of the list: the add slot, or a hidden one.
	if not row then
		if index == state.add_index and mod.loadouts.create() then
			-- No on_loadout_changed: create snapshots the settings that are
			-- already live, so nothing the tab is showing has changed.
			strip.refresh(view)
		end

		return
	end

	if mod.loadouts.select(row.slug) then
		strip.refresh(view)

		-- The tab is showing values that just changed underneath it.
		if view.on_loadout_changed then
			view:on_loadout_changed()
		end
	end
end

strip._cb_default = function (self, view)
	local row = _selected(view)

	if not row then
		return
	end

	mod.loadouts.set_default(row.slug)
	strip.refresh(view)
end

strip._cb_delete = function (self, view)
	local row = _selected(view)

	if not row then
		return
	end

	if not view._strip.armed_delete then
		view._strip.armed_delete = row.slug
		view._strip.armed_accum = 0

		strip.refresh(view)

		return
	end

	view._strip.armed_delete = nil

	if mod.loadouts.delete(row.slug) then
		strip.refresh(view)
	end
end

strip._cb_open_palette = function (self, view, index)
	local row = view._strip.rows[index]

	if not row then
		return
	end

	view._strip.palette_for = row.slug
	view._strip.palette_open = true

	strip.refresh(view)
end

-- Deferred to the next update rather than applied here.
--
-- The backdrop is a full-screen hotspot under the cells so that a click outside
-- one closes the palette -- but a click ON a cell is inside the backdrop too, so
-- both callbacks run for the same click. Which runs first is decided by the
-- order BaseView built its widget list, which comes from pairs() over the
-- definitions table and is therefore undefined: measured live, the settings tab
-- had the backdrop at index 16 and the cells from 18, the buff tab had the cells
-- at 15 and the backdrop at 57. With the backdrop first it cleared palette_for
-- and the cell then had nothing to write to, which is why changing an icon
-- worked on one tab and did nothing on the other.
--
-- Closing a frame later means the pick has always already happened, whichever
-- order the two fired in.
strip._cb_close_palette = function (self, view)
	view._strip.palette_close_pending = true
end

strip._close_palette = function (view)
	local state = view._strip

	state.palette_close_pending = false

	if not state.palette_open then
		return
	end

	_unblock_input(view)

	state.palette_open = false
	state.palette_for = nil

	strip.refresh(view)
end

strip._cb_pick_icon = function (self, view, icon)
	local slug = view._strip.palette_for

	if slug then
		mod.loadouts.set_icon(slug, icon)
	end

	strip._close_palette(view)
end

return strip
