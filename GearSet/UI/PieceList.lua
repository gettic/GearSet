-- Gear Set: right panel - the set's pieces and whether you have or need each one.
-- Header: set name (prev/next arrows), armor type + classes, "Have x / y" (tooltip
-- with the breakdown), a "Set bonuses" link (tooltip) and one "Report wrong source" link.
-- Each row: check box (piece shown on the preview), icon with quality frame, name
-- (up to 2 lines), state, +/- marker. Clicking a row opens it (one at a time) to show
-- where the piece comes from and a "Copy name" button. Shift/Ctrl-click = Blizzard's
-- usual item clicks (link in chat box, dressing room).
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local PieceList = {}
ns.PieceList = PieceList

local ROW_H = 36
local BAND_LEFT = 28        -- detail band starts under the icon
local BAND_PAD = 6
local COPY_H = 20
local INFO_TOP = -32        -- header: title at -10, armor/classes, then "Have x / y"
local COUNT_TOP = -50
local LIST_TOP = -74        -- where the scroll list starts below the header

-- Slots the character model doesn't show (neck, rings, trinkets, unknown).
local NO_MODEL_SLOT = { [0] = true, [2] = true, [11] = true, [12] = true, [13] = true, [14] = true }
local ICON_CROP = { 0.07, 0.93, 0.07, 0.93 }   -- cut the baked grey edge off item icons

local function ShowsOnModel(piece)
    return not NO_MODEL_SLOT[piece.slot or 0]
end

-- ---- small helpers for Theme keys another agent adds (fallbacks keep it working) ----
local function Hint(tip, text)
    if Theme.AddHint then Theme.AddHint(tip, text) return end
    local c = GREEN_FONT_COLOR
    tip:AddLine(text, c and c.r or 0.1, c and c.g or 1, c and c.b or 0.1, true)
end

local function CountRGB(have, total)
    if Theme.CountColor then return Theme.CountColor(have, total) end
    local c = (have >= total and Theme.colors.have) or (have > 0 and Theme.colors.partial) or Theme.colors.none
    return c:GetRGB()
end

local function CheckSize()
    return (Theme.sizes and Theme.sizes.check) or 24
end

local function ArtFile(entry)
    if type(entry) == "table" then return entry.file end
    return entry
end

local function SetRowArt(tex, entry, fallback)
    entry = entry or fallback
    Theme.SetAtlasOr(tex, entry.atlas, entry.file)
end

local function StateColor(state)
    if state == "need" then return Theme.colors.need end
    return Theme.stateColor[state] or Theme.colors.text
end

local function SimpleTip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function ItemLink(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = get(itemID)
    return link
end

local function PieceTooltip(row)
    local p = row.piece
    if not p then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(p.itemID)
    GameTooltip:AddLine(" ")
    Hint(GameTooltip, L.PIECE_TIP)
    Hint(GameTooltip, L.PIECE_TIP_MOD)
    GameTooltip:Show()
end

-- Link-style text button (Blizzard hyperlink colours, underline on hover).
-- tip: text, or a function(button) that fills and shows the tooltip itself.
local function LinkButton(parent, text, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(14)
    local fs = b:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, "small")
    fs:SetPoint("LEFT")
    fs:SetText(text)
    fs:SetTextColor(Theme.colors.link:GetRGB())
    b:SetWidth(fs:GetStringWidth() + 4)
    local underline = b:CreateTexture(nil, "OVERLAY")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -1)
    underline:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -1)
    underline:SetColorTexture(Theme.colors.linkHover:GetRGB())
    underline:Hide()
    b:SetScript("OnEnter", function(self)
        fs:SetTextColor(Theme.colors.linkHover:GetRGB())
        underline:Show()
        if type(tip) == "function" then tip(self) else SimpleTip(self, tip) end
    end)
    b:SetScript("OnLeave", function()
        fs:SetTextColor(Theme.colors.link:GetRGB())
        underline:Hide()
        GameTooltip_Hide()
    end)
    b:SetScript("OnClick", onClick)
    b.text = fs
    return b
end

-- Copy dialog (Core.lua). Falls back to the report dialog if the new one is missing.
local function ShowCopy(kind, text, alt)
    if ns.ShowCopyBox then ns.ShowCopyBox(kind, text, alt)
    elseif ns.ShowReport then ns.ShowReport(text) end
end

-- +/- marker: Blizzard's button art, or a plain "+"/"-" if the client lacks it.
local function SetMarker(row, open)
    local art = Theme.art.expand
    if Theme.TryTexture(row.marker, open and art.minus or art.plus) then
        row.marker:Show()
        row.markerText:Hide()
    else
        row.marker:Hide()
        row.markerText:SetText(open and "-" or "+")
        row.markerText:Show()
    end
