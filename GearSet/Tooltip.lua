-- Gear Set: the item -> set index and one line on item tooltips:
--   "Gear Set: have 3/8 - you need this"   (item in 2+ sets: "Gear Set: Nightslayer 3/8 ..." per set)
--   "Needed by: Stabby 3/8, Healz 1/8"   (alts from ns.Alts, plans\v1.0.0\beta7-interface.md)
-- Only TooltipDataProcessor.AddTooltipPostCall (the probe found no OnTooltipSetItem on Forever);
-- no GameTooltip method is replaced. Item IDs are checked with issecretvalue first.
-- Speed: a non-set item costs one table lookup (plans\v1.0.0\plan.md sec. 8).
local _, ns = ...
local Theme = ns.Theme

local Tip = {}
ns.Tooltip = Tip

-- Texts (merged into ns.L when Core doesn't have them, so translators find them in one table).
local TEXT = {
    TIP_LABEL = "Gear Set:",
    TIP_NEED = "- you need this",
    TIP_HAVE = "have %s",   -- %s = the count; used when the item is in one set only
    TIP_NEEDED_BY = "Needed by:",
    TIP_MORE = "+%d more",
    INSPECT_WEARS = "%s wears",
    INSPECT_MORE = "(+%d more)",
    INSPECT_TITLE = "Gear Set: sets %s wears",
    INSPECT_NOTE = "Only from this inspect; nothing is saved.",
    BROKER_TIP_CLICK = "Click: open or close the window.",
    BROKER_TIP_RIGHT = "Right-click: settings.",
    SHOWITEM_COMBAT = "Gear Set opens this piece's guide after combat.",
}
ns.L = ns.L or {}
for k, v in pairs(TEXT) do
    if ns.L[k] == nil then ns.L[k] = v end
end
local L = ns.L

local issecret = issecretvalue
local function Secret(v)
    return issecret ~= nil and issecret(v) == true
end
Tip.Secret = Secret

-- ---------------------------------------------------------------------------
-- Index: [itemID] = setID, or { setID, setID } for items in more than one set.
-- Built once from the raw bundled table (no API calls), on first use.
local index

function Tip.BuildIndex()
    index = {}
    local sets = ns.ClassicSets
    if type(sets) ~= "table" then return index end
    local function Add(id, setID)
        if type(id) ~= "number" then return end
        local v = index[id]
        if v == nil then
            index[id] = setID
        elseif type(v) == "number" then
            if v ~= setID then index[id] = { v, setID } end
        else
            for _, s in ipairs(v) do if s == setID then return end end
            v[#v + 1] = setID
        end
    end
    local ids = {}
    for setID in pairs(sets) do ids[#ids + 1] = setID end
    table.sort(ids)   -- the same set comes first every time
    for _, setID in ipairs(ids) do
        local e = sets[setID]
        if type(e) == "table" then
            for _, list in ipairs({ e.i, e.up }) do
                if type(list) == "table" then
                    for _, id in ipairs(list) do Add(id, setID) end
                end
            end
        end
    end
    return index
end

-- Raw entry (number, table or nil). Hot path: one lookup.
function Tip.Lookup(itemID)
    return (index or Tip.BuildIndex())[itemID]
end

-- The index itself (built on first use); also Alts.SetItems' "is a set piece" table.
function Tip.Index()
    return index or Tip.BuildIndex()
end

-- New list of set IDs for an item (empty when it is no set piece). Not for the hot path.
function Tip.SetIDsOf(itemID)
    local v = Tip.Lookup(itemID)
    if v == nil then return {} end
    if type(v) == "number" then return { v } end
    local out = {}
    for i, s in ipairs(v) do out[i] = s end
    return out
end

-- itemID from a number, "12345", an item link or "item:12345:...".
function Tip.ItemIDOf(v)
    if v == nil or Secret(v) then return nil end
    if type(v) == "number" then return v end
    if type(v) == "string" then
        return tonumber(v:match("item:(%d+)") or v:match("^%s*(%d+)%s*$"))
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Formatting (same look for tooltip, inspect strip and broker).
local hexCache = setmetatable({}, { __mode = "k" })
function Tip.Hex(color)
    local h = hexCache[color]
    if h then return h end
    local r, g, b = 1, 1, 1
    if color and color.GetRGB then r, g, b = color:GetRGB() end
    h = ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    hexCache[color] = h
    return h
end
local function Wrap(color, text) return Tip.Hex(color) .. text .. "|r" end

function Tip.Count(have, total)
    if not (have and total) then return "" end
    return Wrap(Theme.CountColorObj(have, total), ("%d/%d"):format(have, total))
end

function Tip.Label()
    return Wrap(Theme.colors.tipLabel, L.TIP_LABEL)
end

function Tip.Name(text)
    return Wrap(Theme.colors.tipName, text)
end

function Tip.Note(text)
    return Wrap(Theme.colors.tipNote, text)
end

-- Set object (nil when the set has no piece this client knows) and its name.
function Tip.SetOf(setID)
    local D = ns.Data
    local set = D and D.GetSet and D:GetSet("c" .. setID)
    if set then return set, set.name end
    local get = (C_Item and C_Item.GetItemSetInfo) or GetItemSetInfo
    local name = get and get(setID)
    if type(name) ~= "string" or Secret(name) then name = (L.UNKNOWN_SET or "Set %d"):format(setID) end
    return nil, name
end

-- have, total for a character (nil = this one). Alts first; this character falls back to Owned.
local function Progress(set, setID, charKey)
    -- v1.0.1 (F1): this character's count of a set with pieces this client doesn't know comes
    -- from Owned (they count in the total there, and an old "finished" date isn't used).
    if charKey == nil and set and ns.Owned and ns.Owned.UnknownCount and ns.Owned.UnknownCount(set) > 0 then
        return ns.Owned:SetCount(set)
    end
    local A = ns.Alts
    if A and A.GetSetProgress then
        local ok, h, t = pcall(A.GetSetProgress, A, setID, charKey)
        if ok and type(h) == "number" and type(t) == "number" and t > 0 then return h, t end
    end
    if charKey == nil and set and ns.Owned then
        return ns.Owned:SetCount(set)
    end
    return nil
end
Tip.Progress = Progress

local function PieceOf(set, itemID)
    for _, p in ipairs(set and (set.shown or set.pieces) or {}) do
        if p.itemID == itemID then return p end
    end
end

-- classFile -> classID (built once).
local classIDs
local function ClassID(classFile)
    if not classFile then return nil end
    if not classIDs then
        classIDs = {}
        local n = (GetNumClasses and GetNumClasses()) or 11
        for i = 1, n do
            local _, file = GetClassInfo(i)
            if file then classIDs[file] = i end
        end
    end
    return classIDs[classFile]
end

-- Who holds this item: keys -> true (shared table, refilled per call).
local holdsKeys = {}
local function Holders(itemID)
    wipe(holdsKeys)
    local A = ns.Alts
    if not (A and A.GetHolders) then return holdsKeys end
    local ok, list = pcall(A.GetHolders, A, itemID)
    if ok and type(list) == "table" then
        for _, h in ipairs(list) do
            if type(h) == "table" and h.key then holdsKeys[h.key] = true end
        end
    end
    return holdsKeys
end

local MAX_ALTS = 3

-- "Needed by: A 3/8, B 1/8 +2 more" or nil. Alts who started the set (1+ pieces), haven't
-- finished it, don't hold this item and whose class fits the set.
local function NeededBy(set, setID, held)
    local A = ns.Alts
    if not (A and A.Chars) then return nil end
    local ok, chars = pcall(A.Chars, A)
    if not ok or type(chars) ~= "table" then return nil end
    local parts, extra = {}, 0
    for _, c in ipairs(chars) do
        if type(c) == "table" and not c.me and c.key and not held[c.key] then
            local fits = true
            local cid = ClassID(c.class)
            if set and cid and ns.Data and ns.Data.SetForClass then fits = ns.Data.SetForClass(set, cid) end
            if fits then
                local h, t = Progress(set, setID, c.key)
                if h and t and h > 0 and h < t then
                    if #parts < MAX_ALTS then
                        parts[#parts + 1] = Tip.Name(tostring(c.name or c.key)) .. " " .. Tip.Count(h, t)
                    else
                        extra = extra + 1
                    end
                end
            end
        end
    end
    if #parts == 0 then return nil end
    local s = Tip.Note(L.TIP_NEEDED_BY) .. " " .. table.concat(parts, ", ")
    if extra > 0 then s = s .. " " .. Tip.Note(L.TIP_MORE:format(extra)) end
    return s
end

-- "have 5/8": grey words around the coloured count (L.TIP_HAVE, %s = the count).
function Tip.Have(have, total)
    local fmt = L.TIP_HAVE or "have %s"
    local pre, post = fmt:match("^(.-)%%s(.*)$")
    if not pre then pre, post = fmt .. " ", "" end
    local s = Tip.Count(have, total)
    if pre ~= "" then s = Tip.Note(pre) .. s end
    if post ~= "" then s = s .. Tip.Note(post) end
    return s
end

-- "- you need this" stands out in white (review 3: not the grey of unreached set bonuses).
function Tip.Need()
    return Wrap(Theme.colors.tipNeed or Theme.colors.tipName, L.TIP_NEED)
end

-- v1.0.1 (F2): Dungeon Set 1 pieces are taken by the Dungeon Set 2 quests. From the raw
-- bundled table (tier tag t), no set list needed. D2 counts as out when any D2 set has no u flag.
local d2Out
function Tip.D2Out()
    if d2Out ~= nil then return d2Out end
    d2Out = false
    local sets = ns.ClassicSets
    if type(sets) ~= "table" then return d2Out end
    for _, e in pairs(sets) do
        if type(e) == "table" and e.t == "D2" and (e.u == nil or e.u == false or e.u == 0) then
            d2Out = true
            break
        end
    end
    return d2Out
end

-- The grey "keep it" line for an item in a D1 set (nil for anything else).
function Tip.KeepLine(ids)
    local sets = ns.ClassicSets
    if type(sets) ~= "table" or type(ids) ~= "table" then return nil end
    for _, setID in ipairs(ids) do
        local e = sets[setID]
        if type(e) == "table" and e.t == "D1" then
            local text = Tip.D2Out() and (L.TIP_KEEP_D2 or "Keep it: the Dungeon Set 2 quests take this piece")
                or (L.TIP_KEEP_D2_LATER or "Keep it: the Dungeon Set 2 quests take this piece (not out yet)")
            return Tip.Note(text)
        end
    end
    return nil
end

-- Lines for one item (list of strings; empty for non-set items). Used by the hook and tests.
-- One set: "Gear Set: have 5/8 - you need this" (the set name is already in Blizzard's set
-- block just above). Two or more sets: "Gear Set: <set> 5/8 - you need this" per set.
function Tip.LinesFor(itemID)
    local out = {}
    local v = Tip.Lookup(itemID)
    if v == nil then return out end
    local ids = type(v) == "number" and { v } or v
    local single = #ids == 1
    local held
    for _, setID in ipairs(ids) do
        local set, name = Tip.SetOf(setID)
        local have, total = Progress(set, setID, nil)
        local line
        if single and have and total then
            line = Tip.Label() .. " " .. Tip.Have(have, total)
        else
            line = Tip.Label() .. " " .. Tip.Name(name)
            if have and total then line = line .. " " .. Tip.Count(have, total) end
        end
        local piece = PieceOf(set, itemID)
        if piece and ns.Owned then
            held = held or Holders(itemID)
            local myKey = ns.Alts and ns.Alts.MyKey and ns.Alts:MyKey()
            local done = have and total and have >= total   -- a finished set stays finished
            local need = not done and not ns.Owned:IsHave(piece) and not (myKey and held[myKey])
            if need then line = line .. " " .. Tip.Need() end
        end
        out[#out + 1] = line
        held = held or Holders(itemID)
        local alts = NeededBy(set, setID, held)
        if alts then out[#out + 1] = alts end
    end
    local keep = Tip.KeepLine(ids)
    if keep then out[#out + 1] = keep end
    return out
end

-- Settings (plans\v1.0.0\beta7-B-needs.md): tooltipLine (default on), tooltipShift (default off).
function Tip.Wanted()
    local db = ns.db
    if type(db) ~= "table" then return true end
    if db.tooltipLine == false then return false end
    if db.tooltipShift == true and not (IsShiftKeyDown and IsShiftKeyDown()) then return false end
    return true
end

local function OnItemTooltip(tooltip, data)
    local id = type(data) == "table" and data.id or nil
    if id == nil or Secret(id) then return end
    if (index or Tip.BuildIndex())[id] == nil then return end   -- not a set piece: done
    if not tooltip or not tooltip.AddLine then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local name = tooltip.GetName and tooltip:GetName()
    if type(name) == "string" and not Secret(name) and name:find("^ShoppingTooltip") then return end   -- compare tips
    if not Tip.Wanted() then return end
    local ok, lines = pcall(Tip.LinesFor, id)
    if not ok or #lines == 0 then return end
    for _, line in ipairs(lines) do tooltip:AddLine(line, 1, 1, 1, true) end
    if tooltip.Show then tooltip:Show() end   -- resize to fit the new lines
end
Tip.OnItemTooltip = OnItemTooltip

-- Hook once, at load (TooltipDataProcessor is part of the base UI).
local TDP = TooltipDataProcessor
if type(TDP) == "table" and type(TDP.AddTooltipPostCall) == "function" then
    local itemType = (Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item) or 0
    Tip.hooked = pcall(TDP.AddTooltipPostCall, itemType, OnItemTooltip)
end
