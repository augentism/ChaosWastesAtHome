local mod = get_mod("ChaosWastesAtHome")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidgetGrid = require("scripts/ui/widget_logic/ui_widget_grid")
local ScriptWorld = require("scripts/foundation/utilities/script_world")
local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")
local tabs = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/tab_strip")
local Dropdown = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/recipe_dropdown")
local recipes = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/buff_recipes")
local TextWidget = get_mod("DMF"):io_dofile("dmf/scripts/mods/dmf/modules/ui/options/text/text_widget")
local FIELD_WIDTH, VALUE_WIDTH = 760, 480
local text_blueprint = TextWidget.create_blueprint(FIELD_WIDTH,VALUE_WIDTH,42)
local row_blueprints = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/buff_toggle_view_blueprints")
local VIEW = "chaos_wastes_recipe_view"
local RecipeView = class("ChaosWastesRecipeView", "BaseView")
Dropdown.install(RecipeView)

RecipeView.init = function(self, settings, context)
 self._definitions=mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/recipe_view_definitions")
 self._rows,self._controls,self._dropdowns={},{},{}
 RecipeView.super.init(self,self._definitions,settings,context)
 self._pass_input,self._pass_draw=false,false
 local name=self.__class_name
 self._world=Managers.ui:create_world(name.."_world",10,"ui",self.view_name)
 self._viewport_name=name.."_viewport"
 Managers.ui:create_viewport(self._world,self._viewport_name,"overlay_offscreen",1,self._definitions.shading_environment)
 self._renderer=Managers.ui:create_renderer(name.."_renderer",self._world)
end

RecipeView._read_draft = function(self)
 local out=table.clone(self._draft)
 for key,w in pairs(self._controls) do out[key]=w.content.input_text end
 return out
end

RecipeView._dirty = function(self)
 local draft=self:_read_draft()
 for key,value in pairs(draft) do if tostring(value)~=tostring(self._baseline[key]) then return true end end
 return false
end

RecipeView._confirm = function(self,message,action)
 self._confirmation=action
 Managers.event:trigger("event_show_ui_popup",{title_text_unlocalized=mod:localize("recipe_editor"),
  description_text_unlocalized=message,options={
   {text=mod:localize("recipe_confirm"),no_localization=true,close_on_pressed=true,callback=function()
    self._confirmation=nil;self._popup_id=nil;action()
   end},
   {text="loc_popup_button_cancel",close_on_pressed=true,hotkey="back",callback=function() self._confirmation=nil;self._popup_id=nil end},
  }},function(id) self._popup_id=id end)
end

RecipeView._discard_then = function(self,action)
 if self:_dirty() then self:_confirm(mod:localize("recipe_discard"),action) else action() end
end

RecipeView._select = function(self,definition,saved)
 self:close_focused_dropdown()
 self._draft=table.clone(definition)
 self._draft.legendary=definition.legendary~=false
 self._baseline=table.clone(self._draft)
 self._selected_id=saved and definition.id or nil
 for key,w in pairs(self._controls) do
  local c=w.content
  c.input_text=tostring(definition[key]);c.setting_value=c.input_text;c.is_writing=false
  c._input_text=nil;c._caret_position=nil;c.caret_position=#c.input_text+1;c.force_caret_update=true
 end
 self:_refresh_preview()
end

RecipeView.cb_new = function(self)
 self:_discard_then(function()
  local ids={};for _,r in ipairs(mod.user_buffs.definitions()) do ids[r.id]=true end
  local id,n="new_buff",1
  while ids[id] do n=n+1;id="new_buff_"..n end
  self:_select({id=id,name="New buff",trigger="dodge",effect="movement_speed",amount=2,max_stacks=3,
   duration=10,chance=100,cooldown=0,enabled=true,legendary=true},false)
 end)
end

