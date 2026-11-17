# Gear Set

Keeps track of all known armor sets in the game, in one window with three parts: a list of the sets on the left, how your character looks in the chosen set in the middle, and the pieces of that set you have or still need on the right.

A World of Warcraft addon for **WoW Forever**.

> **Beta:** this is a beta (v1.0.0-beta.1). It has not been fully tested in the game yet, so things may not work as they should. Please tell us what you find.

## Install

1. Open your addon manager.
2. Turn on beta versions (the beta channel). Betas are not shown without it.
3. Find **Gear Set** in the list and install it. If it's not there, restart the addon manager.
4. Start the game, or type `/reload` if it's already running.

## How to use

Type `/gs` (or `/gearset`) to open or close the window. You can also click the minimap button, or pick **Gear Set** in the Addon Compartment (the addons button by the minimap). Esc closes the window. You can drag the window to move it. The window is large (1060x620); on a small screen or at a large UI scale, it shrinks to fit. You can also set a key in Key Bindings > Gear Set > "Open/close Gear Set" (no key is set by default).

### Minimap button

| What | How |
|---|---|
| Open or close the window | Click the button (the transmog symbol), or pick **Gear Set** in the Addon Compartment |
| Move it | Drag it around the minimap |
| Hide it | Right-click the button |
| Show or hide it | /gs minimap |

It also works with minimap-button collector addons such as Mini Map. If one of them holds the button, it moves the button, not Gear Set.

### Sets (left)

| What | How |
|---|---|
| Find a set | Type in the search box |
| Filter | The filter menu shows your current choice for Sort, Class, Armor type and Content. Choices: Class, Armor type, Content (Dungeon, Raid, PvP, Crafted, World, WoW Forever), "Only my class" (on by default for new installs), "Only my faction" (on by default), "Hide complete sets", "Show removed sets", "Reset filters" (puts every filter back to its default; the sort stays) |
| Only my class | Picking a class turns this off, and turning it on sets Class back to All, so the two never hide every set. It keeps sets your class can wear. Dungeon Set 1 and 2 are matched to the classes they were made for. Other sets for all classes show only if your class can wear their armor type |
| Removed sets | Sets taken out of the game in patch 1.11 (old PvP rare sets) are hidden. "Show removed sets" shows them with a grey name |
| Faction | PvP and Arathi Basin sets show a small faction icon. "Only my faction" hides the other faction's sets |
| No match | The list says which search and filters are on, with a button to clear them |
| Count | Each set shows how many of its pieces you have |
| Sort | In the filter menu: "Most owned first" (default), "Closest to finishing" or "Name" |
| Order | "Most owned first": complete sets first, then sets you have some pieces of, then the rest. In each group, the sets you own most of come first, then A-Z. "Closest to finishing": sets missing the fewest pieces first, complete sets last. The chosen set stays in view when the order changes |

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

The set's pieces. At the top: the set name (arrows beside it go to the previous or next set), its armor type and classes, and "Have x / y". Hover "Have x / y" to see how many pieces are equipped, in your bags, in the bank, or only collected as an appearance. Next to it, "Set bonuses (2/3)" shows the bonuses in effect out of all (grey when the set has none). Only pieces you wear count. Hover it to see "Set name (worn/total)" and each bonus; a bonus is green when you wear enough pieces. Each piece shows where it is: Equipped, In bags, In bank, Appearance or Need.

| What | How |
|---|---|
| Show on the preview | Tick the box by the piece. Untick it to take the piece off. Necklaces, rings and trinkets don't show on the model, so their box is greyed out |
| See how to get it | Click the piece to open its guide page (see below) |
| Look it up | On the guide page, "Copy name" (then Ctrl+C) and "Wiki link" (a Warcraft Wiki search link) are in the top bar |
| Link in chat | Shift-click a piece |
| Try it on | Ctrl-click a piece to open the dressing room |
| No source | "Source unknown" means the addon has no entry for that piece |

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

Anything the addon doesn't know says "not known". Guide text is in English only.

### Checked on WoW Forever

Most of the data is classic data, not yet checked on WoW Forever. The guide page and set tooltips say which:

| Text | Meaning |
|---|---|
| Checked on WoW Forever | The set and its sources were checked on Forever (the Dungeon Set 1 sets and the 4 WoW Forever sets) |
| Not confirmed on WoW Forever yet (classic data) | Classic data, not checked on Forever yet |
| Not yet released / Not out yet | Not out on Forever yet. The set or piece is greyed and left out of "Have x / y". Right now: the raid sets (Tier 1-3, Zul'Gurub, Ahn'Qiraj, Onyxia), Dungeon Set 2, the PvP rank and Arathi Basin sets, and the Zul'Gurub crafted sets |

## Colours

| Colour | Pieces (right) | Sets (left) and "Have x / y" |
|---|---|---|
| Green | You have it: equipped, in bags or in bank | You have every piece |
| Blue | Appearance collected (counts as have) | - |
| Gold | - | You have some pieces |
| Grey | You still need it | You have none |

## Commands

| Command | What it does |
|---|---|
| `/gs` or `/gearset` | Open or close the window |
| `/gs reset` | Put the window back in the middle of the screen |
| `/gs minimap` | Show or hide the minimap button |
| `/gs check` | Show the data version, last-checked date, WoW Forever build, data sources and how many sets and sources are checked on Forever, then check the built-in set list against the game and print any problems |
| `/gs probe` | List which game features this client has (waypoints, current map, tooltips, lockouts, reputation, keyring, account bank, journals, art) and put the result in a copy box to paste into a bug report |

## Where the sets come from

The classic armor sets come from a list built into the addon. Set names come from the game itself. Sets the game doesn't know any items for are left out. `/gs check` shows whether the list still matches the game.

## For developers

The addon is in the `GearSet` folder (`GearSet_Forever.toc`, interface 16001). Settings are saved account-wide in `GearSetDB`. Broken or hand-edited settings go back to their defaults at login.

| File | What it does |
|---|---|
| `Core.lua` | Text, saved settings, slash commands |
| `Theme.lua` | Every look choice (Blizzard templates, atlases, fonts, colours) in one place |
| `SetsData.lua` | The built-in list of classic sets |
| `SourcesData.lua` | The built-in list of where each piece comes from |
| `GuideData.lua` | The built-in guide data (bosses, NPCs, quests, items, quest chains) |
| `Data.lua` | Builds, sorts and filters the sets; source lines and wiki search link; `/gs check` |
| `Probe.lua` | `/gs probe` and the data info shown by `/gs check` |
| `Owned.lua` | Works out whether you have each piece |
| `UI\Widgets.lua` | Shared UI helpers (buttons, tooltips, item names) |
| `UI\Main.lua` | The main window |
| `UI\SetList.lua` | The set list, search and filter |
| `UI\Preview.lua` | The character preview |
| `UI\PieceList.lua` | The list of pieces |
| `UI\GuidePage.lua` | The guide page for one piece |
| `UI\Minimap.lua` | The minimap button and the Addon Compartment entry |

## Credits

Set, item and source data, and the how-to-get guide text, gathered from Warcraft Wiki (https://warcraft.wiki.gg), whose text is available under CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). World of Warcraft and its content are trademarks and property of Blizzard Entertainment.

## License

Code: all rights reserved. Wiki-derived data files: CC BY-SA 4.0. See `LICENSE`.
