-- Gear Set: settings page in Blizzard's own Settings panel (Esc > Options > AddOns).
-- Public Settings.* API only (checked: warcraft.wiki.gg "Settings API" and Blizzard's
-- Blizzard_Settings_Shared\Blizzard_Settings.lua / Blizzard_SettingControls.lua).
-- Every call is nil-checked and pcall'd: no Settings API -> no category, Open() = false.
-- Blizzard's panel is opened only out of combat (it is a UI panel; addons may not show
-- panels in combat): in combat one chat line, and it opens when combat ends.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local S = {}
ns.Settings = S

local function T(key, fallback)
    local v = L and L[key]
    if v == nil then return fallback end
    return v
end

local VAR = {
    minimap    = "GearSet_ShowMinimap",
    helpNext   = "GearSet_HelpNextTime",
    showHidden = "GearSet_ShowHiddenSets",
    tooltipLine  = "GearSet_TooltipLine",     -- beta.7 (Tooltip.lua / Integrations.lua)
    tooltipShift = "GearSet_TooltipShift",
    altClick     = "GearSet_AltClick",
}

local function DB() return ns.db end

local function HelpTable()
    local db = DB()
    if not db then return nil end
    if type(db.help) ~= "table" then db.help = { seen = false } end
    return db.help
end

local function HiddenCount()
    local D = ns.Data
    if D and D.HiddenCount then
        local ok, n = pcall(D.HiddenCount)
        if ok and type(n) == "number" then return n end
    end
    return 0
end

-- Getters / setters of the three check boxes (the saved data stays the only truth).
local VALUES = {
    minimap = {
        get = function() local db = DB(); return not (db and db.minimap and db.minimap.hide) end,
        set = function(v)
            local db = DB()
            if not (db and db.minimap) then return end
            local hide = not v
            if (db.minimap.hide and true or false) == hide then return end
            db.minimap.hide = hide
            if ns.MinimapButton and ns.MinimapButton.Refresh then ns.MinimapButton:Refresh() end
        end,
        default = true,
    },
    helpNext = {
        get = function() local h = HelpTable(); return h ~= nil and not h.seen end,
        set = function(v)
            local h = HelpTable()
            if h then h.seen = not v end
        end,
        default = false,
    },
    showHidden = {
        get = function() local db = DB(); return db and db.filters and db.filters.showHidden and true or false end,
        set = function(v)
            local db = DB()
            if not (db and db.filters) then return end
            v = v and true or false
            if (db.filters.showHidden and true or false) == v then return end
            local SL = ns.SetList
            if SL and SL.ToggleShowHidden then
                SL.ToggleShowHidden(db.filters)   -- toggles, refreshes the list, calls S:Refresh()
            else
                db.filters.showHidden = v
                if SL and SL.Refresh then SL:Refresh() end
            end
        end,
        default = false,
    },
    -- beta.7: read on every hover / click by Tooltip.lua and Integrations.lua.
    tooltipLine = {
        get = function() local db = DB(); return not (db and db.tooltipLine == false) end,
        set = function(v) local db = DB(); if db then db.tooltipLine = v and true or false end end,
        default = true,
    },
    tooltipShift = {
        get = function() local db = DB(); return db and db.tooltipShift == true or false end,
        set = function(v) local db = DB(); if db then db.tooltipShift = v and true or false end end,
        default = false,
    },
    altClick = {
        get = function() local db = DB(); return not (db and db.altClick == false) end,
        set = function(v) local db = DB(); if db then db.altClick = v and true or false end end,
        default = true,
    },
}

-- Read by /gs selftest (setting value == saved data).
S.VARS, S.VALUES = VAR, VALUES

function S:IsAvailable()
    return self.category ~= nil
end

