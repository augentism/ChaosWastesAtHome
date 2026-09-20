local harness = ...
return {
	{ "family receipts move to corner without moving choices or leaking across sessions", function (a)
		local hooks = {}
		local mod = { manager = {}, is_enabled = function () return true end }
		function mod:io_dofile() return { register = function (_, method, _, fn) hooks[method] = fn end } end
		local chunk = assert(loadfile(harness.ROOT .. "ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/lesser_boon_notification.lua"))
		local api = setfenv(chunk, setmetatable({get_mod=function()return mod end}, {__index=_G}))()
		api.install({}, {family={is_family_buff=true},legendary={is_family_buff=false}})
		local graph = {canvas={size={1920,1080}},buffs_area={size={480,200},position={0,-50}},
			title={position={0,100}},sub_title={position={0,130}}}
		local view = {_ui_scenegraph=graph,_buff_widgets={{}},_context={buffs={{buff_name="family"}}}}
		function view:set_scenegraph_position(id,x,y) graph[id].position={x,y} end
		local native = function () return "kept", nil, 3 end
		local first, second, third = hooks._generate_buffs_widgets(native,view)
		a.eq(first,"kept");a.nil_(second);a.eq(third,3)
		a.eq(graph.buffs_area.position[1],-660);a.eq(graph.buffs_area.position[2],-280)
		hooks._update_view_state(native,view)
		a.eq(graph.buffs_area.position[1],-660,"no cumulative offset")
		for _,flag in ipairs({"is_choice","is_buff_family","is_wave_title","is_choice_notification"}) do
			view._context[flag]=true;hooks._update_view_state(native,view)
			a.eq(graph.buffs_area.position[1],0);a.eq(graph.title.position[2],100)
			view._context[flag]=nil;hooks._update_view_state(native,view)
		end
		mod.manager=nil;hooks._update_view_state(native,view)
		a.eq(graph.buffs_area.position[2],-50);a.nil_(view._cwah_lesser_positions)
		mod.manager={};view._context.buffs[1].buff_name="legendary"
		hooks._generate_buffs_widgets(native,view);a.eq(graph.buffs_area.position[1],0)
	end },
}
