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
local Theme, L, W = ns.Theme, ns.L, ns.Widgets

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

-- Piece object by item ID (needed for Owned:GetState on tracked pieces): the piece of the
-- first set in list order that has it. No own index: the tooltip's item index names the set
-- (one set -> look only there); items in several sets walk the list.
local function FindIn(set, itemID)
    for _, p in ipairs(set and (set.shown or set.pieces) or {}) do
        if p.itemID == itemID then return p end
    end
end

local function PieceOf(itemID)
    local Tip, D = ns.Tooltip, ns.Data
    if Tip and Tip.Lookup and D and D.GetSet then
        local okL, v = pcall(Tip.Lookup, itemID)
        if okL and v == nil then return nil end
        if okL and type(v) == "number" then
            local okS, set = pcall(D.GetSet, D, "c" .. v)
            return okS and FindIn(set, itemID) or nil
        end
    end
    local sets = AllSets()
    if not sets then return nil end
    for _, set in ipairs(sets) do
        local p = FindIn(set, itemID)
        if p then return p end
    end
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

-- 1.1 beta.2: the 3 sets closest to done. Tracked sets first, then sets this character has
-- started that its class can wear (out now, own faction, not hidden), fewest pieces left
-- first, then effort. -> { { set, left } }.
function Progress.NextTargets(n)
    n = n or 3
    local D, O, TR = ns.Data, ns.Owned, Track
    local out = {}
    if not (D and D.GetSets and O) then return out end
    local mine = D.PlayerFaction and D.PlayerFaction()
    local okC, _, _, cls = pcall(UnitClass, "player")
    if not okC then cls = nil end
    for _, set in ipairs(D:GetSets()) do
        if not set.removed and not set.unreleased and not (set.faction and mine and set.faction ~= mine)
            and not (D.IsHidden and D.IsHidden(set)) then
            local tracked = TR.IsSet(set)
            local have, total = O:SetCount(set)
            if have < total and (tracked or (have > 0 and (not cls or not D.SetForClass or D.SetForClass(set, cls)))) then
                out[#out + 1] = { set = set, left = total - have, tracked = tracked }
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.tracked and true or false) ~= (b.tracked and true or false) then return a.tracked and true or false end
        if a.left ~= b.left then return a.left < b.left end
        local ra = D.EffortRank and D:EffortRank(a.set) or 0
        local rb = D.EffortRank and D:EffortRank(b.set) or 0
        if ra ~= rb then return ra < rb end
        return a.set.name < b.set.name
    end)
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end

-- The next targets for the tooltip (nil when off or none).
local function NextList()
    local db = ns.db
    if type(db) == "table" and db.nextTargets == false then return nil end
    local ok, list = pcall(Progress.NextTargets, 3)
    if not ok or #list == 0 then return nil end
    return list
end

-- One-line form "Next: Devilsaur Armor (1 left), ..." (chat / tests).
function Progress:NextLineText()
    local list = NextList()
    if not list then return nil end
    local parts = {}
    for i, e in ipairs(list) do
        parts[i] = T("NEXT_ITEM", "%s (%d left)"):format(e.set.name, e.left)
    end
    return T("NEXT_LINE", "Next: %s"):format(table.concat(parts, ", "))
end

-- Minimap / broker tooltip: gold "Next:", then up to 3 rows (name left, "n left" grey right),
-- then a blank line before the click hints.
function Progress:AddNextLine(tip)
    if not (tip and tip.AddLine) then return end
    local list = NextList()
    if not list then return end
    local c = Theme.colors
    tip:AddLine(T("NEXT_HEAD", "Next:"), c.tipLabel:GetRGB())
    local nr, ng, nb = c.tipName:GetRGB()
    local gr, gg, gb = c.tipNote:GetRGB()
    for _, e in ipairs(list) do
        local left = T("NEXT_LEFT", "%d left"):format(e.left)
        if tip.AddDoubleLine then
            tip:AddDoubleLine(e.set.name, left, nr, ng, nb, gr, gg, gb)
        else
            tip:AddLine(e.set.name .. "  " .. left, nr, ng, nb)
        end
    end
    local blank = _G.GameTooltip_AddBlankLineToTooltip
    if type(blank) == "function" and tip == GameTooltip then
        blank(tip)
    else
        tip:AddLine(" ")
    end
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
    return T("MS_LINE", "milestone reached - %s!"):format(T("MS_" .. tostring(id), tostring(id)))
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

