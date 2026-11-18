-- Gear Set: first-time help. An overlay over the window's three panels (dimmed) with
-- four notes in Blizzard's help-tip style: 1 sets, 2 the look, 3 pieces, 4 settings
-- (with a line up to the gear button). "Got it", a click anywhere or Esc closes it.
-- Esc closes only the help: its name sits on top of the window's UISpecialFrames slot
-- (W.PushEsc). Shown once (db.help.seen), also for people who used older versions.
-- Plain Show/Hide of our own frames only, so it works the same in combat.
local _, ns = ...
local Theme, L, W = ns.Theme, ns.L, ns.Widgets

local Help = {}
ns.Help = Help

local FRAME_NAME = "GearSetHelpFrame"
local NOTE_W, NOTE_PAD = 236, 10
local NOTE4_DROP = 210   -- how far below the gear button note 4 starts

local function T(key, fallback)
    local v = L and L[key]
    if v == nil then return fallback end
    return v
end

local function HelpTable()
    local db = ns.db
    if not db then return nil end
    if type(db.help) ~= "table" then db.help = { seen = false } end
    return db.help
end

-- Let go of keyboard focus held by one of our edit boxes (search, copy view), so the
-- first Esc goes to the help.
local function ClearOurFocus(window)
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    local p, n = focus, 0
    while p and n < 30 do
        if p == window then
            if focus.ClearFocus then focus:ClearFocus() end
            return
        end
        p = p.GetParent and p:GetParent()
        n = n + 1
    end
end

local function MakeNote(parent, head, body)
    local note, tmpl = Theme.CreateFrame("Frame", nil, parent, "helpNote")
    note:SetWidth(NOTE_W)
    if not tmpl then
        local bg = note:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(Theme.colors.helpNoteBg:GetRGBA())
    end
    -- Templates may set their own mouse handling; the overlay takes the clicks.
    note:EnableMouse(false)
    note.head = note:CreateFontString(nil, "OVERLAY", nil, 7)
    Theme.Font(note.head, "normal")
    note.head:SetTextColor(Theme.colors.helpHead:GetRGB())
    note.head:SetJustifyH("LEFT")
    note.head:SetPoint("TOPLEFT", NOTE_PAD, -NOTE_PAD)
    note.head:SetPoint("TOPRIGHT", -NOTE_PAD, -NOTE_PAD)
    note.head:SetText(head)
    note.body = note:CreateFontString(nil, "OVERLAY", nil, 7)
    Theme.Font(note.body, "small")
    note.body:SetTextColor(Theme.colors.helpText:GetRGB())
    note.body:SetJustifyH("LEFT")
    note.body:SetJustifyV("TOP")
    if note.body.SetWordWrap then note.body:SetWordWrap(true) end
    note.body:SetPoint("TOPLEFT", note.head, "BOTTOMLEFT", 0, -4)
    note.body:SetPoint("TOPRIGHT", note.head, "BOTTOMRIGHT", 0, -4)
    note.body:SetText(body)
    return note
end

-- Height from the measured text (fonts can measure short before the first draw, so
-- this runs on show and again a frame later).
local function FitNote(note)
    local h = (note.head:GetStringHeight() or 12) + 4 + (note.body:GetStringHeight() or 12)
    note:SetHeight(math.floor(h + NOTE_PAD * 2 + 0.5))
end

