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
    NO_SETS = "No sets match.",
    LOADING = "Loading...",
    RESET = "Reset",
    ONLY_SET = "Only the set",
    ONLY_SET_TIP = "Take off your own gear so only the set's pieces show.",
    PIECE_TIP = "Click to take this piece off or put it back on the preview.",
    STATE_equipped = "Equipped",
    STATE_bags = "In bags",
    STATE_bank = "In bank",
    STATE_look = "Look collected",
    STATE_need = "Need",
    ALL_CLASSES = "All classes",
    UNKNOWN_SET = "Set %d",
    HELP = "/gs - open or close the window. /gs reset - put the window back in the middle. /gs minimap - show or hide the minimap button. /gs check - check the built-in set list.",
    POS_RESET = "Window position reset.",
    MINIMAP_TIP_CLICK = "Click: open or close the window.",
    MINIMAP_TIP_DRAG = "Drag: move it around the minimap.",
    MINIMAP_SHOWN = "Minimap button shown.",
    MINIMAP_HIDDEN = "Minimap button hidden. Type /gs minimap to show it again.",
}

local defaults = {
    version = ns.DB_VERSION,
    point = nil,                 -- { point, relPoint, x, y }
    filters = {
        class = 0,               -- 0 = all, else classID
        armor = 0,               -- 0 = all, else armor subclass (1 cloth .. 4 plate)
        usable = false,
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
        ns.Print(ns.L.HELP)
    end
end

SLASH_GEARSET1 = "/gearset"
SLASH_GEARSET2 = "/gs"
SlashCmdList.GEARSET = HandleSlash
