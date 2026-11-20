-- Gear Set: "which wanted piece drops where, from whom" (1.1 beta.1; plans\v1.1.0\plan.md sec. 3,
-- data contract plans\v1.1.0\b1-interface.md). Used by the dungeon checklist (UI\Tracker.lua),
-- the loot-roll mark (LootMark.lua) and later the Plan tab.
-- Read-only: bundled data, Owned / Alts / Track state. Nothing saved, no events of its own
-- (Tracker drives it). ToS W4: ticks come from bags (Owned), never from combat data.
local _, ns = ...

local Runs = {}
ns.Runs = Runs

local function Has(s) return type(s) == "string" and s ~= "" end
local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ---------------------------------------------------------------------------
-- Raw GuideData records, own small parse (Data's record cache is wiped per guide page).
-- Runs.Rec(tname, key, mine) -> { field = first value, ... , [field.."_all"] = { values } } or nil.
-- While `scanning` (a one-off pass over every set item) nothing is kept: records and source
-- lists of items outside the current instance would stay in memory for the session (b1-pretest note 1).
local recCache = {}
local scanning = false
function Runs.Rec(tname, key, mine)
    if not Has(key) then return nil end
    local g = ns.GuideData
    local t = type(g) == "table" and g[tname]
    local raw = type(t) == "table" and t[key]
    if type(raw) ~= "string" then return nil end
    local ck = tname .. "\31" .. key .. "\31" .. (mine or "")
    local hit = recCache[ck]
    if hit ~= nil then return hit or nil end
    local out = {}
    for part in raw:gmatch("[^;]+") do
        local f = {}
        for v in (part .. "|"):gmatch("(.-)|") do f[#f + 1] = Trim(v) end
        local fac
        local last = f[#f]
        if #f > 1 and last and last:match("^@[AH]$") then fac = last:sub(2, 2); f[#f] = nil end
        if Has(f[1]) and (not fac or not mine or fac == mine) then
            local k = f[1]
            if out[k] == nil then out[k] = f[2] or "" end
            local all = out[k .. "_all"]
            if not all then all = {}; out[k .. "_all"] = all end
            all[#all + 1] = f[2] or ""
        end
    end
    if not scanning then recCache[ck] = out end
    return out
end

-- Kill order of a boss (GuideData boss `n|`), nil when unknown.
function Runs.BossOrder(name)
    local r = Runs.Rec("boss", name)
    local n = r and tonumber(r.n)
    if n and n >= 1 and n <= 99 and n == math.floor(n) then return n end
    return nil
end

-- Wing of a boss: the part of its `wing|` text before ":" (nil when none).
function Runs.BossWing(name)
    local r = Runs.Rec("boss", name)
    local w = r and r.wing
    if not Has(w) then return nil end
    return Trim(w:match("^([^:]+)") or w)
end

local function IsInstanceKind(kind) return kind == "dungeon" or kind == "raid" end

-- The run (instance) a place belongs to: itself, or its parent when the place's `zone` is a
-- dungeon/raid place (Ring of Law -> Blackrock Depths). Returns runName, wingName|nil.
function Runs.RunOf(place)
    if not Has(place) then return nil end
    local r = Runs.Rec("place", place)
    local zone = r and r.zone
    if Has(zone) and zone ~= place then
        local pr = Runs.Rec("place", zone)
        if pr and IsInstanceKind(pr.kind) then return zone, place end
    end
    return place, nil
end

-- Instance map ID of a place (`map|`), nil when not in the data yet.
function Runs.PlaceMap(place)
    local r = Runs.Rec("place", place)
    local n = r and tonumber(r.map)
    if n and n > 0 and n == math.floor(n) then return n end
    return nil
end

-- ---------------------------------------------------------------------------
-- Where an item drops: list of { place (run), wing, boss (row label or nil = trash), how
-- ("boss"/"trash"/"handin"), via (hand-in item name), quest, later }.
local srcCache = {}
local NONE = {}   -- shared result for items that drop in no dungeon or raid (read only)

local function BringNames(quest, mine)
    local r = Runs.Rec("quest", quest, mine)
    local out = {}
    for _, v in ipairs(r and r.bring_all or {}) do
        local name = Trim((v:gsub("^%d+%s+", "")))
        if name ~= "" then out[#out + 1] = name end
    end
    return out
end

local function DropRows(name)
    local g = ns.GuideData
    local raw = type(g) == "table" and type(g.drop) == "table" and g.drop[name]
    local out = {}
    if type(raw) ~= "string" then return out end
    for part in raw:gmatch("[^;]+") do
        local k, who, place = part:match("^%s*([^|]*)|([^|]*)|([^|@]*)")
        if k and Trim(k) == "src" and Has(Trim(place or "")) then
            out[#out + 1] = { who = Trim(who or ""), place = Trim(place) }
        end
    end
    return out
end

function Runs.PieceSources(itemID, mine)
    local ck = tostring(itemID) .. (mine or "")
    local hit = srcCache[ck]
    if hit then return hit end
    local out = {}
    local D = ns.Data
    local entries = (D and D.SourceEntries) and D.SourceEntries(itemID) or {}
    local function Add(place, boss, how, via, quest, later)
        local run, wing = Runs.RunOf(place)
        if not run then return end
        local pr = Runs.Rec("place", run)
        if not (pr and IsInstanceKind(pr.kind)) then return end   -- only dungeons and raids
        out[#out + 1] = { place = run, wing = wing, boss = Has(boss) and boss or nil, how = how,
            via = via, quest = quest, later = later and true or nil }
    end
    for _, e in ipairs(entries) do
        if not e.fac or not mine or e.fac == mine then
            if e.kind == "b" then Add(e.b, e.a, "boss", nil, nil, e.later)
            elseif e.kind == "z" then Add(e.a, nil, "trash", nil, nil, e.later)
            elseif e.kind == "q" and Has(e.a) then
                for _, name in ipairs(BringNames(e.a, mine)) do
                    for _, d in ipairs(DropRows(name)) do
                        -- who = "A, B, C" (several bosses) or "enemies ..." / "all bosses" (no boss record)
                        local lw = d.who:lower()
                        if d.who == "" or lw:find("^enemies") then
                            Add(d.place, nil, "handin", name, e.a, e.later)
                        else
                            for who in (d.who .. ","):gmatch("%s*([^,]+),") do
                                Add(d.place, Trim(who), "handin", name, e.a, e.later)
                            end
                        end
                    end
                end
            end
        end
    end
    if #out == 0 then out = NONE end
    if not scanning then srcCache[ck] = out end
    return out
end

-- ---------------------------------------------------------------------------
-- Who wants a piece. Wanted = this character's tracked sets' needed pieces and tracked pieces;
-- with nothing tracked (setting tracker.started, on by default): sets this character has
-- started (1+ pieces, not complete), can wear, that are out now and not hidden.
local wantedCache

local function MyClassID()
    local ok, _, _, id = pcall(UnitClass, "player")
    return ok and id or nil
end

local function SetOK(set, mine)
    if not set or set.removed or set.unreleased then return false end
    if set.faction and mine and set.faction ~= mine then return false end
    local D = ns.Data
    if D and D.IsHidden and D.IsHidden(set) then return false end
    return true
end

-- Adds a set's pieces: needed ones (counting) and not-out-yet ones (shown as skipped).
local function AddSet(out, set)
    local O = ns.Owned
    for _, p in ipairs(set.pieces or {}) do
        if not p.unknown and not (O and O:IsHave(p)) and not out[p.itemID] then
            out[p.itemID] = { set = set, piece = p, later = p.later and true or nil }
        end
    end
    for _, p in ipairs(set.later or {}) do
        if not out[p.itemID] then out[p.itemID] = { set = set, piece = p, later = true } end
    end
end

function Runs.StartedOn()
    local db = ns.db
    local t = db and db.tracker
    return not (type(t) == "table" and t.started == false)
end

-- [itemID] = { set, piece, later } for this character (cached until Runs.Invalidate).
function Runs.Wanted()
    if wantedCache then return wantedCache end
    local out = {}
    local D, O, Tr = ns.Data, ns.Owned, ns.Track
    if not (D and D.GetSets and O) then wantedCache = out; return out end
    local mine = D.PlayerFaction and D.PlayerFaction()
    local tracked = (Tr and Tr.Mine) and Tr.Mine() or {}
    local any = next(tracked) ~= nil
    if any then
        for key in pairs(tracked) do
            local kind, id = tostring(key):match("^(%a+):(%d+)$")
            id = tonumber(id)
            if kind == "set" and id then
                local set = D:GetSet("c" .. id)
                if set and not set.removed then
                    local have, total = O:SetCount(set)
                    if have < total then AddSet(out, set) end
                end
            elseif kind == "item" and id then
                local P = ns.Progress
                local p = P and P.PieceOf and P.PieceOf(id)
                if p and not p.unknown and not O:IsHave(p) and not out[id] then
                    out[id] = { piece = p, later = p.later and true or nil }
                end
            end
        end
    elseif Runs.StartedOn() then
        local cls = MyClassID()
        for _, set in ipairs(D:GetSets()) do
            if SetOK(set, mine) and (not cls or not D.SetForClass or D.SetForClass(set, cls)) then
                local have, total = O:SetCount(set)
                if have > 0 and have < total then AddSet(out, set) end
            end
        end
    end
    wantedCache = out
    return out
end

-- Other characters (own saved ones only, ToS W8) who started the item's set, haven't
-- finished it, don't hold the item and whose class fits. -> list of names (max `max`).
local classIDs
local function ClassIDOf(file)
    if not file then return nil end
    if not classIDs then
        classIDs = {}
        local n = (GetNumClasses and GetNumClasses()) or 12
        for i = 1, n do
            local ok, _, f = pcall(GetClassInfo, i)
            if ok and f then classIDs[f] = i end
        end
    end
    return classIDs[file]
end

local function SetsOfItem(itemID)
    local Tip = ns.Tooltip
    local out = {}
    if Tip and Tip.SetIDsOf then
        for _, sid in ipairs(Tip.SetIDsOf(itemID)) do
            local set = ns.Data and ns.Data:GetSet("c" .. sid)
            if set then out[#out + 1] = set end
        end
    end
    return out
end

function Runs.AltsNeeding(itemID, max)
    local A, D = ns.Alts, ns.Data
    local names = {}
    if not (A and A.Chars and A.GetSetProgress and D) then return names end
    local okC, chars = pcall(A.Chars, A)
    if not okC or type(chars) ~= "table" then return names end
    local held = {}
    local okH, holders = pcall(A.GetHolders, A, itemID)
    for _, h in ipairs(okH and type(holders) == "table" and holders or {}) do
        if type(h) == "table" and h.key then held[h.key] = true end
    end
    local sets = SetsOfItem(itemID)
    for _, c in ipairs(chars) do
        if type(c) == "table" and not c.me and c.key and not held[c.key] then
            for _, set in ipairs(sets) do
                if not set.unreleased and not set.removed then
                    local cid = ClassIDOf(c.class)
                    local fits = not (cid and D.SetForClass) or D.SetForClass(set, cid)
                    local ok, h, t = pcall(A.GetSetProgress, A, set.id, c.key)
                    if fits and ok and type(h) == "number" and type(t) == "number" and h > 0 and h < t then
                        names[#names + 1] = tostring(c.name or c.key)
                        break
                    end
                end
            end
        end
        if max and #names >= max then break end
    end
    return names
end

-- For the loot mark: me (wanted and out now) and / or alt names.
function Runs.WhoNeeds(itemID)
    local w = Runs.Wanted()[itemID]
    local me = w ~= nil and not w.later
    return me, Runs.AltsNeeding(itemID, 3)
end

-- ---------------------------------------------------------------------------
-- Set pieces by run, for alt-only rows. One pass over every set item that keeps nothing but
-- the runs asked for (`want` = { [run] = true }, nil = all): b1-pretest note 1, the full index
-- cost ~1 MB for the session. -> { [run] = { { itemID, src } } }.
local function Scan(want)
    local out = {}
    local Tip, D = ns.Tooltip, ns.Data
    local idx = Tip and Tip.Index and Tip.Index() or {}
    local mine = D and D.PlayerFaction and D.PlayerFaction()
    local was = scanning
    scanning = true
    local ok, err = pcall(function()
        for itemID in pairs(idx) do
            local list = srcCache[tostring(itemID) .. (mine or "")] or Runs.PieceSources(itemID, mine)
            for _, s in ipairs(list) do
                if not want or want[s.place] then
                    local l = out[s.place]
                    if not l then l = {}; out[s.place] = l end
                    l[#l + 1] = { itemID = itemID, src = s }
                end
            end
        end
    end)
    scanning = was
    if not ok then error(err, 0) end
    return out
end

-- Every run (tests, selftest; not cached: a new table each call).
function Runs.PlaceIndex()
    return Scan(nil)
end

-- Pieces of the runs of one instance (cached per run, only runs you entered).
local runItems = {}
function Runs.RunItems(runs)
    local need
    for _, run in ipairs(runs) do
        if not runItems[run] then need = need or {}; need[run] = true end
    end
    if need then
        local found = Scan(need)
        for run in pairs(need) do runItems[run] = found[run] or NONE end
    end
    return runItems
end

-- Any other saved character (own ones only, ToS W8)? Without one there are no alt rows.
function Runs.HasAlts()
    local A = ns.Alts
    if not (A and A.Chars) then return false end
    local ok, chars = pcall(A.Chars, A)
    if not ok or type(chars) ~= "table" then return false end
    for _, c in ipairs(chars) do
        if type(c) == "table" and not c.me then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Instance -> runs. Places with `map|` match by ID only; others by name (b1-interface.md).
local function Words(s) return " " .. s:lower():gsub("[^%w']+", " ") .. " " end

function Runs.PlaceMatches(place, instName, mapID)
    local m = Runs.PlaceMap(place)
    if m then return mapID ~= nil and m == mapID end
    if not Has(instName) then return false end
    local p, n = place:lower(), instName:lower()
    if p == n then return true end
    local wp, wn = Words(place), Words(instName)
    local at = wp:find(wn, 1, true)
    return at == 1 or (at ~= nil and at + #wn - 1 == #wp)
end

-- Run names (instance places with set drops) that this instance covers.
function Runs.RunsIn(instName, mapID)
    local out, seen = {}, {}
    local g = ns.GuideData
    for place in pairs(type(g) == "table" and type(g.place) == "table" and g.place or {}) do
        local r = Runs.Rec("place", place)
        if r and IsInstanceKind(r.kind) and Runs.PlaceMatches(place, instName, mapID) then
            local run = Runs.RunOf(place)
            if run and not seen[run] then seen[run] = true; out[#out + 1] = run end
        end
    end
    table.sort(out)
    return out
end

-- The checklist view of an instance:
-- { title, runs, bosses = { { name, label, order, wing, trash, pieces = { { itemID, later, mine,
--   alts, via } } } }, need = pieces this character needs here that are out now }.
-- `entered` = optional [itemID] = true captured on entering (got pieces stay listed, ticked).
function Runs.View(instName, mapID, entered)
    return Runs.ViewRuns(Runs.RunsIn(instName, mapID), instName, entered)
end

-- The same view for a list of run names (the Plan tab: one run each).
function Runs.ViewRuns(runs, title, entered)
    local view = { title = title, runs = runs, bosses = {}, need = 0 }
    if #view.runs == 0 then return view end
    local inRun = {}
    for _, r in ipairs(view.runs) do inRun[r] = true end
    local wanted = Runs.Wanted()
    local mine = ns.Data and ns.Data.PlayerFaction and ns.Data.PlayerFaction()
    local byBoss, list = {}, {}
    local function Boss(label, trash)
        local key = trash and "\1trash" or label
        local b = byBoss[key]
        if not b then
            b = { name = label, label = label, order = (not trash) and Runs.BossOrder(label) or nil,
                wing = (not trash) and Runs.BossWing(label) or nil, trash = trash or nil, pieces = {}, ids = {} }
            byBoss[key] = b
            list[#list + 1] = b
        end
        return b
    end
    local function AddPiece(itemID, s, isMine, later, alts)
        local b = Boss(s.boss or "", s.boss == nil)
        if not b.wing and not b.trash and Has(s.wing) then b.wing = s.wing end
        if b.ids[itemID] then return end
        b.ids[itemID] = true
        b.pieces[#b.pieces + 1] = { itemID = itemID, later = later or nil, mine = isMine or nil,
            alts = alts, via = s.via,
            got = (isMine and entered and entered[itemID] and not wanted[itemID]) and true or nil }
    end
    -- this character's wanted pieces (and ones got since entering)
    local mineIDs = {}
    for itemID, w in pairs(wanted) do mineIDs[itemID] = w end
    for itemID in pairs(entered or {}) do mineIDs[itemID] = mineIDs[itemID] or { later = nil } end
    local counted = {}
    for itemID, w in pairs(mineIDs) do
        for _, s in ipairs(Runs.PieceSources(itemID, mine)) do
            if inRun[s.place] then
                local later = w.later or s.later
                AddPiece(itemID, s, true, later, nil)
                if not later and wanted[itemID] and not counted[itemID] then
                    counted[itemID] = true
                    view.need = view.need + 1
                end
            end
        end
    end
    view.needIDs = counted
    -- pieces only an alt needs (names of own characters only)
    local pidx = Runs.HasAlts() and Runs.RunItems(view.runs) or {}
    for _, run in ipairs(view.runs) do
        for _, e in ipairs(pidx[run] or NONE) do
            if not mineIDs[e.itemID] and not e.src.later then
                local alts = Runs.AltsNeeding(e.itemID, 2)
                if #alts > 0 then AddPiece(e.itemID, e.src, false, nil, alts) end
            end
        end
    end
    -- bosses in kill order (unknown order after, then name); trash last; a boss with only
    -- not-out-yet pieces is "skipped".
    for _, b in ipairs(list) do
        local allLater = #b.pieces > 0
        for _, p in ipairs(b.pieces) do if not p.later then allLater = false end end
        b.skipped = allLater or nil
        b.ids = nil
        table.sort(b.pieces, function(x, y) return x.itemID < y.itemID end)
    end
    table.sort(list, function(a, b)
        if (a.trash and true or false) ~= (b.trash and true or false) then return not a.trash end
        local oa, ob = a.order or 1000, b.order or 1000
        if oa ~= ob then return oa < ob end
        if (a.wing or "") ~= (b.wing or "") then return (a.wing or "") < (b.wing or "") end
        return (a.name or "") < (b.name or "")
    end)
    view.bosses = list
    return view
end

-- Drops the wanted-list cache (post-hooked on Owned.Invalidate and Progress.Invalidate in Init).
function Runs.Invalidate()
    wantedCache = nil
    if Runs.OnInvalidate then pcall(Runs.OnInvalidate) end
end

-- ---------------------------------------------------------------------------
-- 1.1 beta.4: the Plan tab (plans\v1.1.0\b4-plan.md; data b4-interface.md). Pure parts take
-- their inputs; the readers are pcall'd and secret-guarded. ToS B1 (lockouts read only, the
-- server request is the Plan tab's on-open one), B4 (group notes: static text), B5 (LFG line:
-- copy box only), W8 (own characters only).

local function Secret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s and true or false
end
local function Whole(v) v = tonumber(v); return v and v == math.floor(v) and v > 0 and v < 2 ^ 31 and v or nil end

-- Place facts: { size, lo, hi, kind, keys = { { id, part } }, attq = { ids }, attitem = { ids },
-- notes = { text } }.
function Runs.Facts(run, mine)
    local r = Runs.Rec("place", run, mine) or {}
    local f = { kind = r.kind, size = Whole(r.size), keys = {}, attq = {}, attitem = {}, notes = {} }
    local lo, hi = tostring(r.level or ""):match("^(%d+)%s*%-%s*(%d+)$")
    f.lo, f.hi = Whole(lo) or Whole(r.level), Whole(hi) or Whole(r.level)
    for _, v in ipairs(r.key_all or {}) do
        local id = Whole(v)
        if id then f.keys[#f.keys + 1] = { id = id } end
    end
    -- keypart|id|text: the text is the 3rd field (own small parse of the raw record)
    local g = ns.GuideData
    local raw = type(g) == "table" and type(g.place) == "table" and g.place[run]
    if type(raw) == "string" then
        for id, text in raw:gmatch("keypart|(%d+)|([^;|]*)") do
            f.keys[#f.keys + 1] = { id = tonumber(id), part = Trim(text) }
        end
    end
    for _, v in ipairs(r.attq_all or {}) do local id = Whole(v); if id then f.attq[#f.attq + 1] = id end end
    for _, v in ipairs(r.attitem_all or {}) do local id = Whole(v); if id then f.attitem[#f.attitem + 1] = id end end
    for _, v in ipairs(r.grp_all or {}) do if Has(v) then f.notes[#f.notes + 1] = v end end
    return f
end

-- Where this character has an item: "keyring" / "bags" / "bank" / nil (own counts only).
function Runs.ItemPlace(itemID)
    local A = ns.Alts
    local want = { [itemID] = true }
    if A and A.ScanKeyring then
        local ok, k = pcall(A.ScanKeyring, want)
        if ok and type(k) == "table" and k[itemID] then return "keyring" end
    end
    local C = C_Item
    local count = (C and C.GetItemCount) or _G.GetItemCount
    if type(count) ~= "function" then return nil end
    local okB, bags = pcall(count, itemID)
    if okB and type(bags) == "number" and not Secret(bags) and bags > 0 then return "bags" end
    local okA, all = pcall(count, itemID, true)
    if okA and type(all) == "number" and not Secret(all) and all > 0 then return "bank" end
    return nil
end

-- Attuned? true / false / nil (no attunement in the data).
function Runs.Attuned(facts)
    if #facts.attq == 0 and #facts.attitem == 0 then return nil end
    local Q = _G.C_QuestLog
    local done = Q and Q.IsQuestFlaggedCompleted
    for _, q in ipairs(facts.attq) do
        if type(done) == "function" then
            local ok, v = pcall(done, q)
            if ok and v == true then return true end
        end
    end
    for _, id in ipairs(facts.attitem) do
        if Runs.ItemPlace(id) then return true end
    end
    return false
end

-- Saved raids: { { name, mapID, reset, resetAt, isRaid, done, total, killed = { [boss] = true } | nil } }.
function Runs.ReadLockouts(now)
    local out = {}
    local num, info = _G.GetNumSavedInstances, _G.GetSavedInstanceInfo
    if type(num) ~= "function" or type(info) ~= "function" then return out end
    local okN, n = pcall(num)
    if not okN or type(n) ~= "number" or Secret(n) then return out end
    now = now or time()
    local enc = _G.GetSavedInstanceEncounterInfo
    for i = 1, math.min(n, 40) do
        local ok, name, _, reset, _, locked, _, _, isRaid, _, _, total, done, _, mapID = pcall(info, i)
        if ok and type(name) == "string" and not Secret(name) and not Secret(reset) and locked ~= false
            and (tonumber(reset) or 0) > 0 then   -- reset 0: just expired, not refreshed yet = not locked
            local row = { name = name, mapID = Whole(mapID), reset = tonumber(reset) or 0, isRaid = isRaid and true or false,
                done = tonumber(done) or 0, total = tonumber(total) or 0 }
            row.resetAt = now + row.reset
            if type(enc) == "function" and row.total > 0 then
                local killed, any = {}, false
                for j = 1, math.min(row.total, 40) do
                    local okE, boss, _, isKilled = pcall(enc, i, j)
                    if okE and type(boss) == "string" and not Secret(boss) and not Secret(isKilled) then
                        any = true
                        if isKilled then killed[boss] = true end
                    end
                end
                if any then row.killed = killed end
            end
            out[#out + 1] = row
        end
    end
    return out
end

-- The lockout row of a run (map ID first, then the name).
function Runs.MatchLock(locks, run)
    local m = Runs.PlaceMap(run)
    for _, l in ipairs(locks or {}) do
        if m and l.mapID then
            if l.mapID == m then return l end
        elseif Runs.PlaceMatches(run, l.name, l.mapID) or (Has(l.name) and l.name:lower() == run:lower()) then
            return l
        end
    end
    return nil
end

-- Display name of a run: general places that stand for several wings get a label
-- (pretest finding 1; data stays as it is).
local DISPLAY = { ["Blackrock Spire"] = "RUN_NAME_BRS", ["Scarlet Monastery"] = "RUN_NAME_SM" }
local DISPLAY_FALLBACK = { RUN_NAME_BRS = "Blackrock Spire (Lower or Upper)", RUN_NAME_SM = "Scarlet Monastery (any wing)" }
function Runs.DisplayName(run)
    local key = DISPLAY[run]
    if not key then return run end
    local L = ns.L or {}
    return L[key] or DISPLAY_FALLBACK[key]
end

-- Lockout per run for a list of runs: like MatchLock, but when one row's map is shared by
-- several runs (LBRS / UBRS / Blackrock Spire on 229), only the run whose name (or display
-- name) equals the row's name gets it; with no exact name among them, all keep it.
-- (pretest finding 2) -> { [run] = lock }.
function Runs.AssignLocks(locks, runs)
    local out = {}
    for _, l in ipairs(locks or {}) do
        local hits, exact = {}, {}
        for _, run in ipairs(runs) do
            if Runs.MatchLock({ l }, run) then
                hits[#hits + 1] = run
                local ln = Has(l.name) and l.name:lower() or ""
                if ln == run:lower() or ln == Runs.DisplayName(run):lower() then exact[#exact + 1] = run end
            end
        end
        local use = (#hits > 1 and #exact > 0) and exact or hits
        for _, run in ipairs(use) do if not out[run] then out[run] = l end end
    end
    return out
end

-- "free" (not saved) / "partial" / "done" (every boss with your pieces dead; without the boss
-- list: all bosses). `bosses` = the run's view bosses.
function Runs.LockState(lock, bosses)
    if not lock then return "free" end
    if lock.killed then
        local any = false
        for _, b in ipairs(bosses or {}) do
            if not b.trash and not b.skipped then
                any = true
                if not lock.killed[b.name] then return "partial" end
            end
        end
        if any then return "done" end
    end
    if lock.total > 0 and lock.done >= lock.total then return "done" end
    return "partial"
end

-- "resets Tue 09:00 (in 2d 4h)"; short = "resets in 2d 4h" (the row; the tooltip has the date).
-- Under a minute: "(under 1m)".
function Runs.ResetText(at, now, short)
    now = now or time()
    local left = math.max(0, (at or now) - now)
    local d, h, m = math.floor(left / 86400), math.floor(left % 86400 / 3600), math.floor(left % 3600 / 60)
    local L = ns.L or {}
    local inText
    if d > 0 then inText = (L.LOCK_IN_DH or "in %dd %dh"):format(d, h)
    elseif h > 0 then inText = (L.LOCK_IN_HM or "in %dh %dm"):format(h, m)
    elseif m > 0 then inText = (L.LOCK_IN_M or "in %dm"):format(m)
    else inText = L.LOCK_IN_LT or "under 1m" end
    if short then return (L.LOCK_RESET_SHORT or "resets %s"):format(inText) end
    local okD, day = pcall(date, "%a %H:%M", at)
    return (L.LOCK_RESET or "resets %s (%s)"):format(okD and day or "?", inText)
end

-- Pins: per character (decision Q3).
local function PinTable(create)
    local db = ns.db
    if type(db) ~= "table" or type(db.plan) ~= "table" then return nil end
    local A = ns.Alts
    local key = A and A.MyKey and A:MyKey()
    if not key then return nil end
    if type(db.plan.pinned) ~= "table" then db.plan.pinned = {} end
    local t = db.plan.pinned[key]
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}; db.plan.pinned[key] = t
    end
    return t
end

function Runs.IsPinned(run)
    local t = PinTable(false)
    return t ~= nil and t[run] == true
end

function Runs.Pin(run, on)
    local t = PinTable(true)
    if not t then return end
    if on == nil then on = not t[run] end
    t[run] = on and true or nil
end

-- Pure order: pinned, then not done, by pieces needed (most first), then name; done raids last.
function Runs.Sort(list)
    table.sort(list, function(a, b)
        local da, db = a.lockState == "done", b.lockState == "done"
        if da ~= db then return db end
        if (a.pinned and true or false) ~= (b.pinned and true or false) then return a.pinned and true or false end
        if a.need ~= b.need then return a.need > b.need end
        return a.run < b.run
    end)
    return list
end

-- Item name without the set's shared first word when it repeats ("Beaststalker's Cap, Gloves").
local function ShortNames(names)
    if #names < 2 then return names end
    local first = names[1]:match("^(%S+%s)")
    if not first then return names end
    for _, n in ipairs(names) do if n:sub(1, #first) ~= first then return names end end
    local out = { names[1] }
    for i = 2, #names do out[i] = names[i]:sub(#first + 1) end
    return out
end

-- "LFM Scholomance - need Beaststalker's Cap, Gloves" (max 255 letters; W5 / B5: copy box only).
function Runs.LfgLine(run, names, maxLen)
    maxLen = maxLen or 255
    local L = ns.L or {}
    local list = ShortNames(names or {})
    local text = (L.LFG_LINE or "LFM %s - need %s"):format(run, table.concat(list, ", "))
    if #names == 0 then text = (L.LFG_LINE_NONE or "LFM %s"):format(run) end
    if #text > maxLen then text = text:sub(1, maxLen - 3) .. "..." end
    return text
end

-- General group notes (B4: static text from our data only, never about other players).
function Runs.GroupNotes(facts)
    local L, out = ns.L or {}, {}
    if facts.size and facts.size > 5 then out[#out + 1] = (L.GRP_SIZE or "Up to %d players."):format(facts.size) end
    for _, k in ipairs(facts.keys) do
        if not k.part then out[#out + 1] = L.GRP_KEY or "One key holder can open the door for the group." break end
    end
    if #facts.attq > 0 or #facts.attitem > 0 then out[#out + 1] = L.GRP_ATT or "Everyone needs the attunement." end
    for _, n in ipairs(facts.notes) do out[#out + 1] = n end
    return out
end

-- The Plan list for this character: { runs = { { run, view, facts, need, pinned, lock, lockState,
-- names } }, other = wanted pieces out now that drop in no run }.
function Runs.Plan(locks)
    local wanted = Runs.Wanted()
    local mine = ns.Data and ns.Data.PlayerFaction and ns.Data.PlayerFaction()
    local seen, order, other, otherIDs = {}, {}, 0, {}
    for itemID, w in pairs(wanted) do
        local srcs = Runs.PieceSources(itemID, mine)
        if #srcs == 0 then
            if not w.later then other = other + 1; otherIDs[#otherIDs + 1] = itemID end
        else
            for _, s in ipairs(srcs) do
                if not seen[s.place] then seen[s.place] = true; order[#order + 1] = s.place end
            end
        end
    end
    if #order > 0 and Runs.HasAlts() then Runs.RunItems(order) end   -- one scan for all runs
    local list, kept, pieces, distinct = {}, {}, {}, 0
    for _, run in ipairs(order) do
        local view = Runs.ViewRuns({ run }, run)
        if view.need > 0 then
            local e = { run = run, label = Runs.DisplayName(run), view = view, need = view.need,
                facts = Runs.Facts(run, mine), pinned = Runs.IsPinned(run) }
            -- wings inside the run (Ring of Law under BRD): their own group notes
            e.wings = {}
            for _, b in ipairs(view.bosses) do
                if b.wing and not e.wings[b.wing] then e.wings[b.wing] = Runs.Facts(b.wing, mine).notes end
            end
            for id in pairs(view.needIDs or {}) do
                if not pieces[id] then pieces[id] = true; distinct = distinct + 1 end
            end
            list[#list + 1] = e
            kept[#kept + 1] = run
        end
    end
    local byRun = Runs.AssignLocks(locks, kept)
    for _, e in ipairs(list) do
        e.lock = byRun[e.run]
        e.lockState = Runs.LockState(e.lock, e.view.bosses)
    end
    table.sort(otherIDs)
    return { runs = Runs.Sort(list), other = other, otherIDs = otherIDs, pieces = distinct }
end

-- Clears every cache (tests).
function Runs._Reset()
    wantedCache = nil
    wipe(recCache); wipe(srcCache); wipe(runItems)
end

local hooked
function Runs.Init()
    if hooked then return end
    hooked = true
    if ns.Owned and ns.Owned.Invalidate then hooksecurefunc(ns.Owned, "Invalidate", Runs.Invalidate) end
    if ns.Progress and ns.Progress.Invalidate then hooksecurefunc(ns.Progress, "Invalidate", Runs.Invalidate) end
end