-- Pure: the "Gear Set:" note when only some pieces fit in the chat line (nil = all fit).
function Progress.ShareFitNote(ok, shown, total)
    if not (ok and type(shown) == "number" and type(total) == "number") then return nil end
    if shown <= 0 or shown >= total then return nil end
    return T("SHARE_FIT", "%d of %d pieces fit in one chat line"):format(shown, total)
end

-- -> ok, why. On a failure SetToChat inserts nothing; we tell the player why in one chat line.
-- When only some links fit, one quiet line says how many (the text itself ends "+N more").
function Progress.Share(set)
    if not (set and set.id and Progress.CanShare()) then return nil end
    local done, ok, shown, total, why = pcall(ns.Share.SetToChat, ns.Share, set.id)
    if not done then return nil end
    local note = Progress.ShareNote(ok, why) or Progress.ShareFitNote(ok, shown, total)
    if note and ns.Print then ns.Print(note) end
    return ok, why
end

-- ---------------------------------------------------------------------------
-- The Progress tab (one full-width inset; Main.lua's UI:AddTab makes the page)
-- Left: the "All" bar, then a scroll area with one bar per content kind and per tier under
-- gold headings with the guide's divider (so new tier tags can never run into the note).
-- Right: a scroll area with "Recently got" (icon, link, set name, date) and one bar row per
-- character (class-coloured name). Bars: Blizzard's ColoredProgressBarTemplate (the bar of
-- Forever's Skills / Reputation pages) when the client has it, else a StatusBar with
-- Theme.art.progressBar's file. Every look comes from Theme.

local LEFT_X, LEFT_W, RIGHT_X = 14, 500, 540
local LABEL_W, PCT_W = 150, 44
local LIST_TOP = -104                 -- top of the left scroll area (under the "All" bar)
local HEAD_H = 24                     -- heading + divider + gap
local RECENT_H, ICON, DATE_W = 20, 16, 70
local KIND_ORDER = ns.SET_KINDS or { "d", "r", "p", "c", "w", "f" }
local TIER_ORDER = { "D1", "D2", "T1", "T2", "T3", "ZG", "AQ20", "AQ40", "PvP" }

local function KindName(k) return L["KIND_" .. k:upper()] or k end
local function TierName(tag)
    local D = ns.Data
    if D and D.TierName then return D.TierName(tag) end
    return L["TIER_" .. tag] or tag
end

local function RowHeight() return Theme.sizes.progressRow or 22 end

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

-- Blizzard's bar (Theme.templates.progressBar), only when it has what we call: a client
-- could have a template of that name without SetFillPercent / Fill / Text.
local function TemplateBar(row)
    local bar, tmpl = Theme.CreateFrame("Frame", nil, row, "progressBar")
    if tmpl and bar and bar.SetFillPercent and bar.Fill and bar.Text then return bar end
    if bar then bar:Hide() end
    return nil
end

-- Our own bar: Theme.art.progressBar's file on a dark backing with a darker edge.
local function PlainBar(row)
    local art = Theme.art.progressBar or {}
    local h = art.height or 14
    local edge = row:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("LEFT", LABEL_W - 1, 0)
    edge:SetPoint("RIGHT", row.pct, "LEFT", -5, 0)
    edge:SetHeight(h + 2)
    if art.edge then edge:SetColorTexture(unpack(art.edge)) end
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("LEFT", LABEL_W, 0)
    bar:SetPoint("RIGHT", row.pct, "LEFT", -6, 0)
    bar:SetHeight(h)
    if bar.SetStatusBarTexture and art.file then bar:SetStatusBarTexture(art.file) end
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if art.bg then bg:SetColorTexture(unpack(art.bg)) end
    local count = bar:CreateFontString(nil, "OVERLAY")
    Theme.Font(count, "small")
    count:SetPoint("CENTER")
    return bar, count
end

-- One bar row: white label, bar with "have / total" on it, % at the right.
function Progress.MakeBar(parent, width)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width or LEFT_W, RowHeight())
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Theme.SetArt(hl, Theme.art.listHover)
    row.label = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.label, "text")                -- white, like the Skills page's names
    row.label:SetPoint("LEFT", 4, 0)
    row.label:SetWidth(LABEL_W - 8)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.pct = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.pct, "small")
    row.pct:SetPoint("RIGHT", -4, 0)
    row.pct:SetWidth(PCT_W)
    row.pct:SetJustifyH("RIGHT")
    local stat = TemplateBar(row)
    if stat then
        local art = Theme.art.progressBar or {}
        stat:SetPoint("LEFT", LABEL_W - 6, 0)    -- the template's track has 6 px padding
        stat:SetPoint("RIGHT", row.pct, "LEFT", 0, 0)
        stat:SetHeight(art.barHeight or 24)
        if stat.EnableMouse then stat:EnableMouse(false) end
        row.stat, row.count = stat, stat.Text
    else
        row.bar, row.count = PlainBar(row)
    end
    row:SetScript("OnEnter", BarTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", BarClick)
    return row
end

-- Template bar fill: the darker green atlas when complete, else the white fill tinted in
-- the count colour (Theme.art.progressBar.tint darkens it so the white count stays readable).
local function FillStat(row, have, total)
    local art = Theme.art.progressBar or {}
    local stat = row.stat
    local complete = total > 0 and have >= total
    local atlas = (complete and Theme.AtlasExists(art.complete)) and art.complete or art.atlas
    if atlas and row.gsFill ~= atlas and Theme.AtlasExists(atlas) then
        stat.Fill:SetAtlas(atlas)
        row.gsFill = atlas
    end
    if complete and row.gsFill and row.gsFill == art.complete then
        stat.Fill:SetVertexColor(1, 1, 1)
    else
        local t = art.tint or 1
        local r, g, b = Theme.CountColor(have, total)
        stat.Fill:SetVertexColor(r * t, g * t, b * t)
    end
    stat:SetFillPercent(total > 0 and have / total or 0)
end

function Progress.FillBar(row, label, g)
    row.group = g
    row.label:SetText(label)
    local have, total = g.have, g.total
    if row.stat then
        FillStat(row, have, total)
    else
        local bar = row.bar
        if bar.SetMinMaxValues then bar:SetMinMaxValues(0, math.max(total, 1)) end
        if bar.SetValue then bar:SetValue(have) end
        if bar.SetStatusBarColor then bar:SetStatusBarColor(Theme.CountColor(have, total)) end
    end
    row.count:SetText(("%d / %d"):format(have, total))
    row.pct:SetText(("%d%%"):format(total > 0 and math.floor(have * 100 / total) or 0))
    row.pct:SetTextColor(Theme.CountColor(have, total))
end

-- Gold heading with the guide page's divider under it (fs.gsLine).
local function Head(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, "normal")
    fs:SetTextColor(Theme.colors.progressHead:GetRGB())
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    line:SetWidth(LEFT_W)
    Theme.SetDivider(line)
    fs.gsLine = line
    return fs
end

local function ShowHead(head, shown)
    head:SetShown(shown)
    head.gsLine:SetShown(shown)
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

-- Scroll frame + child (W.ScrollFrame: bar just outside the right edge, wheel fallback).
local function ScrollList(page, width)
    local scroll = W.ScrollFrame(page)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 10)
    scroll:SetScrollChild(child)
    return scroll, child
