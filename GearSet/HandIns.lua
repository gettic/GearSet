-- Gear Set: hand-in reminders (1.1 beta.4, plans\v1.1.0\b4-plan.md; data contract b4-interface.md).
-- Quests that reward a piece you still need (out now) and whose items are all in your bags.
-- ToS B2: nothing here ever accepts, completes or picks a quest reward, talks to an NPC, targets,
-- moves or sets a waypoint: it only prints ONE local chat line per zone entry (B3: via ns.Print,
-- never in combat, never inside an instance, none when the setting is off, no sound) and feeds the
-- Plan tab's "Ready to hand in" section. B9: the list is built on (debounced) bag changes only;
-- a zone change is one table lookup.
local _, ns = ...

local HandIns = {}
ns.HandIns = HandIns

local function T(key, fallback) return (ns.L and ns.L[key]) or fallback end
local function Has(s) return type(s) == "string" and s ~= "" end
local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function Secret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s and true or false
end

-- `bid|<name>|<itemID>` rows of a quest record -> { [name] = itemID } (faction rows: own only).
function HandIns.BidIDs(quest, mine)
    local g = ns.GuideData
    local raw = type(g) == "table" and type(g.quest) == "table" and g.quest[quest]
    local out = {}
    if type(raw) ~= "string" then return out end
    for part in raw:gmatch("[^;]+") do
        local name, id, rest = part:match("^%s*bid|([^|]+)|(%d+)(.*)$")
        local fac = rest and rest:match("|@([AH])")
        if name and (not fac or not mine or fac == mine) then out[Trim(name)] = tonumber(id) end
    end
    return out
end

-- "15 Winterspring Blood Sample" -> 15, "Winterspring Blood Sample"; no count -> 1.
function HandIns.ParseBring(v)
    if not Has(v) then return nil end
    local n, name = v:match("^%s*(%d+)%s+(.+)$")
    if n then return tonumber(n), Trim(name) end
    return 1, Trim(v)
end

-- Bags only (what you carry to the NPC).
local function BagCount(id)
    local C = C_Item
    local count = (C and C.GetItemCount) or _G.GetItemCount
    if type(count) ~= "function" then return 0 end
    local ok, n = pcall(count, id)
    if ok and type(n) == "number" and not Secret(n) then return n end
    return 0
end

