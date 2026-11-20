-- Gear Set: right panel - the set's pieces and whether you have or need each one.
-- Header: set name (prev/next arrows), armor type + classes, a "have x / y" bar (tooltip
-- with the breakdown), then "Set bonuses (x/y)", "Stats" (can you wear it + summed stats)
-- and "Effort: High" (reasons), each with a tooltip; a divider above the list.
-- Each row: check box (piece shown on the preview), icon with quality frame, name
-- (up to 2 lines), state, arrow. Clicking a row opens the piece's guide page
-- (UI\GuidePage.lua) in place of the list; Back / Esc / right-click return here.
-- Shift/Ctrl-click = Blizzard's usual item clicks (link in chat box, dressing room).
-- Shared buttons and helpers: UI\Widgets.lua (ns.Widgets).
local _, ns = ...
local Theme, L, W = ns.Theme, ns.L, ns.Widgets

local PieceList = {}
ns.PieceList = PieceList

local ROW_H = Theme.sizes.pieceRow or 36
local ICON_LEFT = 28        -- icon starts right of the check box
local ROW_GAP = Theme.sizes.pieceRowGap or 2   -- px between rows (journal lists: each row has its own bar)
-- Header (ui-review-3): title at -10, armor/classes, the "have" bar, the label row
-- ("Set bonuses  Stats  Effort"), a divider, then the list.
local INFO_TOP = -32
local BAR_TOP = -50
local LABELS_TOP = -70
local DIVIDER_TOP = -88
local LIST_TOP = -94

-- beta.7 alt memory (Alts.lua). Mailbox / keyring / account bank state: "seen N days ago";
-- a piece this character lacks: "Also on: Bankalt (bank)" (+n more). nil = no line.
local ALT_MAX_W = 170
local SEEN_STATES = { mail = true, keyring = true, account = true }
local function Alts() return ns.Alts end

function PieceList.AltLine(piece, state)
    local A = Alts()
    if not (A and piece) then return nil end
    if SEEN_STATES[state] then
        local ok, _, seen = pcall(A.MyPlace, A, piece.itemID)
        return ok and A.SeenText(seen) or nil
    end
    if state ~= "need" and state ~= "look" then return nil end
    local ok, list = pcall(A.OthersHolding, A, piece.itemID)
    if not ok or type(list) ~= "table" or #list == 0 then return nil end
    local h = list[1]
    local text = L.ALT_HOLDER:format(tostring(h.name), A.WhereText(h.where))
    if #list > 1 then text = L.ALT_MORE:format(text, #list - 1) end
    return L.ALT_ALSO_ON:format(text)
end

-- Shows the line under the state (both move up/down a bit) and keeps the name left of the wider one.
local function PlaceAltLine(row, text)
    if not row.alt then return end
    if not text then
        row.alt:Hide()
        row.state:SetPoint("RIGHT", row.marker, "LEFT", -6, 0)
        row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
        return
    end
    row.alt:SetWidth(0)
    row.alt:SetText(text)
    local w = row.alt:GetStringWidth() or 0
    if w > ALT_MAX_W then row.alt:SetWidth(ALT_MAX_W); w = ALT_MAX_W end
    row.alt:Show()
    row.state:SetPoint("RIGHT", row.marker, "LEFT", -6, 7)
    local wider = w > (row.state:GetStringWidth() or 0) and row.alt or row.state
    row.name:SetPoint("RIGHT", wider, "LEFT", -6, 0)
end

