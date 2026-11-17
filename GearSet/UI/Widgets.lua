-- Gear Set: small widgets and helpers shared by the piece list and the guide page,
-- so a theme swap or a fix touches one file. All looks come from ns.Theme.
-- API: plans\review-fixes\widgets.md (kept outside the addon).
local _, ns = ...
local Theme = ns.Theme

local W = {}
ns.Widgets = W

W.ICON_CROP = Theme.art.iconCrop

-- Slots the character model doesn't show (neck, rings, trinkets, unknown).
local NO_MODEL_SLOT = { [0] = true, [2] = true, [11] = true, [12] = true, [13] = true, [14] = true }

function W.ShowsOnModel(piece)
    return not NO_MODEL_SLOT[piece and piece.slot or 0]
end

function W.StateColor(state)
    if state == "need" then return Theme.colors.need end
    return Theme.stateColor[state] or Theme.colors.text
end

function W.SimpleTip(owner, text, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function ShowTip(owner, tip)
    if type(tip) == "function" then tip(owner)
    elseif tip then W.SimpleTip(owner, tip) end
end

-- Copy dialog (Core.lua, always loaded first).
function W.ShowCopy(kind, text, alt)
    ns.ShowCopyBox(kind, text, alt)
end

function W.ItemLink(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = get(itemID)
    return link
end

-- Shift-click: link into the open chat box; Ctrl-click: dressing room (Blizzard's
-- own handler). Only on the player's own click; nothing is ever sent to chat.
function W.HandleModifiedClick(itemID)
    if not (itemID and IsModifiedClick) then return false end
    if not (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP")) then return false end
    local link = W.ItemLink(itemID)
    if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    return true
end

-- Previous/next page-turn button. "<" / ">" text if the art is missing.
function W.ArrowButton(parent, dir, tip, onClick)
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
    b:SetScript("OnClick", function(self, button)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if onClick then onClick(self, button) end
    end)
    b:SetScript("OnEnter", function(self) ShowTip(self, tip) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- Text button. style "link": Blizzard hyperlink colours, white + underline on hover.
-- style "label": gold small text that turns white on hover (hover-only info, no click).
function W.LinkButton(parent, text, tip, onClick, style)
    local isLabel = style == "label"
    local c = Theme.colors
    local normal = isLabel and (c.guideLabel or c.partial) or c.link
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(14)
    local fs = b:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, "small")
    fs:SetPoint("LEFT")
    b.text = fs
    local underline = b:CreateTexture(nil, "OVERLAY")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -1)
    underline:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -1)
    underline:SetColorTexture(c.linkHover:GetRGB())
    underline:Hide()
    local function Color()
        if b.gsDim then fs:SetTextColor(c.none:GetRGB()) else fs:SetTextColor(normal:GetRGB()) end
    end
    function b:SetLinkText(t)
        fs:SetText(t or "")
        self:SetWidth((fs:GetStringWidth() or 0) + 4)
    end
    function b:SetDim(dim)
        self.gsDim = dim and true or nil
        Color()
    end
    b:SetLinkText(text)
    Color()
    b:SetScript("OnEnter", function(self)
        fs:SetTextColor(c.linkHover:GetRGB())
        if not isLabel then underline:Show() end
        ShowTip(self, tip)
    end)
    b:SetScript("OnLeave", function()
        Color()
        underline:Hide()
        GameTooltip_Hide()
    end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

function W.PanelButton(parent, text, tip, onClick)
    local b = Theme.CreateFrame("Button", nil, parent, "button")
    b:SetHeight(22)
    b:SetText(text)
    local fs = b.GetFontString and b:GetFontString()
    b:SetWidth(math.max(70, (fs and fs:GetStringWidth() or 60) + 24))
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) ShowTip(self, tip) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- Quality frame over an item icon (hidden until FillItem shows it).
function W.IconBorder(parent, icon)
    local border = parent:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(icon)
    local ok = Theme.TryTexture(border, Theme.art.iconBorder.file)
    border:Hide()
    return border, ok
end

-- Name in quality colour + quality frame (uncommon and better, like Blizzard's item
-- buttons). Not loaded yet: "Loading..." and ONE pending load per target and item.
local pending = setmetatable({}, { __mode = "k" })   -- target -> { [itemID] = true } being waited for

function W.FillItem(target, itemID, onLoaded)
    target.gsItem = itemID
    if target.border then target.border:Hide() end
    local item = Item:CreateFromItemID(itemID)
    if item:IsItemDataCached() then
        target.name:SetText(item:GetItemName())
        local q = item:GetItemQuality()
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then target.name:SetTextColor(c.r, c.g, c.b) else target.name:SetTextColor(1, 1, 1) end
        if c and target.border and target.hasBorder and q >= 2 then
            target.border:SetVertexColor(c.r, c.g, c.b)
            target.border:Show()
        end
        return true
    end
    target.name:SetText(ns.L.LOADING)
    target.name:SetTextColor(Theme.colors.loading:GetRGB())
    target.gsOnLoaded = onLoaded
    local waiting = pending[target]
    if not waiting then waiting = {}; pending[target] = waiting end
    if not waiting[itemID] then
        waiting[itemID] = true
        item:ContinueOnItemLoad(function()
            waiting[itemID] = nil
            if target.gsItem == itemID and target.gsOnLoaded then target.gsOnLoaded(target, itemID) end
        end)
    end
    return false
end
