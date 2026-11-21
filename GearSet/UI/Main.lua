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

-- Middle of the screen, window + bottom tabs together (the tabs hang below the window).
local function Center(frame)
    local o = (Theme.sizes and Theme.sizes.tabOverhang) or 0
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, o / 2)
end

function UI:ResetPosition()
    if not self.frame then return end
    self.frame:ClearAllPoints()
    Center(self.frame)
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
    Center(frame)
end

-- Shrink the window (never grow it) so it fits small or 4:3 screens at a large UI scale.
-- The bottom tabs hang below the window (Theme.sizes.tabOverhang), so they count too.
local FIT_MARGIN = 20
local function TabOverhang() return (Theme.sizes and Theme.sizes.tabOverhang) or 30 end
local function FitToScreen(frame)
    local w, h = frame:GetWidth(), frame:GetHeight()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not (w and h and sw and sh) or w <= 0 or h <= 0 then return end
    h = h + TabOverhang()
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

-- Help button in the title bar, just left of the gear: our own button with Blizzard's
-- help-plate "i" art, else a "?" link.
local function HelpOnClick()
    if ns.Help and ns.Help.Show then ns.Help:Show() end
end
local function HelpOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")   -- like the gear's (the X is on its right)
    GameTooltip:SetText(T("HELP_BUTTON_TIP", "Show help"), Theme.colors.title:GetRGB())
    GameTooltip:Show()
end

-- Where it goes: right side on the gear's left side (HELP_GAP px apart, the gear's proven
-- title-bar spot), else (no gear, or the gear has no position) where the gear's own
-- fallback would put it, one button further left. Offsets in window pixels.
local HELP_GAP = 4
local HELP_FALLBACK_X, HELP_FALLBACK_Y = -54, -4
local function PlaceHelp(b, f, onWindow)
    b:ClearAllPoints()
    local s = (b.GetScale and b:GetScale()) or 1   -- offsets count in the button's own scale
    if not s or s <= 0 then s = 1 end
    local gear = UI.gear
    if gear and not onWindow then
        b:SetPoint("RIGHT", gear, "LEFT", -HELP_GAP / s, 0)
    else
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", HELP_FALLBACK_X / s, HELP_FALLBACK_Y / s)
    end
end

local function MakeHelpLink(f, onWindow)
    local b = ns.Widgets.LinkButton(f, "?", HelpOnEnter, HelpOnClick, "link")
    PlaceHelp(b, f, onWindow)
    b:SetFrameLevel(UI.TopLevelOf(f))
    b:Show()
    return b
end

