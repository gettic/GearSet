-- Gear Set: generic entries (plan sec. 7). Everything the addon tracks has a typed key,
-- "set:<itemSetID>" or "item:<itemID>" (later "pet:", "mount:"), so saved data (hidden sets,
-- goals) carries its type and new types need no migration. Each type has a provider:
--   provider = { Get(id) -> entry, List() -> { entries }, Count(entry) -> have, total }
-- Contract: plans\v1.0.0\beta2-interface.md.
local _, ns = ...

local Entries = { providers = {} }
ns.Entries = Entries

function Entries.Key(etype, id)
    return tostring(etype) .. ":" .. tostring(id)
end

-- "set:204" -> "set", 204 (id as a number when it is one); nil for anything else.
function Entries.Parse(key)
    if type(key) ~= "string" then return nil end
    local etype, id = key:match("^(%a+):(.+)$")
    if not etype then return nil end
    return etype, tonumber(id) or id
end

function Entries.SetKey(set)
    return Entries.Key("set", set.id)
end

function Entries:Register(etype, provider)
    if type(etype) == "string" and type(provider) == "table" then self.providers[etype] = provider end
end

function Entries:Get(key)
    local etype, id = Entries.Parse(key)
    local p = etype and self.providers[etype]
    return p and p.Get and p.Get(id) or nil
end

function Entries:List(etype)
    local p = self.providers[etype]
    return p and p.List and p.List() or {}
end

-- have, total for an entry key (0, 0 when unknown).
function Entries:Count(key)
    local etype = Entries.Parse(key)
    local p = etype and self.providers[etype]
    local entry = p and p.Get and p.Get(select(2, Entries.Parse(key)))
    if not entry or not p.Count then return 0, 0 end
    return p.Count(entry)
end

-- Item sets (Data.lua / Owned.lua).
Entries:Register("set", {
    Get = function(id) return ns.Data:GetSet("c" .. tostring(id)) end,
    List = function() return ns.Data:GetSets() end,
    Count = function(set) return ns.Owned:SetCount(set) end,
})
