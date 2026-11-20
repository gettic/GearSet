# Gear Set

Keeps track of all known armor sets in the game, in one window with three parts: a list of the sets on the left, how your character looks in the chosen set in the middle, and the pieces of that set you have or still need on the right.

A World of Warcraft addon for **WoW Forever**.

Current version: **v1.0.0**. A beta, v1.0.1-beta.1, is on the addon manager's beta channel.

## Install

1. Open your addon manager.
2. Find **Gear Set** in the list and install it. If it's not there, restart the addon manager.
3. Start the game, or type `/reload` if it's already running.

Betas of newer versions, when there are any, are on the addon manager's beta channel.

## How to use

Type `/gs` (or `/gearset`) to open or close the window. You can also click the minimap button, or pick **Gear Set** in the Addon Compartment (the addons button by the minimap). Esc closes the window (the X button also works in combat). The first time you open it, and after an update, four short notes explain the window; click **Got it**, click anywhere or press Esc to close them. Open them again with the **i** button in the top bar, left of the gear, or `/gs help`. You can drag the window to move it. The window is large (1060x620); on a small screen or at a large UI scale, it shrinks to fit. You can also set a key in Key Bindings > Gear Set > "Open/close Gear Set" (no key is set by default).

### Minimap button

| What | How |
|---|---|
| Open or close the window | Click the button (the transmog symbol), or pick **Gear Set** in the Addon Compartment |
| Move it | Drag it around the minimap |
| Open the settings | Right-click the button |
| Show or hide it | The check box in the settings, or `/gs minimap` |

It also works with minimap-button collector addons such as Mini Map. If one of them holds the button, it moves the button, not Gear Set.

### Settings

Open them with the gear button at the top right of the window, a right-click on the minimap button, `/gs config`, or Esc > Options > AddOns > Gear Set. In combat they can't open (Blizzard's rule for addons): Gear Set says so and opens them when the fight ends.

