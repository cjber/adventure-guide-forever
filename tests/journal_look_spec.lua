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
local Window = ns.Window
local parent = h.G.CreateFrame("Frame")

-- The Journal's own values, verified in Blizzard_Fonts_Shared/Shared/FontStyles.xml and GameFontStyles.xml.
equal(Window.FONT_TITLE, "GameFontNormalLarge2", "the panel title font")
equal(Window.FONT_ROW, "GameFontNormalMed3", "the list row font")
equal(Window.FONT_HEADER, "GameFontNormal", "the section header font")
same(Window.GOLD, { 0.929, 0.788, 0.62 }, "the gold")

local heading = Window.Heading(parent, "Next steps")
equal(heading:GetFontObject():GetName(), Window.FONT_HEADER, "a heading takes the header font")
same(heading.textColor, { Window.GOLD[1], Window.GOLD[2], Window.GOLD[3] }, "in the Journal's gold")

-- A section header carries the paper-overlay caps and tiled middle, and folds only when given a callback.
local header = Window.CreateSectionHeader(parent, "Next steps")
equal(header.Label:GetText(), "Next steps", "the section's name")
equal(header.Left.file, "Interface\\EncounterJournal\\UI-EncounterJournalTextures", "the paper cap's own file")
equal(header.Right.file, "Interface\\EncounterJournal\\UI-EncounterJournalTextures", "the other cap")
equal(header.Mid.file, "Interface\\EncounterJournal\\UI-EncounterJournalTextures_Tile", "the tiled middle")
equal(header.Chevron.text, nil, "no callback, no fold glyph")
local folded
local folding = Window.CreateSectionHeader(parent, "Reagents", function(open)
	folded = open
end)
equal(folding.Open, true, "a foldable section starts open")
equal(folding.Chevron:GetText(), "-", "with the minus glyph")
folding:GetScript("OnClick")(folding)
equal(folding.Open, false, "the click folds it")
equal(folding.Chevron:GetText(), "+", "and shows the plus glyph")
equal(folded, false, "and tells the caller")

-- A page the client has no art for: a flat dark tile, never a question mark or a substituted picture.
local empty = Window.CreateEmpty(parent, "AGF-No-Such-Atlas")
same(empty.Art.color, { 0.1, 0.09, 0.08, 1 }, "an unknown atlas leaves the dark tile")
equal(empty.Art.atlas, nil, "and no atlas was set")
Window.SetEmpty(empty, "Nothing here")
equal(empty.Text:GetText(), "Nothing here", "the page still says why")

-- A ring with no art keeps its dark disc and hides the icon rather than showing a question mark.
local ring = Window.CreateRingIcon(parent, 26)
Window.SetRingIcon(ring, nil)
equal(ring.Icon:IsShown(), false, "no icon art leaves the ring's disc")

equal(#h.errors, 0, "no errors")
print(("journal_look_spec: %d checks passed"):format(checks))
