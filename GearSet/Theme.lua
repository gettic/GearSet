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
    -- First-time help note boxes (help-tip glow box, else a tooltip box, else a dark box).
    -- The "?" button is our own plain button with Blizzard's art (art.helpIcon): the
    -- MainHelpPlateButton template hides itself on WoW Forever.
    helpNote   = { "GlowBoxTemplate", "TooltipBackdropTemplate" },
    -- beta.8: bottom tabs (Sets / Progress; plain buttons if missing) and the Progress page's
    -- "This character / Whole account" choice (a plain button that switches if missing).
    tab        = { "PanelTabButtonTemplate" },
    dropdown   = { "WowStyle1DropdownTemplate" },
    -- ui-review-3: "Sets complete" count box under the title bar (the journals' count box,
    -- CollectionsCountTemplate inherits it; Mainline UIPanelTemplates.xml); a dark box if missing.
    countBox   = { "InsetFrameTemplate3" },
    -- ui-review-3: Progress bars (Forever's Skills / Reputation bar; our StatusBar if missing),
    -- the guide's copy view (bordered multi-line box; plain ScrollFrame + EditBox if missing)
    -- and the first-time help's arrow at the gear (same art by file, else the gold line).
    progressBar = { "ColoredProgressBarTemplate" },
    copyBox     = { "InputScrollFrameTemplate" },
    helpArrow   = { "GlowBoxArrowTemplate" },
    -- Inspect strip under Blizzard's inspect window: a tooltip box (colours.inspectBg box if missing).
    inspectStrip = { "TooltipBackdropTemplate" },
    -- 1.1 beta.1 dungeon checklist: X button (Blizzard's close button; a plain "x" if missing).
    trackerClose = { "UIPanelCloseButtonNoScripts", "UIPanelCloseButton" },
}

Theme.art = {
    -- Piece rows (36 px, pet-list style).
    rowHover     = { atlas = "PetList-ButtonHighlight", file = "Interface\\QuestFrame\\UI-QuestTitleHighlight", blend = "ADD" },
    rowSelected  = { atlas = "PetList-ButtonSelect",    file = "Interface\\QuestFrame\\UI-QuestTitleHighlight" },
    -- ui-review-3: bar behind each piece row (Mount/Pet journal and Wardrobe set rows);
    -- a faint colour band if the atlas is missing (PieceList BuildRow).
    rowBackground = { atlas = "PetList-ButtonBackground", color = { 1, 1, 1, 0.06 } },
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
    -- Piece rows: arrow at the right end ("opens a page"); ">" text if missing.
    rowArrow = { file = "Interface\\ChatFrame\\ChatFrameExpandArrow", size = 12 },
    -- Guide page: line under the header and under each heading (Settings divider atlas,
    -- else a 1 px line in `color`); fold-out +/- uses `expand` above.
    guideDivider = { atlas = "Options_HorizontalDivider", color = { 1, 1, 1, 0.15 } },
    guideIcon = 40,                                      -- item icon size on the guide page
    -- Faction mark on PvP / Arathi Basin set rows: the mount journal's faction atlases
    -- (Blizzard_MountCollection MOUNT_FACTION_TEXTURES), else the classic battle standard icons.
    faction = {
        A = { atlas = "MountJournalIcons-Alliance", file = "Interface\\Icons\\INV_BannerPVP_02" },
        H = { atlas = "MountJournalIcons-Horde",    file = "Interface\\Icons\\INV_BannerPVP_01" },
        size = 14,
    },
    -- Gear button left of the window's close button (opens the settings).
    settingsIcon = { atlas = "GM-icon-settings", file = "Interface\\Buttons\\UI-OptionsButton", size = 20 },
    -- Help button in the title bar left of the gear: the art of Blizzard's MainHelpPlateButton
    -- by path (64 px layout: "i" 46 px centred, ring 64 px at +12/-13, highlight 46 px at
    -- -1/+1), scaled so the 64 px box is `screen` px in the window.
    -- Main.lua uses a "?" text link if the "i" doesn't load.
    helpIcon = {
        icon      = "Interface\\common\\help-i",
        ring      = "Interface\\Minimap\\MiniMap-TrackingBorder",
        highlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
        size = 64, iconSize = 46, ringX = 12, ringY = -13, screen = 24,
    },
    -- First-time help: line from the "4. Settings" note up to the gear button.
    helpLineWidth = 2,
    -- First-time help: arrow on note 4 pointing up at the gear (GlowBoxArrowTemplate's down
    -- arrow turned up with HelpPlateArrowUp's coords; without the template the same file is
    -- drawn by hand). Coords = left, right, top, bottom.
    helpArrow = { file = "Interface\\TalentFrame\\TalentFrame-Parts",
        up     = { 0.78515625, 0.99218750, 0.58789063, 0.54687500 },
        glowUp = { 0.40625000, 0.66015625, 0.82812500, 0.77343750 },
        w = 53, h = 21, glowW = 65, glowH = 28, glowAlpha = 0.5 },
    -- beta.8 tracking star on set and piece rows: the auction house / pet journal favourite
    -- star, else the raid target star icon.
    star = { atlases = { "auctionhouse-icon-favorite", "PetJournal-FavoritesIcon" },
        file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", size = 14,
        -- 1.1 beta.4 Plan pin "off": the AH's own off star (Blizzard_AuctionHouseSharedTemplates.lua);
        -- missing -> the star above, dimmed (`offAlpha`).
        off = "auctionhouse-icon-favorite-off", offAlpha = 0.35 },
    -- Progress page bars (ui-review-3): ColoredProgressBarTemplate with its white fill tinted
    -- in Theme.CountColor * tint (darker, so the white count stays readable), the darker
    -- green atlas when complete. Without the template: our StatusBar with `file` on a dark
    -- backing (`bg`) with a 1 px darker edge (`edge`), `height` px tall.
    progressBar = { atlas = "common-stat-bar-white", complete = "common-stat-bar-green",
        track = "common-stat-bar-BG", tint = 0.75, barHeight = 24,
        file = "Interface\\TargetingFrame\\UI-StatusBar",
        bg = { 0, 0, 0, 0.45 }, edge = { 0, 0, 0, 0.9 }, height = 14 },
    -- beta.9 guide Way button: the game's own map pin (Waypoint-MapPin-*), hover = its highlight
    -- (ADD). No atlas on this client: the button shows the word L.WAY_FALLBACK ("Way") in link colours.
    -- 1.1 beta.6 rep / chain tracker (Steps.lua): a small StatusBar in the faction's own colour
    -- (FACTION_BAR_COLORS[reaction], read via _G; missing -> colors.repNeed / repReady) on a dark backing.
    -- ui-b6 #5: the fill is Blizzard's own reputation bar art (ReputationFrame.xml), else UI-StatusBar,
    -- else a plain colour. Greyed (desaturated, `greyAlpha`) on "not out yet" rows.
    repBar = { file = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
        fallback = "Interface\\TargetingFrame\\UI-StatusBar", bg = { 0, 0, 0, 0.5 }, edge = { 0, 0, 0, 0.9 }, greyAlpha = 0.6 },
    wayPin = { atlas = "Waypoint-MapPin-Untracked", hover = "Waypoint-MapPin-Highlight",
        text = (ns.L and ns.L.WAY_FALLBACK) or "Way" },   -- the word when the atlas is missing (as on the guide page)
    -- 1.1 beta.1 dungeon checklist (Objective Tracker look). The tracker's own header atlas
    -- (UI-QuestTracker-Header) is missing on WoW Forever (probe), so the line under the title is
    -- the Settings divider, else a 1 px gold line. Tick on got pieces: the checkmark atlas, else
    -- the ready-check tick file. Loot-roll mark: the same star as tracking, a bit bigger.
    -- ui-b1 job A: the Objective Tracker's own header band (Forever ObjectiveTrackerModule.xml:22 /
    -- ObjectiveTrackerContainer.xml:22) behind the title; missing -> the Settings divider under it,
    -- tinted gold (`tint`), else a 1 px gold line (`color`).
    trackerHeader = { atlases = { "UI-QuestTracker-Secondary-Objective-Header", "ui-questtracker-primary-objective-header" },
        divider = "Options_HorizontalDivider", tint = { 1, 0.82, 0, 0.6 }, color = { 1, 0.82, 0, 0.5 } },
    -- ui-b1 job A: the Objective Tracker's fold button (ObjectiveTrackerModule.xml:9-11, .lua:795-799),
    -- 16 px with the yellow ADD highlight; missing -> the +/- files with the plus-button highlight file.
    trackerFold = { atlases = { "ui-questtrackerbutton-secondary-collapse", "ui-questtrackerbutton-secondary-expand" },
        collapse = "ui-questtrackerbutton-secondary-collapse", expand = "ui-questtrackerbutton-secondary-expand",
        collapsePressed = "ui-questtrackerbutton-secondary-collapse-pressed",
        expandPressed = "ui-questtrackerbutton-secondary-expand-pressed",
        highlight = "ui-questtrackerbutton-yellow-highlight",
        file = "Interface\\Buttons\\UI-PlusButton-Up", plus = "Interface\\Buttons\\UI-PlusButton-Up",
        minus = "Interface\\Buttons\\UI-MinusButton-Up", hilight = "Interface\\Buttons\\UI-PlusButton-Hilight",
        size = 16, fileSize = 14 },
    tick = { atlas = "common-icon-checkmark", file = "Interface\\RaidFrame\\ReadyCheck-Ready", size = 12,
        fallback = { 0.1, 1, 0.1, 1 } },   -- last-resort colour square when neither loads
    -- 1.1 beta.2 preview bar: hide helm / cloak / weapons on our model. Blizzard's empty
    -- paper-doll slot icons (checked by /gs probe); missing -> the letter on a plain square
    -- (`slotPlain`). Framed with `iconBorder` (tint colors.slotFrame); a hidden slot gets the red X
    -- (`slotOffMark`, falls back to an "x" in colors.slotOffMark). Sizes: sizes.slot.
    -- `slot`: the texture the character frame itself uses (C_PaperDollInfo.GetInventorySlotInfo,
    -- as PaperDollFrame.lua does) is tried first; then `file`. WoW Forever has no
    -- UI-PaperDoll-Slot-Back (selftest 1.1 beta.2), so the cloak falls back to the chest icon
    -- (the classic character frame shows the back slot with the chest icon too).
    slotHead   = { slot = "HEADSLOT", file = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head", letter = "H" },
    slotBack   = { slot = "BACKSLOT", file = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest", letter = "C" },
    slotWeapon = { slot = "MAINHANDSLOT", file = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand", letter = "W" },
    slotPlain  = { color = { 0.2, 0.2, 0.2, 1 } },
    slotHilight = { file = "Interface\\Buttons\\ButtonHilight-Square", blend = "ADD" },
    slotOffMark = { atlas = "common-icon-redx", text = "x" },
    lootStar = { atlases = { "auctionhouse-icon-favorite", "PetJournal-FavoritesIcon" },
        file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", size = 18 },
    -- 1.1 beta.4 Plan tab: lock on a saved raid (quest-sharing padlock, else the LFG lock file,
    -- else the word); key icon = the key item's own icon, else this file; LFG button = the chat
    -- bubble, else the word "LFG". Reused: expand, star, tick, wayPin, rowBackground, guideDivider.
    lock = { atlas = "QuestSharing-Padlock", file = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK", text = "locked", size = 14 },
    key  = { file = "Interface\\Icons\\INV_Misc_Key_03", size = 16 },
    lfg  = { file = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", pushed = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Down",
        highlight = "Interface\\Buttons\\UI-Common-MouseHilight", text = "LFG", size = 16 },   -- FloatingChatFrame.xml chat button
    -- small-button hover when an entry has no own hover atlas / highlight file
    smallHover = { file = "Interface\\Buttons\\UI-Common-MouseHilight", blend = "ADD" },
}

Theme.sizes = {
    check = 24,        -- every check box
    -- Bottom tabs hang from under the window's bottom border like CharacterFrame's
    -- (TOPLEFT on the window's BOTTOMLEFT 11, +2; the tab's level is under the border's, so
    -- the border draws over its top 2 px); tab 32 px - 2 = how far they hang below
    -- (FitToScreen, clamp). tabGap = px between tabs (CharacterFrame: 1).
    tabOffsetY = 2,
    tabOverhang = 30,
    tabGap = 1,
    progressRow = 26,  -- one bar row on the Progress page (the template bar is 24 px)
    way = 14,          -- guide page Way button (map pin), at the right edge of its row
    wayGap = 4,        -- px between a row's text and the Way button column
    -- Inspect strip: inset from the inspect window's sides, height, gap under it, text padding.
    inspectStrip = { inset = 4, height = 24, gap = -2, pad = 10 },
    -- List rows: piece rows (pet-list style) with a gap between them; set list text rows and
    -- the fixed width of their "have/total" count (so the faction icons line up).
    pieceRow = 36,
    pieceRowGap = 2,
    setRow = 22,
    setCount = 32,
    -- Minimap button (classic LibDBIcon layout): button, ring (border) and background circle;
    -- icon size for Interface\Icons files (cropped) and for whole textures; offsets from TOPLEFT.
    minimapButton = { button = 31, border = 53, background = 20, iconCropped = 17, iconWhole = 20,
        x = 7, y = -5, croppedY = -6 },
    -- 1.1 beta.1 dungeon checklist: width, header and row heights, rows before "+n more",
    -- inner padding, piece indent, header button size.
    -- ui-b1 job A: width 240, header band 26, close 18, fold 16, title x 7, tick x 4, "for" line +4
    -- (the longest hand-in name, "for Qiraji Bindings of Dominance", needs ~202 of the 206 px left).
    -- 1.1 beta.2 shopping list rows (Progress tab right column, 400 px): row height, columns
    -- (name / have / to get / each), price age in days after which a total turns grey.
    shop = { row = 20, icon = 16, have = 56, get = 50, each = 90, indent = 8, oldDays = 3 },
    -- 1.1 beta.2 hide-slot buttons under the model: icon, button (icon + frame), gap after
    -- Reset, gap between buttons, red X.
    slot = { icon = 18, button = 20, first = 8, gap = 4, mark = 12 },
    -- 1.1 beta.4 Plan tab: run header and line heights, boss / piece indents, icon, columns
    -- (size+level text, key/attunement/lockout status), small buttons (LFG, Way).
    -- ui-b4 #8: every Plan column here (x from the row's left; widths), title / summary offsets, the
    -- shopping list's max width (#5), inline icon size in the status column (#7).
    plan = { head = 26, row = 20, indent = 18, pieceX = 200, icon = 16, button = 16, top = 64,
        foldX = 4, pinX = 22, nameX = 42, nameW = 240, infoX = 290, infoW = 170, countW = 70, gap = 6, rightW = 80,
        titleX = 16, titleY = -12, summaryX = -30, summaryY = -14, sectionH = 24, shopW = 520, line = 12, statusLines = 4, inline = 14,   -- 4: two keys + "not attuned (step n of N)" + lockout (beta.6)
        repBarW = 100, repBarH = 10, stepSlot = 16, locksH = 16 },   -- locksH: the list moves up by this without a lockouts line   -- beta.6 rep rows: the bar in the info column; step mark slot
    repBar = { w = 100, h = 10 },      -- beta.6 guide page rep row: the bar on its own line under the text (ui-b6 #6)
    tracker = { width = 240, head = 26, row = 14, maxRows = 12, pad = 6, indent = 18, button = 18, fold = 16,
        titleX = 7, tickX = 4, viaIndent = 4, countGap = 4 },
}

Theme.fonts = {
    header   = "GameFontNormalLarge",
    normal   = "GameFontNormal",
    text     = "GameFontHighlight",
    small    = "GameFontHighlightSmall",
    disabled = "GameFontDisableSmall",
    countLabel = "GameFontNormalSmall",     -- "Sets complete:" (gold)
    countValue = "GameFontHighlightSmall",  -- "12 / 186" (white)
    -- Guide page section headings (14 px gold); the normal font if the client lacks it.
    guideHead = _G.GameFontNormalMed2 and "GameFontNormalMed2" or "GameFontNormal",
    -- 1.1 beta.1 dungeon checklist: the Objective Tracker's fonts when the client has them.
    trackerHead = _G.ObjectiveTrackerHeaderFont and "ObjectiveTrackerHeaderFont" or "GameFontNormal",
    trackerLine = _G.ObjectiveTrackerLineFont and "ObjectiveTrackerLineFont" or "GameFontHighlightSmall",
}

local function Color(global, r, g, b)
    return _G[global] or CreateColor(r, g, b, 1)
end

-- Palette: the few base colours (Blizzard's font colours, own values as fallback). Every
-- role in Theme.colors below points at one of these, so a theme changes a colour here once.
Theme.palette = {
    gold      = Color("NORMAL_FONT_COLOR", 1, 0.82, 0),
    white     = Color("HIGHLIGHT_FONT_COLOR", 1, 1, 1),
    grey      = Color("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),
    lightGrey = Color("LIGHTGRAY_FONT_COLOR", 0.8, 0.8, 0.8),
    green     = Color("GREEN_FONT_COLOR", 0.1, 1, 0.1),
    orange    = Color("ORANGE_FONT_COLOR", 1, 0.5, 0.25),
    blue      = Color("LIGHTBLUE_FONT_COLOR", 0.53, 0.67, 1),
    link      = Color("LINK_FONT_COLOR", 0.4, 0.73, 1),
}
local P = Theme.palette

-- Colour roles (what each colour is for). Missing pieces are grey, like Blizzard's
-- collections (red would read as "can't use").
Theme.colors = {
    -- beta.9 search results (Search.lua / SetList; part C): group header, grey "(place)", "n more" rows
    searchHead = P.gold,
    searchSub  = P.grey,
    searchMore = P.link,
    have      = P.green,
    look      = P.blue,
    need      = P.grey,
    partial   = P.gold,
    none      = P.grey,
    text      = P.white,
    title     = P.white,                -- tooltip titles
    armorLine = P.gold,                 -- armor type in tooltips
    subtle    = P.lightGrey,            -- secondary lines
    loading   = P.grey,                 -- "Loading..."
    hint      = P.green,                -- "Click: ..." lines
    link      = P.link,                 -- link buttons ("Copy name", "Wiki link")
    linkHover = P.white,
    removed   = P.grey,                 -- names of sets removed from the game
    removedSelected = P.lightGrey,      -- removed set's name on the selected bar
    menuChoice = P.grey,                -- current choice after a filter-menu label
    bonusTitle = P.gold,                -- "Set name (2/8)" atop the set bonus tooltip
    bonusOn   = P.green,                -- set bonus in effect / enough pieces
    bonusOff  = P.grey,                 -- set bonus not reached
    -- Guide page
    guideHead  = P.gold,                -- section headings (gold)
    guideSub   = P.white,               -- "Boss Drop: Onyxia"
    guideLabel = P.gold,                -- "Where", "Level" ... (gold, like PaperDoll labels)
    guideText  = P.white,               -- values and paragraphs
    guideHere  = P.green,               -- the chain step for this piece
    guideNote  = P.lightGrey,           -- grey line under a bullet ("Drops from: ...")
    guideHint  = P.gold,                -- copy view: "Text is selected ..."
    copyHighlight = CreateColor(0.3, 0.55, 1, 0.5),              -- copy view: selected text (GetRGBA)
    -- WoW Forever flags (guide lines, list rows, tooltips)
    flagClassic = P.lightGrey,          -- "Not confirmed on WoW Forever yet"
    flagChecked = P.green,              -- "Checked on WoW Forever"
    flagLater   = P.orange,             -- "Not yet released on WoW Forever"
    later       = P.grey,               -- names/counts of sets and pieces not out yet
    laterSelected = P.lightGrey,        -- a not-out-yet set's name on the selected bar
    -- Hidden sets (listed only with "Show hidden sets")
    hidden         = P.grey,
    hiddenSelected = P.lightGrey,
    -- Stats tooltip: can your class wear it
    fitYes = P.green,
    fitNo  = P.grey,
    -- First-time help
    helpDim    = CreateColor(0, 0, 0, 0.6),                       -- over the three panels (GetRGBA)
    helpHead   = P.gold,                -- note headings (gold)
    helpText   = P.white,               -- note text (white)
    helpLine   = P.gold,                -- line to the gear button
    helpNoteBg = CreateColor(0.05, 0.05, 0.05, 0.92),             -- note box when no template exists
    -- Settings panel: grey data line
    settingsData = P.grey,
    -- Item tooltip line / inspect line / broker (review-ui 8, review 3): "Gear Set:" gold, set name
    -- white, count in CountColor, "have" and "Needed by" grey, "- you need this" white
    tipLabel = P.gold,
    tipName  = P.white,
    tipNote  = P.grey,
    tipNeed  = P.white,                 -- "- you need this" (white, stands out from grey set bonuses)
    inspectBg = CreateColor(0, 0, 0, 0.6),                        -- inspect strip without its template (GetRGBA)
    -- beta.8 Progress page / tracking / money
    progressHead = P.gold,              -- section headings (gold)
    progressNote = P.grey,              -- dates, "Not counted: ..."
    money        = P.lightGrey,         -- "12g" money text (was `gold`)
    countBoxBg   = CreateColor(0, 0, 0, 0.5),                    -- count box when InsetFrameTemplate3 is missing (GetRGBA)
    -- 1.1 beta.1 dungeon checklist
    trackerBg   = CreateColor(0, 0, 0, 0.45),                     -- backing behind the rows (GetRGBA)
    trackerHead = P.gold,               -- "Gear Set - Scholomance"
    trackerBoss = P.gold,               -- boss rows
    trackerNeed = P.white,              -- pieces you still need
    trackerGot  = P.green,              -- pieces you got in this run (ticked)
    trackerSkip = P.grey,               -- "not out yet", "for ...", alt names, "+n more"
    trackerCount = P.white,             -- "3 left" in the header
    -- 1.1 beta.2 shopping list (Progress tab) and price lines
    shopHead  = P.gold,                 -- "To craft", "Mats"
    shopText  = P.white,                -- mat names
    shopMissing = P.orange,             -- "not known" (the recipe you still have to get)
    shopDone  = P.green,                -- "known", enough of a mat
    shopWhere = P.grey,                 -- "needs a crafter", "?", column labels, notes
    priceOld  = P.grey,                 -- a total whose price is older than 3 days
    levelHigh = P.orange,               -- "Requires level 60" when more than 5 levels above you
    slotOff   = CreateColor(0.5, 0.5, 0.5, 1),   -- hidden-slot button icon tint (GetRGBA)
    slotFrame = P.grey,                 -- iconBorder tint of the slot buttons
    slotOffMark = P.orange,             -- the "x" when the red X atlas is missing
    -- 1.1 beta.4 Plan tab
    planHead    = P.gold,               -- run names, "What to run"
    planBoss    = P.lightGrey,          -- boss names
    planLocked  = P.grey,               -- a run whose bosses are all dead this lockout
    planNote    = P.grey,               -- size / level, notes, alt names
    planHave    = P.green,              -- key held, attuned
    planMissing = P.orange,             -- key missing, not attuned
    handReady   = P.green,              -- "Ready to hand in"
    -- 1.1 beta.6 rep / chain tracker
    repNeed     = P.orange,             -- standing below what a piece needs
    repReady    = P.green,              -- standing high enough
    stepDone    = P.lightGrey,          -- chain step done (grey + tick, like the objective tracker; ui-b6 #2)
    chainBar    = P.gold,               -- chain progress bar fill (done: planHave)
    stepNext    = P.gold,               -- the next step to do
    stepOpen    = P.white,              -- steps after it
}

-- Effort word colours (Data:GetEffort level): 0 Done grey, 1 Low green, 2 Medium gold,
-- 3 High orange, 4 Very high red.
-- Blizzard's quest-difficulty ("con") colours when the client has them, else these values.
local CON_NAMES = { [0] = "trivial", "standard", "difficult", "verydifficult", "impossible" }
local EFFORT_FALLBACK = {
    [0] = { 0.5, 0.5, 0.5 }, { 0.25, 0.75, 0.25 }, { 1, 1, 0 }, { 1, 0.5, 0.25 }, { 1, 0.1, 0.1 },
}
Theme.effortColor = {}
for level = 0, 4 do
    local con = type(QuestDifficultyColors) == "table" and QuestDifficultyColors[CON_NAMES[level]]
    local f = EFFORT_FALLBACK[level]
    if type(con) == "table" and tonumber(con.r) and tonumber(con.g) and tonumber(con.b) then
        Theme.effortColor[level] = CreateColor(con.r, con.g, con.b, 1)
    else
        Theme.effortColor[level] = CreateColor(f[1], f[2], f[3], 1)
    end
end

-- Colour per piece state.
Theme.stateColor = {
    equipped = Theme.colors.have,
    bags     = Theme.colors.have,
    bank     = Theme.colors.have,
    mail     = Theme.colors.have,      -- beta.7 (Alts.lua)
    keyring  = Theme.colors.have,
    account  = Theme.colors.have,
    look     = Theme.colors.look,
    need     = Theme.colors.need,
}

-- Colour per WoW Forever flag line (Data's guide blocks k = "flag").
Theme.flagColor = {
    classic  = Theme.colors.flagClassic,
    checked  = Theme.colors.flagChecked,
    later    = Theme.colors.flagLater,
    srcLater = Theme.colors.flagLater,
    seen     = Theme.colors.flagChecked,   -- 1.1 beta.4 "Out now (seen in game)"
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

-- A divider line: the entry's atlas at its own height if the client has it, else a
-- 1 px line in entry.color. Returns the height used.
function Theme.SetDivider(tex, entry)
    entry = entry or Theme.art.guideDivider
    if Theme.AtlasExists(entry.atlas) then
        tex:SetAtlas(entry.atlas)
        local info = C_Texture.GetAtlasInfo(entry.atlas)
        local h = math.max(1, math.min(4, (info and info.height) or 1))
        tex:SetHeight(h)
        return h
    end
    tex:SetColorTexture(unpack(entry.color or { 1, 1, 1, 0.15 }))
    tex:SetHeight(1)
    return 1
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

-- 1.1 beta.6: "|A:atlas:s:s|a" / "|T file:s|t" for a Theme.art entry (first atlas that exists, else
-- its file), "" when none - for icons inside a line of text (ticks on chain steps, key icons).
-- file: a texture path / fileID used instead of the entry.
function Theme.InlineIcon(entry, size, file)
    size = size or 12
    if file then return ("|T%s:%d|t"):format(tostring(file), size) end
    if type(entry) ~= "table" then return "" end
    for _, a in ipairs(entry.atlases or { entry.atlas }) do
        if Theme.AtlasExists(a) then return ("|A:%s:%d:%d|a"):format(a, size, size) end
    end
    if entry.file then return ("|T%s:%d|t"):format(entry.file, size) end
    return ""
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

-- Paper-doll slot icon: the character frame's own texture for art.slot, else art.file.
-- Returns true when one loaded.
function Theme.SetSlotTexture(tex, art)
    local PD = _G.C_PaperDollInfo
    if art.slot and PD and type(PD.GetInventorySlotInfo) == "function" then
        local ok, _, texture = pcall(PD.GetInventorySlotInfo, art.slot)
        if ok and (type(texture) == "string" or type(texture) == "number") and Theme.TryTexture(tex, texture) then
            return true
        end
    end
    return Theme.TryTexture(tex, art.file)
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
    local name = Theme.fonts[key] or Theme.fonts.text
    if type(name) == "string" and _G[name] == nil then name = Theme.fonts.text end
    fs:SetFontObject(name)
end

function Theme.ClassColor(classFile)
    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return c end
    end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] or Theme.colors.text
end
