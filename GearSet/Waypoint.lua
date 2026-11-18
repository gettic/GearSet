-- Gear Set: the guide's Way button (beta.9, contract plans\v1.0.0\beta9-interface.md).
-- Positions come from ns.PlacesData (PlacesData.lua). A click (and only a click: never a
-- timer, the page loading or a "next step") sends the player there:
--   1. TomTom loaded: a TomTom waypoint (only our own last one is removed first),
--   2. else the game's own map pin (user waypoint) + super-track: replaces the player's pin,
--   3. else, or in combat: the position in a copy box.
-- One chat line per click through ns.Print ("Gear Set: ..."), never sent to anyone.
-- Checked: C_Map.SetUserWaypoint / CanSetUserWaypointOnMap, UiMapPoint.CreateFromCoordinates,
-- C_SuperTrack.SetSuperTrackedUserWaypoint, C_Map.GetMapChildrenInfo are listed for Forever 1.60.1
-- on warcraft.wiki.gg (API pages, 2026-11-18); /gs probe "Waypoint API" checks them in game.
local _, ns = ...

local Way = {}
ns.Way = Way

local CONTINENTS = { 1414, 1415 }   -- Kalimdor, Eastern Kingdoms (classic uiMapIDs)

local function T(key, fallback)
    local v = ns.L and ns.L[key]
    if v == nil then return fallback end
    return v
end

