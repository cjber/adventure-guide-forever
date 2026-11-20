-- The loader adopts an installed standalone ForeverCore as it is, even when it is older than the copy this addon
-- embeds, so the addon loads on any runtime that serves consumer API 2. ForeverCore 1.15.3 has no
-- SettingsSections.RegisterTrackerAttach (added in 1.15.4): the Tracker page goes without the Attach row, and nothing
-- else on the page or at load changes.
local harness = dofile("tests/harness.lua")
harness.data()

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local function Keys(h)
	local keys = {}
	for _, entry in ipairs(h.settings) do
		if entry.key then
			keys[entry.key] = true
		end
	end
	return keys
end

local current = harness.load({ log = {}, completed = {} })
current.flush()
equal(#current.errors, 0, "core with the Attach row: no errors\n" .. table.concat(current.errors, "\n"))

local older = harness.load({ log = {}, completed = {}, coreWithout = { "SettingsSections.RegisterTrackerAttach" } })
older.flush()
equal(#older.errors, 0, "core without the Attach row: no errors\n" .. table.concat(older.errors, "\n"))
local before, after = Keys(current), Keys(older)
local missing = {}
for key in pairs(before) do
	if not after[key] then
		missing[#missing + 1] = key
	end
end
table.sort(missing)
equal(table.concat(missing, " "), "trackerAttached", "only the Attach row is missing")
equal(after.lockTracker, true, "the Lock row still registers")

print(("older_core_spec: %d checks passed"):format(checks))
