-- Gear Set: alt memory (beta.7). Remembers which set pieces each of this account's own
-- characters has equipped, in bags, bank, mailbox and on the keyring, plus the account bank
-- when the game lets us read it. Contract for other files: plans\v1.0.0\beta7-interface.md.
--
-- Only item IDs of set pieces (ns.ClassicSets) are kept, as sorted "id,id" strings.
-- Reading: equipped/bags/keyring after bag or gear changes (one debounced scan, never in
-- combat), bank while the bank is open, mail on MAIL_INBOX_UPDATE while the mailbox is open,
-- account bank while the bank is open (read-only; nothing is ever moved, taken or sent).
-- Writing to GearSetDB: only at logout and bank close (Save). Until then the current
-- character's data lives in memory (`live`), and the public calls read that.
-- Alt names stay in SavedVariables: never in /gs selftest or "Report a problem" texts.
local _, ns = ...

local Alts = {}
ns.Alts = Alts

local PLACES = { "equipped", "bags", "bank", "mail", "keyring" }
local ACCOUNT_KEY = "#account"
local DAY = 86400
Alts.PLACES, Alts.ACCOUNT_KEY = PLACES, ACCOUNT_KEY

local function Now()
    local t = type(time) == "function" and time() or 0
    return type(t) == "number" and t or 0
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function Num(v) return type(v) == "number" and v == v and v or nil end

-- ---------------------------------------------------------------------------
-- Set items and id strings

local setItems
-- itemID -> a true value for every piece in the bundled set table (built once, no API calls).
-- Shares the tooltip's item index (values there are set IDs) instead of a second copy;
-- own table of `true` only when Tooltip.lua isn't loaded.
function Alts.SetItems()
    if setItems then return setItems end
    local Tip = ns.Tooltip
    if Tip and type(Tip.Index) == "function" then
        local ok, idx = pcall(Tip.Index)
        if ok and type(idx) == "table" then
            setItems = idx
            return setItems
        end
    end
    setItems = {}
    local tbl = ns.ClassicSets
    if type(tbl) == "table" then
        for _, e in pairs(tbl) do
            if type(e) == "table" then
                for _, list in ipairs({ e.i, e.up }) do
                    if type(list) == "table" then
                        for _, id in ipairs(list) do
                            if type(id) == "number" then setItems[id] = true end
                        end
                    end
                end
            end
        end
    end
    return setItems
end

-- { [id] = true } -> "id,id,..." (sorted, so the same items always give the same string).
function Alts.Encode(set)
    local ids = {}
    if type(set) == "table" then
        for id in pairs(set) do
            if type(id) == "number" then ids[#ids + 1] = id end
        end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- "id,id" -> { [id] = true }; anything else -> empty set.
function Alts.Decode(s)
    local out = {}
    if type(s) == "string" then
        for d in s:gmatch("%d+") do out[tonumber(d)] = true end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Who am I

local myKey, myName, myRealm
function Alts:MyKey()
    if myKey then return myKey end
    local okN, name = Call(UnitName, "player")
    if not okN or type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    local realm
    local okR, r = Call(GetNormalizedRealmName)
    if okR and type(r) == "string" and r ~= "" then realm = r end
    if not realm then
        local okG, g = Call(GetRealmName)
        realm = (okG and type(g) == "string") and g:gsub("[%s%-]", "") or "?"
    end
    myName, myRealm = name, realm
    myKey = name .. "-" .. realm
    return myKey
end

local function MyClass()
    local ok, _, file = Call(UnitClass, "player")
    return ok and type(file) == "string" and file or nil
end

local function DB()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.chars) ~= "table" then return nil end     -- PrepareDB makes it; never replaced here
    return db
end

-- ---------------------------------------------------------------------------
-- Live state of the current character: place -> { [id] = true } (nil = not read yet,
-- then the saved string counts), dates[place] = when it was read.

local live = { dates = {} }
local liveDone = {}                 -- setID -> epoch, completions not saved yet
local account = { items = nil, date = 0, readable = nil, checked = 0, api = nil }
local loaded = false
local index, charItems, accountItems
local EMPTY = {}

local function Dirty()
    index, charItems, accountItems = nil, nil, nil
end