-- One boolean setting: a proxy (getter/setter) where the client has it, else an
-- add-on setting on a small mirror table whose changes are written back.
local mirror = {}
local function MakeSetting(category, key, name)
    local v = VALUES[key]
    local Set = Settings
    local vtype = (Set.VarType and Set.VarType.Boolean) or "boolean"
    if type(Set.RegisterProxySetting) == "function" then
        local ok, setting = pcall(Set.RegisterProxySetting, category, VAR[key], vtype, name, v.default,
            function() return v.get() and true or false end,
            function(value) v.set(value) end)
        if ok and setting then return setting end
    end
    if type(Set.RegisterAddOnSetting) == "function" then
        mirror[VAR[key]] = v.get() and true or false
        local ok, setting = pcall(Set.RegisterAddOnSetting, category, VAR[key], VAR[key], mirror,
            vtype, name, v.default)
        if ok and type(setting) == "table" then
            local function OnChanged(_, value)
                if type(value) ~= "boolean" then value = mirror[VAR[key]] end
                v.set(value)
            end
            if setting.SetValueChangedCallback then
                pcall(setting.SetValueChangedCallback, setting, OnChanged)
            elseif type(Set.SetOnValueChangedCallback) == "function" then
                pcall(Set.SetOnValueChangedCallback, VAR[key], OnChanged)
            end
            return setting
        end
    end
end

local function AddInit(layout, init)
    if layout and init and layout.AddInitializer then pcall(layout.AddInitializer, layout, init) end
end

local function Header(layout, text, tooltip)
    if type(CreateSettingsListSectionHeaderInitializer) ~= "function" then return end
    local ok, init = pcall(CreateSettingsListSectionHeaderInitializer, text, tooltip)
    if ok then AddInit(layout, init) end
    return ok and init or nil
end

local function Checkbox(category, key, name, tooltip)
    local setting = MakeSetting(category, key, name)
    if not setting then return end
    local create = Settings.CreateCheckbox or Settings.CreateCheckBox
    if type(create) == "function" then pcall(create, category, setting, tooltip) end
    return setting
end

-- A button row. Without the button initializer: a check box that runs the action when
-- ticked and unticks itself (mockup: "that row falls back to a check box").
local actionVars = 0
local function Button(category, layout, label, buttonText, onClick, tooltip)
    if type(CreateSettingsButtonInitializer) == "function" then
        local ok, init = pcall(CreateSettingsButtonInitializer, label, buttonText, onClick, tooltip, false)
        if ok and init then
            AddInit(layout, init)
            return init
        end
    end
    if type(Settings.RegisterProxySetting) ~= "function" then return end
    actionVars = actionVars + 1
    local vtype = (Settings.VarType and Settings.VarType.Boolean) or "boolean"
    local ok, setting = pcall(Settings.RegisterProxySetting, category, "GearSet_Action" .. actionVars,
        vtype, label ~= "" and label or buttonText, false,
        function() return false end,
        function(value) if value then onClick() end end)
    if ok and setting then
        local create = Settings.CreateCheckbox or Settings.CreateCheckBox
        if type(create) == "function" then pcall(create, category, setting, tooltip) end
    end
end

local function UnhideText()
    return T("S_UNHIDE_ALL", "Show all (%d)"):format(HiddenCount())
end

local function DataText()
    local info = ns.Data and ns.Data.DataInfo and ns.Data.DataInfo() or ns.DataInfo or {}
    local text = T("S_DATA", "Data version %s, checked %s, WoW Forever %s"):format(
        tostring(info.version or "?"), tostring(info.checked or "?"), tostring(info.game or "?"))
    local c = Theme.colors.settingsData
    if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(text) end
    return text
end

-- Button actions (all plain Show/Hide of our own frames or chat-free copy boxes).
local function ResetPosition()
    if ns.db then ns.db.point = nil end
    if ns.UI and ns.UI.ResetPosition then ns.UI:ResetPosition() end
end

local function UnhideAll()
    local D = ns.Data
    if HiddenCount() == 0 or not (D and D.ShowAllHidden) then return end
    pcall(D.ShowAllHidden)
    if ns.SetList and ns.SetList.Refresh then ns.SetList:Refresh() end
    S:Refresh()
end

local function ShowHelp()
    if ns.Help and ns.Help.Show then ns.Help:Show() end
end

local function Report()
    local text
    if type(ns.ReportText) == "function" then
        local ok, t = pcall(ns.ReportText)
        if ok and type(t) == "string" then text = t end
    end
    if not text then
        local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("GearSet", "Version")
            or (GetAddOnMetadata and GetAddOnMetadata("GearSet", "Version"))
        text = "Gear Set " .. tostring(v or "?")
    end
    if ns.ShowCopyBox then ns.ShowCopyBox("report", text) end
end

