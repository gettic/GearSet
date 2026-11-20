-- Gear Set: dungeon checklist (1.1 beta.1, plans\v1.1.0\plan.md sec. 3). A small movable window
-- that opens by itself inside a dungeon or raid where this character still needs a set piece:
-- bosses in kill order with the pieces they drop, ticked green once the piece reaches your bags.
-- ToS (plans\v1.1.0\tos-check.md): W3 the frame is only created out of combat (showing it and
-- changing its text in combat is fine), no OnUpdate, bag events only while it is shown; it never
-- targets, marks, moves or sets a waypoint. W4 ticks come from bags (Owned), never combat data.
-- W8 names are only the user's own saved characters.
local _, ns = ...
local Theme, W = ns.Theme, ns.Widgets

local Tracker = {}
ns.Tracker = Tracker

local function L(key, fallback)
    local v = ns.L and ns.L[key]
    if v == nil then return fallback end
    return v
end

local function Sizes()
    local s = Theme.sizes and Theme.sizes.tracker
    if type(s) ~= "table" then s = {} end
    return s.width or 240, s.head or 26, s.row or 14, s.maxRows or 12, s.pad or 6, s.indent or 18, s.button or 18
end

-- The smaller layout numbers (ui-b1 job A), with fallbacks if a theme leaves them out.
local function Extra()
    local s = Theme.sizes and Theme.sizes.tracker
    if type(s) ~= "table" then s = {} end
    return { fold = s.fold or 16, titleX = s.titleX or 7, tickX = s.tickX or 4, viaIndent = s.viaIndent or 4,
        countGap = s.countGap or 4 }
end

local function DB()
    local db = ns.db
    local t = db and db.tracker
    if type(t) ~= "table" then return nil end
    if type(t.skip) ~= "table" then t.skip = {} end
    return t
end

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function InCombat() return InCombatLockdown ~= nil and InCombatLockdown() end

-- ---------------------------------------------------------------------------
-- Where we are: inside a 5-man dungeon or a raid -> name, mapID, key; else nil.
function Tracker.Where()
    local IsInInstance, GetInstanceInfo = _G.IsInInstance, _G.GetInstanceInfo
    if type(IsInInstance) ~= "function" then return nil end
    local okI, inInst, itype = pcall(IsInInstance)
    if not okI or not inInst or Secret(itype) or (itype ~= "party" and itype ~= "raid") then return nil end
    if type(GetInstanceInfo) ~= "function" then return nil end
    local ok, name, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
    if not ok or Secret(name) or Secret(mapID) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    mapID = tonumber(mapID)
    if mapID and mapID <= 0 then mapID = nil end
    local key = mapID and ("m" .. mapID) or ("n" .. name)
    return name, mapID, key
end

-- ---------------------------------------------------------------------------
-- Frame
local rows, rowUsed = {}, 0

-- The row buttons in use (selftest).
function Tracker.Rows()
    local out = {}
    for i = 1, rowUsed do out[i] = rows[i] end
    return out
end

local function SavePosition(f)
    local t = DB()
    if not t then return end
    local p, _, rp, x, y = f:GetPoint(1)
    if p then t.point = { p, rp, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
end

local function RestorePosition(f)
    f:ClearAllPoints()
    local t = DB()
    local p = t and t.point
    if p and ns.ValidPoint and ns.ValidPoint(p)
        and pcall(f.SetPoint, f, p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0) then
        return
    end
    f:SetPoint("RIGHT", UIParent, "RIGHT", -240, 120)
end

local function HeaderTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L("TITLE", "Gear Set"), 1, 1, 1)
    local v = Tracker.testView or Tracker.view
    if v and v.title then GameTooltip:AddLine(tostring(v.title), Theme.colors.trackerHead:GetRGB()) end
    Theme.AddHint(GameTooltip, L("TRACKER_TIP_HINT", "Drag: move. Right-click: options."))
    GameTooltip:Show()
end

local function ItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, itemID)
        if ok and type(n) == "string" and n ~= "" and not Secret(n) then return n end
    end
    return ("Item %d"):format(itemID)
