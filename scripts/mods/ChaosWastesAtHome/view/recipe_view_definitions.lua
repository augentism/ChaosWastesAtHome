local mod = get_mod("ChaosWastesAtHome")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local ScrollbarPassTemplates = require("scripts/ui/pass_templates/scrollbar_pass_templates")
local tabs = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/tab_strip")
local base = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view_definitions")
local nodes = table.clone(base.scenegraph_definition)
local widgets = {}
local function node(id, x, y, w, h, parent)
 nodes[id] = { parent = parent or "screen", vertical_alignment = "top", horizontal_alignment = "left",
  size = { w, h }, position = { x, y, 2 } }
end
local function text(id, label, size, color)
 widgets[id] = UIWidget.create_definition({ { pass_type = "text", value_id = "text", value = label,
  style = { font_type = "proxima_nova_medium", font_size = size or 22,
   text_color = color or {255,220,215,200}, text_vertical_alignment = "top", word_wrap = true } } }, id)
end
local function button(id, label, x, y, w)
 node(id,x,y,w,38)
 widgets[id] = UIWidget.create_definition(table.clone(ButtonPassTemplates.default_button),id,{original_text=label})
end
widgets.background = UIWidget.create_definition({{pass_type="rect",style={color={240,8,9,10}}}},"screen")
for _, id in ipairs({"title_divider","title_text","subtab_buffs","subtab_havoc","subtab_editor"}) do
 widgets[id] = table.clone(base.widget_definitions[id])
end
button("new",mod:localize("recipe_editor_new"),140,882,155)
button("reload",mod:localize("recipe_reload_short"),305,882,155)
nodes.list_panel=table.clone(nodes.group_panel)
node("list_pivot",0,0,0,0,"list_panel")
nodes.list_mask=table.clone(nodes.group_grid_mask);nodes.list_mask.parent="list_panel"
widgets.list_mask=UIWidget.create_definition({{pass_type="texture",value="content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",style={color={255,255,255,255}}}},"list_mask")
nodes.scrollbar=table.clone(nodes.group_scrollbar);nodes.scrollbar.parent="list_panel"
widgets.scrollbar=UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar,"scrollbar")
node("empty",140,258,320,150);text("empty",mod:localize("recipe_list_empty"),20)
node("fields_heading",520,204,760,35);text("fields_heading",mod:localize("recipe_fields"),24)
local fields={"id","name","trigger","effect","amount","max_stacks","duration","chance","cooldown","enabled","legendary"}
for i,key in ipairs(fields) do node("field_"..key,520,250+(i-1)*48,760,42) end
button("save",mod:localize("recipe_editor_save"),520,882,370)
button("delete",mod:localize("recipe_editor_delete"),910,882,370)
nodes.preview_panel=table.clone(nodes.detail_panel)
nodes.preview_panel.position[1]=1320
widgets.preview_panel=UIWidget.create_definition({{pass_type="rect",style={color={220,22,24,27}}}},"preview_panel")
node("preview_heading",20,16,430,32,"preview_panel");text("preview_heading",mod:localize("recipe_live_preview"),24)
node("preview_title",20,74,430,70,"preview_panel");text("preview_title","",28,{255,224,192,130})
node("preview_description",20,158,430,300,"preview_panel");text("preview_description","",22)
node("preview_state",20,472,430,110,"preview_panel");text("preview_state","",18)
node("status",140,936,1500,65);text("status","",19)
tabs.extend(nodes,widgets)
return {scenegraph_definition=nodes,widget_definitions=widgets,fields=fields,
 shading_environment="content/shading_environments/ui/system_menu"}
