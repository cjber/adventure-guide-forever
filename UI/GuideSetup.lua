---@type string, AGFNamespace
local _, ns = ...

---@class AGFGuideSetup
local Setup = {}
ns.GuideSetup = Setup
---@type Frame?
local popup
local dismissed = false

local function Choose(integrated)
	ns.SetSetting("restedxpGuide", integrated)
	if popup then
		popup:Hide()
	end
end

---@return Frame
local function Ensure()
	if popup then
		return popup
	end
	local frame = CreateFrame("Frame", "AdventureGuideForeverGuideSetup", UIParent)
	popup = frame
	frame:SetSize(454, 294)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	local background = frame:CreateTexture(nil, "BACKGROUND")
	-- art-ok: the client's menu background has native nine-slice margins, which resize with the popup.
	background:SetAtlas("common-dropdown-bg")
	background:SetAllPoints()
	local function Text(x, y, value, font)
		local text = frame:CreateFontString(nil, "OVERLAY", font)
		text:SetPoint("TOPLEFT", x, -y)
		text:SetWidth(410 - x)
		text:SetJustifyH("LEFT")
		text:SetText(value)
		return text
	end
	Text(22, 18, ns.L.RXP_SETUP_TITLE, "GameFontNormal")
	Text(22, 42, ns.L.RXP_SETUP_PROMPT, "GameFontHighlightSmall")
	local hasSPF = ns.Companions.State("ShortestPathForever") == "loaded"
	local function Row(y, height, title, lines, integrated)
		local row = CreateFrame("Button", nil, frame)
		row:SetPoint("TOPLEFT", 14, -y)
		row:SetSize(426, height)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.06)
		local radio = row:CreateTexture(nil, "ARTWORK")
		ns.Art.Fit(radio, "common-dropdown-tickradial", 16, 16)
		radio:SetPoint("TOPLEFT", 8, -10)
		Text(44, y + 10, title, "GameFontNormal")
		for index, line in ipairs(lines) do
			Text(44, y + 31 + (index - 1) * 15, line, "GameFontHighlightSmall")
		end
		row:SetScript("OnClick", function()
			Choose(integrated)
		end)
	end
	local lines = { ns.L.RXP_SETUP_AGF }
	if hasSPF then
		lines[#lines + 1] = ns.L.RXP_SETUP_SPF
	end
	lines[#lines + 1] = hasSPF and ns.L.RXP_SETUP_HIDDEN_SPF or ns.L.RXP_SETUP_HIDDEN
	Row(73, 75, ns.TITLE, lines, true)
	Row(155, 54, ns.L.RXP_SETUP_NATIVE_TITLE, { ns.L.RXP_SETUP_NATIVE }, false)
	if ns.Companions.State("SkillUpForever") == "loaded" then
		Text(44, 244, hasSPF and ns.L.RXP_SETUP_SKILLUP_SPF or ns.L.RXP_SETUP_SKILLUP, "GameFontHighlightSmall")
	end
	Text(44, 267, ns.L.RXP_SETUP_SETTINGS, "GameFontDisableSmall")
	frame:Hide()
	frame:SetScript("OnHide", function()
		if not ns.Setting("restedxpChoiceMade") and not dismissed and not InCombatLockdown() then
			Choose(false)
		end
	end)
	table.insert(UISpecialFrames, "AdventureGuideForeverGuideSetup")
	return frame
end

function Setup.Hide()
	if popup then
		popup:Hide()
	end
end

function Setup.Show()
	if dismissed or ns.Setting("restedxpChoiceMade") or InCombatLockdown() then
		return
	end
	Ensure():Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" and popup and popup:IsShown() then
		dismissed = true
		popup:Hide()
	elseif event == "PLAYER_REGEN_ENABLED" then
		dismissed = false
		ns.RestedXP.Refresh()
	end
end)