-- Our own plain button with Blizzard's help-plate art (Theme.art.helpIcon, by path).
-- Not the MainHelpPlateButton template: on WoW Forever it hides itself.
-- `.I` / `.Ring` keep the template's names (the self-test reads them); `gsArt` marks it.
local function MakeHelpButton(f)
    local art = Theme.art.helpIcon
    if not art then return MakeHelpLink(f) end
    local b = CreateFrame("Button", nil, f)
    local size, iconSize = art.size or 64, art.iconSize or 46
    b:SetSize(size, size)
    -- Drawn in the art's own 64 px layout, scaled to `screen` px in the window.
    b:SetScale((art.screen or 22) / size)
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER")
    if not Theme.TryTexture(icon, art.icon) then
        b:Hide()
        return MakeHelpLink(f)   -- the plain button stays hidden and unused
    end
    b.I = icon
    local ring = b:CreateTexture(nil, "BORDER")
    ring:SetSize(size, size)
    ring:SetPoint("CENTER", art.ringX or 12, art.ringY or -13)
    Theme.TryTexture(ring, art.ring)
    b.Ring = ring
    if art.highlight then
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetSize(iconSize, iconSize)
        hl:SetPoint("CENTER", -1, 1)
        hl:SetTexture(art.highlight)
        hl:SetBlendMode("ADD")
    end
    b:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", HelpOnClick)
    b:SetScript("OnEnter", HelpOnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    PlaceHelp(b, f)
    b.gsArt = true
    b:SetFrameLevel(UI.TopLevelOf(f))
    b:Show()
    return b
end

local function TextureMissing(tex)
    if not tex then return true end
    local id = tex.GetTextureFileID and tex:GetTextureFileID()
    if id == nil and tex.GetTexture then id = tex:GetTexture() end
    return id == nil or id == 0
end

-- Every window open, one frame later: the art "?" hidden, without a position or without
-- its "i" -> swap it for the "?" text link (once); the link itself is kept shown.
function UI:CheckHelpButton()
    local b, f = self.helpButton, self.frame
    if not (b and f and f:IsShown()) then return end
    if b.gsArt then
        local noPlace = b:GetLeft() == nil
        if noPlace or not b:IsShown() or TextureMissing(b.I) then
            b:Hide()
            b.gsArt = nil
            self.helpButton = MakeHelpLink(f, noPlace)
        end
    elseif not b:IsShown() then
        b:Show()
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

-- ---------------------------------------------------------------------------
-- "Sets complete: 12 / 186" box in the strip under the title bar (ui-review-3; the
-- journals' count box, CollectionsCountTemplate pattern). Counts this character's sets
-- (Progress:Get("char")); click = Progress tab. Hidden without the Progress module.
local COUNT_BOX = { x = 70, y = -35, h = 20, pad = 20, gap = 4, minW = 130 }

local function CountSummary()
    local P = ns.Progress
    if not (P and P.Get) then return nil end
    local ok, s = pcall(P.Get, P, "char")
    if ok and type(s) == "table" then return s end
end

local function CountBoxTooltip(self)
    local s = CountSummary()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText(T("COUNT_BOX_TIP", "Sets complete on this character"), 1, 1, 1)
    if s then
        local sub = Theme.colors.subtle
        GameTooltip:AddLine(T("P_SUMMARY", "%d complete, %d started, %d / %d pieces"):format(
            s.complete or 0, s.started or 0, s.have or 0, s.total or 0), sub:GetRGB())
        GameTooltip:AddLine(T("P_PCT", "%d%% of set pieces"):format(s.pct or 0), sub:GetRGB())
    end
    Theme.AddHint(GameTooltip, T("COUNT_BOX_HINT", "Click: open the Progress tab."))
    GameTooltip:Show()
end

local function FontKey(fs, key, fallback)
    fs:SetFontObject(Theme.fonts[key] or fallback)
end

local function MakeCountBox(f)
    if not (ns.Progress and ns.Progress.Get) then return nil end
    local box = Theme.CreateFrame("Frame", nil, f, "countBox")
    if not box then return nil end
    local tmpl = Theme.Template("countBox")
    box:SetPoint("TOPLEFT", f, "TOPLEFT", COUNT_BOX.x, COUNT_BOX.y)
    box:SetSize(COUNT_BOX.minW, COUNT_BOX.h)
    if not tmpl then
        -- No inset template: a dark box with a thin edge.
        local c = Theme.colors.countBoxBg
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        if c and c.GetRGBA then bg:SetColorTexture(c:GetRGBA()) end
    end
    local label = box:CreateFontString(nil, "OVERLAY")
    FontKey(label, "countLabel", "GameFontNormalSmall")
    label:SetText(T("COUNT_BOX", "Sets complete:"))
    label:SetPoint("LEFT", box, "LEFT", COUNT_BOX.pad / 2, 0)
    local count = box:CreateFontString(nil, "OVERLAY")
    FontKey(count, "countValue", "GameFontHighlightSmall")
    count:SetPoint("LEFT", label, "RIGHT", COUNT_BOX.gap, 0)
    box.label, box.count = label, count
    -- Click/hover on a plain button over the box (the inset template is a Frame).
    local hit = CreateFrame("Button", nil, box)
    hit:SetAllPoints()
    hit:SetScript("OnEnter", CountBoxTooltip)
    hit:SetScript("OnLeave", GameTooltip_Hide)
    hit:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if UI.tabByKey.progress then UI:ShowTab("progress") end
    end)
    box.hit = hit
    box:Show()
    return box
end

-- Count text; the box is text + padding wide (at least minW), text centred.
function UI:UpdateCountBox()
    local box = self.countBox
    if not box then return end
    local s = CountSummary()
    if s then
        box.count:SetText(("%d / %d"):format(s.complete or 0, s.sets or 0))
    else
        box.count:SetText("?")
    end
    local textW = (box.label:GetStringWidth() or 0) + COUNT_BOX.gap + (box.count:GetStringWidth() or 0)
    local boxW = math.max(COUNT_BOX.minW, math.ceil(textW + COUNT_BOX.pad))
    box:SetWidth(boxW)
    box.label:ClearAllPoints()
    box.label:SetPoint("LEFT", box, "LEFT", math.floor((boxW - textW) / 2), 0)
end

-- Progress counts were dropped (bags, hide, track ...): redraw once on the next frame.
local countPending
local function CountChanged()
    if countPending or not (UI.frame and UI.frame:IsShown()) then return end
    countPending = true
    local function run()
        countPending = false
        UI:UpdateCountBox()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- ---------------------------------------------------------------------------
-- Bottom tabs (review-ui 2/3): Blizzard's PanelTabButtonTemplate on our own window only,
-- else plain panel buttons. Each tab shows its own frames; `onShow` runs after a switch.
UI.tabs, UI.tabByKey = {}, {}

local function PanelCall(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then pcall(fn, ...) end
end

local function MakeTab(f, i, label)
    local tab, tmpl = Theme.CreateFrame("Button", "GearSetFrameTab" .. i, f, "tab")
    if not tmpl then
        if tab then tab:Hide() end
        tab = Theme.CreateFrame("Button", nil, f, "button")
        tab:SetSize(100, 24)
    end
    tab.gsTemplate = tmpl ~= nil
    tab:SetID(i)
    tab:SetText(label)
    if tab.gsTemplate then
        PanelCall("PanelTemplates_TabResize", tab, 0)
    else
        local w = tab.GetTextWidth and tab:GetTextWidth()
        if w and w > 0 then tab:SetWidth(math.max(90, w + 30)) end
    end
    -- Hung from under the border like CharacterFrame's tabs (TOPLEFT on BOTTOMLEFT 11, 2;
    -- the tab's level is under the border's, so the border's bottom edge draws over its top).
    local sizes = Theme.sizes or {}
    if i == 1 then
        tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, sizes.tabOffsetY or 2)
    else
        tab:SetPoint("TOPLEFT", UI.tabs[i - 1].button, "TOPRIGHT", sizes.tabGap or 1, 0)
    end
    tab:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI:ShowTab(self.gsKey)
    end)
    tab:Show()
    return tab
