-- Gear Set: auction prices from a price addon the user already has (1.1 beta.2).
-- ToS W6 (plans\v1.1.0\tos-check.md): read only. Every call is pcall'd and checked to exist
-- first; our own caller ID "GearSet" is passed to Auctionator; never triggers an Auctionator or
-- TSM scan, never calls C_AuctionHouse, nothing is cached or saved (decision 3).
-- Auctionator: Auctionator.API.v1.GetAuctionPriceByItemID and GetAuctionAgeByItemID (callerID,
-- itemID), both seen in game in the 1.1 beta.2 selftest (with a Thorium Bar price).
-- TSM: TSM_API.GetCustomPriceValue(priceString, itemString), tested with a fake only.
-- /gs probe lists the functions each addon really has.
local _, ns = ...

local AHPrices = {}
ns.AHPrices = AHPrices

local CALLER = "GearSet"

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
-- A usable number: not secret, not NaN, not +-inf (a broken addon value counts as no price).
local function Num(v)
    if type(v) ~= "number" or Secret(v) then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- Auctionator's API v1 table, or nil.
function AHPrices.AuctionatorAPI()
    local A = rawget(_G, "Auctionator")
    local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
    return type(api) == "table" and api or nil
end

function AHPrices.TSMAPI()
    local T = rawget(_G, "TSM_API")
    return type(T) == "table" and type(T.GetCustomPriceValue) == "function" and T or nil
end

local function Setting()
    local db = ns.db
    local s = type(db) == "table" and db.priceSource or "auto"
    if s ~= "auctionator" and s ~= "tsm" and s ~= "off" then s = "auto" end
    return s
end

-- The source in use: "auctionator" / "tsm" / nil.
function AHPrices.Source()
    local s = Setting()
    if s == "off" then return nil end
    local api = AHPrices.AuctionatorAPI()
    local hasA = api and type(api.GetAuctionPriceByItemID) == "function"
    if (s == "auto" or s == "auctionator") and hasA then return "auctionator" end
    if (s == "auto" or s == "tsm") and AHPrices.TSMAPI() then return "tsm" end
    return nil
end

local function FromAuctionator(itemID)
    local api = AHPrices.AuctionatorAPI()
    if not (api and type(api.GetAuctionPriceByItemID) == "function") then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
    price = ok and Num(price) or nil
    if not price or price <= 0 then return nil end
    local age
    if type(api.GetAuctionAgeByItemID) == "function" then
        local okA, a = pcall(api.GetAuctionAgeByItemID, CALLER, itemID)
        age = okA and Num(a) or nil
    end
    return price, age, "auctionator"
end

local function FromTSM(itemID)
    local T = AHPrices.TSMAPI()
    if not T then return nil end
    local ok, price = pcall(T.GetCustomPriceValue, "DBMarket", "i:" .. itemID)
    price = ok and Num(price) or nil
    if not price or price <= 0 then return nil end
    return price, nil, "tsm"   -- TSM's market value is an average: no age
end

-- Price of one item -> copper, ageDays (nil = unknown), source; nil when none.
function AHPrices.Get(itemID)
    if type(itemID) ~= "number" then return nil end
    local src = AHPrices.Source()
    if src == "auctionator" then
        local p, a, s = FromAuctionator(itemID)
        if p then return p, a, s end
        if Setting() == "auto" then return FromTSM(itemID) end
        return nil
    elseif src == "tsm" then
        return FromTSM(itemID)
    end
    return nil
end

-- "Auctionator" / "TSM market value".
function AHPrices.SourceName(src)
    local L = ns.L or {}
    if src == "auctionator" then return L.PRICE_AUCTIONATOR or "Auctionator" end
    if src == "tsm" then return L.PRICE_TSM or "TSM market value" end
    return nil
end

-- Several sources (Auto mode mixing both): short names joined, "Auctionator + TSM".
function AHPrices.SourcesName(list)
    if type(list) ~= "table" or #list == 0 then return "" end
    if #list == 1 then return AHPrices.SourceName(list[1]) or "" end
    local L = ns.L or {}
    local parts = {}
    for i, s in ipairs(list) do
        parts[i] = s == "tsm" and (L.PRICE_TSM_SHORT or "TSM") or AHPrices.SourceName(s) or tostring(s)
    end
    return table.concat(parts, " + ")
end

-- For /gs probe and the selftest: which API functions exist (names only).
function AHPrices.Describe()
    local api = AHPrices.AuctionatorAPI()
    local names = {}
    if api then
        for k, v in pairs(api) do if type(v) == "function" then names[#names + 1] = tostring(k) end end
        table.sort(names)
    end
    return api ~= nil, names, AHPrices.TSMAPI() ~= nil
end
