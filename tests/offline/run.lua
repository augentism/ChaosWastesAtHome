-- Offline test runner. Invoked by run_tests.py, or directly:
--
--   cd ChaosWastesAtHome/tests && luajit offline/run.lua
--   cd ChaosWastesAtHome/tests && luajit offline/run.lua run difficulty
--
-- Trailing arguments filter which test files run, matched as substrings of the
-- file name, so `run difficulty` runs test_run.lua and test_difficulty.lua.

local harness = dofile((os.getenv("CWAH_TEST_DIR") or ".") .. "/offline/harness.lua")

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------

-- Every failure raises a table rather than a string, so the runner can tell a
-- deliberate assertion failure from an unexpected Lua error in the test itself.
-- Conflating those hides real breakage as "test failed".
local function fail(message)
	error({ assertion = true, message = message }, 3)
end

local function _render(value)
	if type(value) ~= "table" then
		return tostring(value)
	end

	local parts = {}

	for i, v in ipairs(value) do
		parts[i] = tostring(v)

		if i >= 8 then
			parts[i + 1] = "... (" .. #value .. " total)"

			break
		end
	end

	return "{" .. table.concat(parts, ", ") .. "}"
end

local a = {}

a.eq = function (got, want, what)
	if got ~= want then
		fail(string.format("%s: expected %s, got %s",
			what or "value", _render(want), _render(got)))
	end
end

a.neq = function (got, unwanted, what)
	if got == unwanted then
		fail(string.format("%s: expected anything but %s", what or "value", _render(unwanted)))
	end
end

a.truthy = function (got, what)
	if not got then
		fail(string.format("%s: expected truthy, got %s", what or "value", _render(got)))
	end
end

a.falsy = function (got, what)
	if got then
		fail(string.format("%s: expected falsy, got %s", what or "value", _render(got)))
	end
end

a.nil_ = function (got, what)
	if got ~= nil then
		fail(string.format("%s: expected nil, got %s", what or "value", _render(got)))
	end
end

local function _find(list, needle)
	for _, v in ipairs(list or {}) do
		if v == needle then
			return true
		end
	end

	return false
end

a.contains = function (list, needle, what)
	if not _find(list, needle) then
		fail(string.format("%s: expected to contain %s, got %s",
			what or "list", tostring(needle), _render(list)))
	end
end

a.not_contains = function (list, needle, what)
	if _find(list, needle) then
		fail(string.format("%s: expected NOT to contain %s, got %s",
			what or "list", tostring(needle), _render(list)))
	end
end

a.count = function (list, want, what)
	local got = #list

	if got ~= want then
		fail(string.format("%s: expected %d entries, got %d -- %s",
			what or "list", want, got, _render(list)))
	end
end

-- Number of keys, for hash tables where # is meaningless.
a.size = function (t, want, what)
	local got = 0

	for _ in pairs(t or {}) do
		got = got + 1
	end

	if got ~= want then
		fail(string.format("%s: expected %d keys, got %d", what or "table", want, got))
	end
end

a.gt = function (got, floor, what)
	if type(got) ~= "number" or got <= floor then
		fail(string.format("%s: expected > %s, got %s", what or "value", tostring(floor), tostring(got)))
	end
end

a.fail = fail

-- ---------------------------------------------------------------------------
-- Discovery
-- ---------------------------------------------------------------------------

-- Listed rather than globbed: LuaJIT has no directory API without an FFI dance,
-- and an explicit list means a test file that fails to load is a hard error
-- instead of quietly not running -- which is the failure mode that makes a
-- green suite worthless.
local FILES = {
	"test_shared_hooks",
	"test_dreyko",
	"test_pause_audio",
	"test_particle_guard",
	"test_game_mode_shim",
	"test_buff_registry",
	"test_buff_pack_compat",
	"test_buff_namespaces",
	"test_cwah_multishot",
	"test_cwah_catalogue",
	"test_buff_pool",
	"test_run",
	"test_difficulty",
	"test_havoc_pool",
	"test_shrines",
	"test_buff_subtabs",
	"test_net_vote",
}

local filters = { ... }

local function wanted(name)
	if #filters == 0 then
		return true
	end

	for _, f in ipairs(filters) do
		if name:find(f, 1, true) then
			return true
		end
	end

	return false
end

-- ---------------------------------------------------------------------------
-- Run
-- ---------------------------------------------------------------------------

local DIR = (os.getenv("CWAH_TEST_DIR") or ".") .. "/offline/"

local passed, failed, errored, skipped = 0, 0, 0, 0
local problems = {}

for _, file in ipairs(FILES) do
	if not wanted(file) then
		skipped = skipped + 1
	else
		io.write(file, "\n")

		local chunk, load_err = loadfile(DIR .. file .. ".lua")

		if not chunk then
			errored = errored + 1
			problems[#problems + 1] = file .. ": could not load: " .. tostring(load_err)
			io.write("  !! could not load: ", tostring(load_err), "\n")
		else
			local ok, cases = pcall(chunk, harness, a)

			if not ok then
				errored = errored + 1
				problems[#problems + 1] = file .. ": error while building cases: " .. tostring(cases)
				io.write("  !! ", tostring(cases), "\n")
			else
				for _, case in ipairs(cases) do
					local name, fn = case[1], case[2]

					harness.reset()

					local case_ok, err = pcall(fn, a, harness)

					if case_ok then
						passed = passed + 1
						io.write("  ok   ", name, "\n")
					elseif type(err) == "table" and err.assertion then
						failed = failed + 1
						problems[#problems + 1] = file .. " / " .. name .. ": " .. err.message
						io.write("  FAIL ", name, "\n         ", err.message, "\n")
					else
						errored = errored + 1
						problems[#problems + 1] = file .. " / " .. name .. ": " .. tostring(err)
						io.write("  ERR  ", name, "\n         ", tostring(err), "\n")
					end
				end
			end
		end
	end
end

io.write("\n")

if #problems > 0 then
	io.write("problems:\n")

	for _, p in ipairs(problems) do
		io.write("  - ", p, "\n")
	end

	io.write("\n")
end

io.write(string.format("offline: %d passed, %d failed, %d errored", passed, failed, errored))

if skipped > 0 then
	io.write(string.format(", %d file(s) filtered out", skipped))
end

io.write("\n")

os.exit((failed + errored) > 0 and 1 or 0)
