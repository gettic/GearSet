-- Gear Set: things other addons and the rest of the game UI can use.
--  * GearSet_IsSetPiece(item) -> true, setID | false     (item = itemID, "12345" or an item link)
--  * GearSet_ShowItem(item)   -> true when the guide opens (or opens after combat), else false
--  * Alt-click on any item (bags, chat links, loot, character slots...) opens its guide.
--    Post-hooks only (hooksecurefunc on HandleModifiedItemClick / SetItemRef), nothing replaced.
--  * LibDataBroker launcher "Gear Set", only when another addon already loaded LibDataBroker-1.1.
-- Info and opening our own window only; never in combat (queued until combat ends).
local _, ns = ...
local Theme, L = ns.Theme, ns.L
local Tip = ns.Tooltip

local Int = {}
ns.Integrations = Int

-- First set of an item that this client can show (sorted set IDs, so always the same one).
local function SetForItem(itemID)
    local ids = Tip.SetIDsOf(itemID)
    for _, setID in ipairs(ids) do
        local set = ns.Data and ns.Data:GetSet("c" .. setID)
        if set then return set, setID end
    end
    return nil, ids[1]
end

function Int.IsSetPiece(item)
    local id = Tip.ItemIDOf(item)
    if not id then return false end
    local v = Tip.Lookup(id)
    if v == nil then return false end
    return true, type(v) == "number" and v or v[1]
end

local queued   -- itemID waiting for combat to end
local waitFrame

local function OpenNow(itemID)
    local set = SetForItem(itemID)
    if not (set and ns.UI and ns.db) then return false end
    local UI = ns.UI
    UI:Build()
    if not UI:IsShown() then
        ns.db.lastSet = set.key   -- the window opens on this set
        UI:Toggle()
    end
    UI:SelectSet(set.key)
    for _, p in ipairs(set.shown or set.pieces) do
        if p.itemID == itemID then
            if ns.PieceList and ns.PieceList.ShowGuide then ns.PieceList:ShowGuide(p) end
            break
        end
    end
    return true
end

function Int.ShowItem(item)
    local id = Tip.ItemIDOf(item)
    if not (id and Tip.Lookup(id) ~= nil) then return false end
    if not SetForItem(id) then return false end
    if InCombatLockdown and InCombatLockdown() then
        if not queued then ns.Print(L.SHOWITEM_COMBAT) end
        queued = id
        if not waitFrame then
            waitFrame = CreateFrame("Frame")
            waitFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                local q = queued
                queued = nil
                if q then OpenNow(q) end
            end)
        end
        ns.SafeRegister(waitFrame, "PLAYER_REGEN_ENABLED")
        return true
    end
    return OpenNow(id)
end

-- Globals for other addons (bag addons, loot browsers).
function GearSet_IsSetPiece(item)
    local ok, isPiece, setID = pcall(Int.IsSetPiece, item)
    if ok and isPiece then return true, setID end
    return false
end

function GearSet_ShowItem(item)
    local ok, shown = pcall(Int.ShowItem, item)
    return ok and shown == true
end

-- ---------------------------------------------------------------------------
-- Alt-click (Alt alone, no Shift/Ctrl: those are chat link / dressing room).
function Int.ClickWanted()
    local db = ns.db
    if type(db) == "table" and db.altClick == false then return false end
    return IsAltKeyDown and IsAltKeyDown() and not (IsShiftKeyDown and IsShiftKeyDown())
        and not (IsControlKeyDown and IsControlKeyDown())
end

local lastID, lastTime
local function OnItemClick(link)
    if not Int.ClickWanted() then return end
    local id = Tip.ItemIDOf(link)
    if not id or Tip.Lookup(id) == nil then return end
    local now = GetTime and GetTime() or 0
    if id == lastID and now == lastTime then return end   -- SetItemRef also calls HandleModifiedItemClick
    lastID, lastTime = id, now
    Int.ShowItem(id)
end
Int.OnItemClick = OnItemClick

local function SafeClick(link)
    local ok, err = pcall(OnItemClick, link)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

if type(HandleModifiedItemClick) == "function" then
    hooksecurefunc("HandleModifiedItemClick", function(link) SafeClick(link) end)
end
if type(SetItemRef) == "function" then
    hooksecurefunc("SetItemRef", function(link)
        if type(link) == "string" and not Tip.Secret(link) and link:find("^item:") then SafeClick(link) end
    end)
end

-- ---------------------------------------------------------------------------
-- LibDataBroker launcher (Titan Panel, ChocolateBar, Bazooka ...). Nothing bundled: only when
-- another addon has already loaded LibStub + LibDataBroker-1.1.
function Int.InitBroker()
    if Int.broker then return Int.broker end
    local LS = _G.LibStub
    if LS == nil then return nil end
    local ok, ldb = pcall(LS, "LibDataBroker-1.1", true)
    if not ok or type(ldb) ~= "table" or type(ldb.NewDataObject) ~= "function" then return nil end
    -- The file the minimap button loaded (checked on a scratch texture when the button is hidden),
    -- so the bar never shows a blank icon when the first choice is missing on this client.
    local MB = ns.MinimapButton
    local icon = MB and MB.IconFile and MB.IconFile()
    if type(icon) ~= "string" then
        local list = Theme.art.minimapIcon
        icon = list and list[#list] or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    local okNew, obj = pcall(ldb.NewDataObject, ldb, "Gear Set", {
        type = "launcher",
        label = L.TITLE or "Gear Set",
        text = L.TITLE or "Gear Set",
        icon = icon,
        OnClick = function(_, button)
            if button == "RightButton" and ns.Settings and ns.Settings:Open() then return end
            if ns.UI then ns.UI:Toggle() end
        end,
        OnTooltipShow = function(tt)
            if not (tt and tt.AddLine) then return end
            tt:AddLine(L.TITLE or "Gear Set", Theme.colors.title:GetRGB())
            if ns.Progress and ns.Progress.AddTooltipLine then pcall(ns.Progress.AddTooltipLine, ns.Progress, tt) end
            if ns.Progress and ns.Progress.AddNextLine then pcall(ns.Progress.AddNextLine, ns.Progress, tt) end
            Theme.AddHint(tt, L.BROKER_TIP_CLICK)
            Theme.AddHint(tt, L.BROKER_TIP_RIGHT)
        end,
    })
    if okNew and obj then Int.broker = obj end
    return Int.broker
end

local f = CreateFrame("Frame")
ns.SafeRegister(f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    pcall(Int.InitBroker)
end)