end

local function RowTooltip(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if e.kind == "piece" or e.kind == "via" then
        GameTooltip:SetItemByID(e.piece.itemID)
        if e.piece.via then
            GameTooltip:AddLine(L("TRACKER_VIA", "for %s"):format(e.piece.via), Theme.colors.trackerSkip:GetRGB())
        end
        if e.piece.later then GameTooltip:AddLine(L("TRACKER_SKIP", "not out yet"), Theme.colors.trackerSkip:GetRGB()) end
        if e.piece.alts and #e.piece.alts > 0 then
            GameTooltip:AddLine(L("TRACKER_ALTS", "Also needed by: %s"):format(table.concat(e.piece.alts, ", ")),
                Theme.colors.trackerSkip:GetRGB())
        end
    elseif e.kind == "boss" or e.kind == "skip" then
        local b = e.boss
        GameTooltip:SetText(b.trash and L("TRACKER_TRASH", "Other enemies") or b.label, Theme.colors.trackerBoss:GetRGB())
        if b.wing then GameTooltip:AddLine(L("TRACKER_WING", "Wing: %s"):format(b.wing), 1, 1, 1, true) end
        for _, p in ipairs(b.pieces) do
            local c = p.got and Theme.colors.trackerGot or ((p.mine and not p.later) and Theme.colors.trackerNeed or Theme.colors.trackerSkip)
            local text = ItemName(p.itemID)
            if p.alts and #p.alts > 0 then text = text .. " - " .. table.concat(p.alts, ", ") end
            GameTooltip:AddLine(text, c:GetRGB())
        end
    else
        GameTooltip:Hide()
        return
    end
    GameTooltip:Show()
end

local function TakeRow(f)
    rowUsed = rowUsed + 1
    local r = rows[rowUsed]
    if not r then
        local _, _, rowH = Sizes()
        r = CreateFrame("Button", nil, f)
        r:SetHeight(rowH)
        r.tick = r:CreateTexture(nil, "ARTWORK")
        local tick = Theme.art.tick or {}
        r.tick:SetSize(tick.size or 12, tick.size or 12)
        if not Theme.SetArt(r.tick, tick) and not tick.file then r.tick:SetColorTexture(unpack(tick.fallback or { 0.1, 1, 0.1, 1 })) end
        r.name = r:CreateFontString(nil, "OVERLAY")
        Theme.Font(r.name, "trackerLine")
        r.name:SetJustifyH("LEFT")
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.extra = r:CreateFontString(nil, "OVERLAY")
        Theme.Font(r.extra, "trackerLine")
        r.extra:SetJustifyH("RIGHT")
        if r.extra.SetWordWrap then r.extra:SetWordWrap(false) end
        r.extra:SetTextColor(Theme.colors.trackerSkip:GetRGB())
        r:SetScript("OnEnter", RowTooltip)
        r:SetScript("OnLeave", GameTooltip_Hide)
        rows[rowUsed] = r
    end
    r:Show()
    return r
end

local function HeaderMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        Tracker:SetCollapsed(not Tracker:IsCollapsed())
        return
    end
    pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
        if root.CreateTitle then root:CreateTitle(Tracker.title or L("TITLE", "Gear Set")) end
        root:CreateButton(Tracker:IsCollapsed() and L("TRACKER_EXPAND", "Expand") or L("TRACKER_COLLAPSE", "Collapse"),
            function() Tracker:SetCollapsed(not Tracker:IsCollapsed()) end)
        root:CreateButton(L("TRACKER_CLOSE_HERE", "Close until I leave"), function() Tracker:CloseHere() end)
        root:CreateButton(L("TRACKER_SKIP_HERE", "Don't show in this instance"), function() Tracker:SkipHere() end)
        root:CreateButton(L("TRACKER_SETTINGS", "Settings"), function()
            if ns.Settings and ns.Settings.Open then ns.Settings:Open() end
        end)
    end)
end

