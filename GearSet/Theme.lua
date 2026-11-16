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
}

Theme.art = {
    rowHighlight = { atlas = "PetList-ButtonHighlight", file = "Interface\\QuestFrame\\UI-QuestTitleHighlight" },
    rowSelect    = { atlas = "PetList-ButtonSelect",    file = "Interface\\QuestFrame\\UI-QuestTitleHighlight" },
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

Theme.colors = {
    have     = Color("GREEN_FONT_COLOR", 0.1, 1, 0.1),
    look     = Color("LIGHTBLUE_FONT_COLOR", 0.53, 0.67, 1),
    need     = Color("RED_FONT_COLOR", 1, 0.1, 0.1),
    partial  = Color("NORMAL_FONT_COLOR", 1, 0.82, 0),
    none     = Color("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),
    text     = Color("HIGHLIGHT_FONT_COLOR", 1, 1, 1),
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