end

function Progress:Build(page)
    if self.page then return end
    self.page = page
    self.pct = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.pct, "header")
    self.pct:SetTextColor(Theme.colors.progressHead:GetRGB())
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

    -- Left: bars per content kind and tier, scrolling.
    local left, lchild = ScrollList(page, LEFT_W)
    left:SetPoint("TOPLEFT", LEFT_X, LIST_TOP)
    left:SetPoint("BOTTOMLEFT", LEFT_X, 30)
    left:SetWidth(LEFT_W)
    self.leftScroll, self.leftChild = left, lchild
    self.kindHead = Head(lchild, T("P_BY_KIND", "By content"))
    self.tierHead = Head(lchild, T("P_BY_TIER", "By tier"))
    self.bars = {}

    -- Right: recently got + one bar row per character.
    local scroll, child = ScrollList(page, 400)
    scroll:SetPoint("TOPLEFT", RIGHT_X, -74)
    scroll:SetPoint("BOTTOMRIGHT", -30, 30)
    self.scroll, self.child = scroll, child
    -- 1.1 beta.2: shopping list for crafted pieces of tracked sets / pieces (top, only when any).
    self.shopHead = Head(child, T("SHOP_HEAD", "Shopping list"))
    self.shopRows = {}
    self.shopTotal = child:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.shopTotal, "small")
    self.shopTotal:SetJustifyH("LEFT")
    self.shopTotal:SetWordWrap(false)
    self.shopTotalMoney = child:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.shopTotalMoney, "small")
    self.shopTotalMoney:SetJustifyH("RIGHT")
    self.shopTotalMoney:SetWordWrap(false)
    self.shopNote = child:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.shopNote, "small")
    self.shopNote:SetTextColor(Theme.colors.shopWhere:GetRGB())
    self.shopNote:SetJustifyH("LEFT")
    self.shopNote:SetWordWrap(false)
    self.recentHead = Head(child, T("P_RECENT", "Recently got"))
    self.recentNone = child:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.recentNone, "small")
    self.recentNone:SetTextColor(Theme.colors.progressNote:GetRGB())
    self.recentNone:SetJustifyH("LEFT")
    self.recentNone:SetWordWrap(true)
    self.recentNone:SetText(T("P_RECENT_NONE", "Nothing new yet."))
    self.charHead = Head(child, T("P_CHARS", "Your characters"))
    self.recentRows, self.charRows = {}, {}

    self.note = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.note, "small")
    self.note:SetTextColor(Theme.colors.progressNote:GetRGB())
    self.note:SetPoint("BOTTOMLEFT", LEFT_X, 10)
    self.note:SetText(T("P_LEFT_OUT", "Not counted: removed, other-faction, hidden and not-yet-released sets."))
