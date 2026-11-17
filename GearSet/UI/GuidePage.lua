-- Gear Set: guide page for one piece. Replaces the piece list in the right panel:
-- top bar [Back] [Copy name] [Wiki link] and "Piece n of N" with previous/next arrows
-- (Shift-click: the next piece you still need), the item (icon, name in quality colour,
-- slot and armor, set and classes, your state, "Show on model", "Copy text"; hover =
-- the normal item tooltip), then the scrolling guide built by Data:GetGuide (blocks:
-- head, sub, row, text, bullet, step, fold).
-- "Copy text" swaps the guide for the same text in a read-only edit box (copy view).
-- Esc: while the page is open its frame stands in for the window in UISpecialFrames,
-- so the game's own Esc handling closes the page first. The only keyboard focus is the
-- copy view's edit box, and every way out of it clears the focus (Esc, Done, Back,
-- arrows, right-click, page hidden), so movement keys are never left captured.
local _, ns = ...
local Theme, L, W = ns.Theme, ns.L, ns.Widgets

local GuidePage = {}
ns.GuidePage = GuidePage

local PAGE_NAME = "GearSetGuidePage"
local WINDOW_NAME = "GearSetFrame"
local HEADER_TOP = -36
local STATE_Y = HEADER_TOP - 54   -- centre of the state line (icon top -48, small font)
local DIVIDER_TOP = -104
local TEXT_TOP = -110
local LABEL_W = 86          -- label column of "row" blocks
local INDENT = 14           -- per fold-out level
local GAP_HEAD, GAP_SUB, GAP_LINE = 14, 6, 2

local function OnRightClickBack(_, button)
    if button == "RightButton" then GuidePage:Back() end
end

local function ItemTooltip(self)
    local p = GuidePage.piece
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(p.itemID)
    GameTooltip:AddLine(" ")
    Theme.AddHint(GameTooltip, L.PIECE_TIP_MOD)
    GameTooltip:Show()
end

local function ArrowTip(text)
    return function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        Theme.AddHint(GameTooltip, L.G_NEED_STEP or "Shift-click: the next piece you still need.")
        GameTooltip:Show()
    end
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

-- Re-anchor the modern scroll bar like the piece list's (inside the panel's right edge).
local function PlaceScrollBar(scroll, tmpl)
    local bar = scroll.ScrollBar
    if tmpl == "ScrollFrameTemplate" and type(bar) == "table" and bar.ClearAllPoints then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -2)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 2)
    end
end