-- Fold button art: the Objective Tracker's atlases (normal + pressed; highlight set once in
-- Build), else the +/- files on `icon`, else a "+"/"-" text.
local function SetExpandArt(btn, collapsed)
    local art = Theme.art.trackerFold or {}
    if btn.gsAtlas then
        btn:SetNormalAtlas(collapsed and art.expand or art.collapse)
        local pressed = collapsed and art.expandPressed or art.collapsePressed
        if Theme.AtlasExists(pressed) then btn:SetPushedAtlas(pressed) end
        btn.icon:Hide(); btn.text:Hide()
        return
    end
    local file = collapsed and art.plus or art.minus
    local ok = file and Theme.TryTexture and Theme.TryTexture(btn.icon, file)
    if not ok then btn.icon:Hide(); btn.text:SetText(collapsed and "+" or "-"); btn.text:Show()
    else btn.icon:Show(); btn.text:Hide() end
end

function Tracker:Build()
    if self.frame then return self.frame end
    if InCombat() then return nil end   -- W3: created out of combat only
    local width, headH, _, _, pad, _, btnSize = Sizes()
    local f = CreateFrame("Frame", "GearSetTracker", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(width, headH)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:Hide()
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(Theme.colors.trackerBg:GetRGBA())

    local head = CreateFrame("Button", nil, f)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(headH)
    head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() if not InCombat() then f:StartMoving() end end)
    head:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePosition(f) end)
    head:SetScript("OnClick", function(btn, button) if button == "RightButton" then HeaderMenu(btn) end end)
    head:SetScript("OnEnter", HeaderTooltip)
    head:SetScript("OnLeave", GameTooltip_Hide)
    f.head = head

    local x = Extra()
    -- Header band (Objective Tracker art) behind the title; without it, a tinted divider under it.
    local ha = Theme.art.trackerHeader or {}
    f.band = head:CreateTexture(nil, "BACKGROUND")
    f.band:SetPoint("LEFT", head, "LEFT", 0, 0)
    local bandAtlas = Theme.SetArt(f.band, { atlases = ha.atlases })
    f.band:SetSize(width, headH)
    f.band:SetShown(bandAtlas ~= nil)
    f.bandAtlas = bandAtlas

    local close = Theme.CreateFrame("Button", nil, head, "trackerClose")
    close:SetSize(btnSize, btnSize)
    close:SetPoint("RIGHT", head, "RIGHT", -2, 0)
    if not (close.GetNormalTexture and close:GetNormalTexture()) then
        local xs = close:CreateFontString(nil, "OVERLAY")
        Theme.Font(xs, "normal")
        xs:SetPoint("CENTER")
        xs:SetText("x")
    end
    close:SetScript("OnClick", function() Tracker:CloseHere() end)
    f.close = close

    local fa = Theme.art.trackerFold or {}
    local fold = CreateFrame("Button", nil, head)
    fold:SetSize(x.fold, x.fold)
    fold:SetPoint("RIGHT", close, "LEFT", 0, 0)
    fold.icon = fold:CreateTexture(nil, "ARTWORK")
    local es = fa.fileSize or 14
    fold.icon:SetSize(es, es)
    fold.icon:SetPoint("CENTER")
    fold.text = fold:CreateFontString(nil, "OVERLAY")
    Theme.Font(fold.text, "normal")
    fold.text:SetPoint("CENTER")
    fold.gsAtlas = Theme.AtlasExists(fa.collapse) and Theme.AtlasExists(fa.expand) or nil
    if fold.gsAtlas and Theme.AtlasExists(fa.highlight) then
        fold:SetHighlightAtlas(fa.highlight, "ADD")
    elseif fa.hilight then
        fold:SetHighlightTexture(fa.hilight, "ADD")
    end
    fold:SetScript("OnClick", function() Tracker:SetCollapsed(not Tracker:IsCollapsed()) end)
    f.fold = fold

    -- "3 left": its own right-aligned text, shown open and collapsed.
    f.count = head:CreateFontString(nil, "OVERLAY")
    Theme.Font(f.count, "trackerLine")
    f.count:SetPoint("RIGHT", fold, "LEFT", -x.countGap, 0)
    f.count:SetJustifyH("RIGHT")
    if f.count.SetWordWrap then f.count:SetWordWrap(false) end
    f.count:SetTextColor(Theme.colors.trackerCount:GetRGB())

    -- The instance name only ("Gear Set" is in the header tooltip).
    f.title = head:CreateFontString(nil, "OVERLAY")
    Theme.Font(f.title, "trackerHead")
    f.title:SetPoint("LEFT", head, "LEFT", x.titleX, 0)
    f.title:SetPoint("RIGHT", f.count, "LEFT", -2, 0)
    f.title:SetJustifyH("LEFT")
    if f.title.SetWordWrap then f.title:SetWordWrap(false) end
    f.title:SetTextColor(Theme.colors.trackerHead:GetRGB())

    f.line = f:CreateTexture(nil, "ARTWORK")
    f.line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", pad, 0)
    f.line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -pad, 0)
    Theme.SetDivider(f.line, { atlas = ha.divider, color = ha.color })
    if Theme.AtlasExists(ha.divider) and ha.tint then f.line:SetVertexColor(unpack(ha.tint)) end

    RestorePosition(f)
    self.frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- Drawing
