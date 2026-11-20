-- Gear Set: core (namespace, saved settings, events, slash commands)
local ADDON, ns = ...

ns.ADDON = ADDON
ns.DB_VERSION = 9

-- All user-facing text in one place (ready for translations later).
ns.L = {
    TITLE = "Gear Set",
    SEARCH = "Search sets",
    FILTER = "Filter",
    CLASS = "Class",
    ARMOR = "Armor type",
    ALL = "All",
    USABLE = "Only my class",
    HIDE_COMPLETE = "Hide complete sets",
    RESET_FILTERS = "Reset filters",
    HAVE_COUNT = "Have %d / %d",
    NO_SET = "Pick a set on the left.",
    NO_SETS = "No sets match. Try other filters or words.",
    LOADING = "Loading...",
    RESET = "Reset view",
    RESET_TIP = "Turn the character back, zoom out and show every piece again.",
    ONLY_SET = "Only the set",
    ONLY_SET_TIP = "Hide your own gear so only the set shows.",
    PIECE_TIP = "Click for a guide on how to get this piece.",
    SHOW_PIECE_TIP = "Show this piece on the character.",
    NO_MODEL_TIP = "This piece doesn't show on the character.",
    -- Source lines (type words come from the game's TRANSMOG_SOURCE_n strings when it has them).
    SRC_BOSS = "Boss Drop",
    SRC_QUEST = "Quest",
    SRC_VENDOR = "Vendor",
    SRC_WORLD = "World Drop",
    SRC_PROFESSION = "Profession",
    SRC_DROP = "Drop",               -- z: trash or several bosses in one place
    SRC_UNKNOWN = "Source unknown",
    STATE_equipped = "Equipped",
    STATE_bags = "In bags",
    STATE_bank = "In bank",
    STATE_look = "Appearance",
    STATE_need = "Need",
    STATE_mail = "In mailbox",
    STATE_keyring = "On keyring",
    STATE_account = "Account bank",
    -- v1.0.1 (F1): a released piece this game client doesn't know (counts in the total, never "have")
    STATE_unknown = "Not in this game version",
    G_STATE_unknown = "Not in this game version yet",
    FLAG_UNKNOWN = "This game version doesn't know this item yet, so it can't be got for now. It still counts in the set's total.",
    UNKNOWN_ITEM = "Item %d",
    UNKNOWN_COUNT = "%d not in this game version",
    -- v1.0.1 (F2): tooltip line on Dungeon Set 1 pieces
    TIP_KEEP_D2 = "Keep it: the Dungeon Set 2 quests take this piece",
    TIP_KEEP_D2_LATER = "Keep it: the Dungeon Set 2 quests take this piece (not out yet)",
    -- v1.0.1 (F5): filter
    HIDE_LATER = "Hide sets not out yet",
    -- 1.1 beta.1: dungeon checklist (UI\Tracker.lua) and loot-roll mark (LootMark.lua)
    TRACKER_TITLE = "Gear Set - %s",
    TRACKER_LEFT = "%d left",
    TRACKER_TRASH = "Other enemies",
    TRACKER_SKIP = "not out yet",
    TRACKER_MORE = "+%d more",
    TRACKER_NONE = "Nothing you need drops here.",
    TRACKER_VIA = "for %s",
    TRACKER_NOT_IN = "The checklist works inside a dungeon or raid.",
    TRACKER_SKIP_HERE = "Don't show in this instance",
    TRACKER_CLOSE_HERE = "Close until I leave",
    TRACKER_COLLAPSE = "Collapse",
    TRACKER_EXPAND = "Expand",
    TRACKER_SETTINGS = "Settings",
    TRACKER_TIP_HINT = "Drag: move. Right-click: options.",
    TRACKER_WING = "Wing: %s",
    TRACKER_ALTS = "Also needed by: %s",
    LOOT_NEED = "Gear Set: you need this",
    LOOT_ALTS = "Gear Set: needed by %s",
    S_DUNGEONS = "Dungeons",
    S_TRACKER = "Open the dungeon checklist by itself",
    S_TRACKER_TIP = "In a dungeon or raid where you still need a set piece, a small list of its bosses and your pieces opens. Also /gs checklist.",
    S_TRACKER_STARTED = "With nothing tracked, use sets I've started",
    S_TRACKER_STARTED_TIP = "When you track no set or piece, the checklist and loot mark use the sets you have some pieces of and your class can wear.",
    S_LOOT_MARK = "Mark set pieces on loot rolls",
    S_LOOT_MARK_TIP = "A small star on the loot roll window when you or one of your other characters needs the item. It never rolls for you.",
    S_SKIPPED_LABEL = "Instances you chose not to show",
    S_SKIPPED = "Show them again (%d)",
    -- 1.1 beta.2: shopping list (Shopping.lua / UI\Progress.lua), prices (AHPrices.lua),
    -- model toggles (UI\Preview.lua), levels (Data / SetList / PieceList), next targets.
    SHOP_HEAD = "Shopping list",
    SHOP_CRAFT = "To craft",
    SHOP_MATS = "Mats",
    SHOP_COL_HAVE = "Have",
    SHOP_COL_GET = "To get",
    SHOP_COL_EACH = "Each",
    SHOP_HAVE_NEED = "%d/%d",
    SHOP_KNOWN = "known",
    SHOP_KNOWN_BY = "known by %s",
    SHOP_NOT_KNOWN = "not known",
    SHOP_CRAFTER = "needs a crafter",
    SHOP_UNKNOWN = "?",
    SHOP_TOTAL = "To buy %s",
    SHOP_TOTAL_MONEY = "about %s",
    SHOP_TOTAL_NONE = "To buy: no price",
    SHOP_SOURCE = "(%s, %s)",
    SHOP_AMOUNTS = "%d mat amounts unknown (?)",
    SHOP_TIP_HAVE = "Have %d: bags %d, bank %d",
    SHOP_TIP_ALT = "%s: %d",
    SHOP_TIP_GET = "Get it: %s",
    SHOP_TIP_PRICE = "Price %s each (%s, %s)",
    SHOP_TIP_RECIPE = "Recipe: %s",
    SHOP_TIP_SKILL = "%s %d",
    SHOP_GET_ah = "auction house",
    SHOP_GET_craft = "%s from %s",
    SHOP_GET_skin = "skinning %s, %s",
    SHOP_GET_drop = "drops from %s, %s",
    SHOP_GET_vendor = "sold by %s, %s",
    PRICE_TODAY = "today",
    PRICE_DAYS = "%d days old",
    PRICE_DAY = "1 day old",
    PRICE_TSM = "TSM market value",
    PRICE_TSM_SHORT = "TSM",
    SHOP_UNPRICED = "%d without a price",
    SHOP_POINTER = "Shopping list: %d mats to get - see the Plan tab",
    SHOP_POINTER_TIP = "Click: open the Plan tab.",
    -- 1.1 beta.4 Plan tab (UI\Plan.lua, Runs.lua, HandIns.lua)
    TAB_PLAN = "Plan",
    PLAN_TITLE = "What to run",
    PLAN_SUMMARY = "%s in %s",
    PLAN_RUN_ONE = "1 run",
    PLAN_RUNS = "%d runs",
    PLAN_RUNS_HEAD = "Runs",
    PLAN_KIND_dungeon = "Dungeon",
    PLAN_KIND_raid = "Raid",
    RUN_NAME_BRS = "Blackrock Spire (Lower or Upper)",
    RUN_NAME_SM = "Scarlet Monastery (any wing)",
    PLAN_LOCKS = "Raid lockouts: %d saved",
    PLAN_LOCKS_NONE = "Raid lockouts: none saved",
    PLAN_EMPTY = "Track a set or a piece (Shift-click it in the list) to plan your runs.",
    PLAN_NONE = "None of the pieces you need drop in a dungeon or raid.",
    PLAN_OTHER = "Not from a run: %d pieces (quests, vendors, crafting). Click a piece for its guide.",
    PLAN_OTHER_HEAD = "Not from a run",      -- beta.6 (ui-b6 #4): section after the runs
    PLAN_OTHER_ROW = "All pieces",           -- its fold row when more than 8 pieces
    PLAN_SRC_VENDOR = "Vendor: %s",          -- "Not from a run" source column / tooltip
    PLAN_SRC_QUEST = "Quest: %s",
    PLAN_SRC_CRAFT = "Crafted: %s",
    PLAN_SRC_TIP = "From: %s",
    PLAN_OTHER_TIP ="Pieces from quests, vendors, crafting or world drops. Click a piece for its guide.",
    PLAN_PIECES = "%d pieces",
    PLAN_PIECE = "1 piece",
    PLAN_SIZE = "%d players",
    PLAN_RAID = "%d-player raid",
    PLAN_LEVEL = "level %s",
    PLAN_TRASH = "Trash",
    PLAN_NEED = "Need",
    PLAN_HANDIN = "Hand-in",
    PLAN_FOR = "for %s",
    PLAN_ALT = "- %s",
    PLAN_PIN_TIP = "Pin this run to the top (this character only).",
    PLAN_FOLD_TIP = "Click: show or hide the bosses.",
    PLAN_LFG_TIP = "Copy a group line to paste into chat yourself.",
    PLAN_TIP_BRING = "Bring: %s",
    PLAN_TIP_GROUP = "Group notes",
    PLAN_TIP_LFG = "Click LFG for a group line to copy.",
    PLAN_TIP_PIECE = "Click: open its guide on the Sets tab.",
    PLAN_HAND_HEAD = "Ready to hand in",
    PLAN_HAND_ROW = "%s, %s - %s",
    KEY_keyring = "%s: keyring",
    KEY_bags = "%s: bags",
    KEY_bank = "%s: bank",
    KEY_MISSING = "%s: missing",
    KEY_PART = "%s (%s)",
    ATT_YES = "attuned",
    ATT_NO = "not attuned",
    LOCK_FREE = "not saved",
    LOCK_SAVED = "saved %d/%d",
    LOCK_DONE = "done this week",
    LOCK_RESET = "resets %s (%s)",
    LOCK_IN_DH = "in %dd %dh",
    LOCK_IN_HM = "in %dh %dm",
    LOCK_IN_M = "in %dm",
    LOCK_IN_LT = "under 1m",
    LOCK_RESET_SHORT = "resets %s",
    -- 1.1 beta.6 rep / chain tracker (Steps.lua, Plan tab, guide page)
    PLAN_REP_HEAD = "Reputation and chains",
    REP_FOLD_TIP = "Click: show or hide the details.",
    REP_UNKNOWN = "not known",
    REP_NOT_MET = "not met yet",
    REP_READY = "%s (ready)",
    REP_NEED = "%s - need %s",
    REP_LATER = "not out yet",
    REP_ALL_READY = "ready",
    REP_NEED_ONE = "need %s for 1 piece",
    REP_NEED_N = "need %s for %d pieces",
    REP_YOU = "You: %s",
    REP_FOR = "Needed for: %s",
    STANDING_1 = "Hated", STANDING_2 = "Hostile", STANDING_3 = "Unfriendly", STANDING_4 = "Neutral",
    STANDING_5 = "Friendly", STANDING_6 = "Honored", STANDING_7 = "Revered", STANDING_8 = "Exalted",
    CHAIN_DONE = "done",
    CHAIN_STEP = "step %d of %d",
    CHAIN_STEPS = "%d steps",
    CHAIN_NEXT = "next: %s",
    CHAIN_NEXT_TAG = "(next)",
    CHAIN_NO_IDS = "Progress not known for this chain yet.",
    ATT_STEP_NEXT = "%s - next: %s",          -- run tooltip: "step 3 of 16 - next: Dragonkin Menace"
    TOKEN_LINE = "Turn-ins in bags: %s",
    TOKEN_SETS = "(%d sets)",
    TOKEN_SET_ONE = "(1 set)",
    BRING_HAVE = "%d/%d in bags",
    LFG_LINE = "LFM %s - need %s",
    LFG_LINE_NONE = "LFM %s",
    LFG_POPUP = "Press Ctrl+C to copy the group line, then paste it into chat yourself.",
    GRP_SIZE = "Up to %d players.",
    GRP_KEY = "One key holder can open the door for the group.",
    GRP_ATT = "Everyone needs the attunement.",
    HAND_LINE_ONE = "1 hand-in ready here: %s.",
    HAND_LINE = "%d hand-ins ready here: %s.",
    HAND_WHO = "%s (%s)",
    HAND_MORE = "+%d more",
    FLAG_SEEN = "Out now (seen in game).",
    S_HANDINS = "Hand-in reminders in chat",
    S_HANDINS_TIP = "When you enter the zone of a quest giver whose reward you still need and your bags hold everything the quest asks for, one line in your chat says so. Only you see it.",
    PRICE_AUCTIONATOR = "Auctionator",
    SLOT_HEAD = "Hide the helm on this model",
    SLOT_BACK = "Hide the cloak on this model",
    SLOT_WEAPONS = "Hide the weapons on this model",
    SLOT_SHOW_HEAD = "Show the helm on this model",
    SLOT_SHOW_BACK = "Show the cloak on this model",
    SLOT_SHOW_WEAPONS = "Show the weapons on this model",
    SLOT_TIP_NOTE = "Only this preview; your character is not changed.",
    LEVEL_RANGE = "Requires level %d-%d",
    LEVEL_ONE = "Requires level %d",
    LEVEL_SHORT = "Level %s",
    MY_LEVEL = "Fits my level (within 5)",
    NEXT_LINE = "Next: %s",
    NEXT_ITEM = "%s (%d left)",
    NEXT_HEAD = "Next:",
    NEXT_LEFT = "%d left",
    S_SHOPPING = "Shopping",
    S_PRICES_LABEL = "Prices from",
    S_PRICES_auto = "Auctionator or TSM",
    S_PRICES_auctionator = "Auctionator",
    S_PRICES_tsm = "TSM",
    S_PRICES_off = "Off",
    S_PRICES_TIP = "Auction prices on the shopping list, read from your price addon. Gear Set never scans the auction house.",
    S_NEXT = "Next targets in the button tooltip",
    S_NEXT_TIP = "The minimap and broker tooltip name the 3 sets closest to done.",
    ALL_CLASSES = "All classes",
    UNKNOWN_SET = "Set %d",
    ANY_CAN_WEAR = "(any class can wear it)",
    -- Removed sets
    SHOW_REMOVED = "Show removed sets",
    REMOVED_TIP = "Removed in patch 1.11. It can't be bought any more.",
    -- Sort menu
    SORT = "Sort",
    SORT_OWNED = "Most owned first",
    SORT_CLOSEST = "Closest to finishing",
    SORT_NAME = "Name",
    -- Content filter (set kinds)
    CONTENT = "Content",
    KIND_D = "Dungeon",
    KIND_R = "Raid",
    KIND_P = "PvP",
    KIND_C = "Crafted",
    KIND_W = "World",
    KIND_F = "WoW Forever",
    MY_FACTION = "Only my faction",
    ALLIANCE = "Alliance",           -- fallbacks; the game's FACTION_ALLIANCE / FACTION_HORDE come first
    HORDE = "Horde",
    -- Filter menu: "Sort: Name", "Class: All" (label, current choice)
    MENU_CHOICE = "%s: %s",
    -- Set bonuses (right panel header)
    BONUSES = "Set bonuses",
    BONUSES_N = "Set bonuses (%d/%d)",       -- bonuses in effect from worn pieces / all
    BONUS_TITLE = "%s (%d/%d)",              -- set name (pieces worn / pieces in the set)
    BONUS_WEARING = "Only pieces you wear count: you wear %d of %d.",
    BONUS_LINE = "(%d) Set: %s",
    BONUS_ACTIVE = "Set: %s",
    BONUS_NONE = "No set bonus.",
    -- One command per line (HandleSlash prints each line on its own).
    HELP = "/gs - open or close the window\n/gs reset - move the window back to the middle\n/gs minimap - show or hide the minimap button\n/gs check - show the data version and test the set list (for bug reports)\n/gs probe - test what this game client supports (for bug reports)\n/gs selftest - the addon checks itself (/gs selftest full also opens a guide page and the help)\n/gs config - open the settings\n/gs checklist - show or hide the dungeon checklist (inside a dungeon or raid)\n/gs plan - open the Plan tab (which runs to do for your pieces)\n/gs forget - forget one of your other characters\n/gs help - show this list and the help on the window",
    POS_RESET = "Window moved back to the middle.",
    MINIMAP_TIP_CLICK = "Click: open or close the window.",
    MINIMAP_TIP_DRAG = "Drag: move this button.",
    MINIMAP_SHOWN = "Minimap button shown.",
    MINIMAP_HIDDEN = "Minimap button hidden. Type /gs minimap to show it again.",
    MINIMAP_TIP_HIDE = "Right-click: hide this button.",
    BIND_TOGGLE = "Open/close Gear Set",
    -- Piece list
    PIECE_TIP_MOD = "Shift-click: track this piece (while typing in chat: link it). Ctrl-click: try it on in the dressing room.",
    COPY = "Copy name",
    COPY_TIP = "Shows the name so you can copy it and look the piece up online.",
    COPY_POPUP = "Press Ctrl+C to copy the name, then search for it online.",
    WIKI_LINK = "Wiki link",
    APPEARANCE_ONLY = "Appearance only",
    APPEARANCE_NOTE = "A collected appearance counts as having the piece.",
    PREV_SET = "Previous set",
    NEXT_SET = "Next set",
    -- Guide page (one piece). Row labels, then headings and lines.
    G_BACK = "Back",                 -- fallback; the game's BACK comes first
    G_BACK_TIP = "Back to the piece list (or press Esc, or right-click the page).",
    G_PIECE_N = "Piece %d of %d",
    G_PREV = "Previous piece",
    G_NEXT = "Next piece",
    G_STATE_equipped = "You have it: equipped",
    G_STATE_bags = "You have it: in your bags",
    G_STATE_bank = "You have it: in your bank",
    G_STATE_look = "You have its appearance",
    G_STATE_need = "You need this piece",
    G_STATE_mail = "You have it: in your mailbox",
    G_STATE_keyring = "You have it: on your keyring",
    G_STATE_account = "You have it: in the account bank",
    G_WIKI_TIP = "Shows a Warcraft Wiki search link for this piece.",
    WIKI_POPUP = "Press Ctrl+C to copy the link, then paste it into your browser.",
    -- beta.9 Way button (Waypoint.lua; the chat lines follow "Gear Set:")
    WAY_POPUP = "Press Ctrl+C to copy the position.",
    WAY_TOMTOM = "TomTom waypoint set: %s",
    WAY_MAP = "map pin set: %s",
    WAY_COPY = "can't set a map pin there - the position is in the copy box: %s",
    WAY_COMBAT = "in combat - the position is in the copy box: %s",
    WAY_TIP_TITLE = "Show the way",
    WAY_TIP_TOMTOM = "Click: sets a TomTom waypoint.",
    WAY_TIP_MAP = "Click: sets a map pin and tracks it. It replaces your own map pin.",
    WAY_TIP_COPY = "Click: shows the position to copy (no map pin can be set there).",
    WAY_TIP_COMBAT = "In combat it only shows the position to copy.",
    WAY_TIP_CLASSIC = "Position from classic, not checked on WoW Forever yet.",
    WAY_ENTRANCE = "(entrance)",
    WAY_AREA = "(roams around here)",
    WAY_ALSO = "Also: %s",
    WAY_FALLBACK = "Way",
    -- beta.9 boss records on the guide page (GuideData boss: wing / n / rare / sum)
    G_INSIDE = "Inside",
    G_BOSS_N = "boss %s of %s",
    G_RARE = "Rare spawn: not always there.",
    G_HOW = "How to get it",
    G_BEFORE = "Before you go",
    G_NEED_TEXT = "To get in you need the %s.",
    G_OTHER_VERSION = "Show the %s version",
    G_RECIPE = "Recipe",
    G_NOT_CRAFTER = "Can't make it yourself?",
    G_BOE_TIP = "It can be traded: buy it on the Auction House, or ask a crafter to make it with your materials.",
    G_TRAINER = "Taught by a trainer.",
    G_NOT_KNOWN = "not known",
    G_HERE = "(this piece's quest)",
    G_INSTANCE = "Instance",
    G_PLACE = "Place",
    G_WHERE = "Where",
    G_CHANCE = "Drop chance",
    G_LEVEL = "Level",
    G_MIN = "start at %s",
    G_GIVER = "Quest giver",
    G_BRING = "You bring",
    G_GOLD = "%s gold",
    G_NEEDS = "Needs",
    G_RANK = "PvP rank %s: %s",
    G_RANK_N = "PvP rank %s",
    G_COST = "Cost",
    G_ALSO = "Reward",
    G_SKILL = "Skill",
    G_SKILL_ORANGE = "orange",
    G_SKILL_YELLOW = "yellow",
    G_SKILL_GREEN = "green",
    G_SKILL_GREY = "grey",
    G_MATS = "Materials",
    G_TOOLS = "Tools",
    G_QUEST = "Quest",
    G_FROM = "Sold by",
    G_DROP = "Dropped by",
    G_NOTE = "Note",
    G_SIZE = "%s players",
    G_LEVEL_N = "level %s",
    -- Guide page: copy view, show on model, step hint, new data rows
    G_COPY_TEXT = "Copy text",
    G_COPY_TIP = "Shows this guide as text you can select and copy.",
    G_COPY_DONE = "Done",
    G_COPY_HINT = "Text is selected - press Ctrl+C to copy. Esc or Done goes back.",
    G_SHOW_MODEL = "Show on model",
    G_NEED_STEP = "Shift-click: the next piece you still need.",
    G_DROPS_FROM = "Drops from: %s",
    G_SPEC_TRAINER = "(trainer: %s)",
    G_TAUGHT_BY = "Taught by",
    G_AMOUNT_UNKNOWN = "%s (amount not known)",
    G_KIND_raid = "raid",
    G_KIND_dungeon = "dungeon",
    G_KIND_zone = "zone",
    G_KIND_city = "city",
    G_KIND_bg = "battleground",
    -- Empty set list (used with :format)
    EMPTY_SEARCH = "Search: \"%s\"",
    EMPTY_FILTERS = "Filters: %s",
    CLEAR_SEARCH = "Clear search",
    CLEAR_ALL = "Clear search and filters",
    -- /gs check
    CHECK_NO_LIST = "The set list is missing. Try reinstalling Gear Set.",
    CHECK_NO_SET = "Set %d: the game doesn't know this set.",
    CHECK_BAD_ENTRY = "Set %d: broken entry.",
    CHECK_NO_ITEM = "Set %d: item %d isn't in the game.",
    CHECK_WRONG_SET = "Set %d: the game puts item %d in set %s.",
    CHECK_NONE = "no set",
    CHECK_SLOW = "%d items didn't load. Try /gs check again.",
    CHECK_DONE = "Check done: %d sets, %d items, %d problems%s.",
    CHECK_FIRST_40 = " (first 40 shown)",
    DATA_VERSION = "Data version %s, last checked %s (WoW Forever %s).",
    DATA_SOURCES = "Data sources: %s.",
    DATA_SOURCES_LIST = "warcraft.wiki.gg (CC BY-SA) and checks in the WoW Forever game",
    DATA_UNKNOWN = "unknown",
    DATA_FLAGS = "Checked on WoW Forever: %d of %d sets, %d sets not out yet; %d of %d sources checked; %d pieces not out yet.",
    DATA_BAD_FLAGS = "%d source flags don't match their sources (data error).",
    -- Forever flags (UI files fall back to the same English text if a key is missing)
    FLAG_CLASSIC = "Not confirmed on WoW Forever yet (classic data).",
    FLAG_CHECKED = "Checked on WoW Forever.",
    FLAG_LATER = "Not yet released on WoW Forever.",
    FLAG_LATER_SHORT = "Not out yet",
    FLAG_LATER_COUNT = "%d more not out yet",
    -- /gs probe (Probe.lua)
    PROBE_HEAD = "Probe, Gear Set %s",
    PROBE_COPY = "The probe text is in the copy box: press Ctrl+C and paste it into your bug report.",
    PROBE_POPUP = "Press Ctrl+C to copy the probe results, then paste them into your bug report.",
    -- /gs selftest (SelfTest.lua)
    SELFTEST_OK = "Self-check: OK (%d checks). The result line is in the copy box.",
    SELFTEST_BAD = "Self-check: %d problem(s) found (%d checks). Copy the line in the box (Ctrl+C) and paste it into your bug report.",
    SELFTEST_STOPPED = "Self-check stopped: combat started. The results so far are in the copy box.",
    SELFTEST_COMBAT = "The self-check runs when combat ends.",
    SELFTEST_BUSY = "The self-check is already running.",
    SELFTEST_POPUP = "Press Ctrl+C to copy the self-check results, then paste them into your bug report.",
    -- beta.2: settings panel (UI\Settings.lua)
    SETTINGS = "Settings",
    SETTINGS_TIP_HINT = "Also: /gs config",
    SETTINGS_COMBAT = "The settings open after combat.",
    SETTINGS_MISSING ="Settings aren't available in this game version. Use /gs minimap and /gs reset.",
    S_WINDOW = "Window",
    S_LIST = "Set list",
    S_HELP = "Help",
    S_MINIMAP = "Show the minimap button",
    S_MINIMAP_TIP = "Also /gs minimap.",
    S_HELP_NEXT = "Show help the next time I open Gear Set",
    S_HELP_NEXT_TIP = "Shows the four help notes again the next time you open the window.",
    S_POS_LABEL = "Window position",
    S_RESET_POS = "Reset",
    S_RESET_POS_TIP = "Moves the window back to the middle of the screen.",
    S_SHOW_HIDDEN = "Show hidden sets in the list",
    S_SHOW_HIDDEN_TIP = "Hidden sets show in grey with a \"hidden\" tag. Right-click a set in the list to hide or show it.",
    S_HIDDEN_LABEL = "Hidden sets",
    S_UNHIDE_ALL = "Show all (%d)",
    S_HELP_LABEL = "First-time help",
    S_HELP_NOW = "Show now",
    S_REPORT_LABEL = "Found a bug?",
    S_REPORT = "Report a problem",
    S_REPORT_TIP = "Shows a line about your game and the set you looked at, ready to copy.",
    S_DATA = "Data version %s, checked %s, WoW Forever %s",
    REPORT_POPUP = "Copy this line (Ctrl+C) and send it with your bug report, then say what went wrong:",
    -- First-time help (UI\Help.lua)
    HELP_TITLE = "Gear Set",
    HELP_GOT_IT = "Got it",
    HELP_BUTTON_TIP = "Show help",
    HELP_SETS_H = "1. Sets",
    HELP_SETS = "Pick a set here. The menu filters and sorts; right-click a set to hide it.",
    HELP_MODEL_H = "2. The look",
    HELP_MODEL = "Drag to turn, wheel to zoom. Untick a piece to hide it on the model.",
    HELP_PIECES_H = "3. Pieces",
    HELP_PIECES = "What you have and what you still need. Click a piece to see how to get it, step by step.",
    HELP_SETTINGS_H = "4. Settings",
    HELP_SETTINGS = "The gear button: minimap button, hidden sets, Report a problem. Reopen this help with the i button or /gs help.",
    MINIMAP_TIP_SETTINGS = "Right-click: settings.",
    -- Hidden sets
    HIDE_SET = "Hide this set",
    SHOW_SET = "Show this set",
    SHOW_HIDDEN = "Show hidden sets",
    HIDDEN_TIP = "Hidden: right-click to show it again.",
    HIDDEN_TAG = "hidden",                   -- small tag on a hidden set's row
    HIDE_HINT = "Right-click: hide this set",
    SORT_EFFORT = "Least effort",
    -- Tier tags (SetsData t = ...)
    TIER_LINE = "Tier: %s",
    TIER_D1 = "Dungeon Set 1",
    TIER_D2 = "Dungeon Set 2",
    TIER_T1 = "Tier 1",
    TIER_T2 = "Tier 2",
    TIER_T3 = "Tier 3",
    TIER_ZG = "Zul'Gurub",
    TIER_AQ20 = "Ruins of Ahn'Qiraj",
    TIER_AQ40 = "Temple of Ahn'Qiraj",
    TIER_PvP = "PvP",
    -- Effort score (Data:GetEffort)
    EFFORT = "Effort: %s",
    EFFORT_0 = "Done",
    EFFORT_1 = "Low",
    EFFORT_2 = "Medium",
    EFFORT_3 = "High",
    EFFORT_4 = "Very high",
    EFFORT_TITLE = "Effort for the %d pieces you still need: %s",
    EFFORT_RAID = "Raid: %s, %d players",
    EFFORT_RAID_NOSIZE = "Raid: %s",
    EFFORT_QUEST_RUNS = "Quests inside dungeons or raids: %d",
    EFFORT_SPECIAL = "Special: %s",
    EFFORT_PLACES = "Places to run: %d (%s)",
    EFFORT_REP = "Reputation: %s",
    EFFORT_GOLD = "About %d gold",
    EFFORT_CHAIN = "Quest chain: %d steps",
    EFFORT_CRAFT = "Crafted",
    EFFORT_WORLD = "Random world drop",
    EFFORT_HINT = "Click a piece to see how to get it.",
    EFFORT_UNKNOWN = "unknown",            -- beta.7: no source data for the needed pieces
    EFFORT_NO_DATA = "No source data for these pieces yet.",
    -- beta.7: alt memory (Alts.lua). Names shown here stay on screen only.
    ALT_ALSO_ON = "Also on: %s",
    ALT_HOLDER = "%s (%s)",                -- "Bankalt (bank)"
    ALT_MORE = "%s +%d",
    ALT_TIP_HEAD = "Your other characters:",
    ALT_ACCOUNT = "Account bank",
    ALT_WHERE_equipped = "equipped",
    ALT_WHERE_bags = "bags",
    ALT_WHERE_bank = "bank",
    ALT_WHERE_mail = "mailbox",
    ALT_WHERE_keyring = "keyring",
    ALT_WHERE_account = "account bank",
    ALT_SEEN_TODAY = "seen today",
    ALT_SEEN_1 = "seen yesterday",
    ALT_SEEN_N = "seen %d days ago",
    ALT_SET_LINE = "%s: %d/%d",            -- set tooltip, one line per other character
    DONE_ON = "Finished on %s",
    DONE_KEPT = "Stays finished, even after you upgrade pieces.",
    S_TIPS = "Tooltip and clicks",
    S_TOOLTIP_LINE = "Show the Gear Set line on item tooltips",
    S_TOOLTIP_LINE_TIP = "On set pieces: how many pieces of the set you have, and whether you still need this one.",
    S_TOOLTIP_SHIFT = "Only while Shift is held",
    S_TOOLTIP_SHIFT_TIP = "Keeps tooltips short when you use other tooltip addons.",
    S_ALT_CLICK = "Alt-click an item to open its guide",
    S_ALT_CLICK_TIP = "Works on bag items, chat links, loot and the character window.",
    S_CHARS = "Characters",
    S_FORGET_LABEL = "Saved characters (%d)",
    S_FORGET = "Forget a character",
    S_FORGET_TIP = "Removes what Gear Set remembers about one of your other characters.",
    S_FORGET_NONE = "Gear Set has no other characters saved yet. Log in on an alt to add it.",
    S_FORGET_MENU = "Forget which character?",
    S_FORGET_ASK = "Forget %s? Gear Set removes the pieces it remembered for this character. It is saved again the next time you log in on it.",
    S_FORGET_DONE = "Forgot %s.",
    -- Fit facts (Data:GetSetStats)
    STATS = "Stats",
    STATS_TITLE = "%s: stats",
    STATS_ALL = "All %d pieces together:",
    STATS_SOURCE = "From the item tooltips in this game.",
    STATS_NONE = "No stats found.",
    STATS_COMBAT = "Stats are read after combat.",
    FIT_YES = "You can wear it (%s).",
    FIT_NO = "Your class can't wear this armor (%s).",
    -- beta.8: tabs, tracking, progress page, milestones (UI\Progress.lua)
    TAB_SETS = "Sets",
    TAB_PROGRESS = "Progress",
    TRACK_SET = "Track this set",
    UNTRACK_SET = "Stop tracking this set",
    TRACK_HINT = "Shift-click: track this set",
    TRACKED = "Tracked",
    TRACKED_ONLY = "Tracked only",
    TIER = "Tier",
    SHARE = "Share in chat",
    SHARE_FULL = "chat box too full",
    SHARE_LOADING = "item info still loading, try again",
    SHARE_MORE = "+%d more",                 -- after the links when not all fit (Share.lua)
    SHARE_FIT = "%d of %d pieces fit in one chat line",
    -- ui-review-3: "Sets complete" count box under the title bar (UI\Main.lua)
    COUNT_BOX = "Sets complete:",
    COUNT_BOX_TIP = "Sets complete on this character",
    COUNT_BOX_HINT = "Click: open the Progress tab.",
    P_SCOPE = "Count for",
    P_SCOPE_char = "This character",
    P_SCOPE_account = "Whole account",
    P_PCT = "%d%% of set pieces",
    P_SUMMARY = "%d complete, %d started, %d / %d pieces",
    P_TRACKED = "Tracked: %d sets and %d pieces, %d pieces still needed",
    P_TRACKED_NONE = "Nothing tracked yet: shift-click a set or a piece to track it.",
    P_BY_KIND = "By content",
    P_BY_TIER = "By tier",
    P_BAR_TIP = "%d of %d sets complete",
    P_BAR_HINT = "Click: show these sets in the list",
    P_RECENT = "Recently got",
    P_RECENT_NONE = "Nothing new yet. Set pieces you get from now on show up here with the date.",
    P_RECENT_WHO = "%s (%s)",
    P_CHARS = "Your characters",
    P_CHAR_LINE = "%s: %d complete, %d%%",
    P_LEFT_OUT = "Not counted: removed, other-faction, hidden and not-yet-released sets.",
    P_LEFT_OUT_CHAR = "Not counted: sets your class can't wear, removed, other-faction, hidden and not-yet-released sets.",
    P_LINE = "%d%% of set pieces",
    P_LINE_TRACKED = "%d%% of set pieces, %d tracked pieces left",
    MS_LINE = "milestone reached - %s!",
    MS_first_set = "your first complete set",
    MS_sets_5 = "5 complete sets",
    MS_sets_10 = "10 complete sets",
    MS_sets_25 = "25 complete sets",
    MS_pct_25 = "a quarter of all set pieces",
    MS_pct_50 = "half of all set pieces",
    MS_pct_75 = "three quarters of all set pieces",
    MS_pct_100 = "every set piece",
    S_PROGRESS = "Progress",
    S_MILESTONES = "Milestone notes in chat",
    S_MILESTONES_TIP = "One quiet chat line when you reach a milestone, like your first complete set. No sound.",
    -- (gold texts GOLD_* live in PART B's Gold.lua)
}

-- Key Bindings menu texts (Bindings.xml, loaded by the game from the addon folder).
BINDING_HEADER_GEARSET = ns.L.TITLE
BINDING_NAME_GEARSET_TOGGLE = ns.L.BIND_TOGGLE

-- Global entry point for the key binding (binding code runs outside the addon's namespace).
function GearSet_Toggle()
    if ns.UI and ns.UI.Toggle then ns.UI:Toggle() end
end

local defaults = {
    version = ns.DB_VERSION,
    point = nil,                 -- { point, relPoint, x, y }
    filters = {
        class = 0,               -- 0 = all, else classID
        armor = 0,               -- 0 = all, else armor subclass (1 cloth .. 4 plate)
        -- "Only my class": on for new installs. ApplyDefaults only fills missing keys,
        -- so an existing saved false stays false.
        usable = true,
        hideComplete = false,
        showRemoved = false,     -- sets removed in patch 1.11 stay hidden
        kind = "",               -- content: "" = all, else "d"/"r"/"p"/"c"/"w"/"f"
        myFaction = true,        -- hide the other faction's PvP / Arathi Basin sets
        showHidden = false,      -- DB v2: list hidden sets too (greyed)
        trackedOnly = false,     -- DB v4: only tracked sets (or sets with a tracked piece)
        tier = "",               -- DB v4: "" = all, else a tier tag ("T1"; Progress page bars set it)
        hideLater = false,       -- DB v5 (v1.0.1): hide sets not out yet on WoW Forever
        myLevel = false,         -- DB v7 (1.1 beta.2): only sets within 5 levels of yours
    },
    sort = "owned",              -- set list order: "owned", "closest", "name", "effort" (v2)
    search = "",
    lastSet = nil,
    onlySet = false,
    minimap = {
        angle = 200,             -- degrees around the minimap, 0 = right, 90 = top
        hide = false,
    },
    -- DB v2 (additive): hidden["set:<itemSetID>"] = true (Entries keys); help.seen = first-time
    -- help shown.
    hidden = {},
    help = {
        seen = false,
    },
    -- DB v3 (additive, Alts.lua): chars["Name-Realm"] = { name, realm, class, seen,
    -- places = { equipped/bags/bank/mail/keyring = "id,id" }, dates = { place = epoch },
    -- done = { [setID] = epoch } } for this account's own characters only (never other
    -- players' data); account = { bank = "id,id", date, readable, checked } (account bank).
    chars = {},
    account = {},
    -- DB v3: tooltip line and Alt-click (Tooltip.lua / Integrations.lua, settings page).
    tooltipLine = true,          -- Gear Set line on item tooltips
    tooltipShift = false,        -- only while Shift is held
    altClick = true,             -- Alt-click a set piece anywhere opens its guide
    -- DB v4 (additive, UI\Progress.lua): tracked["Name-Realm"] = { ["set:<id>"] = true,
    -- ["item:<id>"] = true } per character; progress.scope "char"/"account" (Progress page),
    -- progress.got["Name-Realm"] = { [itemID] = epoch } (0 = had before Gear Set counted),
    -- progress.marks["Name-Realm"] = { [milestone] = epoch } (0 = reached before beta.8).
    tracked = {},
    progress = {
        scope = "char",
        got = {},
        marks = {},
    },
    milestoneNotes = true,       -- one quiet chat line per milestone (no sound)
    -- DB v4 (additive, PART B's Prices.lua): prices[itemID] = { c = copper, x = "other cost", t = epoch },
    -- vendor prices learned in game, account-wide. Never cleared by a migration.
    prices = {},
    -- DB v6 (1.1 beta.1, additive, UI\Tracker.lua / LootMark.lua): the dungeon checklist's
    -- position, collapsed state, open by itself, use started sets when nothing is tracked,
    -- skip[instanceKey] = true ("Don't show in this instance"); the loot-roll star on/off.
    tracker = {
        point = nil,
        collapsed = false,
        auto = true,
        started = true,
        skip = {},
    },
    lootMark = true,
    -- DB v7 (1.1 beta.2, additive): auction prices from "auto" / "auctionator" / "tsm" / "off"
    -- (AHPrices.lua, read only, nothing cached); helm / cloak / weapons hidden on our own model
    -- (Preview.lua); "Next:" line in the minimap / broker tooltip. Alts.lua adds per character
    -- `mats` ("id:bags:bank,..."), `prof` ("skillLine:rank,...") and `recipes` ("spellID,...").
    priceSource = "auto",
    preview = {
        hide = { head = false, back = false, weapons = false },
    },
    nextTargets = true,
    levels = {},             -- itemID -> required level learned in game (Data.LearnLevel)
    -- DB v8 (1.1 beta.4, additive): Plan tab runs folded (account-wide) and pinned (per character,
    -- pinned["Name-Realm"] = { [run] = true }); hand-in chat line on/off; seenOut[itemID] = epoch
    -- when one of your own characters held a "not out yet" piece (Data.NoteSeen; never removed).
    plan = {
        collapsed = {},
        pinned = {},
    },
    handIns = true,
    seenOut = {},
    -- DB v9 (1.1 beta.6, additive): Alts.lua adds per character `rep` ({ [factionID] = { r, v, t } })
    -- and `quests` ({ [questID] = true }) from Steps.Snapshot - own characters only, our IDs only.
    -- Bad rows are ignored where read (Steps.AltRep / AltChains), never deleted. No new top-level keys.
}

-- Filter defaults, read by the set list's "Reset filters" (one place for both).
ns.FILTER_DEFAULTS = defaults.filters

-- Fill missing or wrong-typed keys from defaults; never removes the user's data.
local function ApplyDefaults(db, def)
    for k, v in pairs(def) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            ApplyDefaults(db[k], v)
        elseif db[k] == nil or (v ~= nil and type(db[k]) ~= type(v)) then
            db[k] = v
        end
    end
end

-- Content filter values (set kinds), in menu order; "" = all.
ns.SET_KINDS = { "d", "r", "p", "c", "w", "f" }
local SORT_MODES = { owned = true, closest = true, name = true, effort = true }
local ANCHORS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function Finite(n)
    n = tonumber(n)
    return n ~= nil and n == n and n ~= math.huge and n ~= -math.huge
end

local function WholeIn(n, lo, hi)
    return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
end

-- Saved window point { point, relPoint, x, y } that SetPoint can take.
function ns.ValidPoint(p)
    if type(p) ~= "table" or not ANCHORS[p[1]] then return false end
    if p[2] ~= nil and not ANCHORS[p[2]] then return false end
    if p[3] ~= nil and not Finite(p[3]) then return false end
    if p[4] ~= nil and not Finite(p[4]) then return false end
    return true
end

-- Values of the right type but unknown (hand-edited or broken SavedVariables) go back
-- to their defaults one by one, so the list never comes up empty with no menu choice ticked.
local function ValidateDB(db)
    if db.point ~= nil and not ns.ValidPoint(db.point) then db.point = nil end
    local f, d = db.filters, defaults.filters
    if not WholeIn(f.class, 0, 99) then
        f.class = d.class
    elseif f.class ~= 0 and C_CreatureInfo and C_CreatureInfo.GetClassInfo
        and not C_CreatureInfo.GetClassInfo(f.class) then
        f.class = d.class
    end
    if not WholeIn(f.armor, 0, 4) then f.armor = d.armor end
    local kindOK = f.kind == ""
    for _, k in ipairs(ns.SET_KINDS) do
        if f.kind == k then kindOK = true end
    end
    if not kindOK then f.kind = d.kind end
    if #f.tier > 8 or f.tier:match("[^%w]") then f.tier = d.tier end
    if db.progress.scope ~= "char" and db.progress.scope ~= "account" then
        db.progress.scope = defaults.progress.scope
    end
    -- A class picked in the Class menu and "Only my class" can't both apply (empty list
    -- for any other class); the picked class wins, like in the menu.
    if f.class ~= 0 and f.usable then f.usable = false end
    if not SORT_MODES[db.sort] then db.sort = defaults.sort end
    if db.tracker.point ~= nil and not ns.ValidPoint(db.tracker.point) then db.tracker.point = nil end
    -- an unknown string may come from a newer version: kept (AHPrices reads it as "auto")
    if type(db.priceSource) ~= "string" or db.priceSource == "" then
        db.priceSource = defaults.priceSource
    end
    if not Finite(db.minimap.angle) then db.minimap.angle = defaults.minimap.angle end
    -- v8: a pinned list that isn't a table is dropped (only that character's pins); bad seenOut
    -- values are ignored where read (Data.SeenOut), never deleted.
    for k, v in pairs(db.plan.pinned) do
        if type(k) ~= "string" or type(v) ~= "table" then db.plan.pinned[k] = nil end
    end
end

-- Defaults, checks and migrations on any table (InitDB's saved data; /gs selftest runs
-- it on copies only). Never removes the user's keys.
function ns.PrepareDB(t)
    -- A numeric-looking string version ("5") counts by its number before ApplyDefaults,
    -- which would otherwise swap the wrong type for the default and lower a newer version.
    if type(t.version) == "string" and Finite(t.version) then t.version = tonumber(t.version) end
    ApplyDefaults(t, defaults)
    ValidateDB(t)
    -- Migrations (compare t.version). v1 -> v2, v2 -> v3, v3 -> v4, v4 -> v5, v5 -> v6, v6 -> v7, v7 -> v8 and v8 -> v9 only add keys (ApplyDefaults
    -- above). v3: a char record written in the planned beta.3 shape (one `items` string, no
    -- `places`) gets its items as bags; the old key stays. A newer version number is never
    -- lowered, so an older build opening newer data doesn't mark it as old.
    local v = tonumber(t.version) or 0
    if v < 3 then
        for _, rec in pairs(t.chars) do
            if type(rec) == "table" and type(rec.items) == "string" and rec.places == nil then
                rec.places = { bags = rec.items }
            end
        end
    end
    if v < ns.DB_VERSION then t.version = ns.DB_VERSION end
    return t
end

function ns.InitDB()
    if type(GearSetDB) ~= "table" then GearSetDB = {} end
    ns.PrepareDB(GearSetDB)
    ns.db = GearSetDB
end

function ns.Print(msg)
    local c = NORMAL_FONT_COLOR
    local prefix = c and c:WrapTextInColorCode(ns.L.TITLE .. ":") or (ns.L.TITLE .. ":")
    print(prefix .. " " .. tostring(msg))
end

-- Register an event only if this client knows it (unknown events throw).
function ns.SafeRegister(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end

-- Copy box: Blizzard's own dialog with the text filled in and selected.
-- The text can't be changed (typing puts it back), so Ctrl+C always copies all of it.
-- Kinds: "wiki" (wiki search link) and "name" (item name, "Wiki link" swaps in the wiki search link).
local COPY_MAX = 4000                   -- room for the /gs probe text (names and links are short)
ns.COPY_MAX = COPY_MAX
-- Newer dialog code has GetEditBox()/GetOwningDialog(); older uses .editBox and the parent.
local function CopyBox(self)
    return (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox
end
local function BoxDialog(box)
    return (box.GetOwningDialog and box:GetOwningDialog()) or box:GetParent()
end
local function KeepLink(box, data)
    if data and box:GetText() ~= data then box:SetText(data) end
    box:HighlightText()
end

local function FillBox(dialog, text)
    local box = CopyBox(dialog)
    if not box then return end
    if box.SetMaxLetters then box:SetMaxLetters(COPY_MAX) end
    box:SetText(text or "")
    box:SetCursorPosition(0)
    box:HighlightText()
    box:SetFocus()
end

local function CopyDialog(text)
    return {
        text = text,
        button1 = CLOSE or "Close",
        hasEditBox = true,
        editBoxWidth = 360,
        maxLetters = COPY_MAX,
        OnShow = function(self, data) FillBox(self, data or self.data) end,
        EditBoxOnTextChanged = function(box, data)
            local d = BoxDialog(box)
            -- Read the dialog's current data first: "Wiki link" swaps it while open.
            KeepLink(box, (d and d.data) or data)
        end,
        EditBoxOnEnterPressed = function(box) local d = BoxDialog(box) if d then d:Hide() end end,
        EditBoxOnEscapePressed = function(box) local d = BoxDialog(box) if d then d:Hide() end end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local COPY_DIALOG = { name = "GEARSET_COPYNAME", wiki = "GEARSET_WIKI", probe = "GEARSET_PROBE",
    report = "GEARSET_REPORT", selftest = "GEARSET_SELFTEST", way = "GEARSET_WAY", lfg = "GEARSET_LFG" }

StaticPopupDialogs.GEARSET_WIKI = CopyDialog(ns.L.WIKI_POPUP)
StaticPopupDialogs.GEARSET_PROBE = CopyDialog(ns.L.PROBE_POPUP)   -- /gs probe results
StaticPopupDialogs.GEARSET_SELFTEST = CopyDialog(ns.L.SELFTEST_POPUP) -- /gs selftest results
StaticPopupDialogs.GEARSET_REPORT = CopyDialog(ns.L.REPORT_POPUP) -- Settings: Report a problem
StaticPopupDialogs.GEARSET_WAY = CopyDialog(ns.L.WAY_POPUP)       -- guide Way button: "Zone 43.4, 52.2"
StaticPopupDialogs.GEARSET_LFG = CopyDialog(ns.L.LFG_POPUP)       -- Plan tab LFG line (ToS B5: copy only)

local nameDialog = CopyDialog(ns.L.COPY_POPUP)
nameDialog.button2 = ns.L.WIKI_LINK
nameDialog.noCancelOnEscape = true       -- Esc just closes; only the button swaps the text
-- Button 2 ("Wiki link"): put the wiki search link in the box; returning true keeps the dialog open.
local function SwapToAlt(self)
    local alt = self and self.gsAlt
    if alt then
        self.data = alt
        FillBox(self, alt)
    end
    return true
end
nameDialog.OnCancel = SwapToAlt          -- older dialog code
nameDialog.OnButton2 = SwapToAlt         -- newer code may call this one instead
StaticPopupDialogs.GEARSET_COPYNAME = nameDialog

-- "Report a problem" line: addon, data and game versions, the set shown and the last piece
-- looked at. Never the character's name, realm or guild, and no web address (user's choice).
-- Every part is guarded; missing parts are left out, so it never errors.
local function ReportParts()
    local parts = {}
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, ver = pcall(getMeta, ADDON, "Version")
    parts[#parts + 1] = ns.L.TITLE .. " " .. ((ok and type(ver) == "string" and ver ~= "") and ver or "?")
    if ns.Data and ns.Data.DataInfo then
        local d = ns.Data.DataInfo()
        parts[#parts + 1] = ("data %s (%s, Forever %s)"):format(tostring(d.version), d.checked, d.game)
    end
    if GetBuildInfo then
        local okB, v, build = pcall(GetBuildInfo)
        if okB and v then parts[#parts + 1] = ("game %s (%s)"):format(tostring(v), tostring(build or "?")) end
    end
    local key = ns.db and ns.db.lastSet
    local okS, set = pcall(function() return key and ns.Data:GetSet(key) end)
    if okS and set then parts[#parts + 1] = ("set: %s (%s)"):format(set.name or "?", set.key) end
    local piece
    if ns.GuidePage and ns.GuidePage.IsOpen and ns.GuidePage:IsOpen() then piece = ns.GuidePage.piece end
    local itemID = (piece and piece.itemID) or (ns.PieceList and ns.PieceList.lastItem)
    if type(itemID) == "number" then
        local name
        if C_Item and C_Item.GetItemNameByID then
            local okN, n = pcall(C_Item.GetItemNameByID, itemID)
            if okN then name = n end
        end
        parts[#parts + 1] = ("piece: %s (%d)"):format((type(name) == "string" and name ~= "") and name or "?", itemID)
    end
    return table.concat(parts, " | ")
end

function ns.ReportText()
    local ok, text = pcall(ReportParts)
    if ok and type(text) == "string" then return text end
    return ns.L.TITLE .. " ?"
end

-- ns.ShowCopyBox(kind, text, alt): kind "name", "wiki", "probe", "report", "selftest", "way" or "lfg"; alt = the "Wiki link" text for "name".
function ns.ShowCopyBox(kind, text, alt)
    if not text or text == "" then return end
    local which = COPY_DIALOG[kind] or COPY_DIALOG.wiki
    for _, other in pairs(COPY_DIALOG) do
        if other ~= which then StaticPopup_Hide(other) end
    end
    StaticPopup_Hide(which)              -- reopen fresh so the box shows the new text
    local dialog = StaticPopup_Show(which, nil, nil, text)
    if dialog then dialog.gsAlt = alt end
    return dialog
end


local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        ns.InitDB()
        if ns.Owned and ns.Owned.Init then ns.Owned:Init() end
        if ns.Alts and ns.Alts.Init then pcall(ns.Alts.Init, ns.Alts) end
        if ns.MinimapButton then ns.MinimapButton:Init() end
        if ns.Settings and ns.Settings.Init then pcall(ns.Settings.Init, ns.Settings) end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

local function HandleSlash(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "" then
        ns.UI:Toggle()
    elseif msg == "reset" then
        ns.db.point = nil
        ns.UI:ResetPosition()
        ns.Print(ns.L.POS_RESET)
    elseif msg == "minimap" then
        local shown = ns.MinimapButton:ToggleShown()
        ns.Print(shown and ns.L.MINIMAP_SHOWN or ns.L.MINIMAP_HIDDEN)
    elseif msg == "check" then
        if ns.Probe then ns.Probe:PrintDataInfo() end
        ns.Data:CheckClassic()
    elseif msg == "probe" then
        if ns.Probe then ns.Probe:Run() end
    elseif msg == "selftest" or msg == "selftest full" then
        if ns.SelfTest then ns.SelfTest:Start(msg == "selftest full" and "full" or "quick") end
    elseif msg == "config" or msg == "settings" or msg == "options" then
        -- Settings:Open() handles combat itself; the "missing" line only when the panel can't exist.
        local S = ns.Settings
        local opened = S and S.Open and S:Open()
        if not opened and not (S and S.IsAvailable and S:IsAvailable()) then ns.Print(ns.L.SETTINGS_MISSING) end
    elseif msg == "checklist" then
        -- 1.1 beta.1: show or hide the dungeon checklist for the instance you're in.
        if ns.Tracker and ns.Tracker.Toggle then ns.Tracker:Toggle() end
    elseif msg == "plan" then
        -- 1.1 beta.4: the Plan tab.
        if ns.UI and ns.UI.OpenTab then ns.UI:OpenTab("plan") end
    elseif msg:match("^forget%s*%d*$") then
        -- Same menu as the settings button; "/gs forget 2" picks from the numbered list it
        -- prints when the game has no menu.
        if ns.Settings and ns.Settings.ForgetMenu then ns.Settings.ForgetMenu(tonumber(msg:match("(%d+)$"))) end
    else
        for line in ns.L.HELP:gmatch("[^\n]+") do ns.Print(line) end
        if msg == "help" and ns.Help and ns.Help.Show then ns.Help:Show() end
    end
end

ns.HandleSlash = HandleSlash   -- /gs selftest checks that /gs still reaches it
SLASH_GEARSET1 = "/gearset"
SLASH_GEARSET2 = "/gs"
SlashCmdList.GEARSET = HandleSlash
