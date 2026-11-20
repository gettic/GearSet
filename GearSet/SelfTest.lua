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
local ADDON_NAME, ns = ...

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
        -- ui-review-3: "Sets complete" box under the title (only with the Progress module)
        { name = "countBox", obj = UI.countBox, opt = not ns.Progress },
    }
    for i, t in ipairs(UI.tabs or {}) do
        parts[#parts + 1] = { name = "tab" .. i, obj = t.button }
    end
    local guideOpen = ns.GuidePage and ns.GuidePage.IsOpen and ns.GuidePage:IsOpen()
    if not guideOpen then
        local list = {
            { name = "setPrev", obj = PL.prevB }, { name = "setNext", obj = PL.nextB },
            { name = "title", obj = PL.title }, { name = "countBar", obj = PL.countBar },
            { name = "count", obj = PL.count, shownOnly = true },
            { name = "pDivider", obj = PL.divider, thin = true },
            { name = "bonuses", obj = PL.bonuses, shownOnly = true },
            { name = "stats", obj = PL.stats, shownOnly = true },
            { name = "effort", obj = PL.effort, shownOnly = true, opt = true },
            { name = "pieces", obj = PL.box },
        }
        for _, p in ipairs(list) do parts[#parts + 1] = p end
    end
    return parts
end

-- beta.8 Progress tab (checked while it is shown).
function ST.ProgressParts()
    local UI, P = ns.UI or {}, ns.Progress or {}
    local parts = {
        { name = "pPage", obj = UI.progressPage }, { name = "pPct", obj = P.pct },
        { name = "pScope", obj = P.scope }, { name = "pTotal", obj = P.total },
        { name = "pList", obj = P.scroll }, { name = "pNote", obj = P.note },
        { name = "pLeft", obj = P.leftScroll, opt = true },
    }
    for i, b in ipairs(P.bars or {}) do
        parts[#parts + 1] = { name = "pBar" .. i, obj = b, shownOnly = true }
    end
    for i, b in ipairs(P.charRows or {}) do
        parts[#parts + 1] = { name = "pChar" .. i, obj = b, shownOnly = true }
    end
    return parts
end

-- Bottom tabs hang from under the window's bottom border like CharacterFrame's (top at most
-- Theme.sizes.tabOffsetY px above the window's bottom edge: the border draws over that
-- strip, Blizzard's design), the rest below the window, inside its left/right edges.
local function CheckTabs()
    local UI = ns.UI or {}
    local win = UI.frame
    local sizes = (ns.Theme and ns.Theme.sizes) or {}
    local tuck = math.max(0, tonumber(sizes.tabOffsetY) or 0)
    for i, t in ipairs(UI.tabs or {}) do
        Count()
        local r, w = ScreenRect(t.button), ScreenRect(win)
        if r == "secret" or w == "secret" then
            Skip("tab" .. i, "(secret)")
        elseif type(r) == "table" and type(w) == "table" then
            -- ScreenRect is in screen px; the offset is in window px.
            local s = select(2, Read(win, "GetEffectiveScale"))
            local reach = tuck * (type(s) == "number" and s or 1)
            if r.t > w.b + reach + SCREEN_SLACK then
                Problem("UI", "tab" .. i, ("too far up into the window (%d px)"):format(math.floor(r.t - w.b)))
            elseif r.b > w.b - SCREEN_SLACK then
                Problem("UI", "tab" .. i, "does not hang below the window")
            elseif r.l < w.l - SCREEN_SLACK or r.r > w.r + SCREEN_SLACK then
                Problem("UI", "tab" .. i, "not under the window")
            end
        end
    end
end

-- beta.9: the guide's Way buttons in view (inside the scroll area; scrolled-away ones skipped).
local MAX_WAY_PARTS = 4
local function WayParts(G, parts)
    local area = G.scroll and ScreenRect(G.scroll)
    if type(area) ~= "table" then return end
    local n = 0
    for i = 1, math.min(G.wayUsed or 0, #(G.wayPool or {})) do
        local b = G.wayPool[i]
        local r = ScreenRect(b)
        if type(r) == "table" and r.t <= area.t + SCREEN_SLACK and r.b >= area.b - SCREEN_SLACK and n < MAX_WAY_PARTS then
            n = n + 1
            parts[#parts + 1] = { name = "gWay" .. i, obj = b, shownOnly = true, art = b.icon and { "icon" } or nil }
        end
    end
end

function ST.GuideParts()
    local G = ns.GuidePage or {}
    local parts = {
        { name = "gBack", obj = G.back }, { name = "gCopy", obj = G.copy }, { name = "gWiki", obj = G.wiki },
        { name = "gPrev", obj = G.prevB }, { name = "gNext", obj = G.nextB },
        { name = "gIcon", obj = G.icon, artSelf = true }, { name = "gName", obj = G.name },
        { name = "gModel", obj = G.modelCheck }, { name = "gCopyText", obj = G.copyText },
        { name = "gScroll", obj = G.scroll },
    }
    WayParts(G, parts)
    return parts
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
        -- the arrow (template or file art; nil = line only) and the gold line, which hides
        -- itself when the gap to the gear is tiny
        { name = "note4Arrow", obj = H.arrow, opt = true, art = H.arrow and { "gsArrow" } or nil },
        { name = "note4Line", obj = H.line, opt = true, thin = true, shownOnly = true },
        { name = "gotIt", obj = H.okButton },
    }
end

-- Minimap button: shown as the setting says, next to the minimap.
local function CheckMinimap()
    local MB = ns.MinimapButton
    -- review 3: the icon file the button and the data-bar launcher use loads
    if MB and MB.IconFile then
        Count()
        local okI, file = pcall(MB.IconFile)
        if not okI or type(file) ~= "string" then
            Problem("ART", "minimap icon", "no icon file loads")
        elseif FileLoads(file) == false then   -- nil = couldn't check
            Problem("ART", "minimap icon", "icon file does not load: " .. file)
        end
    end
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
        if not (ignore and ignore[p]) then      -- ignored paths are expected to change
            if type(v) == "table" then
                if type(n) ~= "table" then return p end
                local deeper = Lost(v, n, p, depth + 1, ignore)
                if deeper then return deeper end
            elseif not Same(v, n) then
                return p
            end
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

local V2_SAMPLE = {
    version = 2, point = { "CENTER", "CENTER", 5, 5 },
    filters = { class = 0, armor = 0, usable = true, hideComplete = false, showRemoved = false,
        kind = "", myFaction = true, showHidden = true },
    sort = "effort", search = "", lastSet = "c1", onlySet = false, minimap = { angle = 90, hide = false },
    hidden = { ["set:1"] = true }, help = { seen = true }, custom = "keep",
}

-- Two made-up characters (never the user's own data); "A" and "B" only.
local V3_SAMPLE = {
    version = 3, chars = {
        ["A-Realm"] = { name = "A", realm = "Realm", class = "ROGUE", seen = 1000,
            places = { equipped = "16820,16821", bags = "", bank = "16822", mail = "16823", keyring = "" },
            dates = { equipped = 1000, bank = 900, mail = 800 }, done = { [204] = 950 } },
        ["B-Realm"] = { name = "B", realm = "Realm", seen = 500, places = { bank = "16820" } },
    },
    account = { bank = "16824", date = 700, readable = true, checked = 700 },
    tooltipLine = false, tooltipShift = true, altClick = false,
}

-- beta.8 (DB v4): tracking, progress choice, recently got, milestones (made-up "A" again).
local V4_SAMPLE = {
    version = 4, filters = { trackedOnly = true, tier = "T2" },
    tracked = { ["A-Realm"] = { ["set:204"] = true, ["item:16820"] = true } },
    progress = { scope = "account", got = { ["A-Realm"] = { [16820] = 0, [16821] = 1200 } },
        marks = { ["A-Realm"] = { first_set = 0 } } },
    milestoneNotes = false,
    prices = { [16820] = { c = 120000, t = 1300 }, [16821] = { c = 0, x = "2805 Honor Points", t = 1300 } },
}

-- v1.0.1 (DB v5): "Hide sets not out yet" on (made-up "A" again).
local V5_SAMPLE = {
    version = 5, filters = { hideLater = true, trackedOnly = true },
    tracked = { ["A-Realm"] = { ["set:181"] = true } },
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

    -- 3b. v2 data (beta.2-6): every value kept, the v3 keys added (chars, account, tooltip
    -- settings); a v3 alt record goes through unchanged.
    Count()
    local v2 = DeepCopy(V2_SAMPLE)
    ok, err = pcall(prep, v2)
    if not ok then
        Problem("DB", "v2", Short(err))
    else
        local lost = Lost(V2_SAMPLE, v2, nil, 0, { version = true })
        if lost then Problem("DB", "v2", "lost " .. lost)
        elseif type(v2.chars) ~= "table" or type(v2.account) ~= "table" or v2.tooltipLine ~= true
            or v2.tooltipShift ~= false or v2.altClick ~= true then Problem("DB", "v2", "v3 keys not added")
        elseif v2.version ~= ns.DB_VERSION then Problem("DB", "v2", "version not raised") end
    end
    Count()
    local v3 = DeepCopy(V3_SAMPLE)
    ok, err = pcall(prep, v3)
    if not ok then
        Problem("DB", "v3", Short(err))
    else
        local lost = Lost(V3_SAMPLE, v3, nil, 0, { version = true })
        if lost then Problem("DB", "v3", "changed " .. lost)
        elseif type(v3.tracked) ~= "table" or type(v3.progress) ~= "table" or v3.progress.scope ~= "char"
            or type(v3.progress.got) ~= "table" or type(v3.progress.marks) ~= "table" or v3.milestoneNotes ~= true
            or v3.filters.trackedOnly ~= false or v3.filters.tier ~= "" or type(v3.prices) ~= "table" then
            Problem("DB", "v3", "v4 keys not added")
        elseif v3.version ~= ns.DB_VERSION then Problem("DB", "v3", "version not raised") end
    end
    -- 3c. v4 data (beta.8) goes through unchanged; a bad tier / scope falls back.
    Count()
    local v4 = DeepCopy(V4_SAMPLE)
    ok, err = pcall(prep, v4)
    if not ok then
        Problem("DB", "v4", Short(err))
    else
        local lost = Lost(V4_SAMPLE, v4, nil, 0, { version = true })   -- v1.0.1: version raised to 5
        if lost then Problem("DB", "v4", "changed " .. lost) end
    end
    Count()
    local bad4 = { version = 4, filters = { tier = "T1; drop" }, progress = { scope = "x", got = { keep = 1 } } }
    ok, err = pcall(prep, bad4)
    if not ok then
        Problem("DB", "bad v4", Short(err))
    elseif bad4.filters.tier ~= "" or bad4.progress.scope ~= "char" or bad4.progress.got.keep ~= 1 then
        Problem("DB", "bad v4", "not fixed or data lost")
    end
    -- 3d. v1.0.1 (DB v5): v4 data gets filters.hideLater = false, nothing else changes; v5 data
    -- goes through unchanged; a wrong-typed hideLater falls back.
    Count()
    local v4b = DeepCopy(V4_SAMPLE)
    ok, err = pcall(prep, v4b)
    if not ok then
        Problem("DB", "v4 -> v5", Short(err))
    elseif v4b.filters.hideLater ~= false or v4b.version ~= ns.DB_VERSION then
        Problem("DB", "v4 -> v5", "v5 key not added")
    end
    Count()
    local v5 = DeepCopy(V5_SAMPLE)
    ok, err = pcall(prep, v5)
    if not ok then
        Problem("DB", "v5", Short(err))
    else
        local lost = Lost(V5_SAMPLE, v5)
        if lost then Problem("DB", "v5", "changed " .. lost) end
    end
    Count()
    local bad5 = { version = 5, filters = { hideLater = "yes" } }
    ok, err = pcall(prep, bad5)
    if not ok then Problem("DB", "bad v5", Short(err))
    elseif bad5.filters.hideLater ~= false then Problem("DB", "bad v5", "hideLater not fixed") end

    -- Learned vendor prices (Prices.lua): a count only.
    if type(db.prices) == "table" then
        local n = 0
        for _ in pairs(db.prices) do n = n + 1 end
        Info(("prices learned: %d"):format(n))
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
-- Alt memory (Alts.lua): pure checks on made-up data + counts of the live data.
-- No character names ever go into the result (counts and yes/no only).

local function CheckAlts()
    local A = ns.Alts
    Count()
    if not (A and A.BuildIndex and A.Encode and A.Decode) then return Problem("ALT", "module", "missing") end
    -- id strings: sorted, no doubles, junk ignored
    Count()
    local s = A.Encode(A.Decode("16822,16820,16820,x"))
    if s ~= "16820,16822" then Problem("ALT", "ids", "encode gave " .. tostring(s)) end
    -- index on a copy of the made-up v3 data, as if "Me-Realm" were logged in
    Count()
    local copy = DeepCopy(V3_SAMPLE)
    local okI, idx, per, acc = pcall(A.BuildIndex, copy, "Me-Realm",
        { bags = { [16825] = true }, dates = { bags = 1 } }, { items = { [16824] = true }, date = 700 })
    if not okI then
        Problem("ALT", "index", Short(idx))
    else
        local h = idx[16820]
        local wrong
        if not (h and #h == 2 and h[1].key == "A-Realm" and h[1].where == "equipped" and h[2].where == "bank") then
            wrong = "16820"
        elseif not (idx[16823] and idx[16823][1].where == "mail" and idx[16823][1].seen == 800) then
            wrong = "mail"
        elseif not (idx[16825] and idx[16825][1].key == "Me-Realm" and idx[16825][1].where == "bags") then
            wrong = "live"
        elseif not (idx[16824] and idx[16824][1].where == "account" and acc[16824]) then
            wrong = "account"
        elseif not (per["B-Realm"] and per["B-Realm"][16820]) then
            wrong = "per char"
        end
        if wrong then Problem("ALT", "index", "wrong " .. wrong) end
        if Lost(V3_SAMPLE, copy) then Problem("ALT", "index", "changed its input") end
    end
    -- live calls answer without errors (results not shown: they hold names)
    Count()
    local okL, err = pcall(function()
        assert(type(A:GetHolders(16827)) == "table", "GetHolders")
        assert(type(A:Chars()) == "table", "Chars")
        local have, total = A:GetSetProgress(1)
        assert(type(have) == "number" and type(total) == "number", "GetSetProgress")
    end)
    if not okL then Problem("ALT", "live", Short(err)) end
    -- counts + account bank state (so nobody has to test it at a bank by hand)
    local okS, n, ids = pcall(A.Stats, A)
    if okS then Info(("alts %d saved (%d pieces)"):format(n or 0, ids or 0)) end
    local okA, api, now, last, checked = pcall(A.AccountStatus, A)
    if okA then
        local text = "account bank: " .. (api and "API yes" or "API no")
        if now ~= nil then text = text .. (now and ", readable now" or ", NOT readable now") end
        if last == true then text = text .. ", readable at the last bank visit"
        elseif last == false then text = text .. ", not readable at the last bank visit"
        else text = text .. ", no bank visit yet" end
        if (checked or 0) > 0 and A.DateText then text = text .. " (" .. tostring(A.DateText(checked)) .. ")" end
        Info(text)
    end
end

-- ---------------------------------------------------------------------------
-- beta.8: tracking, progress, milestones, gold, chat share (made-up data + live counts only)

local function GroupSums(s)
    local h, t, n = 0, 0, 0
    for _, g in pairs(s.kinds) do h, t, n = h + g.have, t + g.total, n + g.sets end
    return h, t, n
end

-- Progress numbers that must add up (any summary, live or made up). nil = fine.
local function SumProblem(s)
    if type(s) ~= "table" then return "no summary" end
    if s.have > s.total or s.have < 0 then return "have > total" end
    if s.complete + s.started > s.sets then return "complete + started > sets" end
    local h, t, n = GroupSums(s)
    if h ~= s.have or t ~= s.total or n ~= s.sets then return "kinds don't add up" end
    for _, g in pairs(s.tiers) do
        if g.have > g.total or g.total > s.total then return "tier bigger than total" end
    end
    local pct = s.total > 0 and math.floor(s.have * 100 / s.total) or 0
    if s.pct ~= pct then return "percent wrong" end
end

local function CheckProgress()
    local TR, P = ns.Track, ns.Progress
    if not (TR and P and TR.ToggleIn and P.Summarize) then return Skip("progress", "(not loaded)") end
    -- tracking round trip on a copy of the made-up v4 data
    Count()
    local tbl = DeepCopy(V4_SAMPLE.tracked)
    tbl["X-Realm"] = "keep"
    local a = TR.ToggleIn(tbl, "B-Realm", "set:1")
    local b = TR.IsIn(tbl, "B-Realm", "set:1")
    local c = TR.ToggleIn(tbl, "B-Realm", "set:1")
    local d = TR.IsIn(tbl, "B-Realm", "set:1")
    local e = TR.ToggleIn(tbl, "X-Realm", "set:1")
    if not (a == true and b and c == false and not d and e == nil and tbl["X-Realm"] == "keep"
            and TR.IsIn(tbl, "A-Realm", "set:204") and Lost(V4_SAMPLE.tracked, tbl) == nil) then
        Problem("PRG", "track", "round trip wrong")
    end
    -- a broken entry: only the given (own) character's one is repaired
    if TR.FixMine then
        tbl["Y-Realm"] = 5
        local f1 = TR.FixMine(tbl, "X-Realm")
        local f2 = TR.FixMine(tbl, "X-Realm")
        local f3 = TR.FixMine(tbl, "A-Realm")
        if not (f1 == true and f2 == false and f3 == false and type(tbl["X-Realm"]) == "table"
                and tbl["Y-Realm"] == 5 and TR.ToggleIn(tbl, "X-Realm", "set:1") == true
                and TR.IsIn(tbl, "A-Realm", "set:204")) then
            Problem("PRG", "track", "broken entry repair wrong")
        end
    end
    -- counting rules on made-up sets: removed, other faction, hidden, not out yet left out
    Count()
    local sets = {
        { key = "a", kind = "d", tier = "D1", n = 2, t = 4 }, { key = "b", kind = "d", n = 4, t = 4 },
        { key = "c", kind = "r", tier = "T1", n = 0, t = 8 }, { key = "r", kind = "d", removed = true, n = 1, t = 1 },
        { key = "f", kind = "p", faction = "H", n = 1, t = 1 }, { key = "h", kind = "d", n = 1, t = 1 },
        { key = "u", kind = "r", unreleased = true, n = 0, t = 8 },
    }
    local s = P.Summarize(sets, function(set) return set.n, set.t end, "A", function(set) return set.key == "h" end)
    if s.total ~= 16 or s.have ~= 6 or s.complete ~= 1 or s.started ~= 1 or s.sets ~= 3 or s.pct ~= 37
        or not (s.tiers.T1 and s.tiers.D1) or SumProblem(s) then
        Problem("PRG", "rules", ("made-up sum %d/%d %d%%"):format(s.have, s.total, s.pct))
    end
    -- "This character": only sets the class can wear (here: not "c")
    Count()
    local sc = P.Summarize(sets, function(set) return set.n, set.t end, "A", function(set) return set.key == "h" end,
        function(set) return set.key ~= "c" end)
    if sc.total ~= 8 or sc.have ~= 6 or sc.sets ~= 2 or sc.tiers.T1 or SumProblem(sc) then
        Problem("PRG", "class", ("made-up class sum %d/%d"):format(sc.have, sc.total))
    end
    -- live: both scopes add up; this character's class sets are part of the account's
    local live = {}
    for _, scope in ipairs({ "char", "account" }) do
        Count()
        local ok, got = pcall(P.Get, P, scope)
        if not ok then
            Problem("PRG", scope, Short(got))
        elseif got then
            live[scope] = got
            local why = SumProblem(got)
            if why then Problem("PRG", scope, why) end
            Info(("progress %s %d%% (%d/%d, %d complete)"):format(scope, got.pct, got.have, got.total, got.complete))
        end
    end
    Count()
    if live.char and live.account and (live.char.total > live.account.total or live.char.sets > live.account.sets) then
        Problem("PRG", "class", "this character counts more sets than the account")
    end
    Count()
    local okL, line = pcall(P.LineText, P)
    if not okL then Problem("PRG", "line", Short(line))
    elseif type(line) ~= "string" then Skip("progress line", "(no data)") end
    -- milestones: first look is silent, each one once only
    Count()
    local marks = {}
    local s0 = { have = 0, total = 10, complete = 0 }
    local s1 = { have = 3, total = 10, complete = 1 }
    local m0 = P.NewMilestones(marks, "A-Realm", s0, 100)
    local m1 = P.NewMilestones(marks, "A-Realm", s1, 200)
    local m2 = P.NewMilestones(marks, "A-Realm", s1, 300)
    local mB = P.NewMilestones(marks, "B-Realm", s1, 300)
    local has = {}
    for _, id in ipairs(m1) do has[id] = true end
    if not (#m0 == 0 and #m1 == 2 and has.first_set and has.pct_25 and #m2 == 0 and #mB == 0
            and marks["A-Realm"].first_set == 200 and marks["B-Realm"].first_set == 0) then
        Problem("PRG", "milestone", "not once only")
    end
    -- recently got: first look stores 0, then dates
    Count()
    local got = {}
    local g0 = P.UpdateGot(got, "A-Realm", { [1] = true }, 100)
    local g1 = P.UpdateGot(got, "A-Realm", { [1] = true, [2] = true }, 200)
    if not (#g0 == 0 and #g1 == 1 and got["A-Realm"][1] == 0 and got["A-Realm"][2] == 200) then
        Problem("PRG", "got", "wrong")
    end
    -- PART B's gold + chat share (skipped when the files aren't there)
    local G, SH = ns.Gold, ns.Share
    if G and G.PieceCost then
        Count()
        local okC, copper = pcall(G.PieceCost, G, 21996)
        if not okC then Problem("GOLD", "piece", Short(copper))
        elseif copper ~= 200000 then Problem("GOLD", "piece", "21996 = " .. tostring(copper)) end
    else
        Skip("gold", "(missing)")
    end
    if SH and SH.Text then
        Count()
        local setID
        local D = ns.Data
        for _, set in ipairs((D and D.GetSets and D:GetSets()) or {}) do
            if set.id and #set.pieces >= 6 then setID = set.id; break end
        end
        if setID then
            local okT, text = pcall(SH.Text, setID, 255)
            local me = UnitName and UnitName("player")
            if not okT then Problem("SHARE", "text", Short(text))
            elseif type(text) ~= "string" or #text > 255 then Problem("SHARE", "text", "longer than 255")
            elseif type(me) == "string" and me ~= "" and text:find(me, 1, true) then
                Problem("SHARE", "text", "has the character name")
            else
                Info(("share %d chars"):format(#text))
            end
        end
    else
        Skip("share", "(missing)")
    end
    -- the "Gear Set:" note when a share can't go into the chat box
    if P.ShareNote then
        Count()
        local full, loading = P.ShareNote(false, "full"), P.ShareNote(false, "loading")
        if not (P.ShareNote(true, "full") == nil and type(full) == "string" and full ~= ""
                and type(loading) == "string" and loading ~= "" and full ~= loading
                and P.ShareNote(false, nil) == nil) then
            Problem("SHARE", "note", "wrong failure note")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Data

local function Ms(start)
    if type(debugprofilestop) ~= "function" then return 0 end
    return debugprofilestop() - start
end
local function Now() return type(debugprofilestop) == "function" and debugprofilestop() or 0 end

-- beta.9 map positions (PlacesData) and the Way button's data: every map ID is a real map
-- (English client: with the zone's name) where a map pin can be set; every position parses
-- and its zone has an ID (zones with no static ID, e.g. Riverglades, are looked up and
-- printed so the next data build can add them); a dungeon piece's guide carries a Way point.
-- Read-only: GetMapInfo / CanSetUserWaypointOnMap only, never a waypoint, TomTom or super-track call.
local function CheckPlaces()
    local PD, Way = ns.PlacesData, ns.Way
    Count()
    if type(PD) ~= "table" or type(PD.map) ~= "table" or type(PD.at) ~= "table" then
        return Problem("MAP", "places", "not loaded")
    end
    if not Way then return Problem("MAP", "Way", "missing") end
    local getInfo = C_Map and type(C_Map.GetMapInfo) == "function" and C_Map.GetMapInfo or nil
    local canSet = C_Map and type(C_Map.CanSetUserWaypointOnMap) == "function" and C_Map.CanSetUserWaypointOnMap or nil
    local okLocale, locale = pcall(GetLocale)
    local english = okLocale and (locale == "enUS" or locale == "enGB")
    local nMaps, nOk, nPin, bad, badName = 0, 0, 0, {}, {}
    for zone, id in pairs(PD.map) do
        nMaps = nMaps + 1
        Count()
        if getInfo then
            local ok, info = pcall(getInfo, id)
            if not ok or type(info) ~= "table" then
                bad[#bad + 1] = zone .. "=" .. tostring(id)
            else
                nOk = nOk + 1
                if english and not IsSecret(info.name) and info.name ~= zone then
                    badName[#badName + 1] = ("%s=%s"):format(zone, tostring(info.name))
                end
            end
        end
        if canSet then
            local ok, can = pcall(canSet, id)
            if ok and can == true then nPin = nPin + 1 end
        end
    end
    if not getInfo then Skip("maps", "(no GetMapInfo)") end
    if #bad > 0 then
        Problem("MAP", "ids", ("%d unknown: %s"):format(#bad, table.concat(bad, ", ", 1, math.min(#bad, MAX_LIST))))
    end
    if #badName > 0 then
        Problem("MAP", "names", ("%d differ: %s"):format(#badName, table.concat(badName, ", ", 1, math.min(#badName, MAX_LIST))))
    end
    -- Every position parses; zones without a static ID are found at runtime (or not).
    local nAt, badAt, extra = 0, {}, {}
    for key, raw in pairs(PD.at) do
        nAt = nAt + 1
        Count()
        local rec = Way.Parse(raw)
        if not rec then
            badAt[#badAt + 1] = tostring(key)
        else
            for _, p in ipairs(rec.points) do
                if type(PD.map[p.zone]) ~= "number" and extra[p.zone] == nil then
                    extra[p.zone] = Way.MapID(p.zone) or false
                end
            end
        end
    end
    if #badAt > 0 then
        Problem("MAP", "at", ("%d bad: %s"):format(#badAt, table.concat(badAt, ", ", 1, math.min(#badAt, MAX_LIST))))
    end
    local found = {}
    for zone, id in pairs(extra) do found[#found + 1] = ("%s = %s"):format(zone, id and tostring(id) or "none") end
    table.sort(found)
    Info(("maps %d/%d, map pins %d/%d, places %d%s"):format(nOk, nMaps, nPin, nMaps, nAt,
        #found > 0 and (", " .. table.concat(found, ", ")) or ""))
    -- A dungeon drop's guide has a Way point on its Where row (Data -> Way.Point).
    local D = ns.Data
    if D and D.GetGuide and type(ns.SourcesData) == "table" then
        Count()
        local itemID
        for id, src in pairs(ns.SourcesData) do
            local place = type(src) == "string" and src:match("^b|[^|;]*|([^|;@]+)")
            -- not crafted: a crafted piece's guide may read its tooltip (bind type)
            if place and PD.at["place:" .. place] and not src:find("^c|") and not src:find(";c|", 1, true) then
                itemID = id
                break
            end
        end
        if not itemID then return Skip("way data", "(no dungeon drop with a place)") end
        local ok, blocks = pcall(D.GetGuide, D, { itemID = itemID })
        local hasWay = false
        local function Walk(list)
            for _, b in ipairs(type(list) == "table" and list or {}) do
                if type(b.way) == "table" and b.way.x and b.way.y then hasWay = true end
                if b.blocks then Walk(b.blocks) end
            end
        end
        if ok then Walk(blocks) end
        if not ok then Problem("MAP", "guide", Short(blocks))
        elseif not hasWay then Problem("MAP", "guide", "item " .. tostring(itemID) .. " has no Way point") end
    end
end

-- beta.9 search (part C's check, plans\v1.0.0\beta9-C-adds.md 5). Read-only: never types into
-- the user's box, never changes GearSetDB.search, never calls SetPropagateKeyboardInput.
local function CheckSearch()
    local S = ns.Search
    if not (S and S.Find) then return Skip("search", "(not loaded)") end
    local sets = ns.Data and ns.Data:GetSets() or {}
    local first = sets[1]
    if first then
        Count()
        local groups = S.Find(first.name, sets)
        local g = type(groups) == "table" and groups[1]
        if not (g and g.kind == "set" and (g.n or 0) >= 1) then Problem("SEARCH", "find", "own set name not found") end
    end
    if S.Index then
        Count()
        local idx = S.Index()
        local nb, nNames = 0, 0
        for _, src in ipairs(type(idx) == "table" and type(idx.sources) == "table" and idx.sources or {}) do
            if src.kind == "boss" then nb = nb + 1 end
        end
        for _ in pairs(type(idx) == "table" and type(idx.names) == "table" and idx.names or {}) do nNames = nNames + 1 end
        Info(("search index: %d sources, %d named pieces"):format(
            type(idx) == "table" and type(idx.sources) == "table" and #idx.sources or 0, nNames))
        if nb == 0 then Problem("SEARCH", "index", "no bosses in the index") end
    end
    -- Ctrl+F is wired and keys pass on (ToS W1)
    local f = ns.UI and ns.UI.frame
    if f then
        Count()
        local okE, enabled = Read(f, "IsKeyboardEnabled")
        local okP, passes = Read(f, "GetPropagateKeyboardInput")
        if okE == "ok" and okP == "ok" and enabled and not passes then
            Problem("SEARCH", "keys", "window takes keys without passing them on")
        end
        if not f:GetScript("OnKeyDown") then Problem("SEARCH", "ctrlf", "no Ctrl+F handler") end
    end
end

-- Info "memory: N KB" = this addon's Lua memory as the game counts it (read-only; out of combat).
local function MemoryInfo()
    if InCombat() then return end
    local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
    if type(update) ~= "function" or type(get) ~= "function" then return Skip("memory", "(no API)") end
    local ok = pcall(update)
    local okG, kb = pcall(get, ADDON_NAME)
    if ok and okG and type(kb) == "number" and not IsSecret(kb) then
        Info(("memory: %d KB"):format(math.floor(kb + 0.5)))
    end
end

local function CheckData()
    local D = ns.Data
    Count()
    if not D then return Problem("DATA", "Data", "missing") end
    MemoryInfo()
    local t0 = Now()
    local sets = D:GetSets()
    Count()
    if type(sets) ~= "table" or #sets == 0 then return Problem("DATA", "sets", "none loaded") end
    local bundled = 0
    for _ in pairs(type(ns.ClassicSets) == "table" and ns.ClassicSets or {}) do bundled = bundled + 1 end
    Count()
    if bundled > 0 and #sets > bundled then Problem("DATA", "sets", ("%d built from %d"):format(#sets, bundled)) end

    local badSets, items, unknown, released = {}, 0, {}, {}
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
                if p.unknown then
                    -- v1.0.1 (F1): a released piece this client doesn't know (kept in the total)
                    released[#released + 1] = tostring(p.itemID)
                elseif type(instant) == "function" then
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
    -- v1.0.1 (F1): released pieces (no "not out yet" flag) this client doesn't know: the data
    -- says they're out, the game says they aren't. A problem, so the data gets checked.
    Count()
    if #released > 0 then
        table.sort(released)
        Problem("DATA", "released unknown", ("%d pieces: %s"):format(#released,
            table.concat(released, ", ", 1, math.min(#released, MAX_LIST))))
    end
    -- Owned counts them in the total and never marks such a set finished.
    local O = ns.Owned
    if O and O.SetCount and O.UnknownCount then
        Count()
        local fake = { key = "selftest-unknown", id = nil, pieces = {}, unknown = { { itemID = 1, unknown = true } } }
        local okC, have, total = pcall(O.SetCount, O, fake)
        if not okC then Problem("DATA", "unknown count", Short(have))
        elseif have ~= 0 or total ~= 1 then
            Problem("DATA", "unknown count", ("made-up set %s/%s, want 0/1"):format(tostring(have), tostring(total)))
        end
        if O.GetState and O:GetState(fake.unknown[1]) ~= "unknown" then
            Problem("DATA", "unknown count", "state is not unknown")
        end
    end

    -- Bundled items this client doesn't know (Data skips them while building): info only.
    local built, bundledItems, missing = {}, 0, {}
    for _, s in ipairs(sets) do
        for _, p in ipairs(type(s.shown or s.pieces) == "table" and (s.shown or s.pieces) or {}) do
            if not p.unknown then built[p.itemID] = true end
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
    -- v1.0.1 (F5): "Hide sets not out yet" leaves none of them; sorting puts released sets first.
    Count()
    filters.hideLater = true
    local okH, listH = pcall(D.Filter, D, "", filters)
    if not okH then Problem("DATA", "hide later", Short(listH))
    else
        for _, s in ipairs(type(listH) == "table" and listH or {}) do
            if s.unreleased then Problem("DATA", "hide later", "still lists " .. tostring(s.key)); break end
        end
    end
    local SLs = ns.SetList
    if ok and type(list) == "table" and SLs and type(SLs.LaterLess) == "function" then
        Count()
        local sorted = {}
        for i, s in ipairs(list) do sorted[i] = s end
        local okS = pcall(table.sort, sorted, function(a, b)
            local l = SLs.LaterLess(a, b)
            if l ~= nil then return l end
            return a.key < b.key
        end)
        local seenLater
        for _, s in ipairs(okS and sorted or {}) do
            if s.unreleased then seenLater = true
            elseif seenLater then Problem("DATA", "sort", "a released set after a set not out yet"); break end
        end
    end
    -- The list on screen (no search text: plain sets) in the saved sort order.
    if SLs and type(SLs.list) == "table" and not (DB() and DB().search ~= nil and DB().search ~= "") then
        Count()
        local seenLater
        for _, s in ipairs(SLs.list) do
            if type(s) == "table" and s.key and not s.gsKind then
                if s.unreleased then seenLater = true
                elseif seenLater then Problem("UI", "sets", "a released set listed after a set not out yet"); break end
            end
        end
    end
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
    -- review 3: "Only while Shift is held" hangs under "Show the Gear Set line" (Info, not
    -- Problem: without SetParentInitializer the row still works, just not indented).
    if S and S.category then
        Count()
        if S.shiftIndented ~= true then
            Info("settings: Shift row not indented (no SetParentInitializer on this client)")
        end
    end

    -- beta.7 (Tooltip.lua / Integrations.lua): tooltip post-call, the line text built for a
    -- set piece (builder called directly, no real tooltip; text not shown, it may hold
    -- names), public calls, Alt-click hook target, broker launcher.
    local Tip, Int = ns.Tooltip, ns.Integrations
    local SET_ITEM, OTHER_ITEM = 16827, 6948     -- a Nightslayer piece, the Hearthstone
    if not Tip then
        Skip("tooltip", "(not loaded)")
    else
        local TDP = _G.TooltipDataProcessor
        Count()
        if type(TDP) == "table" and type(TDP.AddTooltipPostCall) == "function" then
            if not Tip.hooked then Problem("HOOK", "tooltip", "line not hooked") end
        else
            Skip("tooltip", "(no TooltipDataProcessor)")
        end
        if type(Tip.LinesFor) == "function" and type(Tip.Lookup) == "function" then
            Count()
            local okP, isPiece = pcall(Tip.Lookup, SET_ITEM)
            if okP and isPiece ~= nil then
                local okL, lines = pcall(Tip.LinesFor, SET_ITEM)
                if not okL then Problem("HOOK", "tooltip", "line for " .. SET_ITEM .. ": " .. Short(lines))
                elseif type(lines) ~= "table" or type(lines[1]) ~= "string" or lines[1] == "" then
                    Problem("HOOK", "tooltip", "no line for " .. SET_ITEM)
                end
                -- review 3: an item in one set says "have x/y" (no set name; Blizzard's set block has it)
                if type(isPiece) == "number" and okL and type(lines) == "table" and type(lines[1]) == "string"
                    and type(Tip.SetOf) == "function" then
                    Count()
                    local okS, _, setName = pcall(Tip.SetOf, isPiece)
                    if okS and type(setName) == "string" and setName ~= "" and lines[1]:find(setName, 1, true) then
                        Problem("HOOK", "tooltip", "one-set line repeats the set name")
                    end
                end
            else
                Info(SET_ITEM .. " is not a set piece in the data")
            end
            Count()
            local okO, other = pcall(Tip.LinesFor, OTHER_ITEM)
            if not okO or type(other) ~= "table" or #other > 0 then
                Problem("HOOK", "tooltip", "line on a non-set item")
            end
            -- v1.0.1 (F2): a Dungeon Set 1 piece gets the "keep it" line, a T1 piece doesn't.
            if type(Tip.KeepLine) == "function" then
                local d1Item
                local ids = {}
                for setID in pairs(type(ns.ClassicSets) == "table" and ns.ClassicSets or {}) do ids[#ids + 1] = setID end
                table.sort(ids)
                for _, setID in ipairs(ids) do
                    local e = ns.ClassicSets[setID]
                    if type(e) == "table" and e.t == "D1" and type(e.i) == "table" and e.i[1] then d1Item = e.i[1]; break end
                end
                local keepText = (ns.L and ns.L.TIP_KEEP_D2_LATER) or "Keep it"
                local keepShort = keepText:match("^[^:]+") or keepText
                local function HasKeep(itemID)
                    local okK, lines = pcall(Tip.LinesFor, itemID)
                    if not okK or type(lines) ~= "table" then return nil end
                    for _, l in ipairs(lines) do
                        if type(l) == "string" and l:find(keepShort, 1, true) then return true end
                    end
                    return false
                end
                if d1Item then
                    Count()
                    if HasKeep(d1Item) ~= true then Problem("HOOK", "tooltip", "no keep line on D1 piece " .. d1Item) end
                end
                Count()
                if HasKeep(SET_ITEM) == true then Problem("HOOK", "tooltip", "keep line on a non-D1 piece") end
            end
        end
    end
    if not Int then
        Skip("public calls", "(not loaded)")
    elseif type(GearSet_IsSetPiece) ~= "function" or type(GearSet_ShowItem) ~= "function" then
        Count()
        Problem("HOOK", "public calls", "missing")
    else
        Count()
        local okA, a = pcall(GearSet_IsSetPiece, SET_ITEM)
        local okB, b = pcall(GearSet_IsSetPiece, OTHER_ITEM)
        local inData = Tip and Tip.Lookup and Tip.Lookup(SET_ITEM) ~= nil
        if not (okA and okB) or b ~= false or (inData and a ~= true) then
            Problem("HOOK", "public calls", "GearSet_IsSetPiece wrong")
        end
    end
    if Int then
        Count()
        local click = type(Int.OnItemClick) == "function" and type(HandleModifiedItemClick) == "function"
        if not click then Problem("HOOK", "alt-click", "no hook target") end
        local LS = _G.LibStub
        local ldb
        if LS ~= nil then
            local okD, l = pcall(LS, "LibDataBroker-1.1", true)
            ldb = okD and type(l) == "table" and type(l.NewDataObject) == "function" and l or nil
        end
        Count()
        if ldb and not Int.broker then Problem("HOOK", "broker", "LibDataBroker loaded but no launcher")
        else Info("broker launcher " .. (Int.broker and "yes" or "no (no LibDataBroker)")) end
    end
    -- review 3: inspect strip look (only once the inspect window was used this session)
    local Insp = ns.Inspect
    if Insp and Insp.strip then
        Count()
        local okT, tmpl = pcall(ns.Theme.Template, "inspectStrip")
        Info("inspect strip: " .. ((okT and tmpl) and "tooltip box" or "colour box"))
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

local OpenProgress

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
    Guard("tabs", CheckTabs)
    OpenProgress()
end

-- beta.8: the Progress tab, then back to the Sets tab (guide + help need it).
local function StepProgress()
    CheckGroup(ST.ProgressParts(), Win())
    Guard("progress tab", function()
        local P = ns.Progress
        Count()
        local text = P and P.pct and P.pct:GetText()
        if not (type(text) == "string" and text:find("%d")) then Problem("PRG", "page", "no number shown") end
    end)
    ns.UI:ShowTab("sets")
    if run.mode == "full" then return Later(1, OpenGuide) end
    Finish()
end

OpenProgress = function()
    local UI = ns.UI
    if not (UI and UI.ShowTab and UI.tabByKey and UI.tabByKey.progress) then
        Skip("progress tab", "(missing)")
        if run.mode == "full" then return OpenGuide() end
        return Finish()
    end
    UI:ShowTab("progress")
    Later(2, StepProgress)
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
    -- The tab the user had open.
    if s.tab and UI and UI.ShowTab and UI.tab ~= s.tab then Try("tab", UI.ShowTab, UI, s.tab) end
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
    Guard("alts", CheckAlts)
    Guard("progress", CheckProgress)
    Guard("data", CheckData)
    Guard("places", CheckPlaces)
    Guard("hooks", CheckHooks)
    Guard("search", CheckSearch)
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
        -- The Sets tab first (the main parts live there); the user's tab comes back at the end.
        if UI.ShowTab and UI.tab and UI.tab ~= "sets" then
            run.state.tab = UI.tab
            UI:ShowTab("sets")
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
