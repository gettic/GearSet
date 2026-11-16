-- Gear Set: right panel - the set's pieces and whether you have or need each one.
-- Each row: check box (piece shown on the preview), icon, name, state, +/- marker.
-- Clicking a row opens it (one at a time) to show where the piece comes from.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local PieceList = {}
ns.PieceList = PieceList

local ROW_H = 36
local BAND_LEFT = 28        -- detail band starts under the icon
local BAND_PAD = 6
local REPORT_H = 14

-- Slots the character model doesn't show (neck, rings, trinkets, unknown).
local NO_MODEL_SLOT = { [0] = true, [2] = true, [11] = true, [12] = true, [13] = true, [14] = true }

local function ShowsOnModel(piece)
    return not NO_MODEL_SLOT[piece.slot or 0]
end

local function PieceTooltip(row)
    local p = row.piece
    if not p then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(p.itemID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.PIECE_TIP, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function SimpleTip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
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
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetPoint("TOPLEFT")
    row.hl:SetPoint("TOPRIGHT")
    row.hl:SetHeight(ROW_H)
    Theme.SetAtlasOr(row.hl, Theme.art.rowHighlight.atlas, Theme.art.rowHighlight.file)
    row.hl:SetBlendMode("ADD")

    -- Check box: piece tried on the preview.
    local check = Theme.CreateFrame("CheckButton", nil, row, "check")
    check:SetSize(22, 22)
    check:SetPoint("TOPLEFT", 3, -(ROW_H - 22) / 2)
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
    row.name = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.name, "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

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
    row.detail:SetTextColor(Theme.colors.detail:GetRGB())

    -- "Report a mistake": link-style text button.
    local report = CreateFrame("Button", nil, row)
    report:SetHeight(REPORT_H)
    report:SetPoint("TOPLEFT", row.detail, "BOTTOMLEFT", 0, -4)
    local rt = report:CreateFontString(nil, "OVERLAY")
    Theme.Font(rt, "small")
    rt:SetPoint("LEFT")
    rt:SetText(L.REPORT)
    rt:SetTextColor(Theme.colors.link:GetRGB())
    report:SetWidth(rt:GetStringWidth() + 4)
    local underline = report:CreateTexture(nil, "OVERLAY")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", rt, "BOTTOMLEFT", 0, -1)
    underline:SetPoint("TOPRIGHT", rt, "BOTTOMRIGHT", 0, -1)
    underline:SetColorTexture(Theme.colors.linkHover:GetRGB())
    underline:Hide()
    report:SetScript("OnEnter", function(self)
        rt:SetTextColor(Theme.colors.linkHover:GetRGB())
        underline:Show()
        SimpleTip(self, L.REPORT_TIP)
    end)
    report:SetScript("OnLeave", function()
        rt:SetTextColor(Theme.colors.link:GetRGB())
        underline:Hide()
        GameTooltip_Hide()
    end)
    report:SetScript("OnClick", function()
        local p = row.piece
        if not p then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.ShowReport(ns.Data:ReportURL(p, PieceList.set))
    end)
    row.report = report

    row:SetScript("OnClick", function(self)
        local p = self.piece
        if not p then return end
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

    local item = Item:CreateFromItemID(itemID)
    if item:IsItemDataCached() then
        row.name:SetText(item:GetItemName())
        local q = item:GetItemQuality()
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then row.name:SetTextColor(c.r, c.g, c.b) else row.name:SetTextColor(1, 1, 1) end
    else
        row.name:SetText(L.LOADING)
        row.name:SetTextColor(0.5, 0.5, 0.5)
        item:ContinueOnItemLoad(function()
            if row.piece == piece then InitRow(row, piece) end
        end)
    end

    local state = ns.Owned:GetState(piece)
    row.state:SetText(L["STATE_" .. state])
    row.state:SetTextColor(Theme.stateColor[state]:GetRGB())

    local open = PieceList.openItem == itemID
    SetMarker(row, open)
    if open then
        local shown = ns.Data:GetSourceLines(piece)
        row.detail:SetText(table.concat(shown, "\n"))
        row.band:Show()
        row.detail:Show()
        row.report:Show()
    else
        row.band:Hide()
        row.detail:Hide()
        row.report:Hide()
    end
end

-- Height of the open row's detail band (source lines wrapped to the band width).
function PieceList:DetailHeight(piece)
    local shown = ns.Data:GetSourceLines(piece)
    local m = self.measure
    local width = (self.box:GetWidth() or 0) - BAND_LEFT - 4 - 16
    if width < 100 then width = 250 end
    m:SetWidth(width)
    m:SetText(table.concat(shown, "\n"))
    local h = m:GetStringHeight() or 0
    if h <= 0 then h = #shown * 12 end
    return BAND_PAD + h + 4 + REPORT_H + BAND_PAD + 2
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

function PieceList:Build(parent)
    local title = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(title, "header")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetPoint("TOPRIGHT", -12, -10)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    self.title = title

    local count = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(count, "text")
    count:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    self.count = count

    local box = Theme.CreateFrame("Frame", nil, parent, "scrollBox")
    box:SetPoint("TOPLEFT", 4, -54)
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

function PieceList:ShowSet(set)
    if set ~= self.set then self.openItem = nil end
    self.set = set
    self:Refresh()
end

function PieceList:Refresh()
    if not self.box then return end
    local set = self.set
    if not set then
        self.title:SetText(L.NO_SET)
        self.count:SetText("")
        self.box:SetDataProvider(CreateDataProvider({}))
        return
    end
    self.title:SetText(set.name)
    local have, total = ns.Owned:SetCount(set)
    self.count:SetText(L.HAVE_COUNT:format(have, total))
    local c = (have >= total and Theme.colors.have) or (have > 0 and Theme.colors.partial) or Theme.colors.need
    self.count:SetTextColor(c:GetRGB())
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.box:SetDataProvider(CreateDataProvider(set.pieces), retain)
end