-- At login: start from the saved record (bank / mail / keyring dates kept).
local function LoadLive()
    if loaded then return end
    local db, key = DB(), Alts:MyKey()
    if not (db and key) then return end
    loaded = true
    local rec = db.chars[key]
    if type(rec) == "table" and type(rec.places) == "table" then
        local dates = type(rec.dates) == "table" and rec.dates or EMPTY
        for _, place in ipairs(PLACES) do
            if type(rec.places[place]) == "string" and live[place] == nil then
                live[place] = Alts.Decode(rec.places[place])
                live.dates[place] = Num(dates[place]) or Num(rec.seen) or 0
            end
        end
    end
    -- 1.1 beta.2: the saved mat counts (bank part only changes at a bank visit)
    if type(rec) == "table" and type(rec.mats) == "string" and live.mats == nil then
        live.mats = Alts.DecodeMats(rec.mats)
    end
    local acc = db.account
    if type(acc) == "table" then
        if type(acc.bank) == "string" then
            account.items = Alts.Decode(acc.bank)
            account.date = Num(acc.date) or 0
        end
        if type(acc.readable) == "boolean" then account.readable = acc.readable end
        account.checked = Num(acc.checked) or 0
    end
    Dirty()
end

-- ---------------------------------------------------------------------------
-- Scans (each in pcall; results only for set items)

local function Secret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s and true or false
end

local function Add(out, id, items)
    if type(id) == "number" and not Secret(id) and items[id] then out[id] = true end
end

local function ScanContainer(bag, out, items)
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemID) then return false end
    local ok, n = pcall(C.GetContainerNumSlots, bag)
    n = ok and not Secret(n) and Num(n) or 0
    for slot = 1, n do
        local okI, id = pcall(C.GetContainerItemID, bag, slot)
        if okI then Add(out, id, items) end
    end
    return n > 0
end

function Alts.ScanEquipped(items)
    local out = {}
    for slot = 1, 19 do
        local ok, id = Call(GetInventoryItemID, "player", slot)
        if ok then Add(out, id, items) end
    end
    return out
end

function Alts.ScanBags(items)
    local out = {}
    local last = Num(NUM_BAG_SLOTS) or 4
    for bag = 0, last do ScanContainer(bag, out, items) end
    return out
end

-- Keyring: Enum.BagIndex.Keyring (-1 on Forever, -2 on Classic Era); nil when the game has none.
local function KeyringBag()
    local E = type(Enum) == "table" and rawget(Enum, "BagIndex")
    local id = type(E) == "table" and rawget(E, "Keyring") or nil
    if type(id) ~= "number" then id = KEYRING_CONTAINER end
    if type(id) == "number" and id < 0 then return id end
end

function Alts.ScanKeyring(items)
    local bag = KeyringBag()
    if not bag then return nil end
    local out = {}
    ScanContainer(bag, out, items)
    return out
end

-- Bank by count (bank + bags minus bags): works with any bank layout. Returns the set and
-- whether the count gave anything (no bank data at all looks the same as an empty bank).
function Alts.ScanBank(items)
    local out, any = {}, false
    local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    if type(GetCount) ~= "function" then return out, false end
    for id in pairs(items) do
        local okA, all = pcall(GetCount, id, true)
        local okB, bags = pcall(GetCount, id)
        all, bags = okA and Num(all) or 0, okB and Num(bags) or 0
        if all > bags then out[id] = true; any = true end
    end
    return out, any
end

function Alts.ScanMail(items)
    if type(GetInboxNumItems) ~= "function" or type(GetInboxItemLink) ~= "function" then return nil end
    local ok, n = pcall(GetInboxNumItems)
    n = ok and Num(n) or 0
    local out = {}
    local per = Num(ATTACHMENTS_MAX_RECEIVE) or 16
    for i = 1, n do
        for j = 1, per do
            local okL, link = pcall(GetInboxItemLink, i, j)
            if okL and type(link) == "string" then
                Add(out, tonumber(link:match("item:(%d+)")), items)
            end
        end
    end
    return out
end

