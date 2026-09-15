--[[
    dropdown_helper.lua
    Wraps the game's options-view dropdown blueprint so custom BaseViews can
    use real engine dropdowns.

    Usage:
      local DropdownHelper = mod:io_dofile(".../view/dropdown_helper")
      DropdownHelper.install(MyView)          -- adds required parent methods

      -- entry:
      --   header_text  label drawn on the left
      --   options      array of { id = ..., display_name = ..., ignore_localization = true }
      --   get_function function() -> currently selected id
      --   on_activated function(new_id) called on selection
      --   size         { w, h } (default { 460, 44 }); value_width = dropdown box width
      local widget = DropdownHelper.create(self, name, scenegraph_id, entry)
      self._widgets[#self._widgets + 1] = widget

      -- every frame:
      DropdownHelper.update(self, widget, input_service, dt, t)
--]]

local mod = get_mod("ChaosWastesAtHome")

local ContentBlueprints = mod:original_require("scripts/ui/views/options_view/options_view_content_blueprints")
local UIWidget          = mod:original_require("scripts/managers/ui/ui_widget")

local dropdown_blueprint = ContentBlueprints.dropdown

local DropdownHelper = {}

DropdownHelper.create = function(view, name, scenegraph_id, entry)
    entry.size        = entry.size or { 460, 44 }
    entry.value_width = entry.value_width or 260
    -- init localizes display_name, so give it a real loc key and override
    -- the header text afterwards.
    entry.display_name = entry.display_name or "loc_settings_option_unavailable"

    local user_on_activated = entry.on_activated
    entry.on_activated = function(new_id, e)
        if user_on_activated then user_on_activated(new_id, e) end
        view:close_focused_dropdown()
    end

    local passes = dropdown_blueprint.pass_template_function(view, entry, entry.size)

    -- Caller-supplied passes rendered as part of the row (e.g. an inline
    -- checkbox next to the dropdown box)
    for _, pass in ipairs(entry.extra_passes or {}) do
        passes[#passes + 1] = pass
    end

    local def = UIWidget.create_definition(passes, scenegraph_id, nil, entry.size)
    local widget = view:_create_widget(name, def)

    dropdown_blueprint.init(view, widget, entry, "cb_on_dropdown_pressed", "cb_on_dropdown_changed")

    if entry.header_text then
        widget.content.text = entry.header_text
    end

    return widget
end

DropdownHelper.update = function(view, widget, input_service, dt, t)
    dropdown_blueprint.update(view, widget, input_service, dt, t)
end

-- True if the cursor is over any part of the dropdown: header, an option
-- row, or the option-list scrollbar.
DropdownHelper.is_hovered = function(widget)
    local content = widget.content
    if content.hotspot and content.hotspot.is_hover then
        return true
    end
    local scrollbar = content.scrollbar_hotspot
    if scrollbar and scrollbar.is_hover then
        return true
    end
    for i = 1, content.num_visible_options or 0 do
        local option_hotspot = content["option_hotspot_" .. i]
        if option_hotspot and option_hotspot.is_hover then
            return true
        end
    end
    return false
end

-- Call from view update: schedules a close when the user clicks anywhere
-- outside the open dropdown. The close is applied after the next draw
-- (see draw_with_focus) so the click can't fall through to widgets that
-- were input-blocked this frame.
DropdownHelper.handle_outside_click = function(view, input_service)
    local focused = view._focused_dropdown
    local left_hold = input_service and input_service:get("left_hold")
    local clicked = left_hold and not view._dropdown_left_was_held

    view._dropdown_left_was_held = left_hold and true or false

    if focused and clicked and not DropdownHelper.is_hovered(focused) then
        view._close_dropdown_after_draw = true
    end
end

-- Draw wrapper: when a dropdown is open, every other widget gets a null
-- input service (so clicks can't reach them), and the open dropdown is
-- drawn last, on top, with real input.
-- super_draw is called as super_draw(effective_input_service).
DropdownHelper.draw_with_focus = function(view, dt, t, input_service, super_draw)
    local focused = view._focused_dropdown

    if not focused then
        super_draw(input_service)
        return
    end

    local UIRenderer = view._dropdown_ui_renderer_module
    if not UIRenderer then
        UIRenderer = mod:original_require("scripts/managers/ui/ui_renderer")
        view._dropdown_ui_renderer_module = UIRenderer
    end

    -- Everything else: input-blocked
    focused.visible = false
    super_draw(input_service:null_service())
    focused.visible = true

    -- The dropdown itself: real input, drawn on top
    local ui_renderer = view._ui_renderer
    UIRenderer.begin_pass(ui_renderer, view._ui_scenegraph, input_service, dt, view._render_settings)
    UIWidget.draw(focused, ui_renderer)
    UIRenderer.end_pass(ui_renderer)

    if view._close_dropdown_after_draw then
        view._close_dropdown_after_draw = nil
        view:close_focused_dropdown()
    end
end

-- Adds the parent methods the blueprint expects (stubs suited to a custom
-- view: no settings grid, dropdowns always fold out downwards) plus focus
-- management callbacks.
DropdownHelper.install = function(view_class)
    view_class.using_cursor_navigation = function(self)
        return Managers.ui:using_cursor_navigation()
    end

    view_class.can_exit = function(self)
        return self._dropdown_can_exit ~= false
    end

    view_class.set_can_exit = function(self, value)
        self._dropdown_can_exit = value
    end

    view_class.settings_scroll_amount = function(self)
        return 0
    end

    view_class.settings_grid_length = function(self)
        return math.huge
    end

    view_class.cb_on_dropdown_changed = function(self) end

    view_class.cb_on_dropdown_pressed = function(self, widget, entry)
        local content = widget.content
        if content.exclusive_focus then
            self:close_focused_dropdown()
        else
            local prev = self._focused_dropdown
            if prev and prev ~= widget then
                prev.content.exclusive_focus = false
            end
            content.exclusive_focus = true
            self._focused_dropdown = widget

            -- Draw the open dropdown last so its option list renders on top
            local widgets = self._widgets
            for i = 1, #widgets do
                if widgets[i] == widget then
                    table.remove(widgets, i)
                    break
                end
            end
            widgets[#widgets + 1] = widget
        end
    end

    view_class.close_focused_dropdown = function(self)
        local focused = self._focused_dropdown
        if focused then
            focused.content.exclusive_focus = false
        end
        self._focused_dropdown = nil
        self:set_can_exit(true)
    end
end

return DropdownHelper

