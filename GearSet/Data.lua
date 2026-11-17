-- Gear Set: set data layer. Turns the bundled table (SetsData.lua) into one shape:
--   set = { key, id, name, classMask, armor, pieces = { { itemID, slot, order, sourceID } },
--           hint (class mask, 0 = none), kind ("d"/"r"/"p"/"c"/"w"/"f" or nil),
--           faction ("A"/"H" or nil = both), removed (true or nil), tier ("T2", "D1", ... or nil),
--           checked (true = checked on WoW Forever), unreleased (true = whole set not out on Forever),
--           later = { pieces of a released set that are not out yet }, shown = pieces + later }
--   A piece not out yet has piece.later = true. set.pieces holds the pieces that count (have/total,
--   model, bonuses); a released set's later pieces are only in set.later / set.shown (greyed, not counted).
--   Contract: plans\v1.0.0\beta1-interface.md.
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

-- ---------------------------------------------------------------------------
-- Data version and WoW Forever flags (contract: plans\v1.0.0\beta1-interface.md).
-- ns.DataInfo (SetsData.lua); set fields fc / u / up; ns.SourceFlags (SourcesData.lua):
-- [itemID] = "flags;flags", one part per source, f = checked on Forever, u = not out yet.

local DATA_INFO_FALLBACK = { version = 0, checked = "?", game = "?" }

-- { version, checked, game } of the bundled data; never nil, wrong types -> fallback values.
function Data.DataInfo()
    local d = ns.DataInfo
    if type(d) ~= "table" then return DATA_INFO_FALLBACK end
    return {
        version = tonumber(d.version) or 0,
        checked = (type(d.checked) == "string" and d.checked ~= "") and d.checked or "?",
        game = (type(d.game) == "string" and d.game ~= "") and d.game or "?",
    }
end

-- English fallbacks; Core.lua's ns.L wins when it has the key.
local FLAG_TEXT = {
    FLAG_CLASSIC = "Not confirmed on WoW Forever yet (classic data).",
    FLAG_CHECKED = "Checked on WoW Forever.",
    FLAG_LATER = "Not yet released on WoW Forever.",
    FLAG_SRC_LATER = "This way is not out on WoW Forever yet.",
    FLAG_LATER_SHORT = "Not out yet",
    FLAG_LATER_COUNT = "%d more not out yet",
}
function Data.FlagText(key)
    local L = ns.L
    return (L and L[key]) or FLAG_TEXT[key] or key
end

local function IsOn(v) return v ~= nil and v ~= false and v ~= 0 end

