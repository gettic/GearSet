-- Gear Set: every art, font, colour and template choice in one place,
-- so a theme can swap them later. Only Blizzard's own art, referenced by name.
local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- Templates: first one that exists on this client wins.
Theme.templates = {
    window    = { "ButtonFrameTemplate", "BasicFrameTemplateWithInset" },
    inset     = { "InsetFrameTemplate" },
    search    = { "SearchBoxTemplate", "InputBoxTemplate" },
    filter    = { "WowStyle1FilterDropdownTemplate", "WowStyle1DropdownTemplate" },
    button    = { "UIPanelButtonTemplate" },
    check     = { "UICheckButtonTemplate" },
    scrollBox = { "WowScrollBoxList" },
    scrollBar = { "MinimalScrollBar" },
    -- Guide page: scrolling text (modern template, then the classic one; plain ScrollFrame + wheel if neither).
    scrollFrame = { "ScrollFrameTemplate", "UIPanelScrollFrameTemplate" },
}

Theme.art = {
    -- Piece rows (36 px, pet-list style). rowHighlight/rowSelect are the old names, same tables.
    rowHover     = { atlas = "PetList-ButtonHighlight", file = "Interface\\QuestFrame\\UI-QuestTitleHighlight", blend = "ADD" },
    rowSelected  = { atlas = "PetList-ButtonSelect",    file = "Interface\\QuestFrame\\UI-QuestTitleHighlight" },
    -- Set list rows (22 px text rows): Settings-list bars, else the pet-list art, else the quest file.
    listHover    = { atlases = { "Options_List_Hover", "PetList-ButtonHighlight" }, file = "Interface\\QuestFrame\\UI-QuestTitleHighlight", blend = "ADD" },
    listSelected = { atlases = { "Options_List_Active", "PetList-ButtonSelect" },   file = "Interface\\QuestFrame\\UI-QuestTitleHighlight" },
    -- Quality frame over piece icons (Blizzard's ItemButton IconBorder art), tinted by quality.
    iconBorder   = { file = "Interface\\Common\\WhiteIconFrame" },
    iconCrop     = { 0.07, 0.93, 0.07, 0.93 },          -- cuts the baked grey edge off icons
    -- Previous/next set buttons (spellbook page-turn art); PieceList shows "<" / ">" if missing.
    arrows = {
        prev = {
            up        = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
            down      = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
            disabled  = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled",
            highlight = "Interface\\Buttons\\UI-Common-MouseHilight",
        },
        next = {
            up        = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
            down      = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
            disabled  = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled",
            highlight = "Interface\\Buttons\\UI-Common-MouseHilight",
        },
    },
    modelBgAtlas = "dressingroom-background-%s",       -- %s = class file name, lower case
    modelBgColor = { 0.05, 0.05, 0.06, 1 },
    -- Minimap button icon: first file that loads. Transmogrifier = the transmog symbol
    -- (minimap tracking texture, patch 7.2+, own transparent edges, shown uncropped);
    -- then INV_Chest_Plate16 (132751, plate chest) and the question mark (134400).
    minimapIcon  = { "Interface\\Minimap\\Tracking\\Transmogrifier", "Interface\\Icons\\INV_Chest_Plate16", "Interface\\Icons\\INV_Misc_QuestionMark" },
    minimapButton = {
        border     = "Interface\\Minimap\\MiniMap-TrackingBorder",
        background = "Interface\\Minimap\\UI-Minimap-Background",
        highlight  = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
    },
    -- Piece row open/closed marker (Blizzard's +/- buttons); text "+"/"-" if missing.
    expand = {
        plus  = "Interface\\Buttons\\UI-PlusButton-Up",
        minus = "Interface\\Buttons\\UI-MinusButton-Up",
        size  = 14,
    },
    detailBand = { 0, 0, 0, 0.35 },                     -- (old open-row band; kept for themes)
    -- Piece rows: arrow at the right end ("opens a page"); ">" text if missing.
    rowArrow = { file = "Interface\\ChatFrame\\ChatFrameExpandArrow", size = 12 },
    -- Guide page: line under the header, fold-out +/- uses `expand` above.
    guideDivider = { 1, 1, 1, 0.15 },
    guideIcon = 40,                                      -- item icon size on the guide page
    -- Faction mark on PvP / Arathi Basin set rows: the mount journal's faction atlases
    -- (Blizzard_MountCollection MOUNT_FACTION_TEXTURES), else the classic battle standard icons.
    faction = {
        A = { atlas = "MountJournalIcons-Alliance", file = "Interface\\Icons\\INV_BannerPVP_02" },
        H = { atlas = "MountJournalIcons-Horde",    file = "Interface\\Icons\\INV_BannerPVP_01" },
        size = 14,
    },
}
Theme.art.rowHighlight = Theme.art.rowHover
Theme.art.rowSelect    = Theme.art.rowSelected

Theme.sizes = {
    check = 24,   -- every check box
}

Theme.fonts = {
    header   = "GameFontNormalLarge",
    normal   = "GameFontNormal",
    text     = "GameFontHighlight",
    small    = "GameFontHighlightSmall",
    disabled = "GameFontDisableSmall",
}

local function Color(global, r, g, b)
    return _G[global] or CreateColor(r, g, b, 1)
end

-- Missing pieces are grey, like Blizzard's collections (red would read as "can't use").
Theme.colors = {
    have      = Color("GREEN_FONT_COLOR", 0.1, 1, 0.1),
    look      = Color("LIGHTBLUE_FONT_COLOR", 0.53, 0.67, 1),
    need      = Color("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),
    partial   = Color("NORMAL_FONT_COLOR", 1, 0.82, 0),
    none      = Color("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),
    text      = Color("HIGHLIGHT_FONT_COLOR", 1, 1, 1),
    title     = Color("HIGHLIGHT_FONT_COLOR", 1, 1, 1),          -- tooltip titles
    armorLine = Color("NORMAL_FONT_COLOR", 1, 0.82, 0),          -- armor type in tooltips
    subtle    = Color("LIGHTGRAY_FONT_COLOR", 0.8, 0.8, 0.8),    -- secondary lines
    loading   = Color("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),         -- "Loading..."
    hint      = Color("GREEN_FONT_COLOR", 0.1, 1, 0.1),          -- "Click: ..." lines
    detail    = Color("LIGHTGRAY_FONT_COLOR", 0.8, 0.8, 0.8),    -- source lines
    link      = Color("LINK_FONT_COLOR", 0.4, 0.73, 1),          -- "Report a mistake"
    linkHover = Color("HIGHLIGHT_FONT_COLOR", 1, 1, 1),
    removed   = Color("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),         -- names of sets removed from the game
    bonusOn   = Color("GREEN_FONT_COLOR", 0.1, 1, 0.1),          -- set bonus in effect / enough pieces
    bonusOff  = Color("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),         -- set bonus not reached
    -- Guide page
    guideHead  = Color("NORMAL_FONT_COLOR", 1, 0.82, 0),         -- section headings (gold)
    guideSub   = Color("HIGHLIGHT_FONT_COLOR", 1, 1, 1),         -- "Boss Drop: Onyxia"
    guideLabel = Color("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),        -- "Where", "Level" ...
    guideText  = Color("LIGHTGRAY_FONT_COLOR", 0.8, 0.8, 0.8),   -- values and paragraphs
    guideHere  = Color("GREEN_FONT_COLOR", 0.1, 1, 0.1),         -- the chain step for this piece
}

-- Colour per piece state.
Theme.stateColor = {
    equipped = Theme.colors.have,
    bags     = Theme.colors.have,
    bank     = Theme.colors.have,
    look     = Theme.colors.look,
    need     = Theme.colors.need,
}

function Theme.TemplateExists(name)
    if not name then return false end
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        return C_XMLUtil.GetTemplateInfo(name) ~= nil
    end
    return true
end

-- Name of the first template in Theme.templates[key] that exists (or nil).
function Theme.Template(key)
    for _, name in ipairs(Theme.templates[key] or {}) do
        if Theme.TemplateExists(name) then return name end
    end
end

-- CreateFrame with the themed template; falls back to no template.
function Theme.CreateFrame(frameType, name, parent, key)
    local tmpl = key and Theme.Template(key)
    local ok, frame = pcall(CreateFrame, frameType, name, parent, tmpl)
    if ok and frame then return frame, tmpl end
    local ok2, plain = pcall(CreateFrame, frameType, name, parent)
    if ok2 then return plain, nil end
    return nil, nil  -- frame type unknown on this client
end

function Theme.AtlasExists(atlas)
    return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- Use the atlas if the client has it, otherwise the fallback file (never a green box).
function Theme.SetAtlasOr(tex, atlas, file)
    if Theme.AtlasExists(atlas) then
        tex:SetAtlas(atlas)
        return true
    end
    if file then tex:SetTexture(file) end
    return false
end

-- Apply a Theme.art entry: first atlas the client has ({atlas=} or {atlases={...}}),
-- else its file; then its blend mode. Returns the atlas used (nil = file or nothing).
function Theme.SetArt(tex, entry)
    if not entry then return nil end
    local used
    for _, atlas in ipairs(entry.atlases or { entry.atlas }) do
        if Theme.AtlasExists(atlas) then
            tex:SetAtlas(atlas)
            used = atlas
            break
        end
    end
    if not used and entry.file then tex:SetTexture(entry.file) end
    if entry.blend and tex.SetBlendMode then tex:SetBlendMode(entry.blend) end
    return used
end

-- One colour rule for "have x / y" everywhere: complete green, some gold, none grey.
function Theme.CountColorObj(have, total)
    if total and total > 0 and have >= total then return Theme.colors.have end
    if have and have > 0 then return Theme.colors.partial end
    return Theme.colors.none
end

function Theme.CountColor(have, total)
    return Theme.CountColorObj(have, total):GetRGB()
end

-- Green instruction line ("Click: ...") like Blizzard's tooltips.
function Theme.AddHint(tooltip, text)
    if not (tooltip and text) then return end
    if type(GameTooltip_AddInstructionLine) == "function" then
        GameTooltip_AddInstructionLine(tooltip, text, true)
    else
        local r, g, b = Theme.colors.hint:GetRGB()
        tooltip:AddLine(text, r, g, b, true)
    end
end

-- Set a texture file; false if this client doesn't have it (SetTexture may return
-- true anyway, so the loaded file ID is checked too; 0/nil = missing).
function Theme.TryTexture(tex, file)
    if not file or tex:SetTexture(file) == false then return false end
    if tex.GetTextureFileID then
        local id = tex:GetTextureFileID()
        if id == nil or id == 0 then return false end
    end
    return true
end

-- Background behind the character model: class art if the client has it.
function Theme.SetModelBackground(tex)
    local _, classFile = UnitClass("player")
    local atlas = classFile and Theme.art.modelBgAtlas:format(classFile:lower())
    if not Theme.AtlasExists(atlas) then
        tex:SetColorTexture(unpack(Theme.art.modelBgColor))
        return
    end
    tex:SetAtlas(atlas)
end

function Theme.Font(fs, key)
    fs:SetFontObject(Theme.fonts[key] or Theme.fonts.text)
end

function Theme.ClassColor(classFile)
    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return c end
    end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] or Theme.colors.text
end