function Help:Build()
    if self.frame then return true end
    local UI = ns.UI
    if not (UI and UI.Build) then return false end
    UI:Build()
    local win = UI.frame
    if not (win and UI.left and UI.mid and UI.right) then return false end

    local f = CreateFrame("Frame", FRAME_NAME, win)
    self.frame = f
    f:SetPoint("TOPLEFT", UI.left, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", UI.right, "BOTTOMRIGHT", 0, 0)
    f:SetFrameLevel(math.min(win:GetFrameLevel() + 200, 9000))
    f:EnableMouse(true)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", function() end)   -- no scrolling the lists underneath
    f:SetScript("OnMouseUp", function() Help:Hide() end)
    f:Hide()

    local dim = f:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(Theme.colors.helpDim:GetRGBA())

    local notes = {}
    notes[1] = MakeNote(f, T("HELP_SETS_H", "1. Sets"),
        T("HELP_SETS", "Pick a set here. The menu filters and sorts; right-click a set to hide it."))
    notes[1]:SetPoint("TOP", UI.left, "TOP", 0, -40)
    notes[2] = MakeNote(f, T("HELP_MODEL_H", "2. The look"),
        T("HELP_MODEL", "Drag to turn, wheel to zoom. Untick a piece to hide it on the model."))
    notes[2]:SetPoint("TOP", UI.mid, "TOP", 0, -40)
    notes[3] = MakeNote(f, T("HELP_PIECES_H", "3. Pieces"),
        T("HELP_PIECES", "What you have and what you still need. Click a piece to see how to get it, step by step."))
    notes[3]:SetPoint("TOPLEFT", UI.right, "TOPLEFT", 14, -40)
    notes[4] = MakeNote(f, T("HELP_SETTINGS_H", "4. Settings"),
        T("HELP_SETTINGS", "The gear button: minimap button, hidden sets, Report a problem. Reopen this help with ? or /gs help."))
    local gear = UI.gear
    if gear then
        -- Note 4 hangs below the gear button with a thin gold line up to it.
        notes[4]:SetPoint("TOPRIGHT", gear, "BOTTOM", 26, -NOTE4_DROP)
        -- The line reaches into the title bar, whose art sits above the overlay: draw it
        -- on a mouse-less holder at the gear's level (UI.TopLevelOf).
        local holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f)
        holder:SetFrameLevel(UI.TopLevelOf and UI.TopLevelOf(win) or f:GetFrameLevel() + 1)
        holder:EnableMouse(false)
        self.lineHolder = holder
        local line = holder:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(Theme.colors.helpLine:GetRGB())
        line:SetWidth(Theme.art.helpLineWidth or 2)
        line:SetPoint("TOP", gear, "BOTTOM", 0, -2)
        line:SetPoint("BOTTOM", gear, "BOTTOM", 0, -NOTE4_DROP)
        self.line = line
    else
        notes[4]:SetPoint("BOTTOMRIGHT", UI.right, "BOTTOMRIGHT", -14, 60)
    end
    self.notes = notes

    local ok = W.PanelButton(f, T("HELP_GOT_IT", "Got it"), nil, function() Help:Hide() end)
    ok:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    self.okButton = ok

    -- Hidden by Esc (CloseSpecialWindows), "Got it", a click, or with the window.
    f:SetScript("OnHide", function() Help:OnHidden() end)
    return true
end

function Help:Layout()
    if not self.notes then return end
    for _, note in ipairs(self.notes) do FitNote(note) end
end

function Help:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

-- Opens the window if needed, then shows the help over it.
function Help:Show()
    local UI = ns.UI
    if not (UI and UI.Build) then return end
    UI:Build()
    local win = UI.frame
    if not win then return end
    if not win:IsShown() then
        self.opening = true   -- the window's OnShow calls MaybeShowFirstTime
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
        win:Show()
        self.opening = nil
    end
    if win.Raise then win:Raise() end
    if not self:Build() then return end
    if self.lineHolder and UI.TopLevelOf then self.lineHolder:SetFrameLevel(UI.TopLevelOf(win)) end
    ClearOurFocus(win)
    if not self.frame:IsShown() then
        self.frame:Show()
        W.PushEsc(FRAME_NAME)
    end
    self:Layout()
    local token = {}
    self.layoutToken = token
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if Help.layoutToken == token and Help:IsShown() then Help:Layout() end
        end)
    end
end

function Help:Hide()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()   -- OnHide -> OnHidden
    else
        self:OnHidden()
    end
end

-- Always ends with the overlay's own shown flag off (it may have been hidden only
-- through the window, which would leave a later Esc spent on it), its Esc name off
-- the stack, and help.seen set.
function Help:OnHidden()
    if self.hiding then return end
    self.hiding = true
    if self.frame and self.frame:IsShown() then self.frame:Hide() end
    self.hiding = nil
    self.layoutToken = nil
    W.PopEsc(FRAME_NAME)
    if self.quiet then return end   -- /gs selftest opened it: help.seen stays as it was
    local h = HelpTable()
    if h and not h.seen then
        h.seen = true
        if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
    end
end

-- Main window's OnShow: the help once (help.seen false = new, or an older version's user).
-- Help.quiet (set by /gs selftest while it runs): no first-time help, help.seen untouched.
function Help:MaybeShowFirstTime()
    if self.opening or self.quiet then return end
    local h = HelpTable()
    if h and not h.seen then self:Show() end
end
