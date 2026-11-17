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
    PIECE_TIP = "Click for a guide on how to get this piece.",
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
    STATE_equipped = "Equipped",
    STATE_bags = "In bags",
    STATE_bank = "In bank",
    STATE_look = "Appearance",
    STATE_need = "Need",
    ALL_CLASSES = "All classes",
    UNKNOWN_SET = "Set %d",
    ANY_CAN_WEAR = "(any class can wear it)",
    -- Removed sets
    SHOW_REMOVED = "Show removed sets",
    REMOVED_TIP = "Removed in patch 1.11. It can't be bought any more.",
    -- Sort menu
    SORT = "Sort",
    SORT_OWNED = "Most owned first",
    SORT_CLOSEST = "Closest to finishing",
    SORT_NAME = "Name",
    -- Content filter (set kinds)
    CONTENT = "Content",
    KIND_D = "Dungeon",
    KIND_R = "Raid",
    KIND_P = "PvP",
    KIND_C = "Crafted",
    KIND_W = "World",
    KIND_F = "WoW Forever",
    MY_FACTION = "Only my faction",
    ALLIANCE = "Alliance",           -- fallbacks; the game's FACTION_ALLIANCE / FACTION_HORDE come first
    HORDE = "Horde",
    -- Filter menu: "Sort: Name", "Class: All" (label, current choice)
    MENU_CHOICE = "%s: %s",
    -- Set bonuses (right panel header)
    BONUSES = "Set bonuses",
    BONUSES_N = "Set bonuses (%d/%d)",       -- bonuses in effect from worn pieces / all
    BONUS_TITLE = "%s (%d/%d)",              -- set name (pieces worn / pieces in the set)
    BONUS_WEARING = "Only pieces you wear count: you wear %d of %d.",
    BONUS_LINE = "(%d) Set: %s",
    BONUS_ACTIVE = "Set: %s",
    BONUS_NONE = "No set bonus.",
    -- One command per line (HandleSlash prints each line on its own).
    HELP = "/gs - open or close the window\n/gs reset - move the window back to the middle\n/gs minimap - show or hide the minimap button\n/gs check - show the data version and test the set list (for bug reports)\n/gs probe - test what this game client supports (for bug reports)",
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
    -- Guide page (one piece). Row labels, then headings and lines.
    G_BACK = "Back",                 -- fallback; the game's BACK comes first
    G_BACK_TIP = "Back to the piece list (or press Esc, or right-click the page).",
    G_PIECE_N = "Piece %d of %d",
    G_PREV = "Previous piece",
    G_NEXT = "Next piece",
    G_STATE_equipped = "You have it: equipped",
    G_STATE_bags = "You have it: in your bags",
    G_STATE_bank = "You have it: in your bank",
    G_STATE_look = "You have its appearance",
    G_STATE_need = "You need this piece",
    G_WIKI_TIP = "Shows a Warcraft Wiki search link for this piece.",
    WIKI_POPUP = "Press Ctrl+C to copy the link, then paste it into your browser.",
    G_HOW = "How to get it",
    G_BEFORE = "Before you go",
    G_NEED_TEXT = "To get in you need the %s.",
    G_OTHER_VERSION = "Show the %s version",
    G_RECIPE = "Recipe",
    G_NOT_CRAFTER = "Can't make it yourself?",
    G_BOE_TIP = "It can be traded: buy it on the Auction House, or ask a crafter to make it with your materials.",
    G_TRAINER = "Taught by a trainer.",
    G_NOT_KNOWN = "not known",
    G_HERE = "(this piece's quest)",
    G_INSTANCE = "Instance",
    G_PLACE = "Place",
    G_WHERE = "Where",
    G_CHANCE = "Drop chance",
    G_LEVEL = "Level",
    G_MIN = "start at %s",
    G_GIVER = "Quest giver",
    G_BRING = "You bring",
    G_GOLD = "%s gold",
    G_NEEDS = "Needs",
    G_RANK = "PvP rank %s: %s",
    G_RANK_N = "PvP rank %s",
    G_COST = "Cost",
    G_ALSO = "Reward",
    G_SKILL = "Skill",
    G_SKILL_ORANGE = "orange",
    G_SKILL_YELLOW = "yellow",
    G_SKILL_GREEN = "green",
    G_SKILL_GREY = "grey",
    G_MATS = "Materials",
    G_TOOLS = "Tools",
    G_QUEST = "Quest",
    G_FROM = "Sold by",
    G_DROP = "Dropped by",
    G_NOTE = "Note",
    G_SIZE = "%s players",
    G_LEVEL_N = "level %s",
    -- Guide page: copy view, show on model, step hint, new data rows
    G_COPY_TEXT = "Copy text",
    G_COPY_TIP = "Shows this guide as text you can select and copy.",
    G_COPY_DONE = "Done",
    G_COPY_HINT = "Text is selected - press Ctrl+C to copy. Esc or Done goes back.",
    G_SHOW_MODEL = "Show on model",
    G_NEED_STEP = "Shift-click: the next piece you still need.",
    G_DROPS_FROM = "Drops from: %s",
    G_SPEC_TRAINER = "(trainer: %s)",
    G_TAUGHT_BY = "Taught by",
    G_AMOUNT_UNKNOWN = "%s (amount not known)",
    G_KIND_raid = "raid",
    G_KIND_dungeon = "dungeon",
    G_KIND_zone = "zone",
    G_KIND_city = "city",
    G_KIND_bg = "battleground",
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
    DATA_VERSION = "Data version %s, last checked %s (WoW Forever %s).",
    DATA_SOURCES = "Data sources: %s.",
    DATA_SOURCES_LIST = "warcraft.wiki.gg (CC BY-SA) and checks in the WoW Forever game",
    DATA_UNKNOWN = "unknown",
    DATA_FLAGS = "Checked on WoW Forever: %d of %d sets, %d sets not out yet; %d of %d sources checked; %d pieces not out yet.",
    DATA_BAD_FLAGS = "%d source flags don't match their sources (data error).",
    -- Forever flags (UI files fall back to the same English text if a key is missing)
    FLAG_CLASSIC = "Not confirmed on WoW Forever yet (classic data).",
    FLAG_CHECKED = "Checked on WoW Forever.",
    FLAG_LATER = "Not yet released on WoW Forever.",
    FLAG_LATER_SHORT = "Not out yet",
    FLAG_LATER_COUNT = "%d more not out yet",
    -- /gs probe (Probe.lua)
    PROBE_HEAD = "Probe, Gear Set %s",
    PROBE_COPY = "The probe text is in the copy box: press Ctrl+C and paste it into your bug report.",
    PROBE_POPUP = "Press Ctrl+C to copy the probe results, then paste them into your bug report.",
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
        showRemoved = false,     -- sets removed in patch 1.11 stay hidden
        kind = "",               -- content: "" = all, else "d"/"r"/"p"/"c"/"w"/"f"
        myFaction = true,        -- hide the other faction's PvP / Arathi Basin sets
    },
    sort = "owned",              -- set list order: "owned", "closest", "name"
    search = "",
    lastSet = nil,
    onlySet = false,
    minimap = {
        angle = 200,             -- degrees around the minimap, 0 = right, 90 = top
        hide = false,
    },
}