end

-- frames: list of frames shown only on this tab (or a function returning it).
function UI:AddTab(key, label, frames, onShow)
    local f = self.frame
    local i = #self.tabs + 1
    local t = { key = key, frames = frames, onShow = onShow, index = i }
    self.tabs[i] = t
    self.tabByKey[key] = t
    t.button = MakeTab(f, i, label)
    t.button.gsKey = key
    if t.button.gsTemplate then
        f.numTabs = i
        PanelCall("PanelTemplates_SetNumTabs", f, i)
    end
    return t
end

local function TabFrames(t)
    local list = t.frames
    if type(list) == "function" then list = list() end
    return list or {}
end

-- Switch tab (default "sets"); the other tabs' frames hide.
function UI:ShowTab(key)
    self:Build()
    local want = self.tabByKey[key] or self.tabs[1]
    if not want then return end
    self.tab = want.key
    for _, t in ipairs(self.tabs) do
        if t ~= want then
            for _, fr in ipairs(TabFrames(t)) do fr:Hide() end
        end
    end
    for _, fr in ipairs(TabFrames(want)) do fr:Show() end
    local f = self.frame
    if want.button.gsTemplate then
        PanelCall("PanelTemplates_SetTab", f, want.index)
    end
    for _, t in ipairs(self.tabs) do
        if not t.button.gsTemplate then
            t.button:SetEnabled(t ~= want)          -- plain buttons: the open tab is greyed
        end
    end
    if want.onShow then want.onShow() end
end

function UI:CurrentTab() return self.tab or "sets" end