-- beta.7: forget one of the other saved characters (Alts.lua). Menu of names -> confirm
-- popup -> ns.Alts:Forget(key). The current character isn't listed (it is saved again
-- at logout anyway).
local function OtherChars()
    local A, out = ns.Alts, {}
    if not (A and A.Chars) then return out end
    local ok, list = pcall(A.Chars, A)
    if not ok or type(list) ~= "table" then return out end
    for _, c in ipairs(list) do
        if not c.me then out[#out + 1] = c end
    end
    return out
end

local function CharLabel(c)
    local text = tostring(c.name)
    if c.realm and c.realm ~= "" then text = text .. " - " .. tostring(c.realm) end
    local seen = ns.Alts and ns.Alts.SeenText and ns.Alts.SeenText(c.seen)
    if seen then text = text .. " (" .. seen .. ")" end
    return text
end

local function Forget(key, label)
    local A = ns.Alts
    if not (A and A.Forget) then return end
    local ok, done = pcall(A.Forget, A, key)
    if ok and done then
        if ns.Print then ns.Print(T("S_FORGET_DONE", "Forgot %s."):format(label)) end
        S:Refresh()
    end
end

local FORGET_DIALOG = {
    text = T("S_FORGET_ASK", "Forget %s?"),
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data)
        if type(data) == "table" then Forget(data.key, data.name) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}
if type(StaticPopupDialogs) == "table" then StaticPopupDialogs.GEARSET_FORGET = FORGET_DIALOG end

local function AskForget(c)
    if type(StaticPopup_Show) == "function" then
        StaticPopup_Show("GEARSET_FORGET", tostring(c.name), nil, { key = c.key, name = tostring(c.name) })
    end
end

-- `pick` (from "/gs forget 2"): the nth character of the printed list.
function S.ForgetMenu(pick)
    local list = OtherChars()
    if #list == 0 then
        if ns.Print then ns.Print(T("S_FORGET_NONE", "Gear Set has no other characters saved yet.")) end
        return
    end
    if pick then
        if list[pick] then AskForget(list[pick]) end
        return
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        local owner = UIParent
        if type(GetMouseFoci) == "function" then
            local ok, f = pcall(GetMouseFoci)
            if ok and type(f) == "table" and type(f[1]) == "table" then owner = f[1] end
        elseif type(GetMouseFocus) == "function" then
            local ok, f = pcall(GetMouseFocus)
            if ok and type(f) == "table" then owner = f end
        end
        local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
            if root.CreateTitle then root:CreateTitle(T("S_FORGET_MENU", "Forget which character?")) end
            for _, c in ipairs(list) do
                root:CreateButton(CharLabel(c), function() AskForget(c) end)
            end
        end)
        if ok then return end
    end
    -- No menu: numbered list in chat, "/gs forget <n>" picks one.
    if ns.Print then
        ns.Print(T("S_FORGET_MENU", "Forget which character?") .. " (/gs forget <n>)")
        for i, c in ipairs(list) do ns.Print(i .. ". " .. CharLabel(c)) end
    end
end

