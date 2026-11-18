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
-- itemID -> true for every piece in the bundled set table (built once, no API calls).
function Alts.SetItems()
    if setItems then return setItems end
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
        any = true
    end
    if pending.bank and state.bankOpen then
        live.bank, live.dates.bank = Alts.ScanBank(items), t
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
