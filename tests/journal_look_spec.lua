-- Run from the repository root: luajit tests/journal_look_spec.lua
-- The window's Journal look (UI/WindowWidgets.lua): the Encounter Journal's type and palette, the paper section
-- header, and the flat dark tile a page with no art falls back to.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function same(actual, expected, label)
	equal(#actual, #expected, label .. " length")
	for index, value in ipairs(expected) do
		equal(actual[index], value, label .. " [" .. index .. "]")
	end
end

local h = harness.load()
local ns = h.ns
local Window = ns.Widgets
local parent = h.G.CreateFrame("Frame")

local heading = Window.Heading(parent, "Next steps")
equal(heading:GetFontObject():GetName(), "GameFontNormal", "a heading takes the header font")
same(heading.textColor, { 0.929, 0.788, 0.62 }, "in the Journal's gold")

equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("journal_look_spec: " .. checks .. " checks passed")
