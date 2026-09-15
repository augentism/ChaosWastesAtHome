local harness = ...

local function fixture()
 local mod={user_buffs={}}
 function mod:io_dofile() return {install=function()end,create_blueprint=function()return{}end} end
 function mod:localize(key) return key end
 local events,opened={},{ }
 local env=setmetatable({get_mod=function()return mod end,require=function()return{}end,
  class=function()return{}end,Managers={event={trigger=function(_,event,data,cb)
   events[#events+1]={event=event,data=data};if cb then cb(1) end
  end},ui={close_view=function()end,open_view=function(_,name)opened[#opened+1]=name end}}},{__index=_G})
 local chunk=assert(loadfile(harness.ROOT.."ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/view/recipe_view.lua"))
 local cls=setfenv(chunk,env)()
 local view=setmetatable({_controls={},_rows={}}, {__index=cls})
 function view:close_focused_dropdown()end
 function view:_refresh_preview()end
 function view:_build_list()end
 local base={id="test",name="Test",trigger="dodge",effect="movement_speed",amount=2,max_stacks=3,
  duration=10,chance=100,cooldown=0,enabled=true}
 view:_select(base,true)
 return view,mod,events,opened,base
end

return {
 {"recipe view reads uncommitted text for save and guards dirty navigation",function(a)
  local v,m,events,opened=fixture()
  a.falsy(v:_dirty())
  v._controls.name={content={input_text="Still typing"}}
  a.eq(v:_read_draft().name,"Still typing");a.truthy(v:_dirty())
  v:_navigate("destination")
  a.eq(#opened,0);a.truthy(v._confirmation)
  events[#events].data.options[2].callback()
  a.nil_(v._confirmation);a.truthy(v:_dirty())
  v:_navigate("destination")
  events[#events].data.options[1].callback()
  a.eq(opened[1],"destination")
 end},
 {"failed view saves preserve draft and identity; successful saves replace baseline",function(a)
  local v,m=fixture()
  v._controls.name={content={input_text="Changed"}}
  m.user_buffs.save_definition=function(draft,id)
   a.eq(id,"test");a.eq(draft.name,"Changed");return false,"conflict"
  end
  a.falsy(v:cb_save());a.truthy(v:_dirty());a.eq(v._selected_id,"test")
  m.user_buffs.save_definition=function()return true,"saved"end
  m.user_buffs.validate_definition=function(d)return d end
  a.truthy(v:cb_save());a.falsy(v:_dirty());a.eq(v._baseline.name,"Changed")
 end},
 {"view deletion requires confirmation and failed deletion retains selected buff",function(a)
  local v,m,events=fixture();local calls=0
  m.user_buffs.delete_definition=function(id)calls=calls+1;a.eq(id,"test");return false,"disk failure"end
  v:cb_delete();a.eq(calls,0)
  events[#events].data.options[2].callback();a.eq(calls,0)
  v:cb_delete();events[#events].data.options[1].callback()
  a.eq(calls,1);a.eq(v._selected_id,"test");a.eq(v._message,"disk failure")
 end},
 {"reload errors preserve the selected draft after explicit discard confirmation",function(a)
  local v,m,events=fixture();local calls=0
  v._controls.name={content={input_text="Changed"}}
  m.user_buffs.reload=function()calls=calls+1;return false,"bad file"end
  v:cb_reload();a.eq(calls,0)
  events[#events].data.options[1].callback()
  a.eq(calls,1);a.eq(v:_read_draft().name,"Changed");a.eq(v._selected_id,"test")
 end},
}
