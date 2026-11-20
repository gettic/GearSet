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
    local view = { title = instName, runs = Runs.RunsIn(instName, mapID), bosses = {}, need = 0 }
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
        return (a.name or "") < (b.name or "")
    end)
    view.bosses = list
    return view
end

-- Drops the wanted-list cache (post-hooked on Owned.Invalidate and Progress.Invalidate in Init).
function Runs.Invalidate()
    wantedCache = nil
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
