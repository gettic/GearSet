-- Gear Set: learn vendor prices of set pieces (beta.8, contract plans\v1.0.0\beta8-interface.md).
-- When the player has a merchant window open, reads the price of the set pieces it sells and saves them
-- account-wide in GearSetDB.prices[itemID] = { c = copper per item, x = "other cost" text or nil, t = epoch }.
-- Read-only: never buys or moves items; nothing runs in combat (waits for PLAYER_REGEN_ENABLED).
local _, ns = ...

local Prices = {}
ns.Prices = Prices

local MAX_COSTS = 3          -- extra cost parts kept per item (honor, marks, tokens)
local MAX_X = 80             -- letters kept of the extra cost text
local open, pending, waitingCombat = false, false, false
local frame

local function Num(v) return type(v) == "number" and v == v and v or nil end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

-- The saved table; nil when GearSetDB isn't there or the key holds something else (never overwritten).
function Prices.Table(create)
    local db = type(GearSetDB) == "table" and GearSetDB or nil
    if not db then return nil end
    if db.prices == nil and create then db.prices = {} end
    return type(db.prices) == "table" and db.prices or nil
end

-- Learned price of one item -> copper|nil, extra text|nil, time|nil
function Prices.Get(itemID)
    local t = Prices.Table(false)
    local e = t and Num(itemID) and t[itemID]
    if type(e) ~= "table" then return nil end
    local c = Num(e.c)
    if c and c <= 0 then c = nil end
    local x = type(e.x) == "string" and e.x ~= "" and e.x or nil
    return c, x, Num(e.t)
end

local function IsSetPiece(id)
    local A = ns.Alts
    if A and A.SetItems then
        local ok, items = pcall(A.SetItems)
        if ok and type(items) == "table" then return items[id] == true end
    end
    return false
end

local function ItemIDAt(i)
    if GetMerchantItemID then
        local ok, id = pcall(GetMerchantItemID, i)
        if ok and Num(id) then return id end
    end
    if GetMerchantItemLink then
        local ok, link = pcall(GetMerchantItemLink, i)
        if ok and type(link) == "string" then return tonumber(link:match("item:(%d+)")) end
    end
end

-- price (copper for one stack), stack, hasExtendedCost
local function InfoAt(i)
    local C = C_MerchantFrame
    if C and C.GetItemInfo then
        local ok, info = pcall(C.GetItemInfo, i)
        if ok and type(info) == "table" then
            return Num(info.price) or 0, Num(info.stackCount) or 1, info.hasExtendedCost and true or false
        end
    end
    if GetMerchantItemInfo then
        local ok, _, _, price, stack, _, _, _, ext = pcall(GetMerchantItemInfo, i)
        if ok then return Num(price) or 0, Num(stack) or 1, ext and true or false end
    end
end

local function Strip(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1"):gsub("|T.-|t", "")
    return s ~= "" and s or nil
end

-- "2805 Honor Points, 1 Arathi Basin Mark of Honor" from GetMerchantItemCostItem.
local function ExtraText(i)
    if not (GetMerchantItemCostInfo and GetMerchantItemCostItem) then return nil end
    local ok, count = pcall(GetMerchantItemCostInfo, i)
    count = ok and Num(count) or 0
    local parts = {}
    for k = 1, math.min(count, MAX_COSTS) do
        local okc, _, value, link, currencyName = pcall(GetMerchantItemCostItem, i, k)
        if okc and Num(value) then
            local name = Strip(currencyName) or Strip(link)
            parts[#parts + 1] = name and (value .. " " .. name) or tostring(value)
        end
    end
    if #parts == 0 then return nil end
    local s = table.concat(parts, ", ")
    if #s > MAX_X then s = s:sub(1, MAX_X) end
    return s
end

-- Reads the open merchant once. Returns the number of set pieces saved.
function Prices.Scan()
    if InCombat() then return 0 end
    if not GetMerchantNumItems then return 0 end
    local ok, n = pcall(GetMerchantNumItems)
    n = ok and Num(n) or 0
    local saved = 0
    for i = 1, math.min(n, 500) do
        local id = ItemIDAt(i)
        if id and IsSetPiece(id) then
            local price, stack, ext = InfoAt(i)
            if price then
                local x = ext and ExtraText(i) or nil
                local c = price > 0 and math.floor(price / math.max(stack, 1) + 0.5) or 0
                if c > 0 or x then
                    local t = Prices.Table(true)
                    if not t then return saved end
                    t[id] = { c = c, x = x, t = time and time() or 0 }
                    saved = saved + 1
                end
            end
        end
    end
    if saved > 0 and ns.Gold and ns.Gold.Clear then ns.Gold.Clear() end
    return saved
end

local function RunScan()
    pending = false
    if not open then return end
    if InCombat() then
        if not waitingCombat then
            waitingCombat = true
            if ns.SafeRegister then ns.SafeRegister(frame, "PLAYER_REGEN_ENABLED") else pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED") end
        end
        return
    end
    Prices.Scan()
end

local function Schedule()
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(0.3, RunScan) else RunScan() end
end

local function OnEvent(_, event)
    if event == "MERCHANT_SHOW" then
        open = true
        Schedule()
    elseif event == "MERCHANT_UPDATE" then
        if open then Schedule() end
    elseif event == "MERCHANT_CLOSED" then
        open = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        waitingCombat = false
        pcall(frame.UnregisterEvent, frame, "PLAYER_REGEN_ENABLED")
        if open then Schedule() end
    end
end

function Prices.Init()
    if frame or not CreateFrame then return end
    frame = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }) do
        if ns.SafeRegister then ns.SafeRegister(frame, e) else pcall(frame.RegisterEvent, frame, e) end
    end
    frame:SetScript("OnEvent", OnEvent)
end

Prices.Init()
