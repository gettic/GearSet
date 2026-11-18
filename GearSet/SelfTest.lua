-- Gear Set: /gs selftest [full]. The addon checks itself in the running game: every
-- button and panel is shown, has a position and a size, is on screen and drawn above the
-- window's border art; its art loads; the saved data survives defaults and migrations
-- (on copies only); the bundled data loads; /gs, the key binding and the settings work.
-- Plan: plans\selftest\plan.md, rules: plans\selftest\tos-check.md.
-- Safety: reads only. It shows and hides only our own frames and puts them back; no
-- Blizzard function is replaced or hooked; nothing protected. Every value read from a
-- frame is checked with issecretvalue before it is compared ("skipped (secret)"). In
-- combat it waits; if combat starts mid-run it stops and puts everything back.
-- Never reads tooltip data or calls Data:GetSetStats. Never writes the saved data.
local ADDON, ns = ...

local ST = {}
ns.SelfTest = ST

local MAX_LIST = 8          -- names listed per summary line
local MISSING_IDS = 5       -- item IDs shown for "unknown to this client" (info line)
local COVER_SHARE = 0.3     -- part counts as covered when this much of it is under another frame
local SCREEN_SLACK = 2      -- px

local run                   -- the run in progress (nil when idle)

-- ---------------------------------------------------------------------------
-- Safe reads

local function IsSecret(v)
    local f = issecretvalue
    if type(f) ~= "function" then return false end
    local ok, s = pcall(f, v)
    return ok and s and true or false
end

local function Pack(...) return { n = select("#", ...), ... } end

-- obj:method(...) -> "ok", results... | "noapi" | "err" | "secret" (any result secret).
local function Read(obj, method, ...)
    if type(obj) ~= "table" then return "noapi" end
    local f = obj[method]
    if type(f) ~= "function" then return "noapi" end
    local r = Pack(pcall(f, obj, ...))
    if not r[1] then return "err" end
    for i = 2, r.n do
        if IsSecret(r[i]) then return "secret" end
    end
    return "ok", unpack(r, 2, r.n)
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function Short(err)
    local P = ns.Probe
    if P and P.ShortError then return P.ShortError(err) end
    return "error: " .. tostring(err):sub(1, 80)
end

-- ---------------------------------------------------------------------------
-- Results

