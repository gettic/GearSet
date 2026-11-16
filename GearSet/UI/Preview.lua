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
    model:SetScript("OnModelLoaded", function() Preview:OnModelLoaded() end)

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

-- Put each shown piece of the set on the model.
function Preview:TryOnPieces()
    local m, set = self.model, self.set
    if not (m and set) then return end
    for _, p in ipairs(set.pieces) do
        if not self.hidden[p.itemID] then
            m:TryOn(p.sourceID or ("item:" .. p.itemID))
        end
    end
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
