-- Gear Set: guide page for one piece. Replaces the piece list in the right panel:
-- [Back] (also Esc or right-click), "Piece n of N" with previous/next arrows, the item
-- (icon, name in quality colour, slot and armor, set and classes, your state; hover =
-- the normal item tooltip), Copy name / Wiki link, then the scrolling guide built by
-- Data:GetGuide (blocks: head, sub, row, text, bullet, step, fold).
-- Esc: while the page is open its frame stands in for the window in UISpecialFrames,
-- so the game's own Esc handling closes the page first. No keyboard capture at all,
-- so it works the same in combat.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local GuidePage = {}
ns.GuidePage = GuidePage

local PAGE_NAME = "GearSetGuidePage"
local WINDOW_NAME = "GearSetFrame"
local HEADER_TOP = -36
local BUTTONS_TOP = -112
local DIVIDER_TOP = -140
local TEXT_TOP = -146
local LABEL_W = 86          -- label column of "row" blocks
local INDENT = 14           -- per fold-out level
local GAP_HEAD, GAP_SUB, GAP_LINE = 10, 6, 2

local function SimpleTip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function ShowCopy(kind, text, alt)
    if ns.ShowCopyBox then ns.ShowCopyBox(kind, text, alt)
    elseif ns.ShowReport then ns.ShowReport(text) end
end

local function ItemLink(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = get(itemID)
    return link
end

-- Esc: swap the window's UISpecialFrames entry for the page's (same index, so a
-- running CloseSpecialWindows loop is not disturbed), and back again.
local function SwapSpecial(from, to)
    if type(UISpecialFrames) ~= "table" then return end
    for i, name in ipairs(UISpecialFrames) do
        if name == from then UISpecialFrames[i] = to; return end
    end
    if to == PAGE_NAME then tinsert(UISpecialFrames, to) end
end

local function PanelButton(parent, text, tip, onClick)
    local b = Theme.CreateFrame("Button", nil, parent, "button")
    b:SetHeight(22)
    b:SetText(text)
    local fs = b.GetFontString and b:GetFontString()
    b:SetWidth(math.max(70, (fs and fs:GetStringWidth() or 60) + 24))
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) SimpleTip(self, tip) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function ArrowButton(parent, dir, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    local art = Theme.art.arrows[dir]
    b:SetNormalTexture(art.up)
    b:SetPushedTexture(art.down)
    b:SetDisabledTexture(art.disabled)
    b:SetHighlightTexture(art.highlight, "ADD")
    local nt = b:GetNormalTexture()
    if nt and nt.GetTextureFileID and not nt:GetTextureFileID() then
        local fs = b:CreateFontString(nil, "OVERLAY")
        Theme.Font(fs, "normal")
        fs:SetPoint("CENTER")
        fs:SetText(dir == "prev" and "<" or ">")
    end
    b:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        GuidePage:Step(dir == "prev" and -1 or 1)
    end)
    b:SetScript("OnEnter", function(self) SimpleTip(self, tip) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function OnRightClickBack(_, button)
    if button == "RightButton" then GuidePage:Back() end
end

local function ItemTooltip(self)
    local p = GuidePage.piece
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(p.itemID)
    GameTooltip:AddLine(" ")
    if Theme.AddHint then Theme.AddHint(GameTooltip, L.PIECE_TIP_MOD) end
    GameTooltip:Show()
end

function GuidePage:Build(parent)
    if self.page then return end
    local page = CreateFrame("Frame", PAGE_NAME, parent)
    page:SetAllPoints(parent)
    page:EnableMouse(true)
    page:SetScript("OnMouseUp", OnRightClickBack)
    page:Hide()
    page:SetScript("OnHide", function() GuidePage:OnHidden() end)
    self.page = page

    -- Top bar: Back, "Piece n of N", arrows.
    local back = PanelButton(page, (type(BACK) == "string" and BACK ~= "" and BACK) or L.G_BACK, L.G_BACK_TIP, function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        GuidePage:Back()
    end)
    back:SetPoint("TOPLEFT", 8, -7)
    self.back = back
    local nextB = ArrowButton(page, "next", L.G_NEXT)
    nextB:SetPoint("TOPRIGHT", -8, -6)
    local prevB = ArrowButton(page, "prev", L.G_PREV)
    prevB:SetPoint("RIGHT", nextB, "LEFT", 0, 0)
    self.prevB, self.nextB = prevB, nextB
    local pos = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(pos, "small")
    pos:SetPoint("RIGHT", prevB, "LEFT", -6, 0)
    pos:SetTextColor(Theme.colors.subtle:GetRGB())
    self.pos = pos

    -- Item header.
    local size = Theme.art.guideIcon or 40
    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("TOPLEFT", 12, HEADER_TOP)
    icon:SetTexCoord(unpack(Theme.art.iconCrop))
    self.icon = icon
    local border = page:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(icon)
    self.hasBorder = Theme.TryTexture(border, Theme.art.iconBorder.file)
    border:Hide()
    self.border = border

    local function Line(font, y)
        local fs = page:CreateFontString(nil, "OVERLAY")
        Theme.Font(fs, font)
        fs:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, y)
        fs:SetPoint("RIGHT", page, "RIGHT", -12, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    self.name = Line("header", 0)
    self.slot = Line("small", -20)
    self.setLine = Line("small", -34)
    self.state = Line("small", -48)

    -- Hover the icon or name: the normal item tooltip; Shift/Ctrl-click as in the list.
    local hit = CreateFrame("Button", nil, page)
    hit:SetPoint("TOPLEFT", icon, "TOPLEFT")
    hit:SetPoint("BOTTOMRIGHT", self.state, "BOTTOMRIGHT")
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnEnter", ItemTooltip)
    hit:SetScript("OnLeave", GameTooltip_Hide)
    hit:SetScript("OnClick", function(_, button)
        if button == "RightButton" then GuidePage:Back() return end
        local p = GuidePage.piece
        if p and IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP")) then
            local link = ItemLink(p.itemID)
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end
    end)
    self.hit = hit

    -- Copy name / Wiki link.
    local copy = PanelButton(page, L.COPY, L.COPY_TIP, function()
        local p = GuidePage.piece
        if not p then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ShowCopy("name", ns.Data:SearchText(p), ns.Data:WikiSearchURL(p))
    end)
    copy:SetPoint("TOPLEFT", 12, BUTTONS_TOP)
    self.copy = copy
    local wiki = PanelButton(page, L.WIKI_LINK, L.G_WIKI_TIP, function()
        local p = GuidePage.piece
        if not p then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ShowCopy("wiki", ns.Data:WikiSearchURL(p))
    end)
    wiki:SetPoint("LEFT", copy, "RIGHT", 6, 0)
    self.wiki = wiki

    local div = page:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", 8, DIVIDER_TOP)
    div:SetPoint("TOPRIGHT", -8, DIVIDER_TOP)
    div:SetColorTexture(unpack(Theme.art.guideDivider))

    -- Scrolling guide text.
    local scroll, tmpl = Theme.CreateFrame("ScrollFrame", nil, page, "scrollFrame")
    scroll:SetPoint("TOPLEFT", 4, TEXT_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    if not tmpl then
        -- No template on this client: mouse wheel only.
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(s, delta)
            local maxY = math.max(0, (GuidePage.contentH or 0) - (s:GetHeight() or 0))
            local y = math.min(maxY, math.max(0, (s:GetVerticalScroll() or 0) - delta * 40))
            s:SetVerticalScroll(y)
        end)
    end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 10)
    content:EnableMouse(true)
    content:SetScript("OnMouseUp", OnRightClickBack)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content

    self.fsPool, self.foldPool = {}, {}
    self.openFolds = {}