local function Count(n) run.checks = run.checks + (n or 1) end
local function Problem(code, name, text)
    run.problems[#run.problems + 1] = code .. " " .. name .. ": " .. text
end
local function Skip(name, why)
    run.skips[#run.skips + 1] = name .. " " .. why
end
local function Info(text) run.info[#run.info + 1] = text end

-- Runs fn in pcall; a throw becomes one "ERR" line.
local function Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Problem("ERR", label, Short(err)) end
    return ok
end

-- ---------------------------------------------------------------------------
-- Frame geometry (screen pixels, so frames with other scales compare)

local function ScreenRect(o)
    local st, l, b, w, h = Read(o, "GetRect")
    if st == "secret" then return "secret" end
    if st ~= "ok" or l == nil or b == nil or w == nil or h == nil then return nil end
    local s2, es = Read(o, "GetEffectiveScale")
    if s2 == "secret" then return "secret" end
    if s2 ~= "ok" or type(es) ~= "number" then
        local p = select(2, Read(o, "GetParent"))
        s2, es = Read(p, "GetEffectiveScale")
        if s2 == "secret" then return "secret" end
        if s2 ~= "ok" or type(es) ~= "number" then es = 1 end
    end
    return { l = l * es, b = b * es, r = (l + w) * es, t = (b + h) * es, w = w, h = h }
end

-- The scroll frame that holds o as its scroll child, else nil.
local function ScrollFrameOf(o)
    local s1, parent = Read(o, "GetParent")
    if s1 ~= "ok" or type(parent) ~= "table" then return nil end
    local s2, child = Read(parent, "GetScrollChild")
    if s2 == "ok" and child == o then return parent end
    return nil
end

-- Screen position of a frame as "x,y wxh" (left, top, size in screen pixels), "?" if none.
local function WhereText(o)
    local r = o and ScreenRect(o)
    if type(r) ~= "table" then return r == "secret" and "secret" or "?" end
    return ("%d,%d %dx%d"):format(math.floor(r.l + 0.5), math.floor(r.t + 0.5),
        math.floor(r.r - r.l + 0.5), math.floor(r.t - r.b + 0.5))
end

local function Overlap(a, b)
    local w = math.min(a.r, b.r) - math.max(a.l, b.l)
    local h = math.min(a.t, b.t) - math.max(a.b, b.b)
    if w <= 0 or h <= 0 then return 0 end
    return w * h
end

-- Frame level of a frame, or of a texture's / font string's frame. nil = can't tell, "secret".
local function Level(o)
    local st, lv = Read(o, "GetFrameLevel")
    if st == "secret" then return "secret" end
    if st == "ok" and type(lv) == "number" then return lv end
    local s2, p = Read(o, "GetParent")
    if s2 == "secret" then return "secret" end
    if s2 == "ok" and p then
        st, lv = Read(p, "GetFrameLevel")
        if st == "secret" then return "secret" end
        if st == "ok" and type(lv) == "number" then return lv end
    end
    return nil
end

local STRATA = { WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function Strata(o)
    local st, s = Read(o, "GetFrameStrata")
    if st == "noapi" then
        local _, p = Read(o, "GetParent")
        st, s = Read(p, "GetFrameStrata")
    end
    if st == "secret" then return "secret" end
    return st == "ok" and STRATA[s] or nil
end

-- true when a is b or one is inside the other (parent chain).
local function Related(a, b)
    for _, pair in ipairs({ { a, b }, { b, a } }) do
        local p, n = pair[1], 0
        while p and n < 25 do
            if p == pair[2] then return true end
            local st, q = Read(p, "GetParent")
            if st ~= "ok" then return nil end
            p, n = q, n + 1
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Art

-- nil = loads; else a short reason.
local function ArtMissing(tex)
    if type(tex) ~= "table" then return "missing" end
    local st, atlas = Read(tex, "GetAtlas")
    if st == "secret" then return "secret" end
    if st == "ok" and type(atlas) == "string" and atlas ~= "" then
        local get = C_Texture and C_Texture.GetAtlasInfo
        if type(get) ~= "function" then return nil end
        local ok, info = pcall(get, atlas)
        if not ok or type(info) ~= "table" then return "atlas " .. atlas .. " gone" end
        local file = info.file or info.filename
        if file == nil or file == 0 or file == "" then return "atlas " .. atlas .. " has no file" end
        return nil
    end
    local id
    st, id = Read(tex, "GetTextureFileID")
    if st == "secret" then return "secret" end
    if st ~= "ok" or id == nil then
        st, id = Read(tex, "GetTexture")
        if st == "secret" then return "secret" end
    end
    if id == nil or id == 0 or id == "" then return "no file" end
    return nil
end

-- One hidden texture to test file paths on (made on the first run only).
local scratch
local function FileLoads(path)
    if not scratch then
        local ok, f = pcall(CreateFrame, "Frame")
        if not ok or not f then return nil end
        f:Hide()
        scratch = f:CreateTexture()
    end
    local T = ns.Theme
    if T and T.TryTexture then
        local ok, r = pcall(T.TryTexture, scratch, path)
        return ok and r or false
    end
    return nil
end

local function AtlasLoads(name)
    local P = ns.Probe
    if P and P.AtlasOK then return P.AtlasOK(name) end
    return nil
end

-- A Theme.art value: string (file or atlas), { atlas/atlases/file/color }, list of files
-- or a table of named files. Returns a reason when nothing of it loads.
local function ArtEntryMissing(v)
    if type(v) == "string" then
        if v:find("%%") then return nil end                 -- format string (class atlas)
        if v:find("[\\/]") then return FileLoads(v) == false and v or nil end
        return AtlasLoads(v) == false and v or nil
    end
    if type(v) ~= "table" then return nil end
    if v.atlas or v.atlases or v.file then
        local names = {}
        if type(v.atlas) == "string" then names[#names + 1] = v.atlas end
        if type(v.atlases) == "table" then
            for _, a in ipairs(v.atlases) do if type(a) == "string" then names[#names + 1] = a end end
        end
        for _, a in ipairs(names) do
            if AtlasLoads(a) ~= false then return nil end
        end
        if type(v.file) == "string" and FileLoads(v.file) ~= false then return nil end
        if type(v.file) == "number" then return nil end
        if v.color then return nil end
        return names[1] or tostring(v.file)
    end
    if #v > 0 then
        for _, f in ipairs(v) do
            if type(f) ~= "string" or ArtEntryMissing(f) == nil then return nil end
        end
        return tostring(v[1])
    end
    for _, f in pairs(v) do
        if type(f) == "string" then
            local miss = ArtEntryMissing(f)
            if miss then return miss end
        end
    end
    return nil
end

-- Template lists without a sensible no-template fallback.
local NEEDED_TEMPLATES = { window = true, button = true, check = true, scrollBox = true, scrollBar = true }

local function CheckTheme()
    local T = ns.Theme
    if not T then return Problem("ART", "theme", "missing") end
    local keys = {}
    for k in pairs(T.art or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local bad = {}
    for _, k in ipairs(keys) do
        Count()
        local miss = ArtEntryMissing(T.art[k])
        if miss then bad[#bad + 1] = k end
    end
    if #bad > 0 then Problem("ART", "theme", "nothing loads for " .. table.concat(bad, ", ", 1, math.min(#bad, MAX_LIST))) end

    local info = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    if type(info) == "function" then
        local none = {}
        for key, list in pairs(T.templates or {}) do
            if NEEDED_TEMPLATES[key] and type(list) == "table" then
                Count()
                local found = false
                for _, n in ipairs(list) do
                    local ok, r = pcall(info, n)
                    if ok and r ~= nil then found = true; break end
                end
                if not found then none[#none + 1] = key end
            end
        end
        table.sort(none)
        if #none > 0 then Problem("ART", "templates", "none found for " .. table.concat(none, ", ")) end
    else
        Skip("templates", "(no API)")
    end

    local fonts = {}
    for key, name in pairs(T.fonts or {}) do
        Count()
        if type(name) == "string" and _G[name] == nil then fonts[#fonts + 1] = key .. "=" .. name end
    end
    table.sort(fonts)
    if #fonts > 0 then Problem("ART", "fonts", "missing " .. table.concat(fonts, ", ")) end
end

-- ---------------------------------------------------------------------------
-- UI parts

-- The window template's parts that hold its border/title/portrait art.
local TEMPLATE_PARTS = { "NineSlice", "PortraitContainer", "TitleContainer", "CloseButton" }

-- Highest template part: level, name (nil when none can be read).
local function ArtTop(win)
    local top, name
    for _, key in ipairs(TEMPLATE_PARTS) do
        local lv = Level(win[key])
        if lv == "secret" then return "secret" end
        if type(lv) == "number" and (top == nil or lv > top) then top, name = lv, key end
    end
    return top, name
end

-- Frames that may draw over a part: the template's portrait/title/X (not the NineSlice:
-- it spans the whole window but draws only the border, which the `top` check covers)
-- plus the other parts of the same group.
local function Coverers(win, parts)
    local list = {}
    for _, key in ipairs({ "PortraitContainer", "TitleContainer", "CloseButton" }) do
        if win and win[key] then list[#list + 1] = { name = key, obj = win[key] } end
    end
    for _, p in ipairs(parts) do
        if p.obj then list[#list + 1] = p end
    end
    return list
end

-- At most one problem line per part: the first check that fails.
local function CheckPart(p, win, coverers)
    local o = p.obj
    Count()
    if o == nil then
        if p.opt then return end
        return Problem("UI", p.name, "missing")
    end
    local st, shown = Read(o, "IsShown")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st ~= "ok" then return Problem("UI", p.name, "can't read (" .. st .. ")") end
    if not shown then
        if p.shownOnly then return end
        return Problem("UI", p.name, "hidden")
    end
    Count()
    local vis
    st, vis = Read(o, "IsVisible")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and not vis then return Problem("UI", p.name, "shown but its parent is hidden") end

    -- Position (the beta.2 "?" bug: shown, but no usable anchor, so never drawn).
    -- A scroll child (the copy view's text box) has only a size, no anchor of its own: the
    -- game places it inside its scroll frame, so measure the scroll frame instead.
    local geo = ScrollFrameOf(o) or o
    Count()
    local valid
    st, valid = Read(geo, "IsRectValid")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and valid == false then return Problem("UI", p.name, "no position") end
    local rect = ScreenRect(geo)
    if rect == "secret" then return Skip(p.name, "(secret)") end
    if rect == nil then return Problem("UI", p.name, "no position") end

    Count()
    if not (rect.w > 1 and rect.h > 1) and not p.thin then
        return Problem("UI", p.name, ("size %dx%d"):format(math.floor(rect.w), math.floor(rect.h)))
    end

    Count()
    local screen = ScreenRect(UIParent)
    if type(screen) == "table" then
        if rect.l < screen.l - SCREEN_SLACK or rect.b < screen.b - SCREEN_SLACK
            or rect.r > screen.r + SCREEN_SLACK or rect.t > screen.t + SCREEN_SLACK then
            return Problem("UI", p.name, "off screen")
        end
    end

    Count()
    local alpha
    st, alpha = Read(o, "GetEffectiveAlpha")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and type(alpha) == "number" and alpha < 0.05 then
        return Problem("UI", p.name, ("invisible (alpha %.2f)"):format(alpha))
    end

    local lv = Level(o)
    if lv == "secret" then return Skip(p.name, "(secret)") end
    local ss = Strata(o)
    if ss == "secret" then return Skip(p.name, "(secret)") end

    -- Above the window's border/title/portrait art (the beta.2 gear bug).
    if p.top and win then
        Count()
        local top, topName = ArtTop(win)
        if top == "secret" then return Skip(p.name, "(secret)") end
        local ws = Strata(win)
        if ws == "secret" then return Skip(p.name, "(secret)") end
        local higherStrata = ss and ws and ss > ws
        if type(lv) == "number" and type(top) == "number" and lv <= top and not higherStrata then
            return Problem("UI", p.name, ("under art %d<=%d (%s)"):format(lv, top, topName))
        end
    end

    -- Not under another frame that covers a good part of it.
    if type(lv) == "number" then
        Count()
        for _, c in ipairs(coverers or {}) do
            if c.obj ~= o then
                local rel = Related(o, c.obj)
                local cv = select(2, Read(c.obj, "IsVisible"))
                if rel == false and cv == true then
                    local clv, cs = Level(c.obj), Strata(c.obj)
                    if clv == "secret" or cs == "secret" then
                        Skip(p.name, "cover (secret)")
                    elseif type(clv) == "number" and clv > lv and (cs == nil or ss == nil or cs == ss) then
                        local cr = ScreenRect(c.obj)
                        if type(cr) == "table" then
                            local area = (rect.r - rect.l) * (rect.t - rect.b)
                            if area > 0 and Overlap(rect, cr) / area >= COVER_SHARE then
                                return Problem("UI", p.name, ("covered by %s (%d>%d)"):format(c.name, clv, lv))
                            end
                        end
                    end
                end
            end
        end
    end

    -- Its art really loads (file IDs, not just "listed").
    for _, key in ipairs(p.art or {}) do
        Count()
        local tex = o[key]
        local miss = ArtMissing(tex)
        if miss == "secret" then
            Skip(p.name .. "." .. key, "(secret)")
        elseif miss then
            return Problem("TEX", p.name .. "." .. key, miss)
        end
    end
    if p.artSelf then
        Count()
        local miss = ArtMissing(o)
        if miss == "secret" then Skip(p.name, "art (secret)")
        elseif miss then return Problem("TEX", p.name, miss) end
    end

    -- Button label cut off.
    local fs = select(2, Read(o, "GetFontString"))
    if fs then
        Count()
        local s2, cut = Read(fs, "IsTruncated")
        if s2 == "ok" and cut then return Problem("UI", p.name, "text cut") end
    end
end

local function CheckGroup(parts, win)
    local cov = Coverers(win, parts)
    for _, p in ipairs(parts) do
        Guard("UI " .. p.name, CheckPart, p, win, cov)
    end
end

local function DB() return ns.db end

-- The window's parts (the piece list's only while no guide page stands in for it).
function ST.MainParts()
    local UI, SL, PL, PV = ns.UI or {}, ns.SetList or {}, ns.PieceList or {}, ns.Preview or {}
    local f = UI.frame
    local help = UI.helpButton
    local parts = {
        { name = "window", obj = f },
        { name = "close", obj = f and f.CloseButton, opt = true },
        { name = "gear", obj = UI.gear, top = true, art = { "icon" } },
        { name = "help", obj = help, top = true, art = (help and (help.gsArt or help.gsTemplate)) and { "I", "Ring" } or nil },
        { name = "insetL", obj = UI.left }, { name = "insetM", obj = UI.mid }, { name = "insetR", obj = UI.right },
        { name = "filter", obj = SL.filter }, { name = "search", obj = SL.search }, { name = "sets", obj = SL.box },
        { name = "model", obj = PV.model }, { name = "reset", obj = PV.reset }, { name = "onlySet", obj = PV.check },
    }
    local guideOpen = ns.GuidePage and ns.GuidePage.IsOpen and ns.GuidePage:IsOpen()
    if not guideOpen then
        local list = {
            { name = "setPrev", obj = PL.prevB }, { name = "setNext", obj = PL.nextB },
            { name = "title", obj = PL.title }, { name = "count", obj = PL.count },
            { name = "bonuses", obj = PL.bonuses, shownOnly = true },
            { name = "stats", obj = PL.stats, shownOnly = true },
            { name = "effort", obj = PL.effort, shownOnly = true, opt = true },
            { name = "pieces", obj = PL.box },
        }
        for _, p in ipairs(list) do parts[#parts + 1] = p end
    end
    return parts
end

function ST.GuideParts()
    local G = ns.GuidePage or {}
    return {
        { name = "gBack", obj = G.back }, { name = "gCopy", obj = G.copy }, { name = "gWiki", obj = G.wiki },
        { name = "gPrev", obj = G.prevB }, { name = "gNext", obj = G.nextB },
        { name = "gIcon", obj = G.icon, artSelf = true }, { name = "gName", obj = G.name },
        { name = "gModel", obj = G.modelCheck }, { name = "gCopyText", obj = G.copyText },
        { name = "gScroll", obj = G.scroll },
    }
end

function ST.CopyParts()
    local G = ns.GuidePage or {}
    return { { name = "gCopyArea", obj = G.copyScroll }, { name = "gCopyBox", obj = G.copyBox } }
end

function ST.HelpParts()
    local H = ns.Help or {}
    local notes = H.notes or {}
    return {
        { name = "helpDim", obj = H.frame },
        { name = "note1", obj = notes[1] }, { name = "note2", obj = notes[2] },
        { name = "note3", obj = notes[3] }, { name = "note4", obj = notes[4] },
        { name = "note4Line", obj = H.line, opt = true, thin = true },
        { name = "gotIt", obj = H.okButton },
    }
end

-- Minimap button: shown as the setting says, next to the minimap.
local function CheckMinimap()
    local MB = ns.MinimapButton
    local b = MB and MB.button
    local db = DB()
    local wantShown = not (db and db.minimap and db.minimap.hide)
    Count()
    if not b then
        if wantShown then Problem("UI", "minimap", "missing") end
        return
    end
    local st, shown = Read(b, "IsShown")
    if st == "secret" then return Skip("minimap", "(secret)") end
    if st == "ok" and (shown and true or false) ~= wantShown then
        return Problem("UI", "minimap", wantShown and "hidden but the setting shows it" or "shown but the setting hides it")
    end
    if not wantShown then return end
    CheckPart({ name = "minimap", obj = b, art = { "icon" } }, nil, nil)
    Count()
    local r, m = ScreenRect(b), ScreenRect(Minimap)
    if type(r) == "table" and type(m) == "table" then
        local cx, cy = (r.l + r.r) / 2, (r.b + r.t) / 2
        local mx, my = (m.l + m.r) / 2, (m.b + m.t) / 2
        local reach = math.max(m.r - m.l, m.t - m.b) / 2 + 40
        if math.sqrt((cx - mx) ^ 2 + (cy - my) ^ 2) > reach then
            Problem("UI", "minimap", "far from the minimap")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Saved data (copies only: ns.db / GearSetDB are never passed to PrepareDB here)

local function DeepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local t = {}
    seen[v] = t
    for k, x in pairs(v) do t[DeepCopy(k, seen)] = DeepCopy(x, seen) end
    return t
end

local function Same(a, b)
    if a ~= a and b ~= b then return true end     -- NaN
    return a == b
end

-- First key path where every value of `old` isn't kept in `new` (nil = all kept).
local function Lost(old, new, path, depth, ignore)
    depth = depth or 0
    if depth > 6 then return nil end
    for k, v in pairs(old) do
        local p = path and (path .. "." .. tostring(k)) or tostring(k)
        local n = new[k]
        if ignore and ignore[p] then
            -- expected to change
        elseif type(v) == "table" then
            if type(n) ~= "table" then return p end
            local deeper = Lost(v, n, p, depth + 1, ignore)
            if deeper then return deeper end
        elseif not Same(v, n) then
            return p
        end
    end
    return nil
end

local V1_SAMPLE = {
    version = 1, point = { "TOP", "TOP", 10, -20 },
    filters = { class = 0, armor = 2, usable = false, hideComplete = true, showRemoved = true,
        kind = "r", myFaction = false },
    sort = "closest", search = "x", lastSet = "c1", onlySet = true,
    minimap = { angle = 45, hide = true }, custom = "keep",
}

local function CheckSaved()
    local prep = ns.PrepareDB
    Count()
    if type(prep) ~= "function" then return Problem("DB", "prepare", "missing") end
    local db = DB()
    Count()
    if type(db) ~= "table" or db ~= GearSetDB then return Problem("DB", "live", "not the saved table") end
    Count()
    if (tonumber(db.version) or 0) < (ns.DB_VERSION or 0) then
        Problem("DB", "live", "version " .. tostring(db.version))
    end

    -- 1. Round trip: the user's own data goes through defaults + checks unchanged.
    Count()
    local copy = DeepCopy(db)
    local ok, err = pcall(prep, copy)
    if not ok then
        Problem("DB", "roundtrip", Short(err))
    else
        local lost = Lost(db, copy)
        if lost then Problem("DB", "roundtrip", "changed " .. lost) end
    end

    -- 2. Old (v1) data: every value kept, the v2 keys added.
    Count()
    local v1 = DeepCopy(V1_SAMPLE)
    ok, err = pcall(prep, v1)
    if not ok then
        Problem("DB", "v1", Short(err))
    else
        local lost = Lost(V1_SAMPLE, v1, nil, 0, { version = true })
        if lost then Problem("DB", "v1", "lost " .. lost)
        elseif type(v1.hidden) ~= "table" or type(v1.help) ~= "table" then Problem("DB", "v1", "v2 keys not added")
        elseif v1.version ~= ns.DB_VERSION then Problem("DB", "v1", "version not raised") end
    end

    -- 3. Broken values fall back to their defaults; unknown keys are kept.
    Count()
    local bad = { version = 99, point = { "NOPE" }, filters = { class = 7.5, armor = 9, kind = "zz" },
        sort = "bad", minimap = { angle = 0 / 0 }, custom = "keep" }
    ok, err = pcall(prep, bad)
    if not ok then
        Problem("DB", "bad", Short(err))
    else
        local f = bad.filters
        local wrong = {}
        if bad.point ~= nil then wrong[#wrong + 1] = "point" end
        if f.class ~= 0 then wrong[#wrong + 1] = "class" end
        if f.armor ~= 0 then wrong[#wrong + 1] = "armor" end
        if f.kind ~= "" then wrong[#wrong + 1] = "kind" end
        if bad.sort ~= "owned" then wrong[#wrong + 1] = "sort" end
        if bad.minimap.angle ~= bad.minimap.angle then wrong[#wrong + 1] = "angle" end
        if bad.custom ~= "keep" then wrong[#wrong + 1] = "custom key lost" end
        if bad.version ~= 99 then wrong[#wrong + 1] = "version lowered" end
        if #wrong > 0 then Problem("DB", "bad", "not fixed: " .. table.concat(wrong, ", ")) end
    end

    -- 4. Live hidden-set keys and last set point at known sets.
    Count()
    local D = ns.Data
    if D and D.GetSet and type(db.hidden) == "table" then
        local unknown = 0
        for k, v in pairs(db.hidden) do
            local id = type(k) == "string" and k:match("^set:(%d+)$")
            if v == true and not (id and D:GetSet("c" .. id)) then unknown = unknown + 1 end
        end
        if unknown > 0 then Info(("hidden keys not in the data: %d"):format(unknown)) end
        if db.lastSet and not D:GetSet(db.lastSet) then Info("last set not in the data") end
    end
end

-- ---------------------------------------------------------------------------
-- Data

local function Ms(start)
    if type(debugprofilestop) ~= "function" then return 0 end
    return debugprofilestop() - start
end
local function Now() return type(debugprofilestop) == "function" and debugprofilestop() or 0 end

local function CheckData()
    local D = ns.Data
    Count()
    if not D then return Problem("DATA", "Data", "missing") end
    local t0 = Now()
    local sets = D:GetSets()
    Count()
    if type(sets) ~= "table" or #sets == 0 then return Problem("DATA", "sets", "none loaded") end
    local bundled = 0
    for _ in pairs(type(ns.ClassicSets) == "table" and ns.ClassicSets or {}) do bundled = bundled + 1 end
    Count()
    if bundled > 0 and #sets > bundled then Problem("DATA", "sets", ("%d built from %d"):format(#sets, bundled)) end

    local badSets, items, unknown = {}, 0, {}
    local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    for _, s in ipairs(sets) do
        Count()
        local list = s.shown or s.pieces
        if type(s.name) ~= "string" or s.name == "" or type(list) ~= "table" or #list == 0 then
            badSets[#badSets + 1] = tostring(s.key)
        else
            for _, p in ipairs(list) do
                items = items + 1
                if p.slot == nil then badSets[#badSets + 1] = tostring(s.key) .. " slot" end
                if type(instant) == "function" then
                    local ok, id = pcall(instant, p.itemID)
                    if ok and id == nil then unknown[#unknown + 1] = tostring(p.itemID) end
                end
            end
        end
    end
    if #badSets > 0 then
        Problem("DATA", "sets", ("%d bad: %s"):format(#badSets, table.concat(badSets, ", ", 1, math.min(#badSets, MAX_LIST))))
    end
    Count()
    if #unknown > 0 then
        Problem("DATA", "items", ("%d unknown: %s"):format(#unknown, table.concat(unknown, ", ", 1, math.min(#unknown, MAX_LIST))))
    end
    if type(instant) ~= "function" then Skip("items", "(no API)") end

    -- Bundled items this client doesn't know (Data skips them while building): info only.
    local built, bundledItems, missing = {}, 0, {}
    for _, s in ipairs(sets) do
        for _, p in ipairs(type(s.shown or s.pieces) == "table" and (s.shown or s.pieces) or {}) do
            built[p.itemID] = true
        end
    end
    local seenItem = {}
    for _, e in pairs(type(ns.ClassicSets) == "table" and ns.ClassicSets or {}) do
        for _, id in ipairs(type(e) == "table" and type(e.i) == "table" and e.i or {}) do
            if not seenItem[id] then
                seenItem[id] = true
                bundledItems = bundledItems + 1
                if not built[id] then missing[#missing + 1] = id end
            end
        end
    end
    table.sort(missing)

    -- GuideData: { v = n, place = {...}, boss = {...}, ... }: count tables and their records.
    local nSrc, nGuide, nRecords = 0, 0, 0
    for _ in pairs(type(ns.SourcesData) == "table" and ns.SourcesData or {}) do nSrc = nSrc + 1 end
    for _, v in pairs(type(ns.GuideData) == "table" and ns.GuideData or {}) do
        if type(v) == "table" then
            nGuide = nGuide + 1
            for _ in pairs(v) do nRecords = nRecords + 1 end
        end
    end
    Count(2)
    if nSrc == 0 then Problem("DATA", "sources", "none loaded") end
    if type(ns.GuideData) ~= "table" then Problem("DATA", "guide", "not loaded") end
    if D.FlagCounts then
        Count()
        local ok, c = pcall(D.FlagCounts, D)
        if not ok then Problem("DATA", "flags", Short(c))
        elseif type(c) == "table" and (c.badFlags or 0) > 0 then Problem("DATA", "flags", c.badFlags .. " bad") end
    end
    local pieces = tostring(items)
    if bundledItems > 0 then
        pieces = ("%d/%d"):format(items, bundledItems)
        if #missing > 0 then
            local ids = {}
            for i = 1, math.min(#missing, MISSING_IDS) do ids[i] = tostring(missing[i]) end
            pieces = pieces .. (" (%d unknown to this client: %s%s)"):format(#missing,
                table.concat(ids, ","), #missing > MISSING_IDS and ",..." or "")
        end
    end
    Info(("sets %d/%d, pieces %s, sources %d, guide tables %d (%d records)"):format(
        #sets, bundled, pieces, nSrc, nGuide, nRecords))

    -- The list code runs without errors (no tooltips, no stats).
    Count()
    local filters = DeepCopy(ns.FILTER_DEFAULTS or {})
    filters.usable, filters.myFaction, filters.showHidden, filters.class, filters.armor = false, false, true, 0, 0
    filters.showRemoved, filters.hideComplete, filters.kind = true, false, ""
    local ok, list = pcall(D.Filter, D, "", filters)
    if not ok then Problem("DATA", "filter", Short(list))
    elseif type(list) ~= "table" or #list == 0 then Problem("DATA", "filter", "no sets with every filter off") end
    if D.GetEffort then
        Count()
        local failed, first = 0, nil
        for _, s in ipairs(sets) do
            local okE, e = pcall(D.GetEffort, D, s)
            if not okE then failed = failed + 1; first = first or Short(e) end
        end
        if failed > 0 then Problem("DATA", "effort", ("%d sets fail, %s"):format(failed, first)) end
    end
    local ms = Ms(t0)
    if ms > 250 then Info(("data checks %d ms"):format(math.floor(ms))) end

    -- The lists on screen hold rows.
    local SL, PL = ns.SetList, ns.PieceList
    if SL and type(SL.list) == "table" and ns.UI and ns.UI.IsShown and ns.UI:IsShown() then
        Count()
        local f = DB() and DB().filters
        local same = f and ns.FILTER_DEFAULTS and Lost(ns.FILTER_DEFAULTS, f) == nil
        if same and #SL.list == 0 and (not DB().search or DB().search == "") then
            Problem("UI", "sets", "list empty with default filters")
        end
    end
    if PL and PL.set and PL.box and PL.box.GetDataProvider then
        Count()
        local okP, dp = pcall(PL.box.GetDataProvider, PL.box)
        if okP and dp and dp.GetSize then
            local n = dp:GetSize()
            local want = #(PL.set.shown or PL.set.pieces)
            if not IsSecret(n) and n ~= want then Problem("UI", "pieces", ("%d rows for %d pieces"):format(n, want)) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hooks into the game

local function CheckHooks()
    Count()
    if SlashCmdList == nil or SlashCmdList.GEARSET ~= ns.HandleSlash or ns.HandleSlash == nil then
        Problem("HOOK", "slash", "GEARSET handler replaced")
    end
    Count()
    if SLASH_GEARSET1 ~= "/gearset" or SLASH_GEARSET2 ~= "/gs" then Problem("HOOK", "slash", "names changed") end
    local hash = _G.hash_SlashCmdList
    if type(hash) == "table" then
        Count()
        local h = hash["/GS"]
        if h ~= nil and h ~= ns.HandleSlash and h ~= SlashCmdList.GEARSET then
            Problem("HOOK", "slash", "/gs taken by another addon")
        end
    end
    Count()
    if type(BINDING_NAME_GEARSET_TOGGLE) ~= "string" or type(GearSet_Toggle) ~= "function" then
        Problem("HOOK", "binding", "missing")
    end

    -- Settings page: exists where the API does; check boxes match the saved data.
    local S = ns.Settings
    local api = type(Settings) == "table" and type(Settings.RegisterAddOnCategory) == "function"
    Count()
    if api and not (S and S.category) then
        Problem("HOOK", "settings", "no page")
    elseif not api then
        Skip("settings", "(no API)")
    end
    if api and S and S.category and S.VARS and S.VALUES and type(Settings.GetValue) == "function" then
        for key, var in pairs(S.VARS) do
            Count()
            local okV, v = pcall(Settings.GetValue, var)
            local spec = S.VALUES[key]
            if okV and v ~= nil and not IsSecret(v) and spec and spec.get then
                local okG, want = pcall(spec.get)
                if okG and (v and true or false) ~= (want and true or false) then
                    Problem("HOOK", "settings", key .. " differs from saved data")
                end
            end
        end
    end
end

-- Esc: our one UISpecialFrames slot holds the top of our Esc stack.
local OUR_ESC = { GearSetFrame = true, GearSetGuidePage = true, GearSetHelpFrame = true }
local function EscSlot()
    if type(UISpecialFrames) ~= "table" then return nil end
    for _, n in ipairs(UISpecialFrames) do
        if OUR_ESC[n] then return n end
    end
    return nil
end

local function CheckEsc(label)
    Count()
    local W = ns.Widgets
    local top = W and W.EscTop and W.EscTop() or "GearSetFrame"
    local slot = EscSlot()
    if slot ~= top then
        Problem("HOOK", "esc", ("%s: slot %s, top %s"):format(label, tostring(slot), tostring(top)))
    end
end

-- ---------------------------------------------------------------------------
-- Steps (one frame apart so the game has laid the frames out)

local Finish

local function Later(frames, fn)
    local function Tick()
        if not run then return end
        frames = frames - 1
        if frames > 0 then return C_Timer.After(0, Tick) end
        if InCombat() then
            run.stopped = true
            return Finish()
        end
        local ok, err = pcall(fn)
        if not ok then
            Problem("ERR", "step", Short(err))
            Finish()
        end
    end
    C_Timer.After(0, Tick)
end

local function Win() return ns.UI and ns.UI.frame end

local function StepHelp()
    CheckGroup(ST.HelpParts(), Win())
    CheckEsc("help open")
    Finish()
end

local function OpenHelp()
    local H = ns.Help
    if H and H.IsShown and H:IsShown() then
        Later(1, StepHelp)
    elseif H and H.Show then
        run.state.openedHelp = true
        H:Show()
        Later(2, StepHelp)
    else
        Skip("help", "(missing)")
        Finish()
    end
end

local function StepCopy()
    CheckGroup(ST.CopyParts(), Win())
    local G = ns.GuidePage
    if run.state.openedCopy then G:HideCopyText(); run.state.openedCopy = nil end
    OpenHelp()
end

local function StepGuide()
    local G = ns.GuidePage
    CheckGroup(ST.GuideParts(), Win())
    if G.copyMode then return StepCopy() end
    run.state.openedCopy = true
    G:ShowCopyText()
    Later(1, StepCopy)
end

local function OpenGuide()
    local G, PL = ns.GuidePage, ns.PieceList
    if not (G and PL and G.IsOpen) then
        Skip("guide", "(missing)")
        return OpenHelp()
    end
    if G:IsOpen() then return StepGuide() end
    local set = PL.set
    local list = set and (set.shown or set.pieces)
    -- A crafted set's guide may read item tooltips (bind type): not from the self-check.
    if not (list and list[1]) or set.kind == "c" then
        Skip("guide", set and "(crafted set shown)" or "(no set)")
        return OpenHelp()
    end
    run.state.openedGuide = true
    run.state.lastItem = PL.lastItem
    PL:ShowGuide(list[1])
    Later(2, StepGuide)
end

local function StepMain()
    CheckGroup(ST.MainParts(), Win())
    Guard("help where", function()
        local UI = ns.UI or {}
        local b = UI.helpButton
        if b then
            Info(("help %s at %s (window %s)"):format(b.gsArt and "art" or "link", WhereText(b), WhereText(Win())))
        end
    end)
    Guard("minimap", CheckMinimap)
    Guard("esc", CheckEsc, "window")
    if run.mode == "full" then return OpenGuide() end
    Finish()
end

-- ---------------------------------------------------------------------------
-- Restore and output

local function Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and run then Problem("ERR", "restore " .. label, Short(err)) end
end

local function Restore()
    local s = run.state
    local G, PL, H, UI = ns.GuidePage, ns.PieceList, ns.Help, ns.UI
    if s.openedHelp and H and H.Hide then Try("help", H.Hide, H) end
    if s.openedCopy and G and G.HideCopyText then Try("copy", G.HideCopyText, G) end
    if s.openedGuide and G and G.Back then
        Try("guide", G.Back, G)
        if PL then
            PL.lastItem = s.lastItem
            if PL.Refresh then Try("list", PL.Refresh, PL) end
        end
    end
    -- Our Esc slot back to the window's name (watch-point 3), whatever happened above.
    Try("esc", function()
        local W = ns.Widgets
        if W and W.PopEsc then
            if s.openedHelp then W.PopEsc("GearSetHelpFrame") end
            if s.openedGuide then W.PopEsc("GearSetGuidePage") end
        end
        local userOpen = (G and G.IsOpen and G:IsOpen()) or (H and H.IsShown and H:IsShown())
        if not userOpen and type(UISpecialFrames) == "table" then
            local found = false
            for i, n in ipairs(UISpecialFrames) do
                if n == "GearSetFrame" then found = true
                elseif n == "GearSetGuidePage" or n == "GearSetHelpFrame" then
                    UISpecialFrames[i] = "GearSetFrame"
                    found = true
                    Problem("HOOK", "esc", "slot put back by hand")
                end
            end
            if not found and Win() then
                tinsert(UISpecialFrames, "GearSetFrame")
                Problem("HOOK", "esc", "window slot was missing")
            end
        end
    end)
    -- The window last, while Help.quiet still keeps help.seen as it was.
    if s.openedWindow and UI and UI.frame then Try("window", UI.frame.Hide, UI.frame) end
    if H then H.quiet = s.helpQuiet end
end

local function Version()
    local P = ns.Probe
    if P and P.AddonVersion then
        local ok, v = pcall(P.AddonVersion)
        if ok and v then return v end
    end
    return "?"
end

-- The copy text: header, one line per problem, skips, info. No names, realms, guilds or links.
function ST.Text(r)
    r = r or run
    local okB, ver, build = false
    if GetBuildInfo then okB, ver, build = pcall(GetBuildInfo) end
    local head = ("GS selftest %s | game %s (%s) | %s | %d checks, %d problems"):format(Version(),
        okB and tostring(ver) or "?", okB and tostring(build) or "?", r.mode, r.checks, #r.problems)
    if r.stopped then head = head .. " | stopped: combat" end
    local parts = { head }
    for _, p in ipairs(r.problems) do parts[#parts + 1] = p end
    if #r.skips > 0 then
        parts[#parts + 1] = ("skipped %d: %s"):format(#r.skips,
            table.concat(r.skips, ", ", 1, math.min(#r.skips, MAX_LIST)))
    end
    for _, i in ipairs(r.info) do parts[#parts + 1] = i end
    local text = table.concat(parts, " | ")
    local max = ns.COPY_MAX or 4000
    if #text > max then text = text:sub(1, max - 3) .. "..." end
    return text
end

Finish = function()
    if not run then return end
    local ok, err = pcall(Restore)
    if not ok then Problem("ERR", "restore", Short(err)) end
    local r = run
    run = nil
    local L = ns.L
    if r.stopped then
        ns.Print(L.SELFTEST_STOPPED)
    elseif #r.problems == 0 then
        ns.Print(L.SELFTEST_OK:format(r.checks))
    else
        ns.Print(L.SELFTEST_BAD:format(#r.problems, r.checks))
    end
    if ns.ShowCopyBox then pcall(ns.ShowCopyBox, "selftest", ST.Text(r)) end
    ST.last = r
end

-- ---------------------------------------------------------------------------
-- Start

local waiter
local function AfterCombat(mode)
    if not waiter then waiter = CreateFrame("Frame") end
    waiter.mode = mode
    waiter:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self:SetScript("OnEvent", nil)
        ST:Start(self.mode)
    end)
    ns.SafeRegister(waiter, "PLAYER_REGEN_ENABLED")
end

function ST.NewRun(mode)
    return { mode = mode or "quick", checks = 0, problems = {}, skips = {}, info = {}, state = {} }
end

function ST:Start(mode)
    if run then return ns.Print(ns.L.SELFTEST_BUSY) end
    if InCombat() then
        ns.Print(ns.L.SELFTEST_COMBAT)
        return AfterCombat(mode)
    end
    run = ST.NewRun(mode)
    -- Checks that need no window.
    Guard("db", CheckSaved)
    Guard("data", CheckData)
    Guard("hooks", CheckHooks)
    Guard("theme", CheckTheme)
    -- The window: opened if closed (no first-time help while we run), checked next frame.
    local UI, H = ns.UI, ns.Help
    if H then run.state.helpQuiet = H.quiet; H.quiet = true end
    local ok, err = pcall(function()
        UI:Build()
        if not UI.frame:IsShown() then
            run.state.openedWindow = true
            UI.frame:Show()
        end
    end)
    if not ok then
        Problem("ERR", "window", Short(err))
        return Finish()
    end
    Later(2, StepMain)
end

-- For the offline test: check a list of parts against a window and return the run.
function ST.CheckPartsForTest(parts, win)
    run = ST.NewRun("test")
    CheckGroup(parts, win)
    local r = run
    run = nil
    return r
end
