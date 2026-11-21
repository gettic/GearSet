-- Gear Set: crafting shopping list (1.1 beta.2, plans\v1.1.0\b2-plan.md; data contract
-- plans\v1.1.0\b2-interface.md). For the crafted pieces this character still needs from its
-- tracked sets / tracked pieces: the recipe state, and the mats added up with have (bags,
-- bank, own other characters: W8), still to get, where to get them and an auction price
-- (AHPrices.lua, read only: W6). Read-only except Alts' live recipe notes; nothing saved here.
local _, ns = ...

local Shopping = {}
ns.Shopping = Shopping

local EMPTY = {}

local function Has(s) return type(s) == "string" and s ~= "" end
local function Whole(n) return type(n) == "number" and n == math.floor(n) and n > 0 and n < 2 ^ 31 end
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function L(key, fallback)
    local v = ns.L and ns.L[key]
    if v == nil then return fallback end
    return v
end

-- English profession names in the data -> Blizzard skill line IDs (GetProfessionInfo 7th return).
Shopping.PROF_IDS = { Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202,
    Leatherworking = 165, Tailoring = 197, Mining = 186, Skinning = 393, Herbalism = 182,
    Jewelcrafting = 755, Cooking = 185, ["First Aid"] = 129, Fishing = 356 }

-- Rows of a record string -> list of field lists (Data.Rows: the shared parser).
local function Rows(raw, mine) return ns.Data.Rows(raw, mine) end

local function Guide(tname)
    local g = ns.GuideData
    local t = type(g) == "table" and g[tname]
    return type(t) == "table" and t or EMPTY
end

-- ---------------------------------------------------------------------------
-- Data

