-- Gear Set: reputation and quest-chain progress (1.1 beta.6; plans\v1.1.0\b6-plan.md, data contract
-- plans\v1.1.0\b6-interface.md). Live values for the guide page's rep / step / bring rows and the
-- Plan tab's "Reputation and chains" section; a per-character snapshot for your other characters.
-- ToS (plans\v1.1.0\tos-b6.md): S1 read-only (GetFactionDataByID, IsQuestFlaggedCompleted,
-- GetItemCount; never a setter, never a quest / gossip call); S3 the snapshot is your own character
-- only, our faction and chain quest IDs only; S4 events debounced 1 s, redraw only what is shown;
-- S5 nothing in chat; S6 every read pcall + issecretvalue guarded.
local _, ns = ...

local Steps = {}
ns.Steps = Steps

local function Has(s) return type(s) == "string" and s ~= "" end
local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function T(key, fallback) return (ns.L and ns.L[key]) or fallback end

-- Faction names as written in GuideData `rep|` rows and `token` keys -> faction IDs (contract sec. 1).
-- 529 confirmed by the probe; the others are checked by the self-test name match and the probe row.
Steps.FACTIONS = {
    ["Zandalar Tribe"] = 270,
    ["Cenarion Circle"] = 609,
    ["Brood of Nozdormu"] = 910,
    ["Argent Dawn"] = 529,
    ["The League of Arathor"] = 509,   -- the game's own name (in-game selftest beta.6)
    ["The Defilers"] = 510,
}
Steps.STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
Steps.DEBOUNCE = 1   -- seconds (S4)

local function Secret(v)
    local f = _G.issecretvalue
    return type(f) == "function" and f(v) and true or false
end

