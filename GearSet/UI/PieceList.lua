-- Gear Set: right panel - the set's pieces and whether you have or need each one.
-- Header: set name (prev/next arrows), armor type + classes, "Have x / y" (tooltip
-- with the breakdown), "Set bonuses (x/y)" (tooltip).
-- Each row: check box (piece shown on the preview), icon with quality frame, name
-- (up to 2 lines), state, arrow. Clicking a row opens the piece's guide page
-- (UI\GuidePage.lua) in place of the list; Back / Esc / right-click return here.
-- Shift/Ctrl-click = Blizzard's usual item clicks (link in chat box, dressing room).
-- Shared buttons and helpers: UI\Widgets.lua (ns.Widgets).
local _, ns = ...
local Theme, L, W = ns.Theme, ns.L, ns.Widgets

local PieceList = {}
ns.PieceList = PieceList

local ROW_H = 36
local ICON_LEFT = 28        -- icon starts right of the check box
local INFO_TOP = -32       -- header: title at -10, armor/classes, then "Have x / y"
local COUNT_TOP = -50
local LIST_TOP = -74        -- where the scroll list starts below the header

local function PieceTooltip(row)
    local p = row.piece
    if not p then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(p.itemID)
    GameTooltip:AddLine(" ")
    Theme.AddHint(GameTooltip, L.PIECE_TIP)
    Theme.AddHint(GameTooltip, L.PIECE_TIP_MOD)
    GameTooltip:Show()
end

local InitRow