local function Lines(view, maxRows)
    local out = {}
    for _, b in ipairs(view.bosses or {}) do
        out[#out + 1] = { kind = "boss", boss = b }
        if b.skipped then
            out[#out + 1] = { kind = "skip", boss = b }   -- "not out yet" on its own grey row
        else
            for _, p in ipairs(b.pieces) do
                out[#out + 1] = { kind = "piece", piece = p, boss = b }
                -- hand-in item: "for <token>" as a second grey line (needed, out-now pieces only)
                if p.via and p.mine and not p.got and not p.later then
                    out[#out + 1] = { kind = "via", piece = p, boss = b }
                end
            end
        end
    end
    local more = 0
    if maxRows and #out > maxRows then
        more = #out - (maxRows - 1)
        for i = #out, maxRows, -1 do out[i] = nil end
        out[#out + 1] = { kind = "more", n = more }
    end
    return out, more
end
Tracker.Lines = Lines

-- Pieces still needed (out now, not got) in a view.
function Tracker.LeftCount(view)
    local n = 0
    for _, b in ipairs(view and view.bosses or {}) do
        for _, p in ipairs(b.pieces) do
            if p.mine and not p.later and not p.got then n = n + 1 end
        end
    end
    return n
end

local refreshPending
local function OnItemLoaded()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.2, function()
        refreshPending = nil
        if Tracker.frame and Tracker.frame:IsShown() then Tracker:Render() end
    end)
end

function Tracker:Render()
    local f = self.frame
    local view = self.testView or self.view
    if not (f and view) then return end
    local width, headH, rowH, maxRows, pad, indent = Sizes()
    for i = 1, rowUsed do rows[i]:Hide(); rows[i].entry = nil end
    rowUsed = 0
    local x = Extra()
    local left = Tracker.LeftCount(view)
    self.title = L("TRACKER_TITLE", "Gear Set - %s"):format(tostring(view.title or "?"))
    local collapsed = self:IsCollapsed()
    f.count:SetText(L("TRACKER_LEFT", "%d left"):format(left))
    f.title:SetText(tostring(view.title or "?"))
    SetExpandArt(f.fold, collapsed)
    f.line:SetShown(not collapsed and not f.bandAtlas)
    if collapsed then
        f:SetSize(width, headH)
        return
    end
    local lines = Lines(view, maxRows)
    local y = -(headH + 2)
    if #lines == 0 then
        local r = TakeRow(f)
        r.entry = { kind = "note" }
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y)
        r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, y)
        r.tick:Hide()
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.name:SetText(L("TRACKER_NONE", "Nothing you need drops here."))
        r.name:SetTextColor(Theme.colors.trackerSkip:GetRGB())
        r.extra:SetText("")
        y = y - rowH
    end
    for _, e in ipairs(lines) do
        local r = TakeRow(f)
        r.entry = e
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y)
        r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, y)
        r.name:ClearAllPoints()
        r.extra:ClearAllPoints()
        r.extra:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.tick:ClearAllPoints()
        r.gsItem = nil
        if e.kind == "boss" then
            local b = e.boss
            r.tick:Hide()
            r.name:SetPoint("LEFT", r, "LEFT", 0, 0)
            r.name:SetPoint("RIGHT", r.extra, "LEFT", -4, 0)
            r.name:SetText(b.trash and L("TRACKER_TRASH", "Other enemies") or b.label)
            r.name:SetTextColor(Theme.colors.trackerBoss:GetRGB())
            r.extra:SetText("")
        elseif e.kind == "skip" or e.kind == "via" then
            r.tick:Hide()
            local ind = indent + (e.kind == "via" and x.viaIndent or 0)
            r.name:SetPoint("LEFT", r, "LEFT", ind, 0)
            r.name:SetPoint("RIGHT", r, "RIGHT", 0, 0)
            if e.kind == "skip" then r.name:SetText(L("TRACKER_SKIP", "not out yet"))
            else r.name:SetText(L("TRACKER_VIA", "for %s"):format(e.piece.via)) end
            r.name:SetTextColor(Theme.colors.trackerSkip:GetRGB())
            r.extra:SetText("")
        elseif e.kind == "piece" then
            local p = e.piece
            r.tick:SetPoint("LEFT", r, "LEFT", x.tickX, 0)
            r.tick:SetShown(p.got == true)
            r.name:SetPoint("LEFT", r, "LEFT", indent, 0)
            r.name:SetPoint("RIGHT", r.extra, "LEFT", -4, 0)
            if W and W.FillItem then W.FillItem(r, p.itemID, OnItemLoaded) else r.name:SetText(ItemName(p.itemID)) end
            local c
            if p.got then c = Theme.colors.trackerGot
            elseif p.later or not p.mine then c = Theme.colors.trackerSkip
            else c = Theme.colors.trackerNeed end
            if p.got or p.later or not p.mine then r.name:SetTextColor(c:GetRGB()) end
            -- the tick + green say "got it"; "for:" has its own line
            local extra = ""
            if p.later and not p.got then extra = L("TRACKER_SKIP", "not out yet")
            elseif not p.mine and p.alts then extra = table.concat(p.alts, ", ") end
            r.extra:SetText(extra)
        else
            r.tick:Hide()
            r.name:SetPoint("LEFT", r, "LEFT", indent, 0)
            r.name:SetPoint("RIGHT", r, "RIGHT", 0, 0)
            r.name:SetText(L("TRACKER_MORE", "+%d more"):format(e.n or 0))
            r.name:SetTextColor(Theme.colors.trackerSkip:GetRGB())
            r.extra:SetText("")
        end
        -- the extra text takes at most half the row
        local w = r.extra:GetStringWidth() or 0
        r.extra:SetWidth(math.min(w + 4, (width - 2 * pad) / 2))   -- +4: rounding slack
        y = y - rowH
    end
    f:SetSize(width, -y + pad)
