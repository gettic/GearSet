-- Gear Set: "Gear Set: Stabby wears Bloodfang 6/8" on a strip under Blizzard's inspect window.
-- Only after the player inspects someone (INSPECT_READY for the unit the open InspectFrame shows).
-- Gear Set never calls NotifyInspect, never saves another player's gear, name or GUID: the result
-- lives in memory only and is wiped when the inspect window closes (plans\v1.0.0\tos-beta7.md).
local _, ns = ...
local Theme, L = ns.Theme, ns.L
local Tip = ns.Tooltip

local Insp = {}
ns.Inspect = Insp

local MAX_LINES = 8
local result = {}   -- { { setID, name, worn, total } } of the shown inspect only

local function Secret(v) return Tip.Secret(v) end

-- Sets the unit wears: list sorted by pieces worn (most first), then name.
function Insp.Count(unit)
    local counts, order = {}, {}
    for slot = 1, 19 do
        local id = GetInventoryItemID(unit, slot)
        if id and not Secret(id) then
            for _, setID in ipairs(Tip.SetIDsOf(id)) do
                if not counts[setID] then order[#order + 1] = setID end
                counts[setID] = (counts[setID] or 0) + 1
            end
        end
    end
    local out = {}
    for _, setID in ipairs(order) do
        local set, name = Tip.SetOf(setID)
        local total = set and #set.pieces or counts[setID]
        if total < counts[setID] then total = counts[setID] end
        out[#out + 1] = { setID = setID, name = name, worn = counts[setID], total = total }
    end
    table.sort(out, function(a, b)
        if a.worn ~= b.worn then return a.worn > b.worn end
        return a.name < b.name
    end)
    return out
end

local function Clear()
    wipe(result)
    Insp.who = nil
    if Insp.strip then Insp.strip:Hide() end
end
Insp.Clear = Clear

local function StripTooltip(self)
    if #result == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L.INSPECT_TITLE:format(Insp.who or "?"), Theme.colors.tipLabel:GetRGB())
    for i, r in ipairs(result) do
        if i > MAX_LINES then break end
        GameTooltip:AddLine(Tip.Name(r.name) .. " " .. Tip.Count(r.worn, r.total), 1, 1, 1)
    end
    GameTooltip:AddLine(L.INSPECT_NOTE, Theme.colors.tipNote:GetRGB())
    GameTooltip:Show()
end

-- The strip hangs under the inspect window (outside it, so it never covers Blizzard's parts).
local function Strip(parent)
    if Insp.strip then return Insp.strip end
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(20)
    s:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    s:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2)
    local bg = s:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(Theme.colors.inspectBg:GetRGBA())
    s.text = s:CreateFontString(nil, "OVERLAY")
    Theme.Font(s.text, "small")
    s.text:SetPoint("LEFT", 8, 0)
    s.text:SetPoint("RIGHT", -8, 0)
    s.text:SetJustifyH("CENTER")
    s.text:SetWordWrap(false)
    s:EnableMouse(true)
    s:SetScript("OnEnter", StripTooltip)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s:Hide()
    Insp.strip = s
    if parent.HookScript then
        parent:HookScript("OnHide", Clear)   -- forget it when the window closes
        parent:HookScript("OnShow", Clear)   -- a new inspect: old result off until its data arrives
    end
    return s
end

function Insp.Show(parent, who, list)
    wipe(result)
    for i, r in ipairs(list) do result[i] = r end
    Insp.who = who
    local s = Strip(parent)
    if #result == 0 then s:Hide() return end
    local top = result[1]
    local text = Tip.Label() .. " " .. L.INSPECT_WEARS:format(who) .. " " .. Tip.Name(top.name) .. " " .. Tip.Count(top.worn, top.total)
    if #result > 1 then text = text .. " " .. Tip.Note(L.INSPECT_MORE:format(#result - 1)) end
    s.text:SetText(text)
    s:Show()
end

local function OnInspectReady(guid)
    if guid == nil or Secret(guid) then return end
    local IF = InspectFrame
    if not (IF and IF.IsShown and IF:IsShown()) then return end   -- only the player's own inspect window
    local unit = IF.unit
    if not unit or Secret(unit) or not UnitGUID then return end
    local ug = UnitGUID(unit)
    if ug == nil or Secret(ug) or ug ~= guid then return end
    local who = UnitName(unit)
    if who == nil or Secret(who) then who = "?" end
    Insp.Show(IF, who, Insp.Count(unit))
end

local f = CreateFrame("Frame")
ns.SafeRegister(f, "INSPECT_READY")
f:SetScript("OnEvent", function(_, _, guid)
    local ok, err = pcall(OnInspectReady, guid)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end)
Insp.OnInspectReady = OnInspectReady
