-- Gear Set: the Plan tab (1.1 beta.4, plans\v1.1.0\b4-plan.md sec. 1 / 6). One scrolling list of
-- runs (dungeons and raids) with the pieces this character still needs from each, keys,
-- attunements and raid lockouts; the hand-ins ready now; the shopping list (moved from Progress, P1).
-- ToS (plans\v1.1.0\tos-b4.md): B1 RequestRaidInfo only when the tab opens, at most once per 10 s,
-- never from UPDATE_INSTANCE_INFO (registered only while the tab is shown, it only redraws);
-- B5 the LFG line goes to a copy box only; B7 pins and the Way pin are click-only.
-- Layout numbers: Theme.sizes.plan (ui-b4 #8).
local _, ns = ...

local Plan = {}
ns.Plan = Plan

local Theme = ns.Theme
local W = ns.Widgets or {}
local function T(key, fallback) return (ns.L and ns.L[key]) or fallback end
local function Sizes() return Theme.sizes.plan end
local function C(key) return Theme.colors[key] end

Plan.RAID_INFO_GAP = 10          -- seconds between two RequestRaidInfo calls (B1)
Plan.requests = 0                -- RequestRaidInfo calls (tests / selftest)
Plan.lastRequest = nil

-- ---------------------------------------------------------------------------
-- Texts (pure, also used by the tests).

-- "5 players, level 55-60"; a place without size and level: "Dungeon" / "Raid" (pretest 1).
function Plan.InfoText(f)
    local parts = {}
    if f.size then
        parts[#parts + 1] = (f.kind == "raid" and T("PLAN_RAID", "%d-player raid") or T("PLAN_SIZE", "%d players")):format(f.size)
    end
    if f.lo then
        local lv = (f.hi and f.hi ~= f.lo) and (f.lo .. "-" .. f.hi) or tostring(f.lo)
        parts[#parts + 1] = T("PLAN_LEVEL", "level %s"):format(lv)
    end
    if #parts == 0 and f.kind then
        return T("PLAN_KIND_" .. f.kind, f.kind == "raid" and "Raid" or "Dungeon")
    end
    return table.concat(parts, ", ")
end

function Plan.CountText(n)
    if n == 1 then return T("PLAN_PIECE", "1 piece") end
    return T("PLAN_PIECES", "%d pieces"):format(n)
end

-- "48 pieces in 10 runs" / "3 pieces in 1 run" (distinct pieces; pretest 4).
function Plan.SummaryText(pieces, runs)
    local r = runs == 1 and T("PLAN_RUN_ONE", "1 run") or T("PLAN_RUNS", "%d runs"):format(runs)
    return T("PLAN_SUMMARY", "%s in %s"):format(Plan.CountText(pieces), r)
end

local function ItemName(id)
    local get = C_Item and C_Item.GetItemNameByID
    if type(get) == "function" then
        local ok, n = pcall(get, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return nil
end

-- "|A:atlas:s:s|a" / "|T file:s|t" for a Theme.art entry (first that exists), else "".
local function Inline(entry, size, file)
    size = size or Sizes().inline
    if file then return ("|T%s:%d|t"):format(tostring(file), size) end
    if not entry then return "" end
    for _, a in ipairs(entry.atlases or { entry.atlas }) do
        if Theme.AtlasExists(a) then return ("|A:%s:%d:%d|a"):format(a, size, size) end
    end
    if entry.file then return ("|T%s:%d|t"):format(entry.file, size) end
    return ""
end

local function KeyIcon(id)
    local get = C_Item and C_Item.GetItemIconByID
    if type(get) == "function" then
        local ok, icon = pcall(get, id)
        if ok and (type(icon) == "number" or type(icon) == "string") then return icon end
    end
    return Theme.art.key.file
end

-- Key texts: { text, have, id } per key ("Skeleton Key: keyring" / "Key to the City (service gate): missing").
function Plan.KeyTexts(f, placeOf)
    placeOf = placeOf or (ns.Runs and ns.Runs.ItemPlace)
    local out = {}
    for _, k in ipairs(f.keys) do
        local name = ItemName(k.id) or ("item " .. k.id)
        if k.part and k.part ~= "" then name = T("KEY_PART", "%s (%s)"):format(name, k.part) end
        local where = placeOf and placeOf(k.id)
        if where then
            out[#out + 1] = { text = T("KEY_" .. where, "%s: " .. where):format(name), have = true, id = k.id }
        else
            out[#out + 1] = { text = T("KEY_MISSING", "%s: missing"):format(name), have = false, id = k.id }
        end
    end
    return out
end

-- Lockout text. Row (short): "saved 3/10, resets in 2d 4h"; tooltip (full): "saved 10/10, done this
-- week, resets Tue 09:00 (in 2d 4h)" (ui-b4 #6).
function Plan.LockText(e, now, full)
    local l = e.lock
    if not l then return T("LOCK_FREE", "not saved") end
    local R = ns.Runs
    local s = T("LOCK_SAVED", "saved %d/%d"):format(l.done or 0, l.total or 0)
    if full and e.lockState == "done" then s = s .. ", " .. T("LOCK_DONE", "done this week") end
    return s .. ", " .. R.ResetText(l.resetAt, now, not full)
end

-- The status column: keys (icon + tick), attunement, lockout (raids), each coloured.
function Plan.StatusText(e, now)
    local parts = {}
    local tick = Inline(Theme.art.tick, 12)
    for _, k in ipairs(Plan.KeyTexts(e.facts)) do
        local icon = Inline(nil, nil, KeyIcon(k.id))
        parts[#parts + 1] = icon .. " " .. C(k.have and "planHave" or "planMissing"):WrapTextInColorCode(k.text)
            .. (k.have and (" " .. tick) or "")
    end
    local att = e.attuned
    if att == true then parts[#parts + 1] = C("planHave"):WrapTextInColorCode(T("ATT_YES", "attuned")) .. " " .. tick
    elseif att == false then parts[#parts + 1] = C("planMissing"):WrapTextInColorCode(T("ATT_NO", "not attuned")) end
    if e.facts.kind == "raid" or e.lock then
        parts[#parts + 1] = C("planNote"):WrapTextInColorCode(Plan.LockText(e, now))
    end
    return table.concat(parts, "   ")
end

-- Wanted names of a run (for the LFG line).
local function NeedNames(e)
    local names = {}
    for _, b in ipairs(e.view.bosses) do
        for _, p in ipairs(b.pieces) do
            if p.mine and not p.later then names[#names + 1] = ItemName(p.itemID) or ("item " .. p.itemID) end
        end
    end
    return names
end
Plan.NeedNames = NeedNames

local function RunLabel(e) return e.label or e.run end

-- ---------------------------------------------------------------------------
-- Lockouts (B1).

local locks = {}
function Plan.ReadLocks()
    local R = ns.Runs
    local ok, l = pcall(R.ReadLockouts)
    locks = ok and type(l) == "table" and l or {}
    return locks
end

-- At most once per RAID_INFO_GAP seconds; only from the tab's OnShow.
function Plan.RequestLocks(now)
    local req = _G.RequestRaidInfo
    if type(req) ~= "function" then return false end
    now = now or (GetTime and GetTime()) or time()
    if Plan.lastRequest and now - Plan.lastRequest < Plan.RAID_INFO_GAP then return false end
    Plan.lastRequest = now
    Plan.requests = Plan.requests + 1
    pcall(req)
    return true
end

-- ---------------------------------------------------------------------------
-- Rows.

local function Collapsed(run)
    local db = ns.db
    return type(db) == "table" and type(db.plan) == "table" and type(db.plan.collapsed) == "table"
        and db.plan.collapsed[run] == true
end

function Plan.Toggle(run)
    local db = ns.db
    if not (type(db) == "table" and type(db.plan) == "table") then return end
    if type(db.plan.collapsed) ~= "table" then db.plan.collapsed = {} end
    db.plan.collapsed[run] = (not Collapsed(run)) or nil
    Plan:Refresh()
end

function Plan.ShowLfg(e)
    local text = ns.Runs.LfgLine(RunLabel(e), NeedNames(e))
    if W.ShowCopy then W.ShowCopy("lfg", text) elseif ns.ShowCopyBox then ns.ShowCopyBox("lfg", text) end
    return text
end

local function HeadTooltip(row)
    local e = row.gsEntry
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(RunLabel(e), C("planHead"):GetRGB())
    Theme.AddHint(GameTooltip, T("PLAN_FOLD_TIP", "Click: show or hide the bosses."))
    local info = Plan.InfoText(e.facts)
    if info ~= "" then GameTooltip:AddLine(info, C("text"):GetRGB()) end
    for _, k in ipairs(Plan.KeyTexts(e.facts)) do
        GameTooltip:AddLine(T("PLAN_TIP_BRING", "Bring: %s"):format(k.text), C(k.have and "planHave" or "planMissing"):GetRGB())
    end
    if e.attuned ~= nil then
        GameTooltip:AddLine(e.attuned and T("ATT_YES", "attuned") or T("ATT_NO", "not attuned"),
            C(e.attuned and "planHave" or "planMissing"):GetRGB())
    end
    if e.lock or e.facts.kind == "raid" then GameTooltip:AddLine(Plan.LockText(e, nil, true), C("planNote"):GetRGB()) end
    local notes = ns.Runs.GroupNotes(e.facts)
    for wing, list in pairs(e.wings or {}) do
        for _, n in ipairs(list) do notes[#notes + 1] = wing .. ": " .. n end
    end
    if #notes > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T("PLAN_TIP_GROUP", "Group notes"), C("planHead"):GetRGB())
        for _, n in ipairs(notes) do GameTooltip:AddLine(n, C("planNote"):GetRGB(), true) end
    end
    Theme.AddHint(GameTooltip, T("PLAN_TIP_LFG", "Click LFG for a group line to copy."))
    GameTooltip:Show()
end

-- Small icon button (ui-b4 #3): the entry's atlas / file / text, hover glow (entry.hover atlas,
-- else entry.highlight / Theme.art.smallHover file, ADD), pressed art (entry.pushed file).
local function SmallButton(parent, art, size, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local used = art.atlas and Theme.AtlasExists(art.atlas)
    if used then tex:SetAtlas(art.atlas) end
    if not used and not Theme.TryTexture(tex, art.file) then
        tex:Hide()
        local fs = b:CreateFontString(nil, "OVERLAY")
        Theme.Font(fs, "small")
        fs:SetPoint("CENTER")
        fs:SetText(art.text or "?")
        fs:SetTextColor(C("link"):GetRGB())
        b:SetWidth(math.max(size, (fs:GetStringWidth() or 20) + 4))
        b.gsText = fs
    else
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        if used and art.hover and Theme.AtlasExists(art.hover) then
            hl:SetAtlas(art.hover)
        elseif not Theme.TryTexture(hl, art.highlight or Theme.art.smallHover.file) then
            hl:Hide()
        end
        hl:SetBlendMode("ADD")
        if art.pushed then
            b:SetScript("OnMouseDown", function() if not Theme.TryTexture(tex, art.pushed) then Theme.TryTexture(tex, art.file) end end)
            b:SetScript("OnMouseUp", function() Theme.TryTexture(tex, art.file) end)
        end
    end
    b.tex = tex
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        if type(tip) == "function" then tip(self) else W.SimpleTip(self, tip) end
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- Pin star: the AH off-star when unpinned (ui-b4 #4); missing -> the star, dimmed.
local function SetPin(btn, pinned)
    local star = Theme.art.star
    btn.tex:SetAlpha(1)
    btn.tex:SetDesaturated(false)
    if not pinned and star.off and Theme.AtlasExists(star.off) then
        btn.tex:SetAtlas(star.off)
        return
    end
    Theme.SetArt(btn.tex, star)
    if not pinned then
        btn.tex:SetAlpha(star.offAlpha or 0.35)
        btn.tex:SetDesaturated(true)
    end
end

local function HeadRow(self, i)
    local r = self.heads[i]
    if r then return r end
    local sz = Sizes()
    r = CreateFrame("Button", nil, self.child)
    r:SetHeight(sz.head)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local art = Theme.art.rowBackground
    if not Theme.SetArt(bg, art) then bg:SetColorTexture(unpack(art.color)) end
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Theme.SetArt(hl, Theme.art.listHover)
    r.fold = r:CreateTexture(nil, "ARTWORK")
    r.fold:SetSize(Theme.art.expand.size, Theme.art.expand.size)
    r.fold:SetPoint("LEFT", sz.foldX, 0)
    r.pin = CreateFrame("Button", nil, r)
    r.pin:SetSize(Theme.art.star.size, Theme.art.star.size)
    r.pin:SetPoint("LEFT", sz.pinX, 0)
    r.pin.tex = r.pin:CreateTexture(nil, "ARTWORK")
    r.pin.tex:SetAllPoints()
    r.pin:SetScript("OnClick", function()
        local e = r.gsEntry
        if not e then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.Runs.Pin(e.run)
        Plan:Refresh()
    end)
    r.pin:SetScript("OnEnter", function(b) W.SimpleTip(b, T("PLAN_PIN_TIP", "Pin this run to the top (this character only).")) end)
    r.pin:SetScript("OnLeave", GameTooltip_Hide)
    r.name = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.name, "normal")
    r.name:SetPoint("LEFT", sz.nameX, 0)
    r.name:SetWidth(sz.nameW)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    -- lock: at the end of the name column; the name gives up that room while locked (ui-b4 #8)
    local lockArt = Theme.art.lock
    r.lock = r:CreateTexture(nil, "ARTWORK")
    r.lock:SetSize(lockArt.size, lockArt.size)
    r.lock:SetPoint("LEFT", sz.nameX + sz.nameW - lockArt.size, 0)
    if lockArt.atlas and Theme.AtlasExists(lockArt.atlas) then
        r.lock:SetAtlas(lockArt.atlas); r.lockOK = true
    else
        r.lockOK = Theme.TryTexture(r.lock, lockArt.file)
    end
    local function Col(x, w)
        local fs = r:CreateFontString(nil, "OVERLAY")
        Theme.Font(fs, "small")
        fs:SetPoint("LEFT", x, 0)
        if w then fs:SetWidth(w) end
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    r.info = Col(sz.infoX, sz.infoW)
    r.count = Col(sz.infoX + sz.infoW + sz.gap, sz.countW)
    r.way = SmallButton(r, Theme.art.wayPin, Theme.sizes.way or 14,
        function(b) if b.gsPoint and ns.Way then ns.Way.Tooltip(b, b.gsPoint) end end,
        function(b) if b.gsPoint and ns.Way then ns.Way:Go(b.gsPoint) end end)
    r.way:SetPoint("RIGHT", -4, 0)
    r.lfg = SmallButton(r, Theme.art.lfg, sz.button, T("PLAN_LFG_TIP", "Copy a group line to paste into chat yourself."),
        function() if r.gsEntry then Plan.ShowLfg(r.gsEntry) end end)
    r.lfg:SetPoint("RIGHT", r.way, "LEFT", -sz.gap, 0)
    r.status = Col(sz.infoX + sz.infoW + sz.gap + sz.countW + sz.gap, nil)
    r.status:SetPoint("RIGHT", r.lfg, "LEFT", -sz.gap, 0)
    r:SetScript("OnClick", function()
        if r.gsEntry then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            Plan.Toggle(r.gsEntry.run)
        end
    end)
    r:SetScript("OnEnter", HeadTooltip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    self.heads[i] = r
    return r
end

local function FillHead(r, e, now)
    local sz = Sizes()
    r.gsEntry = e
    local folded = Collapsed(e.run)
    local ex = Theme.art.expand
    if not Theme.TryTexture(r.fold, folded and ex.plus or ex.minus) then r.fold:Hide() else r.fold:Show() end
    SetPin(r.pin, e.pinned)
    local done = e.lockState == "done"
    local showLock = done and r.lockOK and true or false
    r.name:SetWidth(showLock and (sz.nameW - Theme.art.lock.size - 4) or sz.nameW)
    r.name:SetText(RunLabel(e))
    r.name:SetTextColor(C(done and "planLocked" or "planHead"):GetRGB())
    r.lock:SetShown(showLock)
    r.info:SetText(Plan.InfoText(e.facts))
    r.info:SetTextColor(C("planNote"):GetRGB())
    r.count:SetText(Plan.CountText(e.need))
    r.count:SetTextColor(C(done and "planLocked" or "text"):GetRGB())
    local status = Plan.StatusText(e, now)
    if done then status = C("planLocked"):WrapTextInColorCode((status:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
    r.status:SetText(status)
    local p = ns.Way and ns.Way.Point("place", e.run)
    r.way.gsPoint = p
    r.way:SetShown(p ~= nil)
end

local function LineRow(self, i)
    local r = self.lines[i]
    if r then return r end
    local sz = Sizes()
    r = CreateFrame("Button", nil, self.child)
    r:SetHeight(sz.row)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Theme.SetArt(hl, Theme.art.listHover)
    r.gsHl = hl
    r.boss = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.boss, "small")
    r.boss:SetPoint("LEFT", sz.indent, 0)
    r.boss:SetWidth(sz.pieceX - sz.indent - sz.gap)
    r.boss:SetJustifyH("LEFT")
    r.boss:SetWordWrap(false)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(sz.icon, sz.icon)
    r.icon:SetPoint("LEFT", sz.pieceX, 0)
    if W.ICON_CROP then r.icon:SetTexCoord(unpack(W.ICON_CROP)) end
    if W.IconBorder then
        local border, ok = W.IconBorder(r, r.icon)
        r.border, r.hasBorder = border, ok
    end
    r.right = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.right, "small")
    r.right:SetPoint("RIGHT", -sz.gap, 0)
    r.right:SetWidth(sz.rightW)
    r.right:SetJustifyH("RIGHT")
    r.right:SetWordWrap(false)
    r.name = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.name, "small")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.extra = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.extra, "small")
    r.extra:SetJustifyH("LEFT")
    r.extra:SetWordWrap(false)
    r.extra:SetPoint("LEFT", r.name, "RIGHT", sz.gap, 0)
    r.extra:SetPoint("RIGHT", r.right, "LEFT", -sz.gap, 0)
    r:SetScript("OnClick", function(b)
        local id = b.gsItem
        if not id then return end
        if W.HandleModifiedClick and W.HandleModifiedClick(id) then return end
        local Int = ns.Integrations
        if Int and Int.ShowItem then pcall(Int.ShowItem, id) end
    end)
    r:SetScript("OnEnter", function(b)
        if not b.gsItem then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(b.gsItem)
        Theme.AddHint(GameTooltip, T("PLAN_TIP_PIECE", "Click: open its guide on the Sets tab."))
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    self.lines[i] = r
    return r
end

-- Item name in quality colour, or grey for alt-only / locked rows (also after a late load, ui-b4 #9).
local function FillName(r, itemID)
    if W.FillItem then
        W.FillItem(r, itemID, function(t)
            if t.gsItem ~= itemID then return end
            W.FillItem(t, itemID)
            if t.gsGrey then t.name:SetTextColor(C(t.gsGrey):GetRGB()) end
        end)
    else
        r.name:SetText(ItemName(itemID) or ("item " .. itemID))
    end
    if r.gsGrey then r.name:SetTextColor(C(r.gsGrey):GetRGB()) end
end

-- kind "piece" (boss text + item) or "text" (one line from the left edge).
local function FillLine(r, kind, data)
    local sz = Sizes()
    r.gsItem, r.gsGrey = nil, nil
    r.name:ClearAllPoints()
    if kind == "text" then
        r.boss:Hide(); r.icon:Hide(); r.right:Hide(); r.extra:Hide()
        if r.border then r.border:Hide() end
        r.gsHl:Hide()
        r.name:SetPoint("LEFT", data.x or 8, 0)
        r.name:SetPoint("RIGHT", -sz.gap, 0)
        r.name:SetText(data.text)
        r.name:SetTextColor(C(data.color or "planNote"):GetRGB())
        return
    end
    r.gsHl:Show()
    r.boss:Show(); r.icon:Show(); r.right:Show(); r.extra:Show()
    r.boss:SetText(data.boss or "")
    r.boss:SetTextColor(C("planBoss"):GetRGB())
    r.name:SetPoint("LEFT", r.icon, "RIGHT", sz.gap, 0)
    local p = data.piece
    r.gsItem = p.itemID
    r.gsGrey = (data.locked and "planLocked") or ((not p.mine) and "planNote") or nil
    r.icon:SetTexture((ns.Progress and ns.Progress.ItemIcon and ns.Progress.ItemIcon(p.itemID)) or 134400)
    r.icon:SetDesaturated(not p.mine)
    FillName(r, p.itemID)
    local extra = {}
    if p.via then extra[#extra + 1] = T("PLAN_FOR", "for %s"):format(p.via) end
    if p.alts and #p.alts > 0 then extra[#extra + 1] = T("PLAN_ALT", "- %s"):format(table.concat(p.alts, ", ")) end
    r.extra:SetText(table.concat(extra, " "))
    r.extra:SetTextColor(C("planNote"):GetRGB())
    if p.mine then
        r.right:SetText(p.via and T("PLAN_HANDIN", "Hand-in") or T("PLAN_NEED", "Need"))
        r.right:SetTextColor(C("text"):GetRGB())
    else
        r.right:SetText("")
    end
end

-- ---------------------------------------------------------------------------
-- Build.

function Plan:Build(page)
    if self.page then return end
    self.page = page
    local sz = Sizes()
    self.title = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.title, "header")
    self.title:SetTextColor(C("planHead"):GetRGB())
    self.title:SetPoint("TOPLEFT", sz.titleX, sz.titleY)
    self.title:SetText(T("PLAN_TITLE", "What to run"))
    self.summary = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.summary, "text")
    self.summary:SetPoint("TOPRIGHT", sz.summaryX, sz.summaryY)
    self.summary:SetJustifyH("RIGHT")
    self.locksLine = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.locksLine, "small")
    self.locksLine:SetTextColor(C("planNote"):GetRGB())
    self.locksLine:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -sz.gap)
    self.locksLine:SetJustifyH("LEFT")

    local scroll = W.ScrollFrame and W.ScrollFrame(page) or CreateFrame("ScrollFrame", nil, page)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(900, 10)
    scroll:SetScrollChild(child)
    scroll:SetPoint("TOPLEFT", sz.titleX - 4, -sz.top)
    scroll:SetPoint("BOTTOMRIGHT", sz.summaryX, 30)
    self.scroll, self.child = scroll, child
    self.heads, self.lines = {}, {}

    -- section headings: gold like every other heading (ui-b4 #5); the hand-in rows stay green
    self.handHead = ns.Progress.Head(child, T("PLAN_HAND_HEAD", "Ready to hand in"))
    self.runsHead = ns.Progress.Head(child, T("PLAN_RUNS_HEAD", "Runs"))
    self.empty = child:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.empty, "text")
    self.empty:SetJustifyH("LEFT")
    self.empty:SetWordWrap(true)
    local check = Theme.CreateFrame("CheckButton", nil, child, "check")
    check:SetSize(Theme.sizes.check, Theme.sizes.check)
    local label = check.Text or check.text or check:CreateFontString(nil, "OVERLAY")
    label:ClearAllPoints()
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    Theme.Font(label, "small")
    label:SetText(T("S_TRACKER_STARTED", "With nothing tracked, use sets I've started"))
    check.gsLabel = label
    check:SetScript("OnClick", function(b)
        local on = b:GetChecked() and true or false
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        local db = ns.db
        if type(db) == "table" and type(db.tracker) == "table" then db.tracker.started = on end
        if ns.Runs and ns.Runs.Invalidate then ns.Runs.Invalidate() end
        Plan:Refresh()
    end)
    self.startedCheck = check
    if ns.Progress.BuildShop then ns.Progress.BuildShop(self, child) end

    self.note = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(self.note, "small")
    self.note:SetTextColor(C("planNote"):GetRGB())
    self.note:SetPoint("BOTTOMLEFT", sz.titleX, 10)
    self.note:SetPoint("BOTTOMRIGHT", sz.summaryX, 10)
    self.note:SetJustifyH("LEFT")
    self.note:SetWordWrap(false)

    -- B1: the server request only here (tab opened), throttled; the event only while shown.
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function()
        Plan.ReadLocks()
        Plan:Refresh()
    end)
    page:HookScript("OnShow", function() Plan:OnShow() end)
    page:HookScript("OnHide", function() Plan:OnHide() end)
end

function Plan:OnShow()
    if ns.SafeRegister then ns.SafeRegister(self.events, "UPDATE_INSTANCE_INFO") end
    Plan.ReadLocks()
    Plan.RequestLocks()
end

function Plan:OnHide()
    if self.events then pcall(self.events.UnregisterEvent, self.events, "UPDATE_INSTANCE_INFO") end
end

-- ---------------------------------------------------------------------------
-- Draw (only while the tab is shown).

function Plan.Data(lockList)
    local R = ns.Runs
    local plan = R.Plan(lockList or locks)
    for _, e in ipairs(plan.runs) do
        local ok, att = pcall(R.Attuned, e.facts)
        e.attuned = ok and att or nil
    end
    return plan
end

-- Distinct pieces of a plan (Runs.Plan counts them; a made-up plan: the sum).
local function PieceTotal(plan)
    if plan.pieces then return plan.pieces end
    local n = 0
    for _, e in ipairs(plan.runs) do n = n + e.need end
    return n
end

function Plan:Refresh()
    local page = self.page
    if not (page and page:IsVisible()) then return end
    local width = self.scroll:GetWidth() or 0
    if width < 100 then width = 900 end
    self.child:SetWidth(width)
    local now = time()
    local ok, plan = pcall(Plan.Data, self.sampleLocks)
    if self.sample then ok, plan = true, self.sample end   -- /gs selftest: a made-up run (text fit)
    if not ok or type(plan) ~= "table" then plan = { runs = {}, other = 0 } end
    self.plan = plan
    local sz = Sizes()
    local y, nh, nl = 0, 0, 0
    local function Line(kind, data)
        nl = nl + 1
        local r = LineRow(self, nl)
        FillLine(r, kind, data)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        r:SetWidth(width - 4)
        r:Show()
        y = y + sz.row
        return r
    end
    local function Section(head, shown)
        ns.Progress.ShowHead(head, shown)
        if not shown then return end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        head.gsLine:SetWidth(width - 4)
        y = y + sz.sectionH
    end
    -- hand-ins ready now
    local HI = ns.HandIns
    local hand = {}
    if HI and HI.Ready then
        local okH, list = pcall(HI.Ready)
        if okH and type(list) == "table" then hand = list end
    end
    if self.sampleHand then hand = self.sampleHand end
    Section(self.handHead, #hand > 0)
    if #hand > 0 then
        for _, h in ipairs(hand) do
            local items = {}
            for _, it in ipairs(h.items) do items[#items + 1] = ("%d/%d %s"):format(math.min(it.have or 0, it.n), it.n, it.name) end
            Line("text", { x = 8, color = "handReady", text = T("PLAN_HAND_ROW", "%s, %s - %s"):format(
                h.npc or "?", h.zone or "?", h.quest) .. " (" .. table.concat(items, ", ") .. ")" })
        end
        y = y + 8
    end
    -- runs (a "Runs" heading when the hand-in section is above them)
    Section(self.runsHead, #hand > 0 and #plan.runs > 0)
    local anyRaid = false
    for _, e in ipairs(plan.runs) do
        nh = nh + 1
        if e.facts.kind == "raid" then anyRaid = true end
        local r = HeadRow(self, nh)
        FillHead(r, e, now)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        r:SetWidth(width - 4)
        r:Show()
        y = y + sz.head + 2
        if not Collapsed(e.run) then
            local wing
            for _, b in ipairs(e.view.bosses) do
                -- a wing inside the run (Ring of Law): its label and note once, before its bosses
                if b.wing ~= wing then
                    wing = b.wing
                    if wing and e.wings and e.wings[wing] then
                        local note = e.wings[wing][1]
                        Line("text", { x = sz.indent, color = "planBoss",
                            text = wing .. (note and (" - " .. C("planNote"):WrapTextInColorCode(note)) or "") })
                    end
                end
                local label = b.trash and T("PLAN_TRASH", "Trash") or b.label
                local first = true
                for _, p in ipairs(b.pieces) do
                    if not p.later then
                        -- the boss name on the first piece drawn (pretest 8)
                        Line("piece", { boss = first and label or "", piece = p, locked = e.lockState == "done" })
                        first = false
                    end
                end
            end
            y = y + 4
        end
    end
    for i = nh + 1, #self.heads do self.heads[i]:Hide() end
    -- empty state
    local tracked = ns.Track and ns.Track.Mine and next(ns.Track.Mine()) ~= nil
    local showEmpty = #plan.runs == 0
    self.empty:SetShown(showEmpty)
    self.startedCheck:SetShown(showEmpty and not tracked)
    if showEmpty then
        self.empty:SetText(tracked and T("PLAN_NONE", "None of the pieces you need drop in a dungeon or raid.")
            or T("PLAN_EMPTY", "Track a set or a piece (Shift-click it in the list) to plan your runs."))
        self.empty:ClearAllPoints()
        self.empty:SetPoint("TOPLEFT", self.child, "TOPLEFT", 8, -(y + 4))
        self.empty:SetWidth(width - 16)
        y = y + math.max(16, self.empty:GetStringHeight() or 16) + 10
        if self.startedCheck:IsShown() then
            local db = ns.db
            self.startedCheck:SetChecked(not (type(db) == "table" and type(db.tracker) == "table" and db.tracker.started == false))
            self.startedCheck:ClearAllPoints()
            self.startedCheck:SetPoint("TOPLEFT", self.child, "TOPLEFT", 4, -y)
            y = y + Theme.sizes.check + 8
        end
    end
    for i = nl + 1, #self.lines do self.lines[i]:Hide() end
    -- shopping list (P1), at most sizes.plan.shopW wide (ui-b4 #5)
    y = y + 8
    local missing
    if ns.Progress.LayShopping then y, missing = ns.Progress.LayShopping(self, y, math.min(width, sz.shopW)) end
    self.child:SetHeight(math.max(10, y + 4))
    -- header texts
    local nRuns = #plan.runs
    self.summary:SetText(nRuns > 0 and Plan.SummaryText(PieceTotal(plan), nRuns) or "")
    local saved = 0
    for _, l in ipairs(self.sampleLocks or locks) do if l.isRaid then saved = saved + 1 end end
    -- the lockouts line only when it says something: a raid listed or a raid saved (ui-b4 #11)
    self.locksLine:SetShown(saved > 0 or anyRaid)
    self.locksLine:SetText(saved > 0 and T("PLAN_LOCKS", "Raid lockouts: %d saved"):format(saved)
        or T("PLAN_LOCKS_NONE", "Raid lockouts: none saved"))
    self.note:SetShown((plan.other or 0) > 0)
    self.note:SetText(T("PLAN_OTHER", "Not from a run: %d pieces (quests, vendors, crafting). Click a piece for its guide."):format(plan.other or 0))
    if missing and (self.retries or 0) < 3 and C_Timer and C_Timer.After then
        self.retries = (self.retries or 0) + 1
        C_Timer.After(1, function() Plan:Refresh() end)
    elseif not missing then
        self.retries = 0
    end
end

function Plan._Reset()
    locks = {}
    Plan.requests, Plan.lastRequest = 0, nil
end
