---@meta

-- SkillUp Forever's public API (SkillUpForever.API, version 1: cjber/skillup-forever API.lua and types/API.lua),
-- read only through Integrations.lua for the Adventure Guide window's Professions tab. Every table is SkillUp's own
-- cached copy, so nothing here writes to it. SkillUp Forever is optional; without it the tab says where the steps
-- come from.

---@alias AGFSUStepKind 'buy'|'craft'|'train'|'gather'
---@alias AGFSUReagentSource 'vendor'|'craft'|'gather'|'auction'

---@class AGFSUStep
---@field kind AGFSUStepKind
---@field text string a short line, "Craft 3 Toughened Leather Gloves"
---@field detail? string "142 to 145", "Name, Zone · fee"
---@field itemID? integer the reagent to get, or the craft's or trained recipe's product
---@field spellID? integer the recipe to craft or train
---@field count? number
---@field cost? number copper: a purchase or a training fee
---@field nav boolean Navigate can route to the vendor or trainer

---@class AGFSURecipe
---@field spellID integer
---@field itemID? integer
---@field name? string
---@field count number crafts planned
---@field fromRank number
---@field toRank number
---@field learned boolean
---@field color? 'orange'|'yellow'|'green'|'grey'
---@field trainAt? number the skill the route first uses it at, while it is still to train
---@field cost? number the training fee in copper, while it is still to train

---@class AGFSUReagent
---@field itemID integer
---@field need number for the whole route
---@field have number bags and bank
---@field source? AGFSUReagentSource

---@class AGFSUProfession
---@field name string
---@field skillLineID integer
---@field icon integer a file ID
---@field rank number
---@field maxRank number the current cap
---@field title? string the rank's name, "Journeyman"
---@field steps AGFSUStep[] at most 3, in order
---@field recipes AGFSURecipe[]
---@field reagents AGFSUReagent[]

---@class AGFSUAPI
---@field version integer 1
---@field Professions fun(): AGFSUProfession[] crafting professions only, the most actionable first; the same cached table until something changes
---@field Navigate fun(skillLineID: integer, stepIndex: integer): boolean a waypoint (Shortest Path, TomTom or the map pin) to the step's vendor or trainer
---@field OpenRecipes fun(skillLineID: integer): boolean opens the game's profession window

---@alias AGFSkillUpState "ready"|"missing"|"outdated"

---@class AGFIntegrations
---@field SkillUpState fun(): AGFSkillUpState "ready" with a v1 SkillUp Forever, "outdated" when it is loaded without one, else "missing"
---@field Professions fun(): AGFSUProfession[] SkillUp's professions, each checked for the fields the window draws; empty unless ready
---@field SkillUpNavigate fun(skillLineID: integer, stepIndex: integer): boolean SkillUp's waypoint to a step's vendor or trainer
---@field OpenRecipes fun(skillLineID: integer): boolean SkillUp opens the profession's window

---@type {API: table?}? read only through Integrations.lua, which checks it against AGFSUAPI
SkillUpForever = nil