end

local function Bar(self, i)
    local b = self.bars[i]
    if not b then
        b = Progress.MakeBar(self.leftChild, LEFT_W)
        self.bars[i] = b
    end
    return b
end

-- Bars per kind and tier (only groups with sets), under their headings, in the left list.
local function LayBars(self, s)
    local rowH = RowHeight()
    local y, n = 0, 0
    local function Section(head, order, groups, nameOf, field)
        local any = false
        for _, k in ipairs(order) do if groups[k] then any = true end end
        ShowHead(head, any)
        if not any then return end
        if y > 0 then y = y + 8 end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", self.leftChild, "TOPLEFT", 0, -y)
        y = y + HEAD_H
        for _, k in ipairs(order) do
            local g = groups[k]
            if g then
                n = n + 1
                local b = Bar(self, n)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self.leftChild, "TOPLEFT", 0, -y)
                b.kind, b.tier = nil, nil
                b[field] = k
                Progress.FillBar(b, nameOf(k), g)
                b:Show()
                y = y + rowH
            end
        end
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
    self.leftChild:SetHeight(math.max(10, y + 4))
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

local function ItemIcon(id)
    local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if get then
        local ok, _, _, _, _, icon = pcall(get, id)
        if ok and icon then return icon end
    end
    return 134400
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

