-- Gear Set: the main window (three panels: set list, preview, pieces).
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 1060, 620   -- right panel 462 x 534 (guide page); FitToScreen shrinks it on small screens
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
    -- Checked again here (InitDB checks too): a bad saved point must never stop the window.
    if ns.ValidPoint(p) and pcall(frame.SetPoint, frame, p[1], UIParent, p[2] or p[1],
            tonumber(p[3]) or 0, tonumber(p[4]) or 0) then
        return
    end
    ns.db.point = nil
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
end

-- Shrink the window (never grow it) so it fits small or 4:3 screens at a large UI scale.
local FIT_MARGIN = 20
local function FitToScreen(frame)
    local w, h = frame:GetWidth(), frame:GetHeight()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not (w and h and sw and sh) or w <= 0 or h <= 0 then return end
    local scale = math.min(1, sw / (w + FIT_MARGIN), sh / (h + FIT_MARGIN))
    if scale > 0 and math.abs(frame:GetScale() - scale) > 0.001 then
        frame:SetScale(scale)
    end
end

local function T(key, fallback)
    local v = L[key]
    if v == nil then return fallback end
    return v
end

-- One level above the window template's own parts. Their levels are fixed in the template
-- (WoW Forever: border 500, portrait 400, title bar and X 510), so "window + 10" draws
-- under the border art. Also used by Help.lua for note 4's line.
local TEMPLATE_PARTS = { "NineSlice", "PortraitContainer", "TitleContainer", "CloseButton" }
function UI.TopLevelOf(f)
    local top = f:GetFrameLevel() or 0
    for _, key in ipairs(TEMPLATE_PARTS) do
        local part = f[key]
        if type(part) == "table" and part.GetFrameLevel then
            local lv = part:GetFrameLevel()
            if lv and lv > top then top = lv end
        end
    end
    return math.min(top + 1, 9000)
end

-- Gear and "?" on top of the template's art (Build, and again on every OnShow).
function UI:RaiseButtons()
    local f = self.frame
    if not f then return end
    local level = UI.TopLevelOf(f)
    if self.gear then self.gear:SetFrameLevel(level) end
    if self.helpButton then self.helpButton:SetFrameLevel(level) end
end

-- Gear button left of the close button: opens Gear Set's page in Blizzard's settings.
local function MakeGearButton(f)
    local art = Theme.art.settingsIcon
    local b = CreateFrame("Button", nil, f)
    b:SetSize(art.size or 20, art.size or 20)
    local close = f.CloseButton
    if close then
        b:SetPoint("RIGHT", close, "LEFT", -2, 0)
    else
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -4)
    end
    b:SetFrameLevel(UI.TopLevelOf(f))
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    Theme.SetArt(icon, art)
    b.icon = icon
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Theme.SetArt(hl, art)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.5)
    b:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", 1, -1) end)
    b:SetScript("OnMouseUp", function() icon:ClearAllPoints(); icon:SetAllPoints() end)
    b:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if not (ns.Settings and ns.Settings.Open and ns.Settings:Open()) then
            ns.Print(T("SETTINGS_MISSING", "Settings aren't available in this game version. Use /gs minimap and /gs reset."))
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(T("SETTINGS", "Settings"), Theme.colors.title:GetRGB())
        Theme.AddHint(GameTooltip, T("SETTINGS_TIP_HINT", "Also: /gs config"))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- "?" on the portrait: Blizzard's tutorial button (MainHelpPlateButton), else a "?" link.
-- Its own scripts are replaced on our child button only (no Blizzard function touched).
local function HelpOnClick()
    if ns.Help and ns.Help.Show then ns.Help:Show() end
end
local function HelpOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(T("HELP_BUTTON_TIP", "Show help"), Theme.colors.title:GetRGB())
    GameTooltip:Show()
end

