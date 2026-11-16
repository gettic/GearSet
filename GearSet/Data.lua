-- Gear Set: set data layer. Turns the bundled table (SetsData.lua) into one shape:
--   set = { key, id, name, classMask, armor, pieces = { { itemID, slot, order, sourceID } },
--           hint (class mask, 0 = none), kind ("d"/"r"/"p"/"c"/"w"/"f" or nil),
--           faction ("A"/"H" or nil = both), removed (true or nil) }
local _, ns = ...

local Data = {}
ns.Data = Data

local band, lshift = bit.band, bit.lshift
local ARMOR_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4

-- Equip location -> { inventory slot, display order }
local SLOT_BY_EQUIPLOC = {
    INVTYPE_HEAD = { 1, 1 }, INVTYPE_NECK = { 2, 2 }, INVTYPE_SHOULDER = { 3, 3 },
    INVTYPE_CLOAK = { 15, 4 }, INVTYPE_CHEST = { 5, 5 }, INVTYPE_ROBE = { 5, 5 },
    INVTYPE_BODY = { 4, 6 }, INVTYPE_TABARD = { 19, 7 }, INVTYPE_WRIST = { 9, 8 },
    INVTYPE_HAND = { 10, 9 }, INVTYPE_WAIST = { 6, 10 }, INVTYPE_LEGS = { 7, 11 },
    INVTYPE_FEET = { 8, 12 }, INVTYPE_FINGER = { 11, 13 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = { 16, 15 }, INVTYPE_2HWEAPON = { 16, 15 }, INVTYPE_WEAPONMAINHAND = { 16, 15 },
    INVTYPE_WEAPONOFFHAND = { 17, 16 }, INVTYPE_SHIELD = { 17, 16 }, INVTYPE_HOLDABLE = { 17, 16 },
    INVTYPE_RANGED = { 16, 17 }, INVTYPE_RANGEDRIGHT = { 16, 17 }, INVTYPE_THROWN = { 16, 17 },
    INVTYPE_RELIC = { 18, 18 },
}

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemSetInfo = (C_Item and C_Item.GetItemSetInfo) or GetItemSetInfo
local GetItemSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo

-- Item name if the client has it loaded, else nil.
local function ItemName(itemID)
    local name
    if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(itemID) end
    if not name and GetItemInfo then name = GetItemInfo(itemID) end
    return name
end

-- The bundled classic table (SetsData.lua).
local function ClassicTable()
    return ns.ClassicSets
end

function Data.ClassBit(classID)
    return lshift(1, classID - 1)
end

-- Display rule: classMask 0 = every class (the tooltip/header use the hint separately).
function Data.SetHasClass(set, classID)
    return set.classMask == 0 or band(set.classMask, Data.ClassBit(classID)) ~= 0
end

-- Heaviest armor each class can wear at level 60 (1 cloth .. 4 plate; warcraft.wiki.gg/wiki/Armor).
-- Classes not listed (none in this game) are never hidden by the armor rule.
local CLASS_MAX_ARMOR = {
    [1] = 4, [2] = 4,                 -- Warrior, Paladin: plate
    [3] = 3, [7] = 3,                 -- Hunter, Shaman: mail
    [4] = 2, [11] = 2,                -- Rogue, Druid: leather
    [5] = 1, [8] = 1, [9] = 1,        -- Priest, Mage, Warlock: cloth
}

-- Filter rule ("Only my class", Class dropdown): the class mask if the set has one,
-- else the class hint (Dungeon Set 1/2), else what the class can wear.
function Data.SetForClass(set, classID)
    if not classID then return true end
    local b = Data.ClassBit(classID)
    if set.classMask ~= 0 then return band(set.classMask, b) ~= 0 end
    if (set.hint or 0) ~= 0 then return band(set.hint, b) ~= 0 end
    local max = CLASS_MAX_ARMOR[classID]
    if not max or not set.armor or set.armor == 0 then return true end
    return set.armor <= max
end

-- Player's faction as the data letter: "A", "H" or nil (neutral / unknown).
function Data.PlayerFaction()
    local group = UnitFactionGroup and UnitFactionGroup("player")
    if group == "Alliance" then return "A" end
    if group == "Horde" then return "H" end
    return nil
end

-- Localized faction name for "A"/"H" (Blizzard's FACTION_ALLIANCE / FACTION_HORDE).
function Data.FactionName(letter)
    if letter == "A" then return FACTION_ALLIANCE or ns.L.ALLIANCE end
    if letter == "H" then return FACTION_HORDE or ns.L.HORDE end
    return nil
end

function Data.ArmorName(subclass)
    if not subclass or subclass == 0 then return nil end
    return GetItemSubClassInfo and GetItemSubClassInfo(ARMOR_CLASS, subclass) or nil
end

-- One piece from an itemID; nil if this client doesn't know the item.
-- Also returns the armor subclass (1 cloth .. 4 plate) when the piece counts for
-- the set's armor type (armor, not a cloak); only used while building, not stored.
local function MakePiece(itemID)
    local id, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstant(itemID)
    if not id then return nil end
    local slot = SLOT_BY_EQUIPLOC[equipLoc] or { 0, 99 }
    local sourceID
    if C_TransmogCollection and C_TransmogCollection.GetItemInfo then
        local ok, _, src = pcall(C_TransmogCollection.GetItemInfo, itemID)
        if ok then sourceID = src end
    end
    local armor
    if classID == ARMOR_CLASS and equipLoc ~= "INVTYPE_CLOAK"
        and subclassID and subclassID >= 1 and subclassID <= 4 then
        armor = subclassID
    end
    return { itemID = itemID, slot = slot[1], order = slot[2], sourceID = sourceID }, armor
end

local function SortPieces(pieces)
    table.sort(pieces, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.itemID < b.itemID
    end)
end

local function BuildClassic(out)
    local tbl = ClassicTable()
    if type(tbl) ~= "table" then return end
    for setID, entry in pairs(tbl) do
        if type(entry) == "table" and type(entry.i) == "table" then
            local pieces = {}
            -- Most common armor type (cloth..plate) among body pieces; cloaks don't count.
            local count, best, bestN = {}, 0, 0
            for _, itemID in ipairs(entry.i) do
                local p, armor = MakePiece(itemID)
                if p then pieces[#pieces + 1] = p end
                if armor then
                    count[armor] = (count[armor] or 0) + 1
                    if count[armor] > bestN then best, bestN = armor, count[armor] end
                end
            end
            if #pieces > 0 then  -- sets whose items this client lacks are skipped
                SortPieces(pieces)
                local name = GetItemSetInfo and GetItemSetInfo(setID)
                out[#out + 1] = {
                    key = "c" .. setID, id = setID,
                    name = (name and name ~= "") and name or ns.L.UNKNOWN_SET:format(setID),
                    classMask = tonumber(entry.c) or 0,
                    armor = best,
                    pieces = pieces,
                    -- optional fields (missing = old behaviour)
                    hint = tonumber(entry.h) or 0,
                    kind = (type(entry.k) == "string" and entry.k ~= "") and entry.k or nil,
                    faction = (entry.f == "A" or entry.f == "H") and entry.f or nil,
                    removed = (entry.r ~= nil and entry.r ~= false and entry.r ~= 0) or nil,
                }
            end
        end
    end
end

-- Builds the list once (on first open), not at login.
function Data:GetSets()
    if self.sets then return self.sets end
    local sets = {}
    BuildClassic(sets)
    table.sort(sets, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    self.sets, self.byKey = sets, {}
    for _, s in ipairs(sets) do self.byKey[s.key] = s end
    return sets
end

function Data:GetSet(key)
    self:GetSets()
    return key and self.byKey[key]
end

-- Classes that appear in any set (so the class filter lists only real ones).
function Data:GetClasses()
    local list, seen = {}, {}
    local maxID = (GetNumClasses and GetNumClasses()) or 13
    for classID = 1, math.max(maxID, 13) do
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
        if info and not seen[classID] then
            local bit1 = Data.ClassBit(classID)
            for _, s in ipairs(self:GetSets()) do
                local mask = s.classMask ~= 0 and s.classMask or (s.hint or 0)
                if mask ~= 0 and band(mask, bit1) ~= 0 then
                    seen[classID] = true
                    list[#list + 1] = { id = classID, name = info.className, file = info.classFile }
                    break
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Classes to name for a set (tooltip / header): returns list, hinted.
-- list = nil means "all classes" (classMask 0, no hint); hinted = the list comes from
-- the class hint (any class can wear the set).
function Data:SetClassList(set)
    local mask, hinted = set.classMask, false
    if mask == 0 then
        if (set.hint or 0) == 0 then return nil, false end
        mask, hinted = set.hint, true
    end
    local out = {}
    for _, c in ipairs(self:GetClasses()) do
        if band(mask, Data.ClassBit(c.id)) ~= 0 then out[#out + 1] = c end
    end
    return out, hinted
end

-- Armor types that appear in any set.
function Data:GetArmorTypes()
    local list, seen = {}, {}
    for _, s in ipairs(self:GetSets()) do
        if s.armor > 0 and not seen[s.armor] then
            seen[s.armor] = true
            list[#list + 1] = { id = s.armor, name = Data.ArmorName(s.armor) or tostring(s.armor) }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- Sets matching the search text and filters.
function Data:Filter(search, f)
    local out = {}
    search = (search or ""):lower()
    local playerClass = select(3, UnitClass("player"))
    local myFaction = f.myFaction and Data.PlayerFaction()
    local kind = (type(f.kind) == "string" and f.kind ~= "") and f.kind or nil
    for _, s in ipairs(self:GetSets()) do
        local ok = true
        if s.removed and not f.showRemoved then ok = false end
        if ok and search ~= "" and not s.name:lower():find(search, 1, true) then ok = false end
        if ok and f.class ~= 0 and not Data.SetForClass(s, f.class) then ok = false end
        if ok and f.armor ~= 0 and s.armor ~= f.armor then ok = false end
        if ok and kind and s.kind ~= kind then ok = false end
        if ok and myFaction and s.faction and s.faction ~= myFaction then ok = false end
        if ok and f.usable and playerClass and not Data.SetForClass(s, playerClass) then ok = false end
        if ok and f.hideComplete then
            local have, total = ns.Owned:SetCount(s)
            if have >= total then ok = false end
        end
        if ok then out[#out + 1] = s end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Where a piece comes from: ns.SourcesData (SourcesData.lua) holds
--   [itemID] = "type|field|field" with ";" between several sources.
-- Parsed only when a row is opened, then cached per item (nothing at load).
local SOURCE_MAX_LINES = 3
local SOURCE_TYPES = {      -- letter -> Blizzard's TRANSMOG_SOURCE_n, own text key
    b = { 1, "SRC_BOSS" }, z = { nil, "SRC_DROP" }, q = { 2, "SRC_QUEST" },
    v = { 3, "SRC_VENDOR" }, w = { 4, "SRC_WORLD" }, c = { 6, "SRC_PROFESSION" },
}
local sourceCache = {}

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "a|b||c" -> { "a", "b", "", "c" } (empty fields kept)
local function SplitFields(s)
    local out = {}
    for f in (s .. "|"):gmatch("(.-)|") do out[#out + 1] = Trim(f) end
    return out
end

local function TypeWord(letter)
    local t = SOURCE_TYPES[letter]
    local g = t[1] and _G["TRANSMOG_SOURCE_" .. t[1]]   -- z (trash/several bosses) has none
    if type(g) == "string" and g ~= "" then return g end
    return ns.L[t[2]]
end

local function Has(s) return s and s ~= "" end

-- One source entry -> one shown line (nil if it can't be read), and its faction
-- ("A"/"H" from a last field "@A"/"@H", nil = both). Fields past the ones read here
-- are kept for later readers and ignored.
local function SourceLine(entry)
    local f = SplitFields(entry)
    local faction
    local last = f[#f]
    if #f > 1 and last and last:sub(1, 1) == "@" then
        local letter = last:sub(2, 2)
        if letter == "A" or letter == "H" then faction = letter end
        f[#f] = nil
    end
    local kind, a, b, c = f[1], f[2], f[3], f[4]
    if kind == "x" then return Has(a) and a or nil, faction end
    if not SOURCE_TYPES[kind] then return nil end
    local word = TypeWord(kind)
    local text
    if kind == "c" then
        if not Has(a) then return word, faction end
        text = Has(b) and ("%s (%s)"):format(a, b) or a
    elseif kind == "w" then
        text = Has(a) and a or nil
    else
        if Has(a) and Has(b) then text = a .. " - " .. b
        else text = Has(a) and a or (Has(b) and b or nil) end
        if text and kind == "v" and Has(c) then text = ("%s (%s)"):format(text, c) end
        if kind == "q" and Has(c) then
            local from = ns.L.SRC_FROM:format(c)
            text = text and ("%s (%s)"):format(text, from) or from
        end
    end
    return text and (word .. ": " .. text) or word, faction
end

-- Returns shown lines (max 3 + "+N more"), all lines, and whether the source is known.
-- Shown: when the item has lines for the player's faction, lines tagged for the other
-- faction are left out (untagged lines always show). All: every line, tagged ones
-- marked with the faction name (for the report link).
function Data:GetSourceLines(piece)
    local itemID = piece and piece.itemID
    if not itemID then return { ns.L.SRC_UNKNOWN }, {}, false end
    local hit = sourceCache[itemID]
    if not hit then
        local parsed, all = {}, {}
        local mine, hasMine = Data.PlayerFaction(), false
        local tbl = ns.SourcesData
        local raw = type(tbl) == "table" and tbl[itemID]
        if type(raw) == "string" then
            for entry in raw:gmatch("[^;]+") do
                local line, faction = SourceLine(entry)
                if line then
                    parsed[#parsed + 1] = { line, faction }
                    if faction and faction == mine then hasMine = true end
                    local fname = faction and Data.FactionName(faction)
                    all[#all + 1] = fname and ("%s (%s)"):format(line, fname) or line
                end
            end
        end
        local lines = {}
        for _, p in ipairs(parsed) do
            if not (hasMine and p[2] and p[2] ~= mine) then lines[#lines + 1] = p[1] end
        end
        local shown = {}
        if #lines == 0 then
            shown[1] = ns.L.SRC_UNKNOWN
        else
            for i = 1, math.min(#lines, SOURCE_MAX_LINES) do shown[i] = lines[i] end
            if #lines > SOURCE_MAX_LINES then
                shown[#shown + 1] = ns.L.SRC_MORE:format(#lines - SOURCE_MAX_LINES)
            end
        end
        hit = { shown = shown, all = all }
        sourceCache[itemID] = hit
    end
    return hit.shown, hit.all, #hit.all > 0
end

-- ---------------------------------------------------------------------------
-- Item tooltip text, read on demand (never at login, in OnUpdate or over all sets).
-- C_TooltipInfo.GetItemByID (listed for Forever 1.60.1 on warcraft.wiki.gg), else one
-- reused hidden GameTooltip that is cleared and hidden right after reading.
-- Returns { { text = left, right = right or nil, r, g, b }, ... } or nil.
local scanTip
local function StripCodes(s)
    if type(s) ~= "string" then return nil end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function LinesFromTooltipInfo(itemID)
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local out = {}
    for _, line in ipairs(data.lines) do
        if line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then
            pcall(TooltipUtil.SurfaceArgs, line)   -- older 10.0 data had the fields nested
        end
        local text = StripCodes(line.leftText)
        if text and text ~= "" then
            local c = line.leftColor
            out[#out + 1] = { text = text, right = StripCodes(line.rightText),
                r = c and c.r or 1, g = c and c.g or 1, b = c and c.b or 1 }
        end
    end
    return out
end

local function LinesFromHiddenTooltip(itemID)
    if not scanTip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "GearSetScanTooltip", nil, "GameTooltipTemplate")
        if not ok or not tip then return nil end
        scanTip = tip
    end
    local tip = scanTip
    tip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    local ok = pcall(tip.SetItemByID, tip, itemID)
    local out
    if ok then
        out = {}
        for i = 1, tip:NumLines() or 0 do
            local left = _G["GearSetScanTooltipTextLeft" .. i]
            local right = _G["GearSetScanTooltipTextRight" .. i]
            local text = left and StripCodes(left:GetText())
            if text and text ~= "" then
                local r, g, b = left:GetTextColor()
                local rt = right and right:IsShown() and StripCodes(right:GetText()) or nil
                out[#out + 1] = { text = text, right = rt, r = r or 1, g = g or 1, b = b or 1 }
            end
        end
    end
    tip:ClearLines()
    tip:Hide()
    return out
end

function Data:GetItemTooltipLines(itemID)
    if not itemID then return nil end
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local lines = LinesFromTooltipInfo(itemID)
        if lines then return lines end
    end
    return LinesFromHiddenTooltip(itemID)
end

-- Turns a Blizzard format string ("(%d) Set: %s") into an anchored Lua pattern.
local function FormatToPattern(fmt)
    fmt = fmt:gsub("%%%d+%$([ds])", "%%%1")            -- "%1$s" -> "%s"
    fmt = fmt:gsub("%%d", "\1"):gsub("%%s", "\2")
    fmt = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    fmt = fmt:gsub("\1", "(%%d+)"):gsub("\2", "(.+)")
    return "^" .. fmt .. "$"
end
Data.FormatToPattern = FormatToPattern

local bonusPatterns
local function BonusPatterns()
    if not bonusPatterns then
        local gray = type(ITEM_SET_BONUS_GRAY) == "string" and ITEM_SET_BONUS_GRAY or "(%d) Set: %s"
        local active = type(ITEM_SET_BONUS) == "string" and ITEM_SET_BONUS or "Set: %s"
        bonusPatterns = { gray = FormatToPattern(gray), active = FormatToPattern(active) }
    end
    return bonusPatterns
end

-- Bonus lines out of tooltip lines: { { n = pieces, text } | { active = true, text } }.
-- The game shows bonuses already in effect without the number ("Set: ...").
function Data.ParseSetBonuses(lines)
    local p, out = BonusPatterns(), {}
    for _, l in ipairs(lines or {}) do
        local n, text = l.text:match(p.gray)
        if n then
            out[#out + 1] = { n = tonumber(n), text = text }
        else
            text = l.text:match(p.active)
            if text then out[#out + 1] = { active = true, text = text } end
        end
    end
    return out
end

-- Set bonuses of a set, from the item tooltip of its first piece. Cached per set
-- (an empty list = "no bonus" is cached too). If the item isn't loaded yet, returns
-- nil and tries once more when it has loaded, then calls onReady(set, bonuses).
local bonusCache, bonusWaiting = {}, {}

local function ReadBonuses(set)
    local piece = set.pieces and set.pieces[1]
    local lines = piece and Data:GetItemTooltipLines(piece.itemID)
    return Data.ParseSetBonuses(lines)
end

function Data:GetSetBonuses(set, onReady)
    if not set then return nil end
    local hit = bonusCache[set.key]
    if hit then return hit end
    if bonusWaiting[set.key] then return nil end
    local piece = set.pieces and set.pieces[1]
    if not piece then bonusCache[set.key] = {}; return bonusCache[set.key] end
    if ItemName(piece.itemID) or not (Item and Item.CreateFromItemID) then
        hit = ReadBonuses(set)
        bonusCache[set.key] = hit
        return hit
    end
    -- Not loaded: the one retry, when the item data arrives.
    bonusWaiting[set.key] = true
    Item:CreateFromItemID(piece.itemID):ContinueOnItemLoad(function()
        bonusWaiting[set.key] = nil
        local result = ReadBonuses(set)
        bonusCache[set.key] = result
        if onReady then onReady(set, result) end
    end)
    return nil
end

-- ---------------------------------------------------------------------------
-- Guide page: how to get one piece, built on first open from SourcesData plus
-- ns.GuideData (GuideData.lua; format in plans\piece-guide\data-contract.md).
-- Every GuideData record is optional: without one the page shows what SourcesData
-- has and "not known". Result: a list of blocks for UI\GuidePage.lua:
--   { k = "head"|"sub"|"row"|"text"|"bullet"|"step"|"fold", text, label, here, blocks }
local guideCache, recordCache = {}, {}
local GUIDE_MAX_DEPTH = 4
local BIND_ON_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.OnEquip) or 2

-- "key|a|b;key|a|@H" -> { { key = "key", "a", "b" }, { key = "key", "a", fac = "H" } }
local function ParseRecord(raw)
    local rows = {}
    for part in raw:gmatch("[^;]+") do
        local f = SplitFields(part)
        local fac
        local last = f[#f]
        if #f > 1 and last:sub(1, 1) == "@" then
            local letter = last:sub(2, 2)
            if letter == "A" or letter == "H" then fac = letter end
            f[#f] = nil
        end
        if Has(f[1]) then
            rows[#rows + 1] = { key = f[1], f[2], f[3], f[4], f[5], fac = fac }
        end
    end
    return rows
end

-- One GuideData record as parsed rows (cached), or nil.
function Data.GuideRecord(tname, key)
    if key == nil or key == "" then return nil end
    local g = ns.GuideData
    local t = type(g) == "table" and g[tname]
    if type(t) ~= "table" then return nil end
    local c = recordCache[tname]
    if not c then c = {}; recordCache[tname] = c end
    local hit = c[key]
    if hit == nil then
        local raw = t[key]
        hit = (type(raw) == "string" and raw ~= "") and ParseRecord(raw) or false
        c[key] = hit
    end
    return hit or nil
end

-- true / false, or nil while the item hasn't loaded.
function Data.IsBindOnEquip(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if get then
        local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = get(itemID)
        if not name then return nil end
        if bindType then return bindType == BIND_ON_EQUIP end
    end
    local lines = Data:GetItemTooltipLines(itemID)
    if not lines then return nil end
    local boe = type(ITEM_BIND_ON_EQUIP) == "string" and ITEM_BIND_ON_EQUIP or "Binds when equipped"
    for _, l in ipairs(lines) do
        if l.text == boe then return true end
    end
    return false
end

local function IsMine(row, mine)
    return not row.fac or not mine or row.fac == mine
end

-- First non-empty value of a key (player's faction or untagged).
local function Field(rows, key, mine)
    for _, r in ipairs(rows or {}) do
        if r.key == key and Has(r[1]) and IsMine(r, mine) then return r[1], r end
    end
end

local function Concat(a, b)
    if not a then return b end
    if not b then return a end
    local out = {}
    for _, r in ipairs(a) do out[#out + 1] = r end
    for _, r in ipairs(b) do out[#out + 1] = r end
    return out
end

local function Add(out, k, text, label)
    out[#out + 1] = { k = k, text = text, label = label }
    return out[#out]
end

-- "43.4,52.2" -> "(43, 52)"
local function Coords(s)
    local x, y = (s or ""):match("^%s*([%d%.]+)%s*,%s*([%d%.]+)")
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then return nil end
    return ("(%d, %d)"):format(math.floor(x + 0.5), math.floor(y + 0.5))
end

-- "Zone, place text (43, 52)" from zone/where/xy rows, or nil.
local function WhereText(rec, mine)
    if not rec then return nil end
    local zone, where = Field(rec, "zone", mine), Field(rec, "where", mine)
    local text = (zone and where) and (zone .. ", " .. where) or zone or where
    local xy = Coords(Field(rec, "xy", mine))
    if text and xy then text = text .. " " .. xy end
    return text
end

-- NPC name <title> - where (from the npc record when there is one).
local function NpcText(name, mine)
    local rec = Data.GuideRecord("npc", name)
    local title = Field(rec, "title", mine)
    local text = title and ("%s <%s>"):format(name, title) or name
    local where = WhereText(rec, mine)
    return where and (text .. " - " .. where) or text
end

-- "raid, 40 players, level 60" from a place record.
local function PlaceDesc(rec, mine)
    local L = ns.L
    local parts = {}
    local kind = Field(rec, "kind", mine)
    if kind then parts[#parts + 1] = L["G_KIND_" .. kind:lower()] or kind end
    local size = Field(rec, "size", mine)
    if size then parts[#parts + 1] = L.G_SIZE:format(size) end
    local level = Field(rec, "level", mine)
    if level then parts[#parts + 1] = L.G_LEVEL_N:format(level) end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

local function SkillText(r)
    local colors = { "ff8040", "ffff00", "40bf40", "808080" }   -- Blizzard's recipe difficulty colours
    local words = { ns.L.G_SKILL_ORANGE, ns.L.G_SKILL_YELLOW, ns.L.G_SKILL_GREEN, ns.L.G_SKILL_GREY }
    local parts = {}
    for i = 1, 4 do
        if Has(r[i]) then parts[#parts + 1] = ("|cff%s%s %s|r"):format(colors[i], r[i], words[i]) end
    end
    return table.concat(parts, ", ")
end

local AddRows   -- forward

-- A chain or note record inline (cycle and depth guarded).
local function AddRecord(out, tname, key, ctx)
    if not Has(key) or ctx.seen[key] or ctx.depth >= GUIDE_MAX_DEPTH then return end
    local rec = Data.GuideRecord(tname, key)
    if not rec then return end
    ctx.seen[key] = true
    ctx.depth = ctx.depth + 1
    AddRows(out, rec, ctx)
    ctx.depth = ctx.depth - 1
    ctx.seen[key] = nil
end

-- A fold-out: its blocks are built now (shown when the player opens it). Empty -> nothing.
local function AddFold(out, text, fill)
    local blocks = {}
    fill(blocks)
    if #blocks == 0 then return end
    local b = Add(out, "fold", text)
    b.blocks = blocks
end

local BLOCK_KEYS = { p = true, b = true, t = true, s = true, fold = true, see = true, chain = true, recipe = true, from = true }

-- Rows of one or more records: labelled rows first (level/min/type, bring/gold and
-- mat are joined), then text blocks in their order; the other faction's rows go in
-- a fold-out at the end.
function AddRows(out, rows, ctx)
    if not rows then return end
    local L, mine = ns.L, ctx.mine
    local own, other, otherFac = {}, {}, nil
    for _, r in ipairs(rows) do
        if IsMine(r, mine) then own[#own + 1] = r
        else other[#other + 1] = r; otherFac = otherFac or r.fac end
    end
    local level, minLevel, qtype, bring, mats = nil, nil, nil, {}, {}
    for _, r in ipairs(own) do
        local k, a = r.key, r[1]
        if Has(a) then
            if k == "level" then level = a
            elseif k == "min" then minLevel = a
            elseif k == "type" then qtype = a
            elseif k == "bring" then bring[#bring + 1] = a
            elseif k == "gold" then bring[#bring + 1] = L.G_GOLD:format(a)
            elseif k == "mat" then mats[#mats + 1] = Has(r[2]) and (a .. " " .. r[2]) or a
            end
        end
    end
    local done, blocks = {}, {}
    for _, r in ipairs(own) do
        local k, a, b = r.key, r[1], r[2]
        if BLOCK_KEYS[k] then
            blocks[#blocks + 1] = r
        elseif k == "level" or k == "min" or k == "type" then
            if not done.level then
                done.level = true
                local parts = {}
                if level then parts[#parts + 1] = level end
                if minLevel then parts[#parts + 1] = L.G_MIN:format(minLevel) end
                if qtype then parts[#parts + 1] = qtype end
                if #parts > 0 then Add(out, "row", table.concat(parts, ", "), L.G_LEVEL) end
            end
        elseif k == "bring" or k == "gold" then
            if not done.bring and #bring > 0 then
                done.bring = true
                Add(out, "row", "", L.G_BRING)
                for _, t in ipairs(bring) do Add(out, "bullet", t).col = true end   -- in the value column
            end
        elseif k == "mat" then
            if not done.mat and #mats > 0 then
                done.mat = true
                Add(out, "row", table.concat(mats, ", "), L.G_MATS)
            end
        elseif not Has(a) then
            -- empty value: nothing to show
        elseif k == "giver" then Add(out, "row", NpcText(a, mine), L.G_GIVER)
        elseif k == "rep" then Add(out, "row", Has(b) and (a .. " " .. b) or a, L.G_NEEDS)
        elseif k == "rank" then Add(out, "row", Has(b) and L.G_RANK:format(a, b) or L.G_RANK_N:format(a), L.G_NEEDS)
        elseif k == "cost" then Add(out, "row", a, L.G_COST)
        elseif k == "reward" then Add(out, "row", a, L.G_ALSO)
        elseif k == "chance" then Add(out, "row", a, L.G_CHANCE)
        elseif k == "skill" then Add(out, "row", SkillText(r), L.G_SKILL)
        elseif k == "tools" then Add(out, "row", a, L.G_TOOLS)
        elseif k == "l" then Add(out, "row", Has(b) and b or "", a)
        end
        -- zone/where/xy/title/kind/size/need are read by the callers.
    end
    for _, r in ipairs(blocks) do
        local k, a, b, c = r.key, r[1], r[2], r[3]
        if k == "p" and Has(a) then Add(out, "text", a)
        elseif k == "b" and Has(a) then Add(out, "bullet", a)
        elseif k == "t" and Has(a) then Add(out, "head", a)
        elseif k == "s" and (Has(a) or Has(b)) then
            local text = b or ""
            if Has(c) then text = Has(text) and (text .. " - " .. c) or c end
            local step = Add(out, "step", text, a or "")
            step.here = Has(b) and ctx.quest == b or nil
        elseif k == "fold" and Has(a) and Has(b) then
            AddFold(out, a, function(sub)
                if Data.GuideRecord("chain", b) then AddRecord(sub, "chain", b, ctx)
                else AddRecord(sub, "note", b, ctx) end
            end)
        elseif k == "see" then AddRecord(out, "note", a, ctx)
        elseif k == "chain" then AddRecord(out, "chain", a, ctx)
        elseif k == "recipe" and Has(a) then
            Add(out, "head", L.G_RECIPE)
            Add(out, "sub", a)
        elseif k == "from" and Has(a) then
            if a == "q" and Has(b) then
                Add(out, "row", b, L.G_QUEST)
                AddRecord(out, "quest", b, ctx)
            elseif a == "v" and Has(b) then Add(out, "row", NpcText(b, mine), L.G_FROM)
            elseif a == "t" then Add(out, "text", L.G_TRAINER)
            elseif a == "d" and Has(b) then Add(out, "row", b, L.G_DROP)
            end
        end
    end
    if #other > 0 then
        AddFold(out, L.G_OTHER_VERSION:format(Data.FactionName(otherFac) or otherFac), function(sub)
            local saved = ctx.mine
            ctx.mine = otherFac
            AddRows(sub, other, ctx)
            ctx.mine = saved
        end)
    end
end

-- SourcesData entries of an item: { kind, a, b, c, fac }.
local function SourceEntries(itemID)
    local out = {}
    local tbl = ns.SourcesData
    local raw = type(tbl) == "table" and tbl[itemID]
    if type(raw) ~= "string" then return out end
    for entry in raw:gmatch("[^;]+") do
        local f = SplitFields(entry)
        local fac
        local last = f[#f]
        if #f > 1 and last and last:sub(1, 1) == "@" then
            local letter = last:sub(2, 2)
            if letter == "A" or letter == "H" then fac = letter end
            f[#f] = nil
        end
        if SOURCE_TYPES[f[1]] or f[1] == "x" then
            out[#out + 1] = { kind = f[1], a = f[2], b = f[3], c = f[4], fac = fac }
        end
    end
    return out
end

-- Place lines: "Instance: name - raid, 40 players, level 60", "Where: ..."; the
-- place's need rows are kept for the "Before you go" part.
local function AddPlace(out, place, label, ctx, state)
    local L = ns.L
    local rec = Data.GuideRecord("place", place)
    if Has(place) then
        local desc = PlaceDesc(rec, ctx.mine)
        Add(out, "row", desc and (place .. " - " .. desc) or place, label)
    end
    Add(out, "row", WhereText(rec, ctx.mine) or L.G_NOT_KNOWN, L.G_WHERE)
    for _, r in ipairs(rec or {}) do
        if r.key == "need" and Has(r[1]) then
            local id = r[1] .. "|" .. (r[2] or "") .. "|" .. (r.fac or "")
            if not state.needSeen[id] then
                state.needSeen[id] = true
                state.needs[#state.needs + 1] = r
            end
        end
    end
end

local function HasKey(rows, key)
    for _, r in ipairs(rows or {}) do if r.key == key then return true end end
    return false
end

-- One SourcesData entry as a section. The item's own record goes with the first one.
local function AddSource(out, e, itemID, ctx, state)
    local L = ns.L
    local itemRows
    if not state.itemDone then
        state.itemDone = true
        itemRows = Data.GuideRecord("item", itemID)
    end
    local kind, a, b, c = e.kind, e.a, e.b, e.c
    ctx.quest = nil
    if kind == "x" then
        if Has(a) then
            Add(out, "sub", a)
            AddRecord(out, "note", a, ctx)
        end
        AddRows(out, itemRows, ctx)
        return
    end
    local word = TypeWord(kind)
    if kind == "b" then
        Add(out, "sub", Has(a) and (word .. ": " .. a) or word)
        AddPlace(out, b, L.G_INSTANCE, ctx, state)
        local bossRows = Data.GuideRecord("boss", a)
        if not HasKey(bossRows, "chance") and not HasKey(itemRows, "chance") then
            Add(out, "row", L.G_NOT_KNOWN, L.G_CHANCE)
        end
        AddRows(out, Concat(bossRows, itemRows), ctx)
    elseif kind == "z" or kind == "w" then
        Add(out, "sub", Has(a) and (word .. ": " .. a) or word)
        if Has(a) then AddPlace(out, a, L.G_PLACE, ctx, state) end
        AddRows(out, itemRows, ctx)
    elseif kind == "v" then
        Add(out, "sub", Has(a) and (word .. ": " .. a) or word)
        local npcWhere = Has(a) and WhereText(Data.GuideRecord("npc", a), ctx.mine)
        Add(out, "row", npcWhere or (Has(b) and b) or L.G_NOT_KNOWN, L.G_WHERE)
        if not HasKey(itemRows, "cost") then Add(out, "row", L.G_NOT_KNOWN, L.G_COST) end
        AddRows(out, itemRows, ctx)
        if Has(c) then
            if Data.GuideRecord("note", c) then AddRecord(out, "note", c, ctx)
            else Add(out, "row", c, L.G_NOTE) end
        end
    elseif kind == "q" then
        Add(out, "sub", Has(a) and (word .. ": " .. a) or word)
        local qrec = Data.GuideRecord("quest", a)
        if not HasKey(qrec, "giver") then
            if Has(c) then Add(out, "row", NpcText(c, ctx.mine), L.G_GIVER)
            elseif Has(b) then Add(out, "row", b, L.G_WHERE)
            else Add(out, "row", L.G_NOT_KNOWN, L.G_GIVER) end
        end
        ctx.quest = a
        AddRows(out, Concat(qrec, itemRows), ctx)
        ctx.quest = nil
    elseif kind == "c" then
        Add(out, "sub", Has(a) and (word .. ": " .. a .. (Has(b) and (" " .. b) or "")) or word)
        state.crafted = true
        if not HasKey(itemRows, "mat") then Add(out, "row", L.G_NOT_KNOWN, L.G_MATS) end
        AddRows(out, itemRows, ctx)
    end
end

-- Blocks for the guide page of one piece (cached; see the format above).
function Data:GetGuide(piece)
    local L = ns.L
    local itemID = piece and piece.itemID
    if not itemID then return {} end
    local hit = guideCache[itemID]
    if hit then return hit end

    local mine = Data.PlayerFaction()
    local ctx = { mine = mine, seen = {}, depth = 0 }
    local state = { needs = {}, needSeen = {} }
    local entries = SourceEntries(itemID)
    local hasMine = false
    for _, e in ipairs(entries) do if e.fac and e.fac == mine then hasMine = true end end
    local own, other = {}, {}
    local ownQuest = {}
    for _, e in ipairs(entries) do
        if hasMine and e.fac and e.fac ~= mine then other[#other + 1] = e
        else
            own[#own + 1] = e
            if e.kind == "q" and Has(e.a) then ownQuest[e.a] = true end
        end
    end

    local out = {}
    Add(out, "head", L.G_HOW)
    if #own == 0 then Add(out, "text", L.SRC_UNKNOWN) end
    for _, e in ipairs(own) do AddSource(out, e, itemID, ctx, state) end
    if not state.itemDone then AddRows(out, Data.GuideRecord("item", itemID), ctx) end

    -- Before you go: keys and attunements of the places above.
    if #state.needs > 0 then
        Add(out, "head", L.G_BEFORE)
        local said = {}
        for _, r in ipairs(state.needs) do
            if IsMine(r, mine) then
                if not said[r[1]] then said[r[1]] = true; Add(out, "text", L.G_NEED_TEXT:format(r[1])) end
                AddRecord(out, "chain", r[2], ctx)
            end
        end
        for _, r in ipairs(state.needs) do
            if not IsMine(r, mine) then
                AddFold(out, L.G_OTHER_VERSION:format(Data.FactionName(r.fac) or r.fac), function(sub)
                    local saved = ctx.mine
                    ctx.mine = r.fac
                    if not said[r[1]] then Add(sub, "text", L.G_NEED_TEXT:format(r[1])) end
                    AddRecord(sub, "chain", r[2], ctx)
                    ctx.mine = saved
                end)
            end
        end
    end

    -- Crafted and binds when equipped: other ways to get it.
    local cacheable = true
    if state.crafted then
        local boe = Data.IsBindOnEquip(itemID)
        if boe == nil then cacheable = false
        elseif boe then
            Add(out, "head", L.G_NOT_CRAFTER)
            Add(out, "text", L.G_BOE_TIP)
        end
    end

    -- The other faction's sources (a quest with a record already covers both).
    local rest = {}
    for _, e in ipairs(other) do
        if not (e.kind == "q" and ownQuest[e.a] and Data.GuideRecord("quest", e.a)) then rest[#rest + 1] = e end
    end
    if #rest > 0 then
        local fac = rest[1].fac
        AddFold(out, L.G_OTHER_VERSION:format(Data.FactionName(fac) or fac), function(sub)
            local saved = ctx.mine
            ctx.mine = fac
            local s2 = { needs = {}, needSeen = {}, itemDone = true }
            for _, e in ipairs(rest) do AddSource(sub, e, itemID, ctx, s2) end
            ctx.mine = saved
        end)
    end

    if cacheable then guideCache[itemID] = out end
    return out
end

-- ---------------------------------------------------------------------------
-- "Report wrong source" link (one per set): a new GitHub issue with title and body
-- filled in. Never holds the character's name or realm.
local REPORT_BASE = "https://github.com/gettic/GearSet/issues/new"
local REPORT_MAX_URL = 1900
local WIKI_SEARCH = "https://warcraft.wiki.gg/wiki/Special:Search?search="

local function UrlEncode(s)
    return (tostring(s):gsub("[^A-Za-z0-9%-_%.~]", function(ch)
        return ("%%%02X"):format(ch:byte())
    end))
end
Data.UrlEncode = UrlEncode

local function AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get(ns.ADDON or "GearSet", "Version")
    return v or "?"
end

-- Text to search for a piece online: its name (item ID until the name has loaded).
function Data:SearchText(piece)
    return ItemName(piece.itemID) or tostring(piece.itemID)
end

-- Warcraft Wiki search for the piece (the site the source data comes from).
function Data:WikiSearchURL(piece)
    return WIKI_SEARCH .. UrlEncode(self:SearchText(piece))
end

-- One body line per piece. mode 1: name + shown lines, 2: ID + shown lines,
-- 3: ID + the short data code (e.g. "b|Onyxia|Onyxia's Lair").
local function PieceReportLine(piece, mode)
    local id = piece.itemID
    local src
    if mode == 3 then
        local tbl = ns.SourcesData
        src = (type(tbl) == "table" and tbl[id]) or "?"
    else
        local shown, all = Data:GetSourceLines(piece)
        src = table.concat(#all > 0 and all or shown, "; ")
    end
    local name = mode == 1 and ItemName(id)
    if name then return ("- %s (%d): %s"):format(name, id, src) end
    return ("- %d: %s"):format(id, src)
end

-- Link for a whole set: every piece with its sources, addon version, client, language.
-- Shortened step by step to stay under REPORT_MAX_URL (non-Latin names grow a lot
-- when encoded): names -> item IDs -> data codes -> cut the list with "...".
function Data:SetReportURL(set)
    local version, build = "?", "?"
    if GetBuildInfo then version, build = GetBuildInfo() end
    local locale = GetLocale and GetLocale() or "?"
    local setName = set.name or "?"
    local title = UrlEncode(("Wrong source: %s (set %s)"):format(setName, tostring(set.id)))

    local function Build(lines, cut)
        local body = { ("Set: %s (%s)"):format(setName, tostring(set.id)) }
        for _, l in ipairs(lines) do body[#body + 1] = l end
        if cut then body[#body + 1] = "..." end
        body[#body + 1] = "Addon: " .. AddonVersion()
        body[#body + 1] = ("Client: %s (%s) %s"):format(tostring(version), tostring(build), locale)
        body[#body + 1] = ""
        body[#body + 1] = "What is wrong:"
        body[#body + 1] = ""
        return ("%s?title=%s&body=%s&labels=wrong-source"):format(REPORT_BASE,
            title, UrlEncode(table.concat(body, "\n")))
    end

    local url, lines
    for mode = 1, 3 do
        lines = {}
        for _, p in ipairs(set.pieces) do lines[#lines + 1] = PieceReportLine(p, mode) end
        url = Build(lines)
        if #url <= REPORT_MAX_URL then return url end
    end
    while #lines > 0 and #url > REPORT_MAX_URL do
        lines[#lines] = nil
        url = Build(lines, true)
    end
    return url
end

-- /gs check: verify the bundled table against the game's own item data.
function Data:CheckClassic()
    local L = ns.L
    local tbl = ClassicTable()
    if type(tbl) ~= "table" then
        ns.Print(L.CHECK_NO_LIST)
        return
    end
    local problems, setsN, itemsN, pending = 0, 0, 0, 0
    local done = false
    local function Report(msg)
        problems = problems + 1
        if problems <= 40 then ns.Print(msg) end
    end
    local function Finish()
        if done then return end
        done = true
        ns.Print(L.CHECK_DONE:format(setsN, itemsN, problems, problems > 40 and L.CHECK_FIRST_40 or ""))
    end
    for setID, entry in pairs(tbl) do
        setsN = setsN + 1
        local name = GetItemSetInfo and GetItemSetInfo(setID)
        if not name or name == "" then Report(L.CHECK_NO_SET:format(setID)) end
        if type(entry) ~= "table" or type(entry.i) ~= "table" then
            Report(L.CHECK_BAD_ENTRY:format(setID))
        else
            for _, itemID in ipairs(entry.i) do
                itemsN = itemsN + 1
                if not GetItemInfoInstant(itemID) then
                    Report(L.CHECK_NO_ITEM:format(setID, itemID))
                else
                    pending = pending + 1
                    local item = Item:CreateFromItemID(itemID)
                    item:ContinueOnItemLoad(function()
                        local itemSetID = select(16, C_Item.GetItemInfo(itemID))
                        if itemSetID ~= setID then
                            Report(L.CHECK_WRONG_SET:format(setID, itemID,
                                (itemSetID and itemSetID ~= 0) and tostring(itemSetID) or L.CHECK_NONE))
                        end
                        pending = pending - 1
                        if pending == 0 then Finish() end
                    end)
                end
            end
        end
    end
    if pending == 0 then Finish() else
        C_Timer.After(15, function()
            if not done and pending > 0 then Report(L.CHECK_SLOW:format(pending)) end
            Finish()
        end)
    end
end