local function RecentTooltip(row)
    if not row.itemID then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:Show()
end

-- "Recently got" row: icon, link + set name (grey), date right-aligned in its own column.
local function RecentRow(self, i)
    local r = self.recentRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, self.child)
    r:SetHeight(RECENT_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Theme.SetArt(hl, Theme.art.listHover)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("LEFT", 4, 0)
    if W and W.ICON_CROP then r.icon:SetTexCoord(unpack(W.ICON_CROP)) end
    r.date = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.date, "small")
    r.date:SetTextColor(Theme.colors.progressNote:GetRGB())
    r.date:SetPoint("RIGHT", -4, 0)
    r.date:SetWidth(DATE_W)
    r.date:SetJustifyH("RIGHT")
    r.text = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.text, "small")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", r.date, "LEFT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnEnter", RecentTooltip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(btn)
        if btn.itemID and W and W.HandleModifiedClick then W.HandleModifiedClick(btn.itemID) end
    end)
    self.recentRows[i] = r
    return r
end

-- ---------------------------------------------------------------------------
-- Shopping list rows (1.1 beta.2). One row type: icon, name, then 3 right-hand columns
-- (have / to get / each); a piece row uses the last column, as wide as all 3, for its recipe
-- state; a label row has no icon (gold name, grey column labels).

local function ShopSizes() return Theme.sizes.shop end

-- Price text for the list: no copper at 1g or more; totals also no silver at 100g or more.
local function PriceText(copper, isTotal)
    local S, G = ns.Shopping, ns.Gold
    copper = S and S.RoundPrice and S.RoundPrice(copper, isTotal) or copper
    return G and G.Money and G.Money(copper) or tostring(copper)
end

local function ShopTooltip(row)
    local kind = row.gsKind
    if kind ~= "piece" and kind ~= "mat" then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local c = function(key) return Theme.colors[key]:GetRGB() end
    if kind == "piece" then
        local p = row.gsData
        GameTooltip:SetItemByID(p.itemID)
        if p.recipe then GameTooltip:AddLine(T("SHOP_TIP_RECIPE", "Recipe: %s"):format(p.recipe), c("shopHead")) end
        if p.prof then
            GameTooltip:AddLine(T("SHOP_TIP_SKILL", "%s %d"):format(p.prof, p.skill or 0), c("shopWhere"))
        end
        local text, color = ns.Shopping.StateText(p.state)
        GameTooltip:AddLine(text, c(color))
    else
        local m = row.gsData
        GameTooltip:SetText(m.name, c("shopHead"))
        local parts = m.parts
        if parts then
            GameTooltip:AddLine(T("SHOP_TIP_HAVE", "Have %d: bags %d, bank %d"):format(m.have or 0, parts.bags or 0, parts.bank or 0), c("shopText"))
            for _, a in ipairs(parts.alts or {}) do
                GameTooltip:AddLine(T("SHOP_TIP_ALT", "%s: %d"):format(a.name, a.n), c("shopWhere"))
            end
        end
        if m.where then
            local r, g, b = c("shopText")
            GameTooltip:AddLine(T("SHOP_TIP_GET", "Get it: %s"):format(m.where), r, g, b, true)
        end
        if m.unit then
            local AH, S = ns.AHPrices, ns.Shopping
            local money = PriceText(m.unit)
            local src = AH and AH.SourceName(m.source) or ""
            local age = S.AgeText(m.age)
            local line = age and T("SHOP_TIP_PRICE", "Price %s each (%s, %s)"):format(money, src, age)
                or (money .. " (" .. src .. ")")
            GameTooltip:AddLine(line, c(m.age and m.age > ShopSizes().oldDays and "priceOld" or "shopText"))
        end
        if m.unknown and m.unknown > 0 then GameTooltip:AddLine(T("SHOP_AMOUNTS", "%d mat amounts unknown (?)"):format(m.unknown), c("shopWhere")) end
    end
    GameTooltip:Show()