-- ---------------------------------------------------------------------------
-- Pure: one PlacesData value -> { zone, points = { {x, y, zone}, ... }, kind, checked }, or nil.
-- "zone|x,y[,zone][;x,y[,zone]]|kind|flag"; x/y map percent 0..100.
function Way.Parse(s)
    if type(s) ~= "string" or s == "" then return nil end
    local f = {}
    for part in (s .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
    local zone = (f[1] or ""):match("^%s*(.-)%s*$")
    if zone == "" then return nil end
    local points = {}
    for p in (f[2] or ""):gmatch("[^;]+") do
        local x, y, rest = p:match("^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*(.*)$")
        x, y = tonumber(x), tonumber(y)
        if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
            local own = rest and rest:match("^,%s*(.-)%s*$")
            points[#points + 1] = { x = x, y = y, zone = (own and own ~= "") and own or zone }
        end
    end
    if #points == 0 then return nil end
    local kind = f[3] ~= "" and f[3] or nil
    return { zone = zone, points = points, kind = kind, checked = (f[4] or ""):find("f", 1, true) ~= nil }
end

-- ---------------------------------------------------------------------------
-- Zone name -> uiMapID: PlacesData.map first, then (Forever-only zones such as Riverglades)
-- the game's own zone list by English name, cached (false = not found).
local found = {}

function Way.FindMapID(zone)
    if not (C_Map and C_Map.GetMapChildrenInfo) then return nil end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for _, cont in ipairs(CONTINENTS) do
        local ok, list = pcall(C_Map.GetMapChildrenInfo, cont, zoneType, true)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                if type(info) == "table" and info.name == zone and type(info.mapID) == "number" then
                    return info.mapID
                end
            end
        end
    end
    return nil
end

function Way.MapID(zone)
    if type(zone) ~= "string" or zone == "" then return nil end
    local pd = ns.PlacesData
    local id = type(pd) == "table" and type(pd.map) == "table" and pd.map[zone]
    if type(id) == "number" then return id end
    local hit = found[zone]
    if hit == nil then
        hit = Way.FindMapID(zone) or false
        found[zone] = hit
    end
    return hit or nil
end

-- ---------------------------------------------------------------------------
-- A guide row's point: Way.Point("npc"|"place"|"boss", key) -> { m, x, y, zone, title, kind,
-- checked, points } (first point = where the button sends you; m nil = no map ID: copy box), or nil.
local pointCache = {}

function Way.Point(tname, key)
    if type(tname) ~= "string" or type(key) ~= "string" or key == "" then return nil end
    local id = tname .. ":" .. key
    local hit = pointCache[id]
    if hit ~= nil then return hit or nil end
    local pd = ns.PlacesData
    local raw = type(pd) == "table" and type(pd.at) == "table" and pd.at[id]
    local rec = Way.Parse(raw)
    if rec then
        local p1 = rec.points[1]
        hit = { m = Way.MapID(p1.zone), x = p1.x, y = p1.y, zone = p1.zone, title = key,
            kind = rec.kind, checked = rec.checked, points = rec.points }
    end
    pointCache[id] = hit or false
    return hit
end

function Way.ClearCache()
    wipe(pointCache)
    wipe(found)
end

-- "Ironforge 43.5, 52.6"
function Way.PosText(zone, x, y)
    return ("%s %.1f, %.1f"):format(zone or "?", x or 0, y or 0)
end

-- Text for the copy box and the copy view: "Deliana, Ironforge 43.5, 52.6"
function Way.Text(p)
    if not p then return "" end
    local pos = Way.PosText(p.zone, p.x, p.y)
    if p.title and p.title ~= "" and p.title ~= p.zone then return p.title .. ", " .. pos end
    return pos
end

-- ---------------------------------------------------------------------------
-- Which way a click goes: "tomtom", "map" or "copy" (also for the tooltip).
local function TomTomAdd()
    local tt = rawget(_G, "TomTom")
    if type(tt) == "table" and type(tt.AddWaypoint) == "function" then return tt end
end

local function CanMapPin(m)
    if not (m and C_Map and C_Map.SetUserWaypoint and C_Map.CanSetUserWaypointOnMap) then return false end
    local ump = _G.UiMapPoint   -- (via _G: not in luacheck's WoW list)
    if not (ump and ump.CreateFromCoordinates) then return false end
    local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, m)
    return ok and can == true
end

function Way.Path(p)
    if not (p and p.m) then return "copy" end
    if TomTomAdd() then return "tomtom" end
    if CanMapPin(p.m) then return "map" end
    return "copy"
end

-- ---------------------------------------------------------------------------
-- The click. Returns the path used ("tomtom" / "map" / "copy" / "combat") for the tests.
Way.lastUid = nil   -- our own last TomTom waypoint (the only one we ever remove)

local function CopyBox(p)
    if ns.ShowCopyBox then ns.ShowCopyBox("way", Way.Text(p)) end
end

local function SetTomTom(tt, p)
    if Way.lastUid ~= nil and type(tt.RemoveWaypoint) == "function" then
        pcall(tt.RemoveWaypoint, tt, Way.lastUid)
        Way.lastUid = nil
    end
    local ok, uid = pcall(tt.AddWaypoint, tt, p.m, p.x / 100, p.y / 100,
        { title = p.title, from = T("TITLE", "Gear Set"), persistent = false })
    if ok and uid ~= nil then
        Way.lastUid = uid
        return true
    end
    return false
end

local function SetMapPin(p)
    local ok = pcall(function()
        C_Map.SetUserWaypoint(_G.UiMapPoint.CreateFromCoordinates(p.m, p.x / 100, p.y / 100))
    end)
    if not ok then return false end
    -- The pin is set; tracking it is a quiet extra (a failure here doesn't undo the pin).
    local st = _G.C_SuperTrack
    if st and st.SetSuperTrackedUserWaypoint then
        pcall(st.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

function Way:Go(p)
    if not p then return nil end
    local text = Way.Text(p)
    -- In combat: no TomTom or map call at all, just the position to copy (tos W2).
    if InCombatLockdown and InCombatLockdown() then
        CopyBox(p)
        ns.Print(T("WAY_COMBAT", "in combat - the position is in the copy box: %s"):format(text))
        return "combat"
    end
    local tt = p.m and TomTomAdd()
    if tt and SetTomTom(tt, p) then
        ns.Print(T("WAY_TOMTOM", "TomTom waypoint set: %s"):format(text))
        return "tomtom"
    end
    if CanMapPin(p.m) and SetMapPin(p) then
        ns.Print(T("WAY_MAP", "map pin set: %s"):format(text))
        return "map"
    end
    CopyBox(p)
    ns.Print(T("WAY_COPY", "can't set a map pin there - the position is in the copy box: %s"):format(text))
    return "copy"
end

-- ---------------------------------------------------------------------------
-- Button tooltip: what a click does, which path, what it replaces, and how sure the position is.
function Way.Tooltip(owner, p)
    if not (owner and p and GameTooltip) then return end
    local Theme = ns.Theme
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(T("WAY_TIP_TITLE", "Show the way"), 1, 1, 1)
    local where = Way.PosText(p.zone, p.x, p.y)
    if p.kind == "e" then where = where .. " " .. T("WAY_ENTRANCE", "(entrance)")
    elseif p.kind == "a" then where = where .. " " .. T("WAY_AREA", "(roams around here)") end
    GameTooltip:AddLine(where, 1, 0.82, 0, true)
    for i = 2, #(p.points or {}) do
        local q = p.points[i]
        GameTooltip:AddLine(T("WAY_ALSO", "Also: %s"):format(Way.PosText(q.zone, q.x, q.y)), 0.8, 0.8, 0.8, true)
    end
    local path = Way.Path(p)
    local line
    if path == "tomtom" then line = T("WAY_TIP_TOMTOM", "Click: sets a TomTom waypoint.")
    elseif path == "map" then line = T("WAY_TIP_MAP", "Click: sets a map pin and tracks it. It replaces your own map pin.")
    else line = T("WAY_TIP_COPY", "Click: shows the position to copy (no map pin can be set there).") end
    GameTooltip:AddLine(line, 1, 1, 1, true)
    if path ~= "copy" then
        GameTooltip:AddLine(T("WAY_TIP_COMBAT", "In combat it only shows the position to copy."), 0.6, 0.6, 0.6, true)
    end
    if not p.checked then
        local col = Theme and Theme.colors and Theme.colors.flagClassic
        local r, g, b = 0.6, 0.6, 0.6
        if col and col.GetRGB then r, g, b = col:GetRGB() end
        GameTooltip:AddLine(T("WAY_TIP_CLASSIC", "Position from classic, not checked on WoW Forever yet."), r, g, b, true)
    end
    GameTooltip:Show()
end
