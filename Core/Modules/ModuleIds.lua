local _, addon = ...
local ModuleIds = addon:NewObject("ModuleIds")

--[[
    ModuleIds — the append-only registry of permanent module identities.

    Every module has a stable numeric id that never changes once assigned. The
    id, not the name, is a module's true identity: it keys module data in storage
    and caches, and lets a module be renamed without invalidating stored
    snapshots or their hashes. Ids 1-100 are reserved; assigned ids start at 101.

    APPEND ONLY. Never reuse, renumber, or remove an id that has ever shipped —
    doing so would silently rebind old stored data to the wrong module. A new
    module takes the next free number.
]]

-- name -> permanent numeric id.
local ID_BY_NAME = {
    Addons = 101,
    Settings = 102,
    ActionBars = 103,
    Keybindings = 104,
    Macros = 105,
    Talents = 106,
    PvpTalents = 107,
    Chat = 108,
    CombatLog = 109,
}

-- Reverse map id -> name, plus the ids in ascending order. Both built once. The
-- reverse map guards against a duplicate id typo in the manifest, which would
-- otherwise silently bind two names to one id. ORDERED_IDS is derived (not a
-- hardcoded range) so it can never list an id that isn't actually assigned.
local NAME_BY_ID = {}
local ORDERED_IDS = {}
for name, id in pairs(ID_BY_NAME) do
    assert(NAME_BY_ID[id] == nil, ("ModuleIds: id %d is assigned to both '%s' and '%s'"):format(id, NAME_BY_ID[id] or "", name))
    NAME_BY_ID[id] = name
    table.insert(ORDERED_IDS, id)
end
table.sort(ORDERED_IDS)

-- The permanent id for a module name, or nil when the name has no assigned id.
function ModuleIds:GetId(moduleName)
    return ID_BY_NAME[moduleName]
end

-- The module name for a permanent id, or nil when the id is unknown.
function ModuleIds:GetName(moduleId)
    return NAME_BY_ID[moduleId]
end

-- Iterate every assigned id in a stable ascending order — the canonical order
-- for walking modules everywhere, so results never depend on hash-table order.
function ModuleIds:IterableIds()
    return ipairs(ORDERED_IDS)
end
