# Slice A interfaces — frozen 2026-09-25

All functions use dot calls. Existing interfaces remain available. New tables are detached snapshots unless noted.

## Providers.lua

- `ns.Providers.LegacyState() -> "ready"|"missing"|"outdated"`
- `ns.Providers.Completion() -> {state: string, zones: AGFCompletionZone[]}`; current map first, then chosen/next outdoor journey maps, deduplicated, at most four.
- `AGFCompletionZone = {map: integer, name: string, summary?: LFZoneSummary, targets: LFTarget[], error?: string}`. Summary/target shapes are exactly Legacy API v1 in the plan: category `key, scope, done, total, pending, complete`; zone additionally `questsStatus`; target `key, text, kind, achievementID, criteriaID, quantity?, required?, place?: {map,x,y}`. Pending is never counted as complete. No eligible-quest inference.
- `ns.Providers.NavigateCompletion(map: integer, key: string) -> boolean, string?` revalidates through Legacy.
- `ns.Providers.SetShown(shown: boolean)` subscribes only while the window is shown.
- `ns.Providers.OnChange(callback: fun())` registers refresh listener.
- `ns.Providers.DungeonEntrance(instanceID: integer) -> AGFPoint?, "missing"|"outdated"|"unknown"?` (`AGFPoint = {map: integer,x: number,y: number}`). Instance uses Map.ID, not UiMapID.
- `ns.Providers.GoToEntrance(instanceID: integer) -> boolean, string?` explicit entrance action; does not change quest suitability/pickup route.

## PvP.lua

- `ns.PvP.Data() -> {rank: AGFPvPRank, battlegrounds: AGFPvPBattle[], available: boolean}`.
- `AGFPvPRank = {state: "unavailable"|"unranked"|"ranked"|"capped", level?: integer, earned?: number, threshold?: number, maxLevel?: integer, reward?: {level: integer,text: string,icon?: number}}`.
- `AGFPvPBattle = {id: integer,name: string,level: integer,npc?: integer,place?: AGFPlace}`. Every level-unlocked battleground remains, even without a battlemaster; place is the nearest same-faction/neutral known battlemaster.
- `ns.PvP.Go(id: integer) -> boolean` revalidates the unlocked battleground and its battlemaster.

## Session.lua

- `ns.Session.Get() -> integer` = 0 (No limit), 15, 30, 60.
- `ns.Session.Set(minutes: integer)` persists per character and resets the committed endpoint.
- `ns.Session.Info() -> {minutes: integer, seconds?: number, pending: boolean, empty: boolean, trimmed: boolean}`; seconds is heuristic travel + work; show `SESSION_ABOUT` using `math.ceil(seconds / 60)` only when present.
- `ns.Route().steps` and the chosen journey's `steps` already contain the session result. Render directly; no UI-side trimming. Journey selection survives empty sessions. Order changes do not refill the session; duration/journey changes do.

## Order.lua

- `ns.Order.CanMove(from: integer, to: integer) -> boolean` indexes the chosen route's visible steps; false for unchanged/out-of-range/dependency-breaking moves.
- `ns.Order.Move(from: integer, to: integer) -> boolean` persists the exact valid move and invalidates; no silent extra moves.
- `ns.Order.Reset()` clears the chosen journey's saved custom order and returns to suggested order.
- `ns.Order.IsCustom() -> boolean` for the chosen journey. Town steps are indivisible. Reset only shows while true.
- `ns.Order.SkipGiver(stepKey: string, giverKey: string) -> boolean` skips one remaining town checklist giver for this login; invalidates and retargets. Whole-step skip remains `ns.Skip`.

## Steps / town checklist