end

local function BuildRow(row)
    row.gsInit = true
    row:RegisterForClicks("LeftButtonUp")

    -- Open row: the select art behind the 36 px top part (like the chosen set).
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.sel:SetPoint("TOPLEFT")
    row.sel:SetPoint("TOPRIGHT")
    row.sel:SetHeight(ROW_H)
    SetRowArt(row.sel, Theme.art.rowSelected, Theme.art.rowSelect)
    row.sel:Hide()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetPoint("TOPLEFT")
    row.hl:SetPoint("TOPRIGHT")
    row.hl:SetHeight(ROW_H)
    SetRowArt(row.hl, Theme.art.rowHover, Theme.art.rowHighlight)
    row.hl:SetBlendMode("ADD")

    -- Check box: piece tried on the preview.
    local cs = CheckSize()
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
        if p then SimpleTip(self, ShowsOnModel(p) and L.SHOW_PIECE_TIP or L.NO_MODEL_TIP) end
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    row.check = check

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("TOPLEFT", BAND_LEFT, -3)
    row.icon:SetTexCoord(unpack(Theme.art.iconCrop or ICON_CROP))
    row.border = row:CreateTexture(nil, "OVERLAY")
    row.border:SetAllPoints(row.icon)
    row.hasBorder = Theme.TryTexture(row.border, ArtFile(Theme.art.iconBorder))
    row.border:Hide()

    local size = Theme.art.expand.size
    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetSize(size, size)
    row.marker:SetPoint("RIGHT", row, "TOPRIGHT", -6, -ROW_H / 2)
    row.markerText = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.markerText, "normal")
    row.markerText:SetPoint("CENTER", row.marker, "CENTER")

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

    -- Detail band (only while the row is open).
    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetPoint("TOPLEFT", BAND_LEFT, -ROW_H)
    row.band:SetPoint("BOTTOMRIGHT", -4, 2)
    row.band:SetColorTexture(unpack(Theme.art.detailBand))
    row.detail = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.detail, "small")
    row.detail:SetPoint("TOPLEFT", row.band, "TOPLEFT", 8, -BAND_PAD)
    row.detail:SetPoint("TOPRIGHT", row.band, "TOPRIGHT", -8, -BAND_PAD)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(true)
    if row.detail.SetNonSpaceWrap then row.detail:SetNonSpaceWrap(true) end
    row.detail:SetTextColor(Theme.colors.detail:GetRGB())

    -- "Copy name": the piece's name (or a wiki search link) ready for Ctrl+C.
    local copy = Theme.CreateFrame("Button", nil, row, "button")
    copy:SetHeight(COPY_H)
    copy:SetPoint("TOPLEFT", row.detail, "BOTTOMLEFT", 0, -6)
    copy:SetText(L.COPY)
    local cfs = copy.GetFontString and copy:GetFontString()
    copy:SetWidth(math.max(80, (cfs and cfs:GetStringWidth() or 60) + 24))
    copy:SetScript("OnClick", function()
        local p = row.piece
        if not p then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ShowCopy("name", ns.Data:SearchText(p), ns.Data:WikiSearchURL(p))
    end)
    copy:SetScript("OnEnter", function(self) SimpleTip(self, L.COPY_TIP) end)
    copy:SetScript("OnLeave", GameTooltip_Hide)
    row.copy = copy

    row:SetScript("OnClick", function(self)
        local p = self.piece
        if not p then return end
        -- Shift-click: link into the open chat box; Ctrl-click: dressing room.
        -- Only on the player's own click; nothing is ever sent to chat.
        if IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP")) then
            local link = ItemLink(p.itemID)
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
            return
        end
        local open = PieceList.openItem ~= p.itemID
        PlaySound(open and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        PieceList:SetOpen(open and p.itemID or nil)
    end)
    row:SetScript("OnEnter", PieceTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

local function InitRow(row, piece)
    if not row.gsInit then BuildRow(row) end
    row.piece = piece
    local itemID = piece.itemID

    local _, _, _, _, icon = ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant)(itemID)
    row.icon:SetTexture(icon or 134400)  -- 134400 = question mark icon
    local hidden = ns.Preview:IsHidden(itemID)
    row.icon:SetDesaturated(hidden)

    if ShowsOnModel(piece) then
        row.check:Enable()
        row.check:SetChecked(not hidden)
    else
        row.check:SetChecked(false)
        row.check:Disable()
    end

    row.border:Hide()
    local item = Item:CreateFromItemID(itemID)
    if item:IsItemDataCached() then
        row.name:SetText(item:GetItemName())
        local q = item:GetItemQuality()
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then row.name:SetTextColor(c.r, c.g, c.b) else row.name:SetTextColor(1, 1, 1) end
        if c and row.hasBorder and q >= 2 then   -- uncommon and better, like Blizzard's item buttons
            row.border:SetVertexColor(c.r, c.g, c.b)
            row.border:Show()
        end
    else
        row.name:SetText(L.LOADING)
        local g = Theme.colors.loading or Theme.colors.none
        row.name:SetTextColor(g:GetRGB())
        item:ContinueOnItemLoad(function()
            if row.piece == piece then InitRow(row, piece) end
        end)
    end

    local state = ns.Owned:GetState(piece)
    row.state:SetText(L["STATE_" .. state])
    row.state:SetTextColor(StateColor(state):GetRGB())

    local open = PieceList.openItem == itemID
    SetMarker(row, open)
    row.sel:SetShown(open)
    if open then
        local shown = ns.Data:GetSourceLines(piece)
        row.detail:SetText(table.concat(shown, "\n"))
        row.band:Show()
        row.detail:Show()
        row.copy:Show()
        PieceList:CheckHeight(itemID, row.detail:GetStringHeight())
    else
        row.band:Hide()
        row.detail:Hide()
        row.copy:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Open row height. The lines are measured with a hidden text before the row is
-- drawn; the drawn text is checked again and the list re-laid out once if it is taller.
PieceList.extraH = {}   -- [itemID] = drawn text height when it beat the measurement

function PieceList:DetailHeight(piece)
    local shown = ns.Data:GetSourceLines(piece)
    local m = self.measure
    local width = (self.box:GetWidth() or 0) - BAND_LEFT - 4 - 16
    if width < 100 then width = 250 end
    m:SetWidth(width)
    m:SetText(table.concat(shown, "\n"))
    local h = m:GetStringHeight() or 0
    if h <= 0 then h = #shown * 12 end
    local fix = self.extraH[piece.itemID]
    if fix and fix > h then h = fix end
    self.measuredH = h
    return BAND_PAD + h + 6 + COPY_H + BAND_PAD
end

function PieceList:CheckHeight(itemID, drawn)
    if not drawn or not self.measuredH or drawn <= self.measuredH + 0.5 then return end
    if (self.extraH[itemID] or 0) >= drawn then return end
    self.extraH[itemID] = drawn
    C_Timer.After(0, function() PieceList:Refresh() end)
end

-- Open one row (itemID) or close all (nil); the list re-lays out.
function PieceList:SetOpen(itemID)
    self.openItem = itemID
    self:Refresh()
    if itemID and self.set and self.box.ScrollToElementData then
        for _, p in ipairs(self.set.pieces) do
            if p.itemID == itemID then
                local align = ScrollBoxConstants and ScrollBoxConstants.AlignNearest
                pcall(self.box.ScrollToElementData, self.box, p, align)
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
    if armor then
        local c = Theme.colors.armorLine or Theme.colors.partial
        parts[1] = c:WrapTextInColorCode(armor)
    end
    -- Class names in class colours; Dungeon Set 1/2 add "(any class can wear it)".
    local classes = ns.SetList and ns.SetList.ClassText and ns.SetList.ClassText(set)
    if not classes then classes = L.ALL_CLASSES end
    if classes ~= "" then parts[#parts + 1] = classes end
    return table.concat(parts, " - ")
end

-- "Set bonuses" tooltip: read on hover only (Data caches per set; one retry if the
-- item hasn't loaded, then the tooltip fills in if the mouse is still there).
-- Lines with a piece count are green when you have that many pieces, else grey;
-- bonuses the game already shows as in effect are green "Active: ...".
local function BonusTooltip(self)
    local set = PieceList.set
    if not set then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L.BONUSES, 1, 1, 1)
    local bonuses = ns.Data:GetSetBonuses(set, function(doneSet)
        if PieceList.set == doneSet and GameTooltip:IsOwned(self) then BonusTooltip(self) end
    end)
    if not bonuses then
        GameTooltip:AddLine(L.LOADING, Theme.colors.loading:GetRGB())
    elseif #bonuses == 0 then
        GameTooltip:AddLine(L.BONUS_NONE, Theme.colors.subtle:GetRGB())
    else
        local have = ns.Owned:SetCount(set)
        local on, off = Theme.colors.bonusOn, Theme.colors.bonusOff
        for _, b in ipairs(bonuses) do
            local r, g, bl
            local text
            if b.active then
                text = L.BONUS_ACTIVE:format(b.text)
                r, g, bl = on:GetRGB()
            else
                text = L.BONUS_LINE:format(b.n, b.text)
                r, g, bl = (have >= b.n and on or off):GetRGB()
            end
            GameTooltip:AddLine(text, r, g, bl, true)
        end
    end
    GameTooltip:Show()
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
            local r, g, bl = StateColor(e[1]):GetRGB()
            GameTooltip:AddDoubleLine(L[e[2]] or e[2], b[e[1]], r, g, bl, 1, 1, 1)
        end
    end
    if b.look > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.APPEARANCE_NOTE, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

local function ArrowButton(parent, dir, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    local art = (Theme.art.arrows and Theme.art.arrows[dir]) or {
        up = "Interface\\Buttons\\UI-SpellbookIcon-" .. (dir == "prev" and "PrevPage" or "NextPage") .. "-Up",
        down = "Interface\\Buttons\\UI-SpellbookIcon-" .. (dir == "prev" and "PrevPage" or "NextPage") .. "-Down",
        disabled = "Interface\\Buttons\\UI-SpellbookIcon-" .. (dir == "prev" and "PrevPage" or "NextPage") .. "-Disabled",
        highlight = "Interface\\Buttons\\UI-Common-MouseHilight",
    }
    b:SetNormalTexture(art.up)
    b:SetPushedTexture(art.down)
    b:SetDisabledTexture(art.disabled)
    b:SetHighlightTexture(art.highlight, "ADD")
    -- If the arrow art is missing, show a plain "<" / ">" instead.
    local nt = b:GetNormalTexture()
    if nt and nt.GetTextureFileID and not nt:GetTextureFileID() then
        local fs = b:CreateFontString(nil, "OVERLAY")
        Theme.Font(fs, "normal")
        fs:SetPoint("CENTER")
        fs:SetText(dir == "prev" and "<" or ">")
    end
    b:SetScript("OnClick", function()
        if ns.SetList and ns.SetList.SelectRelative then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            ns.SetList:SelectRelative(dir == "prev" and -1 or 1)
        end
    end)
    b:SetScript("OnEnter", function(self) SimpleTip(self, tip) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

function PieceList:Build(parent)
    local nextB = ArrowButton(parent, "next", L.NEXT_SET)
    nextB:SetPoint("TOPRIGHT", -8, -6)
    local prevB = ArrowButton(parent, "prev", L.PREV_SET)
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

    -- "Set bonuses" link right of "Have x / y" (tooltip only; nothing to click).
    local bonuses = LinkButton(parent, L.BONUSES, BonusTooltip)
    bonuses:SetPoint("LEFT", count, "RIGHT", 12, 0)
    self.bonuses = bonuses

    local report = LinkButton(parent, L.REPORT, L.REPORT_TIP, function()
        local set = PieceList.set
        if not set then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ShowCopy("report", ns.Data:SetReportURL(set))
    end)
    report:SetPoint("TOPRIGHT", -12, COUNT_TOP)
    self.report = report

    local box = Theme.CreateFrame("Frame", nil, parent, "scrollBox")
    box:SetPoint("TOPLEFT", 4, LIST_TOP)
    box:SetPoint("BOTTOMRIGHT", -22, 4)
    local bar = Theme.CreateFrame("EventFrame", nil, parent, "scrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 2)
    self.box = box

    -- Invisible text used to measure the open row's lines.
    local measure = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(measure, "small")
    measure:SetPoint("TOPLEFT")
    measure:SetJustifyH("LEFT")
    measure:SetWordWrap(true)
    if measure.SetNonSpaceWrap then measure:SetNonSpaceWrap(true) end
    measure:SetAlpha(0)
    self.measure = measure

    local view = CreateScrollBoxListLinearView()
    if view.SetElementExtentCalculator then
        view:SetElementExtentCalculator(function(_, piece)
            if piece and piece.itemID == PieceList.openItem then
                return ROW_H + PieceList:DetailHeight(piece)
            end
            return ROW_H
        end)
    else
        view:SetElementExtent(ROW_H)
    end
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

function PieceList:ShowSet(set)
    if set ~= self.set then self.openItem = nil end
    self.set = set
    self:Refresh()
end

function PieceList:Refresh()
    if not self.box then return end
    local set = self.set
    local hasSet = set ~= nil
    self.report:SetShown(hasSet)
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
    self.count:SetTextColor(CountRGB(have, total))
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.box:SetDataProvider(CreateDataProvider(set.pieces), retain)
end