-- Filter defaults, read by the set list's "Reset filters" (one place for both).
ns.FILTER_DEFAULTS = defaults.filters

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

-- Content filter values (set kinds), in menu order; "" = all.
ns.SET_KINDS = { "d", "r", "p", "c", "w", "f" }
local SORT_MODES = { owned = true, closest = true, name = true }
local ANCHORS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function Finite(n)
    n = tonumber(n)
    return n ~= nil and n == n and n ~= math.huge and n ~= -math.huge
end

local function WholeIn(n, lo, hi)
    return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
end

-- Saved window point { point, relPoint, x, y } that SetPoint can take.
function ns.ValidPoint(p)
    if type(p) ~= "table" or not ANCHORS[p[1]] then return false end
    if p[2] ~= nil and not ANCHORS[p[2]] then return false end
    if p[3] ~= nil and not Finite(p[3]) then return false end
    if p[4] ~= nil and not Finite(p[4]) then return false end
    return true
end

-- Values of the right type but unknown (hand-edited or broken SavedVariables) go back
-- to their defaults one by one, so the list never comes up empty with no menu choice ticked.
local function ValidateDB(db)
    if db.point ~= nil and not ns.ValidPoint(db.point) then db.point = nil end
    local f, d = db.filters, defaults.filters
    if not WholeIn(f.class, 0, 99) then
        f.class = d.class
    elseif f.class ~= 0 and C_CreatureInfo and C_CreatureInfo.GetClassInfo
        and not C_CreatureInfo.GetClassInfo(f.class) then
        f.class = d.class
    end
    if not WholeIn(f.armor, 0, 4) then f.armor = d.armor end
    local kindOK = f.kind == ""
    for _, k in ipairs(ns.SET_KINDS) do
        if f.kind == k then kindOK = true end
    end
    if not kindOK then f.kind = d.kind end
    -- A class picked in the Class menu and "Only my class" can't both apply (empty list
    -- for any other class); the picked class wins, like in the menu.
    if f.class ~= 0 and f.usable then f.usable = false end
    if not SORT_MODES[db.sort] then db.sort = defaults.sort end
    if not Finite(db.minimap.angle) then db.minimap.angle = defaults.minimap.angle end
