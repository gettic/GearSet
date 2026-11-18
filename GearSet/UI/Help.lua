-- Gear Set: first-time help. An overlay over the window's three panels (dimmed) with
-- four notes in Blizzard's help-tip style: 1 sets, 2 the look, 3 pieces, 4 settings
-- (3 and 4 side by side; 4 with a help-plate arrow and a short line up to the gear button).
-- The dim covers the three panels and the bottom bar. "Got it", a click anywhere or Esc closes it.
-- Esc closes only the help: its name sits on top of the window's UISpecialFrames slot
-- (W.PushEsc). Shown once (db.help.seen), also for people who used older versions.
-- Plain Show/Hide of our own frames only, so it works the same in combat.
local _, ns = ...
local Theme, L, W = ns.Theme, ns.L, ns.Widgets

local Help = {}
ns.Help = Help

local FRAME_NAME = "GearSetHelpFrame"
local NOTE_W, NOTE_PAD = 236, 10
local NOTE_TOP = -40     -- notes' top, under each inset's top edge
local RIGHT_NOTE_W, RIGHT_GAP = 210, 10   -- notes 3 and 4 side by side in the right inset
local DIM_BOTTOM = 4     -- the dim reaches the window's bottom inner edge (Reset, Only the set)
local LINE_H = 30        -- gold line gear -> arrow / note before the first layout

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

local function MakeNote(parent, head, body, width)
    local note, tmpl = Theme.CreateFrame("Frame", nil, parent, "helpNote")
    note:SetWidth(width or NOTE_W)
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

-- Up arrow on note 4 pointing at the gear: GlowBoxArrowTemplate (Blizzard's help-plate
-- arrow; its down art turned up with Theme.art.helpArrow's coords), else the same art by
-- file, else nil (the gold line alone, as before).
local function MakeArrow(parent)
    local a = Theme.art.helpArrow
    if type(a) ~= "table" then return nil end
    local f, tmpl = Theme.CreateFrame("Frame", nil, parent, "helpArrow")
    if not f then return nil end
    f:SetSize(a.w or 53, a.h or 21)
    f:EnableMouse(false)
    local arrow, glow = tmpl and f.Arrow, tmpl and f.Glow
    if not (arrow and arrow.SetTexCoord) then
        arrow = f:CreateTexture(nil, "ARTWORK")
        if not Theme.TryTexture(arrow, a.file) then f:Hide(); return nil end
        arrow:SetSize(a.w or 53, a.h or 21)
        arrow:SetPoint("TOPLEFT")
        glow = f:CreateTexture(nil, "BORDER")
        if Theme.TryTexture(glow, a.file) then
            glow:SetSize(a.glowW or 65, a.glowH or 28)
            glow:SetBlendMode("ADD")
            glow:SetAlpha(a.glowAlpha or 0.5)
        else
            glow:Hide()
            glow = nil
        end
    end
    if a.up then arrow:SetTexCoord(unpack(a.up)) end
    if glow and glow.SetTexCoord then
        if a.glowUp then glow:SetTexCoord(unpack(a.glowUp)) end
        glow:ClearAllPoints()
        glow:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)   -- glow spreads above the up arrow
    end
    f.gsArrow = arrow
    return f
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
    -- down to the window's bottom inner edge: the bottom bar (Reset, Only the set) dims too
    f:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, DIM_BOTTOM)
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
    notes[1]:SetPoint("TOP", UI.left, "TOP", 0, NOTE_TOP)
    notes[2] = MakeNote(f, T("HELP_MODEL_H", "2. The look"),
        T("HELP_MODEL", "Drag to turn, wheel to zoom. Untick a piece to hide it on the model."))
    notes[2]:SetPoint("TOP", UI.mid, "TOP", 0, NOTE_TOP)
    -- Notes 3 and 4 side by side at the top of the right inset; 4 sits at the right, under
    -- the gear button, with an arrow (and a short gold line) up to it.
    notes[4] = MakeNote(f, T("HELP_SETTINGS_H", "4. Settings"),
        T("HELP_SETTINGS", "The gear button: minimap button, hidden sets, Report a problem. Reopen this help with the i button or /gs help."),
        RIGHT_NOTE_W)
    notes[4]:SetPoint("TOPRIGHT", UI.right, "TOPRIGHT", -8, NOTE_TOP)
    notes[3] = MakeNote(f, T("HELP_PIECES_H", "3. Pieces"),
        T("HELP_PIECES", "What you have and what you still need. Click a piece to see how to get it, step by step."),
        RIGHT_NOTE_W)
    notes[3]:SetPoint("TOPRIGHT", notes[4], "TOPLEFT", -RIGHT_GAP, 0)
    local gear = UI.gear
    if gear then
        -- The arrow and line reach toward the title bar, whose art sits above the overlay:
        -- draw them on a mouse-less holder at the gear's level (UI.TopLevelOf).
        local holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f)
        holder:SetFrameLevel(UI.TopLevelOf and UI.TopLevelOf(win) or f:GetFrameLevel() + 1)
        holder:EnableMouse(false)
        self.lineHolder = holder
        self.arrow = MakeArrow(holder)
        if self.arrow then self.arrow:SetPoint("BOTTOM", notes[4], "TOP", 0, 2) end
        local line = holder:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(Theme.colors.helpLine:GetRGB())
        line:SetWidth(Theme.art.helpLineWidth or 2)
        line:SetPoint("TOP", gear, "BOTTOM", 0, -2)
        line:SetHeight(LINE_H)
        self.line = line
    end
    self.notes = notes

    local ok = W.PanelButton(f, T("HELP_GOT_IT", "Got it"), nil, function() Help:Hide() end)
    ok:SetPoint("BOTTOM", f, "BOTTOM", 0, 36)   -- above the (dimmed) bottom bar
    self.okButton = ok

    -- Hidden by Esc (CloseSpecialWindows), "Got it", a click, or with the window.
    f:SetScript("OnHide", function() Help:OnHidden() end)
    return true
end

function Help:Layout()
    if not self.notes then return end
    for _, note in ipairs(self.notes) do FitNote(note) end
    self:PlaceArrow()
end

-- Arrow right under the gear's centre on note 4's top edge; the gold line fills the gap
-- from the gear down to the arrow (or to the note without an arrow); hidden when tiny.
function Help:PlaceArrow()
    local UI = ns.UI
    local gear, note, line, arrow = UI and UI.gear, self.notes and self.notes[4], self.line, self.arrow
    if not (gear and note and line) then return end
    local gx, gb = gear:GetCenter(), gear:GetBottom()
    local nx, nt = note:GetCenter(), note:GetTop()
    local target = nt
    if arrow then
        arrow:ClearAllPoints()
        arrow:SetPoint("BOTTOM", note, "TOP", (gx and nx) and (gx - nx) or 0, 2)
        target = nt and (nt + 2 + (arrow:GetHeight() or 0))
    end
    local h = (gb and target) and (gb - 2 - target) or LINE_H
    line:SetHeight(math.max(1, h))
    line:SetShown(h >= 4)
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
