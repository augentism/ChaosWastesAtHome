-- Bounded text I/O with optimistic conflict detection and atomic replacement.
-- Dependencies are injected so disk-full, rename and external-edit failures
-- can be tested without touching a player's files.
local store = {}

store.read = function (io_lib, path)
	local file, err = io_lib.open(path, "rb")
	if not file then return nil, err end
	local text, read_err = file:read(65537)
	file:close()
	if not text then return nil, read_err or "Could not read recipes" end
	if #text > 65536 then return nil, "Recipe file exceeds 65536 bytes" end
	return text
end

local function write(io_lib, path, text)
	local file, err = io_lib.open(path, "wb")
	if not file then return false, err end
	local ok, written, write_err = pcall(file.write, file, text)
	local closed, close_err = file:close()
	if not ok or not written or not closed then return false, tostring(not ok and written or write_err or close_err) end
	return true
end

store.save = function (io_lib, replace, path, expected, text)
	if type(expected) ~= "string" then return false, "Reload the recipe file before saving" end
	if type(text) ~= "string" or #text > 65536 then return false, "Recipe file exceeds 65536 bytes" end
	local current, err = store.read(io_lib, path)
	if not current then return false, err end
	if current ~= expected then return false, "Recipe file changed externally. Reload from disk before saving." end
	if current == text then return true end
	local ok
	ok, err = write(io_lib, path .. ".tmp", text)
	if not ok then return false, err end
	ok, err = write(io_lib, path .. ".bak.tmp", current)
	if not ok then return false, err end
	ok, err = replace(path .. ".bak.tmp", path .. ".bak")
	if not ok then return false, "Could not preserve recipe backup: " .. tostring(err) end
	current, err = store.read(io_lib, path)
	if current ~= expected then return false, err or "Recipe file changed while saving; original preserved" end
	ok, err = replace(path .. ".tmp", path)
	if not ok then return false, "Could not replace recipe file: " .. tostring(err) end
	return true
end

return store
