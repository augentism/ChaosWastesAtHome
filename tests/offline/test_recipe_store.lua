local harness = ...
local store = harness.load("recipe_store")

local function disk()
	local files = { buffs = "original" }
	local io_lib = { open = function (path, mode)
		if mode == "rb" then
			if files[path] == nil then return nil, "missing" end
			return { read = function (_, n) return files[path]:sub(1, n) end, close = function () return true end }
		end
		return { write = function (_, data) files[path] = data; return true end, close = function () return true end }
	end }
	local function replace(from, to) files[to], files[from] = files[from], nil; return true end
	return files, io_lib, replace
end

return {
	{ "atomic save keeps previous bytes and detects stale editor data", function (a)
		local files, io_lib, replace = disk()
		a.truthy(store.save(io_lib, replace, "buffs", "original", "updated"))
		a.eq(files.buffs, "updated"); a.eq(files["buffs.bak"], "original")
		a.falsy(store.save(io_lib, replace, "buffs", "original", "lost edit"))
		a.eq(files.buffs, "updated")
	end },
	{ "failed replacement preserves original and recovery backup", function (a)
		local files, io_lib, replace = disk()
		local function failing(from, to)
			if to == "buffs" then return false, "access denied" end
			return replace(from, to)
		end
		a.falsy(store.save(io_lib, failing, "buffs", "original", "updated"))
		a.eq(files.buffs, "original"); a.eq(files["buffs.bak"], "original")
	end },
	{ "read failures, bounds, and short writes cannot replace the original", function (a)
		local files, io_lib, replace = disk()
		a.falsy(store.save(io_lib, replace, "buffs", nil, "updated"))
		a.falsy(store.save(io_lib, replace, "buffs", "original", string.rep("x", 65537)))
		local original_open = io_lib.open
		io_lib.open = function (path, mode)
			if mode == "wb" then return { write = function () return nil, "disk full" end, close = function () return true end } end
			return original_open(path, mode)
		end
		a.falsy(store.save(io_lib, replace, "buffs", "original", "updated"))
		a.eq(files.buffs, "original")
	end },
	{ "an external edit during staging is not overwritten", function (a)
		local files, io_lib, replace = disk()
		local function raced(from, to)
			local ok = replace(from, to)
			if to == "buffs.bak" then files.buffs = "external edit" end
			return ok
		end
		a.falsy(store.save(io_lib, raced, "buffs", "original", "updated"))
		a.eq(files.buffs, "external edit")
	end },
}