local function Num(v)
    if Secret(v) then return nil end
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function Whole(v, lo, hi)
    v = Num(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

function Steps.FactionID(name)
    if not Has(name) then return nil end
    -- data rows may write the name with or without a leading "The " ("League of Arathor")
    local t = Trim(name)
    return Steps.FACTIONS[t] or Steps.FACTIONS["The " .. t] or Steps.FACTIONS[(t:gsub("^The%s+", ""))]
end

-- The name to show: the game's own when it was read, else the data's.
function Steps.DisplayName(rep, fallback)
    if rep and rep.met and Has(rep.name) then return rep.name end
    return fallback
end

-- "Honored" -> 6 (any case); nil for unknown words.
function Steps.StandingIndex(word)
    if not Has(word) then return nil end
    local w = Trim(word):lower()
    for i, s in ipairs(Steps.STANDINGS) do if s:lower() == w then return i end end
    return nil
end

-- The game's own standing word (FACTION_STANDING_LABELn), else ours.
function Steps.StandingName(i)
    local g = _G["FACTION_STANDING_LABEL" .. tostring(i)]
    if not Secret(g) and type(g) == "string" and g ~= "" then return g end   -- S6: the guard first
    return T("STANDING_" .. tostring(i), Steps.STANDINGS[i] or "?")
end

-- ---------------------------------------------------------------------------
-- Reputation (S1, S6).

-- { id, name, reaction (1-8), value, min, max, met } or nil (API missing, secret or broken).
-- A faction the character never met (no name): Neutral 0/3000, met = false.
function Steps.Rep(factionID)
    local C = _G.C_Reputation
    local get = type(C) == "table" and C.GetFactionDataByID
    if type(get) ~= "function" then return nil end
    local ok, d = pcall(get, factionID)
    if not ok then return nil end
    if d == nil then return { id = factionID, reaction = 4, value = 0, min = 0, max = 3000, met = false } end
    if type(d) ~= "table" or Secret(d) then return nil end
    local name = d.name
    if Secret(name) then return nil end
    if not Has(name) then return { id = factionID, reaction = 4, value = 0, min = 0, max = 3000, met = false } end
    local r = Whole(d.reaction, 1, 8)
    local v, lo, hi = Num(d.currentStanding), Num(d.currentReactionThreshold), Num(d.nextReactionThreshold)
    if not (r and v and lo and hi) then return nil end
    return { id = factionID, name = name, reaction = r, value = v, min = lo, max = hi, met = true }
end

function Steps.HasStanding(rep, need)
    local n = Steps.StandingIndex(need)
    return rep ~= nil and n ~= nil and rep.reaction >= n
end

-- Bar fill 0..1 (Exalted / no span: full).
function Steps.Fraction(rep)
    if not rep then return 0 end
    local span = rep.max - rep.min
    if span <= 0 or rep.reaction >= #Steps.STANDINGS then return 1 end
    return math.max(0, math.min(1, (rep.value - rep.min) / span))
end

-- "Friendly 1200/6000" (or "Exalted", "not met yet").
function Steps.StandingText(rep)
    if not rep then return T("REP_UNKNOWN", "not known") end
    if not rep.met then return T("REP_NOT_MET", "not met yet") end
    local name = Steps.StandingName(rep.reaction)
    local span = rep.max - rep.min
    -- b6-pretest finding 4: Exalted is the cap, its 999/999 span says nothing
    if span <= 0 or rep.reaction >= #Steps.STANDINGS then return name end
    return ("%s %d/%d"):format(name, math.floor(rep.value - rep.min), math.floor(span))
end

-- "Friendly 1200/6000 - need Honored" / "Honored (ready)".
function Steps.RepText(rep, need)
    local base = Steps.StandingText(rep)
    local n = Steps.StandingIndex(need)
    if not (rep and n) then return base end
    if rep.reaction >= n then return T("REP_READY", "%s (ready)"):format(base) end
    return T("REP_NEED", "%s - need %s"):format(base, Steps.StandingName(n))
end

-- Blizzard's faction bar colour (FACTION_BAR_COLORS via _G), else ours.
function Steps.BarColor(rep, ready)
    local t = _G.FACTION_BAR_COLORS
    local c = rep and type(t) == "table" and t[rep.reaction]
    if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
    local th = ns.Theme and ns.Theme.colors
    local col = th and th[ready and "repReady" or "repNeed"]
    if col then return col:GetRGB() end
    return 1, 0.5, 0.25
end

-- ---------------------------------------------------------------------------
-- Quests and items.

-- true / false, nil when the API is missing or the answer is secret.
function Steps.QuestDone(questID)
    local Q = _G.C_QuestLog
    local f = type(Q) == "table" and Q.IsQuestFlaggedCompleted
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, questID)
    if not ok or Secret(v) then return nil end
    return v and true or false
end

local function Count(itemID, bank)
    local C = _G.C_Item
    local f = (type(C) == "table" and C.GetItemCount) or _G.GetItemCount
    if type(f) ~= "function" then return 0 end
    local ok, n = pcall(f, itemID, bank)
    return ok and Num(n) or 0
end
Steps.Count = Count

-- Owned anywhere this character can see (bags, bank, keyring, equipped).
function Steps.Owns(itemID)
    if Count(itemID, true) > 0 then return true end
    local R = ns.Runs
    if R and R.ItemPlace then
        local ok, where = pcall(R.ItemPlace, itemID)
        if ok and where then return true end
    end
    local eq = _G.IsEquippedItem
    if type(eq) == "function" then
        local ok, v = pcall(eq, itemID)
        if ok and not Secret(v) and v then return true end   -- S6: the guard before the truth test
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Records (Data.Rows: every field kept; rows of the other faction dropped), cached.

local rowCache = {}
local function Rows(tname, key, mine)
    if key == nil then return nil end
    local g = ns.GuideData
    local t = type(g) == "table" and g[tname]
    local raw = type(t) == "table" and t[key]
    if type(raw) ~= "string" then return nil end
    local ck = tname .. "\31" .. tostring(key) .. "\31" .. (mine or "")
    local hit = rowCache[ck]
    if hit then return hit end
    local out = ns.Data.Rows(raw, mine)
    rowCache[ck] = out
    return out