| Setting | What it does |
|---|---|
| Show the minimap button | Shows or hides the button |
| Show help the next time I open Gear Set | Shows the first-time help again |
| Reset window position | Puts the window back in the middle |
| Show hidden sets in the list | Same as "Show hidden sets" in the filter menu |
| Show all | Un-hides every hidden set |
| Show the Gear Set line on item tooltips | Turns the [tooltip line](#item-tooltips-and-alt-click) on or off (on by default) |
| Only while Shift is held | Shows the tooltip line only while you hold Shift. Sits under the line above and is greyed out while that is off |
| Alt-click an item to open its guide | Turns Alt-click on or off (on by default) |
| Milestone notes in chat | One quiet chat line when you reach a [milestone](#tabs-and-progress) (on by default) |
| Forget a character | Removes the saved pieces of one of your other characters |
| Show help now | Opens the help |
| Report a problem | Shows one line to copy for a bug report: addon and data version, game build, and the set and piece you looked at. No character name, realm or guild. Nothing is sent anywhere |
| Data version | Shown in the "Report a problem" tooltip |

### Sets (left)

| What | How |
|---|---|
| Find a set | Type in the search box. A tier tag works too: "t2" or "tier 2" finds the Tier 2 sets. See [Search](#search) for more |
| Filter | The filter menu shows your current choice for Sort, Class, Armor type and Content. Choices: Class, Armor type, Content (Dungeon, Raid, PvP, Crafted, World, WoW Forever), "Only my class" (on by default for new installs), "Only my faction" (on by default), "Hide complete sets", "Hide sets not out yet", "Show removed sets", "Show hidden sets", "Reset filters" (puts every filter back to its default; the sort stays) |
| Only my class | Picking a class turns this off, and turning it on sets Class back to All, so the two never hide every set. It keeps sets your class can wear. Dungeon Set 1 and 2 are matched to the classes they were made for. Other sets for all classes show only if your class can wear their armor type |
| Removed sets | Sets taken out of the game in patch 1.11 (old PvP rare sets) are hidden. "Show removed sets" shows them with a grey name |
| Faction | PvP and Arathi Basin sets show a small faction icon. "Only my faction" hides the other faction's sets |
| No match | The list says which search and filters are on, with a button to clear them |
| Count | Each set shows how many of its pieces you have |
| Hide a set | Right-click it and pick "Hide this set". "Show hidden sets" in the filter menu lists hidden sets again in grey with a "hidden" tag; right-click one and pick "Show this set". "Reset filters" turns "Show hidden sets" off. Hidden sets are kept through `/reload` and updates |
| Tier | The set tooltip shows the tier tag (Dungeon Set 1/2, Tier 1-3, Zul'Gurub, Ruins / Temple of Ahn'Qiraj, PvP), for example "Tier: Tier 2" |
| Sort | In the filter menu: "Most owned first" (default), "Closest to finishing", "Least effort" or "Name" |
| Order | "Most owned first": complete sets first, then sets you have some pieces of, then the rest. In each group, the sets you own most of come first, then A-Z. "Closest to finishing": sets missing the fewest pieces first, complete sets last. "Least effort": sets that need the least work for the pieces you still need first, then sets with unknown effort, complete sets last. In every order, sets that are out now come before sets not out yet. The chosen set stays in view when the order changes |
| Finished sets | A set you finished stays finished, even after you upgrade or sell pieces. Its tooltip shows the date you finished it |
| Track a set | Shift-click it. A gold star shows on the row. Tracking is saved per character |
| Right-click menu | Track, Share in chat, Hide |
| Tracked only, Tier | In the filter menu: "Tracked only" lists only tracked sets (or sets with a tracked piece). "Tier" picks one tier tag |
| Share in chat | Right-click a set and pick "Share in chat". It puts the set name and its item links into your chat box (up to 255 characters, whole links only). When not every piece fits, it reads "Set name: [link] [link] +5 more" and Gear Set says how many fit. You press Enter to send. Gear Set never sends anything itself. If nothing can be added (chat box too full, or item info still loading), one "Gear Set:" line in chat says why |

### Preview (middle)

Your character wearing the chosen set.

| What | How |
|---|---|
| Turn | Drag with the mouse |
| Zoom | Mouse wheel |
| Show only the set | Tick "Only the set" (bottom bar) to take off your own gear (off by default, so your own gear shows with the set) |
| Take a piece off | Untick its box in the list on the right; tick it again to put it back |
| Start over | "Reset view" (bottom bar) turns the model back, zooms out and puts all pieces back |

### Pieces (right)

The set's pieces. At the top: the set name (arrows beside it go to the previous or next set), its armor type and classes, and "Have x / y". Hover "Have x / y" to see how many pieces are equipped, in your bags, bank, mailbox, keyring or account bank, or only collected as an appearance. Next to it, "Set bonuses (2/3)" shows the bonuses in effect out of all (grey when the set has none). Only pieces you wear count. Hover it to see "Set name (worn/total)" and each bonus; a bonus is green when you wear enough pieces. Each piece shows where it is: Equipped, In bags, In bank, In mailbox, On keyring, Account bank, Appearance or Need. The mailbox, keyring and account bank are only checked when you open the mailbox or bank, so those pieces show a grey date, such as "seen 3 days ago". The account bank only counts if the game lets addons read it. For pieces your other characters have, see [Your other characters](#your-other-characters).

Next to "Set bonuses" are two more hovers:

- **Stats:** whether your class can wear the set, and the stats of all its pieces added up from the game's own item tooltips. It is read only for the set you look at, and only out of combat.
- **Effort:** Low, Medium, High or Very high, worked out from Gear Set's own data for the pieces you still need (dungeons and raids to run, with 40-player raids counting more; quests inside dungeons; reputation; gold; quest chains; crafting; world drops; special events). Hover it to see the reasons. "Effort: unknown" means Gear Set has no source data for the pieces you need yet.

| What | How |
|---|---|
| Show on the preview | Tick the box by the piece. Untick it to take the piece off. Necklaces, rings and trinkets don't show on the model, so their box is greyed out |
| See how to get it | Click the piece to open its guide page (see below) |
| Look it up | On the guide page, "Copy name" (then Ctrl+C) and "Wiki link" (a Warcraft Wiki search link) are in the top bar |
| Track it | Shift-click a piece. A gold star shows on the row. While you type in chat, Shift-click links the piece instead |
| Gold cost | Under the state, the fixed gold it costs, when known. Pieces that bind when picked up say "can't be bought". See [Gold costs](#gold-costs) |
| Try it on | Ctrl-click a piece to open the dressing room |
| No source | "Source unknown" means the addon has no entry for that piece |
| Not in this game version | A piece this game version doesn't know yet shows greyed as "Not in this game version". It still counts in the set's total, so a set can't look finished too early |
| Keep it | Dungeon Set 1 pieces have a grey tooltip line "Keep it: the Dungeon Set 2 quests take this piece", so you don't sell them |

### Piece guide

Clicking a piece opens its guide page in the right panel.

| What | How |
|---|---|
| The page | The item (hover it for the normal tooltip), whether you have it, and a full guide on how to get it |
| Go back | "Back" button, Esc, or right-click |
| Other pieces | The arrows go to the previous or next piece. Shift-click an arrow to jump to the next piece you still need |
| Show on model | Tick "Show on model" (right of your state) to put the piece on the preview |
| Copy text | "Copy text" shows the whole guide as plain text. The text is already selected, so press Ctrl+C. A click in the box selects all again. Esc or Done goes back |
| Look it up | "Copy name" and "Wiki link" are in the top bar |
| More steps | Click a "Show ..." link to fold out more (the other faction's version, keys). Open ones stay open on the other pieces of the same set |

The guide covers:

- Boss drops: the boss, the instance, where it is, and any attunement or key (all under "Before you go").
- Quests: the steps, the giver for each faction, and what to bring. Hand-in items (Naxxramas tokens, Ahn'Qiraj tokens, idols, scarabs, Primal Hakkari items) say which boss drops them.
- Vendors: who sells it, and the PvP rank if one is needed.
- Crafting: the skill, the materials, any Leatherworking specialisation and its trainer, and where the recipe comes from or drops.

Boss drops also show the wing ("Inside: ..."), rare spawns and how a boss is summoned. Anything the addon doesn't know says "not known". Guide text is in English only.

### Way button

Guide rows with a known place (NPCs, dungeon entrances, world bosses, quest chain steps) have a small map pin at the right. Click it:

| Situation | What happens |
|---|---|
| TomTom is installed | A TomTom arrow is set |
| No TomTom | The game's own map pin is set and tracked (it replaces your own map pin) |
| No pin can be set, or you are in combat | Gear Set shows the position to copy |

One "Gear Set:" chat line says what it did. Positions are only for content that is out now. Most are from classic and say so in the tooltip until checked on WoW Forever. The guide's "Copy text" includes the exact positions.

### Search

The search box finds sets, pieces (names your game has already seen), bosses, places and NPCs (vendors, quest givers). Results are grouped, 5 per group and "n more".

| What | How |
|---|---|
| Jump to the box | Ctrl+F (not in combat) |
| Boss, place or NPC | Click it to list the sets with a piece from there and open that piece's guide |
| Open the first result | Enter |
| Clear, then close | Esc clears the search first, then closes the window |

### Item tooltips and Alt-click

| What | How |
|---|---|
| Tooltip line | Set pieces get one line on their item tooltip, for example "Gear Set: have 5/8 - you need this" (the set name is already in the game's set block above it; a piece in two or more sets names each set) |
| Needed by | "Needed by: Name 3/8" lists your other characters who started that set and still need the piece |
| Alt-click | Alt-click a set piece (bags, chat links, loot, character window) to open Gear Set at that piece's guide. In combat it opens when the fight ends |
| Turn them off | In the settings you can turn the tooltip line off, show it only while Shift is held, or turn Alt-click off |

### Tabs and progress

Two tabs sit at the bottom of the window: **Sets** (the window described above) and **Progress**.

| What | How |
|---|---|
| Count box | "Sets complete" under the title bar, for this character. Hover for details, click to open this tab |
| Totals | The % of set pieces you have, and how many sets are complete or started |
| Bars | Blizzard-style bars (like the Skills page), one per content kind and tier. They scroll. Click a bar to list those sets |
| Recently got | Set pieces you got lately, with dates |
| Characters | Each saved character as a bar |
| Count for | "This character" or "Whole account" (remembered). "This character" and each character's line count only the sets that class can wear. "Whole account" counts all sets |
| Tracked | How many sets and pieces you track, and how many pieces are still needed |

Removed, other-faction, hidden and not-yet-released sets are never counted. The minimap button and Titan Panel / data bar tooltips show a line such as "38% of set pieces, 12 tracked pieces left".

**Milestones:** your first complete set, 5, 10 and 25 sets, and a quarter, half, three quarters and all of the pieces. Each gives one quiet chat line, once per character, with no sound. They are on by default; turn them off in Settings > Progress ("Milestone notes in chat"). Milestones you had already reached before the update are noted silently.

### Gold costs

A set shows "Gold still needed" for the fixed in-game gold it still needs on this character, such as the quest gold in the Dungeon Set 2 steps. Vendor prices count only where Gear Set has them. Auction prices are not used, and crafting materials are not priced. Pieces that bind when picked up are marked "can't be bought". The piece tooltip shows the cost line.

When you open a vendor that sells set pieces (PvP rank, Arathi Basin), Gear Set remembers the prices shown (gold and honor or marks) for all your characters. They show as "Price seen at a vendor: ... (date)". It only reads the window and never buys anything.

### Your other characters

Gear Set remembers which set pieces each of your characters has: equipped, in bags, bank, mailbox and on the keyring. It saves them when you log out or close the bank. Piece rows show "Also on: Bankalt (bank)", and set tooltips show your other characters' progress. Only your own characters are saved, and only on your computer.

To remove an old character, use Settings > Characters > "Forget a character", or `/gs forget`.

### Inspect

After you inspect someone, a strip under the inspect window shows the set they wear most, for example "Gear Set: Stabby wears Bloodfang 6/8". Hover it to see all their sets. Nothing about other players is saved.

### Data bars

If you use Titan Panel or another LibDataBroker bar, it shows a "Gear Set" launcher. Click it to open the window, right-click for the settings. Gear Set bundles no libraries: the launcher only shows when such a bar addon is installed.

### Checked on WoW Forever

Most of the data is classic data, not yet checked on WoW Forever. The guide page and set tooltips say which:

| Text | Meaning |
|---|---|
| Checked on WoW Forever | The set and its sources were checked on Forever (the Dungeon Set 1 sets and the 4 WoW Forever sets) |
| Not confirmed on WoW Forever yet (classic data) | Classic data, not checked on Forever yet |
| Not yet released / Not out yet | Not out on Forever yet. The set or piece is greyed and left out of "Have x / y". Right now: the raid sets (Tier 1-3, Zul'Gurub, Ahn'Qiraj, Onyxia), Dungeon Set 2, the PvP rank and Arathi Basin sets, the Zul'Gurub crafted sets, and the four Scourge Invasion sets (Necrotic Rune shoulders and robes, Argent Dawn gloves), because no source says the invasion runs on WoW Forever |

## Colours

| Colour | Pieces (right) | Sets (left) and "Have x / y" |
|---|---|---|
| Green | You have it: equipped, in bags, bank, mailbox, keyring or account bank | You have every piece |
| Blue | Appearance collected (counts as have) | - |
| Gold | - | You have some pieces |
| Grey | You still need it | You have none |

## Commands

| Command | What it does |
|---|---|
| `/gs` or `/gearset` | Open or close the window |
| `/gs reset` | Put the window back in the middle of the screen |
| `/gs minimap` | Show or hide the minimap button |
| `/gs config` | Open the settings |
| `/gs forget` | Pick one of your other characters to forget (removes its saved pieces) |
| `/gs help` | List the commands in chat and show the help on the window |
| `/gs check` | Show the data version, last-checked date, WoW Forever build, data sources and how many sets and sources are checked on Forever, then check the built-in set list against the game and print any problems |
| `/gs probe` | List which game features this client has (waypoints, current map, tooltips, lockouts, reputation, keyring, account bank, journals, art) and put the result in a copy box to paste into a bug report |
| `/gs selftest` | The addon checks its own window, buttons, art, saved settings (on copies, yours are never changed) and data, then puts one line in a copy box to paste into a bug report. The line also says how many characters are saved, whether the account bank could be read, and how much memory the addon uses (for example "memory: 2500 KB"; left out if the game can't tell). It has no character name, realm, guild or web address. In combat it waits until the fight ends |
| `/gs selftest full` | The same, and it also opens and closes a guide page and the help |

## Where the sets come from

The classic armor sets come from a list built into the addon. Set names come from the game itself. Sets the game doesn't know any items for are left out. `/gs check` shows whether the list still matches the game.

## For developers

The addon is in the `GearSet` folder (`GearSet_Forever.toc`, interface 16001). Settings, and the set pieces your characters have, are saved account-wide in `GearSetDB`. Broken or hand-edited settings go back to their defaults at login.

### For other addons

| Function | What it does |
|---|---|
| `GearSet_IsSetPiece(item)` | `item` is an item ID or link. Returns `true` and the set ID for a set piece, else `false` |
| `GearSet_ShowItem(item)` | Opens Gear Set at that piece's guide (after combat if you are in one). Returns `true` if it opens |


| File | What it does |
|---|---|
| `Core.lua` | Text, saved settings, slash commands |
| `Theme.lua` | Every look choice (Blizzard templates, atlases, fonts, colours) in one place |
| `Entries.lua` | Typed keys ("set:<id>") and providers for what the addon tracks |
| `SetsData.lua` | The built-in list of classic sets |
| `SourcesData.lua` | The built-in list of where each piece comes from |
| `GuideData.lua` | The built-in guide data (bosses, NPCs, quests, items, quest chains) |
| `Data.lua` | Builds, sorts and filters the sets; source lines and wiki search link; `/gs check` |
| `Probe.lua` | `/gs probe` and the data info shown by `/gs check` |
| `SelfTest.lua` | `/gs selftest` |
| `Owned.lua` | Works out whether you have each piece |
| `Alts.lua` | Remembers your characters' set pieces, mailbox, keyring and account bank |
| `Tooltip.lua` | The Gear Set line on item tooltips |
| `Inspect.lua` | The strip under the inspect window |
| `Integrations.lua` | Alt-click, the data bar launcher and the functions for other addons |
| `GoldData.lua` | The built-in fixed gold costs (from Warcraft Wiki) |
| `Gold.lua` | Works out the gold still needed and what can't be bought |
| `Prices.lua` | Learns vendor prices when you open a vendor |
| `Share.lua` | Puts a set and its item links in your chat box |
| `Search.lua` | Search across sets, pieces, bosses, places and NPCs |
| `Waypoint.lua` | The Way button (TomTom or map pin) |
| `PlacesData.lua` | The built-in positions of NPCs, entrances and bosses |
| `UI\Widgets.lua` | Shared UI helpers (buttons, tooltips, item names) |
| `UI\Main.lua` | The main window |
| `UI\SetList.lua` | The set list, search and filter |
| `UI\Preview.lua` | The character preview |
| `UI\PieceList.lua` | The list of pieces |
| `UI\GuidePage.lua` | The guide page for one piece |
| `UI\Progress.lua` | The Progress tab, tracking and milestones |
| `UI\Settings.lua` | The settings page |
| `UI\Help.lua` | The first-time help |
| `UI\Minimap.lua` | The minimap button and the Addon Compartment entry |

## Credits

Works with LibDataBroker displays such as Titan Panel and with TomTom if you have them installed; they are not included with Gear Set and keep their own licences.

Set, item, source, position and gold cost data, and the how-to-get guide text, gathered and adapted from Warcraft Wiki (https://warcraft.wiki.gg), whose text is available under CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). World of Warcraft and its content are trademarks and property of Blizzard Entertainment.

## License

Code: all rights reserved. Wiki-derived data files: CC BY-SA 4.0. See `LICENSE` (a copy is also inside the addon, in `GearSet\LICENSE`).