RecipeView._build_list = function(self)
 for _,w in ipairs(self._rows) do self:_unregister_widget_name(w.name) end
 self._rows,self._grid={},nil
 local definitions,errors=mod.user_buffs.definitions()
 local row_blueprint=row_blueprints.blueprints.recipe_row
 local def=UIWidget.create_definition(table.clone(row_blueprint.pass_template),"list_pivot",nil,row_blueprint.size)
 for i,r in ipairs(definitions) do
  local w=self:_create_widget("recipe_row_"..i,def)
  w.content.text=r.name..(r.enabled and "" or " (off)")
  w.content.recipe_id=r.id
  w.content.hotspot.pressed_callback=function() self:_discard_then(function() self:_select(r,true) end) end
  self._rows[#self._rows+1]=w
 end
 self._widgets_by_name.empty.visible=#definitions==0
 if #self._rows>0 then
  self._grid=UIWidgetGrid:new(self._rows,self._rows,self._ui_scenegraph,"list_panel","down",{0,6},nil,true)
  self._grid:set_render_scale(self._render_scale)
  self._grid:assign_scrollbar(self._widgets_by_name.scrollbar,"list_pivot","list_panel")
  self._grid:set_scrollbar_progress(0)
 end
 if #errors>0 then self._message=table.concat(errors,"\n") end
end

RecipeView.cb_save = function(self)
 local draft=self:_read_draft()
 local ok,message=mod.user_buffs.save_definition(draft,self._selected_id)
 self._message=message
 if ok then
  local normalized=mod.user_buffs.validate_definition(draft)
  self:_select(normalized,true);self:_build_list()
 end
 self:_refresh_preview()
 return ok,message
end

RecipeView.cb_delete = function(self)
 local id=self._selected_id
 if not id then return end
 self:_confirm(mod:localize("recipe_delete_confirm",id),function()
  local ok,message=mod.user_buffs.delete_definition(id);self._message=message
  if ok then
   self._baseline=self:_read_draft();self:cb_new();self:_build_list()
  end
 end)
end

RecipeView.cb_reload = function(self)
 self:_discard_then(function()
  local ok,message=mod.user_buffs.reload();self._message=message
  if ok then
   local selected
   for _,r in ipairs(mod.user_buffs.definitions()) do if r.id==self._selected_id then selected=r end end
   if selected then self:_select(selected,true)
   else self._baseline=self:_read_draft();self:cb_new() end
   self:_build_list()
  end
 end)
end

RecipeView._navigate = function(self,view,context)
 self:_discard_then(function()
  mod._recipe_view_draft=nil
  self._leaving=true
  Managers.ui:close_view(VIEW)
  if view then Managers.ui:open_view(view,nil,nil,nil,nil,context) end
 end)
end
RecipeView.cb_on_back_pressed = function(self)
 if self._focused_dropdown then self:close_focused_dropdown();return end
 for _,w in pairs(self._controls) do if w.content.is_writing then w.content.is_writing=false;return end end
 self:_navigate("chaos_wastes_buff_toggle_view")
end
RecipeView.cb_field_changed = function(self) end

RecipeView._build_controls = function(self)
 for _,key in ipairs(self._definitions.fields) do
  local widget
  if key=="trigger" or key=="effect" then
   local options={}
   for id in pairs(recipes[key.."s"]) do options[#options+1]={id=id,display_name=mod:localize(string.format("recipe_%s_%s",key,id)),ignore_localization=true} end
   table.sort(options,function(a,b)return a.display_name<b.display_name end)
   widget=Dropdown.create(self,"input_"..key,"field_"..key,{size={FIELD_WIDTH,42},value_width=VALUE_WIDTH,
    header_text=mod:localize(string.format("recipe_editor_%s",key)),options=options,
    get_function=function()return self._draft[key] end,
    on_activated=function(value)self._draft[key]=value end})
   self._dropdowns[#self._dropdowns+1]=widget
  elseif key=="enabled" or key=="legendary" then
   widget=self:_create_widget("input_"..key,UIWidget.create_definition({
    {pass_type="hotspot",content_id="hotspot"},
    {pass_type="text",value=mod:localize(key=="enabled" and "recipe_editor_enabled" or "recipe_editor_legendary"),style={font_type="proxima_nova_medium",font_size=20,text_color={255,220,215,200},text_vertical_alignment="center"}},
    {pass_type="rect",style={size={32,32},offset={FIELD_WIDTH-36,5,1},color={255,160,150,130}}},
    {pass_type="rect",style={size={28,28},offset={FIELD_WIDTH-34,7,2},color={255,22,24,27}}},
    {pass_type="text",value="",visibility_function=function(c)return c.checked end,
     style={font_type="proxima_nova_bold",font_size=28,text_color={255,190,230,190},size={32,42},offset={FIELD_WIDTH-36,0,3},text_horizontal_alignment="center",text_vertical_alignment="center"}},
   },"field_"..key))
   widget.content.hotspot.pressed_callback=function()self._draft[key]=not self._draft[key] end
  else
   local entry={display_name=mod:localize(string.format("recipe_field_%s",key)),max_length=key=="name" and 120 or (key=="id" and 48 or 12),
    get_function=function()return tostring(self._draft[key]) end,
    on_activated=function(value)self._draft[key]=value;return true end}
   local passes=text_blueprint.pass_template_function(self,entry,{FIELD_WIDTH,42})
   widget=self:_create_widget("input_"..key,UIWidget.create_definition(passes,"field_"..key,nil,{FIELD_WIDTH,42}))
   text_blueprint.init(self,widget,entry,nil,"cb_field_changed")
   widget.style.list_header.font_size=20
   self._controls[key]=widget
  end
  self._widgets[#self._widgets+1]=widget
 end
end

RecipeView._refresh_preview = function(self)
 local draft=self:_read_draft()
 local signature={}
 for _,key in ipairs(self._definitions.fields) do signature[#signature+1]=tostring(draft[key]) end
 signature=table.concat(signature,"\0")
 if signature~=self._preview_signature then
  self._preview_signature=signature
  local definition,message=mod.user_buffs.validate_definition(draft)
  self._valid=definition~=nil
  self._widgets_by_name.preview_title.content.text=tostring(draft.name or "")
  self._widgets_by_name.preview_description.content.text=tostring(message)
 end
 local w=self._widgets_by_name
 w.save.content.hotspot.disabled=not self._valid
 w.delete.content.hotspot.disabled=not self._selected_id
 w.input_enabled.content.checked=self._draft.enabled
 w.input_legendary.content.checked=self._draft.legendary
 w.preview_state.content.text=mod:localize((not self._selected_id or self:_dirty()) and "recipe_unsaved" or "recipe_saved")
 w.status.content.text=(self._message and self._message.."\n" or "")..mod:localize(mod.user_buffs.pending() and "recipe_pending" or "recipe_personal")
 for _,row in ipairs(self._rows) do
  row.content.is_selected=row.content.recipe_id==self._selected_id
  row.content.hotspot.is_selected=row.content.is_selected
 end
end

RecipeView.on_enter = function(self)
 RecipeView.super.on_enter(self)
 self._draft={id="new_buff",name="New buff",trigger="dodge",effect="movement_speed",amount=2,max_stacks=3,duration=10,chance=100,cooldown=0,enabled=true}
 self._baseline=table.clone(self._draft)
 self:_build_controls();self:_build_list()
 local remembered=mod._recipe_view_draft
 if remembered then self:_select(remembered.draft,false);self._selected_id=remembered.id;self._baseline=remembered.baseline
 else local first=mod.user_buffs.definitions()[1];if first then self:_select(first,true) else self:cb_new() end end
 for _,action in ipairs({"new","reload","save","delete"}) do self._widgets_by_name[action].content.hotspot.pressed_callback=callback(self,"cb_"..action) end
 tabs.attach(self,"buffs")
 self._widgets_by_name.title_text.content.text=mod:localize("recipe_editor")
 for _,tab in ipairs(tabs.TABS) do
  if tab.id~="buffs" then self._widgets_by_name["tab_"..tab.id].content.hotspot.pressed_callback=function()self:_navigate(tab.view)end end
 end
 self._widgets_by_name.subtab_buffs.content.hotspot.pressed_callback=function()self:_navigate("chaos_wastes_buff_toggle_view")end
 self._widgets_by_name.subtab_havoc.content.hotspot.pressed_callback=function()self:_navigate("chaos_wastes_buff_toggle_view",{subtab="havoc"})end
 self._widgets_by_name.subtab_editor.content.hotspot.disabled=true
 self._legend=self:_add_element(ViewElementInputLegend,"input_legend",10)
 self._legend:add_entry("loc_settings_menu_close_menu","back",nil,callback(self,"cb_on_back_pressed"),"left_alignment")
 self:_refresh_preview()
end

RecipeView.update = function(self,dt,t,input)
 self.is_text_input_focused=false
 local effective=self._focused_dropdown and input:null_service() or input
 for _,w in pairs(self._controls) do text_blueprint.update(self,w,effective) end
 for _,w in ipairs(self._dropdowns) do Dropdown.update(self,w,(not self._focused_dropdown or self._focused_dropdown==w) and input or input:null_service(),dt,t) end
 Dropdown.handle_outside_click(self,input)
 if self._grid then self._grid:update(dt,t,effective) end
 self:_refresh_preview()
 return RecipeView.super.update(self,dt,t,effective)
end

RecipeView.draw = function(self,dt,t,input,layer)
 Dropdown.draw_with_focus(self,dt,t,input,function(effective)
  self:_draw_elements(dt,t,self._ui_renderer,self._render_settings,effective)
  UIRenderer.begin_pass(self._renderer,self._ui_scenegraph,effective,dt,self._render_settings)
  for _,w in ipairs(self._rows) do if not self._grid or self._grid:is_widget_visible(w) then UIWidget.draw(w,self._renderer) end end
  UIRenderer.end_pass(self._renderer)
  RecipeView.super.draw(self,dt,t,effective,layer)
 end)
end

RecipeView.on_exit = function(self)
 if not self._leaving and self:_dirty() then
  mod._recipe_view_draft={draft=self:_read_draft(),baseline=self._baseline,id=self._selected_id}
 else mod._recipe_view_draft=nil end
 if self._popup_id then Managers.event:trigger("event_remove_ui_popup",self._popup_id) end
 self:close_focused_dropdown()
 self:_remove_element("input_legend")
 Managers.ui:destroy_renderer(self.__class_name.."_renderer")
 ScriptWorld.destroy_viewport(self._world,self._viewport_name)
 Managers.ui:destroy_world(self._world)
 RecipeView.super.on_exit(self)
end
return RecipeView