-- Tooltip lines: where this character keeps it outside bags/bank, and the other characters.
local function AddAltTooltip(tip, piece, state)
    local A = Alts()
    if not (A and A.GetHolders) then return end
    local ok, list = pcall(A.OthersHolding, A, piece.itemID)
    local sr, sg, sb = Theme.colors.subtle:GetRGB()
    if SEEN_STATES[state] then
        local okP, _, seen = pcall(A.MyPlace, A, piece.itemID)
        local s = okP and A.SeenText(seen)
        tip:AddLine(L["STATE_" .. state] .. (s and (", " .. s) or ""), sr, sg, sb)
    end
    if not ok or type(list) ~= "table" or #list == 0 then return end
    tip:AddLine(L.ALT_TIP_HEAD, Theme.colors.title:GetRGB())
    for i, h in ipairs(list) do
        if i > 6 then
            tip:AddLine(("+%d"):format(#list - 6), sr, sg, sb)
            break
        end
        local s = A.SeenText(h.seen)
        tip:AddLine("  " .. L.ALT_HOLDER:format(tostring(h.name), A.WhereText(h.where))
            .. (s and (", " .. s) or ""), sr, sg, sb)
    end
end

local function PieceTooltip(row)
    local p = row.piece
    if not p then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if p.unknown then   -- v1.0.1: the client has no item to show
        GameTooltip:SetText((L.UNKNOWN_ITEM or "Item %d"):format(p.itemID), 1, 1, 1)
        local r, g, b = Theme.colors.later:GetRGB()
        GameTooltip:AddLine(ns.Data.FlagText("FLAG_UNKNOWN"), r, g, b, true)
        GameTooltip:AddLine(" ")
        Theme.AddHint(GameTooltip, L.PIECE_TIP)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetItemByID(p.itemID)
    pcall(AddAltTooltip, GameTooltip, p, ns.Owned:GetState(p))
    -- beta.8: gold (PART B's Gold.lua) and tracking
    local P = ns.Progress
    local cost = P and P.PieceCostText and P.PieceCostText(p.itemID)
    if cost then GameTooltip:AddLine(cost, Theme.colors.subtle:GetRGB()) end
    if ns.Track and ns.Track.IsPiece(p.itemID) then
        GameTooltip:AddLine(L.TRACKED or "Tracked", Theme.colors.partial:GetRGB())
    end
    GameTooltip:AddLine(" ")
    Theme.AddHint(GameTooltip, L.PIECE_TIP)
    Theme.AddHint(GameTooltip, L.PIECE_TIP_MOD)
    GameTooltip:Show()
end

local InitRow

local function BuildRow(row)
    row.gsInit = true
    row:RegisterForClicks("LeftButtonUp")

    -- Row bar under everything (Mount/Pet journal and Wardrobe set rows); a faint colour
    -- band if the atlas is missing, nothing without a Theme entry.
    local bgArt = Theme.art.rowBackground
    row.bg = row:CreateTexture(nil, "BACKGROUND", nil, 0)
    row.bg:SetPoint("TOPLEFT")
    row.bg:SetPoint("TOPRIGHT")
    row.bg:SetHeight(ROW_H)
    local drawn = Theme.SetArt(row.bg, bgArt) or (bgArt and bgArt.file)
    if not drawn and bgArt and bgArt.color then
        row.bg:SetColorTexture(unpack(bgArt.color))
        drawn = true
    end
    row.bg:SetShown(drawn and true or false)

    -- Last piece looked at: the select art (like the chosen set).
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.sel:SetPoint("TOPLEFT")
    row.sel:SetPoint("TOPRIGHT")
    row.sel:SetHeight(ROW_H)
    Theme.SetArt(row.sel, Theme.art.rowSelected)
    row.sel:Hide()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetPoint("TOPLEFT")
    row.hl:SetPoint("TOPRIGHT")
    row.hl:SetHeight(ROW_H)
    Theme.SetArt(row.hl, Theme.art.rowHover)
    row.hl:SetBlendMode("ADD")

    -- Check box: piece tried on the preview.
    local cs = Theme.sizes.check
    local check = Theme.CreateFrame("CheckButton", nil, row, "check")
    check:SetSize(cs, cs)
    check:SetPoint("TOPLEFT", 2, -(ROW_H - cs) / 2)
    check:SetScript("OnClick", function(self)
        local p = row.piece
        if not p then return end
        local shown = self:GetChecked() and true or false
        PlaySound(shown and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        ns.Preview:SetPieceShown(p.itemID, shown)
        row.icon:SetDesaturated(not shown)
    end)
    check:SetScript("OnEnter", function(self)
        local p = row.piece
        if not p then return end
        if p.unknown then W.SimpleTip(self, ns.Data.FlagText("FLAG_UNKNOWN"))
        elseif row.laterOff then W.SimpleTip(self, ns.Data.FlagText("FLAG_LATER"))
        else W.SimpleTip(self, W.ShowsOnModel(p) and L.SHOW_PIECE_TIP or L.NO_MODEL_TIP) end
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    row.check = check

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("TOPLEFT", ICON_LEFT, -3)
    row.icon:SetTexCoord(unpack(W.ICON_CROP))
    row.border, row.hasBorder = W.IconBorder(row, row.icon)
    -- beta.8: tracking star hung on the icon's top-left corner, half outside it (like the
    -- Wardrobe set rows' favourite star), so it doesn't sit on the quality frame.
    if ns.Track and ns.Track.MakeStar then
        row.star = ns.Track.MakeStar(row, "OVERLAY")
        row.star:SetPoint("CENTER", row.icon, "TOPLEFT", -1, 1)
    end

    -- Arrow at the right end: the row opens a page. ">" if the art is missing.
    local arrow = Theme.art.rowArrow
    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetSize(arrow.size, arrow.size)
    row.marker:SetPoint("RIGHT", row, "TOPRIGHT", -6, -ROW_H / 2)
    if not Theme.TryTexture(row.marker, arrow.file) then
        row.marker:Hide()
        local t = row:CreateFontString(nil, "OVERLAY")
        Theme.Font(t, "normal")
        t:SetPoint("CENTER", row.marker, "CENTER")
        t:SetText(">")
    end

    row.state = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.state, "small")
    row.state:SetPoint("RIGHT", row.marker, "LEFT", -6, 0)
    row.state:SetJustifyH("RIGHT")
    -- beta.7: small grey line under the state: "Also on: Bankalt (bank)" or "seen 3 days ago".
    row.alt = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.alt, "small")
    row.alt:SetPoint("RIGHT", row.marker, "LEFT", -6, -7)
    row.alt:SetJustifyH("RIGHT")
    if row.alt.SetWordWrap then row.alt:SetWordWrap(false) end
    row.alt:SetTextColor(Theme.colors.subtle:GetRGB())
    row.alt:Hide()
    -- Name: up to 2 lines (fits the 36 px row), so long names aren't cut.
    row.name = row:CreateFontString(nil, "OVERLAY")
    Theme.Font(row.name, "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(true)
    if row.name.SetMaxLines then row.name:SetMaxLines(2) end

    row:SetScript("OnClick", function(self)
        local p = self.piece
        if not p then return end
        -- Shift-click: track / untrack (beta.8); while typing in chat it links the item
        -- instead (never both). Ctrl-click: dressing room. Nothing is ever sent to chat.
        if ns.Track and IsModifiedClick and IsModifiedClick("CHATLINK") and not PieceList.ChatOpen() then
            ns.Track.TogglePiece(p.itemID)
            return
        end
        if W.HandleModifiedClick(p.itemID) then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        GameTooltip_Hide()
        PieceList:ShowGuide(p)
    end)
    row:SetScript("OnEnter", PieceTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

-- A chat edit box is open (shift-click then links the item instead of tracking it).
function PieceList.ChatOpen()
    local fn = (type(ChatFrameUtil) == "table" and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
    if type(fn) ~= "function" then return false end
    local ok, box = pcall(fn)
    return ok and box ~= nil and box ~= false
end

-- Item loaded later: refill the row (Widgets only calls back while it still shows that item).
local function OnRowItemLoaded(row)
    if row.piece then InitRow(row, row.piece) end
end

InitRow = function(row, piece)
    if not row.gsInit then BuildRow(row) end
    row.piece = piece
    local itemID = piece.itemID

    local _, _, _, _, icon = ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant)(itemID)
    row.icon:SetTexture(icon or 134400)  -- 134400 = question mark icon
    local hidden = ns.Preview:IsHidden(itemID)
    -- Not out yet in a released set: greyed, not on the model, not counted (set.later).
    local set = PieceList.set
    -- v1.0.1: a piece this client doesn't know looks the same way (greyed, off the model).
    local laterOff = (piece.later and not (set and set.unreleased)) or piece.unknown == true
    row.laterOff = laterOff
    row.icon:SetDesaturated(hidden or laterOff)

    if W.ShowsOnModel(piece) and not laterOff then
        row.check:Enable()
        row.check:SetChecked(not hidden)
    else
        row.check:SetChecked(false)
        row.check:Disable()
    end

    if piece.unknown then
        -- never loads: no "Loading..." that stays forever
        row.gsItem = itemID
        if row.border then row.border:Hide() end
        row.name:SetText((L.UNKNOWN_ITEM or "Item %d"):format(itemID))
        row.name:SetTextColor(Theme.colors.later:GetRGB())
    else
        W.FillItem(row, itemID, OnRowItemLoaded)
    end
    row.name:SetAlpha((piece.later or piece.unknown) and 0.6 or 1)

    local state = ns.Owned:GetState(piece)
    if piece.unknown then
        row.state:SetText(L.STATE_unknown or "Not in this game version")
        row.state:SetTextColor(Theme.colors.later:GetRGB())
    elseif piece.later and not ns.Owned:IsHave(piece) then
        row.state:SetText(ns.Data.FlagText("FLAG_LATER_SHORT"))
        row.state:SetTextColor(Theme.colors.later:GetRGB())
    else
        row.state:SetText(L["STATE_" .. state])
        row.state:SetTextColor(W.StateColor(state):GetRGB())
    end
    -- Under the state: the alt line, else (piece still needed) its fixed gold cost.
    local extra = PieceList.AltLine(piece, state)
    if not extra and not piece.unknown and not ns.Owned:IsHave(piece) and ns.Progress and ns.Progress.PieceMoney then
        extra = ns.Progress.PieceMoney(itemID)
    end
    PlaceAltLine(row, extra)
    if row.star then row.star:SetShown(ns.Track ~= nil and ns.Track.IsPiece(itemID)) end

    row.sel:SetShown(PieceList.lastItem == itemID)
end

-- ---------------------------------------------------------------------------
-- Guide page: shown in place of the header and list (same right panel).
function PieceList:ShowGuide(piece)
    if not (piece and ns.GuidePage and ns.GuidePage.page) then return end
    self.root:Hide()
    ns.GuidePage:Open(piece, self.set)
end

function PieceList:HideGuide()
    if ns.GuidePage and ns.GuidePage:IsOpen() then ns.GuidePage:Back()
    elseif self.root then self.root:Show() end
end

-- Called by GuidePage when its page hides (Back, Esc, right-click, window closed):
-- the list comes back, the piece last looked at is marked and scrolled into view.
function PieceList:OnGuideClosed()
    if not self.root then return end
    local p = ns.GuidePage and ns.GuidePage.piece
    self.lastItem = p and p.itemID or nil
    self.root:Show()
    self:Refresh()
    if p and self.set and self.box.ScrollToElementData then
        for _, sp in ipairs(self.set.shown or self.set.pieces) do
            if sp == p then
                local align = ScrollBoxConstants and ScrollBoxConstants.AlignNearest
                pcall(self.box.ScrollToElementData, self.box, sp, align)
                break
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Header

-- Armor type (gold) and classes (class colours), e.g. "Plate - Warrior, Paladin".
local function SetInfoText(set)
    local parts = {}
    local armor = ns.Data.ArmorName(set.armor)
    if armor then parts[1] = Theme.colors.armorLine:WrapTextInColorCode(armor) end
    -- Class names in class colours; Dungeon Set 1/2 add "(any class can wear it)".
    local classes = ns.SetList and ns.SetList.ClassText and ns.SetList.ClassText(set)
    if not classes then classes = L.ALL_CLASSES end
    if classes ~= "" then parts[#parts + 1] = classes end
    return table.concat(parts, " - ")
end

-- Set bonuses only count pieces you wear (not bags, bank or appearances).
local function WornCount(set)
    return ns.Owned:SetBreakdown(set).equipped or 0
end

-- A bonus is in effect when you wear enough pieces (or the game already showed it as on).
local function BonusOn(b, worn)
    return b.active or (b.n ~= nil and worn >= b.n)
end

-- How many bonuses are in effect, and how many there are.
function PieceList.BonusCount(bonuses, worn)
    local on = 0
    for _, b in ipairs(bonuses) do
        if BonusOn(b, worn) then on = on + 1 end
    end
    return on, #bonuses
end

-- "Set bonuses" tooltip, like the set block of Blizzard's item tooltip: set name with
-- pieces worn, then each bonus green when worn pieces reach it, else grey. Read on hover
-- (Data caches per set; one retry if the item hasn't loaded, then it refills if still hovered).
local function BonusTooltip(self)
    local set = PieceList.set
    if not set then return end
    local refilled = false
    local bonuses = ns.Data:GetSetBonuses(set, function(doneSet)
        refilled = true
        if PieceList.set == doneSet then
            PieceList:UpdateBonuses()
            if GameTooltip:IsOwned(self) then BonusTooltip(self) end
        end
    end)
    if refilled then return end      -- the callback ran at once and already drew it
    local worn, total = WornCount(set), #set.pieces
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    local head = Theme.colors.bonusTitle
    GameTooltip:SetText(L.BONUS_TITLE:format(set.name, worn, total), head:GetRGB())
    if not bonuses then
        GameTooltip:AddLine(L.LOADING, Theme.colors.loading:GetRGB())
    elseif #bonuses == 0 then
        GameTooltip:AddLine(L.BONUS_NONE, Theme.colors.subtle:GetRGB())
    else
        local on, off = Theme.colors.bonusOn, Theme.colors.bonusOff
        for _, b in ipairs(bonuses) do
            local text = b.n and L.BONUS_LINE:format(b.n, b.text) or L.BONUS_ACTIVE:format(b.text)
            local r, g, bl = (BonusOn(b, worn) and on or off):GetRGB()
            GameTooltip:AddLine(text, r, g, bl, true)
        end
        GameTooltip:AddLine(" ")
        local r, g, bl = Theme.colors.subtle:GetRGB()
        GameTooltip:AddLine(L.BONUS_WEARING:format(worn, total), r, g, bl, true)
    end
    GameTooltip:Show()
end

-- "Set bonuses (1/3)" next to "Have x / y"; greyed when the set has no bonus.
function PieceList:UpdateBonuses()
    local b, set = self.bonuses, self.set
    if not (b and set) then return end
    local refilled = false
    local bonuses = ns.Data:GetSetBonuses(set, function(doneSet)
        refilled = true
        if PieceList.set == doneSet then
            PieceList:UpdateBonuses()
            if GameTooltip:IsOwned(b) then BonusTooltip(b) end
        end
    end)
    if refilled then return end
    if bonuses and #bonuses > 0 then
        b:SetLinkText(L.BONUSES_N:format(PieceList.BonusCount(bonuses, WornCount(set))))
        b:SetDim(false)
    else
        b:SetLinkText(L.BONUSES)
        b:SetDim(bonuses ~= nil)     -- loading: normal; no bonus at all: grey
    end
end

-- Text with an English fallback (keys part A adds to ns.L at the merge).
local function T(key, fallback) return L[key] or fallback end

-- Fields of a stats row: { name, total } or { name = , total = } (same for equip lines).
local function Pair(row, k1, k2)
    if type(row) ~= "table" then return nil end
    return row[k1] or row[1], row[k2] or row[2]
end

-- "Stats" tooltip: can you wear it, then the set's stats added up from the live item
-- tooltips (Data:GetSetStats, cached per set; "Loading..." then a refill like the bonuses).
local function StatsTooltip(self)
    local set = PieceList.set
    local D = ns.Data
    if not (set and D and D.GetSetStats) then return end
    local refilled = false
    local ok, stats = pcall(D.GetSetStats, D, set, function(doneSet)
        refilled = true
        if PieceList.set == doneSet and GameTooltip:IsOwned(self) then StatsTooltip(self) end
    end)
    if refilled then return end
    if not ok then stats = nil end
    local c = Theme.colors
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(T("STATS_TITLE", "%s: stats"):format(set.name), c.bonusTitle:GetRGB())
    -- Can you wear it (our data: class mask / hint / armor type)?
    local armor = D.ArmorName and D.ArmorName(set.armor)
    local fit = D.CanWear and D.CanWear(set)
    if fit ~= nil and armor then
        local col = fit and (c.fitYes or c.bonusOn) or (c.fitNo or c.bonusOff)
        local text = fit and T("FIT_YES", "You can wear it (%s).")
            or T("FIT_NO", "Your class can't wear this armor (%s).")
        local r, g, b = col:GetRGB()
        GameTooltip:AddLine(text:format(armor), r, g, b, true)
    end
    if not stats then
        GameTooltip:AddLine(L.LOADING, c.loading:GetRGB())
    else
        local list = type(stats.stats) == "table" and stats.stats or {}
        local equip = type(stats.equip) == "table" and stats.equip or {}
        if #list == 0 and #equip == 0 then
            GameTooltip:AddLine(T("STATS_NONE", "No stats found."), c.subtle:GetRGB())
        else
            local pieces = tonumber(stats.pieces) or #set.pieces
            GameTooltip:AddLine(T("STATS_ALL", "All %d pieces together:"):format(pieces), c.text:GetRGB())
            for _, s in ipairs(list) do
                local name, total = Pair(s, "name", "total")
                total = tonumber(total)
                if name and total then
                    GameTooltip:AddLine(("  %+d %s"):format(total, tostring(name)), c.text:GetRGB())
                end
            end
            local r, g, b = c.bonusOn:GetRGB()
            for _, e in ipairs(equip) do
                local text, count = Pair(e, "text", "count")
                count = tonumber(count) or 1
                if text then
                    local line = count > 1 and ("%dx %s"):format(count, tostring(text)) or tostring(text)
                    GameTooltip:AddLine("  " .. line, r, g, b, true)
                end
            end
        end
        GameTooltip:AddLine(T("STATS_SOURCE", "From the item tooltips in this game."), c.none:GetRGB())
    end
    GameTooltip:Show()
end

-- "Effort: High" tooltip: the pieces still needed, the reasons, a hint.
local function EffortTooltip(self)
    local set = PieceList.set
    local SL = ns.SetList
    local e = set and SL and SL.GetEffort and SL.GetEffort(set)
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    local title = T("EFFORT_TITLE", "Effort for the %d pieces you still need: %s")
    GameTooltip:SetText(title:format(tonumber(e.need) or 0, SL.EffortWord(e)), SL.EffortRGB(e))
    local r, g, b = Theme.colors.text:GetRGB()
    for _, text in ipairs(type(e.reasons) == "table" and e.reasons or {}) do
        GameTooltip:AddLine("  " .. tostring(text), r, g, b, true)
    end
    Theme.AddHint(GameTooltip, T("EFFORT_HINT", "Click a piece to see how to get it."))
    GameTooltip:Show()
end

-- "Effort: High" in its colour; hidden while nothing is needed or without the effort data.
-- The label is gold like "Set bonuses"; only the word has the effort colour.
function PieceList:UpdateEffort()
    local b, set, SL = self.effort, self.set, ns.SetList
    if not b then return end
    local e = set and SL and SL.GetEffort and SL.GetEffort(set)
    if not e or (tonumber(e.level) or 0) == 0 then
        b:Hide()
        return
    end
    -- "Effort:" stays the gold label colour; only the word is coloured.
    local word = CreateColor(SL.EffortRGB(e)):WrapTextInColorCode(SL.EffortWord(e))
    b:SetLinkText(T("EFFORT", "Effort: %s"):format(word))
    b:Show()
end

local function TitleTooltip(self)
    local set = PieceList.set
    if not set then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(set.name, 1, 1, 1, 1, true)
    GameTooltip:AddLine(SetInfoText(set), 1, 1, 1, true)
    GameTooltip:Show()
end

-- "Have x / y" tooltip: what you have, split by where it is.
local BREAKDOWN = {
    { "equipped", "STATE_equipped" }, { "bags", "STATE_bags" }, { "bank", "STATE_bank" },
    { "mail", "STATE_mail" }, { "keyring", "STATE_keyring" }, { "account", "STATE_account" },
    { "look", "APPEARANCE_ONLY" }, { "need", "STATE_need" },
    { "unknown", "STATE_unknown" },   -- v1.0.1: pieces this client doesn't know (in the total)
}
-- "Finished on 2026-11-18" (+ "Stays finished ..." when pieces were upgraded away).
-- Also used by the set list tooltip. Returns true when a line was added.
function PieceList.AddDoneLines(tip, set)
    local O, A = ns.Owned, Alts()
    if not (O and O.CompletedOn and A and set) then return false end
    local ok, t = pcall(O.CompletedOn, O, set)
    if not ok or not t then return false end
    local r, g, b = Theme.colors.have:GetRGB()
    tip:AddLine(L.DONE_ON:format(A.DateText(t) or "?"), r, g, b)
    local bd = O:SetBreakdown(set)
    if (bd.need or 0) > 0 then
        tip:AddLine(L.DONE_KEPT, Theme.colors.subtle:GetRGB())
    end
    return true
end

local function CountTooltip(self)
    local set = PieceList.set
    if not set then return end
    local b = ns.Owned:SetBreakdown(set)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L.HAVE_COUNT:format(ns.Owned:SetCount(set)), 1, 1, 1)
    for _, e in ipairs(BREAKDOWN) do
        if (b[e[1]] or 0) > 0 then
            local r, g, bl = (e[1] == "unknown" and Theme.colors.later or W.StateColor(e[1])):GetRGB()
            local vr, vg, vb = Theme.colors.text:GetRGB()
            GameTooltip:AddDoubleLine(L[e[2]] or e[2], b[e[1]], r, g, bl, vr, vg, vb)
        end
    end
    if b.look > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.APPEARANCE_NOTE, Theme.colors.subtle:GetRGB())
    end
    PieceList.AddDoneLines(GameTooltip, set)
    -- WoW Forever lines: pieces not out yet (not in "Have x / y"), checked / not confirmed.
    if ns.SetList and ns.SetList.AddFlagLines then ns.SetList.AddFlagLines(GameTooltip, set) end
    GameTooltip:Show()
end

local function StepSet(delta)
    if ns.SetList and ns.SetList.SelectRelative then ns.SetList:SelectRelative(delta) end
end

function PieceList:Build(panel)
    -- Header and list live in one frame, so the guide page can stand in for both.
    local parent = CreateFrame("Frame", nil, panel)
    parent:SetAllPoints(panel)
    self.root = parent
    if ns.GuidePage then ns.GuidePage:Build(panel) end

    local nextB = W.ArrowButton(parent, "next", L.NEXT_SET, function() StepSet(1) end)
    nextB:SetPoint("TOPRIGHT", -8, -6)
    local prevB = W.ArrowButton(parent, "prev", L.PREV_SET, function() StepSet(-1) end)
    prevB:SetPoint("RIGHT", nextB, "LEFT", 0, 0)
    self.prevB, self.nextB = prevB, nextB

    local title = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(title, "header")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetPoint("TOPRIGHT", prevB, "TOPLEFT", -4, -4)   -- arrows sit at y -6, title at -10
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    self.title = title
    -- Mouse area over the title: full name + armor/classes in a tooltip.
    local titleHit = CreateFrame("Frame", nil, parent)
    titleHit:SetPoint("TOPLEFT", title, "TOPLEFT")
    titleHit:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT")
    titleHit:EnableMouse(true)
    titleHit:SetScript("OnEnter", TitleTooltip)
    titleHit:SetScript("OnLeave", GameTooltip_Hide)

    local info = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(info, "small")
    info:SetPoint("TOPLEFT", 12, INFO_TOP)
    info:SetPoint("TOPRIGHT", -12, INFO_TOP)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    self.info = info

    -- "Have x / y" as a bar (the Progress tab's bar art), "3 / 8" centred; hover = breakdown.
    local art = Theme.art.progressBar or {}
    local barH = art.height or 14
    local countBar = CreateFrame("Frame", nil, parent)
    countBar:SetPoint("TOPLEFT", 12, BAR_TOP)
    countBar:SetPoint("TOPRIGHT", -12, BAR_TOP)
    countBar:SetHeight(barH + 2)
    local edge = countBar:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(unpack(art.edge or { 0, 0, 0, 0.9 }))
    local fill = CreateFrame("StatusBar", nil, countBar)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    if fill.SetStatusBarTexture then fill:SetStatusBarTexture(art.file or "Interface\\TargetingFrame\\UI-StatusBar") end
    if fill.SetMinMaxValues then fill:SetMinMaxValues(0, 1) end
    if fill.SetValue then fill:SetValue(0) end
    local bg = fill:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(art.bg or { 0, 0, 0, 0.45 }))
    local count = fill:CreateFontString(nil, "OVERLAY")
    Theme.Font(count, "small")
    count:SetPoint("CENTER")
    countBar:EnableMouse(true)
    countBar:SetScript("OnEnter", CountTooltip)
    countBar:SetScript("OnLeave", GameTooltip_Hide)
    self.countBar, self.countFill, self.count = countBar, fill, count

    -- Label row under the bar: "Set bonuses (x/y)", "Stats", "Effort: High" (hover-only,
    -- gold label style, not links).
    local bonuses = W.LinkButton(parent, L.BONUSES, BonusTooltip, nil, "label")
    bonuses:SetPoint("TOPLEFT", 12, LABELS_TOP)
    self.bonuses = bonuses

    -- "Stats" and "Effort: High" right of it, same hover-only label style.
    local stats = W.LinkButton(parent, T("STATS", "Stats"), StatsTooltip, nil, "label")
    stats:SetPoint("LEFT", bonuses, "RIGHT", 12, 0)
    self.stats = stats
    local effort = W.LinkButton(parent, "", EffortTooltip, nil, "label")
    effort:SetPoint("LEFT", stats, "RIGHT", 12, 0)
    effort:Hide()
    self.effort = effort

    -- Line between header and list (same divider as the guide page).
    local div = parent:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", 8, DIVIDER_TOP)
    div:SetPoint("TOPRIGHT", -8, DIVIDER_TOP)
    Theme.SetDivider(div)
    self.divider = div

    local box = Theme.CreateFrame("Frame", nil, parent, "scrollBox")
    box:SetPoint("TOPLEFT", 4, LIST_TOP)
    box:SetPoint("BOTTOMRIGHT", -22, 4)
    local bar = Theme.CreateFrame("EventFrame", nil, parent, "scrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 2)
    self.box = box

    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, ROW_GAP)
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
end

-- Big font for the set name; the smaller one if it doesn't fit.
function PieceList:SetTitle(text)
    local t = self.title
    Theme.Font(t, "header")
    t:SetText(text)
    local w = t:GetWidth() or 0
    if w > 0 and t:GetStringWidth() > w then
        Theme.Font(t, "normal")
        t:SetText(text)
    end
end

-- Another set closes the guide page (back to the list of the new set).
function PieceList:ShowSet(set)
    local changed = set ~= self.set
    self.set = set
    if changed then
        self.lastItem = nil
        if ns.GuidePage and ns.GuidePage:IsOpen() then
            ns.GuidePage:Back()        -- OnGuideClosed refreshes
            self.lastItem = nil
        end
    end
    self:Refresh()
end

-- The "have" bar: filled have/total in the count colour, "3 / 8" on it (empty without a set).
function PieceList:SetCountBar(have, total)
    have, total = tonumber(have) or 0, tonumber(total) or 0
    local fill = self.countFill
    if fill then
        if fill.SetMinMaxValues then fill:SetMinMaxValues(0, math.max(total, 1)) end
        if fill.SetValue then fill:SetValue(math.min(have, math.max(total, 1))) end
        if fill.SetStatusBarColor then fill:SetStatusBarColor(Theme.CountColor(have, total)) end
    end
    self.count:SetText(total > 0 and ("%d / %d"):format(have, total) or "")
end

function PieceList:Refresh()
    if not self.box then return end
    local set = self.set
    local hasSet = set ~= nil
    self.bonuses:SetShown(hasSet)
    self.stats:SetShown(hasSet and ns.Data and ns.Data.GetSetStats ~= nil)
    self:UpdateEffort()          -- the effort cache is cleared via Owned:Invalidate
    self.prevB:SetEnabled(hasSet)
    self.nextB:SetEnabled(hasSet)
    if not hasSet then
        self:SetTitle(L.NO_SET)
        self.info:SetText("")
        self:SetCountBar(0, 0)
        self.box:SetDataProvider(CreateDataProvider({}))
        return
    end
    self:SetTitle(set.name)
    self.info:SetText(SetInfoText(set))
    self:SetCountBar(ns.Owned:SetCount(set))
    self:UpdateBonuses()
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    self.box:SetDataProvider(CreateDataProvider(set.shown or set.pieces), retain)
    if ns.GuidePage and ns.GuidePage:IsOpen() then ns.GuidePage:Refresh() end
end