local function ScrollArea(parent, top)
    local scroll, tmpl = Theme.CreateFrame("ScrollFrame", nil, parent, "scrollFrame")
    scroll:SetPoint("TOPLEFT", 6, top)
    scroll:SetPoint("BOTTOMRIGHT", -22, 6)
    PlaceScrollBar(scroll, tmpl)
    if not tmpl then
        -- No template on this client: mouse wheel only.
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(s, delta)
            local child = s:GetScrollChild()
            local h = child and child:GetHeight() or 0
            local maxY = math.max(0, h - (s:GetHeight() or 0))
            local y = math.min(maxY, math.max(0, (s:GetVerticalScroll() or 0) - delta * 40))
            s:SetVerticalScroll(y)
        end)
    end
    return scroll
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

    -- Top bar: Back, Copy name, Wiki link ... "Piece n of N", arrows.
    local back = W.PanelButton(page, (type(BACK) == "string" and BACK ~= "" and BACK) or L.G_BACK, L.G_BACK_TIP, function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        GuidePage:Back()
    end)
    back:SetPoint("TOPLEFT", 8, -7)
    self.back = back
    local copy = W.PanelButton(page, L.COPY, L.COPY_TIP, function()
        local p = GuidePage.piece
        if not p then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        W.ShowCopy("name", ns.Data:SearchText(p), ns.Data:WikiSearchURL(p))
    end)
    copy:SetPoint("LEFT", back, "RIGHT", 6, 0)
    self.copy = copy
    local wiki = W.PanelButton(page, L.WIKI_LINK, L.G_WIKI_TIP, function()
        local p = GuidePage.piece
        if not p then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        W.ShowCopy("wiki", ns.Data:WikiSearchURL(p))
    end)
    wiki:SetPoint("LEFT", copy, "RIGHT", 6, 0)
    self.wiki = wiki

    local function Arrow(dir, delta, tip)
        return W.ArrowButton(page, dir, ArrowTip(tip), function()
            GuidePage:Step(delta, IsShiftKeyDown and IsShiftKeyDown())
        end)
    end
    local nextB = Arrow("next", 1, L.G_NEXT)
    nextB:SetPoint("TOPRIGHT", -8, -6)
    local prevB = Arrow("prev", -1, L.G_PREV)
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
    icon:SetTexCoord(unpack(W.ICON_CROP))
    self.icon = icon
    self.border, self.hasBorder = W.IconBorder(page, icon)

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
    local state = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(state, "small")
    state:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -48)
    state:SetJustifyH("LEFT")
    state:SetWordWrap(false)
    self.state = state

    -- Hover the icon or name: the normal item tooltip; Shift/Ctrl-click as in the list.
    local hit = CreateFrame("Button", nil, page)
    hit:SetPoint("TOPLEFT", icon, "TOPLEFT")
    hit:SetPoint("BOTTOMRIGHT", self.setLine, "BOTTOMRIGHT")
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnEnter", ItemTooltip)
    hit:SetScript("OnLeave", GameTooltip_Hide)
    hit:SetScript("OnClick", function(_, button)
        if button == "RightButton" then GuidePage:Back() return end
        local p = GuidePage.piece
        if p then W.HandleModifiedClick(p.itemID) end
    end)
    self.hit = hit

    -- State line, right side: [x] Show on model   Copy text
    local copyText = W.LinkButton(page, L.G_COPY_TEXT or "Copy text", L.G_COPY_TIP or "Shows this guide as text you can select and copy.", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if GuidePage.copyMode then GuidePage:HideCopyText() else GuidePage:ShowCopyText() end
    end)
    copyText:SetPoint("RIGHT", page, "TOPRIGHT", -12, STATE_Y)
    self.copyText = copyText

    local cs = Theme.sizes.check
    local modelLabel = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(modelLabel, "small")
    modelLabel:SetText(L.G_SHOW_MODEL or "Show on model")
    modelLabel:SetPoint("RIGHT", copyText, "LEFT", -14, 0)
    local check = Theme.CreateFrame("CheckButton", nil, page, "check")
    check:SetSize(cs, cs)
    check:SetPoint("RIGHT", modelLabel, "LEFT", 0, 0)
    check:SetHitRectInsets(0, -((modelLabel:GetStringWidth() or 80) + 2), 0, 0)   -- label clicks too
    check:SetScript("OnClick", function(btn)
        local p = GuidePage.piece
        if not p then return end
        local shown = btn:GetChecked() and true or false
        PlaySound(shown and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        ns.Preview:SetPieceShown(p.itemID, shown)
    end)
    check:SetScript("OnEnter", function(btn)
        local p = GuidePage.piece
        if p then W.SimpleTip(btn, W.ShowsOnModel(p) and L.SHOW_PIECE_TIP or L.NO_MODEL_TIP) end
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    self.modelCheck, self.modelLabel = check, modelLabel
    state:SetPoint("RIGHT", check, "LEFT", -6, 0)
    -- Above the item hover area.
    local level = (hit:GetFrameLevel() or 1) + 2
    check:SetFrameLevel(level)
    copyText:SetFrameLevel(level)

    local div = page:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", 8, DIVIDER_TOP)
    div:SetPoint("TOPRIGHT", -8, DIVIDER_TOP)
    Theme.SetDivider(div)

    -- Scrolling guide text.
    local scroll = ScrollArea(page, TEXT_TOP)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 10)
    content:EnableMouse(true)
    content:SetScript("OnMouseUp", OnRightClickBack)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content

    self.fsPool, self.foldPool, self.linePool = {}, {}, {}
    self.openFolds = {}
end

-- ---------------------------------------------------------------------------
-- Drawing the blocks: pooled font strings, divider lines and fold-out buttons,
-- laid out top-down. (The copy view's PlainLines below reads the same blocks:
-- a new block kind goes in both.)

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

local function TakeLine(self)
    self.lineUsed = self.lineUsed + 1
    local t = self.linePool[self.lineUsed]
    if not t then
        t = self.content:CreateTexture(nil, "ARTWORK")
        t.gsH = Theme.SetDivider(t)
        self.linePool[self.lineUsed] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
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
            GuidePage:ToggleFold(btn.foldKey)
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

-- Fold-outs are remembered by a text key (enclosing fold, heading, label and how often
-- that label came before), not by block table: they stay open on the other pieces of
-- the set, and on guides that are rebuilt on every draw.
local function FoldKey(self, path, head, text)
    local key = (path or "") .. "\31" .. (head or "") .. "\31" .. (text or "")
    local n = (self.foldCount[key] or 0) + 1
    self.foldCount[key] = n
    return key .. "#" .. n
end

local function IsStepNumber(label)
    return #(label or "") <= 3
end

function GuidePage:LayBlocks(blocks, depth, y, width, path)
    local c = Theme.colors
    local x0 = 6 + depth * INDENT
    local w = width - x0 - 4
    local head
    for i, b in ipairs(blocks) do
        local k = b.k
        if k == "head" then
            head = b.text
            if y > 4 then y = y + GAP_HEAD end
            y = y + Text(self, "normal", c.guideHead, b.text, x0, y, w) + 2
            local line = TakeLine(self)
            line:SetPoint("TOPLEFT", x0, -y)
            line:SetWidth(w)
            y = y + (line.gsH or 1) + 4
        elseif k == "sub" then
            if y > 4 and i > 1 and blocks[i - 1].k ~= "head" then y = y + GAP_SUB end
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
        elseif k == "flag" then
            -- WoW Forever flag: "Not confirmed on WoW Forever yet", "Not yet released" ...
            local col = (Theme.flagColor and Theme.flagColor[b.flag]) or c.guideNote
            y = y + Text(self, "small", col, b.text, x0 + 8, y, w - 8) + GAP_LINE
        elseif k == "bullet" then
            -- "You bring" items sit in the value column; note bullets at the left.
            local bx = b.col and (x0 + 8 + LABEL_W) or (x0 + 18)
            Text(self, "small", c.guideText, "-", bx - 10, y, 10)
            y = y + Text(self, "small", c.guideText, b.text, bx, y, w - (bx - x0)) + GAP_LINE
            if b.sub then   -- where a hand-in item drops
                y = y + Text(self, "small", c.guideNote, b.sub, bx, y, w - (bx - x0)) + GAP_LINE
            end
        elseif k == "step" then
            -- Numbers get a narrow column, words ("Belt, Gloves") the label column.
            local lw = IsStepNumber(b.label) and 28 or LABEL_W
            local h1 = Text(self, "small", c.guideLabel, b.label, x0 + 8, y, lw - 4)
            local text = b.here and (b.text .. "  " .. L.G_HERE) or b.text
            local h2 = Text(self, "small", b.here and c.guideHere or c.guideText, text, x0 + 8 + lw, y, w - 8 - lw)
            y = y + math.max(h1, h2) + GAP_LINE
        elseif k == "fold" then
            local key = FoldKey(self, path, head, b.text)
            local btn = TakeFold(self)
            local open = self.openFolds[key] and true or false
            btn.foldKey = key
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
                y = self:LayBlocks(b.blocks, depth + 1, y, width, key)
            end
        elseif b.text and b.text ~= "" then
            -- A kind this page doesn't know yet: as a labelled row or plain text.
            if b.label and b.label ~= "" then
                local h1 = Text(self, "small", c.guideLabel, b.label, x0 + 8, y, LABEL_W - 4)
                local h2 = Text(self, "small", c.guideText, b.text, x0 + 8 + LABEL_W, y, w - 8 - LABEL_W)
                y = y + math.max(h1, h2) + GAP_LINE
            else
                y = y + Text(self, "small", c.guideText, b.text, x0 + 8, y, w - 8) + GAP_LINE
            end
        end
    end
    return y
end

function GuidePage:Render()
    if not (self.page and self.piece) then return end
    self.fsUsed, self.foldUsed, self.lineUsed = 0, 0, 0
    self.foldCount = {}
    local width = self.scroll:GetWidth() or 0
    if width < 100 then width = 434 end
    self.content:SetWidth(width)
    local blocks = ns.Data:GetGuide(self.piece)
    local y = self:LayBlocks(blocks, 0, 4, width, "")
    y = y + 6
    for i = self.fsUsed + 1, #self.fsPool do self.fsPool[i]:Hide() end
    for i = self.foldUsed + 1, #self.foldPool do self.foldPool[i]:Hide() end
    for i = self.lineUsed + 1, #self.linePool do self.linePool[i]:Hide() end
    self.contentH = y
    self.content:SetHeight(math.max(y, 10))
    if self.copyMode then self:FillCopyText() end
end

function GuidePage:ToggleFold(key)
    if not key then return end
    self.openFolds[key] = not self.openFolds[key] or nil
    self:Render()
end

-- ---------------------------------------------------------------------------
-- Copy view: the guide as plain text in a read-only edit box, in place of the guide.
-- PlainLines walks the same blocks as LayBlocks (a new block kind goes in both);
-- every fold-out is included, open or not.

local function Plain(s)
    return ns.Data.StripCodes(s) or ""
end

function GuidePage.PlainLines(blocks, depth, out)
    local ind = string.rep("  ", depth)
    local ind2 = ind .. "  "
    for _, b in ipairs(blocks or {}) do
        local k, text, label = b.k, Plain(b.text), Plain(b.label)
        if k == "head" then
            if #out > 0 and out[#out] ~= "" then out[#out + 1] = "" end
            out[#out + 1] = ind .. text
        elseif k == "sub" then
            out[#out + 1] = ind .. text
        elseif k == "row" then
            out[#out + 1] = ind2 .. label .. ":" .. (text ~= "" and (" " .. text) or "")
        elseif k == "text" or k == "flag" then
            out[#out + 1] = ind2 .. text
        elseif k == "bullet" then
            out[#out + 1] = ind2 .. (b.col and "  " or "") .. "- " .. text
            if b.sub then out[#out + 1] = ind2 .. (b.col and "  " or "") .. "  " .. Plain(b.sub) end
        elseif k == "step" then
            local sep = IsStepNumber(label) and ". " or ": "
            out[#out + 1] = ind2 .. label .. sep .. text .. (b.here and ("  " .. L.G_HERE) or "")
        elseif k == "fold" then
            out[#out + 1] = ind2 .. "[" .. text .. "]"
            GuidePage.PlainLines(b.blocks, depth + 1, out)
        elseif text ~= "" or label ~= "" then
            out[#out + 1] = ind2 .. (label ~= "" and (label .. ": ") or "") .. text
        end
    end
    return out
end

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

function GuidePage:PlainText()
    local p = self.piece
    local out = {}
    out[1] = ns.Data:SearchText(p)
    local slot = SlotAndArmor(p.itemID)
    local parts = {}
    if slot ~= "" then parts[1] = slot end
    if self.set then parts[#parts + 1] = self.set.name end
    if #parts > 0 then out[#out + 1] = table.concat(parts, " - ") end
    out[#out + 1] = ns.Data:WikiSearchURL(p)
    GuidePage.PlainLines(ns.Data:GetGuide(p), 0, out)
    return table.concat(out, "\n")
end

local function BuildCopyView(self)
    local page = self.page
    local hint = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(hint, "small")
    hint:SetTextColor(Theme.colors.guideHint:GetRGB())
    hint:SetPoint("TOPLEFT", 12, TEXT_TOP)
    hint:SetPoint("RIGHT", page, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.G_COPY_HINT or "Text is selected - press Ctrl+C to copy. Esc or Done goes back.")
    local scroll = ScrollArea(page, TEXT_TOP - 18)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:EnableMouse(true)
    box:SetFontObject(Theme.fonts.small)
    box:SetTextInsets(6, 6, 2, 2)
    box:SetMaxLetters(0)                                  -- 0 = no limit
    if box.SetMaxBytes then pcall(box.SetMaxBytes, box, 0) end
    -- A box without a template may draw its selection invisibly: give it a colour.
    local hl = Theme.colors.copyHighlight
    if hl and box.SetHighlightColor then box:SetHighlightColor(hl:GetRGBA()) end
    box:SetWidth(400)
    box:SetHeight(100)
    box:SetScript("OnEscapePressed", function() GuidePage:HideCopyText() end)
    box:SetScript("OnTextChanged", function(eb, userInput)
        if userInput then                                 -- read-only: typing puts the text back
            eb:SetText(eb.gsText or "")
            eb:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(eb) eb:HighlightText() end)
    box:SetScript("OnMouseUp", function(eb, button)
        if button == "RightButton" then GuidePage:Back() return end
        eb:HighlightText()                                -- a click selects all, ready for Ctrl+C
    end)
    scroll:SetScrollChild(box)
    -- The box follows the area's real width (it can read 0 on the frame it's made).
    scroll:HookScript("OnSizeChanged", function()
        if GuidePage.copyMode then GuidePage:FillCopyText() end
    end)
    -- Measures the text height for the box (the box itself may not grow on its own).
    local measure = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(measure, "small")
    measure:SetWordWrap(true)
    measure:Hide()
    self.copyHint, self.copyScroll, self.copyBox, self.copyMeasure = hint, scroll, box, measure
end

function GuidePage:FillCopyText()
    local box = self.copyBox
    if not (box and self.piece) then return end
    local text = self:PlainText()
    local width = self.copyScroll:GetWidth() or 0
    if width > 0 then box:SetWidth(width) else width = box:GetWidth() or 400 end
    box.gsText = text
    box:SetText(text)
    self.copyMeasure:SetWidth(width - 12)
    self.copyMeasure:SetText(text)
    local h = (self.copyMeasure:GetStringHeight() or 0) + 12
    box:SetHeight(math.max(h, self.copyScroll:GetHeight() or 0, 20))
    if box.HasFocus and box:HasFocus() then box:HighlightText() end
end

function GuidePage:ShowCopyText()
    if not (self.page and self.piece) then return end
    if not self.copyBox then BuildCopyView(self) end
    self.copyMode = true
    self.scroll:Hide()
    self.copyHint:Show()
    self.copyScroll:Show()
    self.copyText:SetLinkText(L.G_COPY_DONE or DONE or "Done")
    self:FillCopyText()
    if self.copyScroll.SetVerticalScroll then self.copyScroll:SetVerticalScroll(0) end
    local box = self.copyBox
    box:SetCursorPosition(0)
    box:SetFocus()
    box:HighlightText()
    -- A multi-line box lays its text out again a frame later, which can drop the
    -- selection: refill and select once more next frame (if still in the copy view).
    local token = {}
    self.copyToken = token
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if GuidePage.copyToken ~= token or not GuidePage.copyMode or not GuidePage:IsOpen() then return end
            GuidePage:FillCopyText()
            box:SetFocus()
            box:HighlightText()
        end)
    end
end

-- Back to the normal guide; always lets go of the keyboard.
function GuidePage:HideCopyText()
    self.copyToken = nil                                  -- cancels a pending re-select
    local box = self.copyBox
    if box then
        box:ClearFocus()
        box:HighlightText(0, 0)
        self.copyHint:Hide()
        self.copyScroll:Hide()
    end
    local was = self.copyMode
    self.copyMode = nil
    if self.scroll then self.scroll:Show() end
    if self.copyText then self.copyText:SetLinkText(L.G_COPY_TEXT or "Copy text") end
    return was
end

-- ---------------------------------------------------------------------------
-- Header

local function SetLine(set)
    if not set then return "" end
    local classes = ns.SetList and ns.SetList.ClassText and ns.SetList.ClassText(set)
    local parts = { set.name, classes or L.ALL_CLASSES }
    if set.faction then parts[#parts + 1] = ns.Data.FactionName(set.faction) end
    return table.concat(parts, " - ")
end

-- Big font for the item name; the normal one if it doesn't fit (like the set title).
local function FitName(fs)
    local text = fs:GetText()
    Theme.Font(fs, "header")
    fs:SetText(text)
    local w = fs:GetWidth() or 0
    if w > 0 and (fs:GetStringWidth() or 0) > w then
        Theme.Font(fs, "normal")
        fs:SetText(text)
    end
end

local function OnItemLoaded()
    if GuidePage:IsOpen() then GuidePage:FillHeader(); GuidePage:Render() end
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
    if p.later and not ns.Owned:IsHave(p) then
        self.state:SetText(ns.Data.FlagText("FLAG_LATER_SHORT"))
        self.state:SetTextColor(Theme.colors.later:GetRGB())
    else
        self.state:SetText(L["G_STATE_" .. state] or L["STATE_" .. state])
        self.state:SetTextColor(W.StateColor(state):GetRGB())
    end

    if W.FillItem(self, itemID, OnItemLoaded) then FitName(self.name) else Theme.Font(self.name, "header") end

    -- Show on model: like the row's check box (neck, rings, trinkets can't show; nor a
    -- piece not out yet in a released set: the model only wears set.pieces).
    local check = self.modelCheck
    if W.ShowsOnModel(p) and not (p.later and self.set and not self.set.unreleased) then
        check:Enable()
        check:SetChecked(not ns.Preview:IsHidden(itemID))
        self.modelLabel:SetTextColor(Theme.colors.text:GetRGB())
    else
        check:SetChecked(false)
        check:Disable()
        self.modelLabel:SetTextColor(Theme.colors.none:GetRGB())
    end

    -- Counts over every listed piece, the ones not out yet included (set.shown).
    local n, total = 0, 0
    if self.set then
        local list = self.set.shown or self.set.pieces
        total = #list
        for i, sp in ipairs(list) do if sp == p then n = i end end
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
    self:HideCopyText()
    local newPiece = piece ~= self.piece
    -- Open fold-outs are kept while you stay in the same set.
    if set ~= self.set then self.openFolds = {} end
    self.piece, self.set = piece, set
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

-- Previous/next piece of the set (wraps at the ends). needOnly (Shift-click): the
-- nearest piece in that direction you still need; if there is none, the plain step.
-- Steps through set.shown (pieces not out yet included); "next needed" skips those.
function GuidePage:Step(delta, needOnly)
    local set, p = self.set, self.piece
    local list = set and (set.shown or set.pieces)
    if not (list and p and #list > 0) then return end
    local count = #list
    local idx = 1
    for i, sp in ipairs(list) do if sp == p then idx = i end end
    local target = (idx - 1 + delta) % count + 1
    if needOnly then
        for s = 1, count - 1 do
            local i = (idx - 1 + delta * s) % count + 1
            local sp = list[i]
            if not sp.later and not ns.Owned:IsHave(sp) then target = i; break end
        end
    end
    self:Open(list[target], set)
end

-- Back to the piece list (button, Esc, right-click).
function GuidePage:Back()
    self:HideCopyText()
    if self.page and self.page:IsShown() then self.page:Hide() end
end

-- The page was hidden: by Back, by Esc (CloseSpecialWindows) or with the window.
-- Always ends with the page's own shown flag off, so a later Esc isn't spent on it,
-- and with the copy box's keyboard focus let go.
function GuidePage:OnHidden()
    if self.hiding then return end
    self.hiding = true
    self:HideCopyText()
    if self.page:IsShown() then self.page:Hide() end
    self.hiding = nil
    SwapSpecial(PAGE_NAME, WINDOW_NAME)
    self.renderToken = nil
    if ns.PieceList and ns.PieceList.OnGuideClosed then ns.PieceList:OnGuideClosed() end
end

-- Owned state changed while open: the header only.
function GuidePage:Refresh()
    if self:IsOpen() and self.piece then self:FillHeader() end
end
