-- Adapted from songsintransmit's TEST7 shared hook dispatcher.
-- One DMF registration per object/method, including mixed normal/after callbacks.
local mod = get_mod("ChaosWastesAtHome")
if mod._cwah_shared_hooks then return mod._cwah_shared_hooks end
local api, objects = {}, {}
local function pack(...) return { n = select("#", ...), ... } end
local function object_key(object)
	if type(object) == "table" and CLASS then
		for name, value in pairs(CLASS) do
			if value == object then return name end
		end
	end
	return object
end
local function invoke(entry, index, native, ...)
	if index == 0 then return native(...) end
	return entry.callbacks[entry.order[index]](function (...)
		return invoke(entry, index - 1, native, ...)
	end, ...)
end
local function entry_for(object, method)
	local key = object_key(object)
	objects[key] = objects[key] or {}
	local entry = objects[key][method]
	if entry then return entry end
	entry = { callbacks = {}, order = {}, after = {}, after_order = {}, reported = {} }
	objects[key][method] = entry
	mod:hook(object, method, function (native, ...)
		local result = pack(invoke(entry, #entry.order, native, ...))
		-- These run after this dispatcher's normal chain. Unlike DMF hook_safe,
		-- they cannot promise to run after outer hooks owned by other mods.
		for _, id in ipairs(entry.after_order) do
			local ok, err = pcall(entry.after[id], ...)
			if not ok and not entry.reported[id] then
				entry.reported[id] = true
				mod:error("Shared hook %s.%s (%s): %s", tostring(object), method, id, tostring(err))
			end
		end
		return unpack(result, 1, result.n)
	end)
	return entry
end
function api.register(object, method, id, callback)
	local entry = entry_for(object, method)
	if not entry.callbacks[id] then entry.order[#entry.order + 1] = id end
	entry.callbacks[id] = callback
end
function api.register_safe(object, method, id, callback)
	local entry = entry_for(object, method)
	if not entry.after[id] then entry.after_order[#entry.after_order + 1] = id end
	entry.after[id], entry.reported[id] = callback, nil
end
mod._cwah_shared_hooks = api
return api