end

function ns.InitDB()
    if type(GearSetDB) ~= "table" then GearSetDB = {} end
    ApplyDefaults(GearSetDB, defaults)
    ValidateDB(GearSetDB)
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
-- Kinds: "wiki" (wiki search link) and "name" (item name, "Wiki link" swaps in the wiki search link).
local COPY_MAX = 4000                   -- room for the /gs probe text (names and links are short)
ns.COPY_MAX = COPY_MAX
-- Newer dialog code has GetEditBox()/GetOwningDialog(); older uses .editBox and the parent.
local function CopyBox(self)
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
    local box = CopyBox(dialog)
    if not box then return end
    if box.SetMaxLetters then box:SetMaxLetters(COPY_MAX) end
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
        maxLetters = COPY_MAX,
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

local COPY_DIALOG = { name = "GEARSET_COPYNAME", wiki = "GEARSET_WIKI", probe = "GEARSET_PROBE" }

StaticPopupDialogs.GEARSET_WIKI = CopyDialog(ns.L.WIKI_POPUP)
StaticPopupDialogs.GEARSET_PROBE = CopyDialog(ns.L.PROBE_POPUP)   -- /gs probe results

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

-- ns.ShowCopyBox(kind, text, alt): kind "name" or "wiki"; alt = the "Wiki link" text for "name".
function ns.ShowCopyBox(kind, text, alt)
    if not text or text == "" then return end
    local which = COPY_DIALOG[kind] or COPY_DIALOG.wiki
    for _, other in pairs(COPY_DIALOG) do
        if other ~= which then StaticPopup_Hide(other) end
    end
    StaticPopup_Hide(which)              -- reopen fresh so the box shows the new text
    local dialog = StaticPopup_Show(which, nil, nil, text)
    if dialog then dialog.gsAlt = alt end
    return dialog
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
        if ns.Probe then ns.Probe:PrintDataInfo() end
        ns.Data:CheckClassic()
    elseif msg == "probe" then
        if ns.Probe then ns.Probe:Run() end
    else
        for line in ns.L.HELP:gmatch("[^\n]+") do ns.Print(line) end
    end
end

SLASH_GEARSET1 = "/gearset"
SLASH_GEARSET2 = "/gs"
SlashCmdList.GEARSET = HandleSlash
