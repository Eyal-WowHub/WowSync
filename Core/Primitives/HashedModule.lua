local _, addon = ...
local HashedModule = {}
addon.HashedModule = HashedModule
HashedModule.__index = HashedModule

local Hash = addon.Hash
local ModuleIds = addon.ModuleIds
local C = LibStub("Contracts-1.0")

--[[
    HashedModule — an immutable content fingerprint of one module, tagged with
    the permanent id of the module it belongs to.

    The id makes the fingerprint self-identifying: a comparison can insist that
    two hashes describe the same module, so module X's hash is never mistaken for
    module Y's. Build one by hashing raw module data (Compute) or by wrapping a
    hash already computed elsewhere, such as one read back from storage (From).
]]

-- Reject a module id that is not a registered ModuleIds identity, so a
-- HashedModule always carries a real id. Without this an unknown id would be
-- silently dropped when a HashedSnapshot walks the canonical id order, which
-- could make two different snapshots look identical.
local function AssertRegisteredId(moduleId)
    C:IsNumber(moduleId, 2)
    C:Ensures(ModuleIds:GetName(moduleId) ~= nil, "HashedModule: unknown module id %d", moduleId)
end

-- Fingerprint moduleData and tag it with its owning module id.
function HashedModule:Compute(moduleId, moduleData)
    AssertRegisteredId(moduleId)
    return setmetatable({ identity = moduleId, value = Hash:Create(moduleData) }, HashedModule)
end

-- Wrap an already-computed hash for a module id without hashing anything.
function HashedModule:From(moduleId, hashValue)
    AssertRegisteredId(moduleId)
    C:IsString(hashValue, 3)
    return setmetatable({ identity = moduleId, value = hashValue }, HashedModule)
end

-- The hash string.
function HashedModule:GetValue()
    return self.value
end

-- The permanent id of the module this hash belongs to.
function HashedModule:GetIdentity()
    return self.identity
end

-- True when other is the same module's hash with the same value. Comparing two
-- different modules' hashes is a programming error and is rejected.
function HashedModule:Compare(other)
    HashedModule.Validate(other, 2)
    C:Ensures(self.identity == other.identity, "HashedModule:Compare: identity mismatch (%d vs %d)", self.identity, other.identity)
    return self.value == other.value
end

-- Guard that value is a HashedModule, returning it for convenient chaining.
function HashedModule.Validate(value, pos)
    C:Ensures(getmetatable(value) == HashedModule, "bad argument #%d: expected a HashedModule", pos or 1)
    return value
end