- Existing `step.kind` remains `town|turnin|area|dungeon|trainer|battlemaster`.
- Every model step has `step.verb = "pickup"|"turnin"|"objective"|"town"|"trainer"|"battlemaster"`; use this for icons (dungeon work uses objective icon). `step.title` is already action-led and SPF receives this title.
- `step.checklist?: AGFTownGiver[]`, only towns; each `{key: string,name: string,text: string,pickups: integer[],handins: integer[],done: boolean,skipped: boolean,place: AGFPlace}`. One row per giver, retained/ticked through the town visit. `step.map/x/y` targets nearest remaining giver; no invented point.
- `step.complete?: boolean` true only when every checklist giver is done/skipped. Completed towns leave the route. Giver text is preformatted; UI may use its done flag for a stock tick.
- `ns.Integrations.CurrentStep() -> AGFStep?` resolves the current owned SPF stop when active, otherwise the route head; tracker uses it too.

## Copy keys (all in Core.lua ns.L)

`TAB_PVP`, `TAB_COMPLETION`, `GO_TO_ENTRANCE`, `TWEAKS_MISSING`, `TWEAKS_OUTDATED`, `ENTRANCE_UNKNOWN`, `LEGACY_MISSING`, `LEGACY_OUTDATED`, `COMPLETION_EMPTY`, `COMPLETION_LOADING`, `COMPLETION_UNAVAILABLE`, `COMPLETION_COUNTS` (%d/%d), `COMPLETION_PENDING` (%d), `COMPLETION_ACCOUNT`, `COMPLETION_GO`, `COMPLETION_NO_LOCATION`, `COMPLETION_CATEGORY_AREAS`, `COMPLETION_CATEGORY_TAXIS`, `COMPLETION_CATEGORY_DUNGEONS`, `COMPLETION_CATEGORY_RAIDS`, `COMPLETION_CATEGORY_LEGACY`, `COMPLETION_CATEGORY_REPUTATIONS`, `COMPLETION_CATEGORY_QUESTS`.

`PVP_RANK` (%d), `PVP_RANK_POINTS` (%d/%d), `PVP_UNRANKED`, `PVP_CAPPED`, `PVP_UNAVAILABLE`, `PVP_NO_BATTLEGROUNDS`, `PVP_NO_BATTLEMASTER`, `PVP_BATTLEGROUND_LEVEL` (%d), `PVP_GO_BATTLEMASTER`, `PVP_NEXT_REWARD` (%d, %s).

`SESSION_LABEL`, `SESSION_UNLIMITED`, `SESSION_MINUTES` (%d), `SESSION_ABOUT` (%d), `SESSION_EMPTY`, `SESSION_PENDING`, `ORDER_SOONER`, `ORDER_LATER`, `ORDER_NEXT`, `ORDER_RESET`, `ORDER_CUSTOM`, `TOWN_SKIP_GIVER`, `TOWN_GIVER` (%s, %s), `TOWN_COUNTS` (%d, %d), `TOWN_PICKUPS` (%d), `TOWN_HANDINS` (%d), `TODAY_MORE` (%d), `STOP_VISIT` (%d, %s), `SET_HEARTH` (%s), `SETTING_STEP_SOUND`, `SETTING_STEP_SOUND_TOOLTIP`.

Harness additions: `legacy = {version?, summaries = {[map]=summary}, targets = {[map]=targets}, error?, navigateError?}`, `entrances = {[instanceID]={map,x,y}}`, `bind = string`; existing `rank` and `battlegrounds` options remain. Runtime fixtures are mutable via `h.G.LegacyForever.API`, `h.G.TweaksForever.API`, `h.player.bind`; `h.legacyChanged()` notifies provider subscribers.

A owns TOC/types/harness and will add WindowPvP.lua / WindowCompletion.lua once present. B must arrange packaging ignore for this development-only file (A does not own .pkgmeta).

CHANGE: 2026-09-25 — `step.orderKey: string` distinguishes repeat visits to the same town (`key` intentionally remains shared for whole-town skipping). A's order/session code persists this stable visit identity internally; B's index-based move APIs do not change. `SkipGiver` accepts existing step.key as frozen above.

CHANGE: 2026-09-25 — Clarification of the earlier identity note: existing `step.key` may already have a visit suffix (`town:5:2`). `orderKey` also survives that suffix changing when an earlier visit finishes, and survives a mixed pickup/hand-in visit becoming hand-in-only. The index-based move and `SkipGiver(step.key, giver.key)` interfaces are unchanged.
