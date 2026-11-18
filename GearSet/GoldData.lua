-- Data gathered from Warcraft Wiki (https://warcraft.wiki.gg), CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). Facts only; game content (c) Blizzard Entertainment.
-- Gear Set: fixed in-game gold costs of set pieces (no auction prices; crafting materials not priced).
-- quest[quest name] = whole gold the quest (or its step) asks for; counted once per set by Gold.lua.
-- piece[itemID]     = whole gold for one piece bought from a vendor.
-- Quest gold already in GuideData (`gold|n` rows) is read from there too; an entry here wins.
local _, ns = ...

ns.GoldData = {
  v = 1,
  quest = {
    ["An Earnest Proposition"] = 20,     -- Dungeon Set 2 bracers
    ["Just Compensation"] = 80,          -- Dungeon Set 2 belt + gloves step
    ["Saving the Best for Last"] = 120,  -- Dungeon Set 2 helm + chest step (Hallowed Brazier)
    ["Bonescythe Helmet"] = 75,
    ["Bonescythe Legplates"] = 100,
    ["Bonescythe Sabatons"] = 25,
    ["Bonescythe Waistguard"] = 15,
  },
  piece = {
  },
}
