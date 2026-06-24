local _, addon = ...
local Snapshot = addon:NewObject("Snapshot")

local Hash = addon.Hash
local Time = addon.Time

--[[
    Snapshot helper (pure, stateless).

    Builds and reads the snapshot table shape shared by profile history and the
    per-character undo stack:

        {
            Index,                      -- profile-local identity, assigned by ProfileStore
            Hash,                       -- content fingerprint of Modules (Core/Hash)
            Timestamp,                  -- moment of creation (Core/Time); drives the subject
            Body,                       -- optional, editable note (UI tooltip)
            Pinned,                     -- exempt from pruning when true
            Source = { Character, ClassID },
            Modules = { [moduleName] = capturedData },
        }

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

-- Build an independent snapshot from a captured module set.
function Snapshot:New(modules, source)
    local copied = DeepCopy(modules) or {}
    return {
        Hash = Hash:Create(copied),
        Timestamp = Time:Now(),
        Pinned = false,
        Source = source,
        Modules = copied,
    }
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
