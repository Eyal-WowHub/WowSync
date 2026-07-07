local _, addon = ...
local HashedSnapshot = {}
addon.HashedSnapshot = HashedSnapshot
HashedSnapshot.__index = HashedSnapshot

local C = addon.Contracts
local Hash = addon.Hash
local HashedModule = addon.HashedModule
local ModuleIds = addon.ModuleIds

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

-- True when every module this snapshot carries is present in other with an
-- identical hash; a module missing from other, or holding a different hash,
-- makes it false. Modules other carries that this one lacks are ignored.
-- Compares stored hashes only, so neither snapshot is decoded.
function HashedSnapshot:IsSubsetOf(other)
    HashedSnapshot.Validate(other, 2)

    local this = self.hashedModuleById
    local theirs = other.hashedModuleById
    for _, id in ModuleIds:IterableIds() do
        local module = this[id]
        if module then
            local theirsModule = theirs[id]
            if not theirsModule or module:GetValue() ~= theirsModule:GetValue() then
                return false
            end
        end
    end
    return true
end

-- Guard that value is a HashedSnapshot, returning it for convenient chaining.
function HashedSnapshot.Validate(value, pos)
    C:Ensures(getmetatable(value) == HashedSnapshot, "bad argument #%d: expected a HashedSnapshot", pos or 1)
    return value
end