end

-- ---------------------------------------------------------------------------
-- Drawing the blocks: pooled font strings and fold-out buttons, laid out top-down.

local function TakeFS(self)
    self.fsUsed = self.fsUsed + 1
    local fs = self.fsPool[self.fsUsed]
    if not fs then
        fs = self.content:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        self.fsPool[self.fsUsed] = fs
    end
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

local function TakeFold(self)
    self.foldUsed = self.foldUsed + 1
    local b = self.foldPool[self.foldUsed]
    if not b then
        b = CreateFrame("Button", nil, self.content)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetSize(Theme.art.expand.size, Theme.art.expand.size)
        b.mark:SetPoint("LEFT")
        b.markText = b:CreateFontString(nil, "OVERLAY")
        Theme.Font(b.markText, "small")
        b.markText:SetPoint("CENTER", b.mark, "CENTER")
        b.label = b:CreateFontString(nil, "OVERLAY")
        Theme.Font(b.label, "small")
        b.label:SetPoint("LEFT", b.mark, "RIGHT", 4, 0)
        b.label:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(btn, button)
            if button == "RightButton" then GuidePage:Back() return end
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            GuidePage:ToggleFold(btn.block)
        end)
        b:SetScript("OnEnter", function(btn) btn.label:SetTextColor(Theme.colors.linkHover:GetRGB()) end)
        b:SetScript("OnLeave", function(btn) btn.label:SetTextColor(Theme.colors.link:GetRGB()) end)
        self.foldPool[self.foldUsed] = b
    end
    b:ClearAllPoints()
    b:Show()
    return b
end