end

-- ---------------------------------------------------------------------------
-- State
Tracker.entered = {}

function Tracker:IsCollapsed()
    if self.testView then return false end   -- /gs selftest checks the rows even when folded
    local t = DB()
    return t ~= nil and t.collapsed == true
end

function Tracker:SetCollapsed(v)
    local t = DB()
    if t then t.collapsed = v and true or false end
    self:Render()
end

function Tracker:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

local events
local function Listen(on)
    if not events then return end
    if on then
        if ns.SafeRegister then ns.SafeRegister(events, "BAG_UPDATE_DELAYED") end
    else
        pcall(events.UnregisterEvent, events, "BAG_UPDATE_DELAYED")
    end
end

function Tracker:Hide()
    if self.frame then self.frame:Hide() end
    Listen(false)
end

-- Left the instance (or not in one): everything per-instance is forgotten.
function Tracker:Leave()
    self.key, self.view, self.closedFor, self.manual = nil, nil, nil, nil
    wipe(self.entered)
    self:Hide()
end

-- Should the checklist be open for this view?
function Tracker.Wanted(view, manual)
    if manual then return true end
    local t = DB()
    if t and t.auto == false then return false end
    if not view then return false end
    if view.need > 0 then return true end
    for _, b in ipairs(view.bosses or {}) do
        for _, p in ipairs(b.pieces) do if p.mine and p.got then return true end end
    end
    return false