end

local function ShopRow(self, i)
    local r = self.shopRows[i]
    if r then return r end
    local sz = ShopSizes()
    r = CreateFrame("Button", nil, self.child)
    r:SetHeight(sz.row)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Theme.SetArt(hl, Theme.art.listHover)
    r.gsHl = hl
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(sz.icon, sz.icon)
    r.icon:SetPoint("LEFT", sz.indent, 0)
    if W and W.ICON_CROP then r.icon:SetTexCoord(unpack(W.ICON_CROP)) end
    local function Col(width)
        local fs = r:CreateFontString(nil, "OVERLAY")
        Theme.Font(fs, "small")
        fs:SetWidth(width)
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        return fs
    end
    r.each = Col(sz.each)
    r.each:SetPoint("RIGHT", -4, 0)
    r.get = Col(sz.get)
    r.get:SetPoint("RIGHT", r.each, "LEFT", -4, 0)
    r.have = Col(sz.have)
    r.have:SetPoint("RIGHT", r.get, "LEFT", -4, 0)
    r.name = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.name, "small")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:SetScript("OnEnter", ShopTooltip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(btn)
        local id = btn.gsData and (btn.gsData.itemID or btn.gsData.id)
        if id and W and W.HandleModifiedClick then W.HandleModifiedClick(id) end
    end)
    self.shopRows[i] = r
    return r
end

-- kind "label" / "piece" / "mat"; columns: { have, get, each } texts + colour keys.
local function FillShopRow(r, kind, data, name, cols)
    local sz = ShopSizes()
    r.gsKind, r.gsData = kind, data
    r.gsHl:SetShown(kind ~= "label")
    r.icon:SetShown(kind ~= "label")
    r.name:ClearAllPoints()
    if kind == "label" then
        r.name:SetPoint("LEFT", 4, 0)
        r.name:SetTextColor(Theme.colors.shopHead:GetRGB())
    else
        r.icon:SetTexture(ItemIcon(data.itemID or data.id or 0))
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetTextColor(Theme.colors.shopText:GetRGB())
    end
    r.name:SetText(name)
    local wide = kind == "piece"
    r.each:SetWidth(wide and (sz.have + sz.get + sz.each + 8) or sz.each)
    r.have:SetShown(not wide)
    r.get:SetShown(not wide)
    r.name:SetPoint("RIGHT", wide and r.each or r.have, "LEFT", -6, 0)
    for _, k in ipairs({ "have", "get", "each" }) do
        local col = cols[k]
        r[k]:SetText(col and col[1] or "")
        local c = col and col[2] or "shopText"
        if type(c) == "string" then c = Theme.colors[c] end   -- a colour key or a colour object
        r[k]:SetTextColor(c:GetRGB())
    end
end

local function MatsLeft(list)
    for _, m in ipairs(list.mats) do if m.left > 0 then return true end end
    return false
end

local function PricesOff()
    local db = ns.db
    return type(db) == "table" and db.priceSource == "off"
end

