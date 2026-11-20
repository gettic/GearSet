-- Gear Set: /gs probe (which game APIs this client has) and the data info for /gs check.
-- Read-only: only looks at functions and calls getters, never sets waypoints, never
-- registers anything. Each check runs in pcall, so a missing or throwing API gives a
-- short "error" line instead of a Lua error.
local ADDON, ns = ...

local Probe = {}
ns.Probe = Probe

local PROBE_MAX = ns.COPY_MAX or 2000    -- the copy box's letter limit (Core)

-- Planned art (plans\v1.0.0\review-ui.md, M/L confidence) + the Theme's own atlases.
local PLANNED_ATLASES = {
    "Waypoint-MapPin-Untracked", "Waypoint-MapPin-Highlight", "UI-QuestTracker-Header",
    "common-icon-checkmark", "GM-icon-settings",
    -- ui-review-3: Progress bars (ColoredProgressBarTemplate's art)
    "common-stat-bar-BG", "common-stat-bar-white", "common-stat-bar-green", "common-stat-bar-Mask",
    -- ui-review-3: bar behind each piece row
    "PetList-ButtonBackground",
    -- 1.1 beta.1 checklist / later Plan tab
    "Options_HorizontalDivider", "common-icon-redx", "QuestSharing-Padlock",
    -- ui-b1 job A: the Objective Tracker's own header band and fold button (+ tick for job B)
    "UI-QuestTracker-Secondary-Objective-Header", "ui-questtracker-primary-objective-header",
    "ui-questtrackerbutton-secondary-collapse", "ui-questtrackerbutton-secondary-expand",
    "ui-questtrackerbutton-secondary-collapse-pressed", "ui-questtrackerbutton-secondary-expand-pressed",
    "ui-questtrackerbutton-yellow-highlight", "ui-questtracker-tracker-check",
}
local PLANNED_TEMPLATES = {
    "PanelTabButtonTemplate", "MapCanvasPinTemplate", "MaximizeMinimizeButtonFrameTemplate",
    "MainHelpPlateButton", "WowStyle1DropdownTemplate", "GlowBoxTemplate", "UIPanelButtonTemplate",
    "TooltipBackdropTemplate",
    -- ui-review-3: Progress bars, guide copy view, help arrow
    "ColoredProgressBarTemplate", "InputScrollFrameTemplate", "GlowBoxArrowTemplate",
    -- ui-review-3: "Sets complete" count box
    "InsetFrameTemplate3",
    -- 1.1 beta.1 checklist X button
    "UIPanelCloseButtonNoScripts", "UIPanelCloseButton",
}
local PLANNED_FONTS = { "ObjectiveTrackerLineFont", "GameFontHighlightSmall", "GameFontNormalMed2",
    "ObjectiveTrackerHeaderFont" }

local function IsFunc(f) return type(f) == "function" end
local function YesNo(b) return b and "yes" or "no" end

-- Secret values (Midnight rules) can't be turned into text; say so instead.
local function Safe(v)
    if v == nil then return "nil" end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        if ok and secret then return "secret" end
    end
    local ok, s = pcall(tostring, v)
    return ok and s or "?"
end

-- t.a.b.c without erroring on missing tables.
local function Get(root, path)
    local v = root
    for key in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[key]
    end
    return v
end

-- "Name yes, Name no" for a list of global function paths (only the last part is
-- printed, e.g. "C_Map.SetUserWaypoint" -> "SetUserWaypoint", to keep the copy text short).
local function Has(paths)
    local out = {}
    for _, p in ipairs(paths) do
        out[#out + 1] = (p:match("([^%.]+)$") or p) .. " " .. YesNo(IsFunc(Get(_G, p)))
    end
    return table.concat(out, ", ")
end

-- Call a global function path; returns ok, results (ok false if missing or it threw).
local function Call(path, ...)
    local f = Get(_G, path)
    if not IsFunc(f) then return false end
    return pcall(f, ...)
end

-- "Name <first result>", "Name no" (missing) or "Name error" (it threw).
local function Val(path, ...)
    local name = path:match("([^%.]+)$") or path
    if not IsFunc(Get(_G, path)) then return name .. " no" end
    local ok, v = Call(path, ...)
    return name .. " " .. (ok and Safe(v) or "error")
end

-- One hidden DressUpModel, made once and only when the probe runs (to look at its methods).
local model
local function ModelMethods()
    if not model then
        local ok, m = pcall(CreateFrame, "DressUpModel")
        if not ok or not m then return nil end
        m:Hide()
        model = m
    end
    return model
end

local function AtlasOK(name)
    local info = Get(_G, "C_Texture.GetAtlasInfo")
    if not IsFunc(info) then return nil end
    local ok, r = pcall(info, name)
    return ok and r ~= nil
end

-- Every atlas name the Theme uses ({atlas=} / {atlases={}} anywhere in Theme.art).
local function ThemeAtlases(t, out, seen, depth)
    if type(t) ~= "table" or depth > 4 then return out end
    if type(t.atlas) == "string" and not seen[t.atlas] then
        seen[t.atlas] = true
        out[#out + 1] = t.atlas
    end
    if type(t.atlases) == "table" then
        for _, a in ipairs(t.atlases) do
            if type(a) == "string" and not seen[a] then seen[a] = true; out[#out + 1] = a end
        end
    end
    for _, v in pairs(t) do
        if type(v) == "table" then ThemeAtlases(v, out, seen, depth + 1) end
    end
    return out
end

local function MissingList(names, test)
    local miss, found, unknown = {}, 0, false
    for _, n in ipairs(names) do
        local r = test(n)
        if r == nil then unknown = true
        elseif r then found = found + 1
        else miss[#miss + 1] = n end
    end
    if unknown then return "can't test on this client" end
    local s = ("%d/%d"):format(found, #names)
    if #miss > 0 then s = s .. ", missing: " .. table.concat(miss, ", ") end
    return s
end

local function AddonVersion()
    local f = Get(_G, "C_AddOns.GetAddOnMetadata") or GetAddOnMetadata
    if not IsFunc(f) then return "?" end
    local ok, v = pcall(f, ADDON, "Version")
    return ok and v and Safe(v) or "?"
end

local function AddonLoaded(name)
    local f = Get(_G, "C_AddOns.IsAddOnLoaded") or IsAddOnLoaded
    if not IsFunc(f) then return "?" end
    local ok, loaded = pcall(f, name)
    return ok and YesNo(loaded) or "?"
end

-- The checks, in print order: { label, function returning the line's text }.
local CHECKS = {
    { "Client", function()
        local ok, ver, build, _, iface = Call("GetBuildInfo")
        local s = ok and ("%s (%s) interface %s"):format(Safe(ver), Safe(build), Safe(iface)) or "GetBuildInfo no"
        return s .. ", project " .. Safe(WOW_PROJECT_ID)
    end },
    { "Waypoint API", function()
        return Has({ "C_Map.SetUserWaypoint", "C_Map.CanSetUserWaypointOnMap",
            "C_SuperTrack.SetSuperTrackedUserWaypoint", "UiMapPoint.CreateFromCoordinates",
            -- beta.9 Way button: runtime zone lookup (Forever-only zones) and map names
            "C_Map.GetMapChildrenInfo", "C_Map.GetMapInfo" })
    end },
    { "Current map", function()
        local ok, mapID = Call("C_Map.GetBestMapForUnit", "player")
        if not ok then return "C_Map.GetBestMapForUnit no" end
        if mapID == nil then return "none" end
        local s = Safe(mapID)
        if s == "secret" then return s end
        local okI, info = Call("C_Map.GetMapInfo", mapID)
        if okI and type(info) == "table" then
            s = s .. " " .. Safe(info.name) .. " (type " .. Safe(info.mapType) .. ", parent " .. Safe(info.parentMapID) .. ")"
        end
        local okP, pos = Call("C_Map.GetPlayerMapPosition", mapID, "player")
        if okP and pos and pos.GetXY then
            local okXY, x, y = pcall(pos.GetXY, pos)
            if okXY and type(x) == "number" and type(y) == "number" and Safe(x) ~= "secret" then
                s = s .. (", at %.1f %.1f"):format(x * 100, y * 100)
            else
                s = s .. ", position " .. (okXY and Safe(x) or "error")
            end
        else
            s = s .. ", position none"
        end
        local okC, can = Call("C_Map.CanSetUserWaypointOnMap", mapID)
        s = s .. ", waypoint here " .. (okC and YesNo(can) or "?")
        local okIn, inInst, instType = Call("IsInInstance")
        if okIn and inInst then s = s .. ", in instance " .. Safe(instType) end
        return s
    end },
    { "Zone", function()
        local ok, z = Call("GetRealZoneText")
        local ok2, sub = Call("GetSubZoneText")
        return (ok and Safe(z) or "?") .. " / " .. (ok2 and Safe(sub) or "?")
    end },
    { "Map pins", function()
        local wm = WorldMapFrame
        return "MapCanvasDataProviderMixin " .. YesNo(type(MapCanvasDataProviderMixin) == "table")
            .. ", WorldMapFrame:AddDataProvider " .. YesNo(type(wm) == "table" and IsFunc(wm.AddDataProvider))
    end },
    { "Model", function()
        local m = ModelMethods()
        if not m then return "DressUpModel can't be made" end
        local out = {}
        for _, name in ipairs({ "SetCustomRace", "SetItemTransmogInfo", "GetItemTransmogInfoList",
            "UndressSlot", "SetSheathed", "SetCamDistanceScale", "SetAnimation" }) do
            out[#out + 1] = name .. " " .. YesNo(IsFunc(m[name]))
        end
        return table.concat(out, ", ")
    end },
    { "Tooltip", function()
        local tdp = TooltipDataProcessor
        local s = "TooltipDataProcessor.AddTooltipPostCall " .. YesNo(type(tdp) == "table" and IsFunc(tdp.AddTooltipPostCall))
        s = s .. ", Enum.TooltipDataType.Item " .. Safe(Get(_G, "Enum.TooltipDataType.Item"))
        s = s .. ", " .. Has({ "C_TooltipInfo.GetItemByID" })
        local gt = GameTooltip
        local okH, has = false, false
        if type(gt) == "table" and IsFunc(gt.HasScript) then okH, has = pcall(gt.HasScript, gt, "OnTooltipSetItem") end
        return s .. ", OnTooltipSetItem " .. (okH and YesNo(has) or "no")
    end },
    { "Secrets", function()
        return Has({ "issecretvalue", "canaccessvalue" })
    end },
    -- beta.2: can we read an item's tooltip text (fit facts)? Item 16827 = a Tier 1 piece.
    { "Tooltip data", function()
        local s = "in combat " .. YesNo(InCombatLockdown and InCombatLockdown())
        local ok, data = Call("C_TooltipInfo.GetItemByID", 16827)
        if not ok then
            s = s .. ", GetItemByID " .. (IsFunc(Get(_G, "C_TooltipInfo.GetItemByID")) and "error" or "no")
        elseif Safe(data) == "secret" then
            s = s .. ", item data secret"
        elseif type(data) == "table" and type(data.lines) == "table" then
            local first = data.lines[1]
            s = s .. ", item lines " .. #data.lines .. ", first " .. Safe(first and first.leftText)
        else
            s = s .. ", item data " .. Safe(data)
        end
        local D = ns.Data
        if D and D.GetItemTooltipLines then
            local okL, lines = pcall(D.GetItemTooltipLines, D, 16827)
            s = s .. ", our read " .. (okL and (type(lines) == "table" and (#lines .. " lines") or "none") or "error")
        end
        return s
    end },
    -- beta.2: Blizzard Settings panel pieces (UI\Settings.lua).
    { "Settings", function()
        return Has({ "Settings.RegisterVerticalLayoutCategory", "Settings.RegisterAddOnCategory",
            "Settings.RegisterAddOnSetting", "Settings.RegisterProxySetting", "Settings.CreateCheckbox",
            "Settings.OpenToCategory", "CreateSettingsButtonInitializer",
            "CreateSettingsListSectionHeaderInitializer" })
    end },
    { "Lockouts", function()
        local s = Has({ "GetSavedInstanceInfo", "RequestRaidInfo", "GetSavedInstanceEncounterInfo" })
            .. ", " .. Val("GetNumSavedInstances")
        -- 1.1: each saved row (name, reset s, isRaid, bosses done/total, map ID = 14th return)
        local okN, n = Call("GetNumSavedInstances")
        if okN and type(n) == "number" and not (issecretvalue and issecretvalue(n)) then
            for i = 1, math.min(n, 5) do
                local ok, name, _, reset, _, locked, _, _, isRaid, _, _, total, done, _, mapID = Call("GetSavedInstanceInfo", i)
                if ok then
                    s = s .. (" [%s %s reset %s raid %s %s/%s map %s]"):format(Safe(name), Safe(locked), Safe(reset),
                        Safe(isRaid), Safe(done), Safe(total), Safe(mapID))
                end
            end
        end
        return s
    end },
    -- 1.1 beta.1 checklist: where you are (name, type, instance ID = 8th return) and the
    -- checklist's own match; the loot roll frames the loot mark hooks.
    { "Instance", function()
        local okI, inInst, itype = Call("IsInInstance")
        local s = "in " .. (okI and Safe(inInst) or "?") .. " " .. (okI and Safe(itype) or "")
        if okI and inInst then
            local ok, name, _, _, _, maxPlayers, _, _, mapID = Call("GetInstanceInfo")
            if ok then s = s .. (", %s, %s players, id %s"):format(Safe(name), Safe(maxPlayers), Safe(mapID)) end
            local R = ns.Runs
            if ok and R and R.RunsIn and not (issecretvalue and (issecretvalue(name) or issecretvalue(mapID))) then
                local okR, runs = pcall(R.RunsIn, name, tonumber(mapID))
                if okR and type(runs) == "table" then s = s .. ", matches " .. (#runs > 0 and table.concat(runs, "/") or "none") end
            end
        end
        return s
    end },
    { "Loot roll", function()
        local frames = 0
        for i = 1, 4 do if type(_G["GroupLootFrame" .. i]) == "table" then frames = frames + 1 end end
        local LM = ns.LootMark
        return Has({ "GetLootRollItemLink", "GetLootRollItemInfo" }) .. (", GroupLootFrame %d/4"):format(frames)
            .. ", hooked " .. (LM and LM.HookedCount and LM.HookedCount() or 0)
    end },
    -- 1.1 beta.2 shopping list: recipe reads (Imperial Plate Chest's spell from the data, else
    -- 16742), price addons (read only: which API functions exist, one price), item levels,
    -- the model's UndressSlot (hide helm / cloak / weapons on our own model).
    { "Recipes", function()
        local S = ns.Shopping
        local spells = S and S.RecipeSpells and S.RecipeSpells() or {}
        local id = spells[1] or 16742
        local s = Has({ "C_SpellBook.IsSpellKnown", "C_TradeSkillUI.GetRecipeInfo", "IsPlayerSpell" })
            .. (", %d recipe spells in data, %s %s"):format(#spells, tostring(id), Val("C_SpellBook.IsSpellKnown", id))
        local ok, info = Call("C_TradeSkillUI.GetRecipeInfo", id)
        if ok and type(info) == "table" then s = s .. ", learned " .. Safe(info.learned) end
        return s
    end },
    { "Price addons", function()
        local AH = ns.AHPrices
        if not (AH and AH.Describe) then return "module no" end
        local hasA, names, hasT = AH.Describe()
        local s = "Auctionator " .. YesNo(hasA)
        if hasA then s = s .. " (" .. table.concat(names, " ", 1, math.min(#names, 20)) .. ")" end
        s = s .. ", TSM_API " .. YesNo(hasT) .. ", source " .. Safe(AH.Source())
        local ok, p, age = pcall(AH.Get, 12359)   -- Thorium Bar
        if ok then s = s .. ", 12359 = " .. Safe(p) .. " age " .. Safe(age) end
        return s
    end },
    { "Required level", function()
        local ok, name, _, _, _, minLevel = Call("C_Item.GetItemInfo", 16820)
        return Has({ "C_Item.GetItemInfo", "UnitLevel" }) .. ", 16820 " .. (ok and (Safe(name) .. " min " .. Safe(minLevel)) or "?")
            .. ", " .. Val("UnitLevel", "player")
    end },
    { "Model slots", function()
        local m = ModelMethods()
        return "UndressSlot " .. YesNo(m and IsFunc(m.UndressSlot))
    end },
    { "Reputation", function()
        local s = Has({ "C_Reputation.GetFactionDataByID", "GetFactionInfoByID" })
        local ok, data = Call("C_Reputation.GetFactionDataByID", 529)   -- Argent Dawn
        if ok and type(data) == "table" then
            s = s .. ", 529 = " .. Safe(data.name) .. " " .. Safe(data.reaction)
        else
            local ok2, name, _, standing = Call("GetFactionInfoByID", 529)
            if ok2 and name then s = s .. ", 529 = " .. Safe(name) .. " " .. Safe(standing) end
        end
        return s
    end },
    { "PvP rank", function()
        return Val("UnitPVPRank", "player") .. ", " .. Has({ "GetPVPRankInfo", "GetPVPLifetimeStats" })
    end },
    { "Professions", function()
        local s = Has({ "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
            "C_TradeSkillUI.GetProfessionInfoBySkillLineID" })
        local ok, p1, p2 = Call("GetProfessions")
        if ok then s = s .. ", mine " .. Safe(p1) .. "/" .. Safe(p2) end
        return s
    end },
    { "Quests", function()
        return Has({ "C_QuestLog.IsQuestFlaggedCompleted" })
    end },
    { "Account bank", function()
        local s = "C_Bank " .. YesNo(type(C_Bank) == "table")
            .. ", Enum.BankType.Account " .. Safe(Get(_G, "Enum.BankType.Account"))
            .. ", Enum.BagIndex.AccountBankTab_1 " .. Safe(Get(_G, "Enum.BagIndex.AccountBankTab_1"))
        local acc = Get(_G, "Enum.BankType.Account")
        if acc ~= nil then
            local ok, can = Call("C_Bank.CanViewBank", acc)
            s = s .. ", CanViewBank " .. (ok and YesNo(can) or "?")
        end
        return s
    end },
    { "Keyring", function()
        local id = Get(_G, "Enum.BagIndex.Keyring")
        if id == nil then id = KEYRING_CONTAINER end
        local s = "bag ID " .. Safe(id)
        if type(id) == "number" then
            local ok, n = Call("C_Container.GetContainerNumSlots", id)
            s = s .. ", slots " .. (ok and Safe(n) or "?")
        end
        local okK, hasKey = Call("HasKey")
        return s .. ", HasKey " .. (okK and YesNo(hasKey) or "no")
    end },
    { "Mail", function()
        return Has({ "GetInboxNumItems", "GetInboxItemLink", "C_Container.GetContainerItemInfo" })
    end },
    { "Pet journal", function()
        local ok, n, owned = Call("C_PetJournal.GetNumPets")
        return ok and ("GetNumPets %s (owned %s)"):format(Safe(n), Safe(owned)) or "C_PetJournal.GetNumPets no"
    end },
    { "Mount journal", function()
        return Val("C_MountJournal.GetNumMounts") .. ", "
            .. Has({ "C_MountJournal.GetMountIDs", "C_MountJournal.GetMountInfoByID" })
    end },
    { "Collections", function()
        return Has({ "C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance",
            "C_TransmogCollection.GetAppearanceInfoBySource", "C_TransmogCollection.GetAllAppearanceSources" })
    end },
    { "Other addons", function()
        local out = {}
        for _, name in ipairs({ "TomTom", "Auctionator", "TradeSkillMaster", "Questie" }) do
            out[#out + 1] = name .. " " .. AddonLoaded(name)
        end
        return table.concat(out, ", ")
    end },
    { "Theme atlases", function()
        local names = ThemeAtlases(ns.Theme and ns.Theme.art, {}, {}, 0)
        local okU, _, classFile = Call("UnitClass", "player")
        if not okU then classFile = nil end
        if type(classFile) == "string" and ns.Theme and ns.Theme.art and type(ns.Theme.art.modelBgAtlas) == "string" then
            names[#names + 1] = ns.Theme.art.modelBgAtlas:format(classFile:lower())
        end
        return MissingList(names, AtlasOK)
    end },
    { "Planned atlases", function()
        return MissingList(PLANNED_ATLASES, AtlasOK)
    end },
    { "Templates", function()
        local info = Get(_G, "C_XMLUtil.GetTemplateInfo")
        if not IsFunc(info) then return "can't test on this client" end
        local names, seen = {}, {}
        for _, list in pairs(ns.Theme and ns.Theme.templates or {}) do
            if type(list) == "table" then
                for _, n in ipairs(list) do
                    if type(n) == "string" and not seen[n] then seen[n] = true; names[#names + 1] = n end
                end
            end
        end
        table.sort(names)
        for _, n in ipairs(PLANNED_TEMPLATES) do
            if not seen[n] then seen[n] = true; names[#names + 1] = n end
        end
        return MissingList(names, function(n)
            local ok, r = pcall(info, n)
            return ok and r ~= nil
        end)
    end },
    { "Fonts", function()
        return MissingList(PLANNED_FONTS, function(n) return _G[n] ~= nil end)
    end },
}

-- Short error text: drop the file path the game puts in front.
local function ShortError(err)
    local s = Safe(err)
    s = s:gsub("^.-:%d+: ", "")
    return "error: " .. s:sub(1, 80)
end

-- Shared with /gs selftest (SelfTest.lua), read-only helpers.
Probe.Safe, Probe.ShortError, Probe.AtlasOK = Safe, ShortError, AtlasOK
Probe.AddonVersion, Probe.MissingList = AddonVersion, MissingList

-- Runs every check; returns the list of "Label: text" lines. Never errors.
function Probe.Lines()
    local L = ns.L
    local lines = { (L.PROBE_HEAD):format(AddonVersion()) }
    for _, check in ipairs(CHECKS) do
        local ok, text = pcall(check[2])
        if not ok then text = ShortError(text)
        elseif type(text) ~= "string" then text = Safe(text) end
        lines[#lines + 1] = check[1] .. ": " .. text
    end
    return lines
end

-- /gs probe: one chat line per check, then the same text (one line, " | " between checks)
-- in the copy box so the user can paste it back.
function Probe:Run()
    local ok, lines = pcall(Probe.Lines)
    if not ok then lines = { ShortError(lines) } end
    for _, line in ipairs(lines) do ns.Print(line) end
    local text = table.concat(lines, " | ")
    if #text > PROBE_MAX then text = text:sub(1, PROBE_MAX - 3) .. "..." end
    if ns.ShowCopyBox then pcall(ns.ShowCopyBox, "probe", text) end
    ns.Print(ns.L.PROBE_COPY)
end

-- Data info for /gs check: ns.DataInfo = { version, checked, game } in SetsData.lua, read
-- through ns.Data.DataInfo() (plans\v1.0.0\beta1-interface.md). Read defensively so a
-- missing or half-filled field shows "unknown", never an error.
local function DataField()
    local D = ns.Data
    if type(D) == "table" and IsFunc(D.DataInfo) then
        local ok, info = pcall(D.DataInfo)
        if ok and type(info) == "table" then return info end
    end
    if type(ns.DataInfo) == "table" then return ns.DataInfo end
    return {}
end

-- "?" and 0 are the data layer's "missing" values.
local function Known(v)
    if v == nil or v == "" or v == "?" or v == 0 then return nil end
    return v
end

local function SourcesText(s)
    if type(s) == "string" and s ~= "" then return s end
    if type(s) == "table" then
        local out = {}
        for _, v in ipairs(s) do
            if type(v) == "string" or type(v) == "number" then out[#out + 1] = tostring(v) end
        end
        if #out > 0 then return table.concat(out, ", ") end
    end
    return nil
end

function Probe.DataInfoLines()
    local L = ns.L
    local info = DataField()
    local function Text(v)
        v = Known(v)
        return v == nil and L.DATA_UNKNOWN or Safe(v)
    end
    local lines = {
        L.DATA_VERSION:format(Text(info.version), Text(info.checked), Text(info.game)),
        L.DATA_SOURCES:format(SourcesText(info.sources) or L.DATA_SOURCES_LIST),
    }
    -- Forever-checked / not-yet-released counts, if the data layer has them.
    local D = ns.Data
    if type(D) == "table" and IsFunc(D.FlagCounts) then
        local ok, c = pcall(D.FlagCounts, D)
        if ok and type(c) == "table" then
            local function N(v) return type(v) == "number" and v or 0 end
            lines[#lines + 1] = L.DATA_FLAGS:format(N(c.setsChecked), N(c.sets), N(c.setsUnreleased),
                N(c.sourcesChecked), N(c.sources), N(c.piecesLater))
            if N(c.badFlags) > 0 then lines[#lines + 1] = L.DATA_BAD_FLAGS:format(N(c.badFlags)) end
        end
    end
    return lines
end

function Probe:PrintDataInfo()
    local ok, lines = pcall(Probe.DataInfoLines)
    if not ok then lines = { ShortError(lines) } end
    for _, line in ipairs(lines) do ns.Print(line) end
end