end

function Tracker:Update()
    if self.testView then return end
    local name, mapID, key = Tracker.Where()
    if not name then self:Leave(); return end
    if key ~= self.key then
        self.key, self.closedFor, self.manual = key, nil, nil
        wipe(self.entered)
    end
    local R = ns.Runs
    if not (R and R.View) then return end
    local ok, view = pcall(R.View, name, mapID, self.entered)
    if not ok or type(view) ~= "table" then return end
    for id in pairs(view.needIDs or {}) do self.entered[id] = true end
    self.view = view
    local t = DB()
    local skipped = t and t.skip[key]
    if self.closedFor == key or (skipped and not self.manual) or not Tracker.Wanted(view, self.manual) then
        self:Hide()
        return
    end
    if not self.frame then
        if InCombat() then self:WaitForCombat(); return end
        self:Build()
    end
    if not self.frame then return end
    self:Render()
    self.frame:Show()
    Listen(true)
end

-- Built after combat (W3), then the normal update.
function Tracker:WaitForCombat()
    if not events then return end
    if ns.SafeRegister then ns.SafeRegister(events, "PLAYER_REGEN_ENABLED") end
end

function Tracker:CloseHere()
    self.closedFor = self.key
    self.manual = nil
    self:Hide()
end

function Tracker:SkipHere()
    local t = DB()
    if t and self.key then t.skip[self.key] = true end
    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
    self:CloseHere()
end

function Tracker.SkippedCount()
    local t = DB()
    local n = 0
    for _ in pairs(t and t.skip or {}) do n = n + 1 end
    return n
end

function Tracker.ClearSkipped()
    local t = DB()
    if t then wipe(t.skip) end
    if ns.Settings and ns.Settings.Refresh then ns.Settings:Refresh() end
    Tracker:Update()
end

-- /gs checklist: show it here even when nothing is needed, or close it until you leave.
function Tracker:Toggle()
    local name = Tracker.Where()
    if not name then
        if ns.Print then ns.Print(L("TRACKER_NOT_IN", "The checklist works inside a dungeon or raid.")) end
        return
    end
    if self:IsShown() then self:CloseHere(); return end
    self.closedFor = nil
    self.manual = true
    self:Update()
end

-- Selftest: shows a made-up view (out of combat only), then gives the real state back.
function Tracker:ShowTest(view)
    if InCombat() and not self.frame then return false end
    if not self:Build() then return false end
    self.testShown = self.frame:IsShown()
    self.testView = view
    self:Render()
    self.frame:Show()
    return true
end

function Tracker:HideTest()
    if not self.testView then return end
    self.testView = nil
    if self.frame then
        if self.testShown and self.view then self:Render(); self.frame:Show() else self.frame:Hide() end
    end
    self.testShown = nil
end

-- ---------------------------------------------------------------------------
-- Events: where we are (always; cheap), bags only while shown.
local bagPending
events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if ns.Runs and ns.Runs.Init then pcall(ns.Runs.Init) end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Tracker:Update()
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        if bagPending then return end
        bagPending = true
        C_Timer.After(0.5, function()
            bagPending = nil
            if ns.Runs then ns.Runs.Invalidate() end
            if Tracker:IsShown() then Tracker:Update() end
        end)
        return
    end
    -- PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA: instance info settles a moment later.
    C_Timer.After(1, function() Tracker:Update() end)
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    if ns.SafeRegister then ns.SafeRegister(events, e) else pcall(events.RegisterEvent, events, e) end
end
Tracker.events = events
