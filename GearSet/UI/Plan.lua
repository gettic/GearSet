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
Plan.OTHER_FOLD = 8              -- beta.6: more "Not from a run" pieces than this fold into one row
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

-- "|A:atlas:s:s|a" / "|T file:s|t" for a Theme.art entry (first that exists), else "" (Theme.InlineIcon, ui-b6 #7).
local function Inline(entry, size, file)
    return Theme.InlineIcon(entry, size or Sizes().inline, file)
end

-- The real source of a "Not from a run" piece (ui-b6 #4, user's screenshot: "Boss Drop" was unclear):
-- the first own-faction source that isn't a free note -> full ("Lord Kazzak - Blasted Lands",
-- "Vendor: Deliana - Ironforge", "Quest: The Fall of Ossirian"), short (the first part only).
-- Only the type word ("World Drop") when the data has nothing better; "", "" when no source.
local function Has(s) return type(s) == "string" and s ~= "" end
function Plan.SourceText(itemID)
    local D = ns.Data
    if not (D and D.SourceEntries) then return "", "" end
    local mine = D.PlayerFaction and D.PlayerFaction()
    local ok, list = pcall(D.SourceEntries, itemID)
    for _, e in ipairs(ok and type(list) == "table" and list or {}) do
        if e.kind ~= "x" and (not e.fac or not mine or e.fac == mine) then
            local k, short, place = e.kind, nil, nil
            if k == "b" and Has(e.a) then short, place = e.a, e.b
            elseif k == "z" and Has(e.a) then short = e.a
            elseif k == "v" and Has(e.a) then short, place = T("PLAN_SRC_VENDOR", "Vendor: %s"):format(e.a), e.b
            elseif k == "q" and Has(e.a) then short, place = T("PLAN_SRC_QUEST", "Quest: %s"):format(e.a), e.b
            elseif k == "c" and Has(e.a) then short = T("PLAN_SRC_CRAFT", "Crafted: %s"):format(e.a)
            end
            if short then
                local full = Has(place) and place ~= short and (short .. " - " .. place) or short
                return full, short
            end
            local w = D.TypeWord and D.TypeWord(k)
            if w and w ~= "" then return w, w end
        end
    end
    return "", ""
end

-- The type word only (kept for callers / tests).
function Plan.SourceWord(itemID)
    local D = ns.Data
    local mine = D and D.PlayerFaction and D.PlayerFaction()
    local ok, list = pcall(D.SourceEntries, itemID)
    for _, e in ipairs(ok and type(list) == "table" and list or {}) do
        if e.kind ~= "x" and (not e.fac or not mine or e.fac == mine) then
            local w = D.TypeWord and D.TypeWord(e.kind)
            if w and w ~= "" then return w end
        end
    end
    return ""
end

-- A text cut to fit `room` px (measure(text) -> px, 15 % margin): full, else short, else short cut + "...".
function Plan.FitText(full, short, room, measure)
    local fit = room * 0.85
    if measure(full) <= fit then return full end
    if measure(short) <= fit then return short end
    local s = short
    while #s > 1 and measure(s .. "...") > fit do
        s = s:sub(1, -2):gsub("[\192-\255][\128-\191]*$", "")   -- never half a UTF-8 letter
    end
    return (s:gsub("%s+$", "")) .. "..."
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
-- Plan.StatusParts -> list of segments; StatusText = one line; StatusLines = packed into the room.
function Plan.StatusText(e, now) return table.concat(Plan.StatusParts(e, now), Plan.STATUS_GAP) end
Plan.STATUS_GAP = "   "

-- Pack segments into lines that fit `room` px (measure(text) -> px; a 15 % margin for the real font),
-- at most sizes.plan.statusLines lines; a segment never splits. Returns the text ("\n" between lines), lines.
function Plan.StatusLines(parts, room, measure)
    local max = Sizes().statusLines or 3
    local fit = room * 0.85
    local lines = {}
    for _, seg in ipairs(parts) do
        local cur = lines[#lines]
        local joined = cur and (cur .. Plan.STATUS_GAP .. seg)
        if joined and (#lines >= max or measure(joined) <= fit) then
            lines[#lines] = joined
        else
            lines[#lines + 1] = seg
        end
    end
    return table.concat(lines, "\n"), math.max(1, #lines)
end

-- Width of the status column on a row `rowW` px wide (from Theme.sizes.plan; the LFG / Way buttons at the right).
-- wayW: the Way button's real width (the "Way" word when the pin atlas is missing is wider than 14).
function Plan.StatusRoom(rowW, lfgW, wayW)
    local sz = Sizes()
    local x = sz.infoX + sz.infoW + sz.gap + sz.countW + sz.gap
    return rowW - x - (4 + (wayW or Theme.sizes.way or 14) + sz.gap + (lfgW or sz.button) + sz.gap)
end

function Plan.StatusParts(e, now)
    local parts = {}
    local tick = Inline(Theme.art.tick, 12)
    for _, k in ipairs(Plan.KeyTexts(e.facts)) do
        local icon = Inline(nil, nil, KeyIcon(k.id))
        parts[#parts + 1] = icon .. " " .. C(k.have and "planHave" or "planMissing"):WrapTextInColorCode(k.text)
            .. (k.have and (" " .. tick) or "")
    end
    local att = e.attuned
    if att == true then parts[#parts + 1] = C("planHave"):WrapTextInColorCode(T("ATT_YES", "attuned")) .. " " .. tick
    elseif att == false then
        local s = T("ATT_NO", "not attuned")
        if e.attStep and e.attStep ~= "" then s = s .. " (" .. e.attStep .. ")" end   -- beta.6
        parts[#parts + 1] = C("planMissing"):WrapTextInColorCode(s)
    end
    if e.facts.kind == "raid" or e.lock then
        parts[#parts + 1] = C("planNote"):WrapTextInColorCode(Plan.LockText(e, now))
    end
    return parts
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
        local s = e.attuned and T("ATT_YES", "attuned") or T("ATT_NO", "not attuned")
        -- beta.6 (ui-b6 #8): "not attuned (step 3 of 16 - next: Dragonkin Menace)"
        if e.attuned == false and e.attStep and e.attStep ~= "" then
            local step = e.attNext and T("ATT_STEP_NEXT", "%s - next: %s"):format(e.attStep, e.attNext) or e.attStep
            s = s .. " (" .. step .. ")"
        end
        GameTooltip:AddLine(s, C(e.attuned and "planHave" or "planMissing"):GetRGB(), true)
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
    r.status:SetWordWrap(true)   -- only breaks at the "\n" StatusLines puts between parts
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

local function FillHead(r, e, now, rowW)
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
    -- status: wraps between its parts when the column is too narrow (selftest "text cut: status")
    local parts = Plan.StatusParts(e, now)
    if done then
        for i, s in ipairs(parts) do parts[i] = C("planLocked"):WrapTextInColorCode((s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
    end
    local m = Plan.measure
    local status, n = Plan.StatusLines(parts, Plan.StatusRoom(rowW or 900, r.lfg:GetWidth(), r.way:GetWidth()), function(s)
        if not m then return 0 end
        m:SetText(s)
        return m:GetStringWidth() or 0
    end)
    r.status:SetText(status)
    r:SetHeight(math.max(sz.head, n * sz.line + 8))
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
    -- beta.6 (ui-b6 #1): chain step status slot (tick / next arrow / blank), placed by FillLine
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetSize(Theme.art.tick.size or 12, Theme.art.tick.size or 12)
    r.mark:Hide()
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
        if b.gsSource and b.gsSource ~= "" then
            GameTooltip:AddLine(T("PLAN_SRC_TIP", "From: %s"):format(b.gsSource), C("planNote"):GetRGB(), true)
        end
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

-- kind "piece" (boss text + item) or "text" (one line from the left edge). A "text" line with
-- data.mark ("tick" / "next" / "none") gets the fixed step slot in front (ui-b6 #1): the text
-- always starts sizes.plan.stepSlot px right of data.x, done or not.
local function FillLine(r, kind, data)
    local sz = Sizes()
    r.gsItem, r.gsGrey = nil, nil
    r.gsSource = data.source   -- "Not from a run": the full source for the tooltip
    r.name:ClearAllPoints()
    r.mark:Hide()
    r.gsMark = nil
    if kind == "text" then
        r.boss:Hide(); r.icon:Hide(); r.right:Hide(); r.extra:Hide()
        if r.border then r.border:Hide() end
        r.gsHl:Hide()
        local x = data.x or 8
        if data.mark then
            r.mark:ClearAllPoints()
            r.mark:SetPoint("LEFT", x, 0)
            if W.SetMark then W.SetMark(r.mark, data.mark) end
            r.gsMark = data.mark
            x = x + sz.stepSlot
        end
        r.name:SetPoint("LEFT", x, 0)
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
-- 1.1 beta.6: "Reputation and chains" (Steps.lua; b6-plan.md sec. 1 / 6). One row per faction your
-- wanted pieces need and per chain (attunement / key / set chain); folded by default, a click opens
-- it (tokens, your other characters, the steps). ToS S2: the Way pin is click-only.

-- Open state: plan.collapsed["+rep:<faction>"] / ["+chain:<key>"] = true (these rows start closed).
local function IsOpen(key)
    if Plan.sample and Plan.sample.openAll then return true end   -- /gs selftest: step lines shown (text fit)
    local db = ns.db
    return type(db) == "table" and type(db.plan) == "table" and type(db.plan.collapsed) == "table"
        and db.plan.collapsed["+" .. key] == true
end
Plan.IsOpenRow = IsOpen

function Plan.ToggleOpen(key)
    local db = ns.db
    if not (type(db) == "table" and type(db.plan) == "table") then return end
    if type(db.plan.collapsed) ~= "table" then db.plan.collapsed = {} end
    db.plan.collapsed["+" .. key] = (not IsOpen(key)) or nil
    Plan:Refresh()
end

-- The Way point of a chain step: its quest's giver, else the NPC named before "," in "NPC, place".
local function StepPoint(s)
    local Way, S = ns.Way, ns.Steps
    if not (Way and Way.Point and s) then return nil end
    for _, f in ipairs(S.Rows("quest", s.name, nil) or {}) do
        if f[1] == "giver" and f[2] and f[2] ~= "" then
            local p = Way.Point("npc", f[2])
            if p then return p end
        end
    end
    local npc = s.where and s.where:match("^%s*([^,]+)")
    return npc and Way.Point("npc", npc) or nil
end
Plan.StepPoint = StepPoint

-- Texts of a rep row: name, value, status parts, colour keys.
function Plan.RepTexts(f)
    local S = ns.Steps
    local statusKey = f.later and "planNote" or (f.ready and "repReady" or "repNeed")
    return S.DisplayName(f.rep, f.faction), S.StandingText(f.rep), { C(statusKey):WrapTextInColorCode(S.NeedText(f)) }
end

-- Texts of a chain row: name, value, status parts.
function Plan.ChainTexts(st)
    local S = ns.Steps
    local name = S.ShortTitle(st.title or st.key)
    local value = S.ChainText(st)
    local parts = {}
    if st.complete then
        parts[1] = C("planHave"):WrapTextInColorCode(T("CHAIN_DONE", "done")) .. " " .. Inline(Theme.art.tick, 12)
    elseif not st.known then
        parts[1] = C("planNote"):WrapTextInColorCode(T("CHAIN_STEPS", "%d steps"):format(st.total or #st.steps))
    else
        local s = st.steps[st.next or 1]
        if s then
            parts[1] = C("stepNext"):WrapTextInColorCode(T("CHAIN_NEXT", "next: %s"):format(s.name))
            if s.where and s.where ~= "" then parts[2] = C("planNote"):WrapTextInColorCode(s.where) end
        end
    end
    return name, value, parts
end

local function RepTooltip(row)
    local S, d = ns.Steps, row.gsData
    if not d then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.gsKind == "other" then
        GameTooltip:SetText(T("PLAN_OTHER_HEAD", "Not from a run"), C("planHead"):GetRGB())
        Theme.AddHint(GameTooltip, T("REP_FOLD_TIP", "Click: show or hide the details."))
        GameTooltip:AddLine(T("PLAN_OTHER_TIP", "Pieces from quests, vendors, crafting or world drops. Click a piece for its guide."),
            C("planNote"):GetRGB(), true)
    elseif row.gsKind == "rep" then
        GameTooltip:SetText(S.DisplayName(d.rep, d.faction), C("planHead"):GetRGB())
        Theme.AddHint(GameTooltip, T("REP_FOLD_TIP", "Click: show or hide the details."))
        GameTooltip:AddLine(T("REP_YOU", "You: %s"):format(S.RepText(d.rep, d.goal and S.STANDINGS[d.goal])), C("text"):GetRGB())
        for i, a in ipairs(d.id and S.AltRep(d.id) or {}) do
            if i > 5 then break end
            GameTooltip:AddLine(S.AltRepText(a), C("planNote"):GetRGB())
        end
        local names = {}
        for _, p in ipairs(d.pieces or {}) do
            if #names >= 6 then names[#names + 1] = "..." break end
            names[#names + 1] = (ItemName(p.itemID) or ("item " .. p.itemID)) .. (p.need and (" (" .. p.need .. ")") or "")
        end
        if #names > 0 then
            GameTooltip:AddLine(T("REP_FOR", "Needed for: %s"):format(table.concat(names, ", ")), C("planNote"):GetRGB(), true)
        end
    else
        GameTooltip:SetText(d.title or d.key, C("planHead"):GetRGB())
        Theme.AddHint(GameTooltip, T("REP_FOLD_TIP", "Click: show or hide the details."))
        local v = S.ChainText(d)
        if v ~= "" then GameTooltip:AddLine(v, C("text"):GetRGB()) end
        for _, a in ipairs(S.AltChains(d.key) or {}) do
            GameTooltip:AddLine(("%s: %s"):format(a.name, a.text), C("planNote"):GetRGB())
        end
        if not d.known then GameTooltip:AddLine(T("CHAIN_NO_IDS", "Progress not known for this chain yet."), C("planNote"):GetRGB(), true) end
    end
    GameTooltip:Show()
end

local function RepRow(self, i)
    self.repRows = self.repRows or {}
    local r = self.repRows[i]
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
    r.name = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.name, "normal")
    r.name:SetPoint("LEFT", sz.nameX, 0)
    r.name:SetWidth(sz.nameW)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    -- the bar (W.RepBar, art from Theme.art.repBar; ui-b6 #5 / #7), value always right of it (#3)
    r.bar = W.RepBar(r, sz.repBarW, sz.repBarH)
    r.bar:SetPoint("LEFT", sz.infoX, 0)
    r.value = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.value, "small")
    r.value:SetJustifyH("LEFT")
    r.value:SetWordWrap(false)
    r.value:SetPoint("LEFT", sz.infoX + sz.repBarW + sz.gap, 0)
    r.value:SetWidth(sz.infoW + sz.gap + sz.countW - sz.repBarW - sz.gap)
    r.way = SmallButton(r, Theme.art.wayPin, Theme.sizes.way or 14,
        function(b) if b.gsPoint and ns.Way then ns.Way.Tooltip(b, b.gsPoint) end end,
        function(b) if b.gsPoint and ns.Way then ns.Way:Go(b.gsPoint) end end)
    r.way:SetPoint("RIGHT", -4, 0)
    r.status = r:CreateFontString(nil, "OVERLAY")
    Theme.Font(r.status, "small")
    r.status:SetPoint("LEFT", sz.infoX + sz.infoW + sz.gap + sz.countW + sz.gap, 0)
    r.status:SetPoint("RIGHT", r.way, "LEFT", -sz.gap, 0)
    r.status:SetJustifyH("LEFT")
    r.status:SetWordWrap(true)
    r:SetScript("OnClick", function()
        if r.gsKey then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            Plan.ToggleOpen(r.gsKey)
        end
    end)
    r:SetScript("OnEnter", RepTooltip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    self.repRows[i] = r
    return r
end

local function FillRep(r, kind, d, rowW)
    local sz, S = Sizes(), ns.Steps
    r.gsKind, r.gsData = kind, d
    r.gsKey = (kind == "rep" and "rep:" .. d.faction) or (kind == "other" and "other") or ("chain:" .. d.key)
    local ex = Theme.art.expand
    if not Theme.TryTexture(r.fold, Plan.IsOpenRow(r.gsKey) and ex.minus or ex.plus) then r.fold:Hide() else r.fold:Show() end
    local name, value, parts
    if kind == "rep" then name, value, parts = Plan.RepTexts(d)
    elseif kind == "other" then name, value, parts = T("PLAN_OTHER_ROW", "All pieces"), Plan.CountText(d.n or 0), {}
    else name, value, parts = Plan.ChainTexts(d) end
    local grey = kind == "rep" and d.later
    r.name:SetText(name)
    r.name:SetTextColor(C(grey and "planLocked" or "planHead"):GetRGB())
    -- ui-b6 #3: every rep row has the bar (unmet: empty), known chains a done/total bar, the value
    -- always in the same column; #5: greyed on "not out yet" rows.
    if kind == "rep" then
        r.bar:Show()
        if d.rep then
            local cr, cg, cb = S.BarColor(d.rep, d.ready)
            r.bar:SetValue(d.rep.met and S.Fraction(d.rep) or 0, cr, cg, cb, grey)
        else
            r.bar:SetValue(0)
        end
    elseif kind == "chain" and d.known and (d.total or 0) > 0 then
        r.bar:Show()
        r.bar:SetValue((d.done or 0) / d.total, C(d.complete and "planHave" or "chainBar"):GetRGB())
    else
        r.bar:Hide()
    end
    r.value:SetText(value or "")
    r.value:SetTextColor(C(grey and "planLocked" or "text"):GetRGB())
    local p = (kind == "chain" and not d.complete and d.known) and StepPoint(d.steps[d.next or 1]) or nil
    r.way.gsPoint = p
    r.way:SetShown(p ~= nil)
    local m = Plan.measure
    local room = rowW - (sz.infoX + sz.infoW + sz.gap + sz.countW + sz.gap) - (4 + (r.way:GetWidth() or Theme.sizes.way or 14) + sz.gap)
    local text, n = Plan.StatusLines(parts, room, function(s)
        if not m then return 0 end
        m:SetText(s)
        return m:GetStringWidth() or 0
    end)
    r.status:SetText(text)
    r:SetHeight(math.max(sz.head, n * sz.line + 8))
end

-- The lines under an open rep / chain row: { { text, color[, mark] } }. Chain steps carry a mark
-- ("tick" done / "next" / "none") for the fixed slot in front (ui-b6 #1); no tick inside the text.
function Plan.RepLines(kind, d)
    local S = ns.Steps
    local out = {}
    if kind == "rep" then
        local tok = S.TokenText(d.faction)
        if tok then out[#out + 1] = { text = tok, color = "planNote" } end
        for i, a in ipairs(d.id and S.AltRep(d.id) or {}) do
            if i > 3 then break end
            out[#out + 1] = { text = S.AltRepText(a), color = "planNote" }
        end
    else
        for i, s in ipairs(d.steps) do
            local isNext = d.known and d.next == i
            local color = (s.state and "stepDone") or (isNext and "stepNext") or "stepOpen"
            local text = ("%s. %s"):format(i, s.name)
            if s.where and s.where ~= "" then text = text .. " " .. C("planNote"):WrapTextInColorCode("- " .. s.where) end
            out[#out + 1] = { text = text, color = color, mark = (s.state and "tick") or (isNext and "next") or "none",
                head = ("%s. %s"):format(i, s.name), where = (s.where and s.where ~= "") and s.where or nil }
        end
        for _, a in ipairs(S.AltChains(d.key) or {}) do
            out[#out + 1] = { text = ("%s: %s"):format(a.name, a.text), color = "planNote" }
        end
    end
    return out
end

-- One RepLines line -> the rows it takes in `room` px (measure(text) -> px, 15 % margin like the
-- status column): a step too long for one row puts its "- NPC, place" part on the rows under it,
-- split at ", " (blank mark slot, so they line up with the step text). -> { { text, color, mark } }.
function Plan.StepRows(l, room, measure)
    local fit = room * 0.85
    if not (l.where and l.head) or measure(l.text) <= fit then return { l } end
    local rows = { { text = l.head, color = l.color, mark = l.mark } }
    local pieces = {}
    for p in (l.where .. ", "):gmatch("(.-), ") do if p ~= "" then pieces[#pieces + 1] = p end end
    local cur = "- " .. (pieces[1] or "")
    local function Push(s) rows[#rows + 1] = { text = C("planNote"):WrapTextInColorCode(s), color = "planNote", mark = "none" } end
    for i = 2, #pieces do
        local joined = cur .. ", " .. pieces[i]
        if measure(joined) <= fit then cur = joined else Push(cur .. ","); cur = pieces[i] end
    end
    Push(cur)
    return rows
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
    self.repHead = ns.Progress.Head(child, T("PLAN_REP_HEAD", "Reputation and chains"))   -- beta.6
    self.repRows = {}
    self.otherHead = ns.Progress.Head(child, T("PLAN_OTHER_HEAD", "Not from a run"))   -- beta.6 (ui-b6 #4)
    self.empty =child:CreateFontString(nil, "OVERLAY")
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

    -- hidden, for measuring status parts in the real font (same font as the status column)
    Plan.measure = page:CreateFontString(nil, "OVERLAY")
    Theme.Font(Plan.measure, "small")
    Plan.measure:Hide()

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
        -- b6-pretest bug 1: keep false ("not attuned"); `ok and att or nil` turned it into nil
        if ok then e.attuned = att else e.attuned = nil end
    end
    -- beta.6: factions and chains for the wanted pieces and these runs
    local S = ns.Steps
    if S and S.ForPlan then
        local okS, st = pcall(S.ForPlan, R.Wanted(), plan.runs)
        plan.steps = okS and st or nil
        -- a run's attunement word gets the chain step ("not attuned (step 3 of 16)")
        for _, e in ipairs(plan.runs) do
            for _, f in ipairs(S.Rows("place", e.run, nil) or {}) do
                if f[1] == "att" and f[3] and plan.steps then
                    for _, c in ipairs(plan.steps.chains) do
                        if c.key == f[3] and c.known and not c.complete then
                            e.attStep = S.ChainText(c)
                            local s = c.steps[c.next or 1]
                            e.attNext = s and s.name ~= "" and s.name or nil   -- run tooltip (ui-b6 #8)
                        end
                    end
                end
            end
        end
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
    -- beta.6: reputation and chains
    local steps = plan.steps or { reps = {}, chains = {} }
    local nr = 0
    local anyRep = #steps.reps + #steps.chains > 0
    Section(self.repHead, anyRep)
    local function RepBlock(kind, d)
        nr = nr + 1
        local r = RepRow(self, nr)
        FillRep(r, kind, d, width - 4)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        r:SetWidth(width - 4)
        r:Show()
        y = y + r:GetHeight() + 2
        if kind ~= "other" and IsOpen(r.gsKey) then
            -- ui-b6 #8: the lines start under the row's name
            local room = width - 4 - sz.nameX - sz.stepSlot - sz.gap
            local m = Plan.measure
            local function Measure(s)
                if not m then return 0 end
                m:SetText(s)
                return m:GetStringWidth() or 0
            end
            for _, l in ipairs(Plan.RepLines(kind, d)) do
                for _, row in ipairs(Plan.StepRows(l, room, Measure)) do
                    Line("text", { x = sz.nameX, color = row.color, text = row.text, mark = row.mark })
                end
            end
            y = y + 4
        end
    end
    for _, f in ipairs(steps.reps) do RepBlock("rep", f) end
    for _, c in ipairs(steps.chains) do RepBlock("chain", c) end
    if anyRep then y = y + 8 end
    -- runs (a "Runs" heading when the hand-in or rep section is above them)
    Section(self.runsHead, (#hand > 0 or anyRep) and #plan.runs > 0)
    local anyRaid = false
    for _, e in ipairs(plan.runs) do
        nh = nh + 1
        if e.facts.kind == "raid" then anyRaid = true end
        local r = HeadRow(self, nh)
        FillHead(r, e, now, width - 4)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
        r:SetWidth(width - 4)
        r:Show()
        y = y + r:GetHeight() + 2
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
    if #plan.runs > 0 then y = y + 8 end   -- the same gap before the next heading as after the other sections
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
    -- beta.6 (ui-b6 #4): "Not from a run" - the wanted pieces with no dungeon / raid source, one
    -- clickable row each (source word, icon + name, Need); more than 8: one fold row, closed by default.
    local otherIDs = plan.otherIDs or {}
    Section(self.otherHead, #otherIDs > 0)
    if #otherIDs > 0 then
        local show = true
        if #otherIDs > Plan.OTHER_FOLD then
            RepBlock("other", { n = #otherIDs })
            show = IsOpen("other")
        end
        if show then
            local m = Plan.measure
            local function Measure(s)
                if not m then return 0 end
                m:SetText(s)
                return m:GetStringWidth() or 0
            end
            local room = sz.pieceX - sz.indent - sz.gap   -- the boss column
            for _, id in ipairs(otherIDs) do
                local full, short = Plan.SourceText(id)
                Line("piece", { boss = Plan.FitText(full, short, room, Measure), source = full,
                    piece = { itemID = id, mine = true } })
            end
        end
        y = y + 8
    end
    for i = nr + 1, #self.repRows do self.repRows[i]:Hide() end
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
    -- the list starts right under the title when there is no lockouts line (no empty band; screenshot)
    local top = (saved > 0 or anyRaid) and sz.top or (sz.top - (sz.locksH or 16))
    if self.scrollTop ~= top then
        self.scrollTop = top
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", sz.titleX - 4, -top)
        self.scroll:SetPoint("BOTTOMRIGHT", sz.summaryX, 30)
    end
    self.locksLine:SetText(saved > 0 and T("PLAN_LOCKS", "Raid lockouts: %d saved"):format(saved)
        or T("PLAN_LOCKS_NONE", "Raid lockouts: none saved"))
    -- the old "Not from a run: n pieces" footer: replaced by the section above (ui-b6 #4)
    self.note:Hide()
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
