-- Gear Set: tracking (ns.Track), collection progress (ns.Progress) and the Progress tab.
--
-- Tracking: a star on set and piece rows; shift-click tracks / untracks. Saved per
-- character in GearSetDB.tracked["Name-Realm"] = { ["set:<id>"] = true, ["item:<id>"] = true }
-- (typed keys like Entries.lua, so pets/mounts can be added later).
--
-- Progress: worked out on demand (Progress tab, minimap / broker tooltip, the quiet
-- milestone check) and cached until Owned:Invalidate (bags, bank, gear, collection,
-- alt data changed). Sets that are removed, the other faction's, hidden or not out yet
-- are left out of every count. "This character" = Owned:SetCount; "Whole account" = a piece
-- counts when this character has it or any saved character / the account bank holds it.
--
-- "Recently got": the first time a set piece shows up on this character (Alts' bag / bank /
-- mail / keyring lists) its date is kept in progress.got; at the first look everything
-- already there is stored with date 0, so old pieces never show as new.
-- Milestones: one quiet chat line ("Gear Set: Milestone: ..."), never a sound, never sent
-- to anyone; at the first look the milestones already reached are noted silently.
-- Only this account's own characters are ever counted (never inspect data).
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local Track, Progress = {}, {}
ns.Track, ns.Progress = Track, Progress

local EMPTY = {}
local MAX_RECENT = 20
local MIN_GAP = 20          -- seconds between two background checks (got + milestones)

local function T(key, fallback)
    local v = L and L[key]
    if v == nil then return fallback end
    return v
end

local function Now()
    local t = type(time) == "function" and time() or 0
    return type(t) == "number" and t or 0
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function MyKey()
    local A = ns.Alts
    if not (A and A.MyKey) then return nil end
    local ok, key = pcall(A.MyKey, A)
    if ok and type(key) == "string" then return key end
end

local function DB() return type(ns.db) == "table" and ns.db or nil end

-- ---------------------------------------------------------------------------
-- Tracking

function Track.Key(kind, id) return tostring(kind) .. ":" .. tostring(id) end

-- Pure (also used by /gs selftest on copies): tbl = a `tracked` table.
function Track.IsIn(tbl, charKey, key)
    local t = type(tbl) == "table" and charKey and tbl[charKey]
    return type(t) == "table" and t[key] == true
end

