# Gear Set

Keeps track of all known armor sets in the game, in one window with three parts: a list of the sets on the left, how your character looks in the chosen set in the middle, and the pieces of that set you have or still need on the right.

A World of Warcraft addon for **WoW Forever**.

> **Beta:** this is a beta (v0.0.1-beta.5). It has not been fully tested in the game yet, so things may not work as they should. Please tell us what you find.

## Install

1. Open your addon manager.
2. Turn on beta versions (the beta channel). Betas are not shown without it.
3. Find **Gear Set** in the list and install it. If it's not there, restart the addon manager.
4. Start the game, or type `/reload` if it's already running.

## How to use

Type `/gs` (or `/gearset`) to open or close the window. You can also click the minimap button, or pick **Gear Set** in the Addon Compartment (the addons button by the minimap). Esc closes the window. You can drag the window to move it.

### Minimap button

| What | How |
|---|---|
| Open or close the window | Click the button (the transmog symbol), or pick **Gear Set** in the Addon Compartment |
| Move it | Drag it around the minimap |
| Hide or show it | `/gs minimap` |

It also works with minimap-button collector addons such as Mini Map. If one of them holds the button, it moves the button, not Gear Set.

### Sets (left)

| What | How |
|---|---|
| Find a set | Type in the search box |
| Filter | Class, armor type, "Only my class", "Hide complete sets", "Reset filters" |
| Count | Each set shows how many of its pieces you have |
| Order | Complete sets first, then sets you have some pieces of, then the rest. In each group, the sets you own most of come first, then A-Z |

### Preview (middle)

Your character wearing the chosen set.

| What | How |
|---|---|
| Turn | Drag with the mouse |
| Zoom | Mouse wheel |
| Show only the set | Tick "Only the set" to take off your own gear (off by default, so your own gear shows with the set) |
| Take a piece off | Untick its box in the list on the right; tick it again to put it back |
| Start over | "Reset" turns the model back, zooms out and puts all pieces back |

### Pieces (right)

The set's pieces, with "Have x / y" at the top. Each piece shows where it is: Equipped, In bags, In bank, Look collected or Need.

| What | How |
|---|---|
| Show on the preview | Tick the box by the piece. Untick it to take the piece off. Necklaces, rings and trinkets don't show on the model, so their box is greyed out |
| See how to get it | Click the piece (the +/-). It shows up to 3 lines: boss drop, quest, vendor, profession, world drop, or "Drop: <place>" for trash or several bosses. One piece is open at a time |
| No source | "Source unknown" means the addon has no entry for that piece |
| Wrong source | Open the piece and click "Report a mistake" |

### Report a mistake

A box appears with a ready link, already selected. Press Ctrl+C, then paste the link into your browser. It opens a pre-filled GitHub issue (you need a GitHub account). Add what is right and submit. Fixes come in the next update.

## Colours

| Colour | Pieces (right) | Sets (left) and "Have x / y" |
|---|---|---|
| Green | You have it: equipped, in bags or in bank | You have every piece |
| Blue | Look collected (counts as have) | - |
| Gold | - | You have some pieces |
| Red | You still need it | "Have x / y" when you have none |
| Grey | - | Set list: you have none |

## Commands

| Command | What it does |
|---|---|
| `/gs` or `/gearset` | Open or close the window |
| `/gs reset` | Put the window back in the middle of the screen |
| `/gs minimap` | Show or hide the minimap button |
| `/gs check` | Check the built-in set list against the game and print any problems |

## Where the sets come from

The classic armor sets come from a list built into the addon. Set names come from the game itself. Sets the game doesn't know any items for are left out. `/gs check` shows whether the list still matches the game.

## For developers

The addon is in the `GearSet` folder (`GearSet_Forever.toc`, interface 16001). Settings are saved account-wide in `GearSetDB`.

| File | What it does |
|---|---|
| `Core.lua` | Text, saved settings, slash commands |
| `Theme.lua` | Every look choice (Blizzard templates, atlases, fonts, colours) in one place |
| `SetsData.lua` | The built-in list of classic sets |
| `SourcesData.lua` | The built-in list of where each piece comes from |
| `Data.lua` | Builds, sorts and filters the sets; source lines and report link; `/gs check` |
| `Owned.lua` | Works out whether you have each piece |
| `UI\Main.lua` | The main window |
| `UI\SetList.lua` | The set list, search and filter |
| `UI\Preview.lua` | The character preview |
| `UI\PieceList.lua` | The list of pieces |
| `UI\Minimap.lua` | The minimap button and the Addon Compartment entry |

## Credits

Set, item and source data gathered from Warcraft Wiki (https://warcraft.wiki.gg), whose text is available under CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). World of Warcraft and its content are trademarks and property of Blizzard Entertainment.

## License

Copyright (c) 2026 gettic. All rights reserved. See `LICENSE`.
