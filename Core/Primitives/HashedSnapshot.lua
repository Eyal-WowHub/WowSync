local _, addon = ...
local HashedSnapshot = {}
addon.HashedSnapshot = HashedSnapshot
HashedSnapshot.__index = HashedSnapshot

local Hash = addon.Hash
local HashedModule = addon.HashedModule
local ModuleIds = addon:GetObject("ModuleIds")
local C = LibStub("Contracts-1.0")

--[[
    HashedSnapshot — an immutable "hash of hashes" over a set of HashedModules.

    It never touches raw module data: given the per-module hashes it derives one
    value that identifies the whole snapshot. Two snapshots with the same value
    hold identical content; comparing by module reports exactly which modules
    differ, so callers can tell what changed without decoding anything. Modules
    are always walked in ModuleIds' canonical order, so results are deterministic.
]]

-- Combine a list of HashedModule into one snapshot fingerprint. The combined
-- value is order-independent: it is built from each module's id and hash walked
-- in ModuleIds' canonical order, so the same set of module hashes always yields
-- the same value regardless of the input list's order.
function HashedSnapshot:Compute(hashedModules)
    C:IsTable(hashedModules, 2)

    local hashedModuleById = {}
    for _, hashedModule in ipairs(hashedModules) do
        HashedModule.Validate(hashedModule, 2)
        hashedModuleById[hashedModule:GetIdentity()] = hashedModule
    end

    local parts = {}
    for _, id in ModuleIds:IterableIds() do
        local hashedModule = hashedModuleById[id]
        if hashedModule then
            table.insert(parts, id .. "=" .. hashedModule:GetValue())
        end
    end

    return setmetatable({
        hashedModuleById = hashedModuleById,
        value = Hash:Create(table.concat(parts, ";")),
    }, HashedSnapshot)
end

-- The combined hash-of-hashes string.
function HashedSnapshot:GetValue()
    return self.value
end

-- Iterate the per-module hashes as (moduleId, HashedModule) pairs, in ModuleIds'
-- canonical order, skipping ids this snapshot does not carry.
function HashedSnapshot:IterableHashedModules()
    local hashedModuleById = self.hashedModuleById
    local nextId, orderedIds, index = ModuleIds:IterableIds()
    return function()
        while true do
            local nextIndex, id = nextId(orderedIds, index)
            index = nextIndex
            if id == nil then
                return nil
            end
            local hashedModule = hashedModuleById[id]
            if hashedModule then
                return id, hashedModule
            end
        end
    end
end

-- True when other holds identical content (same combined value).
function HashedSnapshot:Compare(other)
    HashedSnapshot.Validate(other, 2)
    return self.value == other.value
end

-- Iterate the ids of modules that differ between this and other: present in both
-- with different hashes, or present in only one. Walks ModuleIds' canonical order
-- and yields each differing id once. Lazy, so a caller can stop at the first
-- difference (e.g. "does anything differ?") without building a set.
function HashedSnapshot:CompareByModules(other)
    HashedSnapshot.Validate(other, 2)

    local mine = self.hashedModuleById
    local theirs = other.hashedModuleById
    local nextId, orderedIds, index = ModuleIds:IterableIds()
    return function()
        while true do
            local nextIndex, id = nextId(orderedIds, index)
            index = nextIndex
            if id == nil then
                return nil
            end
            local mineModule = mine[id]
            local theirsModule = theirs[id]
            if mineModule or theirsModule then
                if not mineModule or not theirsModule or mineModule:GetValue() ~= theirsModule:GetValue() then
                    return id
                end
            end
        end
    end
end

-- Guard that value is a HashedSnapshot, returning it for convenient chaining.
function HashedSnapshot.Validate(value, pos)
    C:Ensures(getmetatable(value) == HashedSnapshot, "bad argument #%d: expected a HashedSnapshot", pos or 1)
    return value
end
