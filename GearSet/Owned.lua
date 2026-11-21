-- Gear Set: which pieces you have or need.
-- States: equipped, bags, bank, mail, keyring, account (you own it), look (appearance
-- collected, item not owned), need. 1.1.1: "look" counts as have only with the setting
-- db.countLooks (off by default: items you own only, what the set bonus needs); a finished
-- date is only ever recorded from items. Results are cached until something changes.
local _, ns = ...

local Owned = {}
ns.Owned = Owned

local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local stateCache, countCache, equipped = {}, {}, nil

-- beta.7: mail / keyring / account bank (Alts.lua) count as have too.
-- 1.1.1: the states where you own the item; "look" is added by Owned.CountsLooks().
Owned.HAVE = { equipped = true, bags = true, bank = true, mail = true, keyring = true, account = true }

-- The setting "Count collected appearances as have" (false / missing = items only).
function Owned.CountsLooks()
    local db = ns.db
    return type(db) == "table" and db.countLooks == true
end

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
    if piece.unknown then return "unknown" end   -- v1.0.1: not in this game version (never "have")
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

-- You own the item (any place), whatever the setting says.
function Owned:IsOwned(piece)
    return self.HAVE[self:GetState(piece)] == true
end

-- Counts as have: owned, or (with the setting on) its look collected.
function Owned:IsHave(piece)
    local s = self:GetState(piece)
    if self.HAVE[s] then return true end
    return s == "look" and Owned.CountsLooks()
end

-- Released pieces of a set this client doesn't know (Data's set.unknown), 0 when none.
function Owned.UnknownCount(set)
    local u = set and set.unknown
    return type(u) == "table" and #u or 0
end

-- have, total for a set (cached). beta.7: a set once complete stays complete (Alts keeps the
-- date per character), so upgrading pieces away doesn't make it "unfinished" again.
function Owned:SetCount(set)
    local c = countCache[set.key]
    if c then return c[1], c[2] end
    local have, owned, total = 0, 0, #set.pieces
    local looksCount = Owned.CountsLooks()
    for _, p in ipairs(set.pieces) do
        local s = self:GetState(p)          -- read once per piece (bag changes recount every set)
        if self.HAVE[s] then
            owned = owned + 1
            have = have + 1
        elseif s == "look" and looksCount then
            have = have + 1
        end
    end
    -- v1.0.1 (F1): pieces this client doesn't know count in the total, never as have, and a
    -- set with any of them is never marked finished (a date saved before stays saved, unused).
    local unknown = Owned.UnknownCount(set)
    total = total + unknown
    local A = ns.Alts
    if A and set.id and total > 0 and unknown == 0 then
        -- 1.1.1: a finished date is recorded only when every item is owned (never from looks).
        if owned >= total and not set.unreleased then pcall(A.MarkCompleted, A, set.id) end
        if have < total then
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
    if Owned.UnknownCount(set) > 0 then return nil end   -- v1.0.1: an old date isn't shown
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
    out.unknown = Owned.UnknownCount(set)   -- v1.0.1
    return out
end

-- 1.1.1: the "Looks" count: pieces you own or whose look you collected, total (same total as
-- SetCount; no finished date is honoured here: looks don't go away).
function Owned:LookCount(set)
    local n = 0
    for _, p in ipairs(set.pieces) do
        local s = self:GetState(p)
        if self.HAVE[s] or s == "look" then n = n + 1 end
    end
    return n, #set.pieces + Owned.UnknownCount(set)
end

-- 1.1.1: items you own right now, total (no setting, no finished date): "Check finished
-- sets again" (Alts.RecheckDone) uses it.
function Owned:ItemCount(set)
    local n = 0
    for _, p in ipairs(set.pieces) do
        if self:IsOwned(p) then n = n + 1 end
    end
    return n, #set.pieces
end

-- The settings check box: save, drop every count, redraw what is open.
function Owned.SetCountsLooks(on)
    local db = ns.db
    if type(db) ~= "table" then return end
    on = on and true or false
    if (db.countLooks == true) == on then return end
    db.countLooks = on
    Owned:Invalidate()
    if ns.Runs and ns.Runs.Invalidate then pcall(ns.Runs.Invalidate) end
    if ns.Progress and ns.Progress.Invalidate then pcall(ns.Progress.Invalidate, ns.Progress) end
    if ns.UI and ns.UI.IsShown and ns.UI:IsShown() and ns.UI.RefreshAll then pcall(ns.UI.RefreshAll, ns.UI) end
    if ns.Tracker and ns.Tracker.Update then pcall(ns.Tracker.Update, ns.Tracker) end
end

-- 1.1.1: one local chat line, once per account, for data from before DB v10 (ToS N7: a plain
-- ns.Print in our style). Shown a few seconds after the first login with this version.
function Owned.ShowLookNote()
    local db = ns.db
    if type(db) ~= "table" or db.lookNote ~= false then return false end
    db.lookNote = true
    if ns.Print and ns.L and ns.L.LOOK_NOTE then ns.Print(ns.L.LOOK_NOTE) end
    return true
end
Owned.NOTE_DELAY = 8

function Owned:Invalidate()
    wipe(stateCache)
    wipe(countCache)
    equipped = nil
    if ns.Data and ns.Data.ClearEffort then ns.Data:ClearEffort() end   -- effort counts needed pieces
end

-- 1.1 beta.4 seenOut (ToS B6): not-out-yet pieces your own characters hold, checked at most
-- once per 2 s after bags / bank / equipment change (Data.NoteSeen, Alts index only).
local seenPending = false
function Owned.QueueSeen()
    if seenPending or not (ns.Data and ns.Data.NoteSeen) then return end
    seenPending = true
    local function run()
        seenPending = false
        pcall(ns.Data.NoteSeen)
    end
    if C_Timer and C_Timer.After then C_Timer.After(2, run) else run() end
end

-- Something changed: clear the cache, refresh the window once (coalesced).
local pending = false
function Owned:Changed()
    self:Invalidate()
    Owned.QueueSeen()
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
    -- 1.1.1: the one-time note (only when the saved data asks for it).
    if type(ns.db) == "table" and ns.db.lookNote == false then
        local n = CreateFrame("Frame")
        ns.SafeRegister(n, "PLAYER_ENTERING_WORLD")
        n:SetScript("OnEvent", function(frame)
            frame:UnregisterAllEvents()
            if C_Timer and C_Timer.After then
                C_Timer.After(Owned.NOTE_DELAY, Owned.ShowLookNote)
            else
                Owned.ShowLookNote()
            end
        end)
    end
end