local function Text(self, font, color, text, x, y, width)
    local fs = TakeFS(self)
    Theme.Font(fs, font)
    fs:SetTextColor(color:GetRGB())
    fs:SetWidth(width)
    fs:SetPoint("TOPLEFT", x, -y)
    fs:SetText(text or "")
    local h = fs:GetStringHeight() or 0
    if h <= 0 then h = 12 end
    return h
end

function GuidePage:LayBlocks(blocks, depth, y, width)
    local c = Theme.colors
    local x0 = 6 + depth * INDENT
    local w = width - x0 - 4
    for i, b in ipairs(blocks) do
        local k = b.k
        if k == "head" then
            if y > 0 then y = y + GAP_HEAD end
            y = y + Text(self, "normal", c.guideHead, b.text, x0, y, w) + GAP_LINE + 2
        elseif k == "sub" then
            if y > 0 and i > 1 and blocks[i - 1].k ~= "head" then y = y + GAP_SUB end
            y = y + Text(self, "text", c.guideSub, b.text, x0, y, w) + GAP_LINE
        elseif k == "row" then
            local h1 = Text(self, "small", c.guideLabel, b.label, x0 + 8, y, LABEL_W - 4)
            local h2 = 0
            if b.text and b.text ~= "" then
                h2 = Text(self, "small", c.guideText, b.text, x0 + 8 + LABEL_W, y, w - 8 - LABEL_W)
            end
            y = y + math.max(h1, h2) + GAP_LINE
        elseif k == "text" then
            y = y + Text(self, "small", c.guideText, b.text, x0 + 8, y, w - 8) + GAP_LINE
        elseif k == "bullet" then
            -- "You bring" items sit in the value column; note bullets at the left.
            local bx = b.col and (x0 + 8 + LABEL_W) or (x0 + 18)
            Text(self, "small", c.guideText, "-", bx - 10, y, 10)
            y = y + Text(self, "small", c.guideText, b.text, bx, y, w - (bx - x0)) + GAP_LINE
        elseif k == "step" then
            -- Numbers get a narrow column, words ("Belt, Gloves") the label column.
            local lw = (#(b.label or "") <= 3) and 28 or LABEL_W
            local h1 = Text(self, "small", c.guideLabel, b.label, x0 + 8, y, lw - 4)
            local text = b.here and (b.text .. "  " .. L.G_HERE) or b.text
            local h2 = Text(self, "small", b.here and c.guideHere or c.guideText, text, x0 + 8 + lw, y, w - 8 - lw)
            y = y + math.max(h1, h2) + GAP_LINE
        elseif k == "fold" then
            local btn = TakeFold(self)
            local open = self.openFolds[b] and true or false
            btn.block = b
            if not Theme.TryTexture(btn.mark, open and Theme.art.expand.minus or Theme.art.expand.plus) then
                btn.mark:Hide(); btn.markText:SetText(open and "-" or "+"); btn.markText:Show()
            else
                btn.mark:Show(); btn.markText:Hide()
            end
            btn.label:SetText(b.text)
            btn.label:SetTextColor(c.link:GetRGB())
            btn:SetPoint("TOPLEFT", x0 + 8, -y)
            btn:SetSize(math.min(w - 8, (btn.label:GetStringWidth() or 100) + Theme.art.expand.size + 8), 16)
            y = y + 16 + GAP_LINE
            if open and b.blocks then
                y = self:LayBlocks(b.blocks, depth + 1, y, width)
            end
        end
    end
    return y
end

function GuidePage:Render()
    if not (self.page and self.piece) then return end
    self.fsUsed, self.foldUsed = 0, 0
    local width = self.scroll:GetWidth() or 0
    if width < 100 then width = 420 end
    self.content:SetWidth(width)
    local blocks = ns.Data:GetGuide(self.piece)
    local y = self:LayBlocks(blocks, 0, 4, width)
    y = y + GAP_HEAD
    y = y + Text(self, "small", Theme.colors.guideLabel, L.G_FOOTER, 12, y, width - 16) + 6
    for i = self.fsUsed + 1, #self.fsPool do self.fsPool[i]:Hide() end
    for i = self.foldUsed + 1, #self.foldPool do self.foldPool[i]:Hide() end
    self.contentH = y
    self.content:SetHeight(math.max(y, 10))
end

function GuidePage:ToggleFold(block)
    if not block then return end
    self.openFolds[block] = not self.openFolds[block] or nil
    self:Render()
end

-- ---------------------------------------------------------------------------
-- Header

local function SlotAndArmor(itemID)
    local _, _, subType, equipLoc, icon, classID, subclassID = ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant)(itemID)
    local parts = {}
    local slot = equipLoc and equipLoc ~= "" and _G[equipLoc]
    if type(slot) == "string" and slot ~= "" then parts[#parts + 1] = slot end
    local armorClass = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4
    if classID == armorClass and subclassID and subclassID >= 1 and subclassID <= 4 then
        local name = ns.Data.ArmorName(subclassID) or subType
        if name then parts[#parts + 1] = name end
    end
    return table.concat(parts, " - "), icon
end

local function SetLine(set)
    if not set then return "" end
    local classes = ns.SetList and ns.SetList.ClassText and ns.SetList.ClassText(set)
    local parts = { set.name, classes or L.ALL_CLASSES }
    if set.faction then parts[#parts + 1] = ns.Data.FactionName(set.faction) end
    return table.concat(parts, " - ")
end

function GuidePage:FillHeader()
    local p = self.piece
    local itemID = p.itemID
    local slotText, icon = SlotAndArmor(itemID)
    self.icon:SetTexture(icon or 134400)
    self.slot:SetText(slotText)
    self.slot:SetTextColor(Theme.colors.subtle:GetRGB())
    self.setLine:SetText(SetLine(self.set))
    self.setLine:SetTextColor(Theme.colors.subtle:GetRGB())
    local state = ns.Owned:GetState(p)
    self.state:SetText(L["G_STATE_" .. state] or L["STATE_" .. state])
    local sc = (state == "need" and Theme.colors.need) or Theme.stateColor[state] or Theme.colors.text
    self.state:SetTextColor(sc:GetRGB())

    self.border:Hide()
    local item = Item:CreateFromItemID(itemID)
    if item:IsItemDataCached() then
        self.name:SetText(item:GetItemName())
        local q = item:GetItemQuality()
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then self.name:SetTextColor(c.r, c.g, c.b) else self.name:SetTextColor(1, 1, 1) end
        if c and self.hasBorder and q >= 2 then
            self.border:SetVertexColor(c.r, c.g, c.b)
            self.border:Show()
        end
    else
        self.name:SetText(L.LOADING)
        self.name:SetTextColor(Theme.colors.loading:GetRGB())
        item:ContinueOnItemLoad(function()
            if GuidePage.piece == p and GuidePage:IsOpen() then GuidePage:FillHeader(); GuidePage:Render() end
        end)
    end

    local n, total = 0, 0
    if self.set then
        total = #self.set.pieces
        for i, sp in ipairs(self.set.pieces) do if sp == p then n = i end end
    end
    self.pos:SetText(total > 0 and L.G_PIECE_N:format(n, total) or "")
    self.prevB:SetEnabled(total > 1)
    self.nextB:SetEnabled(total > 1)
end

-- ---------------------------------------------------------------------------

function GuidePage:IsOpen()
    return self.page ~= nil and self.page:IsShown()
end

function GuidePage:Open(piece, set)
    if not (self.page and piece) then return end
    local newPiece = piece ~= self.piece
    self.piece, self.set = piece, set
    if newPiece then self.openFolds = {} end
    if not self.page:IsShown() then
        SwapSpecial(WINDOW_NAME, PAGE_NAME)
        self.page:Show()
    end
    self:FillHeader()
    self:Render()
    if newPiece and self.scroll.SetVerticalScroll then self.scroll:SetVerticalScroll(0) end
    -- Font strings can measure short before their first draw: lay out once more next frame.
    local token = {}
    self.renderToken = token
    C_Timer.After(0, function()
        if GuidePage.renderToken == token and GuidePage:IsOpen() then GuidePage:Render() end
    end)
end

-- Previous/next piece of the set (wraps at the ends).
function GuidePage:Step(delta)
    local set, p = self.set, self.piece
    if not (set and p and #set.pieces > 0) then return end
    local idx = 1
    for i, sp in ipairs(set.pieces) do if sp == p then idx = i end end
    idx = (idx - 1 + delta) % #set.pieces + 1
    self:Open(set.pieces[idx], set)
end

-- Back to the piece list (button, Esc, right-click).
function GuidePage:Back()
    if self.page and self.page:IsShown() then self.page:Hide() end
end

-- The page was hidden: by Back, by Esc (CloseSpecialWindows) or with the window.
-- Always ends with the page's own shown flag off, so a later Esc isn't spent on it.
function GuidePage:OnHidden()
    if self.hiding then return end
    self.hiding = true
    if self.page:IsShown() then self.page:Hide() end
    self.hiding = nil
    SwapSpecial(PAGE_NAME, WINDOW_NAME)
    self.renderToken = nil
    if ns.PieceList and ns.PieceList.OnGuideClosed then ns.PieceList:OnGuideClosed() end
end

-- Owned state changed while open: the header line only.
function GuidePage:Refresh()
    if self:IsOpen() and self.piece then self:FillHeader() end
end