local function ForgetLabel()
    return T("S_FORGET_LABEL", "Saved characters (%d)"):format(#OtherChars())
end

-- Called by Core on ADDON_LOADED (after InitDB). Safe to call twice.
function S:Init()
    if self.category or self.tried then return end
    self.tried = true
    if not (type(Settings) == "table" and type(Settings.RegisterVerticalLayoutCategory) == "function"
            and type(Settings.RegisterAddOnCategory) == "function") then
        return
    end
    local ok, category, layout = pcall(Settings.RegisterVerticalLayoutCategory, T("TITLE", "Gear Set"))
    if not (ok and category) then return end
    if not layout and category.GetLayout then layout = category:GetLayout() end
    if not layout and Settings.GetLayout then
        local okL, l = pcall(Settings.GetLayout, category)
        if okL then layout = l end
    end

    Header(layout, T("S_WINDOW", "Window"))
    self.settings = {}
    self.settings.minimap = Checkbox(category, "minimap", T("S_MINIMAP", "Show the minimap button"),
        T("S_MINIMAP_TIP", "Also /gs minimap."))
    self.settings.helpNext = Checkbox(category, "helpNext",
        T("S_HELP_NEXT", "Show help the next time I open Gear Set"))
    Button(category, layout, T("S_POS_LABEL", "Window position"), T("S_RESET_POS", "Reset"),
        ResetPosition, T("S_RESET_POS_TIP", "Moves the window back to the middle of the screen."))

    Header(layout, T("S_LIST", "Set list"))
    self.settings.showHidden = Checkbox(category, "showHidden",
        T("S_SHOW_HIDDEN", "Show hidden sets in the list"))
    self.unhideInit = Button(category, layout, T("S_HIDDEN_LABEL", "Hidden sets"), UnhideText(), UnhideAll)
    -- Greyed out while nothing is hidden (only where the initializer has the method).
    if type(self.unhideInit) == "table" and type(self.unhideInit.AddModifyPredicate) == "function" then
        pcall(self.unhideInit.AddModifyPredicate, self.unhideInit, function() return HiddenCount() > 0 end)
    end

    Header(layout, T("S_TIPS", "Tooltip and clicks"))
    self.settings.tooltipLine = Checkbox(category, "tooltipLine",
        T("S_TOOLTIP_LINE", "Show the Gear Set line on item tooltips"))
    self.settings.tooltipShift = Checkbox(category, "tooltipShift", T("S_TOOLTIP_SHIFT", "Only while Shift is held"),
        T("S_TOOLTIP_SHIFT_TIP", "Keeps tooltips short when you use other tooltip addons."))
    self.settings.altClick = Checkbox(category, "altClick", T("S_ALT_CLICK", "Alt-click an item to open its guide"),
        T("S_ALT_CLICK_TIP", "Works on bag items, chat links, loot and the character window."))

    Header(layout, T("S_CHARS", "Characters"))
    self.forgetInit = Button(category, layout, ForgetLabel(), T("S_FORGET", "Forget a character"),
        function() S.ForgetMenu() end,
        T("S_FORGET_TIP", "Removes what Gear Set remembers about one of your other characters."))

    Header(layout, T("S_HELP", "Help"))
    Button(category, layout, T("S_HELP_LABEL", "First-time help"), T("S_HELP_NOW", "Show now"), ShowHelp)
    Button(category, layout, T("S_REPORT_LABEL", "Found a bug?"), T("S_REPORT", "Report a problem"), Report,
        T("S_REPORT_TIP", "Shows a line about your game and the set you looked at, ready to copy."))

    self.dataInit = Header(layout, DataText())

    if not pcall(Settings.RegisterAddOnCategory, category) then return end
    self.category = category
end

local function CategoryID(category)
    if category.GetID then
        local ok, id = pcall(category.GetID, category)
        if ok and id then return id end
    end
    return category.ID
end

local function OpenNow()
    local c = S.category
    if not (c and type(Settings.OpenToCategory) == "function") then return false end
    S:Refresh()
    return (pcall(Settings.OpenToCategory, CategoryID(c)))
end

-- Combat: one chat line, then open once combat ends (PLAYER_REGEN_ENABLED).
local waiter
local function OpenAfterCombat()
    if not waiter then
        waiter = CreateFrame("Frame")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            if S.pending then
                S.pending = nil
                OpenNow()
            end
        end)
    end
    if not S.pending then
        S.pending = true
        if ns.SafeRegister then ns.SafeRegister(waiter, "PLAYER_REGEN_ENABLED")
        else pcall(waiter.RegisterEvent, waiter, "PLAYER_REGEN_ENABLED") end
        if ns.Print then ns.Print(T("SETTINGS_COMBAT", "The settings open after combat.")) end
    end
end

-- true when opened (or queued until combat ends); false when there is no settings page.
function S:Open()
    if not self.category then return false end
    if InCombatLockdown and InCombatLockdown() then
        OpenAfterCombat()
        return true
    end
    return OpenNow()
end

-- Re-read values changed elsewhere (filter menu, /gs minimap, help closed, sets hidden).
-- Only tells Blizzard's controls; never refreshes the set list (SetList calls this).
function S:Refresh()
    if not self.category or self.refreshing then return end
    self.refreshing = true
    for key, var in pairs(VAR) do
        if mirror[var] ~= nil then mirror[var] = VALUES[key].get() and true or false end
        if type(Settings.NotifyUpdate) == "function" then pcall(Settings.NotifyUpdate, var) end
    end
    -- Button text and data line are read again the next time the rows are drawn.
    local function SetData(init, field, value)
        if not init then return end
        local data = init.GetData and init:GetData() or init.data
        if type(data) == "table" then data[field] = value end
    end
    SetData(self.unhideInit, "buttonText", UnhideText())
    SetData(self.dataInit, "name", DataText())
    SetData(self.forgetInit, "name", ForgetLabel())
    self.refreshing = nil
end
