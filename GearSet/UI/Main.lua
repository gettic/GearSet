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
    b:SetFrameLevel(f:GetFrameLevel() + 10)
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
local function MakeHelpButton(f)
    local function OnClick()
        if ns.Help and ns.Help.Show then ns.Help:Show() end
    end
    local function OnEnter(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(T("HELP_BUTTON_TIP", "Show help"), Theme.colors.title:GetRGB())
        GameTooltip:Show()
    end
    local anchor = f.PortraitContainer or f.portrait or f
    local b, tmpl = Theme.CreateFrame("Button", nil, f, "helpButton")
    if b and tmpl then
        b:SetScale(0.6)
        b:ClearAllPoints()
        b:SetPoint("CENTER", anchor, "BOTTOMRIGHT", -2, 4)
        b:SetScript("OnClick", OnClick)
        b:SetScript("OnEnter", OnEnter)
        b:SetScript("OnLeave", GameTooltip_Hide)
    else
        if b then b:Hide() end
        b = ns.Widgets.LinkButton(f, "?", OnEnter, OnClick, "link")
        b:SetPoint("CENTER", anchor, "BOTTOMRIGHT", -6, 6)
    end
    b:SetFrameLevel(f:GetFrameLevel() + 10)
    return b
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
