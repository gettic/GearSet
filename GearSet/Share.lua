-- Gear Set: chat share (beta.8, contract plans\v1.0.0\beta8-interface.md).
-- Puts the set name and the pieces' item links into the chat edit box; the player sends it.
-- Never calls SendChatMessage; links only as the game returns them; no addon tag; 255 characters max.
local _, ns = ...

local Share = {}
ns.Share = Share

local MAX_CHARS = 255

local function SetOf(setID)
    if type(setID) == "table" then return setID end
    local D = ns.Data
    local key
    if type(setID) == "number" then key = "c" .. setID
    elseif type(setID) == "string" then key = setID:match("^c%d+$") and setID or (tonumber(setID) and "c" .. setID) end
    if not (key and D and D.GetSet) then return nil end
    local ok, set = pcall(D.GetSet, D, key)
    return ok and type(set) == "table" and set or nil
end

local function LinkOf(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local ok, name, link = pcall(get, itemID)
    if ok and name and type(link) == "string" and link:find("|Hitem:", 1, true) then return link end
    local req = C_Item and C_Item.RequestLoadItemDataByID
    if req then pcall(req, itemID) end
    return nil
end

local function Pieces(set)
    local list = type(set.shown) == "table" and set.shown or set.pieces
    return type(list) == "table" and list or {}
end

-- Text for a set within `room` characters (default 255): name, then whole links while they fit.
-- -> text|nil, shown, total, notLoaded (pieces skipped because their link isn't loaded yet)
function Share.Text(setID, room)
    local set = SetOf(setID)
    if not set or type(set.name) ~= "string" or set.name == "" then return nil, 0, 0 end
    room = type(room) == "number" and room or MAX_CHARS
    local pieces = Pieces(set)
    local text = set.name
    if #text > room then return nil, 0, #pieces end
    local shown, notLoaded = 0, 0
    for _, p in ipairs(pieces) do
        local id = type(p) == "table" and p.itemID or p
        local link = type(id) == "number" and LinkOf(id)
        if not link then
            notLoaded = notLoaded + 1
        elseif #text + 1 + #link <= room then
            text = text .. " " .. link
            shown = shown + 1
        end
    end
    return text, shown, #pieces, notLoaded
end

-- Chat box helpers: ChatFrameUtil (current client) first, older global names as fallback.
local function ActiveBox()
    local U = ChatFrameUtil
    local get = (U and U.GetActiveWindow) or ChatEdit_GetActiveWindow
    if not get then return nil end
    local ok, box = pcall(get)
    return ok and box or nil
end

local function InsertFn()
    local U = ChatFrameUtil
    return (U and U.InsertLink) or ChatEdit_InsertLink
end

local function OpenFn()
    local U = ChatFrameUtil
    return (U and U.OpenChat) or ChatFrame_OpenChat
end

-- -> ok, shown, total, why ("full" = no link fits in the chat box, "loading" = no link loaded yet)
function Share:SetToChat(setID)
    local box = ActiveBox()
    local room = MAX_CHARS
    if box and box.GetText then
        local ok, cur = pcall(box.GetText, box)
        if ok and type(cur) == "string" then room = MAX_CHARS - #cur - (cur ~= "" and 1 or 0) end
    end
    if room <= 0 then
        local t = select(3, Share.Text(setID)) or 0
        return false, 0, t, t > 0 and "full" or nil
    end
    local text, shown, total, notLoaded = Share.Text(setID, room)
    if not text then return false, 0, total or 0, total and total > 0 and "full" or nil end
    -- a set with pieces but no link in the text: insert nothing
    if total > 0 and shown == 0 then return false, 0, total, notLoaded == total and "loading" or "full" end
    if box then
        local insert = InsertFn()
        if insert then
            local cur = box.GetText and select(2, pcall(box.GetText, box))
            if type(cur) == "string" and cur ~= "" and not cur:find("%s$") then text = " " .. text end
            local ok, res = pcall(insert, text)
            if ok and res ~= false then return true, shown, total end
        end
    end
    local open = OpenFn()
    if not open then return false, shown, total end
    local ok = pcall(open, text)
    return ok and true or false, shown, total
end
