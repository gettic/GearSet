-- Gear Set: left panel - search box, filter menu and the scrolling set list.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local SetList = {}
ns.SetList = SetList

local ROW_H = 22

local function CountColor(have, total)
    if total > 0 and have >= total then return Theme.colors.have end
    if have > 0 then return Theme.colors.partial end
    return Theme.colors.none
end

local function SetTooltip(row)
    local set = row.set
    if not set then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(set.name, 1, 1, 1)
    local armor = ns.Data.ArmorName(set.armor)
    if armor then GameTooltip:AddLine(armor, 1, 0.82, 0) end
    if set.classMask == 0 then
        GameTooltip:AddLine(L.ALL_CLASSES, 0.8, 0.8, 0.8)
    else
        local names = {}
        for _, c in ipairs(ns.Data:GetClasses()) do
            if ns.Data.SetHasClass(set, c.id) then
                names[#names + 1] = Theme.ClassColor(c.file):WrapTextInColorCode(c.name)
            end
        end
        GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
    end
    local have, total = ns.Owned:SetCount(set)
    GameTooltip:AddLine(L.HAVE_COUNT:format(have, total), 1, 1, 1)
    GameTooltip:Show()
end

local function InitRow(row, set)
    if not row.gsInit then
        row.gsInit = true
        row:SetHeight(ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        Theme.SetAtlasOr(row.hl, Theme.art.rowHighlight.atlas, Theme.art.rowHighlight.file)
        row.hl:SetBlendMode("ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        Theme.SetAtlasOr(row.sel, Theme.art.rowSelect.atlas, Theme.art.rowSelect.file)
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
    row.count:SetTextColor(CountColor(have, total):GetRGB())
    row.sel:SetShown(set.key == ns.db.lastSet)
end

-- Filter menu (Blizzard Menu API). Falls back to a plain button + context menu.
local function SetupMenu(owner, root)
    local f = ns.db.filters
    local function Changed() SetList:Refresh() end

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
    root:CreateButton(L.RESET_FILTERS, function()
        f.class, f.armor, f.usable, f.hideComplete = 0, 0, false, false
        Changed()
    end)
end

local function FiltersActive()
    local f = ns.db.filters
    return f.class ~= 0 or f.armor ~= 0 or f.usable or f.hideComplete
end

function SetList:Build(parent)
    -- Filter button (top right of the panel)
    local filter, tmpl = Theme.CreateFrame("DropdownButton", nil, parent, "filter")
    if filter and tmpl and filter.SetupMenu then
        filter:SetupMenu(SetupMenu)
        if filter.SetDefaultCallback and filter.SetIsDefaultCallback then
            filter:SetIsDefaultCallback(function() return not FiltersActive() end)
            filter:SetDefaultCallback(function()
                local f = ns.db.filters
                f.class, f.armor, f.usable, f.hideComplete = 0, 0, false, false
                SetList:Refresh()
            end)
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
        ns.db.search = self:GetText() or ""
        SetList:Refresh()
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

    self.empty = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.empty, "disabled")
    self.empty:SetPoint("TOP", box, "TOP", 0, -20)
    self.empty:SetText(L.NO_SETS)
    self.empty:Hide()
end

function SetList:Refresh()
    if not self.box then return end
    local list = ns.Data:Filter(ns.db.search, ns.db.filters)
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.box:SetDataProvider(CreateDataProvider(list), retain)
    self.empty:SetShown(#list == 0)
    -- First open: pick the first set so the window is never blank.
    if not ns.Data:GetSet(ns.db.lastSet) and list[1] then
        ns.db.lastSet = list[1].key
        ns.UI:RefreshAll()
    end
end
