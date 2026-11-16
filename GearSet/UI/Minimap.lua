-- Gear Set: minimap button + Addon Compartment entry (own code, no libraries).
-- The button is named so minimap-button collectors (e.g. the "Mini Map" addon) pick it
-- up; while another addon holds it (parent is not Minimap) we never move it ourselves.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local MB = {}
ns.MinimapButton = MB

local BUTTON_NAME = "GearSetMinimapButton"
local EDGE = 5   -- how far past the map's edge the button's centre sits

-- Which quadrants are round for each GetMinimapShape() value; the rest are square.
-- Quadrant names: TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT.
local function QuadrantIsRound(shape, quad)
    if shape == nil or shape == "ROUND" then return true end
    if shape == "SQUARE" then return false end
    local kind, where = shape:match("^(%u+)%-(%u+)$")
    if kind == "CORNER" then return quad == where end           -- only that corner round
    if kind == "SIDE" then return quad:find(where, 1, true) ~= nil end -- that side's corners round
    if kind == "TRICORNER" then return quad ~= where end        -- all but that corner round
    return true
end

-- Offset of the button's centre from the map's centre for an angle in degrees
-- (0 = right, 90 = top). Round quadrants follow the circle, square ones the box edge.
function MB.EdgeOffset(angle, shape, radius)
    local rad = math.rad(angle or 0)
    local c, s = math.cos(rad), math.sin(rad)
    local quad = (s >= 0 and "TOP" or "BOTTOM") .. (c < 0 and "LEFT" or "RIGHT")
    if QuadrantIsRound(shape, quad) then
        return c * radius, s * radius
    end
    local m = math.max(math.abs(c), math.abs(s))
    return c / m * radius, s / m * radius
end

-- Angle in degrees (0-360) from the map's centre to a point.
function MB.AngleTo(cx, cy, px, py)
    local a = math.deg(math.atan2(py - cy, px - cx))
    return a % 360
end

local function Shape()
    if type(GetMinimapShape) == "function" then
        local ok, s = pcall(GetMinimapShape)
        if ok and type(s) == "string" then return s end
    end
    return "ROUND"
end

local function Held(btn)
    return btn:GetParent() ~= Minimap   -- a collector addon took it over
end

function MB:UpdatePosition()
    local btn = self.button
    if not btn or Held(btn) then return end
    local radius = Minimap:GetWidth() / 2 + EDGE
    local x, y = MB.EdgeOffset(ns.db.minimap.angle, Shape(), radius)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Tooltip, shared by the button and the compartment entry.
local function ShowTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    GameTooltip:SetText(L.TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_TIP_CLICK, nil, nil, nil, true)
    if owner == MB.button then
        GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, nil, nil, nil, true)
    end
    GameTooltip:Show()
end

local function DragUpdate(btn)
    local cx, cy = Minimap:GetCenter()
    if not cx then return end
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    ns.db.minimap.angle = MB.AngleTo(cx, cy, px / scale, py / scale)
    MB:UpdatePosition()
end

-- First icon the client can load (SetTexture returns false for a missing file;
-- clients that return nothing are taken as success).
local function SetIcon(tex)
    for _, file in ipairs(Theme.art.minimapIcon) do
        if tex:SetTexture(file) ~= false then return end
    end
end

function MB:Build()
    if self.button or not Minimap then return end
    local art = Theme.art.minimapButton
    local btn = CreateFrame("Button", BUTTON_NAME, Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture(art.highlight)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(art.background)
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    SetIcon(icon)
    btn.icon = icon   -- collectors look for .icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture(art.border)
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function() ns.UI:Toggle() end)
    btn:SetScript("OnEnter", function(self) ShowTooltip(self) end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnDragStart", function(self)
        if Held(self) then return end
        GameTooltip:Hide()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    self.button = btn
    self:UpdatePosition()
end

function MB:Refresh()
    if ns.db.minimap.hide then
        if self.button then self.button:Hide() end
    else
        self:Build()
        if self.button then
            self.button:Show()
            self:UpdatePosition()
        end
    end
end

function MB:Init()
    self:Refresh()
end

-- /gs minimap: show or hide the button; returns true when it is now shown.
function MB:ToggleShown()
    ns.db.minimap.hide = not ns.db.minimap.hide
    self:Refresh()
    return not ns.db.minimap.hide
end

-- Addon Compartment (named in the .toc). Globals because the .toc refers to them.
function GearSet_OnAddonCompartmentClick()
    ns.UI:Toggle()
end

function GearSet_OnAddonCompartmentEnter(_, menuButton)
    if menuButton then ShowTooltip(menuButton, "ANCHOR_LEFT") end
end

function GearSet_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
