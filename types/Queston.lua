---@meta

-- Queston Forever's published addon table (`_G.QuestonForever`, Core.lua). Only the world map page is read here:
-- whether it is open and its Show(showGuide).
---@class QuestonChronicleView
---@field open? boolean whether its page is shown
---@field Show fun(self: QuestonChronicleView, showGuide: boolean) shows its page or puts the map's own content back

---@class QuestonForeverAddon
---@field ChronicleView? QuestonChronicleView

---@type QuestonForeverAddon?
QuestonForever = nil
