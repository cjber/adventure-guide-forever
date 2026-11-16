-- Run from the repository root: luajit tests/rxp_badge_spec.lua
-- A compact guide row carries two marks at its right edge (#713): RestedXP's own logo and the Adventure Guide's
-- "new" badge. They reserve separate room and never overlap, and the title gives both their width.
local harness = dofile("tests/harness.lua")
local checks = 0

local function check(ok, label)
	checks = checks + 1
	if not ok then
		error(label, 2)
	end
end

local LOGO = [[Interface\AddOns\RXPGuides\Textures\v2\rxp-icon-logo]]
local h = harness.load({
	spf = "v1",
	planned = true,
	db = { autoStart = false },
	charDB = { journey = "carry" },
	completed = { 844 },
	log = { { id = 843, title = "Gann's Reclamation", level = 23, complete = false } },
})
-- The fixture publishes RestedXP's own v2 theme logo; the scenes resolve that exact file from the installed addon.
local engine = dofile("tests/rxp_fixture.lua")(h, nil, nil, "19-25 Elwynn")
check(
	engine.v2 and engine.v2.activeTheme and engine.v2.activeTheme.guideWindow.logo == LOGO,
	"the fixture names RestedXP's v2 logo"
)
check(h.ns.RestedXP.ProviderIcon() == LOGO, "the guide card carries RestedXP's installed mark")

-- A level gained after the guide's cards arrive marks them, so the row has both its "new" badge and the logo.
for key in pairs(h.ns.Prefs().seen or {}) do
	if key:find("^guide:") then
		h.ns.Prefs().seen[key] = nil
	end
end
h.player.level = 19
h.fire("PLAYER_LEVEL_UP")
h.flush()
h.ns.Invalidate()
h.flush()
h.ns.OpenPanel()
h.flush()

local rows = h.Find(function(frame)
	return frame.Provider ~= nil
		and frame.IconFrame ~= nil
		and frame.journey ~= nil
		and frame:GetHeight() == 26
		and frame.Provider:IsShown()
end)
check(#rows == 2, "both offered RestedXP guides have a compact row with the provider's mark")
local row = rows[1]
check(row.journey.providerIcon == LOGO and row.New:IsShown(), "the row draws the logo and its new badge")

local newPoint, _, _, newX = row.New:GetPoint(1)
local providerPoint, _, _, providerX = row.Provider:GetPoint(1)
check(newPoint == "RIGHT" and providerPoint == "RIGHT", "both marks sit at the row's right edge")
check(newX <= providerX - row.Provider:GetWidth(), "the new badge ends before the provider's mark starts")
local _, _, _, iconX = row.IconFrame:GetPoint(1)
local _, _, _, titleX = row.Title:GetPoint(1)
local titleRight = iconX + row.IconFrame:GetWidth() + titleX + row.Title:GetWidth()
local newLeft = row:GetWidth() + newX - row.New:GetWidth()
check(titleRight <= newLeft, "the title's run ends before the new badge")

local plain
for _, candidate in
	ipairs(h.Find(function(frame)
		return frame.Provider ~= nil and frame.IconFrame ~= nil and frame:GetHeight() == 26 and frame:IsVisible()
	end))
do
	if not candidate.Provider:IsShown() then
		plain = plain or candidate
	end
end
check(plain ~= nil and plain:GetWidth() == row:GetWidth(), "a compact card without a mark keeps its full row")
check(plain.Title:GetWidth() > row.Title:GetWidth(), "a title with no marks keeps the room the marked row gives them")

h.Hover(row)
local hint
for _, line in ipairs(h.tooltip) do
	if line:find("RestedXP", 1, true) then
		hint = line
	end
end
check(hint ~= nil, "the row's tooltip names RestedXP as where its steps come from")

-- The chosen card's larger 18px mark sits inside the card's bevel, not on it.
local chosenH = harness.load({
	spf = "v1",
	db = { autoStart = false },
	charDB = false,
	completed = { 844 },
	log = {},
})
dofile("tests/rxp_fixture.lua")(chosenH, 10)
local chosenGuide = assert(chosenH.ns.RestedXP.Journey())
chosenH.ns.Choose(chosenGuide.key, true)
chosenH.flush()
chosenH.ns.OpenPanel()
chosenH.flush()
local chosen = chosenH.Find(function(frame)
	return frame.IconFrame ~= nil
		and frame.journey ~= nil
		and frame.journey.key == chosenGuide.key
		and frame:IsVisible()
end)[1]
check(chosen ~= nil and chosen.Provider:IsShown(), "the chosen guide card draws the provider's mark")
local _, _, _, markX, markY = chosen.Provider:GetPoint(1)
check(markX <= -10 and markY <= -8, "the chosen card's mark keeps clear of its top and right bevel")

check(#h.errors == 0, "no errors\n" .. table.concat(h.errors, "\n"))
check(#chosenH.errors == 0, "no errors in the chosen card's run\n" .. table.concat(chosenH.errors, "\n"))
print(("rxp_badge_spec: %d checks passed"):format(checks))
