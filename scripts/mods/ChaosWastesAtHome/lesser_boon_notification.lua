-- Positioning adapted from songsintransmit's TEST10 Korean fork.
-- Automatic family-buff receipts move; interactive choices keep native layout.
local mod = get_mod("ChaosWastesAtHome")
local api = {}
local nodes = { "buffs_area", "title", "sub_title" }

local function restore(self)
	local saved = self._cwah_lesser_positions
	if not saved then return end
	for name, p in pairs(saved) do
		if self._ui_scenegraph and self._ui_scenegraph[name] then
			self:set_scenegraph_position(name, p[1], p[2])
		end
	end
	self._cwah_lesser_positions = nil
end

function api.install(class, data)
	local shared = mod:io_dofile("ChaosWastesAtHome/scripts/mods/ChaosWastesAtHome/shared_hooks")
	local function eligible(self)
		local c = self._context
		if not mod:is_enabled() or not mod.manager or not c or c.is_choice
			or c.is_buff_family or c.is_wave_title or c.is_choice_notification
			or not c.buffs or #c.buffs ~= 1 then return false end
		local buff = data[c.buffs[1].buff_name]
		return buff and buff.is_family_buff == true or false
	end
	local function position(self)
		if not eligible(self) or not self._buff_widgets or #self._buff_widgets ~= 1 then return end
		local graph = self._ui_scenegraph
		if not graph or not graph.canvas then return end
		for _, name in ipairs(nodes) do if not graph[name] then return end end
		local canvas, area = graph.canvas.size, graph.buffs_area.size
		if not canvas or not area then return end
		if not self._cwah_lesser_positions then
			local saved = {}
			for _, name in ipairs(nodes) do
				local p = graph[name].position
				saved[name] = { p[1], p[2] }
			end
			self._cwah_lesser_positions = saved
		end
		-- Scaled UI coordinates: 60 from left, 160 from top. Leave space
		-- above the card for its artwork and acquisition heading.
		local x = 60 + area[1] * 0.5 - canvas[1] * 0.5
		local function set(name, y)
			local p = graph[name].position
			if p[1] ~= x or p[2] ~= y then self:set_scenegraph_position(name, x, y) end
		end
		set("buffs_area", 160 + area[2] * 0.5 - canvas[2] * 0.5)
		set("title", 28)
		set("sub_title", 56)
	end
	shared.register(class, "_generate_buffs_widgets", "lesser_boon_corner", function (func, self, ...)
		restore(self)
		local function finish(...)
			position(self)
			return ...
		end
		return finish(func(self, ...))
	end)
	shared.register(class, "_update_view_state", "lesser_boon_corner", function (func, self, ...)
		if not eligible(self) then restore(self) end
		local function finish(...)
			if eligible(self) then position(self) else restore(self) end
			return ...
		end
		return finish(func(self, ...))
	end)
end

return api
