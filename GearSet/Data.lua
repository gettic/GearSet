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