local function MakeTabs(self, f)
    self:AddTab("sets", T("TAB_SETS", "Sets"), function()
        local PV = ns.Preview or {}
        local list = { self.left, self.mid, self.right, PV.reset, PV.check }
        for _, b in ipairs(PV.slotButtons or {}) do list[#list + 1] = b end   -- hide-slot buttons: Sets tab only
        return list
    end, function() UI:RefreshAll() end)
    if ns.Progress and ns.Progress.Build then
        local page = MakeInset(f, 4, nil)
        page:Hide()
        self.progressPage = page
        ns.Progress:Build(page)
        self:AddTab("progress", T("TAB_PROGRESS", "Progress"), { page }, function() ns.Progress:Refresh() end)
    end
    -- 1.1 beta.4: the Plan tab (UI\Plan.lua), full-width inset like the Progress page.
    if ns.Plan and ns.Plan.Build then
        local page = MakeInset(f, 4, nil)
        page:Hide()
        self.planPage = page
        ns.Plan:Build(page)
        self:AddTab("plan", T("TAB_PLAN", "Plan"), { page }, function() ns.Plan:Refresh() end)
    end
    -- Help notes point at the Sets tab's panels.
    if ns.Help and ns.Help.Show and hooksecurefunc then
        hooksecurefunc(ns.Help, "Show", function() if UI.tab ~= "sets" then UI:ShowTab("sets") end end)
    end
    self.tab = "sets"
    PanelCall("PanelTemplates_SetTab", f, 1)
    for _, t in ipairs(self.tabs) do
        if not t.button.gsTemplate then t.button:SetEnabled(t.key ~= "sets") end
    end
end

-- ---------------------------------------------------------------------------
-- Ctrl+F focuses the search box (beta.9 part C; ToS watch-point W1, plans\v1.0.0\tos-beta9.md).
-- The window takes keyboard input but passes every key on (propagation on). Only Ctrl+F,
-- out of combat, stops that one key and turns propagation back on the next frame.
-- SetPropagateKeyboardInput is restricted in combat: if combat started in between, the
-- window stops taking keys at once (EnableKeyboard(false); if that fails, the window
-- hides) and propagation comes back after combat. In combat Ctrl+F does nothing.
UI.keys = { pending = false, waiting = false }

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

-- Out of combat only: pass keys on first, then take them (never the other way round).
local function KeysOn(f)
    f:SetPropagateKeyboardInput(true)
    f:EnableKeyboard(true)
end

local keyWait   -- one event frame, only registered while waiting for combat to end
local function AfterCombat(f)
    UI.keys.waiting = true
    if not keyWait then
        keyWait = CreateFrame("Frame")
        keyWait:SetScript("OnEvent", function(self)
            if InCombat() then return end
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            UI.keys.waiting = false
            KeysOn(f)
        end)
    end
    keyWait:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- In combat with propagation off: stop taking keys now, so no key of the player's is eaten.
local function KeysOff(f)
    local ok = pcall(f.EnableKeyboard, f, false)
    if not ok or (f.IsKeyboardEnabled and f:IsKeyboardEnabled()) then f:Hide() end
    AfterCombat(f)
end

local function RestoreKeys(f)
    UI.keys.pending = false
    if InCombat() then KeysOff(f) return end
    f:SetPropagateKeyboardInput(true)
end

function UI.OnKeyDown(f, key)
    if key ~= "F" or not (IsControlKeyDown and IsControlKeyDown()) then return end   -- every other key: untouched
    if InCombat() or UI.keys.pending or UI.keys.waiting then return end
    UI.keys.pending = true
    f:SetPropagateKeyboardInput(false)        -- this one key stays with us
    if ns.SetList and ns.SetList.FocusSearch then ns.SetList:FocusSearch() end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() RestoreKeys(f) end)
    else
        RestoreKeys(f)
    end
end

local function SetupKeys(f)
    f:SetScript("OnKeyDown", UI.OnKeyDown)
    if InCombat() then AfterCombat(f) else KeysOn(f) end
end

function UI:Build()
    if self.frame then return end
    local f = Theme.CreateFrame("Frame", "GearSetFrame", UIParent, "window")
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 0, -TabOverhang()) end   -- tabs stay on screen
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
    MakeTabs(self, f)
    self.countBox = MakeCountBox(f)
    if self.countBox and hooksecurefunc and ns.Progress.Invalidate then
        hooksecurefunc(ns.Progress, "Invalidate", CountChanged)
    end

    f:SetScript("OnShow", function()
        FitToScreen(f)
        UI:RaiseButtons()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() UI:CheckHelpButton() end)
        end
        if f.SetPortraitToUnit then f:SetPortraitToUnit("player") end
        ns.Owned:Invalidate()
        UI:RefreshAll()
        if UI.tab == "progress" and ns.Progress then ns.Progress:Refresh() end
        if ns.Help and ns.Help.MaybeShowFirstTime then ns.Help:MaybeShowFirstTime() end
    end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end)

    SetupKeys(f)
    RestorePosition(f)
end

function UI:IsShown()
    return self.frame and self.frame:IsShown()
end

-- Open the window on a tab (/gs plan).
function UI:OpenTab(key)
    self:Build()
    if not self.frame:IsShown() then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        self.frame:Show()
    end
    self:ShowTab(key)
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
    if self.tab and self.tab ~= "sets" then self:ShowTab("sets") end
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
    self:UpdateCountBox()
end

-- Owned states changed (bags, bank, equipment, collection).
function UI:RefreshCounts()
    ns.SetList:Refresh()
    ns.PieceList:Refresh()
    self:UpdateCountBox()
    if ns.Progress then ns.Progress:Refresh() end   -- only draws while its tab is shown
    if ns.Plan and ns.Plan.Queue then ns.Plan:Queue() end   -- the same (one queued redraw)
end
