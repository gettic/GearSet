-- Gear Set: core (namespace, saved settings, events, slash commands)
local ADDON, ns = ...

ns.ADDON = ADDON
ns.DB_VERSION = 1

-- All user-facing text in one place (ready for translations later).
ns.L = {
    TITLE = "Gear Set",
    SEARCH = "Search sets",
    FILTER = "Filter",
    CLASS = "Class",
    ARMOR = "Armor type",
    ALL = "All",
    USABLE = "Only my class",
    HIDE_COMPLETE = "Hide complete sets",
    RESET_FILTERS = "Reset filters",
    HAVE_COUNT = "Have %d / %d",
    NO_SET = "Pick a set on the left.",
    NO_SETS = "No sets match. Try other filters or words.",
    LOADING = "Loading...",
    RESET = "Reset view",
    RESET_TIP = "Turn the character back, zoom out and show every piece again.",
    ONLY_SET = "Only the set",
    ONLY_SET_TIP = "Hide your own gear so only the set shows.",
    PIECE_TIP = "Click to see where this piece comes from.",
    SHOW_PIECE_TIP = "Show this piece on the character.",
    NO_MODEL_TIP = "This piece doesn't show on the character.",
    -- Source lines (type words come from the game's TRANSMOG_SOURCE_n strings when it has them).
    SRC_BOSS = "Boss Drop",
    SRC_QUEST = "Quest",
    SRC_VENDOR = "Vendor",
    SRC_WORLD = "World Drop",
    SRC_PROFESSION = "Profession",
    SRC_DROP = "Drop",               -- z: trash or several bosses in one place
    SRC_UNKNOWN = "Source unknown",
    SRC_MORE = "+%d more",
    REPORT = "Report wrong source",
    REPORT_TIP = "Shows a link to tell us the right source.",
    REPORT_POPUP = "Press Ctrl+C to copy the link, then paste it into your browser.\nYou need a GitHub account to send the report.",
    STATE_equipped = "Equipped",
    STATE_bags = "In bags",
    STATE_bank = "In bank",
    STATE_look = "Appearance",
    STATE_need = "Need",
    ALL_CLASSES = "All classes",
    UNKNOWN_SET = "Set %d",
    -- One command per line (HandleSlash prints each line on its own).
    HELP = "/gs - open or close the window\n/gs reset - move the window back to the middle\n/gs minimap - show or hide the minimap button\n/gs check - test the set list (for bug reports)",
    POS_RESET = "Window moved back to the middle.",
    MINIMAP_TIP_CLICK = "Click: open or close the window.",
    MINIMAP_TIP_DRAG = "Drag: move this button.",
    MINIMAP_SHOWN = "Minimap button shown.",
    MINIMAP_HIDDEN = "Minimap button hidden. Type /gs minimap to show it again.",
    MINIMAP_TIP_HIDE = "Right-click: hide this button.",
    BIND_TOGGLE = "Open/close Gear Set",
    -- Piece list
    PIECE_TIP_MOD = "Shift-click: put the link in chat. Ctrl-click: try it on in the dressing room.",
    COPY = "Copy name",
    COPY_TIP = "Shows the name so you can copy it and look the piece up online.",
    COPY_POPUP = "Press Ctrl+C to copy the name, then search for it online.",
    WIKI_LINK = "Wiki link",
    APPEARANCE_ONLY = "Appearance only",
    APPEARANCE_NOTE = "A collected appearance counts as having the piece.",
    PREV_SET = "Previous set",
    NEXT_SET = "Next set",
    -- Empty set list (used with :format)
    EMPTY_SEARCH = "Search: \"%s\"",
    EMPTY_FILTERS = "Filters: %s",
    CLEAR_SEARCH = "Clear search",
    CLEAR_ALL = "Clear search and filters",
    -- /gs check
    CHECK_NO_LIST = "The set list is missing. Try reinstalling Gear Set.",
    CHECK_NO_SET = "Set %d: the game doesn't know this set.",
    CHECK_BAD_ENTRY = "Set %d: broken entry.",
    CHECK_NO_ITEM = "Set %d: item %d isn't in the game.",
    CHECK_WRONG_SET = "Set %d: the game puts item %d in set %s.",
    CHECK_NONE = "no set",
    CHECK_SLOW = "%d items didn't load. Try /gs check again.",
    CHECK_DONE = "Check done: %d sets, %d items, %d problems%s.",
    CHECK_FIRST_40 = " (first 40 shown)",
}

-- Key Bindings menu texts (Bindings.xml, loaded by the game from the addon folder).
BINDING_HEADER_GEARSET = ns.L.TITLE
BINDING_NAME_GEARSET_TOGGLE = ns.L.BIND_TOGGLE

-- Global entry point for the key binding (binding code runs outside the addon's namespace).
function GearSet_Toggle()
    if ns.UI and ns.UI.Toggle then ns.UI:Toggle() end
end

local defaults = {
    version = ns.DB_VERSION,
    point = nil,                 -- { point, relPoint, x, y }
    filters = {
        class = 0,               -- 0 = all, else classID
        armor = 0,               -- 0 = all, else armor subclass (1 cloth .. 4 plate)
        -- "Only my class": on for new installs. ApplyDefaults only fills missing keys,
        -- so an existing saved false stays false.
        usable = true,
        hideComplete = false,
    },
    search = "",
    lastSet = nil,
    onlySet = false,
    minimap = {
        angle = 200,             -- degrees around the minimap, 0 = right, 90 = top
        hide = false,
    },
}

-- Fill missing or wrong-typed keys from defaults; never removes the user's data.
local function ApplyDefaults(db, def)
    for k, v in pairs(def) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            ApplyDefaults(db[k], v)
        elseif db[k] == nil or (v ~= nil and type(db[k]) ~= type(v)) then
            db[k] = v
        end
    end
end

function ns.InitDB()
    if type(GearSetDB) ~= "table" then GearSetDB = {} end
    ApplyDefaults(GearSetDB, defaults)
    -- Future migrations go here (compare GearSetDB.version).
    GearSetDB.version = ns.DB_VERSION
    ns.db = GearSetDB
end

function ns.Print(msg)
    local c = NORMAL_FONT_COLOR
    local prefix = c and c:WrapTextInColorCode(ns.L.TITLE .. ":") or (ns.L.TITLE .. ":")
    print(prefix .. " " .. tostring(msg))
end

-- Register an event only if this client knows it (unknown events throw).
function ns.SafeRegister(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end

-- Copy box: Blizzard's own dialog with the text filled in and selected.
-- The text can't be changed (typing puts it back), so Ctrl+C always copies all of it.
-- Kinds: "report" (GitHub link) and "name" (item name, "Wiki link" swaps in the wiki search link).
local REPORT_MAX = 2000
-- Newer dialog code has GetEditBox()/GetOwningDialog(); older uses .editBox and the parent.
local function ReportBox(self)
    return (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox
end
local function BoxDialog(box)
    return (box.GetOwningDialog and box:GetOwningDialog()) or box:GetParent()
end
local function KeepLink(box, data)
    if data and box:GetText() ~= data then box:SetText(data) end
    box:HighlightText()
end

local function FillBox(dialog, text)
    local box = ReportBox(dialog)
    if not box then return end
    if box.SetMaxLetters then box:SetMaxLetters(REPORT_MAX) end
    box:SetText(text or "")
    box:SetCursorPosition(0)
    box:HighlightText()
    box:SetFocus()
end

local function CopyDialog(text)
    return {
        text = text,
        button1 = CLOSE or "Close",
        hasEditBox = true,
        editBoxWidth = 360,
        maxLetters = REPORT_MAX,
        OnShow = function(self, data) FillBox(self, data or self.data) end,
        EditBoxOnTextChanged = function(box, data)
            local d = BoxDialog(box)
            -- Read the dialog's current data first: "Wiki link" swaps it while open.
            KeepLink(box, (d and d.data) or data)
        end,
        EditBoxOnEnterPressed = function(box) local d = BoxDialog(box) if d then d:Hide() end end,
        EditBoxOnEscapePressed = function(box) local d = BoxDialog(box) if d then d:Hide() end end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local COPY_DIALOG = { report = "GEARSET_REPORT", name = "GEARSET_COPYNAME" }

StaticPopupDialogs.GEARSET_REPORT = CopyDialog(ns.L.REPORT_POPUP)

local nameDialog = CopyDialog(ns.L.COPY_POPUP)
nameDialog.button2 = ns.L.WIKI_LINK
nameDialog.noCancelOnEscape = true       -- Esc just closes; only the button swaps the text
-- Button 2 ("Wiki link"): put the wiki search link in the box; returning true keeps the dialog open.
local function SwapToAlt(self)
    local alt = self and self.gsAlt
    if alt then
        self.data = alt
        FillBox(self, alt)
    end
    return true
end
nameDialog.OnCancel = SwapToAlt          -- older dialog code
nameDialog.OnButton2 = SwapToAlt         -- newer code may call this one instead
StaticPopupDialogs.GEARSET_COPYNAME = nameDialog

-- ns.ShowCopyBox(kind, text, alt): kind "report" or "name"; alt = the "Wiki link" text for "name".
function ns.ShowCopyBox(kind, text, alt)
    if not text or text == "" then return end
    local which = COPY_DIALOG[kind] or COPY_DIALOG.report
    for _, other in pairs(COPY_DIALOG) do
        if other ~= which then StaticPopup_Hide(other) end
    end
    StaticPopup_Hide(which)              -- reopen fresh so the box shows the new text
    local dialog = StaticPopup_Show(which, nil, nil, text)
    if dialog then dialog.gsAlt = alt end
    return dialog
end

-- Old name, kept so nothing that still calls it breaks.
function ns.ShowReport(url)
    return ns.ShowCopyBox("report", url)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        ns.InitDB()
        if ns.Owned and ns.Owned.Init then ns.Owned:Init() end
        if ns.MinimapButton then ns.MinimapButton:Init() end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

local function HandleSlash(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "" then
        ns.UI:Toggle()
    elseif msg == "reset" then
        ns.db.point = nil
        ns.UI:ResetPosition()
        ns.Print(ns.L.POS_RESET)
    elseif msg == "minimap" then
        local shown = ns.MinimapButton:ToggleShown()
        ns.Print(shown and ns.L.MINIMAP_SHOWN or ns.L.MINIMAP_HIDDEN)
    elseif msg == "check" then
        ns.Data:CheckClassic()
    else
        for line in ns.L.HELP:gmatch("[^\n]+") do ns.Print(line) end
    end
end

SLASH_GEARSET1 = "/gearset"
SLASH_GEARSET2 = "/gs"
SlashCmdList.GEARSET = HandleSlash