-- A mat's record: { id, gets = { {kind, a, b} } } or nil.
local matCache = {}
function Shopping.Mat(name)
    if not Has(name) then return nil end
    local hit = matCache[name]
    if hit ~= nil then return hit or nil end
    local raw = Guide("mats")[name]
    if type(raw) ~= "string" then matCache[name] = false; return nil end
    local m = { name = name, gets = {} }
    for _, f in ipairs(Rows(raw)) do
        if f[1] == "id" then
            local id = tonumber(f[2])
            if Whole(id) then m.id = id end
        elseif f[1] == "get" and Has(f[2]) then
            m.gets[#m.gets + 1] = { kind = f[2], a = f[3], b = f[4] }
        end
    end
    matCache[name] = m
    return m
end

-- Every mat item ID in the data (Alts counts only these).
local matIDs
function Shopping.MatIDs()
    if matIDs then return matIDs end
    local ids, seen = {}, {}
    for name in pairs(Guide("mats")) do
        local m = Shopping.Mat(name)
        if m and m.id and not seen[m.id] then seen[m.id] = true; ids[#ids + 1] = m.id end
    end
    table.sort(ids)
    matIDs = ids
    return ids
end

-- A crafted set piece: { itemID, prof, profID, skill, recipe, recipeItem, recipeSpell,
-- mats = { { name, n (nil = amount unknown) } } } or nil when it isn't crafted.
local craftCache = {}
function Shopping.Crafted(itemID)
    local hit = craftCache[itemID]
    if hit ~= nil then return hit or nil end
    local raw = Guide("item")[itemID]
    local c = { itemID = itemID, mats = {} }
    local D = ns.Data
    for _, e in ipairs((D and D.SourceEntries) and D.SourceEntries(itemID) or EMPTY) do
        if e.kind == "c" and not c.prof then
            c.prof = e.a
            c.skill = tonumber(e.b)
        end
    end
    for _, f in ipairs(Rows(raw)) do
        if f[1] == "mat" and Has(f[3]) then
            c.mats[#c.mats + 1] = { name = f[3], n = tonumber(f[2]) }
        elseif f[1] == "skill" and not c.skill then c.skill = tonumber(f[2])
        elseif f[1] == "recipe" and Has(f[2]) then c.recipe = f[2]
        elseif f[1] == "ritem" then c.recipeItem = Whole(tonumber(f[2])) and tonumber(f[2]) or nil
        elseif f[1] == "rspell" then c.recipeSpell = Whole(tonumber(f[2])) and tonumber(f[2]) or nil
        end
    end
    if not c.prof and #c.mats == 0 then craftCache[itemID] = false; return nil end
    c.profID = c.prof and Shopping.PROF_IDS[c.prof] or nil
    craftCache[itemID] = c
    return c
end

-- Every recipe spell in the data (Alts reads which of these are known).
local recipeSpells
function Shopping.RecipeSpells()
    if recipeSpells then return recipeSpells end
    local out = {}
    for itemID, raw in pairs(Guide("item")) do
        if type(raw) == "string" and raw:find("rspell|", 1, true) then
            local c = Shopping.Crafted(itemID)
            if c and c.recipeSpell then out[#out + 1] = c.recipeSpell end
        end
    end
    table.sort(out)
    recipeSpells = out
    return out
end

-- "skinning Devilsaurs, Un'Goro Crater" (first 2 ways, joined).
function Shopping.WhereText(m)
    if not m then return nil end
    local parts = {}
    for _, g in ipairs(m.gets) do
        if #parts >= 2 then break end
        local fmt = L("SHOP_GET_" .. g.kind, nil)
        local text
        if g.kind == "ah" then text = fmt or "auction house"
        elseif g.kind == "note" then text = g.a
        elseif fmt and Has(g.a) then
            local ok, s = pcall(string.format, fmt, g.a, g.b or "")
            text = ok and s:gsub(",%s*$", "") or nil
        end
        if Has(text) then parts[#parts + 1] = text end
    end
    return #parts > 0 and table.concat(parts, "; ") or nil
end

-- ---------------------------------------------------------------------------
-- Live state

-- Crafted pieces this character still needs from tracked sets / tracked pieces (decision Q1:
-- never the "started sets" fallback). -> list of crafted records, item order.
function Shopping.Wanted()
    local Tr, R = ns.Track, ns.Runs
    if not (Tr and Tr.Mine and R and R.Wanted) then return {} end
    if next(Tr.Mine()) == nil then return {} end
    local out = {}
    for itemID, w in pairs(R.Wanted()) do
        if not w.later then
            local c = Shopping.Crafted(itemID)
            if c then out[#out + 1] = c end
        end
    end
    table.sort(out, function(a, b) return a.itemID < b.itemID end)
    return out
end

-- One list's view of your characters (1.2 optimizer item 2): the character list read once, and each
-- character's Recipes / Professions / MatCounts once (pcall results kept as they came). Before, every
-- piece and every mat read them again (~1,100 IsSpellKnown calls per list).
local function Snapshot()
    local A = ns.Alts
    if not (A and A.Chars) then return nil end
    local snap = { memo = {} }
    snap.ok, snap.chars = pcall(A.Chars, A)
    function snap.Call(name, key)
        local m = snap.memo[name]
        if not m then m = {}; snap.memo[name] = m end
        local r = m[key]
        if not r then r = { pcall(A[name], A, key) }; m[key] = r end
        return r[1], r[2], r[3]
    end
    return snap
end
local function Chars(A, snap)
    if snap then return snap.ok, snap.chars end
    return pcall(A.Chars, A)
end
local function Per(A, snap, name, key)
    if snap then return snap.Call(name, key) end
    return pcall(A[name], A, key)
end

-- Have of a mat: total, { bags, bank, alts = { { name, n } } }. `snap` (optional): Snapshot().
function Shopping.Have(matID, snap)
    local out = { bags = 0, bank = 0, alts = {} }
    if not matID then return nil, out end
    local C = C_Item
    local GetCount = (C and C.GetItemCount) or _G.GetItemCount
    if type(GetCount) == "function" then
        local okB, bags = pcall(GetCount, matID)
        local okA, all = pcall(GetCount, matID, true)
        if okB and type(bags) == "number" and not Secret(bags) then out.bags = bags end
        if okA and type(all) == "number" and not Secret(all) then out.bank = math.max(0, all - out.bags) end
    end
    local total = out.bags + out.bank
    local A = ns.Alts
    if A and A.Chars and A.MatCounts then
        local ok, chars = Chars(A, snap)
        for _, ch in ipairs(ok and type(chars) == "table" and chars or EMPTY) do
            if type(ch) == "table" and not ch.me and ch.key then
                local okM, m = Per(A, snap, "MatCounts", ch.key)
                local c = okM and type(m) == "table" and m[matID]
                local n = c and ((c[1] or 0) + (c[2] or 0)) or 0
                if n > 0 then
                    out.alts[#out.alts + 1] = { name = tostring(ch.name or ch.key), n = n }
                    total = total + n
                end
            end
        end
    end
    return total, out
end

-- Recipe state of a crafted piece: "me" | <alt name> | "no" | "crafter" | "?". `snap`: as Have.
function Shopping.RecipeState(c, snap)
    local A = ns.Alts
    if not (A and A.Chars and A.Recipes) then return "?" end
    local okC, chars = Chars(A, snap)
    chars = okC and type(chars) == "table" and chars or EMPTY
    local sure, profSeen, hasProf = false, false, false
    for _, ch in ipairs(chars) do
        if type(ch) == "table" and ch.key then
            if c.recipeSpell then
                local ok, known, readable = Per(A, snap, "Recipes", ch.key)
                if ok and type(known) == "table" then
                    if known[c.recipeSpell] then return ch.me and "me" or tostring(ch.name or ch.key) end
                    if ch.me and readable then sure = true end
                end
            end
            if c.profID and A.Professions then
                local ok, prof, read = Per(A, snap, "Professions", ch.key)
                if ok and type(prof) == "table" then
                    if ch.me or read then profSeen = true end
                    if prof[c.profID] then hasProf = true end
                end
            end
        end
    end
    if c.profID and profSeen and not hasProf then return "crafter" end
    if c.recipeSpell and sure then return "no" end
    return "?"
end

-- ---------------------------------------------------------------------------
-- The list

-- Pure: crafted list + have / price lookups -> { pieces, mats, total, priced, unpriced,
-- unknownAmounts, source, age }. haveFn(id) -> total, breakdown; priceFn(id) -> copper, age, source.
function Shopping.Build(crafted, haveFn, priceFn, stateFn)
    local list = { pieces = {}, mats = {}, total = 0, priced = 0, unpriced = 0, unknownAmounts = 0 }
    local byName = {}
    for _, c in ipairs(crafted) do
        list.pieces[#list.pieces + 1] = { itemID = c.itemID, prof = c.prof, skill = c.skill, recipe = c.recipe,
            recipeItem = c.recipeItem, state = stateFn and stateFn(c) or "?" }
        for _, mt in ipairs(c.mats) do
            local row = byName[mt.name]
            if not row then
                local m = Shopping.Mat(mt.name)
                row = { name = mt.name, id = m and m.id, need = 0, unknown = 0, where = Shopping.WhereText(m) }
                byName[mt.name] = row
                list.mats[#list.mats + 1] = row
            end
            if mt.n then row.need = row.need + mt.n else row.unknown = row.unknown + 1; list.unknownAmounts = list.unknownAmounts + 1 end
        end
    end
    local oldest, seenSrc = nil, {}
    list.sources = {}
    for _, row in ipairs(list.mats) do
        local have, parts = nil, nil
        if row.id and haveFn then have, parts = haveFn(row.id) end
        row.have, row.parts = have, parts
        row.left = have and math.max(0, row.need - have) or row.need
        if row.id and priceFn and row.left > 0 then
            local copper, age, source = priceFn(row.id)
            if type(copper) == "number" and copper > 0 and copper < math.huge then
                row.unit, row.age, row.source = copper, age, source
                list.total = list.total + copper * row.left
                list.priced = list.priced + 1
                list.source = list.source or source
                if source and not seenSrc[source] then seenSrc[source] = true; list.sources[#list.sources + 1] = source end
                if age and (not oldest or age > oldest) then oldest = age end
            else
                list.unpriced = list.unpriced + 1
            end
        end
    end
    list.age = oldest
    table.sort(list.mats, function(a, b)
        if (a.left > 0) ~= (b.left > 0) then return a.left > 0 end
        return a.name < b.name
    end)
    return list
end

-- The list for this character (nil when there is nothing to craft).
function Shopping:List()
    local crafted = Shopping.Wanted()
    if #crafted == 0 then return nil end
    local P = ns.AHPrices
    local priceFn = P and P.Get and function(id) return P.Get(id) end or nil
    local snap = Snapshot()
    return Shopping.Build(crafted, function(id) return Shopping.Have(id, snap) end, priceFn,
        function(c) return Shopping.RecipeState(c, snap) end)
end

-- Rounded for the list: no copper at 1g or more; a total (isTotal) no silver at 100g or more.
function Shopping.RoundPrice(copper, isTotal)
    if type(copper) ~= "number" then return copper end
    if isTotal and copper >= 1000000 then return copper - copper % 10000 end
    if copper >= 10000 then return copper - copper % 100 end
    return copper
end

-- Text of a price age in days.
function Shopping.AgeText(age)
    if age == nil then return nil end
    if age < 1 then return L("PRICE_TODAY", "today") end
    if age < 2 then return L("PRICE_DAY", "1 day old") end
    return L("PRICE_DAYS", "%d days old"):format(math.floor(age))
end

function Shopping.StateText(state)
    if state == "me" then return L("SHOP_KNOWN", "known"), "shopDone" end
    if state == "no" then return L("SHOP_NOT_KNOWN", "not known"), "shopMissing" end
    if state == "crafter" then return L("SHOP_CRAFTER", "needs a crafter"), "shopWhere" end
    if state == "?" then return L("SHOP_UNKNOWN", "?"), "shopWhere" end
    return L("SHOP_KNOWN_BY", "known by %s"):format(state), "shopDone"
end

-- Tests: drop the parse caches.
function Shopping._Reset()
    wipe(matCache); wipe(craftCache)
    matIDs, recipeSpells = nil, nil
end

-- ---------------------------------------------------------------------------
-- The profession window says which recipes are learned (only while it is open).
local events = CreateFrame("Frame")
local function ReadWindow()
    local T = _G.C_TradeSkillUI
    if not (T and type(T.GetRecipeInfo) == "function") then return end
    local A = ns.Alts
    if not (A and A.NoteRecipe) then return end
    for _, id in ipairs(Shopping.RecipeSpells()) do
        local ok, info = pcall(T.GetRecipeInfo, id)
        if ok and type(info) == "table" and type(info.learned) == "boolean" and not Secret(info.learned) then
            A.NoteRecipe(id, info.learned)
        end
    end
end
events:SetScript("OnEvent", function(self, event)
    if event == "TRADE_SKILL_SHOW" then
        if ns.SafeRegister then ns.SafeRegister(self, "TRADE_SKILL_LIST_UPDATE") end
        ReadWindow()
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        ReadWindow()
    elseif event == "TRADE_SKILL_CLOSE" then
        pcall(self.UnregisterEvent, self, "TRADE_SKILL_LIST_UPDATE")
    end
end)
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE" }) do
    if ns.SafeRegister then ns.SafeRegister(events, e) else pcall(events.RegisterEvent, events, e) end
end
Shopping.events = events
