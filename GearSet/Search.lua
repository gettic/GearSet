-- Gear Set: search everywhere (beta.9, contract plans\v1.0.0\beta9-interface.md part 4).
-- One search text finds sets (name, tier), pieces (names the game already has cached),
-- bosses, places and NPCs (vendors, quest givers) that give a set piece.
-- The index is built on the first search, from the bundled data only. Piece names come
-- only from C_Item.GetItemNameByID for items the client has cached already: no
-- GetItemInfo loops and no item load requests (ToS check tos-beta9.md item 6).
local _, ns = ...

local Search = {}
ns.Search = Search

-- Texts (merged into ns.L when Core doesn't have them).
local TEXT = {
    SEARCH_BOX = "Search (Ctrl+F)",
    SEARCH_G_SET = "Sets (%d)",
    SEARCH_G_PIECE = "Pieces (%d)",
    SEARCH_G_BOSS = "Bosses (%d)",
    SEARCH_G_PLACE = "Places (%d)",
    SEARCH_G_NPC = "NPCs (%d)",
    SEARCH_MORE = "%d more ...",
    SEARCH_FROM = "Sets with pieces from %s (%d)",
    SEARCH_BACK = "< All results",
    SEARCH_SETS_N = "Sets with a piece from here: %d",
    SEARCH_KIND_BOSS = "Boss",
    SEARCH_KIND_PLACE = "Place",
    SEARCH_KIND_NPC = "NPC (vendor or quest giver)",
    SEARCH_SRC_HINT = "Click: show these sets and the first piece's guide",
    SEARCH_PIECE_HINT = "Click: open its set and its guide",
    SEARCH_MORE_HINT = "Click: show all",
    SEARCH_TIP = "Finds sets, pieces, bosses, places and NPCs.",
    SEARCH_ENTER_HINT = "Enter: open the first result",
    SEARCH_ESC_HINT = "Esc: clear the search",
}
ns.L = ns.L or {}
for k, v in pairs(TEXT) do
    if ns.L[k] == nil then ns.L[k] = v end
end

Search.KINDS = { "set", "piece", "boss", "place", "npc" }   -- group order
Search.CAP = 5                                                -- results per group before "n more"
local GROUP_TEXT = { set = "SEARCH_G_SET", piece = "SEARCH_G_PIECE", boss = "SEARCH_G_BOSS",
    place = "SEARCH_G_PLACE", npc = "SEARCH_G_NPC" }

-- Lower-case words of a search text (nil = nothing to search).
function Search.Words(text)
    if type(text) ~= "string" then return nil end
    local words = {}
    for w in text:lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return nil end
    return words
end

-- Every word found (plain) in the lower-case text.
local function Match(lower, words)
    for i = 1, #words do
        if not lower:find(words[i], 1, true) then return false end
    end
    return true
end
Search.Match = Match

-- ---------------------------------------------------------------------------
-- Index (lazy, built once): sources = { {kind, label, lower, sub, items = {[itemID] = true}} },
-- names = {[itemID] = lower name} for items whose name the client already had.
local index

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "a|b|c|@A" -> { "a", "b", "c" } (a last @A / @H field dropped).
local function Fields(entry)
    local f = {}
    for part in (entry .. "|"):gmatch("(.-)|") do f[#f + 1] = Trim(part) end
    if #f > 1 and f[#f]:sub(1, 1) == "@" then f[#f] = nil end
    return f
end

local function Has(s) return type(s) == "string" and s ~= "" end

-- Quest givers from the guide data's quest record ("giver|Name" rows).
local function Givers(quest)
    local D = ns.Data
    if not (Has(quest) and D and D.GuideRecord) then return nil end
    local ok, rows = pcall(D.GuideRecord, "quest", quest)
    if not ok or type(rows) ~= "table" then return nil end
    local out
    for _, r in ipairs(rows) do
        if r.key == "giver" and Has(r[1]) then
            out = out or {}
            out[#out + 1] = r[1]
        end
    end
    return out
end

local function AddSource(idx, kind, label, sub, itemID)
    if not Has(label) then return end
    local key = kind .. ":" .. label:lower()
    local s = idx.byKey[key]
    if not s then
        s = { kind = kind, label = label, lower = label:lower(), items = {} }
        idx.byKey[key] = s
        idx.sources[#idx.sources + 1] = s
    end
    if Has(sub) and not s.sub and sub ~= label then s.sub = sub end
    s.items[itemID] = true
end

local function IndexItem(idx, itemID)
    local raw = type(ns.SourcesData) == "table" and ns.SourcesData[itemID]
    if type(raw) ~= "string" then return end
    for entry in raw:gmatch("[^;]+") do
        local f = Fields(entry)
        local t = f[1]
        if t == "b" then
            AddSource(idx, "boss", f[2], f[3], itemID)
            AddSource(idx, "place", f[3], nil, itemID)
        elseif t == "z" then
            AddSource(idx, "place", f[2], nil, itemID)
        elseif t == "v" then
            AddSource(idx, "npc", f[2], f[3], itemID)
            AddSource(idx, "place", f[3], nil, itemID)
        elseif t == "q" then
            AddSource(idx, "npc", f[4], f[3], itemID)
            AddSource(idx, "place", f[3], nil, itemID)
            for _, giver in ipairs(Givers(f[2]) or {}) do
                AddSource(idx, "npc", giver, f[3], itemID)
            end
        end
    end
end

local function BySourceLabel(a, b)
    if a.lower ~= b.lower then return a.lower < b.lower end
    return a.kind < b.kind
end

function Search.Index()
    if index then return index end
    local idx = { sources = {}, byKey = {}, names = {} }
    local D = ns.Data
    local sets = D and D.GetSets and D:GetSets() or {}
    local seen = {}
    for _, s in ipairs(sets) do
        for _, p in ipairs(s.shown or s.pieces or {}) do
            local id = p.itemID
            if id and not seen[id] then
                seen[id] = true
                IndexItem(idx, id)
            end
        end
    end
    table.sort(idx.sources, BySourceLabel)
    -- A boss / NPC also matches on its place ("stratholme" lists the bosses there too).
    for _, s in ipairs(idx.sources) do
        s.find = s.sub and (s.lower .. "\n" .. s.sub:lower()) or s.lower
    end
    index = idx
    return idx
end

-- Drops the index (tests; data reloads).
function Search.Reset() index = nil end

-- Lower-case item name if the client already has the item cached, else nil.
-- Never asks the server for the item (IsItemDataCachedByID first).
local function NameOf(idx, itemID)
    local n = idx.names[itemID]
    if n then return n end
    local CI = C_Item
    if not (CI and CI.GetItemNameByID) then return nil end
    if CI.IsItemDataCachedByID and not CI.IsItemDataCachedByID(itemID) then return nil end
    local ok, name = pcall(CI.GetItemNameByID, itemID)
    if ok and type(name) == "string" and name ~= "" then
        n = { lower = name:lower(), name = name }
        idx.names[itemID] = n
        return n
    end
end
Search.NameOf = function(itemID) return NameOf(Search.Index(), itemID) end

local function SetLower(s)
    local t = s.name and s.name:lower() or ""
    if type(s.tier) == "string" and s.tier ~= "" then
        local D = ns.Data
        local tn = D and D.TierName and D.TierName(s.tier)
        t = t .. "\n" .. s.tier:lower() .. (type(tn) == "string" and ("\n" .. tn:lower()) or "")
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Search.Find(text[, sets[, expanded]]) -> groups (only groups with results, in KINDS order):
--   { kind, label = "Bosses (2)", n, items = { ... } (at most CAP unless expanded[kind] or it's
--   the only group), more = n - #items, all = every item (sets group: the full set list) }
-- items: set   { kind, label, set }
--        piece { kind, label, itemID, piece, set }            (first listed set holding it)
--        boss / place / npc { kind, label, sub, sets = {...}, n = #sets, itemIDs = {[itemID] = true} }
-- `sets` = the sets results may come from, in display order (default: all sets).
function Search.Find(text, sets, expanded)
    local words = Search.Words(text)
    if not words then return {} end
    local D = ns.Data
    sets = sets or (D and D.GetSets and D:GetSets()) or {}
    expanded = expanded or {}
    local idx = Search.Index()
    local found = { set = {}, piece = {}, boss = {}, place = {}, npc = {} }

    local pieceSeen = {}
    for _, s in ipairs(sets) do
        if Match(SetLower(s), words) then
            found.set[#found.set + 1] = { kind = "set", label = s.name, set = s }
        end
        for _, p in ipairs(s.shown or s.pieces or {}) do
            local id = p.itemID
            if id and not pieceSeen[id] then
                local n = NameOf(idx, id)
                if n and Match(n.lower, words) then
                    pieceSeen[id] = true
                    found.piece[#found.piece + 1] = { kind = "piece", label = n.name, itemID = id, piece = p, set = s }
                end
            end
        end
    end

    for _, src in ipairs(idx.sources) do
        if Match(src.find or src.lower, words) then
            local list = {}
            for _, s in ipairs(sets) do
                for _, p in ipairs(s.shown or s.pieces or {}) do
                    if p.itemID and src.items[p.itemID] then list[#list + 1] = s; break end
                end
            end
            if #list > 0 then
                local g = found[src.kind]
                g[#g + 1] = { kind = src.kind, label = src.label, sub = src.sub, sets = list, n = #list,
                    itemIDs = src.items }
            end
        end
    end

    local groups, nonEmpty = {}, 0
    for _, k in ipairs(Search.KINDS) do
        if #found[k] > 0 then nonEmpty = nonEmpty + 1 end
    end
    local L = ns.L
    for _, k in ipairs(Search.KINDS) do
        local all = found[k]
        if #all > 0 then
            local items = all
            if not expanded[k] and nonEmpty > 1 and #all > Search.CAP then
                items = {}
                for i = 1, Search.CAP do items[i] = all[i] end
            end
            groups[#groups + 1] = { kind = k, n = #all, items = items, more = #all - #items, all = all,
                label = (L[GROUP_TEXT[k]] or TEXT[GROUP_TEXT[k]]):format(#all) }
        end
    end
    return groups
end

-- The first result a click / Enter would open (nil = none).
function Search.First(groups)
    local g = groups and groups[1]
    return g and g.items[1]
end
