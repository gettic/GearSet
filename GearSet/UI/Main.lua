-- Gear Set: the main window (three panels: set list, preview, pieces).
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 940, 580
local TOP, BOTTOM = -60, 26        -- inset area inside ButtonFrameTemplate
local LEFT_W, MID_W, GAP = 280, 300, 4

local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then ns.db.point = { point, relPoint, x, y } end
end

function UI:ResetPosition()
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER")
end

local function RestorePosition(frame)
    local p = ns.db.point
    frame:ClearAllPoints()
    if type(p) == "table" and p[1] then
        frame:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
    else
        frame:SetPoint("CENTER")
    end
end

local function MakeInset(parent, x1, x2)
    local inset = Theme.CreateFrame("Frame", nil, parent, "inset")
    inset:SetPoint("TOPLEFT", parent, "TOPLEFT", x1, TOP)
    if x2 then
        inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", x2, BOTTOM)
    else
        inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, BOTTOM)
    end
    return inset
end

function UI:Build()
    if self.frame then return end
    local f = Theme.CreateFrame("Frame", "GearSetFrame", UIParent, "window")
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    f:Hide()

    if f.SetTitle then
        f:SetTitle(L.TITLE)
    elseif f.TitleText then
        f.TitleText:SetText(L.TITLE)
    end
    if f.SetPortraitToUnit then
        f:SetPortraitToUnit("player")
    end
    if f.Inset then f.Inset:Hide() end  -- we use our own three insets

    tinsert(UISpecialFrames, "GearSetFrame")  -- Esc closes it

    self.left = MakeInset(f, 4, 4 + LEFT_W)
    self.mid = MakeInset(f, 4 + LEFT_W + GAP, 4 + LEFT_W + GAP + MID_W)
    self.right = MakeInset(f, 4 + LEFT_W + GAP + MID_W + GAP, nil)

    ns.SetList:Build(self.left)
    ns.Preview:Build(self.mid)
    ns.PieceList:Build(self.right)

    f:SetScript("OnShow", function()
        if f.SetPortraitToUnit then f:SetPortraitToUnit("player") end
        ns.Owned:Invalidate()
        UI:RefreshAll()
    end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end)

    RestorePosition(f)
end

function UI:IsShown()
    return self.frame and self.frame:IsShown()
end

function UI:Toggle()
    self:Build()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        self.frame:Show()
    end
end

-- Pick a set (from the list) and show it in the preview and piece list.
function UI:SelectSet(key)
    ns.db.lastSet = key
    local set = ns.Data:GetSet(key)
    ns.SetList:Refresh()
    ns.Preview:ShowSet(set)
    ns.PieceList:ShowSet(set)
end

function UI:RefreshAll()
    ns.SetList:Refresh()
    local set = ns.Data:GetSet(ns.db.lastSet)
    ns.Preview:ShowSet(set)
    ns.PieceList:ShowSet(set)
end

-- Owned states changed (bags, bank, equipment, collection).
function UI:RefreshCounts()
    ns.SetList:Refresh()
    ns.PieceList:Refresh()
end