local function BuildRow(row)
    row.gsInit = true
    row:RegisterForClicks("LeftButtonUp")

    -- Last piece looked at: the select art (like the chosen set).
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.sel:SetPoint("TOPLEFT")
    row.sel:SetPoint("TOPRIGHT")
    row.sel:SetHeight(ROW_H)
    Theme.SetArt(row.sel, Theme.art.rowSelected)
    row.sel:Hide()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetPoint("TOPLEFT")
    row.hl:SetPoint("TOPRIGHT")
    row.hl:SetHeight(ROW_H)
    Theme.SetArt(row.hl, Theme.art.rowHover)
    row.hl:SetBlendMode("ADD")

    -- Check box: piece tried on the preview.
    local cs = Theme.sizes.check
    local check = Theme.CreateFrame("CheckButton", nil, row, "check")
    check:SetSize(cs, cs)
    check:SetPoint("TOPLEFT", 2, -(ROW_H - cs) / 2)
    check:SetScript("OnClick", function(self)
        local p = row.piece
        if not p then return end
        local shown = self:GetChecked() and true or false
        PlaySound(shown and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        ns.Preview:SetPieceShown(p.itemID, shown)
        row.icon:SetDesaturated(not shown)
    end)
    check:SetScript("OnEnter", function(self)
        local p = row.piece
        if p then W.SimpleTip(self, W.ShowsOnModel(p) and L.SHOW_PIECE_TIP or L.NO_MODEL_TIP) end
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    row.check = check

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("TOPLEFT", ICON_LEFT, -3)
    row.icon:SetTexCoord(unpack(W.ICON_CROP))
    row.border, row.hasBorder = W.IconBorder(row, row.icon)

    -- Arrow at the right end: the row opens a page. ">" if the art is missing.
    local arrow = Theme.art.rowArrow
    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetSize(arrow.size, arrow.size)
    row.marker:SetPoint("RIGHT", row, "TOPRIGHT", -6, -ROW_H / 2)
    if not Theme.TryTexture(row.marker, arrow.file) then
        row.marker:Hide()
        local t = row:CreateFontString(nil, "OVERLAY")
        Theme.Font(t, "normal")
        t:SetPoint("CENTER", row.marker, "CENTER")
        t:SetText(">")
    end

    row.state = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.state, "small")
    row.state:SetPoint("RIGHT", row.marker, "LEFT", -6, 0)
    row.state:SetJustifyH("RIGHT")
    -- Name: up to 2 lines (fits the 36 px row), so long names aren't cut.
    row.name = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.name, "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(true)
    if row.name.SetMaxLines then row.name:SetMaxLines(2) end

    row:SetScript("OnClick", function(self)
        local p = self.piece
        if not p then return end
        -- Shift-click: link into the open chat box; Ctrl-click: dressing room.
        -- Only on the player's own click; nothing is ever sent to chat.
        if W.HandleModifiedClick(p.itemID) then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        GameTooltip_Hide()
        PieceList:ShowGuide(p)
    end)
    row:SetScript("OnEnter", PieceTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

-- Item loaded later: refill the row (Widgets only calls back while it still shows that item).
local function OnRowItemLoaded(row)
    if row.piece then InitRow(row, row.piece) end
end

InitRow = function(row, piece)
    if not row.gsInit then BuildRow(row) end
    row.piece = piece
    local itemID = piece.itemID

    local _, _, _, _, icon = ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant)(itemID)
    row.icon:SetTexture(icon or 134400)  -- 134400 = question mark icon
    local hidden = ns.Preview:IsHidden(itemID)
    row.icon:SetDesaturated(hidden)

    if W.ShowsOnModel(piece) then
        row.check:Enable()
        row.check:SetChecked(not hidden)
    else
        row.check:SetChecked(false)
        row.check:Disable()
    end

    W.FillItem(row, itemID, OnRowItemLoaded)

    local state = ns.Owned:GetState(piece)
    row.state:SetText(L["STATE_" .. state])
    row.state:SetTextColor(W.StateColor(state):GetRGB())

    row.sel:SetShown(PieceList.lastItem == itemID)
end

-- ---------------------------------------------------------------------------
-- Guide page: shown in place of the header and list (same right panel).
function PieceList:ShowGuide(piece)
    if not (piece and ns.GuidePage and ns.GuidePage.page) then return end
    self.root:Hide()
    ns.GuidePage:Open(piece, self.set)
end

function PieceList:HideGuide()
    if ns.GuidePage and ns.GuidePage:IsOpen() then ns.GuidePage:Back()
    elseif self.root then self.root:Show() end
end

-- Called by GuidePage when its page hides (Back, Esc, right-click, window closed):
-- the list comes back, the piece last looked at is marked and scrolled into view.
function PieceList:OnGuideClosed()
    if not self.root then return end
    local p = ns.GuidePage and ns.GuidePage.piece
    self.lastItem = p and p.itemID or nil
    self.root:Show()
    self:Refresh()
    if p and self.set and self.box.ScrollToElementData then
        for _, sp in ipairs(self.set.pieces) do
            if sp == p then
                local align = ScrollBoxConstants and ScrollBoxConstants.AlignNearest
                pcall(self.box.ScrollToElementData, self.box, sp, align)
                break
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Header

-- Armor type (gold) and classes (class colours), e.g. "Plate - Warrior, Paladin".
local function SetInfoText(set)
    local parts = {}
    local armor = ns.Data.ArmorName(set.armor)
    if armor then parts[1] = Theme.colors.armorLine:WrapTextInColorCode(armor) end
    -- Class names in class colours; Dungeon Set 1/2 add "(any class can wear it)".
    local classes = ns.SetList and ns.SetList.ClassText and ns.SetList.ClassText(set)
    if not classes then classes = L.ALL_CLASSES end
    if classes ~= "" then parts[#parts + 1] = classes end
    return table.concat(parts, " - ")
end

-- Set bonuses only count pieces you wear (not bags, bank or appearances).
local function WornCount(set)
    return ns.Owned:SetBreakdown(set).equipped or 0
end

-- A bonus is in effect when you wear enough pieces (or the game already showed it as on).
local function BonusOn(b, worn)
    return b.active or (b.n ~= nil and worn >= b.n)
end

-- How many bonuses are in effect, and how many there are.
function PieceList.BonusCount(bonuses, worn)
    local on = 0
    for _, b in ipairs(bonuses) do
        if BonusOn(b, worn) then on = on + 1 end
    end
    return on, #bonuses
end

-- "Set bonuses" tooltip, like the set block of Blizzard's item tooltip: set name with
-- pieces worn, then each bonus green when worn pieces reach it, else grey. Read on hover
-- (Data caches per set; one retry if the item hasn't loaded, then it refills if still hovered).
local function BonusTooltip(self)
    local set = PieceList.set
    if not set then return end
    local refilled = false
    local bonuses = ns.Data:GetSetBonuses(set, function(doneSet)
        refilled = true
        if PieceList.set == doneSet then
            PieceList:UpdateBonuses()
            if GameTooltip:IsOwned(self) then BonusTooltip(self) end
        end
    end)
    if refilled then return end      -- the callback ran at once and already drew it
    local worn, total = WornCount(set), #set.pieces
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    local head = Theme.colors.bonusTitle
    GameTooltip:SetText(L.BONUS_TITLE:format(set.name, worn, total), head:GetRGB())
    if not bonuses then
        GameTooltip:AddLine(L.LOADING, Theme.colors.loading:GetRGB())
    elseif #bonuses == 0 then
        GameTooltip:AddLine(L.BONUS_NONE, Theme.colors.subtle:GetRGB())
    else
        local on, off = Theme.colors.bonusOn, Theme.colors.bonusOff
        for _, b in ipairs(bonuses) do
            local text = b.n and L.BONUS_LINE:format(b.n, b.text) or L.BONUS_ACTIVE:format(b.text)
            local r, g, bl = (BonusOn(b, worn) and on or off):GetRGB()
            GameTooltip:AddLine(text, r, g, bl, true)
        end
        GameTooltip:AddLine(" ")
        local r, g, bl = Theme.colors.subtle:GetRGB()
        GameTooltip:AddLine(L.BONUS_WEARING:format(worn, total), r, g, bl, true)
    end
    GameTooltip:Show()
end

-- "Set bonuses (1/3)" next to "Have x / y"; greyed when the set has no bonus.
function PieceList:UpdateBonuses()
    local b, set = self.bonuses, self.set
    if not (b and set) then return end
    local refilled = false
    local bonuses = ns.Data:GetSetBonuses(set, function(doneSet)
        refilled = true
        if PieceList.set == doneSet then
            PieceList:UpdateBonuses()
            if GameTooltip:IsOwned(b) then BonusTooltip(b) end
        end
    end)
    if refilled then return end
    if bonuses and #bonuses > 0 then
        b:SetLinkText(L.BONUSES_N:format(PieceList.BonusCount(bonuses, WornCount(set))))
        b:SetDim(false)
    else
        b:SetLinkText(L.BONUSES)
        b:SetDim(bonuses ~= nil)     -- loading: normal; no bonus at all: grey
    end
end

local function TitleTooltip(self)
    local set = PieceList.set
    if not set then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(set.name, 1, 1, 1, 1, true)
    GameTooltip:AddLine(SetInfoText(set), 1, 1, 1, true)
    GameTooltip:Show()
end

-- "Have x / y" tooltip: what you have, split by where it is.
local BREAKDOWN = {
    { "equipped", "STATE_equipped" }, { "bags", "STATE_bags" }, { "bank", "STATE_bank" },
    { "look", "APPEARANCE_ONLY" }, { "need", "STATE_need" },
}
local function CountTooltip(self)
    local set = PieceList.set
    if not set then return end
    local b = ns.Owned:SetBreakdown(set)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L.HAVE_COUNT:format(ns.Owned:SetCount(set)), 1, 1, 1)
    for _, e in ipairs(BREAKDOWN) do
        if b[e[1]] > 0 then
            local r, g, bl = W.StateColor(e[1]):GetRGB()
            GameTooltip:AddDoubleLine(L[e[2]] or e[2], b[e[1]], r, g, bl, 1, 1, 1)
        end
    end
    if b.look > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.APPEARANCE_NOTE, Theme.colors.subtle:GetRGB())
    end
    GameTooltip:Show()
end

local function StepSet(delta)
    if ns.SetList and ns.SetList.SelectRelative then ns.SetList:SelectRelative(delta) end
end

function PieceList:Build(panel)
    -- Header and list live in one frame, so the guide page can stand in for both.
    local parent = CreateFrame("Frame", nil, panel)
    parent:SetAllPoints(panel)
    self.root = parent
    if ns.GuidePage then ns.GuidePage:Build(panel) end

    local nextB = W.ArrowButton(parent, "next", L.NEXT_SET, function() StepSet(1) end)
    nextB:SetPoint("TOPRIGHT", -8, -6)
    local prevB = W.ArrowButton(parent, "prev", L.PREV_SET, function() StepSet(-1) end)
    prevB:SetPoint("RIGHT", nextB, "LEFT", 0, 0)
    self.prevB, self.nextB = prevB, nextB

    local title = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(title, "header")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetPoint("TOPRIGHT", prevB, "TOPLEFT", -4, -4)   -- arrows sit at y -6, title at -10
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    self.title = title
    -- Mouse area over the title: full name + armor/classes in a tooltip.
    local titleHit = CreateFrame("Frame", nil, parent)
    titleHit:SetPoint("TOPLEFT", title, "TOPLEFT")
    titleHit:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT")
    titleHit:EnableMouse(true)
    titleHit:SetScript("OnEnter", TitleTooltip)
    titleHit:SetScript("OnLeave", GameTooltip_Hide)

    local info = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(info, "small")
    info:SetPoint("TOPLEFT", 12, INFO_TOP)
    info:SetPoint("TOPRIGHT", -12, INFO_TOP)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    self.info = info

    local count = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(count, "text")
    count:SetPoint("TOPLEFT", 12, COUNT_TOP)
    self.count = count
    local countHit = CreateFrame("Frame", nil, parent)
    countHit:SetPoint("TOPLEFT", count, "TOPLEFT")
    countHit:SetPoint("BOTTOMRIGHT", count, "BOTTOMRIGHT")
    countHit:EnableMouse(true)
    countHit:SetScript("OnEnter", CountTooltip)
    countHit:SetScript("OnLeave", GameTooltip_Hide)

    -- "Set bonuses (x/y)" right of "Have x / y": hover-only, so gold label style, not a link.
    local bonuses = W.LinkButton(parent, L.BONUSES, BonusTooltip, nil, "label")
    bonuses:SetPoint("LEFT", count, "RIGHT", 12, 0)
    self.bonuses = bonuses

    local box = Theme.CreateFrame("Frame", nil, parent, "scrollBox")
    box:SetPoint("TOPLEFT", 4, LIST_TOP)
    box:SetPoint("BOTTOMRIGHT", -22, 4)
    local bar = Theme.CreateFrame("EventFrame", nil, parent, "scrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 2)
    self.box = box

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
end

-- Big font for the set name; the smaller one if it doesn't fit.
function PieceList:SetTitle(text)
    local t = self.title
    Theme.Font(t, "header")
    t:SetText(text)
    local w = t:GetWidth() or 0
    if w > 0 and t:GetStringWidth() > w then
        Theme.Font(t, "normal")
        t:SetText(text)
    end
end

-- Another set closes the guide page (back to the list of the new set).
function PieceList:ShowSet(set)
    local changed = set ~= self.set
    self.set = set
    if changed then
        self.lastItem = nil
        if ns.GuidePage and ns.GuidePage:IsOpen() then
            ns.GuidePage:Back()        -- OnGuideClosed refreshes
            self.lastItem = nil
        end
    end
    self:Refresh()
end

function PieceList:Refresh()
    if not self.box then return end
    local set = self.set
    local hasSet = set ~= nil
    self.bonuses:SetShown(hasSet)
    self.prevB:SetEnabled(hasSet)
    self.nextB:SetEnabled(hasSet)
    if not hasSet then
        self:SetTitle(L.NO_SET)
        self.info:SetText("")
        self.count:SetText("")
        self.box:SetDataProvider(CreateDataProvider({}))
        return
    end
    self:SetTitle(set.name)
    self.info:SetText(SetInfoText(set))
    local have, total = ns.Owned:SetCount(set)
    self.count:SetText(L.HAVE_COUNT:format(have, total))
    self.count:SetTextColor(Theme.CountColor(have, total))
    self:UpdateBonuses()
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.box:SetDataProvider(CreateDataProvider(set.pieces), retain)
    if ns.GuidePage and ns.GuidePage:IsOpen() then ns.GuidePage:Refresh() end
end