-- Where the "?" goes: the bottom-right of the portrait picture when it has a size,
-- else a fixed spot on the window (the portrait's corner on the classic layout).
local PORTRAIT_SPOT_X, PORTRAIT_SPOT_Y = 52, -50
local function PortraitRegion(f)
    local pc = f.PortraitContainer
    local list = { pc and pc.portrait, f.portrait, pc }
    for i = 1, 3 do
        local r = list[i]
        if type(r) == "table" and r.GetWidth then
            local w, h = r:GetWidth(), r:GetHeight()
            if w and h and w > 1 and h > 1 then return r end
        end
    end
end

local function PlaceHelp(b, f, dx, dy, onWindow)
    b:ClearAllPoints()
    local region = not onWindow and PortraitRegion(f)
    if region then
        b:SetPoint("CENTER", region, "BOTTOMRIGHT", dx, dy)
    else
        local s = (b.GetScale and b:GetScale()) or 1   -- offsets count in the button's own scale
        if not s or s <= 0 then s = 1 end
        b:SetPoint("CENTER", f, "TOPLEFT", PORTRAIT_SPOT_X / s, PORTRAIT_SPOT_Y / s)
    end
end

local function MakeHelpLink(f, onWindow)
    local b = ns.Widgets.LinkButton(f, "?", HelpOnEnter, HelpOnClick, "link")
    PlaceHelp(b, f, -6, 6, onWindow)
    b:SetFrameLevel(UI.TopLevelOf(f))
    b:Show()
    return b
end

local function MakeHelpButton(f)
    local b, tmpl = Theme.CreateFrame("Button", nil, f, "helpButton")
    if b and tmpl then
        b:SetScale(0.6)
        PlaceHelp(b, f, -2, 4)
        b:SetScript("OnClick", HelpOnClick)
        b:SetScript("OnEnter", HelpOnEnter)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b.gsTemplate = true
        b:SetFrameLevel(UI.TopLevelOf(f))
        b:Show()   -- the template may start hidden on this client
        return b
    end
    if b then b:Hide() end
    return MakeHelpLink(f)
end

-- First show, one frame later: if the template "?" has no position or its "i" art is
-- missing on this client, swap it for the "?" text link on the window itself.
local function TextureMissing(tex)
    if not tex then return true end
    local id = tex.GetTextureFileID and tex:GetTextureFileID()
    if id == nil and tex.GetTexture then id = tex:GetTexture() end
    return id == nil or id == 0
end

function UI:CheckHelpButton()
    local b, f = self.helpButton, self.frame
    if self.helpChecked or not (b and f and b.gsTemplate and f:IsShown()) then return end
    self.helpChecked = true
    local noPlace = b:GetLeft() == nil
    if noPlace or TextureMissing(b.I) then
        b:Hide()
        self.helpButton = MakeHelpLink(f, noPlace)
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
    -- The template's X calls HideUIPanel, which Blizzard blocks for addons in combat:
    -- hide our own window directly (like Blizzard's floating frames' close buttons).
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

    tinsert(UISpecialFrames, "GearSetFrame")  -- Esc closes it

    self.left = MakeInset(f, 4, 4 + LEFT_W)
    self.mid = MakeInset(f, 4 + LEFT_W + GAP, 4 + LEFT_W + GAP + MID_W)
    self.right = MakeInset(f, 4 + LEFT_W + GAP + MID_W + GAP, nil)

    ns.SetList:Build(self.left)
    ns.Preview:Build(self.mid, f)  -- its Reset / "Only the set" go in the window's bottom bar
    ns.PieceList:Build(self.right)

    self.gear = MakeGearButton(f)
    self.helpButton = MakeHelpButton(f)

    f:SetScript("OnShow", function()
        FitToScreen(f)
        UI:RaiseButtons()
        if not UI.helpChecked and C_Timer and C_Timer.After then
            C_Timer.After(0, function() UI:CheckHelpButton() end)
        end
        if f.SetPortraitToUnit then f:SetPortraitToUnit("player") end
        ns.Owned:Invalidate()
        UI:RefreshAll()
        if ns.Help and ns.Help.MaybeShowFirstTime then ns.Help:MaybeShowFirstTime() end
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