-- Toggles `key` for `charKey`; returns the new state (nil = can't).
function Track.ToggleIn(tbl, charKey, key)
    if type(tbl) ~= "table" or type(charKey) ~= "string" or type(key) ~= "string" then return nil end
    local t = tbl[charKey]
    if type(t) ~= "table" then
        if t ~= nil then return nil end     -- not ours to overwrite
        t = {}
        tbl[charKey] = t
    end
    if t[key] then
        t[key] = nil
        return false
    end
    t[key] = true
    return true
end

local function Tracked()
    local db = DB()
    return db and type(db.tracked) == "table" and db.tracked or nil
end

-- This character's tracked keys (read only; EMPTY when none).
function Track.Mine()
    local tbl, key = Tracked(), MyKey()
    local t = tbl and key and tbl[key]
    return type(t) == "table" and t or EMPTY
end

function Track.IsSet(set)
    return set ~= nil and set.id ~= nil and Track.Mine()[Track.Key("set", set.id)] == true
end

function Track.IsPiece(itemID)
    return itemID ~= nil and Track.Mine()[Track.Key("item", itemID)] == true
end

-- The set or any of its pieces is tracked ("Tracked only" filter).
function Track.Touches(set)
    if not set then return false end
    if Track.IsSet(set) then return true end
    local mine = Track.Mine()
    if next(mine) == nil then return false end
    for _, p in ipairs(set.shown or set.pieces or EMPTY) do
        if mine[Track.Key("item", p.itemID)] then return true end
    end
    return false
end

local function AfterTrackChange()
    Progress:Invalidate()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then
        if ns.SetList and ns.SetList.Refresh then ns.SetList:Refresh() end
        if ns.PieceList and ns.PieceList.Refresh then ns.PieceList:Refresh() end
        Progress:Refresh()
    end
end

-- Pure: the current character's own entry, if it isn't a table (broken SavedVariables),
-- becomes an empty one so tracking works again. Other characters' entries are never touched.
function Track.FixMine(tbl, charKey)
    if type(tbl) ~= "table" or type(charKey) ~= "string" then return false end
    local t = tbl[charKey]
    if t ~= nil and type(t) ~= "table" then
        tbl[charKey] = {}
        return true
    end
    return false
end

local function Toggle(kind, id)
    local key = MyKey()
    Track.FixMine(Tracked(), key)
    local state = Track.ToggleIn(Tracked(), key, Track.Key(kind, id))
    if state == nil then return nil end
    if PlaySound and SOUNDKIT then
        PlaySound(state and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
    AfterTrackChange()
    return state
end

function Track.ToggleSet(set)
    if not (set and set.id) then return nil end
    return Toggle("set", set.id)
end

function Track.TogglePiece(itemID)
    if type(itemID) ~= "number" then return nil end
    return Toggle("item", itemID)
end

-- Star texture on a row (Theme.art.star).
function Track.MakeStar(parent, layer)
    local art = Theme.art.star or {}
    local tex = parent:CreateTexture(nil, layer or "OVERLAY")
    tex:SetSize(art.size or 12, art.size or 12)
    Theme.SetArt(tex, art)
    tex:Hide()
    return tex
end

-- ---------------------------------------------------------------------------
-- Counting (pure parts take everything as arguments, so tests and /gs selftest can run them)

-- Left out of every %: removed, the other faction's, hidden, not out yet; with classOk
-- (one character's count, the user's choice) also sets that class can't wear.
function Progress.Counted(set, faction, isHidden, classOk)
    if type(set) ~= "table" or set.removed or set.unreleased then return false end
    if faction and set.faction and set.faction ~= faction then return false end
    if isHidden and isHidden(set) then return false end
    if classOk and not classOk(set) then return false end
    return true
end

local function Group(t, k)
    local g = t[k]
    if not g then
        g = { have = 0, total = 0, complete = 0, sets = 0 }
        t[k] = g
    end
    return g
end

local function AddTo(g, have, total)
    g.have, g.total, g.sets = g.have + have, g.total + total, g.sets + 1
    if have >= total then g.complete = g.complete + 1 end
end

-- sets: list; count(set) -> have, total. Returns { have, total, complete, started, sets, pct,
-- kinds = { [kind] = group }, tiers = { [tag] = group } }.
function Progress.Summarize(sets, count, faction, isHidden, classOk)
    local s = { have = 0, total = 0, complete = 0, started = 0, sets = 0, kinds = {}, tiers = {} }
    for _, set in ipairs(sets or EMPTY) do
        if Progress.Counted(set, faction, isHidden, classOk) then
            local ok, have, total = pcall(count, set)
            have, total = ok and tonumber(have) or 0, ok and tonumber(total) or 0
            if total > 0 then
                if have > total then have = total end
                if have < 0 then have = 0 end
                AddTo(s, have, total)
                if have > 0 and have < total then s.started = s.started + 1 end
                if type(set.kind) == "string" then AddTo(Group(s.kinds, set.kind), have, total) end
                if type(set.tier) == "string" and set.tier ~= "" then AddTo(Group(s.tiers, set.tier), have, total) end
            end
        end
    end
    s.pct = s.total > 0 and math.floor(s.have * 100 / s.total) or 0
    return s
end

local function HiddenFn()
    local D = ns.Data
    return D and D.IsHidden or nil
end

local function Faction()
    local D = ns.Data
    if D and D.PlayerFaction then
        local ok, f = pcall(D.PlayerFaction)
        if ok then return f end
    end
end

local function AllSets()
    local D = ns.Data
    if not (D and D.GetSets) then return nil end
    local ok, sets = pcall(D.GetSets, D)
    return ok and type(sets) == "table" and sets or nil
end

local function CharCount(set)
    return ns.Owned:SetCount(set)
end

-- Class ID from a class file name ("ROGUE" -> 4); nil when unknown.
local function ClassIDOf(file)
    if type(file) ~= "string" then return nil end
    local n = type(GetNumClasses) == "function" and GetNumClasses() or 12
    for id = 1, n do
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(id)
        if type(info) == "table" and info.classFile == file then return id end
        if type(GetClassInfo) == "function" then
            local _, f = GetClassInfo(id)
            if f == file then return id end
        end
    end
end

-- "This character" counts only sets that class can wear (Data.SetForClass, the same rule
-- as the list's "Only my class"). nil = no class known: every set counts.
local function ClassFilter(classID)
    local D = ns.Data
    if not (classID and D and D.SetForClass) then return nil end
    return function(set)
        local ok, yes = pcall(D.SetForClass, set, classID)
        return not ok or yes and true or false
    end
end
Progress.ClassFilter = ClassFilter

local function MyClassID()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, _, id = pcall(UnitClass, "player")
    return ok and type(id) == "number" and id or nil
end

-- Whole account: this character's count, a finished set on any saved character, or each
-- piece held by anyone (Alts' index, incl. the account bank).
local function AccountCounter()
    local A, O = ns.Alts, ns.Owned
    local chars = {}
    if A and A.Chars then
        local ok, list = pcall(A.Chars, A)
        if ok and type(list) == "table" then chars = list end
    end
    return function(set)
        local have, total = O:SetCount(set)
        if have >= total or not A then return have, total end
        for _, c in ipairs(chars) do
            if not c.me and A.IsCompleted and A:IsCompleted(set.id, c.key) then return total, total end
        end
        have = 0
        for _, p in ipairs(set.pieces) do
            if O:IsHave(p) or (A.GetHolders and #A:GetHolders(p.itemID) > 0) then have = have + 1 end
        end
        return have, total
    end
end

local cache = {}

function Progress:Invalidate()
    wipe(cache)
end

function Progress.Scope()
    local db = DB()
    local s = db and type(db.progress) == "table" and db.progress.scope
    return (s == "account") and "account" or "char"
end

-- Summary for "char" / "account" (default: the saved choice); cached. nil = no data yet.
function Progress:Get(scope)
    scope = scope or Progress.Scope()
    if cache[scope] then return cache[scope] end
    local sets = AllSets()
    if not (sets and ns.Owned) then return nil end
    local count = scope == "account" and AccountCounter() or CharCount
    local classOk = scope ~= "account" and ClassFilter(MyClassID()) or nil
    local s = Progress.Summarize(sets, count, Faction(), HiddenFn(), classOk)
    cache[scope] = s
    return s
end

-- One summary per saved character (Progress tab rows; this character first).
function Progress:Chars()
    if cache.chars then return cache.chars end
    local A, sets = ns.Alts, AllSets()
    local out = {}
    if A and A.Chars and A.GetSetProgress and sets then
        local ok, list = pcall(A.Chars, A)
        if ok and type(list) == "table" then
            local faction, hidden = Faction(), HiddenFn()
            for _, c in ipairs(list) do
                local classID = c.me and MyClassID() or ClassIDOf(c.class)
                local s = Progress.Summarize(sets, function(set)
                    if c.me then return CharCount(set) end
                    return A:GetSetProgress(set.id, c.key)
                end, faction, hidden, ClassFilter(classID))
                s.name, s.class, s.me = c.name, c.class, c.me
                out[#out + 1] = s
            end
        end
    end
    cache.chars = out
    return out
end

-- Piece object by item ID (needed for Owned:GetState on tracked pieces).
local pieceIndex
local function PieceOf(itemID)
    if not pieceIndex then
        local sets = AllSets()
        if not sets then return nil end
        pieceIndex = {}
        for _, set in ipairs(sets) do
            for _, p in ipairs(set.shown or set.pieces) do
                if not pieceIndex[p.itemID] then pieceIndex[p.itemID] = p end
            end
        end
    end
    return pieceIndex[itemID]
end
Progress.PieceOf = PieceOf

-- This character's tracked sets / pieces and how many pieces are still needed (unique).
function Progress:TrackedStats()
    if cache.tracked then return cache.tracked end
    local nSets, nPieces, need = 0, 0, {}
    local D, O = ns.Data, ns.Owned
    for key in pairs(Track.Mine()) do
        local kind, id = tostring(key):match("^(%a+):(%d+)$")
        id = tonumber(id)
        if kind == "set" and id and D and D.GetSet then
            local set = D:GetSet("c" .. id)
            if set then
                nSets = nSets + 1
                for _, p in ipairs(set.pieces) do
                    if not O:IsHave(p) then need[p.itemID] = true end
                end
            end
        elseif kind == "item" and id then
            local p = PieceOf(id)
            if p then
                nPieces = nPieces + 1
                if not O:IsHave(p) then need[id] = true end
            end
        end
    end
    local left = 0
    for _ in pairs(need) do left = left + 1 end
    cache.tracked = { sets = nSets, pieces = nPieces, left = left }
    return cache.tracked
end

-- Line for the minimap button and broker tooltips ("38% of set pieces, 12 tracked pieces left").
function Progress:LineText()
    local ok, s = pcall(self.Get, self)
    if not ok or not s or s.total == 0 then return nil end
    local okT, t = pcall(self.TrackedStats, self)
    if okT and t and (t.sets + t.pieces) > 0 then
        return T("P_LINE_TRACKED", "%d%% of set pieces, %d tracked pieces left"):format(s.pct, t.left)
    end
    return T("P_LINE", "%d%% of set pieces"):format(s.pct)
end

function Progress:AddTooltipLine(tip)
    if not (tip and tip.AddLine) then return end
    local text = self:LineText()
    if text then tip:AddLine(text, Theme.colors.text:GetRGB()) end
end

-- ---------------------------------------------------------------------------
-- Recently got + milestones (pure parts, then the live check)

-- got = progress.got; have = { [itemID] = true } now. First look: everything stored with 0.
-- Returns the item IDs that are new since the last look.
function Progress.UpdateGot(got, key, have, now)
    if type(got) ~= "table" or type(key) ~= "string" then return {} end
    local rec = got[key]
    local new = {}
    if rec == nil then
        rec = {}
        got[key] = rec
        for id in pairs(have) do rec[id] = 0 end
        return new
    end
    if type(rec) ~= "table" then return new end
    for id in pairs(have) do
        if rec[id] == nil then
            rec[id] = now
            new[#new + 1] = id
        end
    end
    return new
end

local MILESTONES = {
    { "first_set", function(s) return s.complete >= 1 end },
    { "sets_5",    function(s) return s.complete >= 5 end },
    { "sets_10",   function(s) return s.complete >= 10 end },
    { "sets_25",   function(s) return s.complete >= 25 end },
    { "pct_25",    function(s) return s.total > 0 and s.have * 4 >= s.total end },
    { "pct_50",    function(s) return s.total > 0 and s.have * 2 >= s.total end },
    { "pct_75",    function(s) return s.total > 0 and s.have * 4 >= s.total * 3 end },
    { "pct_100",   function(s) return s.total > 0 and s.have >= s.total end },
}
Progress.MILESTONES = MILESTONES

-- marks = progress.marks. First look: what is already reached is noted with 0 (no line).
-- Returns the milestone IDs reached just now (each only ever once per character).
function Progress.NewMilestones(marks, key, sum, now)
    if type(marks) ~= "table" or type(key) ~= "string" or type(sum) ~= "table" then return {} end
    local rec = marks[key]
    local first = rec == nil
    if first then
        rec = {}
        marks[key] = rec
    elseif type(rec) ~= "table" then
        return {}
    end
    local new = {}
    for _, m in ipairs(MILESTONES) do
        if rec[m[1]] == nil and m[2](sum) then
            rec[m[1]] = first and 0 or now
            if not first then new[#new + 1] = m[1] end
        end
    end
    return new
end

function Progress.MilestoneText(id)
    return T("MS_LINE", "Milestone: %s"):format(T("MS_" .. tostring(id), tostring(id)))
end

local function ProgressTable()
    local db = DB()
    local p = db and db.progress
    if type(p) ~= "table" then return nil end
    if type(p.got) ~= "table" or type(p.marks) ~= "table" then return nil end   -- PrepareDB makes them
    return p
end

-- Set pieces this character holds now (Alts' lists: equipped, bags, bank, mail, keyring).
local function MyItems(me)
    local A = ns.Alts
    local out = {}
    if not (A and A.SetItems and A.GetHolders) then return out end
    for id in pairs(A.SetItems()) do
        for _, h in ipairs(A:GetHolders(id)) do
            if h.key == me then out[id] = true; break end
        end
    end
    return out
end

function Progress:ScanGot()
    local p, me = ProgressTable(), MyKey()
    if not (p and me) then return {} end
    local new = Progress.UpdateGot(p.got, me, MyItems(me), Now())
    if #new > 0 then cache.recent = nil end
    return new
end

function Progress:CheckMilestones()
    local p, me = ProgressTable(), MyKey()
    if not (p and me) then return {} end
    local s = self:Get("char")
    if not s then return {} end
    local new = Progress.NewMilestones(p.marks, me, s, Now())
    local db = DB()
    if db and db.milestoneNotes ~= false and ns.Print then
        for _, id in ipairs(new) do ns.Print(Progress.MilestoneText(id)) end
    end
    return new
end

-- Both at once (the debounced background check; tests call it directly).
function Progress:CheckNow()
    local okG, got = pcall(self.ScanGot, self)
    local okM, ms = pcall(self.CheckMilestones, self)
    if self.page and self.page:IsVisible() then self:Refresh() end
    return okG and got or {}, okM and ms or {}
end

-- Recently got pieces: { { id, t, who } } newest first (who = character name, account scope).
function Progress:Recent(scope)
    scope = scope or Progress.Scope()
    local key = "recent_" .. scope
    if cache[key] then return cache[key] end
    local p, me = ProgressTable(), MyKey()
    local out = {}
    if p then
        local names = {}
        if scope == "account" and ns.Alts and ns.Alts.Chars then
            local ok, list = pcall(ns.Alts.Chars, ns.Alts)
            if ok and type(list) == "table" then
                for _, c in ipairs(list) do names[c.key] = c.name end
            end
        end
        for ck, rec in pairs(p.got) do
            if type(rec) == "table" and (scope == "account" or ck == me) then
                for id, t in pairs(rec) do
                    if type(id) == "number" and type(t) == "number" and t > 0 then
                        out[#out + 1] = { id = id, t = t, who = scope == "account" and (names[ck] or ck:match("^([^%-]+)")) or nil }
                    end
                end
            end
        end
        table.sort(out, function(a, b)
            if a.t ~= b.t then return a.t > b.t end
            return a.id < b.id
        end)
        for i = #out, MAX_RECENT + 1, -1 do out[i] = nil end
    end
    cache[key] = out
    return out
end

-- Debounced background check: a few seconds after bags/bank/gear change, never in combat,
-- at most once per MIN_GAP seconds, and only from 10 s after login (Alts has read the bags).
local ready, pending, lastRun = false, false, nil
local waiter = CreateFrame("Frame")

local function RunCheck()
    pending = false
    if not ready then return end
    if InCombat() then
        ns.SafeRegister(waiter, "PLAYER_REGEN_ENABLED")
        return
    end
    local t = type(GetTime) == "function" and GetTime() or 0
    if lastRun and t - lastRun < MIN_GAP then
        pending = true
        C_Timer.After(MIN_GAP - (t - lastRun), RunCheck)
        return
    end
    lastRun = t
    Progress:CheckNow()
end

function Progress.Schedule(delay)
    if pending or not (C_Timer and C_Timer.After) then return end
    pending = true
    C_Timer.After(delay or 3, RunCheck)
end

waiter:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if C_Timer and C_Timer.After then
            C_Timer.After(10, function() ready = true; Progress.Schedule(0) end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Progress.Schedule(1)
    end
end)
ns.SafeRegister(waiter, "PLAYER_LOGIN")

-- Our own module's functions (not Blizzard's): the cache follows Owned's.
if ns.Owned and hooksecurefunc then
    hooksecurefunc(ns.Owned, "Invalidate", function() Progress:Invalidate() end)
    hooksecurefunc(ns.Owned, "Changed", function() Progress.Schedule(3) end)
end

-- ---------------------------------------------------------------------------
-- Gold (PART B's ns.Gold; everything nil-guarded) and chat share

-- Contract: plans\v1.0.0\beta8-interface.md. Texts come from Gold.lua (ns.L.GOLD_*).

-- Short money text for a piece row ("20g"), only when a fixed cost is known.
function Progress.PieceMoney(itemID)
    local G = ns.Gold
    if not (G and G.PieceCost and G.Money and itemID) then return nil end
    local ok, copper = pcall(G.PieceCost, G, itemID)
    if not ok or type(copper) ~= "number" or copper <= 0 then return nil end
    local okM, text = pcall(G.Money, copper)
    return okM and text or nil
end

-- "Costs 20g (quest)" / "Sold by a vendor (price not in our data)" / "Can't be bought ..." / nil.
function Progress.PieceCostText(itemID)
    local G = ns.Gold
    if not (G and G.PieceCostText and itemID) then return nil end
    local ok, text = pcall(G.PieceCostText, G, itemID)
    return ok and type(text) == "string" and text or nil
end

-- "Gold still needed: 120g[, 3 pieces can't be bought]" for this character, or nil.
function Progress.SetCostText(set)
    local G = ns.Gold
    if not (G and G.SetCostText and set and set.id) then return nil end
    local ok, text = pcall(G.SetCostText, G, set.id, MyKey())
    return ok and type(text) == "string" and text or nil
end

function Progress.CanShare()
    local S = ns.Share
    return S ~= nil and type(S.SetToChat) == "function"
end

local SHARE_WHY = {
    full = { "SHARE_FULL", "chat box too full" },
    loading = { "SHARE_LOADING", "item info still loading, try again" },
}

-- Pure: the "Gear Set:" note for a failed share (nil when there's nothing to say).
function Progress.ShareNote(ok, why)
    if ok then return nil end
    local w = SHARE_WHY[why]
    return w and T(w[1], w[2]) or nil
end

-- -> ok, why. On a failure SetToChat inserts nothing; we tell the player why in one chat line.
function Progress.Share(set)
    if not (set and set.id and Progress.CanShare()) then return nil end
    local done, ok, _, _, why = pcall(ns.Share.SetToChat, ns.Share, set.id)
    if not done then return nil end
    local note = Progress.ShareNote(ok, why)
    if note and ns.Print then ns.Print(note) end
    return ok, why
end

-- ---------------------------------------------------------------------------
-- The Progress tab (one full-width inset; Main.lua's UI:AddTab makes the page)

local LEFT_X, LEFT_W, RIGHT_X = 14, 500, 540
local LABEL_W, PCT_W = 150, 44
local KIND_ORDER = ns.SET_KINDS or { "d", "r", "p", "c", "w", "f" }
local TIER_ORDER = { "D1", "D2", "T1", "T2", "T3", "ZG", "AQ20", "AQ40", "PvP" }

local function KindName(k) return L["KIND_" .. k:upper()] or k end
local function TierName(tag)
    local D = ns.Data
    if D and D.TierName then return D.TierName(tag) end
    return L["TIER_" .. tag] or tag
end

local function BarTooltip(row)
    local g = row.group
    if not g then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.label:GetText() or "", Theme.colors.title:GetRGB())
    GameTooltip:AddLine(L.HAVE_COUNT:format(g.have, g.total), Theme.CountColor(g.have, g.total))
    GameTooltip:AddLine(T("P_BAR_TIP", "%d of %d sets complete"):format(g.complete, g.sets), Theme.colors.subtle:GetRGB())
    if row.kind or row.tier then Theme.AddHint(GameTooltip, T("P_BAR_HINT", "Click: show these sets in the list")) end
    GameTooltip:Show()
end

local function BarClick(row)
    if not (row.kind or row.tier) then return end
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    local SL = ns.SetList
    if SL and SL.ShowGroup then SL.ShowGroup(row.kind, row.tier) end
end

function Progress.MakeBar(parent, width)
    local art = Theme.art.progressBar or {}
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width or LEFT_W, Theme.sizes.progressRow or 22)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Theme.SetArt(hl, Theme.art.listHover)
    row.label = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.label, "normal")
    row.label:SetPoint("LEFT", 4, 0)
    row.label:SetWidth(LABEL_W - 8)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.pct = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.pct, "small")
    row.pct:SetPoint("RIGHT", -4, 0)
    row.pct:SetWidth(PCT_W)
    row.pct:SetJustifyH("RIGHT")
    local h = art.height or 14
    local edge = row:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("LEFT", LABEL_W - 1, 0)
    edge:SetPoint("RIGHT", row.pct, "LEFT", -5, 0)
    edge:SetHeight(h + 2)
    edge:SetColorTexture(unpack(art.edge or { 0, 0, 0, 0.9 }))
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("LEFT", LABEL_W, 0)
    bar:SetPoint("RIGHT", row.pct, "LEFT", -6, 0)
    bar:SetHeight(h)
    if bar.SetStatusBarTexture then bar:SetStatusBarTexture(art.file or "Interface\\TargetingFrame\\UI-StatusBar") end
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(art.bg or { 0, 0, 0, 0.45 }))
    row.bar = bar
    row.count = bar:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.count, "small")
    row.count:SetPoint("CENTER")
    row:SetScript("OnEnter", BarTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", BarClick)
    return row
end

function Progress.FillBar(row, label, g)
    row.group = g
    row.label:SetText(label)
    local have, total = g.have, g.total
    local bar = row.bar
    if bar.SetMinMaxValues then bar:SetMinMaxValues(0, math.max(total, 1)) end
    if bar.SetValue then bar:SetValue(have) end
    if bar.SetStatusBarColor then bar:SetStatusBarColor(Theme.CountColor(have, total)) end
    row.count:SetText(("%d / %d"):format(have, total))
    row.pct:SetText(("%d%%"):format(total > 0 and math.floor(have * 100 / total) or 0))
    row.pct:SetTextColor(Theme.CountColor(have, total))
end

local function Head(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, "normal")
    fs:SetTextColor(Theme.colors.progressHead:GetRGB())
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function SetScope(scope)
    local db = DB()
    if not (db and type(db.progress) == "table") then return end
    if db.progress.scope == scope then return end
    db.progress.scope = scope
    Progress:Refresh()
end

local function ScopeText(scope) return T("P_SCOPE_" .. scope, scope) end

local function MakeScope(page)
    local dd, tmpl = Theme.CreateFrame("DropdownButton", nil, page, "dropdown")
    if dd and tmpl and dd.SetupMenu then
        dd:SetupMenu(function(_, root)
            for _, s in ipairs({ "char", "account" }) do
                root:CreateRadio(ScopeText(s), function() return Progress.Scope() == s end,
                    function() SetScope(s) end)
            end
        end)
    else
        if dd then dd:Hide() end
        dd = Theme.CreateFrame("Button", nil, page, "button")
        dd:SetScript("OnClick", function()
            SetScope(Progress.Scope() == "char" and "account" or "char")
        end)
        dd.gsPlain = true
    end
    dd:SetSize(170, 22)
    dd:SetPoint("TOPRIGHT", -14, -10)
    local label = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(label, "normal")
    label:SetPoint("RIGHT", dd, "LEFT", -8, 0)
    label:SetText(T("P_SCOPE", "Count for"))
    return dd
end

function Progress:Build(page)
    if self.page then return end
    self.page = page
    self.pct = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.pct, "header")
    self.pct:SetPoint("TOPLEFT", LEFT_X, -12)
    self.summary = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.summary, "text")
    self.summary:SetPoint("TOPLEFT", self.pct, "BOTTOMLEFT", 0, -4)
    self.tracked = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.tracked, "small")
    self.tracked:SetTextColor(Theme.colors.subtle:GetRGB())
    self.tracked:SetPoint("TOPLEFT", self.summary, "BOTTOMLEFT", 0, -4)
    self.scope = MakeScope(page)

    self.total = Progress.MakeBar(page, LEFT_W)
    self.total:SetPoint("TOPLEFT", LEFT_X, -74)
    self.kindHead = Head(page, T("P_BY_KIND", "By content"))
    self.tierHead = Head(page, T("P_BY_TIER", "By tier"))
    self.bars = {}

    -- Right column: recently got + one row per character, in a scroll frame.
    local scroll = Theme.CreateFrame("ScrollFrame", nil, page, "scrollFrame")
    scroll:SetPoint("TOPLEFT", RIGHT_X, -74)
    scroll:SetPoint("BOTTOMRIGHT", -30, 30)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 10)
    scroll:SetScrollChild(child)
    if scroll.SetScript and not scroll.ScrollBar then
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(sf, delta)
            local cur, max = sf:GetVerticalScroll() or 0, sf:GetVerticalScrollRange() or 0
            sf:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 40)))
        end)
    end
    self.scroll, self.child, self.lines = scroll, child, {}

    self.note = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.note, "small")
    self.note:SetTextColor(Theme.colors.progressNote:GetRGB())
    self.note:SetPoint("BOTTOMLEFT", LEFT_X, 10)
    self.note:SetText(T("P_LEFT_OUT", "Not counted: removed, other-faction, hidden and not-yet-released sets."))