-- Pure: the hand-ins for `wanted` ([itemID] = { later }) with `sourcesOf(itemID)` (SourceEntries
-- shape) and `countOf(id)`. -> list of { quest, npc, zone, piece, ready, items = { { name, id, n, have } } }.
function HandIns.Build(wanted, sourcesOf, countOf, mine)
    local R = ns.Runs
    local out, seen = {}, {}
    for itemID, w in pairs(wanted or {}) do
        if not w.later then
            for _, e in ipairs(sourcesOf(itemID) or {}) do
                if e.kind == "q" and Has(e.a) and not e.later and (not e.fac or not mine or e.fac == mine)
                    and not seen[e.a] then
                    local r = R and R.Rec("quest", e.a, mine)
                    if r and r.bring_all and #r.bring_all > 0 then
                        seen[e.a] = true
                        local bids = HandIns.BidIDs(e.a, mine)
                        local h = { quest = e.a, piece = itemID, items = {}, ready = true }
                        h.npc = Has(r.giver) and r.giver or nil
                        local nr = h.npc and R.Rec("npc", h.npc, mine)
                        h.zone = nr and Has(nr.zone) and nr.zone or nil
                        for _, v in ipairs(r.bring_all) do
                            local n, name = HandIns.ParseBring(v)
                            if name then
                                local id = bids[name]
                                local have = id and countOf(id) or nil
                                h.items[#h.items + 1] = { name = name, id = id, n = n, have = have }
                                if not (have and have >= n) then h.ready = false end
                            end
                        end
                        if #h.items == 0 then h.ready = false end
                        out[#out + 1] = h
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.quest < b.quest end)
    return out
end

-- The list for this character (cached; rebuilt by HandIns.Rebuild on bag changes).
local cache, byZone
function HandIns.Rebuild()
    cache, byZone = {}, {}
    local R, D = ns.Runs, ns.Data
    if not (R and R.Wanted and D and D.SourceEntries) then return cache end
    local mine = D.PlayerFaction and D.PlayerFaction()
    local ok, list = pcall(HandIns.Build, R.Wanted(), D.SourceEntries, BagCount, mine)
    if ok and type(list) == "table" then cache = list end
    for _, h in ipairs(cache) do
        if h.ready and h.zone then
            local z = byZone[h.zone]
            if not z then z = {}; byZone[h.zone] = z end
            z[#z + 1] = h
        end
    end
    return cache
end

function HandIns.List()
    return cache or HandIns.Rebuild()
end

function HandIns.Ready(zone)
    if not cache then HandIns.Rebuild() end
    if zone == nil then
        local out = {}
        for _, h in ipairs(cache) do if h.ready then out[#out + 1] = h end end
        return out
    end
    return byZone[zone] or {}
end

-- "1 hand-in ready here: Deliana (An Earnest Proposition)."
function HandIns.LineText(list)
    local parts = {}
    for i, h in ipairs(list) do
        if i > 3 then break end
        parts[#parts + 1] = h.npc and T("HAND_WHO", "%s (%s)"):format(h.npc, h.quest) or h.quest
    end
    local text = table.concat(parts, ", ")
    if #list > 3 then text = text .. ", " .. T("HAND_MORE", "+%d more"):format(#list - 3) end
    if #list == 1 then return T("HAND_LINE_ONE", "1 hand-in ready here: %s."):format(text) end
    return T("HAND_LINE", "%d hand-ins ready here: %s."):format(#list, text)
end

-- ---------------------------------------------------------------------------
-- Zone entry (B3 / B9).
local function ZoneName()
    local real = _G.GetRealZoneText
    if type(real) == "function" then
        local ok, z = pcall(real)
        if ok and type(z) == "string" and z ~= "" and not Secret(z) then return z end
    end
    local M = C_Map
    if M and M.GetBestMapForUnit and M.GetMapInfo then
        local ok, m = pcall(M.GetBestMapForUnit, "player")
        if ok and type(m) == "number" and not Secret(m) then
            local ok2, info = pcall(M.GetMapInfo, m)
            if ok2 and type(info) == "table" and type(info.name) == "string" and not Secret(info.name) then return info.name end
        end
    end
    return nil
end

local function InInstance()
    local isIn = _G.IsInInstance
    if type(isIn) ~= "function" then return false end
    local ok, inside = pcall(isIn)
    return ok and inside and true or false
end

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function On()
    local db = ns.db
    return type(db) == "table" and db.handIns ~= false
end

HandIns.state = { zone = nil, told = false, waiting = false, printed = 0 }
HandIns.LOGIN_DELAY = 5   -- seconds after PLAYER_ENTERING_WORLD before the first zone check

-- Called on zone entry and after combat. Returns true when it printed.
function HandIns.Check()
    local st = HandIns.state
    if st.told or not On() or InInstance() then return false end
    if InCombat() then st.waiting = true; return false end
    st.waiting = false
    local list = HandIns.Ready(st.zone)
    if #list == 0 then return false end
    st.told = true
    st.printed = st.printed + 1
    ns.Print(HandIns.LineText(list))
    return true
end

function HandIns.OnZone()
    local st = HandIns.state
    local z = ZoneName()
    if z ~= st.zone then
        st.zone, st.told, st.waiting = z, false, false
        if z then HandIns.Check() end
    end
end

local bagPending = false
local function BagsChanged()
    if bagPending then return end
    bagPending = true
    local function run()
        bagPending = false
        HandIns.Rebuild()
        if ns.Plan and ns.Plan.Refresh then pcall(ns.Plan.Refresh, ns.Plan) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, run) else run() end
end
HandIns.BagsChanged = BagsChanged
-- Tracking or owned pieces changed (Runs.Invalidate): the same debounced rebuild.
if ns.Runs then ns.Runs.OnInvalidate = BagsChanged end

local frame = CreateFrame("Frame")
HandIns.frame = frame
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do
    if ns.SafeRegister then ns.SafeRegister(frame, e) else pcall(frame.RegisterEvent, frame, e) end
end
frame:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
        BagsChanged()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if HandIns.state.waiting then pcall(HandIns.Check) end
    else
        -- pretest finding 3: no build during login; the first zone check runs a few seconds later
        -- (the list is then built on that first need, after that only on bag changes).
        if event == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then
            C_Timer.After(HandIns.LOGIN_DELAY, function() pcall(HandIns.OnZone) end)
        else
            pcall(HandIns.OnZone)
        end
    end
end)

function HandIns._Reset()
    cache, byZone, bagPending = nil, nil, false
    HandIns.state = { zone = nil, told = false, waiting = false, printed = 0 }
end