-- Number of sources an item has in SourcesData ("a;b;c" -> 3; empty parts don't count).
local function NumSources(itemID)
    local tbl = ns.SourcesData
    local raw = type(tbl) == "table" and tbl[itemID]
    if type(raw) ~= "string" then return 0 end
    local n = 0
    for _ in raw:gmatch("[^;]+") do n = n + 1 end
    return n
end

-- Flag strings of an item's sources, one per source in SourcesData order ("" = none). Never nil.
function Data.SourceFlags(itemID)
    local tbl = ns.SourceFlags
    local raw = type(tbl) == "table" and tbl[itemID]
    local out = {}
    if type(raw) ~= "string" then return out end
    for part in (raw .. ";"):gmatch("([^;]*);") do out[#out + 1] = part end
    return out
end

function Data.SourceChecked(itemID, index)
    local f = Data.SourceFlags(itemID)[index]
    return f ~= nil and f:find("f", 1, true) ~= nil
end

-- True when the item has sources and every one of them is flagged "not out yet".
local function AllSourcesLater(itemID)
    local tbl = ns.SourceFlags
    if type(tbl) ~= "table" or tbl[itemID] == nil then return false end
    local n = NumSources(itemID)
    if n == 0 then return false end
    local flags = Data.SourceFlags(itemID)
    for i = 1, n do
        if not (flags[i] and flags[i]:find("u", 1, true)) then return false end
    end
    return true
end

local function BuildClassic(out)
    local tbl = ClassicTable()
    if type(tbl) ~= "table" then return end
    for setID, entry in pairs(tbl) do
        if type(entry) == "table" and type(entry.i) == "table" then
            local pieces, later = {}, {}
            local whole = IsOn(entry.u)
            local upSet
            if type(entry.up) == "table" then
                upSet = {}
                for _, id in ipairs(entry.up) do upSet[id] = true end
            end
            -- Most common armor type (cloth..plate) among body pieces; cloaks don't count.
            local count, best, bestN = {}, 0, 0
            for _, itemID in ipairs(entry.i) do
                local p, armor = MakePiece(itemID)
                if p then
                    if whole or (upSet and upSet[itemID]) or AllSourcesLater(itemID) then p.later = true end
                    if p.later and not whole then later[#later + 1] = p else pieces[#pieces + 1] = p end
                end
                if armor then
                    count[armor] = (count[armor] or 0) + 1
                    if count[armor] > bestN then best, bestN = armor, count[armor] end
                end
            end
            -- Every piece not out yet: the whole set counts as not released.
            if #pieces == 0 and #later > 0 then
                whole, pieces, later = true, later, {}
            end
            if #pieces > 0 then  -- sets whose items this client lacks are skipped
                SortPieces(pieces)
                local shown = pieces
                if #later > 0 then
                    SortPieces(later)
                    shown = {}
                    for _, p in ipairs(pieces) do shown[#shown + 1] = p end
                    for _, p in ipairs(later) do shown[#shown + 1] = p end
                end
                local name = GetItemSetInfo and GetItemSetInfo(setID)
                out[#out + 1] = {
                    key = "c" .. setID, id = setID,
                    name = (name and name ~= "") and name or ns.L.UNKNOWN_SET:format(setID),
                    classMask = tonumber(entry.c) or 0,
                    armor = best,
                    pieces = pieces,
                    later = later,
                    shown = shown,
                    -- optional fields (missing = old behaviour)
                    hint = tonumber(entry.h) or 0,
                    kind = (type(entry.k) == "string" and entry.k ~= "") and entry.k or nil,
                    tier = (type(entry.t) == "string" and entry.t ~= "") and entry.t or nil,
                    faction = (entry.f == "A" or entry.f == "H") and entry.f or nil,
                    removed = IsOn(entry.r) or nil,
                    checked = IsOn(entry.fc) or nil,
                    unreleased = whole or nil,
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

-- Flag totals for /gs check (no item loads). badFlags: SourceFlags entries that aren't strings,
-- use letters other than f/u, or have more parts than the item has sources.
function Data:FlagCounts()
    local c = { sets = 0, setsChecked = 0, setsUnreleased = 0, pieces = 0, piecesLater = 0,
        sources = 0, sourcesChecked = 0, sourcesLater = 0, badFlags = 0 }
    for _, s in ipairs(self:GetSets()) do
        c.sets = c.sets + 1
        if s.checked then c.setsChecked = c.setsChecked + 1 end
        if s.unreleased then c.setsUnreleased = c.setsUnreleased + 1 end
        for _, p in ipairs(s.shown or s.pieces) do
            c.pieces = c.pieces + 1
            if p.later then c.piecesLater = c.piecesLater + 1 end
        end
    end
    if type(ns.SourcesData) == "table" then
        for itemID in pairs(ns.SourcesData) do
            local n = NumSources(itemID)
            c.sources = c.sources + n
            local flags = Data.SourceFlags(itemID)
            for i = 1, n do
                local f = flags[i]
                if f and f:find("f", 1, true) then c.sourcesChecked = c.sourcesChecked + 1 end
                if f and f:find("u", 1, true) then c.sourcesLater = c.sourcesLater + 1 end
            end
        end
    end
    if type(ns.SourceFlags) == "table" then
        for itemID, raw in pairs(ns.SourceFlags) do
            if type(raw) ~= "string" or raw:find("[^fu;]") or #Data.SourceFlags(itemID) > NumSources(itemID) then
                c.badFlags = c.badFlags + 1
            end
        end
    end
    return c
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
        if ok and not f.showHidden and Data.IsHidden(s) then ok = false end
        if ok and search ~= "" and not s.name:lower():find(search, 1, true)
            and not (s.tier and (s.tier:lower():find(search, 1, true)
                or Data.TierName(s.tier):lower():find(search, 1, true))) then
            ok = false
        end
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
-- Parsed only when needed (guide page), then cached per item.
local SOURCE_TYPES = {      -- letter -> Blizzard's TRANSMOG_SOURCE_n, own text key
    b = { 1, "SRC_BOSS" }, z = { nil, "SRC_DROP" }, q = { 2, "SRC_QUEST" },
    v = { 3, "SRC_VENDOR" }, w = { 4, "SRC_WORLD" }, c = { 6, "SRC_PROFESSION" },
}

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "a|b||c" -> { "a", "b", "", "c" } (empty fields kept)
local function SplitFields(s)
    local out = {}
    for f in (s .. "|"):gmatch("(.-)|") do out[#out + 1] = Trim(f) end
    return out
end

-- "a|b|@H" -> { "a", "b" }, "H": fields, and the faction of a last "@A"/"@H" field
-- (always last; nil = both factions). Used by sources and guide records alike.
local function SplitTagged(s)
    local f = SplitFields(s)
    local fac
    local last = f[#f]
    if #f > 1 and last and last:sub(1, 1) == "@" then
        local letter = last:sub(2, 2)
        if letter == "A" or letter == "H" then fac = letter end
        f[#f] = nil
    end
    return f, fac
end

local function TypeWord(letter)
    local t = SOURCE_TYPES[letter]
    local g = t[1] and _G["TRANSMOG_SOURCE_" .. t[1]]   -- z (trash/several bosses) has none
    if type(g) == "string" and g ~= "" then return g end
    return ns.L[t[2]]
end

local function Has(s) return s and s ~= "" end

-- ---------------------------------------------------------------------------
-- Item tooltip text, read on demand (never at login, in OnUpdate or over all sets).
-- C_TooltipInfo.GetItemByID (listed for Forever 1.60.1 on warcraft.wiki.gg), else one
-- reused hidden GameTooltip that is cleared and hidden right after reading.
-- Returns { { text = left, right = right or nil, r, g, b }, ... } or nil.
local scanTip
-- Plain text from UI text: colour codes, textures (|T...|t), links (|H...|h[x]|h -> x)
-- and |n newlines. Also used by the guide page's copy view.
local function StripCodes(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h%[?(.-)%]?|h", "%1"):gsub("|T.-|t", ""):gsub("|n", "\n")
    return s
end
Data.StripCodes = StripCodes

-- Midnight "secret" values (probe: issecretvalue exists): never read or change them.
local function IsSecret(v)
    if issecretvalue then
        local ok, s = pcall(issecretvalue, v)
        return not ok or s == true
    end
    return false
end
Data.IsSecret = IsSecret

local function LinesFromTooltipInfo(itemID)
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(data) ~= "table" or IsSecret(data.lines) or type(data.lines) ~= "table" then return nil end
    local out = {}
    for _, line in ipairs(data.lines) do
        if line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then
            pcall(TooltipUtil.SurfaceArgs, line)   -- older 10.0 data had the fields nested
        end
        local text = not IsSecret(line.leftText) and StripCodes(line.leftText) or nil
        if text and text ~= "" then
            local c = line.leftColor
            out[#out + 1] = { text = text, right = not IsSecret(line.rightText) and StripCodes(line.rightText) or nil,
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
            local raw = left and left:GetText()
            local text = not IsSecret(raw) and StripCodes(raw) or nil
            if text and text ~= "" then
                local r, g, b = left:GetTextColor()
                local rraw = right and right:IsShown() and right:GetText()
                local rt = rraw and not IsSecret(rraw) and StripCodes(rraw) or nil
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

-- Set bonuses of a set, from the item tooltip of its first piece. Cached per set.
-- An empty list ("no bonus") is cached only when the item has no set ID; else the
-- tooltip may just not have its set lines yet, so the next hover reads it again.
-- If the item isn't loaded yet, returns nil and tries once more when it has loaded,
-- then calls onReady(set, bonuses) (not when the load answered at once: the result
-- is returned instead). The cache is cleared when your equipment changes, because
-- the game writes bonuses in effect as "Set: ..." without the piece count.
local bonusCache, bonusWaiting = {}, {}

local function ReadBonuses(set)
    local piece = set.pieces and set.pieces[1]
    local lines = piece and Data:GetItemTooltipLines(piece.itemID)
    local out = Data.ParseSetBonuses(lines)
    if #out == 0 and piece then
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local setID = get and select(16, get(piece.itemID))
        if setID and setID ~= 0 then return out end   -- not cached: set lines may come later
    end
    bonusCache[set.key] = out
    return out
end

function Data:GetSetBonuses(set, onReady)
    if not set then return nil end
    local hit = bonusCache[set.key]
    if hit then return hit end
    if bonusWaiting[set.key] then return nil end
    local piece = set.pieces and set.pieces[1]
    if not piece then bonusCache[set.key] = {}; return bonusCache[set.key] end
    if ItemName(piece.itemID) or not (Item and Item.CreateFromItemID) then
        return ReadBonuses(set)
    end
    -- Not loaded: the one retry, when the item data arrives.
    bonusWaiting[set.key] = true
    local sync, result = true, nil
    Item:CreateFromItemID(piece.itemID):ContinueOnItemLoad(function()
        bonusWaiting[set.key] = nil
        result = ReadBonuses(set)
        if not sync and onReady then onReady(set, result) end
    end)
    sync = false
    return result
end

function Data:ClearSetBonuses()
    wipe(bonusCache)
end

do
    local f = CreateFrame("Frame")
    ns.SafeRegister(f, "PLAYER_EQUIPMENT_CHANGED")   -- also used by Owned.lua
    f:SetScript("OnEvent", function() Data:ClearSetBonuses() end)
end

-- ---------------------------------------------------------------------------
-- Guide page: how to get one piece, built on first open from SourcesData plus
-- ns.GuideData (GuideData.lua; format in plans\piece-guide\data-contract.md).
-- Every GuideData record is optional: without one the page shows what SourcesData
-- has and "not known". Result: a list of blocks for UI\GuidePage.lua:
--   { k = "head"|"sub"|"row"|"text"|"bullet"|"step"|"fold", text, label, here, blocks }
-- bullets may have col (value column) and sub (a grey line under it: where it drops).
local guideCache, recordCache = {}, {}
local GUIDE_MAX_DEPTH = 4
local BIND_ON_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.OnEquip) or 2

-- "key|a|b;key|a|@H" -> { { key = "key", "a", "b" }, { key = "key", "a", fac = "H" } }
local function ParseRecord(raw)
    local rows = {}
    for part in raw:gmatch("[^;]+") do
        local f, fac = SplitTagged(part)
        if Has(f[1]) then
            rows[#rows + 1] = { key = f[1], f[2], f[3], f[4], f[5], f[6], fac = fac }
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

-- Where a hand-in item drops ("You bring" line): "Drops from: Thaddius (Naxxramas)".
-- Key = the bring text without a leading count ("15 Wartorn Leather Scrap"); nil if
-- the drop table has nothing for it.
local function DropText(bring)
    local name = bring:gsub("^%d+%s+", "")
    local rec = Data.GuideRecord("drop", name)
    if not rec then return nil end
    local parts = {}
    for _, r in ipairs(rec) do
        if r.key == "src" and Has(r[1]) then
            parts[#parts + 1] = Has(r[2]) and ("%s (%s)"):format(r[1], r[2]) or r[1]
        end
    end
    if #parts == 0 then return nil end
    return (ns.L.G_DROPS_FROM or "Drops from: %s"):format(table.concat(parts, "; "))
end

-- Leatherworking specialisation: "Dragonscale Leatherworking (trainer: Peter Galen, Azshara, ...)".
local function SpecText(spec, trainer, mine)
    if not Has(trainer) then return spec end
    local where = WhereText(Data.GuideRecord("npc", trainer), mine)
    local who = where and (trainer .. ", " .. where) or trainer
    return spec .. " " .. (ns.L.G_SPEC_TRAINER or "(trainer: %s)"):format(who)
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

-- A chain record, else a note record of that key.
local function AddChainOrNote(out, key, ctx)
    if Data.GuideRecord("chain", key) then AddRecord(out, "chain", key, ctx)
    else AddRecord(out, "note", key, ctx) end
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
    local level, minLevel, qtype, bring, mats, drops = nil, nil, nil, {}, {}, {}
    for _, r in ipairs(own) do
        local k, a = r.key, r[1]
        if Has(a) then
            if k == "level" then level = a
            elseif k == "min" then minLevel = a
            elseif k == "type" then qtype = a
            elseif k == "bring" then bring[#bring + 1] = { a, DropText(a) }
            elseif k == "gold" then bring[#bring + 1] = { L.G_GOLD:format(a) }
            elseif k == "mat" then
                if a == "?" then
                    if Has(r[2]) then mats[#mats + 1] = (L.G_AMOUNT_UNKNOWN or "%s (amount not known)"):format(r[2]) end
                else
                    mats[#mats + 1] = Has(r[2]) and (a .. " " .. r[2]) or a
                end
            end
        end
        -- Recipe drops ("from|d|who|place", repeatable): one row, joined.
        if k == "from" and a == "d" and Has(r[2]) then
            drops[#drops + 1] = Has(r[3]) and ("%s (%s)"):format(r[2], r[3]) or r[2]
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
                for _, t in ipairs(bring) do
                    local bl = Add(out, "bullet", t[1])
                    bl.col = true          -- in the value column
                    bl.sub = t[2]          -- "Drops from: ..." under it (drop table), or nil
                end
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
        elseif k == "spec" then Add(out, "row", SpecText(a, b, mine), L.G_NEEDS)
        elseif k == "l" then Add(out, "row", Has(b) and b or "", a)
        end
        -- zone/where/xy/title/kind/size/need/att are read by the callers; unknown keys skipped.
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
            AddFold(out, a, function(sub) AddChainOrNote(sub, b, ctx) end)
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
            elseif a == "t" and Has(b) then Add(out, "row", NpcText(b, mine), L.G_TAUGHT_BY or "Taught by")
            elseif a == "t" then Add(out, "text", L.G_TRAINER)
            elseif a == "d" and #drops > 0 and not done.drop then
                done.drop = true
                Add(out, "row", table.concat(drops, ", "), L.G_DROP)
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

-- SourcesData entries of an item: { kind, a, b, c, fac, checked, later } (checked / later
-- from ns.SourceFlags, same position as the source in the string).
local function SourceEntries(itemID)
    local out = {}
    local tbl = ns.SourcesData
    local raw = type(tbl) == "table" and tbl[itemID]
    if type(raw) ~= "string" then return out end
    local flags = Data.SourceFlags(itemID)
    local i = 0
    for entry in raw:gmatch("[^;]+") do
        i = i + 1
        local f, fac = SplitTagged(entry)
        if SOURCE_TYPES[f[1]] or f[1] == "x" then
            local fl = flags[i] or ""
            out[#out + 1] = { kind = f[1], a = f[2], b = f[3], c = f[4], fac = fac,
                checked = fl:find("f", 1, true) ~= nil, later = fl:find("u", 1, true) ~= nil }
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
        if (r.key == "need" or r.key == "att") and Has(r[1]) then
            local id = r.key .. "|" .. r[1] .. "|" .. (r[2] or "") .. "|" .. (r.fac or "")
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
        -- No drop chance known: no row at all (a "not known" row only adds noise).
        AddRows(out, Concat(Data.GuideRecord("boss", a), itemRows), ctx)
    elseif kind == "z" or kind == "w" then
        Add(out, "sub", Has(a) and (word .. ": " .. a) or word)
        if Has(a) then AddPlace(out, a, L.G_PLACE, ctx, state) end
        AddRows(out, itemRows, ctx)
    elseif kind == "v" then
        Add(out, "sub", Has(a) and (word .. ": " .. a) or word)
        local npcWhere = Has(a) and WhereText(Data.GuideRecord("npc", a), ctx.mine)
        Add(out, "row", npcWhere or (Has(b) and b) or L.G_NOT_KNOWN, L.G_WHERE)
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

-- WoW Forever flag line: { k = "flag", flag = "classic"/"checked"/"later"/"srcLater", text }.
local FLAG_KEYS = { classic = "FLAG_CLASSIC", checked = "FLAG_CHECKED", later = "FLAG_LATER", srcLater = "FLAG_SRC_LATER" }
local function FlagBlock(flag)
    return { k = "flag", flag = flag, text = Data.FlagText(FLAG_KEYS[flag]) }
end

-- A list of sources with their Forever flags: one line on top when all of them agree
-- (all checked / none checked), else a line under each source's heading. A source that
-- is not out yet always says so (unless the whole piece already does).
local function AddSources(out, list, itemID, ctx, state, pieceLater)
    local nChecked = 0
    for _, e in ipairs(list) do if e.checked then nChecked = nChecked + 1 end end
    local perSource = nChecked > 0 and nChecked < #list
    if #list > 0 and not perSource then
        out[#out + 1] = FlagBlock(nChecked > 0 and "checked" or "classic")
    end
    for _, e in ipairs(list) do
        local n0 = #out
        AddSource(out, e, itemID, ctx, state)
        local flag
        if e.later and not pieceLater then flag = "srcLater"
        elseif perSource then flag = e.checked and "checked" or "classic" end
        if flag then
            local at = (out[n0 + 1] and out[n0 + 1].k == "sub") and n0 + 2 or n0 + 1
            table.insert(out, math.min(at, #out + 1), FlagBlock(flag))
        end
    end
end

-- Blocks for the guide page of one piece (cached; see the format above).
function Data:GetGuide(piece)
    local L = ns.L
    local itemID = piece and piece.itemID
    if not itemID then return {} end
    local cacheKey = piece.later and (itemID .. "L") or itemID   -- same item, other set's flag
    local hit = guideCache[cacheKey]
    if hit then return hit end
    -- Only the page on screen is kept: a new piece drops the old blocks and parsed
    -- records (building one costs ~0.02 ms; keeping all could reach ~2 MB).
    wipe(guideCache)
    wipe(recordCache)

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
    if piece.later then out[#out + 1] = FlagBlock("later") end
    if #own == 0 then Add(out, "text", L.SRC_UNKNOWN) end
    AddSources(out, own, itemID, ctx, state, piece.later)
    if not state.itemDone then AddRows(out, Data.GuideRecord("item", itemID), ctx) end

    -- Before you go: keys and attunements of the places above, all the same way:
    -- the sentence ("att": as written; "need": "To get in you need the <item>."), then
    -- the chain open for your faction, the other faction's in a fold-out.
    if #state.needs > 0 then
        Add(out, "head", L.G_BEFORE)
        local said = {}
        local function Sentence(r)
            if r.key == "att" then return r[1] end
            return L.G_NEED_TEXT:format(r[1])
        end
        for _, r in ipairs(state.needs) do
            if IsMine(r, mine) then
                local s = Sentence(r)
                if not said[s] then said[s] = true; Add(out, "text", s) end
                AddChainOrNote(out, r[2], ctx)
            end
        end
        for _, r in ipairs(state.needs) do
            if not IsMine(r, mine) then
                AddFold(out, L.G_OTHER_VERSION:format(Data.FactionName(r.fac) or r.fac), function(sub)
                    local saved = ctx.mine
                    ctx.mine = r.fac
                    if not said[Sentence(r)] then Add(sub, "text", Sentence(r)) end
                    AddChainOrNote(sub, r[2], ctx)
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
            AddSources(sub, rest, itemID, ctx, s2, piece.later)
            ctx.mine = saved
        end)
    end

    if cacheable then guideCache[cacheKey] = out end
    return out
end

-- ---------------------------------------------------------------------------
-- Looking a piece up online: its name and a Warcraft Wiki search link.
local WIKI_SEARCH = "https://warcraft.wiki.gg/wiki/Special:Search?search="

local function UrlEncode(s)
    return (tostring(s):gsub("[^A-Za-z0-9%-_%.~]", function(ch)
        return ("%%%02X"):format(ch:byte())
    end))
end

-- Text to search for a piece online: its name (item ID until the name has loaded).
function Data:SearchText(piece)
    return ItemName(piece.itemID) or tostring(piece.itemID)
end

-- Warcraft Wiki search for the piece (the site the source data comes from).
function Data:WikiSearchURL(piece)
    return WIKI_SEARCH .. UrlEncode(self:SearchText(piece))
end

-- /gs check: verify the bundled table against the game's own item data.
function Data:CheckClassic()
    local L = ns.L
    local tbl = ClassicTable()
    if type(tbl) ~= "table" then
        ns.Print(L.CHECK_NO_LIST)
        return
    end
    -- pending starts at 1 (a guard for the loop itself): cached items answer at once,
    -- and "done" must not print before every item was looked at.
    local problems, setsN, itemsN, pending = 0, 0, 0, 1
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
    pending = pending - 1      -- the loop's guard
    if pending == 0 then Finish() else
        C_Timer.After(15, function()
            if not done and pending > 0 then Report(L.CHECK_SLOW:format(pending)) end
            Finish()
        end)
    end
end

-- ---------------------------------------------------------------------------
-- beta.2: tiers, hidden sets, fit facts, effort score (plans\v1.0.0\beta2-interface.md).

-- "T2" -> "Tier 2" (ns.L TIER_<tag>, else the tag itself).
function Data.TierName(tag)
    if type(tag) ~= "string" then return nil end
    return (ns.L and ns.L["TIER_" .. tag]) or tag
end

-- Hidden sets: ns.db.hidden["set:<id>"] = true. Unknown keys and values are left alone.
local function HiddenKey(set)
    if ns.Entries and ns.Entries.SetKey then return ns.Entries.SetKey(set) end
    return "set:" .. tostring(set.id)
end

local function HiddenTable()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.hidden) ~= "table" then db.hidden = {} end
    return db.hidden
end

function Data.IsHidden(set)
    local h = set and HiddenTable()
    return h ~= nil and h[HiddenKey(set)] == true
end

function Data.SetHidden(set, hidden)
    local h = set and HiddenTable()
    if not h then return end
    h[HiddenKey(set)] = hidden and true or nil
end

-- Number of hidden sets (only "set:" keys set to true).
function Data.HiddenCount()
    local h, n = HiddenTable(), 0
    for k, v in pairs(h or {}) do
        if v == true and type(k) == "string" and k:find("^set:") then n = n + 1 end
    end
    return n
end

-- Show every hidden set again (removes only the set flags).
function Data.ShowAllHidden()
    local h = HiddenTable()
    if not h then return end
    local keys = {}
    for k in pairs(h) do
        if type(k) == "string" and k:find("^set:") then keys[#keys + 1] = k end
    end
    for _, k in ipairs(keys) do h[k] = nil end
end

-- Can the player's class wear this set's armor? true / false, nil if unknown.
-- (Class-limited sets: the class mask; else the heaviest armor the class can wear.)
function Data.CanWear(set)
    if not set then return nil end
    local classID = UnitClass and select(3, UnitClass("player"))
    if not classID then return nil end
    if set.classMask and set.classMask ~= 0 then return band(set.classMask, Data.ClassBit(classID)) ~= 0 end
    local max = CLASS_MAX_ARMOR[classID]
    if not max or not set.armor or set.armor == 0 then return true end
    return set.armor <= max
end

-- Effort score: from our own data only (SourcesData + GuideData), for the pieces still
-- needed. Points: dungeon or zone-boss place 1, raid place 3 (+1 at 40 players), quest done
-- in a dungeon 1 / raid 3, special source (x note) 2, world drop 3, crafted 1, reputation 2
-- each, gold 100+ 1 / 500+ 2, quest chain steps / 3 (rounded up). Per piece the source with
-- the fewest points counts; places, quests, reps and chains count once per set.
local effortCache, factCache = {}, {}
local EFFORT_LEVELS = { 3, 7, 12 }       -- Low <= 3, Medium <= 7, High <= 12, else Very high

-- Facts of one GuideData record (own small parse, does not touch the guide caches):
-- { kind, size, gold, reps = { "Faction Standing" }, chain, steps }.
local function RecordFacts(tname, key, mine)
    if not Has(key) then return nil end
    local g = ns.GuideData
    local t = type(g) == "table" and g[tname]
    local raw = type(t) == "table" and t[key]
    if type(raw) ~= "string" then return nil end
    local ck = tname .. "\31" .. key .. "\31" .. (mine or "")
    local hit = factCache[ck]
    if hit ~= nil then return hit or nil end
    local f = { gold = 0, reps = {}, steps = 0 }
    for part in raw:gmatch("[^;]+") do
        local r, fac = SplitTagged(part)
        if not fac or not mine or fac == mine then
            local k, a, b = r[1], r[2], r[3]
            if k == "kind" and Has(a) then f.kind = a
            elseif k == "size" then f.size = tonumber(a)
            elseif k == "type" and Has(a) then f.qtype = a:lower()
            elseif k == "gold" then f.gold = f.gold + (tonumber(a) or 0)
            elseif k == "rep" and Has(a) then f.reps[#f.reps + 1] = Has(b) and (a .. " " .. b) or a
            elseif k == "chain" and Has(a) then f.chain = a
            elseif k == "s" then f.steps = f.steps + 1 end
        end
    end
    factCache[ck] = f
    return f
end

local function GoldPoints(g)
    if g >= 500 then return 2 elseif g >= 100 then return 1 end
    return 0
end

-- One source as a small plan: places { name = { raid, size } }, world, craft, gold, reps, chains,
-- quests { name = "dungeon"|"raid" } (quests done inside an instance), special { note = true }.
local function SourcePlan(e, itemID, mine)
    local p = { places = {}, gold = 0, reps = {}, chains = {}, quests = {}, special = {} }
    local function AddRec(rec)
        if not rec then return end
        p.gold = p.gold + rec.gold
        for _, r in ipairs(rec.reps) do p.reps[r] = true end
        if rec.chain then p.chains[rec.chain] = true end
    end
    local function AddPlaceFacts(name)
        if not Has(name) then return end
        local rec = RecordFacts("place", name, mine)
        local kind = rec and rec.kind
        if kind == "city" or kind == "bg" then return end
        -- zone: a named boss or rare out in the world, one place to go like a dungeon
        p.places[name] = { raid = kind == "raid", size = rec and rec.size }
        AddRec(rec)
    end
    local k = e.kind
    if k == "b" then AddPlaceFacts(e.b)
    elseif k == "z" then AddPlaceFacts(e.a)
    elseif k == "w" then p.world = true
    elseif k == "c" then p.craft = true
    elseif k == "v" then AddRec(RecordFacts("npc", e.a, mine))
    elseif k == "q" then
        local q = RecordFacts("quest", e.a, mine)
        AddRec(q)
        local qt = q and q.qtype
        if Has(e.a) and (qt == "dungeon" or qt == "raid") then p.quests[e.a] = qt end
    elseif k == "x" and Has(e.a) then p.special[e.a] = true end
    AddRec(RecordFacts("item", itemID, mine))
    return p
end

local function ChainSteps(key, mine)
    local rec = RecordFacts("chain", key, mine)
    return rec and rec.steps or 0
end

local function PlanPoints(p, mine)
    local pts = 0
    for _, pl in pairs(p.places) do
        pts = pts + (pl.raid and (3 + ((pl.size or 0) >= 40 and 1 or 0)) or 1)
    end
    for _, qt in pairs(p.quests) do pts = pts + (qt == "raid" and 3 or 1) end
    for _ in pairs(p.special) do pts = pts + 2 end
    if p.world then pts = pts + 3 end
    if p.craft then pts = pts + 1 end
    for _ in pairs(p.reps) do pts = pts + 2 end
    local steps = 0
    for c in pairs(p.chains) do steps = steps + ChainSteps(c, mine) end
    pts = pts + math.ceil(steps / 3) + GoldPoints(p.gold)
    return pts, steps
end

local function SortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- { level 0..4, word, points, reasons = { text }, need } for a set, cached until
-- Owned:Invalidate (Data:ClearEffort). level 0 = nothing left to get.
function Data:GetEffort(set)
    if not set or not set.pieces then return nil end
    local hit = effortCache[set.key]
    if hit then return hit end
    local L, mine = ns.L, Data.PlayerFaction()
    local total = { places = {}, gold = 0, reps = {}, chains = {}, quests = {}, special = {} }
    local need = 0
    for _, piece in ipairs(set.pieces) do
        if not (ns.Owned and ns.Owned:IsHave(piece)) then
            need = need + 1
            -- The easiest way among this piece's sources (other faction's and not-out-yet ones skipped).
            local best, bestPts
            for _, e in ipairs(SourceEntries(piece.itemID)) do
                if (not e.fac or not mine or e.fac == mine) and not e.later then
                    local p = SourcePlan(e, piece.itemID, mine)
                    local pts = PlanPoints(p, mine)
                    if not bestPts or pts < bestPts then best, bestPts = p, pts end
                end
            end
            if best then
                for name, pl in pairs(best.places) do total.places[name] = pl end
                total.world = total.world or best.world
                total.craft = total.craft or best.craft
                total.gold = total.gold + best.gold
                for r in pairs(best.reps) do total.reps[r] = true end
                for c in pairs(best.chains) do total.chains[c] = true end
                for q, qt in pairs(best.quests) do total.quests[q] = qt end
                for x in pairs(best.special) do total.special[x] = true end
            end
        end
    end
    local points, steps = PlanPoints(total, mine)
    local level = 0
    if need > 0 then
        level = 4
        for i, max in ipairs(EFFORT_LEVELS) do
            if points <= max then level = i; break end
        end
    end
    local reasons, dungeons = {}, {}
    for _, name in ipairs(SortedKeys(total.places)) do
        local pl = total.places[name]
        if pl.raid then
            reasons[#reasons + 1] = pl.size and L.EFFORT_RAID:format(name, pl.size)
                or (L.EFFORT_RAID_NOSIZE or "Raid: %s"):format(name)
        else
            dungeons[#dungeons + 1] = name
        end
    end
    if #dungeons > 0 then
        reasons[#reasons + 1] = L.EFFORT_PLACES:format(#dungeons, table.concat(dungeons, ", "))
    end
    local nq = #SortedKeys(total.quests)
    if nq > 0 then reasons[#reasons + 1] = (L.EFFORT_QUEST_RUNS or "Quests inside dungeons or raids: %d"):format(nq) end
    for _, x in ipairs(SortedKeys(total.special)) do
        reasons[#reasons + 1] = (L.EFFORT_SPECIAL or "Special: %s"):format(x)
    end
    for _, r in ipairs(SortedKeys(total.reps)) do reasons[#reasons + 1] = L.EFFORT_REP:format(r) end
    if total.gold > 0 then reasons[#reasons + 1] = L.EFFORT_GOLD:format(math.floor(total.gold + 0.5)) end
    if steps > 0 then reasons[#reasons + 1] = L.EFFORT_CHAIN:format(steps) end
    if total.craft then reasons[#reasons + 1] = L.EFFORT_CRAFT end
    if total.world then reasons[#reasons + 1] = L.EFFORT_WORLD end
    local out = { level = level, word = L["EFFORT_" .. level], points = points, reasons = reasons, need = need }
    effortCache[set.key] = out
    return out
end

function Data:ClearEffort()
    wipe(effortCache)
end

-- Sort key for "Least effort": lower first; complete sets last, sets not out yet before them.
function Data:EffortRank(set)
    local e = self:GetEffort(set)
    if not e or e.need == 0 then return 1e9 end
    if set.unreleased then return 1e8 + e.points end
    return e.points + e.need * 0.01
end

-- Fit facts: stats added up from the live item tooltips of one set's pieces (the shown set
-- only, never all sets). Never read in combat (secret values): returns nil, "combat" and
-- calls onReady once after combat. Items not loaded: nil, one ContinueOnItemLoad each, then
-- onReady(set, stats). No timers, no repeated retries.
local statsCache, statsWaiting = {}, {}
local combatWaiting, combatFrame = {}, nil

local statPatterns
local function StatPatterns()
    if not statPatterns then
        local equip = type(ITEM_SPELL_TRIGGER_ONEQUIP) == "string" and ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"
        local use = type(ITEM_SPELL_TRIGGER_ONUSE) == "string" and ITEM_SPELL_TRIGGER_ONUSE or "Use:"
        local armor = type(ARMOR_TEMPLATE) == "string" and ARMOR_TEMPLATE or "%s Armor"
        statPatterns = { equip = equip, use = use, armor = FormatToPattern(armor),
            armorName = type(ARMOR) == "string" and ARMOR or "Armor" }
    end
    return statPatterns
end

-- Pure parse (also used by the offline test): lines of several items -> stats table.
function Data.SumStats(linesList)
    local P = StatPatterns()
    local bonus = BonusPatterns()
    local sums, order, equip, equipOrder = {}, {}, {}, {}
    local function AddStat(name, n)
        if not sums[name] then sums[name] = 0; order[#order + 1] = name end
        sums[name] = sums[name] + n
    end
    for _, lines in ipairs(linesList) do
        for _, l in ipairs(lines) do
            local text = l.text
            if type(text) == "string" and not text:match(bonus.gray) and not text:match(bonus.active) then
                local n, name = text:match("^%+(%d+) (.+)$")
                if n then
                    AddStat(name, tonumber(n))
                elseif text:sub(1, #P.equip) == P.equip or text:sub(1, #P.use) == P.use then
                    if not equip[text] then equip[text] = 0; equipOrder[#equipOrder + 1] = text end
                    equip[text] = equip[text] + 1
                else
                    local a = text:match(P.armor)
                    a = a and tonumber((a:gsub(",", "")))
                    if a then AddStat(P.armorName, a) end
                end
            end
        end
    end
    local stats = {}
    for _, name in ipairs(order) do stats[#stats + 1] = { name = name, total = sums[name] } end
    table.sort(stats, function(x, y)
        if x.total ~= y.total then return x.total > y.total end
        return x.name < y.name
    end)
    local eq = {}
    for _, text in ipairs(equipOrder) do eq[#eq + 1] = { text = text, count = equip[text] } end
    return { stats = stats, equip = eq, pieces = #linesList }
end

local function ReadStats(set)
    local list = {}
    for _, piece in ipairs(set.pieces) do
        local lines = Data:GetItemTooltipLines(piece.itemID)
        if not lines then return nil end          -- not ready: not cached, read again next time
        list[#list + 1] = lines
    end
    local out = Data.SumStats(list)
    statsCache[set.key] = out
    return out
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function WaitForCombatEnd(set, onReady)
    if not onReady then return end
    combatWaiting[set.key] = { set, onReady }
    if not combatFrame then
        combatFrame = CreateFrame("Frame")
        combatFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local list = combatWaiting
            combatWaiting = {}
            for _, w in pairs(list) do
                local stats = Data:GetSetStats(w[1], w[2])
                if stats then w[2](w[1], stats) end
            end
        end)
    end
    ns.SafeRegister(combatFrame, "PLAYER_REGEN_ENABLED")
end

function Data:GetSetStats(set, onReady)
    if not set or not set.pieces then return nil end
    local hit = statsCache[set.key]
    if hit then return hit end
    if InCombat() then
        WaitForCombatEnd(set, onReady)
        return nil, "combat"
    end
    if statsWaiting[set.key] then return nil end
    local missing = {}
    if Item and Item.CreateFromItemID then
        for _, piece in ipairs(set.pieces) do
            if not ItemName(piece.itemID) then missing[#missing + 1] = piece.itemID end
        end
    end
    if #missing == 0 then return ReadStats(set) end
    -- The one retry: when every missing item has loaded.
    statsWaiting[set.key] = true
    local left, sync, result = #missing, true, nil
    for _, itemID in ipairs(missing) do
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            left = left - 1
            if left > 0 then return end
            statsWaiting[set.key] = nil
            if InCombat() then
                if not sync then WaitForCombatEnd(set, onReady) end
                return
            end
            result = ReadStats(set)
            if not sync and onReady and result then onReady(set, result) end
        end)
    end
    sync = false
    return result
end

function Data:ClearSetStats()
    wipe(statsCache)
end