end

local function Bar(self, i)
    local b = self.bars[i]
    if not b then
        b = Progress.MakeBar(self.page, LEFT_W)
        self.bars[i] = b
    end
    return b
end

-- Bars per kind and tier (only groups with sets), under their headings.
local function LayBars(self, s)
    local rowH = Theme.sizes.progressRow or 22
    local y, n = -104, 0
    local function Section(head, order, groups, nameOf, field)
        local any = false
        for _, k in ipairs(order) do if groups[k] then any = true end end
        head:SetShown(any)
        if not any then return end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", LEFT_X, y)
        y = y - 20
        for _, k in ipairs(order) do
            local g = groups[k]
            if g then
                n = n + 1
                local b = Bar(self, n)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", LEFT_X, y)
                b.kind, b.tier = nil, nil
                b[field] = k
                Progress.FillBar(b, nameOf(k), g)
                b:Show()
                y = y - rowH
            end
        end
        y = y - 8
    end
    Section(self.kindHead, KIND_ORDER, s.kinds, KindName, "kind")
    -- tiers not in the known order still show (data may add tags)
    local order = {}
    for _, k in ipairs(TIER_ORDER) do order[#order + 1] = k end
    local extra = {}
    for k in pairs(s.tiers) do
        local known = false
        for _, o in ipairs(TIER_ORDER) do if o == k then known = true end end
        if not known then extra[#extra + 1] = k end
    end
    table.sort(extra)
    for _, k in ipairs(extra) do order[#order + 1] = k end
    Section(self.tierHead, order, s.tiers, TierName, "tier")
    for i = n + 1, #self.bars do self.bars[i]:Hide() end
end

local function Line(self, i, font)
    local fs = self.lines[i]
    if not fs then
        fs = self.child:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        self.lines[i] = fs
    end
    Theme.Font(fs, font)
    fs:SetTextColor(Theme.colors.text:GetRGB())
    return fs
end

local function ItemText(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link
    if get then
        local ok, n, l = pcall(get, id)
        if ok then name, link = n, l end
    end
    if type(link) == "string" and link ~= "" then return link, true end
    if type(name) == "string" and name ~= "" then return name, true end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return "item " .. tostring(id), false
end

local function SetNameOf(id)
    local Tip, D = ns.Tooltip, ns.Data
    if not (Tip and Tip.Lookup and D and D.GetSet) then return nil end
    local ok, v = pcall(Tip.Lookup, id)
    if not ok or v == nil then return nil end
    local sid = type(v) == "table" and v[1] or v
    local set = D:GetSet("c" .. tostring(sid))
    return set and set.name
end

local function DateText(t)
    local A = ns.Alts
    return A and A.DateText and A.DateText(t) or tostring(t)
end

local function LayRight(self, scope)
    local width = (self.scroll:GetWidth() or 0)
    if width < 50 then width = 470 end
    self.child:SetWidth(width)
    local y, n, missing = 0, 0, false
    local function Add(text, font, color)
        n = n + 1
        local fs = Line(self, n, font)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        fs:SetWidth(width - 4)
        fs:SetText(text)
        if color then fs:SetTextColor(color:GetRGB()) end
        fs:Show()
        y = y + math.max(14, fs:GetStringHeight() or 14) + 4
        return fs
    end
    Add(T("P_RECENT", "Recently got"), "normal", Theme.colors.progressHead)
    local recent = self:Recent(scope)
    if #recent == 0 then
        Add(T("P_RECENT_NONE", "Nothing new yet."), "small", Theme.colors.progressNote)
    end
    for _, r in ipairs(recent) do
        local item, loaded = ItemText(r.id)
        if not loaded then missing = true end
        local text = Theme.colors.progressNote:WrapTextInColorCode(DateText(r.t)) .. "  " .. item
        local setName = SetNameOf(r.id)
        if setName then text = text .. "  " .. Theme.colors.subtle:WrapTextInColorCode("(" .. setName .. ")") end
        if r.who then text = text .. " - " .. tostring(r.who) end
        Add(text, "small")
    end
    y = y + 10
    Add(T("P_CHARS", "Your characters"), "normal", Theme.colors.progressHead)
    for _, c in ipairs(self:Chars()) do
        local name = tostring(c.name or "?")
        if c.class then name = Theme.ClassColor(c.class):WrapTextInColorCode(name) end
        local fs = Add(T("P_CHAR_LINE", "%s: %d complete, %d%%"):format(name, c.complete, c.pct), "small")
        fs:SetTextColor(Theme.CountColor(c.have, c.total))
    end
    for i = n + 1, #self.lines do self.lines[i]:Hide() end
    self.child:SetHeight(math.max(10, y))
    -- item names not loaded yet: draw again once they are (a few tries)
    if missing and (self.retries or 0) < 3 and C_Timer and C_Timer.After then
        self.retries = (self.retries or 0) + 1
        C_Timer.After(1, function()
            if self.page and self.page:IsVisible() then cache["recent_" .. scope] = nil; LayRight(self, scope) end
        end)
    elseif not missing then
        self.retries = 0
    end
end

function Progress:Refresh()
    local page = self.page
    if not (page and page:IsVisible()) then return end
    local scope = Progress.Scope()
    if self.scope then
        if self.scope.gsPlain then
            self.scope:SetText(ScopeText(scope))
        elseif self.scope.GenerateMenu then
            pcall(self.scope.GenerateMenu, self.scope)
        end
    end
    local s = self:Get(scope)
    if not s then
        self.pct:SetText(L.LOADING)
        return
    end
    self.pct:SetText(T("P_PCT", "%d%% of set pieces"):format(s.pct))
    self.pct:SetTextColor(Theme.CountColor(s.have, s.total))
    self.summary:SetText(T("P_SUMMARY", "%d complete, %d started, %d / %d pieces"):format(
        s.complete, s.started, s.have, s.total))
    local t = self:TrackedStats()
    if t.sets + t.pieces > 0 then
        self.tracked:SetText(T("P_TRACKED", "Tracked: %d sets and %d pieces, %d pieces still needed"):format(t.sets, t.pieces, t.left))
    else
        self.tracked:SetText(T("P_TRACKED_NONE", "Nothing tracked yet: shift-click a set or a piece to track it."))
    end
    if scope == "account" then
        self.note:SetText(T("P_LEFT_OUT", "Not counted: removed, other-faction, hidden and not-yet-released sets."))
    else
        self.note:SetText(T("P_LEFT_OUT_CHAR", "Not counted: sets your class can't wear, removed, other-faction, hidden and not-yet-released sets."))
    end
    Progress.FillBar(self.total, T("ALL", "All"), s)
    LayBars(self, s)
    LayRight(self, scope)
end