-- Account (warband) bank: only when the game says it can be viewed and has slots.
-- Returns items or nil, readable (true/false), apiThere.
local function AccountTabs()
    local E = type(Enum) == "table" and rawget(Enum, "BagIndex")
    local tabs = {}
    if type(E) == "table" then
        for i = 1, 5 do
            local id = rawget(E, "AccountBankTab_" .. i)
            if type(id) == "number" then tabs[#tabs + 1] = id end
        end
    end
    return tabs
end

function Alts.ScanAccount(items)
    local B = C_Bank
    local BT = type(Enum) == "table" and rawget(Enum, "BankType")
    local acc = type(BT) == "table" and rawget(BT, "Account") or nil
    local tabs = AccountTabs()
    if not (type(B) == "table" and type(B.CanViewBank) == "function" and type(acc) == "number" and #tabs > 0) then
        return nil, false, false
    end
    local ok, can = pcall(B.CanViewBank, acc)
    if not (ok and can == true) then return nil, false, true end
    local out, slots = {}, false
    for _, bag in ipairs(tabs) do
        if ScanContainer(bag, out, items) then slots = true end
    end
    if not slots then return nil, false, true end
    return out, true, true
end

-- ---------------------------------------------------------------------------
-- Debounced scans (one timer; in combat they wait for PLAYER_REGEN_ENABLED)

local pending, timerOn = {}, false
local state = { bankOpen = false, bankRead = false, mailOpen = false }
local frame

local function Changed()
    Dirty()
    if ns.Owned and ns.Owned.Changed then ns.Owned:Changed() end
end

local function RunScans()
    timerOn = false
    if InCombat() then
        if frame then ns.SafeRegister(frame, "PLAYER_REGEN_ENABLED") end
        return
    end
    LoadLive()
    local items, t = Alts.SetItems(), Now()
    local any = false
    if pending.bags then
        live.equipped, live.dates.equipped = Alts.ScanEquipped(items), t
        live.bags, live.dates.bags = Alts.ScanBags(items), t
        local k = Alts.ScanKeyring(items)
        if k then live.keyring, live.dates.keyring = k, t end
        Alts.CountMats(false)
        any = true
    end
    if pending.bank and state.bankOpen then
        live.bank, live.dates.bank = Alts.ScanBank(items), t
        Alts.CountMats(true)
        state.bankRead = true
        local got, readable, api = Alts.ScanAccount(items)
        account.api, account.readable, account.checked = api, readable, t
        if got then account.items, account.date = got, t end
        any = true
    end
    if pending.mail and state.mailOpen then
        local m = Alts.ScanMail(items)
        if m then live.mail, live.dates.mail = m, t; any = true end
    end
    wipe(pending)
    if any then Changed() end
end

local function Schedule(kind, delay)
    pending[kind] = true
    if timerOn then return end
    timerOn = true
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 1, RunScans)
    else
        RunScans()
    end
end

-- Write the current character's data (and account bank) into GearSetDB.
-- Called at logout and bank close only.
function Alts:Save()
    local db, key = DB(), self:MyKey()
    if not (db and key) then return end
    LoadLive()
    local rec = db.chars[key]
    if type(rec) ~= "table" then rec = {}; db.chars[key] = rec end
    rec.name, rec.realm = myName, myRealm
    rec.class = MyClass() or rec.class
    rec.seen = Now()
    if type(rec.places) ~= "table" then rec.places = {} end
    if type(rec.dates) ~= "table" then rec.dates = {} end
    for _, place in ipairs(PLACES) do
        if live[place] ~= nil then
            rec.places[place] = Alts.Encode(live[place])
            rec.dates[place] = Num(live.dates[place]) or rec.seen
        end
    end
    -- 1.1 beta.2 (Shopping.lua): mats on the list, professions, known list recipes.
    if live.mats then rec.mats = Alts.EncodeMats(live.mats) end
    -- 1.1 beta.6 (DB v9): this character's standing and chain quest flags (Steps.Snapshot; ToS S3:
    -- own character only, our faction and chain quest IDs only). Nothing read -> the old values stay.
    local S = ns.Steps
    if S and S.Snapshot then
        local okS, snap = pcall(S.Snapshot)
        if okS and type(snap) == "table" then
            if snap.rep then
                -- merged per faction (b6-pretest finding 5): a faction unreadable this time keeps its old row
                local merged = {}
                if type(rec.rep) == "table" then for k, v in pairs(rec.rep) do merged[k] = v end end
                for k, v in pairs(snap.rep) do merged[k] = v end
                rec.rep = merged
            end
            if snap.quests then rec.quests = snap.quests end
        end
    end
    local prof = Alts.ReadProfessions()
    if prof then rec.prof = Alts.EncodeNums(prof) end
    local rcp = Alts.ReadRecipes()
    if rcp then rec.recipes = Alts.EncodeList(rcp) end
    if next(liveDone) then
        if type(rec.done) ~= "table" then rec.done = {} end
        for id, t in pairs(liveDone) do
            if rec.done[id] == nil then rec.done[id] = t end
        end
        wipe(liveDone)
    end
    if type(db.account) ~= "table" then db.account = {} end
    local acc = db.account
    if account.readable ~= nil then
        acc.readable, acc.checked = account.readable, account.checked
    end
    if account.items and account.readable then
        acc.bank, acc.date = Alts.Encode(account.items), account.date
    end
    Dirty()
