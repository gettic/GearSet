-- Gear Set: middle panel - your character wearing the chosen set.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local Preview = {}
ns.Preview = Preview

Preview.hidden = {}     -- [itemID] = true for pieces taken off by clicking them

local MAX_ZOOM = 0.9

function Preview:Build(parent)
    local bg = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    Theme.SetModelBackground(bg)
    self.bg = bg

    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetPoint("TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", -4, 40)
    model:SetAutoDress(true)
    model:SetUnit("player")
    self.model = model
    self.zoom = 0
    self.facing = 0

    -- Drag to turn, mouse wheel to zoom.
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:SetScript("OnMouseDown", function(m, button)
        if button == "LeftButton" then m.dragX = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(m) m.dragX = nil end)
    model:SetScript("OnUpdate", function(m)
        if not m.dragX then return end
        local x = GetCursorPosition()
        Preview.facing = Preview.facing + (x - m.dragX) * 0.01
        m.dragX = x
        m:SetFacing(Preview.facing)
    end)
    model:SetScript("OnMouseWheel", function(m, delta)
        Preview.zoom = math.max(0, math.min(MAX_ZOOM, Preview.zoom + delta * 0.1))
        m:SetPortraitZoom(Preview.zoom)
    end)
    model:SetScript("OnModelLoaded", function() Preview:Apply() end)

    -- Bottom bar: Reset button and "Only the set" check box.
    local reset = Theme.CreateFrame("Button", nil, parent, "button")
    reset:SetSize(90, 22)
    reset:SetPoint("BOTTOMLEFT", 10, 10)
    reset:SetText(L.RESET)
    reset:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Preview:Reset()
    end)

    local check = Theme.CreateFrame("CheckButton", nil, parent, "check")
    check:SetSize(26, 26)
    check:SetPoint("BOTTOMRIGHT", -110, 8)
    local text = check.Text or check.text
    if not text then
        text = check:CreateFontString(nil, "OVERLAY")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    end
    Theme.Font(text, "small")
    text:SetText(L.ONLY_SET)
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
end

-- Dress the model: your gear (or nothing), then each shown piece of the set.
function Preview:Apply()
    local m = self.model
    if not m then return end
    if ns.db.onlySet then m:Undress() else m:Dress() end
    local set = self.set
    if not set then return end
    for _, p in ipairs(set.pieces) do
        if not self.hidden[p.itemID] then
            m:TryOn(p.sourceID or ("item:" .. p.itemID))
        end
    end
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

-- Click on a piece in the right list: take it off / put it back on.
function Preview:TogglePiece(itemID)
    self.hidden[itemID] = not self.hidden[itemID] or nil
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
