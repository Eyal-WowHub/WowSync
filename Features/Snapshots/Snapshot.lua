local _, addon = ...
local Snapshot = addon:NewObject("Snapshot")
Snapshot.__index = Snapshot
local ModuleIds = addon:GetObject("ModuleIds")

local C = LibStub("Contracts-1.0")
local HashedModule = addon.HashedModule
local HashedSnapshot = addon.HashedSnapshot
local Time = addon.Time
local Codec = addon.Codec

-- ProfileStore loads before this file (the Profiles block precedes Snapshots).
-- SnapshotManager loads AFTER, so it is resolved lazily at call time.
local ProfileStore = addon:GetObject("ProfileStore")
local function Manager()
    return addon:GetObject("SnapshotManager")
end

-- Identity caches so exactly one wrapper exists per backing table (weak, so a
-- deleted snapshot's wrapper is collected) and per character head (refreshed in
-- place, so a head keeps its identity across captures).
local storedByRaw = setmetatable({}, { __mode = "k" })
local headByCharKey = {}

--[[
    Snapshot — a live object wrapping one snapshot: either a stored history entry
    or a character's head (its unsaved setup). Feature and UI
    code hold a Snapshot and ask it for intent (notes, pin state, modules,
    preview, apply) without ever touching the stored shape. Factories are
    identity-cached, so one wrapper exists per backing table.

    The wrapped storage shape (owned by the repositories, never handed raw to
    features) is shared by profile history and the per-character undo stack:

        {
            Index,                      -- profile-local identity, assigned by ProfileStore
            Hash,                       -- content fingerprint of the modules
            ModuleHashes,               -- per-module fingerprints keyed by permanent module id
            Timestamp,                  -- moment of creation (Core/Time); drives the subject
            Notes,                      -- optional, editable note (UI tooltip)
            Pinned,                     -- exempt from pruning when true
            Source = { Character, ClassID },
            Modules = { [moduleName] = true },   -- plaintext set of the modules present
            Data,                       -- the captured module data, compressed (Core/Codec)
        }

    The bulky captured data lives compressed in Data; Modules keeps only the
    plaintext set of module names so the UI can list and test membership without
    decompressing. GetModules restores the full { [name] = data } table. When
    compression is unavailable the raw data is kept in Modules and Data is nil.

    Hash is a content fingerprint and the "nothing changed" detector. ProfileStore
    assigns Index; together they form the user-facing selector <hash>#<index>.
    The display subject is derived from Timestamp on demand and is never stored
    or edited.
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

--[[ Data-shape helpers (private; operate on the raw stored table) ]]

-- The full { [moduleName] = capturedData } table a raw snapshot stands for,
-- decompressed from Data. Returns the raw Modules table for snapshots stored
-- uncompressed (heads and the compression-unavailable fallback).
local function DecodeModules(raw)
    if not raw then
        return nil
    end
    if raw.Data == nil then
        return raw.Modules or {}
    end
    return Codec:Decode(raw.Data) or {}
end

-- The plaintext set of module names present in a captured module set.
local function BuildModuleNameSet(modulesData)
    local names = {}
    for name in pairs(modulesData) do
        names[name] = true
    end
    return names
end

-- The sorted module names present in a name-set or a { [name] = data } table.
local function SortedNames(nameSet)
    local names = {}
    if nameSet then
        for name in pairs(nameSet) do
            names[#names + 1] = name
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

-- Backfill a raw snapshot's Hash + ModuleHashes, computing them once for older
-- snapshots that predate ModuleHashes. Returns the hash string and the map.
local function EnsureHashFields(raw)
    if not raw then
        return nil, nil
    end

    if type(raw.ModuleHashes) == "table" then
        -- The combined hash is derived deterministically from ModuleHashes, so a
        -- stored value can be trusted; only recombine when it is missing.
        if type(raw.Hash) ~= "string" then
            raw.Hash = BuildHashedSnapshotFromModuleHashes(raw.ModuleHashes):GetValue()
        end
        return raw.Hash, raw.ModuleHashes
    end

    -- Import duplicates can reference an owner's payload and carry only the
    -- already-computed hash; avoid rehashing a payload-less shell here.
    if raw.Ref ~= nil and raw.Data == nil then
        return raw.Hash, nil
    end

    local hashedSnapshot, moduleHashes = BuildHashedSnapshot(DecodeModules(raw))
    raw.ModuleHashes = moduleHashes
    raw.Hash = hashedSnapshot:GetValue()
    return raw.Hash, raw.ModuleHashes
end

-- The stable "<hash>#<index>" selector of a raw stored snapshot.
local function SelectorOfRaw(raw)
    if not raw then
        return nil
    end
    return ("%s#%s"):format((EnsureHashFields(raw)), raw.Index)
end

--[[ Data-shape API (raw tables; for the persistence + orchestration layer) ]]

-- Fingerprint of a captured module set: its combined hash plus the per-module
-- hash map keyed by permanent module id.
function Snapshot:Fingerprint(modulesData)
    local hashedSnapshot, moduleHashes = BuildHashedSnapshot(modulesData or {})
    return hashedSnapshot:GetValue(), moduleHashes
end

-- The combined content-hash string of a raw stored snapshot.
function Snapshot:HashValue(raw)
    return (EnsureHashFields(raw))
end

-- The decoded { [moduleName] = capturedData } table of a raw stored snapshot.
function Snapshot:GetModules(raw)
    return DecodeModules(raw)
end

-- Human-readable subject of a raw stored snapshot, e.g. "22 Jun 2026 16:47".
function Snapshot:GetSubject(raw)
    return Time:ToShortDisplay(raw and raw.Timestamp)
end

-- The stable "<hash>#<index>" selector of a raw stored snapshot.
function Snapshot:SelectorOf(raw)
    return SelectorOfRaw(raw)
end

--[[ Factories (identity-cached) ]]

-- Mint a new, unsaved snapshot from a captured module set, compressing the data
-- into Data and keeping only the module-name set in Modules. The wrapper is
-- registered so it keeps its identity once its raw table is persisted.
function Snapshot:Create(modulesData, source)
    modulesData = modulesData or {}
    local hash, moduleHashes = self:Fingerprint(modulesData)

    local raw = {
        Hash = hash,
        ModuleHashes = moduleHashes,
        Timestamp = Time:Now(),
        Pinned = false,
        Source = source,
    }

    local encoded = Codec:Encode(modulesData)
    if encoded then
        raw.Modules = BuildModuleNameSet(modulesData)
        raw.Data = encoded
    else
        -- Compression unavailable; keep an independent copy of the raw data so
        -- the snapshot stays detached from the live Current table and usable.
        raw.Modules = DeepCopy(modulesData)
    end

    local snapshot = setmetatable({
        isHead = false,
        raw = raw,
        charKey = source and source.Character,
    }, Snapshot)
    storedByRaw[raw] = snapshot
    return snapshot
end

-- Wrap a stored snapshot table owned by the given character, or nil when raw is
-- nil. Returns the same wrapper for the same table across calls.
function Snapshot:FromStore(charKey, raw)
    if not raw then
        return nil
    end
    local snapshot = storedByRaw[raw]
    if not snapshot then
        snapshot = setmetatable({ isHead = false, raw = raw, charKey = charKey }, Snapshot)
        storedByRaw[raw] = snapshot
    elseif charKey ~= nil then
        snapshot.charKey = charKey
    end
    return snapshot
end

-- Wrap a character's head (its unsaved setup), or nil when nothing is captured
-- for that character.
function Snapshot:FromHead(charKey)
    local headInfo = Manager():GetCharInfo(charKey)
    if not headInfo then
        headByCharKey[charKey] = nil
        return nil
    end
    local snapshot = headByCharKey[charKey]
    if not snapshot then
        snapshot = setmetatable({ isHead = true, charKey = charKey }, Snapshot)
        headByCharKey[charKey] = snapshot
    end
    snapshot.head = headInfo
    return snapshot
end

--[[ Instance: reads ]]

-- The combined content-hash string this snapshot stands for.
local function OwnHashValue(self)
    if self.isHead then
        return self.head.Hash
    end
    return (EnsureHashFields(self.raw))
end

-- True for a character's live head versus a saved snapshot.
function Snapshot:IsHead()
    return self.isHead
end

-- True when this head belongs to the character who is currently connected.
function Snapshot:IsCharacterConnected()
    return self.isHead and self.head.IsConnected or false
end

-- True when this snapshot already matches the logged-in character's live setup,
-- so applying it would change nothing.
function Snapshot:IsUpToDate()
    local currentHead = Manager():GetCharInfo()
    return currentHead ~= nil and OwnHashValue(self) == currentHead.Hash
end

-- The character this snapshot belongs to: its owning profile key, the character
-- it was captured from, and the class it was captured on.
function Snapshot:GetCharacterInfo()
    if self.characterInfo then
        return self.characterInfo
    end

    local info
    if self.isHead then
        info = {
            Key = self.charKey,
            Character = self.charKey,
            ClassID = self.head.ClassID,
        }
    else
        local source = self.raw.Source
        info = {
            Key = self.charKey,
            Character = source and source.Character,
            ClassID = source and source.ClassID,
        }
    end
    self.characterInfo = info
    return info
end

-- The moment the snapshot was captured (a head reports when it was last seen).
function Snapshot:GetTimestamp()
    if self.isHead then
        return self.head.LastSeen
    end
    return self.raw.Timestamp
end

-- The editable note attached to a saved snapshot ("" for a head or when unset).
function Snapshot:GetNotes()
    if self.isHead then
        return ""
    end
    return self.raw.Notes or ""
end

-- True when the snapshot is pinned (exempt from pruning). A head is never pinned.
function Snapshot:IsPinned()
    return (not self.isHead) and self.raw.Pinned or false
end

-- The sorted module names the snapshot carries.
function Snapshot:GetModuleNames()
    if self.isHead then
        return SortedNames(self.head.Modules)
    end
    return SortedNames(self.raw.Modules)
end

-- The "<hash>#<index>" selector for a saved snapshot, or nil for a head.
function Snapshot:GetSelector()
    if self.isHead then
        return nil
    end
    return SelectorOfRaw(self.raw)
end

-- The content fingerprint this snapshot stands for, as a HashedSnapshot.
function Snapshot:GetHash()
    if self.isHead then
        return BuildHashedSnapshotFromModuleHashes(self.head.ModuleHashes)
    end
    EnsureHashFields(self.raw)
    return BuildHashedSnapshotFromModuleHashes(self.raw.ModuleHashes)
end

-- The decoded { [moduleName] = capturedData } table the snapshot carries.
function Snapshot:Modules()
    if self.isHead then
        return self.head.Modules
    end
    return DecodeModules(self.raw)
end

--[[ Instance: writes (validated; no-op on a head) ]]

-- Set the editable note on a saved snapshot.
function Snapshot:SetNotes(text)
    C:IsString(text, 2)
    if self.isHead then
        return
    end
    ProfileStore:SetSnapshotNotes(self.charKey, SelectorOfRaw(self.raw), text)
end

-- Pin a saved snapshot so pruning skips it.
function Snapshot:Pin()
    if self.isHead then
        return
    end
    ProfileStore:PinSnapshot(self.charKey, SelectorOfRaw(self.raw))
end

-- Clear a saved snapshot's pin.
function Snapshot:Unpin()
    if self.isHead then
        return
    end
    ProfileStore:UnpinSnapshot(self.charKey, SelectorOfRaw(self.raw))
end

--[[ Instance: operations ]]

-- Preview applying the snapshot (optionally a module subset) over the logged-in
-- character's current setup.
function Snapshot:Preview(moduleSet, cached)
    if self.isHead then
        if self.head.IsConnected then
            return Manager():PreviewApplySnapshot(self.charKey, nil, moduleSet, cached)
        end
        return Manager():PreviewApplyHeadByCharKey(self.charKey, moduleSet, cached)
    end
    return Manager():PreviewApplySnapshot(self.charKey, SelectorOfRaw(self.raw), moduleSet, cached)
end

-- Apply the snapshot (optionally a module subset) to the logged-in character,
-- pushing a rollback snapshot first. Returns an ApplyResult.
function Snapshot:Apply(strategy, moduleSet)
    if self.isHead then
        return Manager():ApplyHeadByCharKey(self.charKey, strategy, moduleSet)
    end
    return Manager():ApplySnapshot(self.charKey, SelectorOfRaw(self.raw), strategy, moduleSet)
end

-- Permanently remove a saved snapshot from its character's history.
function Snapshot:Delete()
    if self.isHead then
        return
    end
    Manager():DeleteSnapshot(self.charKey, SelectorOfRaw(self.raw))
end

--[[ Persistence boundary (repositories only) ]]

-- The backing plain table, for a repository to store.
function Snapshot:ToStore()
    return self.raw
end
