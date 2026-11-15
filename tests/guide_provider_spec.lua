-- Run from the repository root: luajit tests/guide_provider_spec.lua
-- A RestedXP guide card says where its steps come from (#713): the card draws RestedXP's own mark, its tooltip names
-- RestedXP, and Adventure Guide's Clean up my log and zone story keep their own icons. Card sizes stay as they were.
local harness = dofile("tests/harness.lua")
local checks = 0

local function check(ok, label)
	checks = checks + 1
	if not ok then
		error(label, 2)
	end
end

local function Shown(h, test)
	return h.Find(function(frame)
		return frame:IsVisible() and test(frame)
	end)
end

local function Tip(h, frame)
	h.Hover(frame)
	return table.concat(h.tooltip, "\n")
end

local h = harness.load({
	planned = true,
	panelHeight = 1200,
	spf = "v1",
	db = { autoStart = false },
	charDB = false,
	completed = { 844 },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	},
})
local engine = dofile("tests/rxp_fixture.lua")(h)
-- RestedXP's v2 theme names the 256-square logo it draws in its own guide window, so the card never guesses at a
-- path. The legacy fallback asks for exactly the 64 the legacy guide window requests; the 128 path here is a trap.
local LOGO = [[Interface\AddOns\RXPGuides\Textures\v2\rxp-icon-logo]]
local LOGO_LEGACY = [[Interface\AddOns\RXPGuides\Textures\rxp_logo-64]]
local LOGO_UNSHIPPED = [[Interface\AddOns\MyCustomTheme\rxp_logo-128]]
local asked = {}
engine.v2 = { activeTheme = { guideWindow = { logo = LOGO } } }
engine.GetV1Texture = function(name)
	asked[#asked + 1] = name
	return name == "rxp_logo-64" and LOGO_LEGACY or name == "rxp_logo-128" and LOGO_UNSHIPPED or nil
end
-- A second guide in the catalogue, so the offered card is exercised as well as the one being followed. Its level span
-- leaves it open to the level-18 character.
engine.guideList.Example.names_[2] = { group = "Example guides", name = "19-25 Elwynn" }
local running = engine.GetGuideTable
engine.GetGuideTable = function(_, group, name)
	if name == "19-25 Elwynn" then
		return { name = name, group = group, steps = {} }
	end
	return running(group, name)
end
h.flush()
local ns = h.ns
ns.Invalidate()
h.flush()

local guide = assert(ns.RestedXP.Journey())
check(guide.provider == "RestedXP", "the guide being followed names RestedXP")
check(
	guide.providerIcon == ns.RestedXP.ProviderIcon() and guide.providerIcon == LOGO,
	"the guide draws RestedXP's own installed mark"
)
check(asked[1] == nil and guide.providerIcon:find("rxp-icon-logo", 1, true) ~= nil, "the v2 theme's own logo leads")
check(
	guide.subline == ns.L.RXP_PROGRESS:format(engine.GetGuideProgress(), 2),
	"the chosen guide's card keeps its step progress"
)

local choices = ns.RestedXP.Cards()
check(#choices == 2, "the catalogue offers the running guide and the other one")
for _, choice in ipairs(choices) do
	check(choice.provider == "RestedXP" and choice.providerIcon == guide.providerIcon, "catalogue cards name RestedXP")
end

-- The overview, where the player picks a journey: the offered guide draws the provider's mark; Clean up my log and the
-- zone story keep their quest-log icons.
local offered
for _, journey in ipairs(ns.Route().journeys) do
	offered = offered or (journey.kind == "guide" and journey.key == choices[2].key and journey or nil)
end
check(offered ~= nil and offered.provider == "RestedXP", "the offered guide joins the route with its provider")
-- The client's own open, so the map shows with the quest sidebar the guide lives in (#664).
h.G.C_Map.OpenWorldMap()
h.flush()
ns.Prefs().previewGroups = { continue = false }
ns.OpenPanel()
h.flush()
local overviewGuide = Shown(h, function(frame)
	return frame.Icon ~= nil and frame.Icon.Clip ~= nil and frame.journey == offered
end)[1]
check(overviewGuide ~= nil, "the offered guide has an overview card")
check(overviewGuide:GetHeight() == 64, "the provider mark keeps the overview card's height")
check(
	overviewGuide.Icon.Kind.atlas == ns.Overview.KIND_ICONS.guide and overviewGuide.Icon.Kind.file == nil,
	"the overview guide card keeps the guide kind's own icon"
)
check(
	overviewGuide.Provider.file == offered.providerIcon and overviewGuide.Provider:IsShown(),
	"the overview guide card draws RestedXP's mark at its top right"
)
check(
	Tip(h, overviewGuide):find(ns.L.PROVIDER_CARD_HINT:format("RestedXP"), 1, true) ~= nil,
	"the offered guide's tooltip says its steps come from RestedXP"
)

local carry, story = nil, nil
for _, journey in ipairs(ns.Route().journeys) do
	carry = carry or (journey.kind == "carry" and journey or nil)
	story = story or (journey.kind == "story" and journey or nil)
end
local overviewCarry = Shown(h, function(frame)
	return frame.Icon ~= nil and frame.Icon.Clip ~= nil and frame.journey == carry
end)[1]
local overviewStory = Shown(h, function(frame)
	return frame.Icon ~= nil and frame.Icon.Clip ~= nil and frame.journey == story
end)[1]
check(
	overviewCarry and overviewCarry.Icon.Kind.atlas == ns.Overview.KIND_ICONS.carry,
	"Clean up my log keeps its own icon"
)
check(
	overviewStory and overviewStory.Icon.Kind.atlas == ns.Overview.KIND_ICONS.story,
	"the zone story keeps its own icon"
)
check(
	Tip(h, overviewStory):find("RestedXP", 1, true) == nil,
	"an Adventure Guide card's tooltip never claims to be RestedXP's"
)

-- The chosen guide's card in the guide list, and the cards under it: the same mark at the same sizes.
ns.Choose(guide.key, true)
h.flush()
local chosen = Shown(h, function(frame)
	return frame.IconFrame ~= nil and frame.journey and frame.journey.key == guide.key
end)[1]
check(chosen ~= nil, "the chosen guide has a card")
check(chosen:GetHeight() == 86, "the provider mark keeps the chosen card's height")
check(
	chosen.IconFrame.Icon.atlas == ns.Overview.KIND_ICONS.guide and chosen.IconFrame.Icon.file == nil,
	"the chosen guide card keeps the guide kind's own icon"
)
check(
	chosen.Provider.file == guide.providerIcon and chosen.Provider:IsShown(),
	"the chosen guide card draws RestedXP's mark at its top right"
)
check(chosen.Title:GetWidth() < 212, "the provider mark shortens the title's run so the two never overlap")
check(
	Tip(h, chosen):find(ns.L.PROVIDER_CARD_HINT:format("RestedXP"), 1, true) ~= nil,
	"the chosen guide's tooltip says its steps come from RestedXP"
)
local compactStory = Shown(h, function(frame)
	return frame.IconFrame ~= nil and frame.journey.kind == "story"
end)[1]
check(compactStory and compactStory:GetHeight() == 26, "another card's compact row keeps its height")
check(
	compactStory.IconFrame.Icon.atlas == ns.Overview.KIND_ICONS.story and compactStory.IconFrame.Icon.file == nil,
	"a compact zone story keeps its own icon"
)

-- Older RestedXP, without the v2 theme, names the 64 logo its legacy window draws; only then does the card fall back.
engine.v2.activeTheme = nil
ns.Invalidate()
h.flush()
local legacy = Shown(h, function(frame)
	return frame.IconFrame ~= nil and frame.journey and frame.journey.key == guide.key
end)[1]
local only64 = true
for _, name in ipairs(asked) do
	only64 = only64 and name == "rxp_logo-64"
end
check(
	legacy and legacy.journey.providerIcon == LOGO_LEGACY and only64,
	"a legacy guide asks only for the 64 logo it draws, never an unshipped 128"
)

-- Without a path from RestedXP the card keeps its known kind icon rather than drawing a file that may be missing.
engine.GetV1Texture = nil
ns.Invalidate()
h.flush()
local fallback = Shown(h, function(frame)
	return frame.IconFrame ~= nil and frame.journey ~= nil and frame.journey.kind == "guide"
end)[1]
check(fallback ~= nil, "the guide card stays with no provider mark")
check(
	fallback.journey.provider == "RestedXP" and fallback.journey.providerIcon == nil,
	"the card still names RestedXP when its mark is unavailable"
)
check(
	fallback.IconFrame.Icon.atlas == ns.Overview.KIND_ICONS.guide and fallback.IconFrame.Icon.file == nil,
	"no provider mark keeps the guide kind's own icon"
)
check(
	not fallback.Provider:IsShown() and fallback.Title:GetWidth() == 212,
	"no provider mark leaves no gap in the title's run"
)
check(fallback:GetHeight() == 86, "the fallback keeps the chosen card's height")

check(#h.errors == 0, "no errors\n" .. table.concat(h.errors, "\n"))
print(("guide_provider_spec: %d checks passed"):format(checks))
