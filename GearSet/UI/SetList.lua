-- Gear Set: left panel - search box, filter menu and the scrolling set list.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local SetList = {}
ns.SetList = SetList

local ROW_H = Theme.sizes.setRow or 22
local COUNT_W = Theme.sizes.setCount or 32   -- fixed width of "have/total", so the faction icons line up
local MAX_REASONS = 4   -- effort reasons shown in a set row's tooltip

-- Text with an English fallback (keys part A adds to ns.L at the merge).
local function T(key, fallback) return L[key] or fallback end

-- Calls into Data (part A); nil-guarded so the list works without them.
local function IsHidden(set)
    local D = ns.Data
    return D and D.IsHidden and D.IsHidden(set) and true or false
end

local function TierName(tag)
    local D = ns.Data
    if D and D.TierName then return D.TierName(tag) end
    return L["TIER_" .. tag] or tag
end

-- Effort table for a set or nil (nothing needed, or Data has no effort yet).
function SetList.GetEffort(set)
    local D = ns.Data
    if not (set and D and D.GetEffort) then return nil end
    local ok, e = pcall(D.GetEffort, D, set)
    if ok and type(e) == "table" then return e end
end

local EFFORT_WORDS = { [0] = "Done", "Low", "Medium", "High", "Very high" }

-- Effort word ("High") and colour r, g, b (Theme.effortColor: Blizzard's con colours).
function SetList.EffortWord(e)
    local level = e and tonumber(e.level) or 0
    return e and e.word or L["EFFORT_" .. level] or EFFORT_WORDS[level] or tostring(level)
end

function SetList.EffortRGB(e)
    local level = e and tonumber(e.level) or 0
    local c = Theme.effortColor and (Theme.effortColor[level] or Theme.effortColor[0])
    if c and c.GetRGB then return c:GetRGB() end
    return 0.5, 0.5, 0.5
end

-- "Effort: High" (coloured) + up to `max` reasons in a tooltip; nothing while nothing is needed.
function SetList.AddEffortLines(tip, set, max)
    local e = SetList.GetEffort(set)
    if not e or (tonumber(e.level) or 0) == 0 then return false end
    local r, g, b = SetList.EffortRGB(e)
    tip:AddLine(T("EFFORT", "Effort: %s"):format(SetList.EffortWord(e)), r, g, b)
    local reasons = type(e.reasons) == "table" and e.reasons or {}
    local sr, sg, sb = Theme.colors.text:GetRGB()
    for i, text in ipairs(reasons) do
        if max and i > max then break end
        tip:AddLine("  " .. tostring(text), sr, sg, sb, true)
    end
    return true
end

-- Class line for a set: class names in class colours; hinted sets (Dungeon Set 1/2)
-- add "(any class can wear it)"; nil = all classes. Also used by the right panel header.
function SetList.ClassText(set)
    local list, hinted = ns.Data:SetClassList(set)
    if not list then return nil end
    local names = {}
    for _, c in ipairs(list) do
        names[#names + 1] = Theme.ClassColor(c.file):WrapTextInColorCode(c.name)
    end
    local text = table.concat(names, ", ")
    if hinted then text = text .. " " .. Theme.colors.subtle:WrapTextInColorCode(L.ANY_CAN_WEAR) end
    return text
end

-- WoW Forever lines for a set's tooltips (set list rows, the piece list's "Have x / y"):
-- the whole set or some pieces not out yet (those aren't counted), then checked / not confirmed.
function SetList.AddFlagLines(tip, set)
    local c, D = Theme.colors, ns.Data
    local nLater = set.later and #set.later or 0
    if set.unreleased then
        local r, g, b = c.flagLater:GetRGB()
        tip:AddLine(D.FlagText("FLAG_LATER"), r, g, b, true)
    elseif nLater > 0 then
        local r, g, b = c.flagLater:GetRGB()
        tip:AddLine(D.FlagText("FLAG_LATER_COUNT"):format(nLater), r, g, b, true)
    end
    local r, g, b = (set.checked and c.flagChecked or c.flagClassic):GetRGB()
    tip:AddLine(D.FlagText(set.checked and "FLAG_CHECKED" or "FLAG_CLASSIC"), r, g, b, true)
end

-- beta.7: one line per other saved character that has some of the set ("Stabby: 5/8"),
-- at most MAX_ALTS. Names stay on screen only.
local MAX_ALTS = 5
function SetList.AddAltLines(tip, set)
    local A = ns.Alts
    if not (A and A.Chars and A.GetSetProgress and set and set.id) then return end
    local ok, chars = pcall(A.Chars, A)
    if not ok or type(chars) ~= "table" then return end
    local shown = 0
    for _, c in ipairs(chars) do
        if not c.me then
            local okP, have, total = pcall(A.GetSetProgress, A, set.id, c.key)
            if okP and type(have) == "number" and have > 0 and (total or 0) > 0 then
                if shown == MAX_ALTS then return end
                if shown == 0 then tip:AddLine(L.ALT_TIP_HEAD, Theme.colors.subtle:GetRGB()) end
                shown = shown + 1
                tip:AddLine("  " .. L.ALT_SET_LINE:format(tostring(c.name), have, total), Theme.CountColor(have, total))
            end
        end
    end
end

local function SetTooltip(row)
    local set = row.set
    if not set then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local dim = set.removed or set.unreleased
    local tr, tg, tb = (dim and Theme.colors.removed or Theme.colors.title):GetRGB()
    GameTooltip:SetText(set.name, tr, tg, tb)
    local armor = ns.Data.ArmorName(set.armor)
    if armor then GameTooltip:AddLine(armor, Theme.colors.armorLine:GetRGB()) end
    local classes = SetList.ClassText(set)
    if not classes then
        GameTooltip:AddLine(L.ALL_CLASSES, Theme.colors.subtle:GetRGB())
    else
        local r, g, b = Theme.colors.text:GetRGB()
        GameTooltip:AddLine(classes, r, g, b, true)
    end
    local faction = ns.Data.FactionName(set.faction)
    if faction then GameTooltip:AddLine(faction, Theme.colors.subtle:GetRGB()) end
    if type(set.tier) == "string" and set.tier ~= "" then
        GameTooltip:AddLine(T("TIER_LINE", "Tier: %s"):format(TierName(set.tier)), Theme.colors.subtle:GetRGB())
    end
    local have, total = ns.Owned:SetCount(set)
    GameTooltip:AddLine(L.HAVE_COUNT:format(have, total), Theme.CountColor(have, total))
    if ns.PieceList and ns.PieceList.AddDoneLines then pcall(ns.PieceList.AddDoneLines, GameTooltip, set) end
    SetList.AddAltLines(GameTooltip, set)
    SetList.AddEffortLines(GameTooltip, set, MAX_REASONS)
    if set.removed then
        local r, g, b = Theme.colors.removed:GetRGB()
        GameTooltip:AddLine(L.REMOVED_TIP, r, g, b, true)
    end
    SetList.AddFlagLines(GameTooltip, set)
    SetList.AddGoldLines(GameTooltip, set)
    local TR = ns.Track
    if TR and TR.IsSet(set) then
        GameTooltip:AddLine(T("TRACKED", "Tracked"), Theme.colors.partial:GetRGB())
    end
    if TR then Theme.AddHint(GameTooltip, T("TRACK_HINT", "Shift-click: track this set")) end
    if IsHidden(set) then
        Theme.AddHint(GameTooltip, T("HIDDEN_TIP", "Hidden: right-click to show it again."))
    elseif ns.Data and ns.Data.SetHidden then
        Theme.AddHint(GameTooltip, T("HIDE_HINT", "Right-click: hide this set"))
    end
    GameTooltip:Show()
end

-- beta.8: "Gold still needed: 12g" (+ "n pieces can't be bought") from PART B's Gold.lua.
function SetList.AddGoldLines(tip, set)
    local P = ns.Progress
    local text = P and P.SetCostText and P.SetCostText(set)
    if text then
        local r, g, b = Theme.colors.subtle:GetRGB()
        tip:AddLine(text, r, g, b, true)
    end
end

-- Hide or show a set (right-click menu), then redraw the list and the settings page.
function SetList.ToggleHidden(set)
    local D = ns.Data
    if not (set and D and D.SetHidden) then return end
    D.SetHidden(set, not IsHidden(set))
    if ns.Progress then ns.Progress:Invalidate() end    -- hidden sets aren't counted
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    SetList:Refresh()
    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
end

-- Row right-click: Blizzard's context menu with the set name, Track, Share in chat and
-- Hide / Show this set.
local function RowMenu(row)
    local set = row.set
    if not set then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local hidden = IsHidden(set)
    local TR, P = ns.Track, ns.Progress
    MenuUtil.CreateContextMenu(row, function(_, root)
        if root.CreateTitle then root:CreateTitle(set.name) end
        if TR then
            local text = TR.IsSet(set) and T("UNTRACK_SET", "Stop tracking this set") or T("TRACK_SET", "Track this set")
            root:CreateButton(text, function() TR.ToggleSet(set) end)
        end
        if P and P.CanShare and P.CanShare() then
            root:CreateButton(T("SHARE", "Share in chat"), function() P.Share(set) end)
        end
        if ns.Data and ns.Data.SetHidden then
            local text = hidden and T("SHOW_SET", "Show this set") or T("HIDE_SET", "Hide this set")
            root:CreateButton(text, function() SetList.ToggleHidden(set) end)
        end
    end)
end

-- Right end of a row, from the right: count, faction mark, tracking star, "hidden" tag;
-- the name ends left of the last one shown (so the name is cut, never the marks).
local function SetFactionIcon(row, faction, hidden, tracked)
    local art = Theme.art.faction
    local entry = faction and art and art[faction]
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 8, 0)
    row.tag:ClearAllPoints()
    row.star:ClearAllPoints()
    local anchor, gap
    if entry then
        Theme.SetArt(row.faction, entry)
        row.faction:Show()
        anchor, gap = row.faction, -4
    else
        row.faction:Hide()
        anchor, gap = row.count, -6
    end
    if tracked then
        row.star:SetPoint("RIGHT", anchor, "LEFT", gap, 0)
        row.star:Show()
        anchor, gap = row.star, -3
    else
        row.star:Hide()
    end
    -- A hidden set's "hidden" tag sits left of the icon / count; the name is cut, not the tag.
    if hidden then
        row.tag:SetPoint("RIGHT", anchor, "LEFT", gap, 0)
        row.tag:Show()
        row.label:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
    else
        row.tag:Hide()
        row.label:SetPoint("RIGHT", anchor, "LEFT", gap, 0)
    end
end

local ResultTooltip   -- search result rows (below)

-- Parts every list row has (set rows and search result rows share the frames).
local function BuildRow(row)
    if not row.gsInit then
        row.gsInit = true
        row:SetHeight(ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        Theme.SetArt(row.hl, Theme.art.listHover)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        Theme.SetArt(row.sel, Theme.art.listSelected)
        row.count = row:CreateFontString(nil, "OVERLAY")
        Theme.Font(row.count, "small")
        row.count:SetPoint("RIGHT", -6, 0)
        row.count:SetWidth(COUNT_W)
        row.count:SetJustifyH("RIGHT")
        row.label = row:CreateFontString(nil, "OVERLAY")
        Theme.Font(row.label, "text")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.faction = row:CreateTexture(nil, "ARTWORK")
        local size = (Theme.art.faction and Theme.art.faction.size) or 14
        row.faction:SetSize(size, size)
        row.faction:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
        row.faction:Hide()
        row.tag = row:CreateFontString(nil, "OVERLAY")
        Theme.Font(row.tag, "disabled")
        row.tag:SetJustifyH("RIGHT")
        row.tag:SetWordWrap(false)
        row.tag:Hide()
        if ns.Track and ns.Track.MakeStar then
            row.star = ns.Track.MakeStar(row, "ARTWORK")
        else
            row.star = row:CreateTexture(nil, "ARTWORK")
            row.star:Hide()
        end
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            if self.elem then
                if button ~= "RightButton" then SetList.Activate(self.elem) end
            elseif button == "RightButton" then
                RowMenu(self)
            elseif self.set and IsShiftKeyDown and IsShiftKeyDown() and ns.Track then
                ns.Track.ToggleSet(self.set)     -- shift-click: track / untrack (no chat link)
            elseif self.set then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                ns.UI:SelectSet(self.set.key)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if self.elem then ResultTooltip(self) else SetTooltip(self) end
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end
end

-- Back to the set row look after the frame showed a search result (frames are reused).
local function ResetRowLook(row)
    row.elem = nil
    row:EnableMouse(true)
    row.hl:Show()
    Theme.Font(row.label, "text")
    Theme.Font(row.count, "small")
    row.count:Show()
end

local function InitRow(row, set)
    BuildRow(row)
    ResetRowLook(row)
    row.set = set
    local selected = set.key == ns.db.lastSet
    -- Hidden sets (listed only with "Show hidden sets"), removed and not-yet-released
    -- sets are grey; on the selected bar a lighter grey so the name stays readable.
    local hidden = IsHidden(set)
    row.label:SetText(set.name)
    local nameColor = Theme.colors.text
    if hidden then
        local c = Theme.colors
        nameColor = selected and (c.hiddenSelected or c.removedSelected) or (c.hidden or c.removed)
        row.tag:SetText(T("HIDDEN_TAG", "hidden"))
        row.tag:SetTextColor(nameColor:GetRGB())
    elseif set.removed then
        nameColor = selected and Theme.colors.removedSelected or Theme.colors.removed
    elseif set.unreleased then
        nameColor = selected and Theme.colors.laterSelected or Theme.colors.later
    end
    row.label:SetTextColor(nameColor:GetRGB())
    SetFactionIcon(row, set.faction, hidden, ns.Track and ns.Track.IsSet(set))
    local have, total = ns.Owned:SetCount(set)
    row.count:SetText(("%d/%d"):format(have, total))
    if set.unreleased then row.count:SetTextColor(Theme.colors.later:GetRGB())
    else row.count:SetTextColor(Theme.CountColor(have, total)) end
    row.sel:SetShown(selected)
end

-- ---------------------------------------------------------------------------
-- beta.9 search results (part C, ns.Search): with search text the list shows groups
-- ("Sets (4)", "Pieces (2)", "Bosses (1)" ...). Element data: a set table (the normal set
-- row) or { gsKind = "head" | "piece" | "boss" | "place" | "npc" | "more" | "back", ... }.
local SOURCE_KINDS = { boss = true, place = true, npc = true }
local KIND_WORD = { boss = { "SEARCH_KIND_BOSS", "Boss" }, place = { "SEARCH_KIND_PLACE", "Place" },
    npc = { "SEARCH_KIND_NPC", "NPC (vendor or quest giver)" } }

local function Color(key, fallback)
    local c = Theme.colors
    return c[key] or c[fallback] or c.text
end

local function Grey(text)
    return Color("searchSub", "subtle"):WrapTextInColorCode(text)
end

local function HideSetParts(row)
    row.faction:Hide(); row.star:Hide(); row.tag:Hide(); row.sel:Hide()
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
end

local function InitResultRow(row, e)
    BuildRow(row)
    ResetRowLook(row)
    row.elem, row.set = e, nil
    HideSetParts(row)
    row.count:SetText("")
    local k = e.gsKind
    if k == "head" then
        row:EnableMouse(false)
        row.hl:Hide()
        Theme.Font(row.label, "normal")
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 4, -2)
        row.label:SetPoint("RIGHT", -6, -2)
        row.label:SetText(e.label)
        row.label:SetTextColor(Color("searchHead", "title"):GetRGB())
    elseif k == "more" or k == "back" then
        Theme.Font(row.label, "small")
        row.label:SetText(e.label)
        row.label:SetTextColor(Color("searchMore", "link"):GetRGB())
    elseif k == "piece" then
        local name = e.label
        if e.set and e.set.name then name = name .. " " .. Grey("(" .. e.set.name .. ")") end
        row.label:SetText(name)
        local state = ns.Owned and e.piece and ns.Owned:GetState(e.piece)
        local W = ns.Widgets
        local c = state and W and W.StateColor and W.StateColor(state)
        row.label:SetTextColor(((c and c.GetRGB) and c or Theme.colors.text):GetRGB())
    else   -- boss / place / npc: name (place), number of sets on the right
        local name = e.label
        if e.sub then name = name .. " " .. Grey("(" .. e.sub .. ")") end
        row.label:SetText(name)
        row.label:SetTextColor(Theme.colors.text:GetRGB())
        row.count:SetText(tostring(e.n or 0))
        row.count:SetTextColor(Color("searchSub", "subtle"):GetRGB())
    end
end

-- The view's one initializer: set rows and result rows share the Button frames.
local function InitAny(row, e)
    if type(e) == "table" and e.gsKind then InitResultRow(row, e) else InitRow(row, e) end
end
SetList.InitElement = InitAny   -- offline tests / pictures draw rows with it

function ResultTooltip(row)
    local e = row.elem
    if not e or e.gsKind == "head" or e.gsKind == "back" then GameTooltip:Hide() return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local sub = Color("searchSub", "subtle")
    if e.gsKind == "more" then
        GameTooltip:SetText(e.label, Theme.colors.title:GetRGB())
        Theme.AddHint(GameTooltip, T("SEARCH_MORE_HINT", "Click: show all"))
    elseif e.gsKind == "piece" then
        if GameTooltip.SetItemByID and e.itemID then
            GameTooltip:SetItemByID(e.itemID)
        else
            GameTooltip:SetText(e.label, Theme.colors.title:GetRGB())
        end
        if e.set then GameTooltip:AddLine(e.set.name, sub:GetRGB()) end
        Theme.AddHint(GameTooltip, T("SEARCH_PIECE_HINT", "Click: open its set and its guide"))
    else
        GameTooltip:SetText(e.label, Theme.colors.title:GetRGB())
        local w = KIND_WORD[e.gsKind]
        if w then GameTooltip:AddLine(T(w[1], w[2]), sub:GetRGB()) end
        if e.sub then GameTooltip:AddLine(e.sub, sub:GetRGB()) end
        local sets = e.sets or {}
        GameTooltip:AddLine(T("SEARCH_SETS_N", "Sets with a piece from here: %d"):format(#sets), Theme.colors.text:GetRGB())
        for i, s in ipairs(sets) do
            if i > 5 then break end
            GameTooltip:AddLine("  " .. s.name, Theme.colors.text:GetRGB())
        end
        Theme.AddHint(GameTooltip, T("SEARCH_SRC_HINT", "Click: show these sets and the first piece's guide"))
    end
    GameTooltip:Show()
end

-- Filter defaults: Core.lua's defaults.filters (ns.FILTER_DEFAULTS). "Only my class"
-- and "Only my faction" are on by default, so they only count as changed when off.
local FALLBACK_DEFAULTS = { class = 0, armor = 0, usable = true, hideComplete = false,
    showRemoved = false, kind = "", myFaction = true, showHidden = false, trackedOnly = false, tier = "" }
local function Defaults() return ns.FILTER_DEFAULTS or FALLBACK_DEFAULTS end
-- Filters this file knows even before Core's defaults list them (DB v2).
local EXTRA_DEFAULTS = { showHidden = false, trackedOnly = false, tier = "" }

local function DiffersFrom(f, k, v)
    if type(v) == "boolean" then return (not f[k]) ~= (not v) end
    return f[k] ~= v and f[k] ~= nil
end

-- True when filter table f differs from the defaults in any key (booleans compared
-- as booleans, so a missing key reads as false).
local function FiltersDiffer(f)
    local d = Defaults()
    for k, v in pairs(d) do
        if DiffersFrom(f, k, v) then return true end
    end
    for k, v in pairs(EXTRA_DEFAULTS) do
        if d[k] == nil and DiffersFrom(f, k, v) then return true end
    end
    return false
end

-- True when any filter differs from its default (the dropdown's reset button shows).
local function FiltersActive()
    return FiltersDiffer(ns.db.filters)
end

-- The one place filters go back to their defaults (menu entry, dropdown reset
-- button, empty-list button). The sort order is not a filter and stays. Doesn't refresh; callers do.
local function ResetFilters()
    local f = ns.db.filters
    local d = Defaults()
    for k, v in pairs(d) do f[k] = v end
    for k, v in pairs(EXTRA_DEFAULTS) do
        if d[k] == nil then f[k] = v end
    end
end

-- Content filter entries (set kinds) in menu order (Core.lua, also used to check saved values).
local KINDS = ns.SET_KINDS or { "d", "r", "p", "c", "w", "f" }
local function KindName(k) return L["KIND_" .. k:upper()] end

-- Sort orders in menu order; unknown saved values sort like "owned".
-- Third field: English fallback for keys part A adds later.
local SORTS = { { "owned", "SORT_OWNED" }, { "closest", "SORT_CLOSEST" }, { "name", "SORT_NAME" },
    { "effort", "SORT_EFFORT", "Least effort" } }
local function SortLabel(s) return L[s[2]] or s[3] or s[1] end

-- Menu entry label with the current choice after it: "Sort: Name" (choice in grey).
local function ChoiceLabel(label, choice)
    if not choice then return label end
    local c = Theme.colors.menuChoice
    return L.MENU_CHOICE:format(label, c:WrapTextInColorCode(choice))
end

-- Names of the current choices (pure; nil = nothing to name).
function SetList.SortChoiceName()
    for _, s in ipairs(SORTS) do
        if s[1] == SetList.SortMode() then return SortLabel(s) end
    end
end

function SetList.ClassName(id)
    if id == 0 then return L.ALL end
    for _, c in ipairs(ns.Data:GetClasses()) do
        if c.id == id then return c.name end
    end
end

function SetList.ArmorChoiceName(id)
    if id == 0 then return L.ALL end
    return ns.Data.ArmorName(id)
end

function SetList.KindChoiceName(kind)
    if (kind or "") == "" then return L.ALL end
    return KindName(kind)
end

-- Class menu and "Only my class" can't both apply (a Mage set on a Warrior = empty list):
-- picking a class turns "Only my class" off; ticking "Only my class" sets Class to All.
function SetList.PickClass(f, id)
    f.class = id
    if id ~= 0 then f.usable = false end
end

function SetList.ToggleUsable(f)
    f.usable = not f.usable
    if f.usable then f.class = 0 end
end

-- Search/filter changed: the list starts from the top again.
local function Changed()
    SetList.fromTop = true
    SetList:Refresh()
    local filter = SetList.filter
    if filter and filter.ValidateResetState then filter:ValidateResetState() end
    -- The settings page shows "Show hidden sets" too (a reset may change it).
    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
end

-- "Show hidden sets" (filter menu; the settings page has the same check box).
function SetList.ToggleShowHidden(f)
    f = f or ns.db.filters
    f.showHidden = not f.showHidden
    Changed()
end

-- Filter menu (Blizzard Menu API). Falls back to a plain button + context menu.
local function SetupMenu(owner, root)
    local f = ns.db.filters

    -- Submenu labels show the current choice; the menu is built again each time it opens.
    local sortMenu = root:CreateButton(ChoiceLabel(L.SORT, SetList.SortChoiceName()))
    for _, s in ipairs(SORTS) do
        sortMenu:CreateRadio(SortLabel(s), function() return SetList.SortMode() == s[1] end,
            function() ns.db.sort = s[1]; Changed() end)
    end
    root:CreateDivider()

    local classMenu = root:CreateButton(ChoiceLabel(L.CLASS, SetList.ClassName(f.class)))
    classMenu:CreateRadio(L.ALL, function() return f.class == 0 end, function() SetList.PickClass(f, 0); Changed() end)
    for _, c in ipairs(ns.Data:GetClasses()) do
        local text = Theme.ClassColor(c.file):WrapTextInColorCode(c.name)
        classMenu:CreateRadio(text, function() return f.class == c.id end,
            function() SetList.PickClass(f, c.id); Changed() end)
    end

    local armorMenu = root:CreateButton(ChoiceLabel(L.ARMOR, SetList.ArmorChoiceName(f.armor)))
    armorMenu:CreateRadio(L.ALL, function() return f.armor == 0 end, function() f.armor = 0; Changed() end)
    for _, a in ipairs(ns.Data:GetArmorTypes()) do
        armorMenu:CreateRadio(a.name, function() return f.armor == a.id end, function() f.armor = a.id; Changed() end)
    end

    local kindMenu = root:CreateButton(ChoiceLabel(L.CONTENT, SetList.KindChoiceName(f.kind)))
    kindMenu:CreateRadio(L.ALL, function() return (f.kind or "") == "" end, function() f.kind = ""; Changed() end)
    for _, k in ipairs(KINDS) do
        kindMenu:CreateRadio(KindName(k), function() return f.kind == k end, function() f.kind = k; Changed() end)
    end

    local tiers = SetList.TierList()
    if #tiers > 0 then
        local cur = (f.tier or "") ~= "" and TierName(f.tier) or L.ALL
        local tierMenu = root:CreateButton(ChoiceLabel(T("TIER", "Tier"), cur))
        tierMenu:CreateRadio(L.ALL, function() return (f.tier or "") == "" end, function() f.tier = ""; Changed() end)
        for _, tag in ipairs(tiers) do
            tierMenu:CreateRadio(TierName(tag), function() return f.tier == tag end, function() f.tier = tag; Changed() end)
        end
    end

    root:CreateDivider()
    if ns.Track then
        root:CreateCheckbox(T("TRACKED_ONLY", "Tracked only"), function() return f.trackedOnly end,
            function() f.trackedOnly = not f.trackedOnly; Changed() end)
    end
    root:CreateCheckbox(L.USABLE, function() return f.usable end, function() SetList.ToggleUsable(f); Changed() end)
    root:CreateCheckbox(L.MY_FACTION, function() return f.myFaction end, function() f.myFaction = not f.myFaction; Changed() end)
    root:CreateCheckbox(L.HIDE_COMPLETE, function() return f.hideComplete end, function() f.hideComplete = not f.hideComplete; Changed() end)
    root:CreateCheckbox(L.SHOW_REMOVED, function() return f.showRemoved end, function() f.showRemoved = not f.showRemoved; Changed() end)
    if ns.Data and ns.Data.IsHidden then
        root:CreateCheckbox(T("SHOW_HIDDEN", "Show hidden sets"), function() return f.showHidden end,
            function() SetList.ToggleShowHidden(f) end)
    end
    root:CreateDivider()
    root:CreateButton(L.RESET_FILTERS, function() ResetFilters(); Changed() end)
end

-- Lines that say why the list is empty: the search words and each filter that hides sets.
-- Returns lines, searchOn, filtersOn (pure: no frames, so it can be tested offline).
-- filtersOn = some filter differs from its default (so "Reset filters" would change it);
-- "Only my class" / "Only my faction" are named when on (they hide sets) but, being
-- defaults, don't set it. "Show removed sets" / "Show hidden sets" show more, so they
-- aren't named (but do set filtersOn, so "Reset filters" offers to turn them off).
function SetList.EmptyReason(search, f)
    local lines = {}
    local searchOn = type(search) == "string" and search:match("%S") ~= nil
    if searchOn then
        lines[#lines + 1] = L.EMPTY_SEARCH:format(search)
    end
    local parts = {}
    if f.class ~= 0 then
        for _, c in ipairs(ns.Data:GetClasses()) do
            if c.id == f.class then parts[#parts + 1] = c.name end
        end
    end
    if f.armor ~= 0 then parts[#parts + 1] = ns.Data.ArmorName(f.armor) or L.ARMOR end
    if type(f.kind) == "string" and f.kind ~= "" then parts[#parts + 1] = KindName(f.kind) or L.CONTENT end
    if type(f.tier) == "string" and f.tier ~= "" then parts[#parts + 1] = TierName(f.tier) end
    if f.trackedOnly then parts[#parts + 1] = T("TRACKED_ONLY", "Tracked only") end
    if f.usable then parts[#parts + 1] = L.USABLE end
    if f.myFaction then parts[#parts + 1] = L.MY_FACTION end
    if f.hideComplete then parts[#parts + 1] = L.HIDE_COMPLETE end
    local filtersOn = FiltersDiffer(f)
    if #parts > 0 then
        lines[#lines + 1] = L.EMPTY_FILTERS:format(table.concat(parts, ", "))
    end
    return lines, searchOn, filtersOn
end

-- Text for the empty-list button (nil = nothing to clear, no button).
function SetList.ClearButtonText(searchOn, filtersOn)
    if searchOn and filtersOn then return L.CLEAR_ALL end
    if searchOn then return L.CLEAR_SEARCH end
    if filtersOn then return L.RESET_FILTERS end
end

-- Empty-list button: clear the search and reset the filters, then refresh once.
function SetList:ClearAll()
    ResetFilters()
    if self.search and (self.search:GetText() or "") ~= "" then
        self:ClearSearch()        -- saves "" and refreshes from the top
    else
        ns.db.search = ""
        self.fromTop = true
        self:Refresh()
    end
    if self.filter and self.filter.ValidateResetState then self.filter:ValidateResetState() end
    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
end

local function BuildEmpty(self, parent, box)
    local e = CreateFrame("Frame", nil, parent)
    e:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -20)
    e:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -20)
    e:SetHeight(120)
    e.title = e:CreateFontString(nil, "OVERLAY")
    Theme.Font(e.title, "disabled")
    e.title:SetPoint("TOP")
    e.title:SetText(L.NO_SETS)
    e.reason = e:CreateFontString(nil, "OVERLAY")
    Theme.Font(e.reason, "small")
    e.reason:SetTextColor(Theme.colors.subtle:GetRGB())
    e.reason:SetPoint("TOPLEFT", e, "TOPLEFT", 0, -22)
    e.reason:SetPoint("TOPRIGHT", e, "TOPRIGHT", 0, -22)
    e.reason:SetJustifyH("CENTER")
    e.reason:SetWordWrap(true)
    e.button = Theme.CreateFrame("Button", nil, e, "button")
    e.button:SetSize(170, 22)
    e.button:SetPoint("TOP", e.reason, "BOTTOM", 0, -10)
    e.button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        SetList:ClearAll()
    end)
    e:Hide()
    self.empty = e
end

function SetList:UpdateEmpty(isEmpty)
    local e = self.empty
    if not e then return end
    if not isEmpty then e:Hide(); return end
    local lines, searchOn, filtersOn = SetList.EmptyReason(ns.db.search, ns.db.filters)
    e.reason:SetText(table.concat(lines, "\n"))
    local text = SetList.ClearButtonText(searchOn, filtersOn)
    if text then
        e.button:SetText(text)
        local w = e.button.GetTextWidth and e.button:GetTextWidth()
        if w and w > 0 then e.button:SetWidth(math.max(120, w + 30)) end
        e.button:Show()
    else
        e.button:Hide()
    end
    e:Show()
end

-- ---------------------------------------------------------------------------
-- Search text, Esc and Ctrl+F (beta.9 part C).
local ESC_NAME = "GearSetSearchEsc"

-- While the box has text, a hidden named frame sits on the Esc stack (W.PushEsc): Esc
-- (Blizzard's CloseSpecialWindows) hides it, which clears the search; the next Esc closes
-- the window as before. Hidden together with the window: only taken off the stack (the
-- text stays) and put back when the window shows again.
local function UpdateEsc()
    local e = SetList.escFrame
    if not e then return end
    e:SetShown((ns.db.search or "") ~= "")
end

local function BuildEscFrame(self, parent)
    local e = CreateFrame("Frame", ESC_NAME, parent)
    e:SetSize(1, 1)
    e:SetPoint("TOPLEFT")
    e:Hide()
    e:SetScript("OnShow", function()
        local W = ns.Widgets
        if W and W.PushEsc then W.PushEsc(ESC_NAME) end
    end)
    e:SetScript("OnHide", function(f)
        local W = ns.Widgets
        if W and W.PopEsc then W.PopEsc(ESC_NAME) end
        if not f:IsShown() then SetList:ClearSearch() end   -- hidden itself (Esc), not with the window
    end)
    self.escFrame = e
    UpdateEsc()
end

-- New search text (box typing, ClearSearch): saved, results start over, list from the top.
function SetList:ApplySearch(text)
    text = text or ""
    if text == ns.db.search and SetList.list then return end
    ns.db.search = text
    SetList.source = nil
    SetList.expanded = {}
    UpdateEsc()
    Changed()
end

function SetList:ClearSearch()
    local box = self.search
    if box and (box:GetText() or "") ~= "" then box:SetText("") end
    self:ApplySearch("")
end

-- Ctrl+F (Main.lua): Sets tab, focus the box, its text selected so typing replaces it.
function SetList:FocusSearch()
    local box = self.search
    if not box then return false end
    local UI = ns.UI
    if UI and UI.CurrentTab and UI:CurrentTab() ~= "sets" and UI.ShowTab then UI:ShowTab("sets") end
    box:SetFocus()
    if box.HighlightText then box:HighlightText() end
    return true
end

local function SearchTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText(T("SEARCH_TIP", "Finds sets, pieces, bosses, places and NPCs."), Theme.colors.title:GetRGB())
    Theme.AddHint(GameTooltip, T("SEARCH_ENTER_HINT", "Enter: open the first result"))
    Theme.AddHint(GameTooltip, T("SEARCH_ESC_HINT", "Esc: clear the search"))
    GameTooltip:Show()
end

function SetList:Build(parent)
    -- Filter button (top right of the panel)
    local filter, tmpl = Theme.CreateFrame("DropdownButton", nil, parent, "filter")
    if filter and tmpl and filter.SetupMenu then
        filter:SetupMenu(SetupMenu)
        if filter.SetDefaultCallback and filter.SetIsDefaultCallback then
            filter:SetIsDefaultCallback(function() return not FiltersActive() end)
            filter:SetDefaultCallback(function() ResetFilters(); Changed() end)
        end
        if filter.SetText and not filter:GetText() then filter:SetText(L.FILTER) end
    else
        if filter then filter:Hide() end
        filter = Theme.CreateFrame("Button", nil, parent, "button")
        filter:SetText(L.FILTER)
        filter:SetScript("OnClick", function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(self, SetupMenu) end
        end)
    end
    filter:SetSize(90, 22)
    filter:SetPoint("TOPRIGHT", -6, -5)
    self.filter = filter

    -- Search box
    local search = Theme.CreateFrame("EditBox", nil, parent, "search")
    search:SetSize(150, 20)
    -- x 15: SearchBoxTemplate's left cap draws 5 px outside the box (Mount journal: 15,-9),
    -- so its visible edge lines up with the row text.
    search:SetPoint("TOPLEFT", 15, -6)
    search:SetPoint("RIGHT", filter, "LEFT", -8, 0)
    search:SetAutoFocus(false)
    if search.Instructions then search.Instructions:SetText(T("SEARCH_BOX", L.SEARCH)) end
    search:SetText(ns.db.search or "")
    search:HookScript("OnTextChanged", function(self)
        SetList:ApplySearch(self:GetText() or "")
    end)
    -- Enter opens the first result (then the box lets go of the keyboard).
    search:HookScript("OnEnterPressed", function(box)
        SetList:ActivateFirst()
        box:ClearFocus()
    end)
    search:HookScript("OnEnter", SearchTooltip)
    search:HookScript("OnLeave", GameTooltip_Hide)
    self.search = search
    BuildEscFrame(self, parent)

    -- Scrolling list
    local box = Theme.CreateFrame("Frame", nil, parent, "scrollBox")
    box:SetPoint("TOPLEFT", 4, -32)
    box:SetPoint("BOTTOMRIGHT", -22, 4)
    local bar = Theme.CreateFrame("EventFrame", nil, parent, "scrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 2)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitAny)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    self.box = box

    BuildEmpty(self, parent, box)
end

-- Complete sets first, then sets with some pieces, then the rest.
-- Inside a group: highest share owned, then most pieces owned, then name order.
-- Counts are worked out once per set before sorting (never in the comparator).
-- Sort keys live in reused file-level tables keyed by set (sets are fixed objects, so
-- they never grow past the number of sets): no new tables per refresh.
local rGroup, rShare, rHave, rMissing, rTotal = {}, {}, {}, {}, {}

local function FillRanks(list)
    for _, s in ipairs(list) do
        local have, total = ns.Owned:SetCount(s)
        rHave[s], rTotal[s] = have, total
        rMissing[s] = total - have
        rShare[s] = total > 0 and have / total or 0
    end
end

local function ByName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
end

local function OwnedFirstLess(a, b)
    local ga, gb = rGroup[a], rGroup[b]
    if ga ~= gb then return ga < gb end
    if rShare[a] ~= rShare[b] then return rShare[a] > rShare[b] end
    if rHave[a] ~= rHave[b] then return rHave[a] > rHave[b] end
    return ByName(a, b)
end

local function SortOwnedFirst(list)
    FillRanks(list)
    for _, s in ipairs(list) do
        local have, total = rHave[s], rTotal[s]
        rGroup[s] = (have >= total and 1) or (have > 0 and 2) or 3
    end
    table.sort(list, OwnedFirstLess)
    return list
end

-- Closest to finishing: sets with some pieces first (fewest missing, then highest share),
-- then untouched sets (fewest pieces), complete sets last; ties by name/key.
local function ClosestLess(a, b)
    local ga, gb = rGroup[a], rGroup[b]
    if ga ~= gb then return ga < gb end
    if ga == 1 then
        if rMissing[a] ~= rMissing[b] then return rMissing[a] < rMissing[b] end
        if rShare[a] ~= rShare[b] then return rShare[a] > rShare[b] end
    elseif ga == 2 then
        if rTotal[a] ~= rTotal[b] then return rTotal[a] < rTotal[b] end
    end
    return ByName(a, b)
end

local function SortClosest(list)
    FillRanks(list)
    for _, s in ipairs(list) do
        local have, total = rHave[s], rTotal[s]
        rGroup[s] = (have >= total and 3) or (have > 0 and 1) or 2
    end
    table.sort(list, ClosestLess)
    return list
end

local function SortName(list)
    table.sort(list, ByName)
    return list
end

-- Least effort first (Data:EffortRank: points for the pieces still needed, complete
-- sets last), then name. Without the effort data it sorts by name.
local rEffort = {}

local function EffortLess(a, b)
    if rEffort[a] ~= rEffort[b] then return rEffort[a] < rEffort[b] end
    return ByName(a, b)
end

local function SortEffort(list)
    local D = ns.Data
    if not (D and D.EffortRank) then return SortName(list) end
    for _, s in ipairs(list) do
        local ok, rank = pcall(D.EffortRank, D, s)
        rank = ok and tonumber(rank)
        rEffort[s] = (rank and rank == rank) and rank or math.huge   -- NaN would break table.sort
    end
    table.sort(list, EffortLess)
    return list
end

local SORTERS = { owned = SortOwnedFirst, closest = SortClosest, name = SortName, effort = SortEffort }

-- The saved sort order ("owned" when missing or unknown).
function SetList.SortMode()
    local mode = ns.db and ns.db.sort
    return SORTERS[mode] and mode or "owned"
end

-- beta.8 filters on top of Data:Filter: tier tag and "Tracked only".
local function ExtraFilter(list, f)
    local tier = type(f.tier) == "string" and f.tier ~= "" and f.tier or nil
    local TR = f.trackedOnly and ns.Track or nil
    if not (tier or TR) then return list end
    local out = {}
    for _, s in ipairs(list) do
        if (not tier or s.tier == tier) and (not TR or TR.Touches(s)) then out[#out + 1] = s end
    end
    return out
end

-- Filtered and sorted list, as shown.
local function BuildList()
    local list = ExtraFilter(ns.Data:Filter(ns.db.search, ns.db.filters), ns.db.filters)
    return SORTERS[SetList.SortMode()](list)
end

-- Sets the filters allow (search left out), sorted: search results come only from these.
local function AllowedSets()
    local list = ExtraFilter(ns.Data:Filter("", ns.db.filters), ns.db.filters)
    return SORTERS[SetList.SortMode()](list)
end

local function SearchWords()
    local S = ns.Search
    return S and S.Words and S.Words(ns.db.search)
end

SetList.expanded = {}   -- result groups opened with "n more" (reset when the text changes)

-- Narrowed to one boss / place / NPC: "Sets with pieces from X (n)", "< All results", its sets
-- (those the filters still allow, in list order).
local function SourceRows(src)
    local allowed, keep = {}, {}
    for _, s in ipairs(AllowedSets()) do allowed[s] = true end
    for _, s in ipairs(src.sets or {}) do
        if allowed[s] then keep[#keep + 1] = s end
    end
    local rows = {
        { gsKind = "head", label = T("SEARCH_FROM", "Sets with pieces from %s (%d)"):format(src.label, #keep) },
        { gsKind = "back", label = T("SEARCH_BACK", "< All results") },
    }
    for _, s in ipairs(keep) do rows[#rows + 1] = s end
    return rows, keep
end

-- Grouped results; a group header only when more than the sets group has results
-- (a plain set-name search looks like the list always did). Returns rows, sets shown.
local function ResultRows()
    local groups = ns.Search.Find(ns.db.search, AllowedSets(), SetList.expanded)
    SetList.groups = groups
    local rows, sets = {}, {}
    local onlySets = #groups == 1 and groups[1].kind == "set"
    for _, g in ipairs(groups) do
        if not onlySets then rows[#rows + 1] = { gsKind = "head", label = g.label, kind = g.kind } end
        for _, it in ipairs(g.items) do
            if it.kind == "set" then
                rows[#rows + 1] = it.set
            else
                it.gsKind = it.kind
                rows[#rows + 1] = it
            end
        end
        if g.kind == "set" then
            for _, it in ipairs(g.all) do sets[#sets + 1] = it.set end
        end
        if g.more > 0 then
            rows[#rows + 1] = { gsKind = "more", kind = g.kind,
                label = T("SEARCH_MORE", "%d more ..."):format(g.more) }
        end
    end
    return rows, sets
end

-- Rows to show and the set list behind them (SelectRelative steps through that list).
local function BuildRows()
    if not SearchWords() then
        SetList.source, SetList.groups = nil, nil
        local list = BuildList()
        return list, list
    end
    if SetList.source then return SourceRows(SetList.source) end
    return ResultRows()
end

local function FirstPieceFrom(set, src)
    local ids = src.itemIDs or {}
    for _, p in ipairs(set.shown or set.pieces or {}) do
        if ids[p.itemID] then return p end
    end
end

-- A result row clicked (or Enter on the first one).
function SetList.Activate(e)
    if type(e) ~= "table" then return false end
    local UI, PL = ns.UI, ns.PieceList
    local k = e.gsKind
    if not k then
        if not e.key then return false end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI:SelectSet(e.key)
        return true
    end
    if k == "piece" and e.set then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI:SelectSet(e.set.key)
        if PL and PL.ShowGuide and e.piece then PL:ShowGuide(e.piece) end
        return true
    elseif SOURCE_KINDS[k] then
        local first = e.sets and e.sets[1]
        if not first then return false end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        SetList.source = e
        SetList.fromTop = true
        UI:SelectSet(first.key)
        local piece = FirstPieceFrom(first, e)
        if piece and PL and PL.ShowGuide then PL:ShowGuide(piece) end
        return true
    elseif k == "more" then
        SetList.expanded[e.kind] = true
        SetList:Refresh()
        return true
    elseif k == "back" then
        SetList.source = nil
        SetList.fromTop = true
        SetList:Refresh()
        return true
    end
    return false
end

-- Enter in the search box: open the first row that does something.
function SetList:ActivateFirst()
    for _, e in ipairs(self.rows or {}) do
        local k = type(e) == "table" and e.gsKind
        if not k or k == "piece" or SOURCE_KINDS[k] then return SetList.Activate(e) end
    end
    return false
end

-- Tier tags that have sets, in the usual order (unknown tags after, by name).
local TIER_ORDER = { "D1", "D2", "T1", "T2", "T3", "ZG", "AQ20", "AQ40", "PvP" }
function SetList.TierList()
    local have = {}
    for _, s in ipairs(ns.Data:GetSets()) do
        if type(s.tier) == "string" and s.tier ~= "" then have[s.tier] = true end
    end
    local out = {}
    for _, t in ipairs(TIER_ORDER) do
        if have[t] then out[#out + 1] = t; have[t] = nil end
    end
    local extra = {}
    for t in pairs(have) do extra[#extra + 1] = t end
    table.sort(extra)
    for _, t in ipairs(extra) do out[#out + 1] = t end
    return out
end

-- Progress page bar clicked: the Sets tab with only that content kind or tier.
function SetList.ShowGroup(kind, tier)
    local f = ns.db.filters
    f.kind = kind or ""
    f.tier = tier or ""
    if ns.UI and ns.UI.ShowTab then ns.UI:ShowTab("sets") end
    Changed()
end

local function IndexOf(list, key)
    if not (list and key) then return nil end
    for i, s in ipairs(list) do
        if s.key == key then return i end
    end
end

-- Bring the chosen set's row into view (only moves when it is outside the view).
function SetList:ScrollToSelected()
    local box = self.box
    local i = IndexOf(self.list, ns.db.lastSet)
    if not (box and i and box.ScrollToElementData) then return end
    -- Search results may show only some of the sets (5 per group): only scroll to a shown row.
    local set, shown = self.list[i], false
    for _, e in ipairs(self.rows or self.list) do
        if e == set then shown = true break end
    end
    if not shown then return end
    local align = ScrollBoxConstants and ScrollBoxConstants.AlignNearest
    pcall(box.ScrollToElementData, box, set, align)
end

function SetList:Refresh()
    if not self.box then return end
    -- Window hidden: skip the work; OnShow refreshes everything.
    if not (ns.UI and ns.UI:IsShown()) then return end
    local rows, list = BuildRows()
    self.list, self.rows = list, rows
    local fromTop = self.fromTop
    self.fromTop = nil
    local consts = ScrollBoxConstants
    local retain   -- DiscardScrollPosition is false, so no "a and b or c" here
    if consts then
        if fromTop then retain = consts.DiscardScrollPosition else retain = consts.RetainScrollPosition end
    end
    self.box:SetDataProvider(CreateDataProvider(rows), retain)
    self:UpdateEmpty(#rows == 0)
    -- First open: pick the first set so the window is never blank.
    if not ns.Data:GetSet(ns.db.lastSet) and list[1] then
        ns.db.lastSet = list[1].key
        ns.UI:RefreshAll()
        return
    end
    -- Keep the chosen set in view when it is new or moved in the order (owned-first
    -- sort after a bag change). Not after a search/filter change: those start at the top.
    local key, index = ns.db.lastSet, IndexOf(list, ns.db.lastSet)
    if not fromTop and (key ~= self.shownKey or index ~= self.shownIndex) then
        self:ScrollToSelected()
    end
    self.shownKey, self.shownIndex = key, index
end

-- Previous (delta < 0) or next (delta > 0) set in the order shown, wrapping around at
-- the ends. If the chosen set is filtered out, next = first and previous = last.
-- Selects it (which scrolls it into view) and returns its key, or nil if the list is empty.
function SetList:SelectRelative(delta)
    local list = self.list
    if not list then
        list = BuildList()
        self.list = list
    end
    local n = #list
    if n == 0 or not delta or delta == 0 then return nil end
    local i = IndexOf(list, ns.db.lastSet)
    if i then
        i = (i - 1 + delta) % n + 1
    else
        i = delta > 0 and 1 or n
    end
    local key = list[i].key
    ns.UI:SelectSet(key)
    self:ScrollToSelected()
    return key
end