-- The shopping list section from y; returns the new y (unchanged when nothing to craft).
local function LayShopping(self, y, width)
    local S = ns.Shopping
    local ok, list = false, nil
    if self.shopSample then
        ok, list = true, self.shopSample       -- /gs selftest: a made-up list (text fit)
    elseif S and S.List then
        ok, list = pcall(S.List, S)
    end
    if not ok then list = nil end
    self.shopList = list
    local n, missing = 0, false
    local function Row(kind, data, name, cols)
        n = n + 1
        local r = ShopRow(self, n)
        FillShopRow(r, kind, data, name, cols)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        r:SetWidth(width - 4)
        r:Show()
        y = y + ShopSizes().row
    end
    if not list then
        ShowHead(self.shopHead, false)
        self.shopTotal:Hide(); self.shopTotalMoney:Hide(); self.shopNote:Hide()
        for i = 1, #self.shopRows do self.shopRows[i]:Hide() end
        return y, false
    end
    self.shopHead:ClearAllPoints()
    self.shopHead:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
    self.shopHead.gsLine:SetWidth(width - 4)
    ShowHead(self.shopHead, true)
    y = y + HEAD_H
    Row("label", nil, T("SHOP_CRAFT", "To craft"), {})
    for _, p in ipairs(list.pieces) do
        local text, loaded = ItemText(p.itemID)
        if not loaded then missing = true end
        local state, color = S.StateText(p.state)
        Row("piece", p, text, { each = { state, color } })
    end
    y = y + 4
    Row("label", nil, T("SHOP_MATS", "Mats"), { have = { T("SHOP_COL_HAVE", "Have"), "shopWhere" },
        get = { T("SHOP_COL_GET", "To get"), "shopWhere" }, each = { T("SHOP_COL_EACH", "Each"), "shopWhere" } })
    for _, m in ipairs(list.mats) do
        local text = m.name
        if m.id then
            local t2, loaded = ItemText(m.id)
            if loaded then text = t2 else missing = true end
        end
        local done = m.left == 0 and m.unknown == 0
        local get = done and "-" or tostring(m.left)
        if m.unknown > 0 then get = (m.left > 0 and (get .. "+") or "") .. T("SHOP_UNKNOWN", "?") end
        local each
        if m.unit then
            each = { PriceText(m.unit), (m.age and m.age > ShopSizes().oldDays) and "priceOld" or "shopText" }
        end
        -- "6/18" (like Blizzard's reagent lists) in the count colour (green enough, gold some, grey none)
        local have = { T("SHOP_UNKNOWN", "?"), "shopWhere" }
        if m.have and m.need > 0 then
            have = { T("SHOP_HAVE_NEED", "%d/%d"):format(m.have, m.need), Theme.CountColorObj(math.min(m.have, m.need), m.need) }
        elseif m.have then
            have = { tostring(m.have), "shopText" }
        end
        Row("mat", m, text, { have = have, get = { get, done and "shopDone" or "shopText" }, each = each })
    end
    for i = n + 1, #self.shopRows do self.shopRows[i]:Hide() end
    -- "To buy (Auctionator, today)" left, "about 133g" right under the Each column, when a price
    -- addon gave any price.
    local AH = ns.AHPrices
    local total, sum = self.shopTotal, self.shopTotalMoney
    sum:SetText("")
    if list.priced > 0 then
        local src = AH and (AH.SourcesName and AH.SourcesName(list.sources or { list.source }) or AH.SourceName(list.source)) or ""
        local age = S.AgeText(list.age)
        local srcText = age and T("SHOP_SOURCE", "(%s, %s)"):format(src, age) or ("(" .. src .. ")")
        total:SetText(T("SHOP_TOTAL", "To buy %s"):format(srcText))
        sum:SetText(T("SHOP_TOTAL_MONEY", "about %s"):format(PriceText(list.total, true)))
        local old = list.age and list.age > ShopSizes().oldDays
        local r, g, b = Theme.colors[old and "priceOld" or "shopText"]:GetRGB()
        total:SetTextColor(r, g, b); sum:SetTextColor(r, g, b)
    elseif MatsLeft(list) and not PricesOff() then   -- no price addon / no price for anything
        total:SetText(T("SHOP_TOTAL_NONE", "To buy: no price"))
        total:SetTextColor(Theme.colors.shopWhere:GetRGB())
    else
        total:SetText("")
    end
    total:SetShown(total:GetText() ~= "" and total:GetText() ~= nil)
    sum:SetShown(total:IsShown() and sum:GetText() ~= "")
    if total:IsShown() then
        local sz = ShopSizes()
        sum:ClearAllPoints()
        sum:SetPoint("TOPRIGHT", self.child, "TOPLEFT", width - 8, -(y + 2))
        sum:SetWidth(sz.each)
        total:ClearAllPoints()
        total:SetPoint("TOPLEFT", self.child, "TOPLEFT", 4, -(y + 2))
        total:SetWidth(width - 12 - (sum:IsShown() and sz.each or 0))
        y = y + 16
    end
    -- notes: a partial total ("2 without a price"), unknown amounts
    local note, notes = self.shopNote, {}
    if list.priced > 0 and list.unpriced > 0 then notes[#notes + 1] = T("SHOP_UNPRICED", "%d without a price"):format(list.unpriced) end
    if list.unknownAmounts > 0 then notes[#notes + 1] = T("SHOP_AMOUNTS", "%d mat amounts unknown (?)"):format(list.unknownAmounts) end
    note:SetShown(#notes > 0)
    if #notes > 0 then
        note:SetText(table.concat(notes, ", "))
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", self.child, "TOPLEFT", 4, -(y + 2))
        note:SetWidth(width - 8)
        y = y + 16
    end
    return y + 12, missing
end

local function LayRight(self, scope)
    local width = (self.scroll:GetWidth() or 0)
    if width < 50 then width = 470 end
    self.child:SetWidth(width)
    local y, missing = LayShopping(self, 0, width)
    local function PlaceHead(head)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        head.gsLine:SetWidth(width - 4)
        ShowHead(head, true)
        y = y + HEAD_H
    end
    PlaceHead(self.recentHead)
    local recent = self:Recent(scope)
    local none = self.recentNone
    none:SetShown(#recent == 0)
    if #recent == 0 then
        none:ClearAllPoints()
        none:SetPoint("TOPLEFT", self.child, "TOPLEFT", 4, -y)
        none:SetWidth(width - 8)
        y = y + math.max(14, none:GetStringHeight() or 14) + 4
    end
    for i, r in ipairs(recent) do
        local row = RecentRow(self, i)
        local item, loaded = ItemText(r.id)
        if not loaded then missing = true end
        local setName = SetNameOf(r.id)
        local extra = setName
        if r.who then extra = T("P_RECENT_WHO", "%s (%s)"):format(setName or "", tostring(r.who)) end
        local text = item
        if extra and extra ~= "" then text = text .. "  " .. Theme.colors.progressNote:WrapTextInColorCode(extra) end
        row.itemID = r.id
        row.icon:SetTexture(ItemIcon(r.id))
        row.text:SetText(text)
        row.date:SetText(DateText(r.t))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        row:SetWidth(width - 4)
        row:Show()
        y = y + RECENT_H
    end
    for i = #recent + 1, #self.recentRows do self.recentRows[i]:Hide() end
    y = y + 12
    PlaceHead(self.charHead)
    local rowH = RowHeight()
    local chars = self:Chars()
    for i, c in ipairs(chars) do
        local b = self.charRows[i]
        if not b then
            b = Progress.MakeBar(self.child, width - 4)
            self.charRows[i] = b
        end
        b:SetWidth(width - 4)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        local name = tostring(c.name or "?")
        if c.class then name = Theme.ClassColor(c.class):WrapTextInColorCode(name) end
        Progress.FillBar(b, name, c)
        b:Show()
        y = y + rowH
    end
    for i = #chars + 1, #self.charRows do self.charRows[i]:Hide() end
    self.child:SetHeight(math.max(10, y + 4))
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

-- "38% of set pieces": the line stays gold (a page title), only the number is coloured.
local function PctTitle(s)
    local fmt = T("P_PCT", "%d%% of set pieces")
    local num = Theme.CountColorObj(s.have, s.total):WrapTextInColorCode(("%d%%"):format(s.pct))
    local withS, n = fmt:gsub("%%d%%%%", "%%s", 1)
    if n == 1 then return withS:format(num) end
    return fmt:format(s.pct)
end
Progress.PctTitle = PctTitle

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
    self.pct:SetText(PctTitle(s))
    self.pct:SetTextColor(Theme.colors.progressHead:GetRGB())
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