end
Steps.Rows = Rows

local function Mine()
    local D = ns.Data
    return D and D.PlayerFaction and D.PlayerFaction() or nil
end

-- Chain record -> { title, steps = { { label, name, where, qids = {}, items = {} } } }.
function Steps.Chain(key, mine)
    local rows = Rows("chain", key, mine)
    if not rows then return nil end
    local c = { key = key, steps = {} }
    for _, f in ipairs(rows) do
        if f[1] == "t" and Has(f[2]) then c.title = c.title or f[2]
        elseif f[1] == "s" and (Has(f[2]) or Has(f[3])) then
            c.steps[#c.steps + 1] = { label = f[2] or "", name = Has(f[3]) and f[3] or (f[4] or ""), where = Has(f[3]) and f[4] or nil,
                qids = {}, items = {} }
        end
    end
    for _, f in ipairs(rows) do
        local n = Whole(f[2], 1, #c.steps)
        local list = n and ((f[1] == "sq" and c.steps[n].qids) or (f[1] == "si" and c.steps[n].items))
        if list then
            for i = 3, #f do
                local id = Whole(f[i], 1, 2 ^ 31 - 1)
                if id then list[#list + 1] = id end
            end
        end
    end
    return c
end

-- Short display title: the chain title without its "(...)" part ("Seal of Ascension").
function Steps.ShortTitle(title)
    if not Has(title) then return "" end
    return Trim((title:gsub("%s*%b()", ""))) ~= "" and Trim((title:gsub("%s*%b()", ""))) or title
end

-- Progress of a chain: { key, title, total, done, next (index|nil), known, complete, steps = { {..., state} } }.
-- state: true done / false not done / nil unknown (no ID: never a guess, R6). A later step done ->
-- every earlier step done. questDone / owns: optional (alts: their saved quest set, no items).
function Steps.ChainState(key, mine, questDone, owns)
    local c = Steps.Chain(key, mine or Mine())
    if not c then return nil end
    questDone = questDone or Steps.QuestDone
    owns = owns or Steps.Owns
    local known, last = false, 0
    for i, s in ipairs(c.steps) do
        local state
        if #s.qids > 0 or #s.items > 0 then
            known = true
            state = false
            for _, q in ipairs(s.qids) do if questDone(q) then state = true; break end end
            if not state then for _, id in ipairs(s.items) do if owns(id) then state = true; break end end end
        end
        s.state = state
        if state then last = i end
    end
    local done = 0
    for i, s in ipairs(c.steps) do
        if i <= last then s.state = true end
        if s.state then done = done + 1 end
    end
    local nxt
    for i, s in ipairs(c.steps) do if not s.state then nxt = i; break end end
    c.total, c.done, c.next, c.known = #c.steps, done, nxt, known
    c.complete = known and #c.steps > 0 and last == #c.steps
    return c
end

-- "step 7 of 16" / "done" / "" (no IDs).
function Steps.ChainText(st)
    if not (st and st.known) then return "" end
    if st.complete then return T("CHAIN_DONE", "done") end
    return T("CHAIN_STEP", "step %d of %d"):format(math.min(st.done + 1, st.total), st.total)
end

-- Every chain quest ID in the data (the snapshot's quest list).
function Steps.AllChainQuests()
    local g = ns.GuideData
    local out, seen = {}, {}
    for key in pairs(type(g) == "table" and type(g.chain) == "table" and g.chain or {}) do
        local c = Steps.Chain(key, nil)
        for _, s in ipairs(c and c.steps or {}) do
            for _, q in ipairs(s.qids) do if not seen[q] then seen[q] = true; out[#out + 1] = q end end
        end
    end
    table.sort(out)
    return out
end

-- ---------------------------------------------------------------------------
-- Turn-in tokens (counts only, R3): GuideData `token[faction]` (contract sec. 4).

function Steps.Tokens(faction)
    local rows = Rows("token", faction, nil)
    if not rows then return nil end
    local items, groups = {}, {}
    for _, f in ipairs(rows) do
        if f[1] == "item" then
            local id = Whole(f[2], 1, 2 ^ 31 - 1)
            if id then items[#items + 1] = { id = id, name = Has(f[3]) and f[3] or ("item " .. id), group = Has(f[4]) and f[4] or nil } end
        elseif f[1] == "group" and Has(f[2]) then
            groups[f[2]] = { size = Whole(f[3], 1, 99) or 1, label = Has(f[4]) and f[4] or f[2] }
        end
    end
    return items, groups
end

-- How many full sets of `size` different items: greedy, always from the largest counts.
function Steps.FullSets(counts, size)
    local c = {}
    for _, n in ipairs(counts) do if n > 0 then c[#c + 1] = n end end
    local sets = 0
    while #c >= size do
        table.sort(c, function(a, b) return a > b end)
        for i = 1, size do c[i] = c[i] - 1 end
        local keep = {}
        for _, n in ipairs(c) do if n > 0 then keep[#keep + 1] = n end end
        c = keep
        sets = sets + 1
    end
    return sets
end

-- "6 coins (2 sets), 1 Zandalar Honor Token" from the bags, or nil (none / no data).
function Steps.TokenText(faction, count)
    local items, groups = Steps.Tokens(faction)
    if not items then return nil end
    count = count or function(id) return Count(id, false) end
    -- b6-pretest finding 2: ZG coins turn in as fixed trios, so the data has one group per trio
    -- (coin1 / coin2 / coin3) with the same label; the sets of every group are added up per label.
    local parts, byGroup, byLabel, labels = {}, {}, {}, {}
    for _, it in ipairs(items) do
        local n = count(it.id) or 0
        if n > 0 then
            if it.group and groups[it.group] then
                local g = byGroup[it.group]
                if not g then g = { counts = {} }; byGroup[it.group] = g end
                g.counts[#g.counts + 1] = n
                local label = groups[it.group].label
                local l = byLabel[label]
                if not l then l = { total = 0, sets = 0, sized = false }; byLabel[label] = l; labels[#labels + 1] = label end
                l.total = l.total + n
            else
                parts[#parts + 1] = ("%d %s"):format(n, it.name)
            end
        end
    end
    for key, g in pairs(byGroup) do
        local def = groups[key]
        if def.size > 1 then
            local l = byLabel[def.label]
            l.sized = true
            l.sets = l.sets + Steps.FullSets(g.counts, def.size)
        end
    end
    for i = #labels, 1, -1 do
        local l = byLabel[labels[i]]
        local s = ("%d %s"):format(l.total, labels[i])
        -- finding 3: no "(0 sets)"
        if l.sized and l.sets > 0 then
            s = s .. " " .. (l.sets == 1 and T("TOKEN_SET_ONE", "(1 set)") or T("TOKEN_SETS", "(%d sets)"):format(l.sets))
        end
        table.insert(parts, 1, s)
    end
    if #parts == 0 then return nil end
    return T("TOKEN_LINE", "Turn-ins in bags: %s"):format(table.concat(parts, ", "))
end

-- ---------------------------------------------------------------------------
-- Your characters (R2, S3: own characters only, our IDs only).

-- This character's values: { rep = { [id] = { r, v, t } }, quests = { [qid] = true } } or nil.
function Steps.Snapshot(now)
    now = now or time()
    local rep, quests, any = {}, {}, false
    for _, id in pairs(Steps.FACTIONS) do
        local r = Steps.Rep(id)
        if r and r.met then rep[id] = { r = r.reaction, v = math.floor(r.value), t = now }; any = true end
    end
    local canQuest = false
    for _, q in ipairs(Steps.AllChainQuests()) do
        local d = Steps.QuestDone(q)
        if d ~= nil then canQuest = true end
        if d then quests[q] = true end
    end
    if not any and not canQuest then return nil end
    return { rep = any and rep or nil, quests = canQuest and quests or nil }
end

local function OtherChars()
    local db, A = ns.db, ns.Alts
    local chars = type(db) == "table" and type(db.chars) == "table" and db.chars or {}
    local me = A and A.MyKey and A:MyKey()
    local out = {}
    for key, rec in pairs(chars) do
        if key ~= me and type(rec) == "table" then
            local name = (type(rec.name) == "string" and rec.name ~= "") and rec.name or tostring(key):match("^([^%-]+)") or tostring(key)
            out[#out + 1] = { key = key, name = name, rec = rec }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Your other characters' saved standing: { { name, reaction, value, t } } (bad rows skipped).
function Steps.AltRep(factionID)
    local out = {}
    for _, c in ipairs(OtherChars()) do
        local t = type(c.rec.rep) == "table" and c.rec.rep[factionID]
        local r = type(t) == "table" and Whole(t.r, 1, 8)
        if r then out[#out + 1] = { name = c.name, reaction = r, value = Num(t.v), t = Num(t.t) } end
    end
    table.sort(out, function(a, b) return a.reaction > b.reaction end)
    return out
end

-- "Stabby: Honored (2 days ago)".
function Steps.AltRepText(a)
    local when = (ns.Alts and ns.Alts.SeenText and a.t) and ns.Alts.SeenText(a.t) or nil
    local s = ("%s: %s"):format(a.name, Steps.StandingName(a.reaction))
    return when and (s .. " (" .. when .. ")") or s
end

-- Your other characters' progress in a chain: { { name, text } } (from their saved quest flags).
function Steps.AltChains(key, mine)
    local out = {}
    for _, c in ipairs(OtherChars()) do
        local q = c.rec.quests
        if type(q) == "table" then
            local st = Steps.ChainState(key, mine, function(id) return q[id] == true end, function() return false end)
            if st and st.known and st.done > 0 then out[#out + 1] = { name = c.name, text = Steps.ChainText(st) } end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The Plan tab: factions and chains for the wanted pieces and the listed runs.

-- Rep rows of a piece: { { faction, need } } from its quest records and its own item record, and the
-- names of its own-faction quest sources. Static data: cached per item and faction (1.2 optimizer
-- item 4; only these two short lists are kept, a piece with neither shares NONE). Read only.
local NONE = {}
local NO_REPS = { NONE, NONE }
local repCache = {}
function Steps.PieceReps(itemID, mine)
    local ck = tostring(itemID) .. (mine or "")
    local hit = repCache[ck]
    if hit then return hit[1], hit[2] end
    local D = ns.Data
    local out, quests = {}, {}
    local function From(rows)
        for _, f in ipairs(rows or NONE) do
            if f[1] == "rep" and Has(f[2]) then out[#out + 1] = { faction = f[2], need = f[3] } end
        end
    end
    local entries = (D and D.SourceEntries) and D.SourceEntries(itemID) or NONE
    for _, e in ipairs(entries) do
        if (not e.fac or not mine or e.fac == mine) and e.kind == "q" and Has(e.a) then
            quests[#quests + 1] = e.a
            From(Rows("quest", e.a, mine))
        end
    end
    From(Rows("item", itemID, mine))
    if #out == 0 then out = NONE end
    if #quests == 0 then quests = NONE end
    repCache[ck] = (out == NONE and quests == NONE) and NO_REPS or { out, quests }
    return out, quests
end

local function AddChain(chains, key, mine, why)
    if not Has(key) or chains[key] then return end
    local st = Steps.ChainState(key, mine)
    if st and #st.steps > 0 then
        st.why = why
        chains[key] = st
    end
end

-- -> { reps = { { faction, id, rep, need, missing, pieces, later } }, chains = { ChainState + why } }.
-- reps sorted: needed first (then name), ready last; chains: open first, done last.
function Steps.ForPlan(wanted, runs, mine)
    mine = mine or Mine()
    local byFaction, chains = {}, {}
    for itemID, w in pairs(wanted or {}) do
        local reps, quests = Steps.PieceReps(itemID, mine)
        for _, r in ipairs(reps) do
            local f = byFaction[r.faction]
            if not f then f = { faction = r.faction, pieces = {}, later = true }; byFaction[r.faction] = f end
            f.pieces[#f.pieces + 1] = { itemID = itemID, need = r.need, later = w.later }
            if not w.later then f.later = false end
        end
        for _, q in ipairs(quests) do
            for _, f in ipairs(Rows("quest", q, mine) or NONE) do
                if f[1] == "chain" then AddChain(chains, f[2], mine, q) end
            end
        end
    end
    -- attunement / key chains of the runs on the tab
    for _, e in ipairs(runs or {}) do
        for _, f in ipairs(Rows("place", e.run, mine) or {}) do
            if f[1] == "att" and Has(f[3]) then AddChain(chains, f[3], mine, e.run) end
        end
    end
    local reps = {}
    for name, f in pairs(byFaction) do
        f.id = Steps.FactionID(name)
        f.rep = f.id and Steps.Rep(f.id) or nil
        local cur = f.rep and f.rep.reaction or 0
        local goal, missing = nil, 0
        for _, p in ipairs(f.pieces) do
            local n = Steps.StandingIndex(p.need)
            if n and n > cur then
                missing = missing + 1
                if not goal or n < goal then goal = n end
            end
        end
        f.goal, f.missing = goal, missing
        f.ready = f.rep ~= nil and missing == 0
        reps[#reps + 1] = f
    end
    table.sort(reps, function(a, b)
        if a.later ~= b.later then return not a.later end
        if a.ready ~= b.ready then return not a.ready end
        return a.faction < b.faction
    end)
    local list = {}
    for _, st in pairs(chains) do list[#list + 1] = st end
    table.sort(list, function(a, b)
        if (a.complete or false) ~= (b.complete or false) then return not a.complete end
        return (a.title or a.key) < (b.title or b.key)
    end)
    return { reps = reps, chains = list }
end

-- "need Honored for 3 pieces" / "ready" / "not out yet".
function Steps.NeedText(f)
    if f.later then return T("REP_LATER", "not out yet") end
    if f.ready then return T("REP_ALL_READY", "ready") end
    if not f.goal then return "" end
    local name = Steps.StandingName(f.goal)
    if f.missing == 1 then return T("REP_NEED_ONE", "need %s for 1 piece"):format(name) end
    return T("REP_NEED_N", "need %s for %d pieces"):format(name, f.missing)
end

-- ---------------------------------------------------------------------------
-- Events (S4): one refresh per second at most, and only of what is shown.

Steps.changes = 0   -- refreshes run (tests)
local pending = false
local function Flush()
    pending = false
    Steps.changes = Steps.changes + 1
    if Steps.OnChange then pcall(Steps.OnChange) end
    local P, G = ns.Plan, ns.GuidePage
    if P and P.page and P.page:IsVisible() then pcall(P.Queue or P.Refresh, P) end
    if G and G.page and G.page:IsVisible() and G.Render then pcall(G.Render, G) end
end

function Steps.Changed()
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(Steps.DEBOUNCE, Flush) else Flush() end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() Steps.Changed() end)
for _, e in ipairs({ "UPDATE_FACTION", "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED" }) do
    if ns.SafeRegister then ns.SafeRegister(events, e) else pcall(events.RegisterEvent, events, e) end
end

function Steps._Reset()
    wipe(rowCache)
    wipe(repCache)
    pending = false
    Steps.changes = 0
end
