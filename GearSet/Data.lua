-- Gear Set: set data layer. Turns every source into one shape:
--   set = { key, id, name, classMask, armor, source, pieces = { { itemID, slot, order, sourceID } } }
-- Sources (providers): "classic" = the bundled table in SetsData.lua.
-- The game's own transmog set list is added in a later step (plan step 8).
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

-- The bundled classic table (SetsData.lua). Accepts the few names it may use.
local function ClassicTable()
    return ns.ClassicSets or ns.SetsData or _G.GearSet_ClassicSets
end

function Data.ClassBit(classID)
    return lshift(1, classID - 1)
end

function Data.SetHasClass(set, classID)
    return set.classMask == 0 or band(set.classMask, Data.ClassBit(classID)) ~= 0
end

function Data.ArmorName(subclass)
    if not subclass or subclass == 0 then return nil end
    return GetItemSubClassInfo and GetItemSubClassInfo(ARMOR_CLASS, subclass) or nil
end

-- One piece from an itemID; nil if this client doesn't know the item.
local function MakePiece(itemID)
    local id, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstant(itemID)
    if not id then return nil end
    local slot = SLOT_BY_EQUIPLOC[equipLoc] or { 0, 99 }
    local sourceID
    if C_TransmogCollection and C_TransmogCollection.GetItemInfo then
        local ok, _, src = pcall(C_TransmogCollection.GetItemInfo, itemID)
        if ok then sourceID = src end
    end
    return {
        itemID = itemID, slot = slot[1], order = slot[2], sourceID = sourceID,
        equipLoc = equipLoc, classID = classID, subclassID = subclassID,
    }
end

-- Most common armor type (cloth..plate) among body pieces; cloaks don't count.
local function ArmorOf(pieces)
    local count, best, bestN = {}, 0, 0
    for _, p in ipairs(pieces) do
        if p.classID == ARMOR_CLASS and p.equipLoc ~= "INVTYPE_CLOAK"
            and p.subclassID and p.subclassID >= 1 and p.subclassID <= 4 then
            count[p.subclassID] = (count[p.subclassID] or 0) + 1
            if count[p.subclassID] > bestN then best, bestN = p.subclassID, count[p.subclassID] end
        end
    end
    return best
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
            for _, itemID in ipairs(entry.i) do
                local p = MakePiece(itemID)
                if p then pieces[#pieces + 1] = p end
            end
            if #pieces > 0 then  -- sets whose items this client lacks are skipped
                SortPieces(pieces)
                local name = GetItemSetInfo and GetItemSetInfo(setID)
                out[#out + 1] = {
                    key = "c" .. setID, id = setID, source = "classic",
                    name = (name and name ~= "") and name or ns.L.UNKNOWN_SET:format(setID),
                    classMask = tonumber(entry.c) or 0,
                    armor = ArmorOf(pieces),
                    pieces = pieces,
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
            for _, s in ipairs(self:GetSets()) do
                if s.classMask ~= 0 and band(s.classMask, Data.ClassBit(classID)) ~= 0 then
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
    for _, s in ipairs(self:GetSets()) do
        local ok = true
        if search ~= "" and not s.name:lower():find(search, 1, true) then ok = false end
        if ok and f.class ~= 0 and not Data.SetHasClass(s, f.class) then ok = false end
        if ok and f.armor ~= 0 and s.armor ~= f.armor then ok = false end
        if ok and f.usable and playerClass and not Data.SetHasClass(s, playerClass) then ok = false end
        if ok and f.hideComplete then
            local have, total = ns.Owned:SetCount(s)
            if have >= total then ok = false end
        end
        if ok then out[#out + 1] = s end
    end
    return out
end

-- /gs check: verify the bundled table against the game's own item data.
function Data:CheckClassic()
    local tbl = ClassicTable()
    if type(tbl) ~= "table" then
        ns.Print("No built-in set list found (SetsData.lua).")
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
        ns.Print(("Check done: %d sets, %d items, %d problems%s."):format(
            setsN, itemsN, problems, problems > 40 and " (first 40 shown)" or ""))
    end
    for setID, entry in pairs(tbl) do
        setsN = setsN + 1
        local name = GetItemSetInfo and GetItemSetInfo(setID)
        if not name or name == "" then Report(("Set %d: the game has no item set with this ID."):format(setID)) end
        if type(entry) ~= "table" or type(entry.i) ~= "table" then
            Report(("Set %d: bad entry."):format(setID))
        else
            for _, itemID in ipairs(entry.i) do
                itemsN = itemsN + 1
                if not GetItemInfoInstant(itemID) then
                    Report(("Set %d: item %d is unknown to this client."):format(setID, itemID))
                else
                    pending = pending + 1
                    local item = Item:CreateFromItemID(itemID)
                    item:ContinueOnItemLoad(function()
                        local itemSetID = select(16, C_Item.GetItemInfo(itemID))
                        if itemSetID ~= setID then
                            Report(("Set %d: item %d belongs to set %s."):format(setID, itemID, tostring(itemSetID)))
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
            if not done and pending > 0 then Report(("%d items did not load in time."):format(pending)) end
            Finish()
        end)
    end
end
