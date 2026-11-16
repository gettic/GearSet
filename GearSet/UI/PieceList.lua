-- Gear Set: right panel - the set's pieces and whether you have or need each one.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local PieceList = {}
ns.PieceList = PieceList

local ROW_H = 36

local function PieceTooltip(row)
    local p = row.piece
    if not p then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(p.itemID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.PIECE_TIP, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function InitRow(row, piece)
    if not row.gsInit then
        row.gsInit = true
        row:SetHeight(ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        Theme.SetAtlasOr(row.hl, Theme.art.rowHighlight.atlas, Theme.art.rowHighlight.file)
        row.hl:SetBlendMode("ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", 4, 0)
        row.state = row:CreateFontString(nil, "OVERLAY")
        Theme.Font(row.state, "small")
        row.state:SetPoint("RIGHT", -6, 0)
        row.state:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY")
        Theme.Font(row.name, "text")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if not self.piece then return end
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            ns.Preview:TogglePiece(self.piece.itemID)
            PieceList:Refresh()
        end)
        row:SetScript("OnEnter", PieceTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end
    row.piece = piece
    local itemID = piece.itemID

    local _, _, _, _, icon = ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant)(itemID)
    row.icon:SetTexture(icon or 134400)  -- 134400 = question mark icon
    row.icon:SetDesaturated(ns.Preview:IsHidden(itemID))

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
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    self.box = box
end

function PieceList:ShowSet(set)
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
