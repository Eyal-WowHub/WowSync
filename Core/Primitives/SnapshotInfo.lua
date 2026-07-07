local _, addon = ...
local SnapshotInfo = {}
addon.SnapshotInfo = SnapshotInfo

local C = addon.Contracts
local Codec = addon.Codec
local HashedModule = addon.HashedModule
local HashedSnapshot = addon.HashedSnapshot
local ModuleIds = addon.ModuleIds
local Time = addon.Time

--[[
    SnapshotInfo — the immutable data of one snapshot, and the factory that
    creates, validates and derives from it.

    A snapshotInfo is a PLAIN table (no metatable) so it persists to
    SavedVariables unchanged. This object owns everything about that shape: how
    to create it from captured modules (CreateForSavedSnapshot for a saved
    snapshot, CreateForLiveSnapshot for a live snapshot), how to validate it
    (Validate), and how to derive from it (hashing, decoding, selector,
    subject). The Snapshot object
    wraps a snapshotInfo and exposes the read surface; features never touch the
    plain table directly.

    Shape:
        {
            Index,         -- number: profile-local id (saved snapshots only)
            Hash,          -- string: combined content fingerprint
            ModuleHashes,  -- { [moduleId] = "<hex>" }: per-module fingerprints
            Timestamp,     -- number: capture time (drives the display subject)
            Notes,         -- string?: editable note
            Pinned,        -- boolean?: exempt from pruning
            Source = { CharacterName, ClassID },
            Modules,       -- name-set { [name]=true } (compressed) OR full dict
            Data,          -- string?: Codec blob of { [name]=data } (compressed)
            Live,          -- true for the live snapshot (an unsaved current setup)
            Connected,     -- true when the live snapshot belongs to the connected character
        }
]]

-- Deep copy so a snapshot is independent of the live Current table.
local function DeepCopy(sourceValue)
    if type(sourceValue) ~= "table" then
        return sourceValue
    end

    local copy = {}
    for key, innerValue in pairs(sourceValue) do
        copy[key] = DeepCopy(innerValue)
    end
    return copy
end

-- The full { [moduleName] = capturedData } table a snapshotInfo stands for,
-- decompressed from Data. Returns the plaintext Modules table for snapshots
-- stored uncompressed (the live snapshot and the compression-unavailable fallback).
local function DecodeModules(snapshotInfo)
    if snapshotInfo.Data == nil then
        return snapshotInfo.Modules or {}
    end
    return Codec:Decode(snapshotInfo.Data) or {}
end

-- The plaintext set of module names present in a captured module set.
local function BuildModuleNameSet(modulesData)
    local names = {}
    for name in pairs(modulesData) do
        names[name] = true
    end
    return names
end

-- The sorted module names present in a name-set or a { [name] = data } table,
-- optionally narrowed to a { [name] = true } subset.
local function SortedNames(nameSet, moduleSet)
    local names = {}
    if nameSet then
        for name in pairs(nameSet) do
            if not moduleSet or moduleSet[name] then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    return names
end