end

local function OnEvent(_, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        LoadLive()
        Schedule("bags", 3)
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        -- bags/equipped only; the bank is read once on open and once on close (each read
        -- is ~2 GetItemCount calls per set item, too much for every bag update)
        Schedule("bags", 1)
    elseif event == "BANKFRAME_OPENED" then
        state.bankOpen = true
        Schedule("bank", 0.5)
    elseif event == "BANKFRAME_CLOSED" then
        if state.bankOpen and not InCombat() then
            -- last look before it closes for good, then save
            pending.bank = true
            RunScans()
            Alts:Save()
        end
        state.bankOpen = false
    elseif event == "MAIL_SHOW" then
        state.mailOpen = true
    elseif event == "MAIL_INBOX_UPDATE" then
        if state.mailOpen then Schedule("mail", 0.5) end
    elseif event == "MAIL_CLOSED" then
        state.mailOpen = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        if frame then frame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        if next(pending) then Schedule("bags", 0.5) end
    elseif event == "PLAYER_LOGOUT" then
        -- Logout: read what is always readable. The bank and account bank lists only ever
        -- come from a read while the bank is open (kept from bank close, or the saved
        -- ones): a count at logout may not see the bank and would wipe a good list.
        LoadLive()
        local items, t = Alts.SetItems(), Now()
        local okE, eq = pcall(Alts.ScanEquipped, items)
        if okE then live.equipped, live.dates.equipped = eq, t end
        local okB, bags = pcall(Alts.ScanBags, items)
        if okB then live.bags, live.dates.bags = bags, t end
        local okK, k = pcall(Alts.ScanKeyring, items)
        if okK and k then live.keyring, live.dates.keyring = k, t end
        pcall(Alts.CountMats, false)
        Alts:Save()
    end
end

-- Called by Core on ADDON_LOADED (after InitDB).
function Alts:Init()
    if frame then return end
    frame = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
        "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
        "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "PLAYER_LOGOUT" }) do
        ns.SafeRegister(frame, e)
    end
    frame:SetScript("OnEvent", OnEvent)
end

-- ---------------------------------------------------------------------------
-- Index: itemID -> holders, char key -> items (rebuilt lazily after any change)

local function CharName(key, rec)
    if type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" then return rec.name end
    return (tostring(key):match("^([^%-]+)")) or tostring(key)
end

-- Pure: builds the index from a DB table, the current key and live data (also used by
-- /gs selftest on copies). Returns idx[itemID] = { holder, ... }, perChar[key] = { [id] = true },
-- accountSet.
function Alts.BuildIndex(db, me, liveData, accountData)
    local idx, per = {}, {}
    local function Put(id, h)
        local l = idx[id]
        if not l then l = {}; idx[id] = l end
        l[#l + 1] = h
    end
    local chars = type(db) == "table" and type(db.chars) == "table" and db.chars or EMPTY
    local keys = {}
    for key, rec in pairs(chars) do
        if type(key) == "string" and type(rec) == "table" and key ~= me then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        local na, nb = CharName(a, chars[a]), CharName(b, chars[b])
        if na ~= nb then return na < nb end
        return a < b
    end)
    for _, key in ipairs(keys) do
        local rec = chars[key]
        local name, items = CharName(key, rec), {}
        per[key] = items
        local places = type(rec.places) == "table" and rec.places or EMPTY
        local dates = type(rec.dates) == "table" and rec.dates or EMPTY
        for _, place in ipairs(PLACES) do
            if type(places[place]) == "string" then
                local seen = Num(dates[place]) or Num(rec.seen) or 0
                for d in places[place]:gmatch("%d+") do
                    local id = tonumber(d)
                    items[id] = true
                    Put(id, { name = name, key = key, where = place, seen = seen })
                end
            end
        end
    end
    if me then
        local items = {}
        per[me] = items
        local rec = chars[me]
        local name = type(rec) == "table" and CharName(me, rec) or (me:match("^([^%-]+)") or me)
        liveData = liveData or EMPTY
        local dates = type(liveData.dates) == "table" and liveData.dates or EMPTY
        for _, place in ipairs(PLACES) do
            local set = liveData[place]
            if type(set) == "table" then
                local ids = {}
                for id in pairs(set) do ids[#ids + 1] = id end
                table.sort(ids)
                for _, id in ipairs(ids) do
                    items[id] = true
                    Put(id, { name = name, key = me, where = place, seen = Num(dates[place]) or 0 })
                end
            end
        end
    end
    local accSet = {}
    if type(accountData) == "table" and type(accountData.items) == "table" then
        local name = (ns.L and ns.L.ALT_ACCOUNT) or "Account bank"
        local ids = {}
        for id in pairs(accountData.items) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            accSet[id] = true
            Put(id, { name = name, key = ACCOUNT_KEY, where = "account", seen = Num(accountData.date) or 0 })
        end
    end
    return idx, per, accSet
end

local function Index()
    if index then return index end
    LoadLive()
    -- account.items is only ever set by a good read (a later failed read keeps it).
    index, charItems, accountItems = Alts.BuildIndex(DB(), Alts:MyKey(), live, account)
    return index
end

-- ---------------------------------------------------------------------------
-- Public calls (plans\v1.0.0\beta7-interface.md)

function Alts:GetHolders(itemID)
    if type(itemID) ~= "number" then return EMPTY end
    return Index()[itemID] or EMPTY
end

-- Other characters' holders only (piece rows: "Also on: ...").
function Alts:OthersHolding(itemID)
    local out, me = {}, self:MyKey()
    for _, h in ipairs(self:GetHolders(itemID)) do
        if h.key ~= me then out[#out + 1] = h end
    end
    return out
end

function Alts:Chars()
    local out, db, me = {}, DB(), self:MyKey()
    local chars = db and db.chars or EMPTY
    for key, rec in pairs(chars) do
        if type(key) == "string" and type(rec) == "table" then
            out[#out + 1] = { key = key, name = CharName(key, rec),
                realm = type(rec.realm) == "string" and rec.realm or (key:match("%-(.+)$")),
                class = type(rec.class) == "string" and rec.class or nil,
                seen = Num(rec.seen) or 0, me = (key == me) or nil }
        end
    end
    if me and not chars[me] then
        out[#out + 1] = { key = me, name = myName or me, realm = myRealm, class = MyClass(), seen = Now(), me = true }
    end
    table.sort(out, function(a, b)
        if (a.me and true or false) ~= (b.me and true or false) then return a.me and true or false end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    return out
end

local function SetIDOf(setID)
    if type(setID) == "number" then return setID end
    if type(setID) == "string" then return tonumber(setID:match("^c?(%d+)$")) end
end

-- Pieces that count for a set (like Data's set.pieces) without building the set list.
local rawPieces = {}
function Alts.SetPieceIDs(id)
    local D = ns.Data
    local built = D and type(D.byKey) == "table" and D.byKey["c" .. id]
    if built and type(built.pieces) == "table" then
        local out = {}
        for _, p in ipairs(built.pieces) do out[#out + 1] = p.itemID end
        return out, built
    end
    if rawPieces[id] then return rawPieces[id] end
    local e = type(ns.ClassicSets) == "table" and ns.ClassicSets[id]
    local out = {}
    if type(e) == "table" and type(e.i) == "table" then
        local whole = e.u == 1 or e.u == true
        local up = {}
        if type(e.up) == "table" then for _, x in ipairs(e.up) do up[x] = true end end
        local later = D and D.AllSourcesLater
        local all = {}
        for _, x in ipairs(e.i) do
            if type(x) == "number" then
                all[#all + 1] = x
                local isLater = whole or up[x] or (later and later(x))
                if not isLater or whole then out[#out + 1] = x end
            end
        end
        if #out == 0 then out = all end    -- every piece not out yet: the whole set counts
    end
    rawPieces[id] = out
    return out
end

function Alts:IsCompleted(setID, charKey)
    local id = SetIDOf(setID)
    if not id then return nil end
    local me = self:MyKey()
    charKey = charKey or me
    if charKey == me and liveDone[id] then return liveDone[id] end
    local db = DB()
    local rec = db and charKey and db.chars[charKey]
    local done = type(rec) == "table" and type(rec.done) == "table" and rec.done or nil
    return done and Num(done[id]) or nil
end

-- A set of the current character is complete: remember the date (saved at logout).
function Alts:MarkCompleted(setID)
    local id = SetIDOf(setID)
    if not id or self:IsCompleted(id) then return end
    liveDone[id] = Now()
end

-- 1.1.1 "Check finished sets again" (Settings): finished dates saved before items-only counting
-- may have come from collected looks. Every saved finished set (each own character, plus this
-- character's unsaved ones) whose items that character doesn't own now has its date moved to
-- rec.doneOld[setID] (oldest date; other dates of that set in rec.doneOldMore[setID], a list;
-- broken saved values kept under "<field>Bad"; nothing is deleted). dry = only count.
-- This character: Owned:ItemCount on the built set (sets with pieces this client doesn't know
-- are skipped); other characters: their last saved items (+ the account bank), and only once
-- Gear Set has seen their bank (never read / bank never seen -> left alone).
-- Returns the number of dates moved (or that would be moved).
function Alts:RecheckDone(dry)
    local db = DB()
    if not db then return 0 end
    local me = self:MyKey()
    local O, D = ns.Owned, ns.Data
    Index()
    local function OwnsAll(key, id, rec)
        if key == me then
            local set = D and D.GetSet and D:GetSet("c" .. id)
            if not (set and O and O.ItemCount) then return true end      -- unknown set: leave it
            if O.UnknownCount and O.UnknownCount(set) > 0 then return true end
            local have, total = O:ItemCount(set)
            return total == 0 or have >= total
        end
        -- nothing ever read for that character (no places saved): leave its dates alone
        if not (type(rec) == "table" and type(rec.places) == "table" and next(rec.places)) then return true end
        -- its bank was never seen: the items may be there, so leave its dates alone too
        if rec.places.bank == nil then return true end
        local items = charItems and charItems[key] or {}
        local pieces = Alts.SetPieceIDs(id)
        for _, x in ipairs(pieces) do
            if not (items[x] or (accountItems and accountItems[x])) then return false end
        end
        return true
    end
    local moved = 0
    -- A broken (non-table) saved value is kept under the first free side key, never overwritten.
    local function TableAt(rec, field)
        local cur = rec[field]
        if type(cur) == "table" then return cur end
        if cur ~= nil then
            local side, n = field .. "Bad", 1
            while rec[side] ~= nil do n = n + 1; side = field .. "Bad" .. n end
            rec[side] = cur
        end
        rec[field] = {}
        return rec[field]
    end
    -- doneOld[id] holds the oldest date; every other date of that set goes into the list
    -- doneOldMore[id] (so a second recheck after buying and selling again loses nothing).
    local function Move(key, rec, id, t)
        moved = moved + 1
        if dry then return end
        local old = TableAt(rec, "doneOld")
        local cur = old[id]
        if cur == nil then old[id] = t; return end
        if cur == t then return end
        local more = TableAt(rec, "doneOldMore")
        if type(more[id]) ~= "table" then
            if more[id] ~= nil then TableAt(more, id) else more[id] = {} end
        end
        local list = more[id]
        if Num(cur) and cur <= t then
            list[#list + 1] = t
        else
            list[#list + 1] = cur              -- a newer or broken old value moves to the list
            old[id] = t
        end
    end
    for key, rec in pairs(db.chars) do
        if type(key) == "string" and type(rec) == "table" and type(rec.done) == "table" then
            for id, t in pairs(rec.done) do
                if type(id) == "number" and Num(t) and not OwnsAll(key, id, rec) then
                    Move(key, rec, id, t)
                    if not dry then rec.done[id] = nil end
                end
            end
        end
    end
    -- this character's finished sets not saved yet (saved at logout)
    if me then
        for id, t in pairs(liveDone) do
            if not OwnsAll(me, id) then
                if dry then
                    moved = moved + 1
                else
                    if type(db.chars[me]) ~= "table" then db.chars[me] = { name = myName, realm = myRealm } end
                    Move(me, db.chars[me], id, t)
                    liveDone[id] = nil
                end
            end
        end
    end
    if not dry and moved > 0 then
        Dirty()
        if O and O.Invalidate then O:Invalidate() end
        if ns.Progress and ns.Progress.Invalidate then pcall(ns.Progress.Invalidate, ns.Progress) end
    end
    return moved
end

function Alts:GetSetProgress(setID, charKey)
    local id = SetIDOf(setID)
    if not id then return 0, 0 end
    local pieces, built = Alts.SetPieceIDs(id)
    local total = #pieces
    if total == 0 then return 0, 0 end
    local me = self:MyKey()
    charKey = charKey or me
    if self:IsCompleted(id, charKey) then return total, total end
    if charKey == me and built and ns.Owned and ns.Owned.SetCount then
        local ok, have, tot = pcall(ns.Owned.SetCount, ns.Owned, built)
        if ok and type(have) == "number" then return have, tot or total end
    end
    Index()
    local items = charKey and charItems and charItems[charKey]
    if not items then return 0, total end
    local have = 0
    for _, x in ipairs(pieces) do
        if items[x] or (accountItems and accountItems[x]) then have = have + 1 end
    end
    return have, total
end

-- Owned: where the current character keeps an item outside bags/bank/equipped
-- ("mail" / "keyring" / "account"), and when that place was seen.
function Alts:MyPlace(itemID)
    LoadLive()
    if live.mail and live.mail[itemID] then return "mail", live.dates.mail end
    if live.keyring and live.keyring[itemID] then return "keyring", live.dates.keyring end
    if account.items and account.items[itemID] then return "account", account.date end
    return nil
end

-- "seen today" / "seen yesterday" / "seen 12 days ago" (nil when the date is unknown).
function Alts.SeenText(t)
    t = Num(t)
    if not t or t <= 0 then return nil end
    local L = ns.L or EMPTY
    local days = math.floor((Now() - t) / DAY)
    if days <= 0 then return L.ALT_SEEN_TODAY or "seen today" end
    if days == 1 then return L.ALT_SEEN_1 or "seen yesterday" end
    return (L.ALT_SEEN_N or "seen %d days ago"):format(days)
end

function Alts.DateText(t)
    t = Num(t)
    if not t or t <= 0 or type(date) ~= "function" then return nil end
    local ok, s = pcall(date, "%Y-%m-%d", t)
    return ok and s or nil
end

function Alts.WhereText(where)
    local L = ns.L or EMPTY
    return L["ALT_WHERE_" .. tostring(where)] or tostring(where)
end

-- Remove a saved character (Settings' "Forget a character"). The current one can't be
-- forgotten (it would be saved again at logout).
function Alts:Forget(key)
    local db = DB()
    if not (db and type(key) == "string") or key == self:MyKey() then return false end
    if db.chars[key] == nil then return false end
    db.chars[key] = nil
    Changed()
    return true
end

-- For /gs selftest: counts only, no names.
function Alts:Stats()
    local db = DB()
    local n, ids = 0, 0
    for _, rec in pairs(db and db.chars or EMPTY) do
        if type(rec) == "table" then
            n = n + 1
            for _, place in ipairs(PLACES) do
                local s = type(rec.places) == "table" and rec.places[place]
                if type(s) == "string" then for _ in s:gmatch("%d+") do ids = ids + 1 end end
            end
        end
    end
    return n, ids
end

-- Account bank state for /gs selftest: apiThere, readable now (nil = not at a bank),
-- last result at a bank (true / false / nil = never at a bank), when.
function Alts:AccountStatus()
    LoadLive()
    local _, readable, api = Alts.ScanAccount(EMPTY)
    local now
    if state.bankOpen then now = readable end
    return api, now, account.readable, account.checked
end

-- ---------------------------------------------------------------------------
-- 1.1 beta.2: mats, professions and recipes (Shopping.lua). Only the shopping mats (<= 29 IDs
-- from GuideData `mats`) and the data's recipe spells are read; own characters only (W8).

local function Whole(v) return type(v) == "number" and v == math.floor(v) and v >= 0 and v < 2 ^ 31 end

-- "id:bags:bank,..." (zeros left out) <-> { [id] = { bags, bank } }.
function Alts.EncodeMats(m)
    local ids = {}
    for id, c in pairs(m) do
        if Whole(id) and type(c) == "table" and ((c[1] or 0) > 0 or (c[2] or 0) > 0) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local parts = {}
    for i, id in ipairs(ids) do parts[i] = ("%d:%d:%d"):format(id, m[id][1] or 0, m[id][2] or 0) end
    return table.concat(parts, ",")
end

function Alts.DecodeMats(s)
    local out = {}
    if type(s) ~= "string" then return out end
    for id, b, k in s:gmatch("(%d+):(%d+):(%d+)") do
        out[tonumber(id)] = { tonumber(b), tonumber(k) }
    end
    return out
end

-- { [k] = n } <-> "k:n,..."; { [k] = true } <-> "k,...".
function Alts.EncodeNums(t)
    local keys = {}
    for k, v in pairs(t) do if Whole(k) and Whole(v) then keys[#keys + 1] = k end end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do parts[i] = k .. ":" .. t[k] end
    return table.concat(parts, ",")
end

function Alts.DecodeNums(s)
    local out = {}
    if type(s) ~= "string" then return out end
    for k, v in s:gmatch("(%d+):(%d+)") do out[tonumber(k)] = tonumber(v) end
    return out
end

function Alts.EncodeList(t)
    local keys = {}
    for k, v in pairs(t) do if Whole(k) and v then keys[#keys + 1] = k end end
    table.sort(keys)
    return table.concat(keys, ",")
end

function Alts.DecodeList(s)
    local out = {}
    if type(s) ~= "string" then return out end
    for k in s:gmatch("%d+") do out[tonumber(k)] = true end
    return out
end

local function MatIDs()
    local S = ns.Shopping
    if S and S.MatIDs then
        local ok, ids = pcall(S.MatIDs)
        if ok and type(ids) == "table" then return ids end
    end
    return EMPTY
end

-- Counts the shopping mats of this character: bags always, the bank only while it is open.
function Alts.CountMats(withBank)
    local ids = MatIDs()
    if #ids == 0 then return end
    local C = C_Item
    local GetCount = (C and C.GetItemCount) or _G.GetItemCount
    if type(GetCount) ~= "function" then return end
    local m = live.mats or {}
    for _, id in ipairs(ids) do
        local okB, bags = pcall(GetCount, id)
        if okB and not Secret(bags) and type(bags) == "number" then
            local c = m[id] or { 0, 0 }
            c[1] = bags
            if withBank then
                local okA, all = pcall(GetCount, id, true)
                if okA and not Secret(all) and type(all) == "number" then c[2] = math.max(0, all - bags) end
            end
            m[id] = c
        end
    end
    live.mats = m
end

-- This character's professions -> { [skillLine] = rank } (nil when unreadable).
function Alts.ReadProfessions()
    local GetProfessions, GetProfessionInfo = _G.GetProfessions, _G.GetProfessionInfo
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(GetProfessions)
    if not ok then return nil end
    local out = {}
    for _, idx in pairs({ a, b, c, d, e }) do
        if type(idx) == "number" and not Secret(idx) then
            local okI, _, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, idx)
            if okI and Whole(rank) and Whole(skillLine) and not Secret(skillLine) then out[skillLine] = rank end
        end
    end
    return out
end

-- The data's recipe spells this character knows -> { [spellID] = true } (nil = can't tell).
-- C_SpellBook.IsSpellKnown at any time (probe "Recipes" confirms it covers recipes), plus
-- what the profession window told us (`live.recipes`).
function Alts.ReadRecipes()
    local S = ns.Shopping
    local spells = (S and S.RecipeSpells) and S.RecipeSpells() or EMPTY
    local known = {}
    for id in pairs(live.recipes or EMPTY) do known[id] = true end
    local SB = _G.C_SpellBook
    local IsKnown = SB and SB.IsSpellKnown
    if type(IsKnown) ~= "function" and next(known) == nil then return nil end
    if type(IsKnown) == "function" then
        for _, id in ipairs(spells) do
            local ok, k = pcall(IsKnown, id)
            if ok and k == true then known[id] = true end
        end
    end
    return known
end

-- The profession window said a recipe is learned (or not).
function Alts.NoteRecipe(spellID, learned)
    if not Whole(spellID) then return end
    live.recipes = live.recipes or {}
    live.recipes[spellID] = learned and true or nil
end

-- Per character (own saved ones; this one = live): mats { [id] = { bags, bank } },
-- professions { [skillLine] = rank }, recipes { [spellID] = true }.
function Alts:MatCounts(key)
    if key == self:MyKey() then
        LoadLive()
        if live.mats then return live.mats end
    end
    local db = DB()
    local rec = db and db.chars[key]
    return type(rec) == "table" and Alts.DecodeMats(rec.mats) or {}
end

function Alts:Professions(key)
    if key == self:MyKey() then
        local p = Alts.ReadProfessions()
        if p then return p end
    end
    local db = DB()
    local rec = db and db.chars[key]
    return type(rec) == "table" and Alts.DecodeNums(rec.prof) or {}, type(rec) == "table" and type(rec.prof) == "string"
end

function Alts:Recipes(key)
    if key == self:MyKey() then
        local r = Alts.ReadRecipes()
        if r then return r, true end
    end
    local db = DB()
    local rec = db and db.chars[key]
    if type(rec) == "table" and type(rec.recipes) == "string" then return Alts.DecodeList(rec.recipes), true end
    return {}, false
end

-- Offline tests: reset the in-memory state.
function Alts._Reset()
    live = { dates = {} }
    wipe(liveDone)
    account = { items = nil, date = 0, readable = nil, checked = 0 }
    loaded, myKey = false, nil
    state.bankOpen, state.bankRead, state.mailOpen = false, false, false
    wipe(pending); timerOn = false
    Dirty()
end
Alts._state, Alts._live = state, function() return live end
