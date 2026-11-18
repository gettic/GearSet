-- Gear Set: fixed gold costs of set pieces (beta.8, contract plans\v1.0.0\beta8-interface.md).
-- Facts only from bundled data (GoldData quest/piece gold, GuideData quest `gold|n` rows); vendor sources
-- from SourcesData. Bind on pickup from the game (C_Item.GetItemInfo bindType). Never reads auction prices,
-- never writes GearSetDB, never errors on bad input.
local _, ns = ...

local Gold = {}
ns.Gold = Gold

-- Texts (merged into ns.L when Core doesn't have them).
local TEXT = {
    GOLD_SET_LINE = "Gold still needed: %s",
    GOLD_SET_CANT = "Gold still needed: %s, %d |4piece:pieces; can't be bought",
    GOLD_ONLY_CANT = "%d |4piece:pieces; can't be bought (binds when picked up)",
    GOLD_PIECE_QUEST = "Costs %s (quest)",
    GOLD_PIECE_VENDOR = "Costs %s (vendor)",
    GOLD_VENDOR_UNKNOWN = "Sold by a vendor (open the vendor once to learn the price)",
    GOLD_PIECE_SEEN = "Price seen at a vendor: %s (%s)",
    GOLD_PIECE_SEEN_X = "Price seen at a vendor: %s + %s (%s)",
    GOLD_CANT_BUY = "Can't be bought (binds when picked up)",
}
ns.L = ns.L or {}
for k, v in pairs(TEXT) do
    if ns.L[k] == nil then ns.L[k] = v end
end
local L = ns.L

local COPPER_PER_GOLD = 10000
local BIND_ON_PICKUP = (type(Enum) == "table" and type(Enum.ItemBind) == "table" and Enum.ItemBind.OnAcquire) or 1

local function Num(v) return type(v) == "number" and v == v and v or nil end

-- ---------------------------------------------------------------------------
-- Sources of one item: quest names and whether a vendor sells it (SourcesData, cached).
local srcCache = {}
local NONE = {}

local function Sources(itemID)
    local hit = srcCache[itemID]
    if hit then return hit end
    local raw = type(ns.SourcesData) == "table" and ns.SourcesData[itemID]
    local out = NONE
    if type(raw) == "string" then
        out = { quests = {} }
        for part in raw:gmatch("[^;]+") do
            local kind, a = part:match("^(%a)|([^|]*)")
            if kind == "q" and a and a ~= "" then
                local seen = false
                for _, q in ipairs(out.quests) do if q == a then seen = true end end
                if not seen then out.quests[#out.quests + 1] = a end
            elseif kind == "v" then
                out.vendor = true
            end
        end
    end
    srcCache[itemID] = out
    return out
end

-- Whole gold a quest asks for: GoldData first, else GuideData's quest record (`gold|n` rows, any faction).
local questGold = {}
local function QuestGold(name)
    local hit = questGold[name]
    if hit ~= nil then return hit or nil end
    local g = type(ns.GoldData) == "table" and type(ns.GoldData.quest) == "table" and Num(ns.GoldData.quest[name])
    if not g then
        local gd = type(ns.GuideData) == "table" and type(ns.GuideData.quest) == "table" and ns.GuideData.quest[name]
        if type(gd) == "string" then
            for n in gd:gmatch("gold|(%d+)") do g = (g or 0) + tonumber(n) end
        end
    end
    questGold[name] = g or false
    return g
end

local function PieceGold(itemID)
    local p = type(ns.GoldData) == "table" and type(ns.GoldData.piece) == "table" and Num(ns.GoldData.piece[itemID])
    return p
end

-- ---------------------------------------------------------------------------
-- Bind type from the game: true = binds on pickup, false = not, nil = not loaded yet.
local bindCache = {}

local function AskLoad(itemID)
    local req = C_Item and C_Item.RequestLoadItemDataByID
    if req then pcall(req, itemID) end
end

local function IsBoP(itemID)
    local hit = bindCache[itemID]
    if hit ~= nil then return hit end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local ok, name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = pcall(get, itemID)
    if not ok or not name then
        AskLoad(itemID)
        return nil
    end
    if Num(bindType) == nil then return nil end
    local bop = bindType == BIND_ON_PICKUP
    bindCache[itemID] = bop
    return bop
end

function Gold.Clear()
    wipe(bindCache)
    wipe(srcCache)
    wipe(questGold)
end

-- ---------------------------------------------------------------------------
-- Public: one piece.
function Gold:PieceCost(itemID)
    itemID = Num(itemID)
    if not itemID then return nil, nil, nil end
    local src = Sources(itemID)
    local copper, how
    local g = PieceGold(itemID)
    if g then
        copper, how = g * COPPER_PER_GOLD, "vendor"
    else
        local sum
        for _, q in ipairs(src.quests or NONE) do
            local qg = QuestGold(q)
            if qg then sum = math.max(sum or 0, qg) end     -- other faction's same quest: not twice
        end
        if sum then copper, how = sum * COPPER_PER_GOLD, "quest"
        elseif src.vendor then how = "vendor" end
    end
    -- learned at a vendor (Prices.lua), after the bundled facts
    local extra
    if not copper and ns.Prices and ns.Prices.Get then
        local ok, c, x = pcall(ns.Prices.Get, itemID)
        if ok and (c or x) then copper, extra, how = c, x, "learned" end
    end
    return copper, IsBoP(itemID), how, extra
end

-- ---------------------------------------------------------------------------
-- Sets and who lacks what.
local function SetOf(setID)
    local D = ns.Data
    if type(setID) == "table" then return setID.pieces and setID or nil end
    local key
    if type(setID) == "number" then key = "c" .. setID
    elseif type(setID) == "string" then key = setID:match("^c%d+$") and setID or (tonumber(setID) and "c" .. setID) end
    if not (key and D and D.GetSet) then return nil end
    local ok, set = pcall(D.GetSet, D, key)
    return ok and type(set) == "table" and type(set.pieces) == "table" and set or nil
end

local function MyKey()
    local A = ns.Alts
    if A and A.MyKey then
        local ok, k = pcall(A.MyKey, A)
        if ok then return k end
    end
end

-- Lacks(piece, set, charKey, me) -> true when that character still needs the piece.
local function Lacks(piece, set, charKey, me)
    local A, O = ns.Alts, ns.Owned
    if charKey == nil or charKey == me then
        if O and O.IsHave then
            local ok, have = pcall(O.IsHave, O, piece)
            if ok then return not have end
        end
        return true
    end
    if A and A.GetHolders then
        local ok, holders = pcall(A.GetHolders, A, piece.itemID)
        if ok and type(holders) == "table" then
            for _, h in ipairs(holders) do
                if h.key == charKey or h.where == "account" then return false end
            end
        end
    end
    return true
end

local function Completed(set, charKey)
    local A = ns.Alts
    if not (A and A.IsCompleted and set.id) then return false end
    local ok, done = pcall(A.IsCompleted, A, set.id, charKey)
    return ok and done and true or false
end

function Gold:SetCost(setID, charKey)
    local info = { need = 0, priced = 0, unpriced = 0, loading = 0 }
    local set = SetOf(setID)
    if not set then return 0, 0, info end
    local me = MyKey()
    if charKey == me then charKey = nil end
    if Completed(set, charKey) then return 0, 0, info end
    local copper, cantBuy, quests = 0, 0, {}
    for _, piece in ipairs(set.pieces) do
        local id = type(piece) == "table" and Num(piece.itemID)
        if id and Lacks(piece, set, charKey, me) then
            info.need = info.need + 1
            local c, bop, how = self:PieceCost(id)
            if c then
                info.priced = info.priced + 1
                local counted = false
                if how == "quest" then
                    for _, q in ipairs(Sources(id).quests or NONE) do
                        if QuestGold(q) then
                            if quests[q] then counted = true else quests[q] = true end
                        end
                    end
                end
                if not counted then copper = copper + c end
            elseif bop == nil then
                info.loading = info.loading + 1
            elseif bop and how ~= "vendor" and how ~= "learned" then
                cantBuy = cantBuy + 1
            else
                info.unpriced = info.unpriced + 1
            end
        end
    end
    return copper, cantBuy, info
end

-- ---------------------------------------------------------------------------
-- Text helpers.
function Gold.Money(copper)
    copper = Num(copper)
    if not copper or copper <= 0 then return nil end
    if GetMoneyString then
        local ok, s = pcall(GetMoneyString, copper)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if c > 0 then out[#out + 1] = c .. "c" end
    return table.concat(out, " ")
end

function Gold:SetCostText(setID, charKey)
    local copper, cantBuy = self:SetCost(setID, charKey)
    local money = Gold.Money(copper)
    if money and cantBuy > 0 then return L.GOLD_SET_CANT:format(money, cantBuy) end
    if money then return L.GOLD_SET_LINE:format(money) end
    if cantBuy > 0 then return L.GOLD_ONLY_CANT:format(cantBuy) end
    return nil
end

-- Date a learned price was seen ("2026-11-18"; "?" when unknown).
local function SeenDate(itemID)
    local P = ns.Prices
    local ok, _, _, t = false, nil, nil, nil
    if P and P.Get then ok, _, _, t = pcall(P.Get, itemID) end
    t = ok and Num(t)
    if not t or t <= 0 then return "?" end
    local A = ns.Alts
    if A and A.DateText then
        local okd, s = pcall(A.DateText, t)
        if okd and type(s) == "string" and s ~= "" then return s end
    end
    if date then
        local okd, s = pcall(date, "%Y-%m-%d", t)
        if okd and type(s) == "string" then return s end
    end
    return "?"
end

function Gold:PieceCostText(itemID)
    local copper, bop, how, extra = self:PieceCost(itemID)
    local money = Gold.Money(copper)
    if how == "learned" then
        local when = SeenDate(itemID)
        if money and extra then return L.GOLD_PIECE_SEEN_X:format(money, extra, when) end
        if money then return L.GOLD_PIECE_SEEN:format(money, when) end
        if extra then return L.GOLD_PIECE_SEEN:format(extra, when) end
    end
    if money then return (how == "vendor" and L.GOLD_PIECE_VENDOR or L.GOLD_PIECE_QUEST):format(money) end
    if how == "vendor" then return L.GOLD_VENDOR_UNKNOWN end
    if bop then return L.GOLD_CANT_BUY end
    return nil
end
