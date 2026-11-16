-- Gear Set: left panel - search box, filter menu and the scrolling set list.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local SetList = {}
ns.SetList = SetList

local ROW_H = 22

local function SetTooltip(row)
    local set = row.set
    if not set then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(set.name, Theme.colors.title:GetRGB())
    local armor = ns.Data.ArmorName(set.armor)
    if armor then GameTooltip:AddLine(armor, Theme.colors.armorLine:GetRGB()) end
    if set.classMask == 0 then
        GameTooltip:AddLine(L.ALL_CLASSES, Theme.colors.subtle:GetRGB())
    else
        local names = {}
        for _, c in ipairs(ns.Data:GetClasses()) do
            if ns.Data.SetHasClass(set, c.id) then
                names[#names + 1] = Theme.ClassColor(c.file):WrapTextInColorCode(c.name)
            end
        end
        local r, g, b = Theme.colors.text:GetRGB()
        GameTooltip:AddLine(table.concat(names, ", "), r, g, b, true)
    end
    local have, total = ns.Owned:SetCount(set)
    GameTooltip:AddLine(L.HAVE_COUNT:format(have, total), Theme.CountColor(have, total))
    GameTooltip:Show()
end

local function InitRow(row, set)
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
        row.label = row:CreateFontString(nil, "OVERLAY")
        Theme.Font(row.label, "text")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if self.set then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                ns.UI:SelectSet(self.set.key)
            end
        end)
        row:SetScript("OnEnter", SetTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end
    row.set = set
    row.label:SetText(set.name)
    local have, total = ns.Owned:SetCount(set)
    row.count:SetText(("%d/%d"):format(have, total))
    row.count:SetTextColor(Theme.CountColor(have, total))
    row.sel:SetShown(set.key == ns.db.lastSet)
end

-- Filter defaults (same as Core.lua's defaults): "Only my class" is on by default,
-- so it only counts as a changed filter when it is turned off.
local DEFAULT_USABLE = true

-- True when any filter differs from its default (the dropdown's reset button shows).
local function FiltersActive()
    local f = ns.db.filters
    return f.class ~= 0 or f.armor ~= 0 or (not f.usable) ~= (not DEFAULT_USABLE) or f.hideComplete
end

-- The one place filters go back to "show everything" (menu entry, dropdown reset
-- button, empty-list button). Doesn't refresh; callers do.
local function ResetFilters()
    local f = ns.db.filters
    f.class, f.armor, f.usable, f.hideComplete = 0, 0, DEFAULT_USABLE, false
end

-- Search/filter changed: the list starts from the top again.
local function Changed()
    SetList.fromTop = true
    SetList:Refresh()
    local filter = SetList.filter
    if filter and filter.ValidateResetState then filter:ValidateResetState() end
end

-- Filter menu (Blizzard Menu API). Falls back to a plain button + context menu.
local function SetupMenu(owner, root)
    local f = ns.db.filters

    local classMenu = root:CreateButton(L.CLASS)
    classMenu:CreateRadio(L.ALL, function() return f.class == 0 end, function() f.class = 0; Changed() end)
    for _, c in ipairs(ns.Data:GetClasses()) do
        local text = Theme.ClassColor(c.file):WrapTextInColorCode(c.name)
        classMenu:CreateRadio(text, function() return f.class == c.id end, function() f.class = c.id; Changed() end)
    end

    local armorMenu = root:CreateButton(L.ARMOR)
    armorMenu:CreateRadio(L.ALL, function() return f.armor == 0 end, function() f.armor = 0; Changed() end)
    for _, a in ipairs(ns.Data:GetArmorTypes()) do
        armorMenu:CreateRadio(a.name, function() return f.armor == a.id end, function() f.armor = a.id; Changed() end)
    end

    root:CreateDivider()
    root:CreateCheckbox(L.USABLE, function() return f.usable end, function() f.usable = not f.usable; Changed() end)
    root:CreateCheckbox(L.HIDE_COMPLETE, function() return f.hideComplete end, function() f.hideComplete = not f.hideComplete; Changed() end)
    root:CreateDivider()
    root:CreateButton(L.RESET_FILTERS, function() ResetFilters(); Changed() end)
end

-- Lines that say why the list is empty: the search words and each filter that hides sets.
-- Returns lines, searchOn, filtersOn (pure: no frames, so it can be tested offline).
-- filtersOn = some filter differs from its default (so "Reset filters" would change it);
-- "Only my class" is named when on (it hides sets) but, being the default, doesn't set it.
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
    if f.usable then parts[#parts + 1] = L.USABLE end
    if f.hideComplete then parts[#parts + 1] = L.HIDE_COMPLETE end
    local filtersOn = f.class ~= 0 or f.armor ~= 0 or f.hideComplete
        or (not f.usable) ~= (not DEFAULT_USABLE)
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
        self.search:SetText("")   -- OnTextChanged saves "" and refreshes from the top
    else
        ns.db.search = ""
        self.fromTop = true
        self:Refresh()
    end
    if self.filter and self.filter.ValidateResetState then self.filter:ValidateResetState() end
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
    search:SetPoint("TOPLEFT", 12, -6)
    search:SetPoint("RIGHT", filter, "LEFT", -8, 0)
    search:SetAutoFocus(false)
    if search.Instructions then search.Instructions:SetText(L.SEARCH) end
    search:SetText(ns.db.search or "")
    search:HookScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text == ns.db.search and SetList.list then return end
        ns.db.search = text
        Changed()
    end)
    self.search = search

    -- Scrolling list
    local box = Theme.CreateFrame("Frame", nil, parent, "scrollBox")
    box:SetPoint("TOPLEFT", 4, -32)
    box:SetPoint("BOTTOMRIGHT", -22, 4)
    local bar = Theme.CreateFrame("EventFrame", nil, parent, "scrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 2)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    self.box = box

    BuildEmpty(self, parent, box)
end

-- Complete sets first, then sets with some pieces, then the rest.
-- Inside a group: highest share owned, then most pieces owned, then name order.
-- Counts are worked out once per set before sorting (never in the comparator).
local function SortOwnedFirst(list)
    local rank = {}
    for _, s in ipairs(list) do
        local have, total = ns.Owned:SetCount(s)
        local group = (have >= total and 1) or (have > 0 and 2) or 3
        rank[s] = { group, total > 0 and have / total or 0, have }
    end
    table.sort(list, function(a, b)
        local ra, rb = rank[a], rank[b]
        if ra[1] ~= rb[1] then return ra[1] < rb[1] end
        if ra[2] ~= rb[2] then return ra[2] > rb[2] end
        if ra[3] ~= rb[3] then return ra[3] > rb[3] end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    return list
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
    local align = ScrollBoxConstants and ScrollBoxConstants.AlignNearest
    pcall(box.ScrollToElementData, box, self.list[i], align)
end

function SetList:Refresh()
    if not self.box then return end
    -- Window hidden: skip the work; OnShow refreshes everything.
    if not (ns.UI and ns.UI:IsShown()) then return end
    local list = SortOwnedFirst(ns.Data:Filter(ns.db.search, ns.db.filters))
    self.list = list
    local fromTop = self.fromTop
    self.fromTop = nil
    local consts = ScrollBoxConstants
    local retain   -- DiscardScrollPosition is false, so no "a and b or c" here
    if consts then
        if fromTop then retain = consts.DiscardScrollPosition else retain = consts.RetainScrollPosition end
    end
    self.box:SetDataProvider(CreateDataProvider(list), retain)
    self:UpdateEmpty(#list == 0)
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
        list = SortOwnedFirst(ns.Data:Filter(ns.db.search, ns.db.filters))
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
