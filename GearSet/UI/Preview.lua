-- Gear Set: middle panel - your character wearing the chosen set.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local Preview = {}
ns.Preview = Preview

Preview.hidden = {}     -- [itemID] = true for pieces taken off by clicking them

local MAX_ZOOM = 0.9

-- 1.1 beta.2: slots that can be hidden on OUR model only (ToS W7: never ShowHelm / ShowCloak,
-- never the player's own settings). Inventory slot numbers: head 1, back 15, main/off/ranged 16-18.
Preview.SLOTS = { head = { 1 }, back = { 15 }, weapons = { 16, 17, 18 } }
Preview.SLOT_ORDER = { "head", "back", "weapons" }
local SLOT_ART = { head = "slotHead", back = "slotBack", weapons = "slotWeapon" }
local SLOT_TEXT = { head = "HEAD", back = "BACK", weapons = "WEAPONS" }

local function HideTable()
    local db = ns.db
    local p = type(db) == "table" and db.preview
    local h = type(p) == "table" and p.hide
    return type(h) == "table" and h or nil
end

function Preview.IsSlotHidden(key)
    local h = HideTable()
    return h ~= nil and h[key] == true
end

-- parent: the middle inset; bar: the window (its bottom bar holds Reset / "Only the set").
function Preview:Build(parent, bar)
    local bg = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    Theme.SetModelBackground(bg)
    self.bg = bg

    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetPoint("TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", -4, 4)   -- full inset: the controls sit in the window's bottom bar
    model:SetAutoDress(true)
    model:SetUnit("player")
    self.model = model
    self.zoom = 0
    self.facing = 0

    -- Drag to turn, mouse wheel to zoom.
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    -- The turning OnUpdate runs only while the left button is held (no per-frame call otherwise).
    local function DragTurn(m)
        if not m.dragX then return end
        local x = GetCursorPosition()
        Preview.facing = Preview.facing + (x - m.dragX) * 0.01
        m.dragX = x
        m:SetFacing(Preview.facing)
    end
    model:SetScript("OnMouseDown", function(m, button)
        if button == "LeftButton" then
            m.dragX = GetCursorPosition()
            m:SetScript("OnUpdate", DragTurn)
        end
    end)
    model:SetScript("OnMouseUp", function(m)
        m.dragX = nil
        m:SetScript("OnUpdate", nil)
    end)
    model:SetScript("OnMouseWheel", function(m, delta)
        Preview.zoom = math.max(0, math.min(MAX_ZOOM, Preview.zoom + delta * 0.1))
        m:SetPortraitZoom(Preview.zoom)
    end)
    model:SetScript("OnModelLoaded", function() Preview:OnModelLoaded() end)

    -- Window bottom bar (under this panel, like the dressing room): Reset button
    -- on the left, "Only the set" check box on the right, placed from its label.
    bar = bar or parent:GetParent() or parent
    local reset = Theme.CreateFrame("Button", nil, bar, "button")
    reset:SetSize(100, 22)
    reset:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, 0)
    reset:SetText(L.RESET)
    local fs = reset.GetFontString and reset:GetFontString()
    if fs and fs:GetStringWidth() + 20 > 100 then
        reset:SetWidth(math.ceil(fs:GetStringWidth()) + 20)
    end
    reset:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Preview:Reset()
    end)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.RESET, 1, 1, 1)
        local tip = L.RESET_TIP
        if tip then
            if Theme.AddHint then
                Theme.AddHint(GameTooltip, tip)
            else
                GameTooltip:AddLine(tip, nil, nil, nil, true)
            end
        end
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", GameTooltip_Hide)
    self.reset = reset

    local size = Theme.sizes and Theme.sizes.check or 24
    local check = Theme.CreateFrame("CheckButton", nil, bar, "check")
    check:SetSize(size, size)
    local text = check.Text or check.text
    if not text then
        text = check:CreateFontString(nil, "OVERLAY")
    end
    text:ClearAllPoints()
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    Theme.Font(text, "small")
    text:SetText(L.ONLY_SET)
    local labelW = math.ceil(text:GetStringWidth() or 0)
    if labelW <= 0 then labelW = 80 end
    -- Right edge of the label lines up with the panel's right edge (4 px in);
    -- vertically centred on the Reset button.
    check:SetPoint("RIGHT", parent, "BOTTOMRIGHT", -(labelW + 2 + 4), -11)
    check:SetHitRectInsets(0, -(labelW + 2), 0, 0)  -- the label is clickable too
    check:SetChecked(ns.db.onlySet)
    check:SetScript("OnClick", function(self)
        ns.db.onlySet = self:GetChecked() and true or false
        PlaySound(ns.db.onlySet and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        Preview:Apply()
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.ONLY_SET_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    self.check = check

    -- 1.1 beta.2: hide helm / cloak / weapons on this model (3 slot buttons right of Reset).
    self.slotButtons = {}
    local prev = reset
    for i, key in ipairs(Preview.SLOT_ORDER) do
        local art, sz = Theme.art[SLOT_ART[key]], Theme.sizes.slot
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(sz.button, sz.button)
        b:SetPoint("LEFT", prev, "RIGHT", i == 1 and sz.first or sz.gap, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("CENTER")
        b.icon:SetSize(sz.icon, sz.icon)
        if not Theme.TryTexture(b.icon, art.file) then
            b.icon:SetColorTexture(unpack(Theme.art.slotPlain.color))
            b.letter = b:CreateFontString(nil, "OVERLAY")
            Theme.Font(b.letter, "small")
            b.letter:SetPoint("CENTER")
            b.letter:SetText(art.letter)
        end
        -- frame like the item icons elsewhere (grey)
        b.border = b:CreateTexture(nil, "OVERLAY")
        b.border:SetAllPoints(b.icon)
        if Theme.TryTexture(b.border, Theme.art.iconBorder.file) then
            b.border:SetVertexColor(Theme.colors.slotFrame:GetRGB())
        else
            b.border:Hide()
        end
        -- red X while the slot is hidden ("x" text when the atlas is missing)
        local mark = Theme.art.slotOffMark
        if Theme.AtlasExists(mark.atlas) then
            b.off = b:CreateTexture(nil, "OVERLAY", nil, 2)
            b.off:SetAtlas(mark.atlas)
            b.off:SetSize(sz.mark, sz.mark)
        else
            b.off = b:CreateFontString(nil, "OVERLAY")
            Theme.Font(b.off, "small")
            b.off:SetTextColor(Theme.colors.slotOffMark:GetRGB())
            b.off:SetText(mark.text)
        end
        b.off:SetPoint("CENTER")
        b.off:Hide()
        local hl = Theme.art.slotHilight
        if hl and hl.file then b:SetHighlightTexture(hl.file, hl.blend or "ADD") end
        b.gsSlot = key
        b:SetScript("OnClick", function(btn)
            local hidden = Preview:ToggleSlot(btn.gsSlot)
            if hidden == nil then return end
            PlaySound(hidden and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            if GameTooltip:IsOwned(btn) then btn:GetScript("OnEnter")(btn) end
        end)
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            local hidden = Preview.IsSlotHidden(btn.gsSlot)
            local k = (hidden and "SLOT_SHOW_" or "SLOT_") .. SLOT_TEXT[btn.gsSlot]
            GameTooltip:SetText(L[k] or k, 1, 1, 1)
            GameTooltip:AddLine(L.SLOT_TIP_NOTE or "", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        self.slotButtons[i] = b
        prev = b
    end
    self:UpdateSlotButtons()
end

-- Flips one slot (saved for the account) and redraws; returns the new hidden state (nil = no DB).
function Preview:ToggleSlot(key)
    local h = HideTable()
    if not (h and Preview.SLOTS[key]) then return nil end
    h[key] = not h[key]
    self:UpdateSlotButtons()
    self:Apply()
    return h[key]
end

-- Hidden slots show their button greyed.
function Preview:UpdateSlotButtons()
    for _, b in ipairs(self.slotButtons or {}) do
        local hidden = Preview.IsSlotHidden(b.gsSlot)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(hidden) end
        if hidden then b.icon:SetVertexColor(Theme.colors.slotOff:GetRGBA()) else b.icon:SetVertexColor(1, 1, 1, 1) end
        if b.letter then b.letter:SetAlpha(hidden and 0.5 or 1) end
        if b.off then b.off:SetShown(hidden) end
    end
end

-- Takes the hidden slots off our model (after the set was tried on).
function Preview:ApplyHidden()
    local m = self.model
    if not (m and m.UndressSlot) then return end
    for _, key in ipairs(Preview.SLOT_ORDER) do
        if Preview.IsSlotHidden(key) then
            for _, slot in ipairs(Preview.SLOTS[key]) do pcall(m.UndressSlot, m, slot) end
        end
    end
end

-- Put each shown piece of the set on the model.
function Preview:TryOnPieces()
    local m, set = self.model, self.set
    if not (m and set) then return end
    for _, p in ipairs(set.pieces) do
        if not self.hidden[p.itemID] then
            m:TryOn(p.sourceID or ("item:" .. p.itemID))
        end
    end
    self:ApplyHidden()
end

-- Dress the model: your gear (or nothing), then each shown piece of the set.
-- Dress() reloads the model and may fire OnModelLoaded inside the call; the
-- flag stops that from coming back here (it used to recurse until C stack overflow).
function Preview:Apply()
    local m = self.model
    if not m then return end
    self.applying = true
    if ns.db.onlySet then m:Undress() else m:Dress() end
    self.applying = nil
    self:TryOnPieces()
end

-- The model finished (re)loading (after SetUnit or Dress, now or a frame later).
-- Never call Dress/SetUnit here: they reload the model and fire this again.
function Preview:OnModelLoaded()
    if self.applying then return end    -- inside our own Dress: Apply tries the pieces on next
    if ns.db.onlySet then
        self.applying = true
        self.model:Undress()
        self.applying = nil
    end
    self:TryOnPieces()
end

function Preview:ShowSet(set)
    if not self.model then return end
    if set ~= self.set then wipe(self.hidden) end
    self.set = set
    self.model:SetUnit("player")
    self.model:SetFacing(self.facing)
    self.model:SetPortraitZoom(self.zoom)
    self:Apply()
end

-- Check box on a piece in the right list: put it on (shown) or take it off the preview.
function Preview:SetPieceShown(itemID, shown)
    local hidden = not shown or nil
    if self.hidden[itemID] == hidden then return end
    self.hidden[itemID] = hidden
    self:Apply()
end

function Preview:IsHidden(itemID)
    return self.hidden[itemID] == true
end

function Preview:Reset()
    wipe(self.hidden)
    self.facing, self.zoom = 0, 0
    if self.model then
        self.model:SetFacing(0)
        self.model:SetPortraitZoom(0)
    end
    self:Apply()
    ns.PieceList:Refresh()
end
