-- Gear Set: which pieces you have or need.
-- States: equipped, bags, bank (you own it), look (appearance collected), need.
-- "look" counts as have (user's choice). Results are cached until something changes.
local _, ns = ...

local Owned = {}
ns.Owned = Owned

local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local stateCache, countCache, equipped = {}, {}, nil

-- beta.7: mail / keyring / account bank (Alts.lua) count as have too.
Owned.HAVE = { equipped = true, bags = true, bank = true, look = true, mail = true, keyring = true, account = true }

-- Mailbox / keyring / account bank, from Alts' last read (nil = not there or no Alts).
local function OtherPlace(id)
    local A = ns.Alts
    if not (A and A.MyPlace) then return nil end
    local ok, where = pcall(A.MyPlace, A, id)
    return ok and where or nil
end

local function EquippedSet()
    if equipped then return equipped end
    equipped = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then equipped[id] = true end
    end
    return equipped
end

local function LookCollected(piece)
    local TC = C_TransmogCollection
    local src = piece.sourceID
    if not TC or not src then return false end
    if TC.PlayerHasTransmogItemModifiedAppearance then
        local ok, has = pcall(TC.PlayerHasTransmogItemModifiedAppearance, src)
        if ok and has then return true end
    end
    if TC.GetAppearanceInfoBySource then
        local ok, info = pcall(TC.GetAppearanceInfoBySource, src)
        if ok and type(info) == "table" and info.appearanceIsCollected then return true end
    end
    return false
end

function Owned:GetState(piece)
    local id = piece.itemID
    local s = stateCache[id]
    if s then return s end
    if EquippedSet()[id] then
        s = "equipped"
    else
        local bags = GetItemCount(id) or 0
        if bags > 0 then
            s = "bags"
        elseif (GetItemCount(id, true) or 0) > bags then
            s = "bank"
        elseif OtherPlace(id) then
            s = OtherPlace(id)
        elseif LookCollected(piece) then
            s = "look"
        else
            s = "need"
        end
    end
    stateCache[id] = s
    return s
end

function Owned:IsHave(piece)
    return self.HAVE[self:GetState(piece)] == true
end

-- have, total for a set (cached). beta.7: a set once complete stays complete (Alts keeps the
-- date per character), so upgrading pieces away doesn't make it "unfinished" again.
function Owned:SetCount(set)
    local c = countCache[set.key]
    if c then return c[1], c[2] end
    local have, total = 0, #set.pieces
    for _, p in ipairs(set.pieces) do
        if self:IsHave(p) then have = have + 1 end
    end
    local A = ns.Alts
    if A and set.id and total > 0 then
        if have >= total then
            if not set.unreleased then pcall(A.MarkCompleted, A, set.id) end
        else
            local ok, done = pcall(A.IsCompleted, A, set.id)
            if ok and done then have = total end
        end
    end
    countCache[set.key] = { have, total }
    return have, total
end

-- Completion date (epoch) of a set for this character, nil if not finished.
function Owned:CompletedOn(set)
    local A = ns.Alts
    if not (A and set and set.id) then return nil end
    self:SetCount(set)        -- marks it when complete right now
    local ok, t = pcall(A.IsCompleted, A, set.id)
    return ok and t or nil
end

-- How many of a set's pieces are in each state: { equipped = n, bags = n, bank = n,
-- mail = n, keyring = n, account = n, look = n, need = n } (same per-item cache).
function Owned:SetBreakdown(set)
    local out = { equipped = 0, bags = 0, bank = 0, mail = 0, keyring = 0, account = 0, look = 0, need = 0 }
    for _, p in ipairs(set.pieces) do
        local s = self:GetState(p)
        out[s] = (out[s] or 0) + 1
    end
    return out
end

function Owned:Invalidate()
    wipe(stateCache)
    wipe(countCache)
    equipped = nil
    if ns.Data and ns.Data.ClearEffort then ns.Data:ClearEffort() end   -- effort counts needed pieces
end

-- Something changed: clear the cache, refresh the window once (coalesced).
local pending = false
function Owned:Changed()
    self:Invalidate()
    if pending then return end
    if not (ns.UI and ns.UI:IsShown()) then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        if ns.UI:IsShown() then ns.UI:RefreshCounts() end
    end)
end

function Owned:Init()
    local f = CreateFrame("Frame")
    for _, e in ipairs({
        "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYERBANKSLOTS_CHANGED",
        "BANKFRAME_OPENED", "TRANSMOG_COLLECTION_UPDATED",
    }) do
        ns.SafeRegister(f, e)
    end
    f:SetScript("OnEvent", function() Owned:Changed() end)
end
