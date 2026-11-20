-- Gear Set: a quiet star on Blizzard's group loot roll window when you (or one of your own other
-- characters) need the item for a set (1.1 beta.1, plans\v1.1.0\plan.md sec. 3).
-- ToS (plans\v1.1.0\tos-check.md) W1: ONLY shows a star. Never calls RollOnLoot,
-- ConfirmLootRoll or any GroupLootFrame_* function, never clicks / shows / hides the roll
-- buttons, never replaces, moves or re-parents the roll frame or changes its scripts: only
-- HookScript (post-hook) and our own overlay frame, parented to UIParent. No sound, no flash.
-- W2: our overlay is anchored to the (unprotected) roll frame's icon only; the item link is
-- checked with issecretvalue; a missing GroupLootFrame<i> just means no star.
-- W8: alt names are only the user's own saved characters.
local _, ns = ...
local Theme = ns.Theme

local LootMark = {}
ns.LootMark = LootMark

local MAX_FRAMES = 4                 -- GroupLootFrame1..4 (Forever 1.60.1 Mainline GroupLootFrame.lua)
local hooked = {}
local marks = {}                     -- [roll frame] = our overlay

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function L(key, fallback)
    local v = ns.L and ns.L[key]
    if v == nil then return fallback end
    return v
end

function LootMark.Enabled()
    local db = ns.db
    return not (type(db) == "table" and db.lootMark == false)
end

-- Item ID of a roll, nil when unreadable (missing API, secret value, no link).
function LootMark.ItemOfRoll(rollID)
    local GetLootRollItemLink = _G.GetLootRollItemLink
    if rollID == nil or Secret(rollID) or type(GetLootRollItemLink) ~= "function" then return nil end
    local ok, link = pcall(GetLootRollItemLink, rollID)
    if not ok or link == nil or Secret(link) or type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- -> show (bool), tooltip text. Only set pieces (one table lookup first).
function LootMark.Decide(itemID)
    if not itemID then return false end
    local Tip = ns.Tooltip
    if Tip and Tip.Lookup and Tip.Lookup(itemID) == nil then return false end
    local R = ns.Runs
    if not (R and R.WhoNeeds) then return false end
    local ok, me, alts = pcall(R.WhoNeeds, itemID)
    if not ok then return false end
    if me then return true, L("LOOT_NEED", "Gear Set: you need this") end
    if type(alts) == "table" and #alts > 0 then
        return true, L("LOOT_ALTS", "Gear Set: needed by %s"):format(table.concat(alts, ", "))
    end
    return false
end

local function Mark(frame)
    local m = marks[frame]
    if m then return m end
    m = CreateFrame("Frame", nil, UIParent)
    local art = Theme.art.lootStar or Theme.art.star or {}
    local size = art.size or 18
    m:SetSize(size, size)
    m.tex = m:CreateTexture(nil, "OVERLAY")
    m.tex:SetAllPoints()
    if not Theme.SetArt(m.tex, art) and not art.file then m.tex:SetColorTexture(1, 0.82, 0, 1) end
    -- No mouse: the star never takes clicks meant for the roll window (the item's own tooltip
    -- already carries the Gear Set line). gsText is kept for tests and the selftest.
    m:EnableMouse(false)
    m:Hide()
    marks[frame] = m
    return m
end

local function Clear(frame)
    local m = marks[frame]
    if m then m:Hide(); m.gsText = nil end
end
LootMark.Clear = Clear

-- Our star on a roll frame, nil when none was made (tests, selftest).
function LootMark.MarkOf(frame) return marks[frame] end

-- A roll frame was shown (or a roll started): star on it when the item is needed.
function LootMark.Refresh(frame)
    if not frame then return end
    Clear(frame)
    if not LootMark.Enabled() then return end
    local okS, shown = pcall(frame.IsShown, frame)
    if not okS or not shown then return end
    local itemID = LootMark.ItemOfRoll(frame.rollID)
    local show, text = LootMark.Decide(itemID)
    if not show then return end
    local m = Mark(frame)
    local anchor = frame.IconFrame or frame
    m:ClearAllPoints()
    m:SetPoint("CENTER", anchor, "TOPLEFT", 2, -2)
    local okL, strata = pcall(frame.GetFrameStrata, frame)
    if okL and strata then m:SetFrameStrata(strata) end
    local okV, lv = pcall(frame.GetFrameLevel, frame)
    if okV and type(lv) == "number" then m:SetFrameLevel(lv + 10) end
    m.gsText = text
    m:Show()
    return true
end

local function OnShow(frame) LootMark.Refresh(frame) end
local function OnHide(frame) Clear(frame) end

-- Post-hooks on the roll frames that exist (once each).
function LootMark.Hook()
    local n = 0
    for i = 1, MAX_FRAMES do
        local f = _G["GroupLootFrame" .. i]
        if type(f) == "table" and not hooked[f] and type(f.HookScript) == "function" then
            if pcall(f.HookScript, f, "OnShow", OnShow) and pcall(f.HookScript, f, "OnHide", OnHide) then
                hooked[f] = true
            end
        end
        if hooked[f] then n = n + 1 end
    end
    return n
end

function LootMark.HookedCount()
    local n = 0
    for _ in pairs(hooked) do n = n + 1 end
    return n
end

-- START_LOOT_ROLL: Blizzard fills the frame in the same event; look next frame.
local function OnRoll()
    LootMark.Hook()
    C_Timer.After(0, function()
        for i = 1, MAX_FRAMES do
            local f = _G["GroupLootFrame" .. i]
            if type(f) == "table" then LootMark.Refresh(f) end
        end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then LootMark.Hook()
    elseif event == "START_LOOT_ROLL" then OnRoll() end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "START_LOOT_ROLL" }) do
    if ns.SafeRegister then ns.SafeRegister(events, e) else pcall(events.RegisterEvent, events, e) end
end
LootMark.events = events