local function BuildHashedSnapshot(modulesData)
    local hashedModules = {}
    local moduleHashes = {}

    for name, moduleData in pairs(modulesData or {}) do
        local moduleId = ModuleIds:GetId(name)
        if moduleId then
            local hashedModule = HashedModule:Compute(moduleId, moduleData)
            moduleHashes[moduleId] = hashedModule:GetValue()
            hashedModules[#hashedModules + 1] = hashedModule
        end
    end

    return HashedSnapshot:Compute(hashedModules), moduleHashes
end

local function BuildHashedSnapshotFromModuleHashes(moduleHashes)
    local hashedModules = {}

    for moduleId, hashValue in pairs(moduleHashes or {}) do
        local numericId = tonumber(moduleId)
        if numericId and type(hashValue) == "string" and ModuleIds:GetName(numericId) ~= nil then
            hashedModules[#hashedModules + 1] = HashedModule:From(numericId, hashValue)
        end
    end

    return HashedSnapshot:Compute(hashedModules)
end

-- Backfill a snapshotInfo's Hash + ModuleHashes, computing them once for older
-- snapshots that predate ModuleHashes. Returns the hash string and the map.
local function EnsureHashFields(snapshotInfo)
    if type(snapshotInfo.ModuleHashes) == "table" then
        -- The combined hash is derived deterministically from ModuleHashes, so a
        -- stored value can be trusted; only recombine when it is missing.
        if type(snapshotInfo.Hash) ~= "string" then
            snapshotInfo.Hash = BuildHashedSnapshotFromModuleHashes(snapshotInfo.ModuleHashes):GetValue()
        end
        return snapshotInfo.Hash, snapshotInfo.ModuleHashes
    end

    -- Import duplicates can reference an owner's payload and carry only the
    -- already-computed hash; avoid rehashing a payload-less shell here.
    if snapshotInfo.Ref ~= nil and snapshotInfo.Data == nil then
        return snapshotInfo.Hash, nil
    end

    local hashedSnapshot, moduleHashes = BuildHashedSnapshot(DecodeModules(snapshotInfo))
    snapshotInfo.ModuleHashes = moduleHashes
    snapshotInfo.Hash = hashedSnapshot:GetValue()
    return snapshotInfo.Hash, snapshotInfo.ModuleHashes
end

--[[ Construction ]]

-- Fingerprint of a captured module set: its combined hash plus the per-module
-- hash map keyed by permanent module id.
function SnapshotInfo:Fingerprint(modulesData)
    C:IsTable(modulesData, 2)
    local hashedSnapshot, moduleHashes = BuildHashedSnapshot(modulesData)
    return hashedSnapshot:GetValue(), moduleHashes
end

-- Create the immutable data of a new saved snapshot from a captured module set,
-- compressing it into Data and keeping only the module-name set in Modules.
function SnapshotInfo:CreateForSavedSnapshot(modulesData, source)
    C:IsTable(modulesData, 2)
    C:IsTable(source, 3)

    local hash, moduleHashes = self:Fingerprint(modulesData)
    local snapshotInfo = {
        Hash = hash,
        ModuleHashes = moduleHashes,
        Timestamp = Time:Now(),
        Pinned = false,
        Source = source,
    }

    local encoded = Codec:Encode(modulesData)
    if encoded then
        snapshotInfo.Modules = BuildModuleNameSet(modulesData)
        snapshotInfo.Data = encoded
    else
        -- Compression unavailable; keep an independent copy of the raw data so
        -- the snapshot stays detached from the live Current table and usable.
        snapshotInfo.Modules = DeepCopy(modulesData)
    end
    return snapshotInfo
end

-- Create the immutable data of a character's live snapshot from its captured
-- modules. A live snapshot is uncompressed and carries no Index; Live marks it
-- unsaved and Connected marks it as the currently connected character's setup.
-- metadata is { CharacterName, ClassID, LastSeen, Connected }.
function SnapshotInfo:CreateForLiveSnapshot(modulesData, metadata)
    C:IsTable(modulesData, 2)
    C:IsTable(metadata, 3)

    local hash, moduleHashes = self:Fingerprint(modulesData)
    return {
        Hash = hash,
        ModuleHashes = moduleHashes,
        Timestamp = metadata.LastSeen,
        Source = { CharacterName = metadata.CharacterName, ClassID = metadata.ClassID },
        Modules = modulesData,
        Live = true,
        Connected = metadata.Connected or false,
    }
end

-- Assert a value is a well-formed snapshotInfo, returning it for chaining.
function SnapshotInfo:Validate(snapshotInfo)
    C:IsTable(snapshotInfo, 2)
    C:Ensures(type(snapshotInfo.Modules) == "table", "SnapshotInfo: missing Modules table")
    C:Ensures(type(snapshotInfo.Source) == "table", "SnapshotInfo: missing Source table")
    return snapshotInfo
end

--[[ Derivations ]]

-- The combined content-hash string (backfilled once for older snapshots).
function SnapshotInfo:HashValue(snapshotInfo)
    return (EnsureHashFields(snapshotInfo))
end

-- The content fingerprint as a HashedSnapshot value object.
function SnapshotInfo:Hashed(snapshotInfo)
    EnsureHashFields(snapshotInfo)
    return BuildHashedSnapshotFromModuleHashes(snapshotInfo.ModuleHashes)
end

-- The decoded { [moduleName] = capturedData } table.
function SnapshotInfo:Modules(snapshotInfo)
    return DecodeModules(snapshotInfo)
end

-- The sorted module names present, without decompressing.
function SnapshotInfo:ModuleNames(snapshotInfo, moduleSet)
    return SortedNames(snapshotInfo.Modules, moduleSet)
end

-- The "<hash>#<index>" selector of a saved snapshot, or nil for the live snapshot (no Index).
function SnapshotInfo:Selector(snapshotInfo)
    if snapshotInfo.Index == nil then
        return nil
    end
    return ("%s#%s"):format((EnsureHashFields(snapshotInfo)), snapshotInfo.Index)
end

-- Human-readable capture time, e.g. "22 Jun 2026 16:47".
function SnapshotInfo:Subject(snapshotInfo)
    return Time:ToShortDisplay(snapshotInfo.Timestamp)
end

-- Split a selector string into its lowercased hash (or prefix) and optional
-- #index. Returns hash, index (index nil when the selector carries none).
function SnapshotInfo.ParseSelector(selector)
    local hash, indexText = selector:match("^([%w]+)#(%d+)$")
    if indexText then
        return hash:lower(), tonumber(indexText)
    end
    return selector:lower(), nil
end
