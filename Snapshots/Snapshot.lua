local _, addon = ...
local Snapshot = addon:NewObject("Snapshot")

local Hash = addon.Hash
local Time = addon.Time
local Codec = addon.Codec

--[[
    Snapshot helper (pure, stateless).

    Builds and reads the snapshot table shape shared by profile history and the
    per-character undo stack:

        {
            Index,                      -- profile-local identity, assigned by ProfileStore
            Hash,                       -- content fingerprint of the modules (Core/Hash)
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

    Hash is a content fingerprint and the "nothing changed" detector (a save
    whose Hash equals the profile's latest snapshot is skipped). ProfileStore
    assigns Index; together they form the user-facing selector <hash>#<index>.
    The display subject is derived from Timestamp on demand and is never stored
    or edited.
]]

-- Deep copy so a snapshot is independent of the live Current table.
local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, inner in pairs(value) do
        copy[key] = DeepCopy(inner)
    end
    return copy
end

--[[ API ]]

-- Fingerprint of a captured module set (without building a full snapshot).
function Snapshot:Fingerprint(modules)
    return Hash:Create(modules or {})
end

-- The plaintext set of module names present in a captured module set.
local function NameSet(modules)
    local names = {}
    for name in pairs(modules) do
        names[name] = true
    end
    return names
end

-- Build an independent snapshot from a captured module set, compressing the
-- captured data into Data and keeping only the module-name set in Modules.
function Snapshot:New(modules, source)
    modules = modules or {}
    local snapshot = {
        Hash = Hash:Create(modules),
        Timestamp = Time:Now(),
        Pinned = false,
        Source = source,
    }

    local encoded = Codec:Encode(modules)
    if encoded then
        -- Hash, Encode and NameSet only read the source, so the compressed Data
        -- and the name set are already independent of the live Current table.
        snapshot.Modules = NameSet(modules)
        snapshot.Data = encoded
    else
        -- Compression unavailable; keep an independent copy of the raw data so
        -- the snapshot stays detached from the live Current table and usable.
        snapshot.Modules = DeepCopy(modules)
    end
    return snapshot
end

-- The full { [moduleName] = capturedData } table a snapshot stands for,
-- decompressed from Data. Returns the raw Modules table for snapshots that were
-- stored uncompressed (heads and the compression-unavailable fallback).
function Snapshot:GetModules(snapshot)
    if not snapshot then
        return nil
    end
    if snapshot.Data == nil then
        return snapshot.Modules or {}
    end
    return Codec:Decode(snapshot.Data) or {}
end

-- The sorted list of module names a snapshot contains, read from the plaintext
-- name set without decompressing the captured data.
function Snapshot:GetModuleNames(snapshot)
    local names = {}
    if snapshot and snapshot.Modules then
        for name in pairs(snapshot.Modules) do
            tinsert(names, name)
        end
    end
    table.sort(names)
    return names
end

-- Human-readable subject, e.g. "22 Jun 2026 16:47" (derived, not stored).
function Snapshot:GetSubject(snapshot)
    return Time:ToShortDisplay(snapshot and snapshot.Timestamp)
end

-- Stable user-facing selector for commands and UI actions.
function Snapshot:GetSelector(snapshot)
    if not snapshot then
        return nil
    end
    return ("%s#%s"):format(snapshot.Hash, snapshot.Index)
end
