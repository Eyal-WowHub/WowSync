local _, addon = ...
local Snapshot = {}
addon.Snapshot = Snapshot
Snapshot.__index = Snapshot

local C = addon.Contracts
local SnapshotInfo = addon.SnapshotInfo

-- Identity cache so exactly one wrapper exists per backing snapshotInfo (weak,
-- so a dropped snapshot's wrapper is collected).
local cache = setmetatable({}, { __mode = "k" })

--[[
    Snapshot — the behaviour/identity object wrapping one snapshotInfo (the
    immutable data, owned and created by SnapshotInfo). A Snapshot is either a
    stored history entry or the character's live snapshot; the live snapshot is
    just a snapshot that has not been saved. The entity only reads and derives
    from its data and
    compares against other snapshots — every operation (apply, save, pin, delete)
    lives on a manager that takes a Snapshot. Wrappers are identity-cached, so one
    Snapshot exists per snapshotInfo.
]]

--[[ Factories (identity-cached) ]]

-- Create the snapshot wrapping a snapshotInfo (a stored entry or the live
-- snapshot) owned by the given character. Returns the same wrapper per
-- snapshotInfo across calls.
function Snapshot:Create(charKey, snapshotInfo)
    C:Requires(charKey, 2, "string", "nil")
    C:IsTable(snapshotInfo, 3)
    local snapshot = cache[snapshotInfo]
    if not snapshot then
        SnapshotInfo:Validate(snapshotInfo)
        snapshot = setmetatable({ info = snapshotInfo, charKey = charKey }, Snapshot)
        cache[snapshotInfo] = snapshot
    elseif charKey ~= nil and charKey ~= snapshot.charKey then
        snapshot.charKey = charKey
        -- The owner key is baked into the memoized character info; drop it so
        -- the next read rebuilds against the new owner.
        snapshot.characterInfo = nil
    end
    return snapshot
end

-- A saved-shape snapshot from a captured module set.
function Snapshot:FromCapturedModuleSet(modulesData, source)
    local snapshotInfo = SnapshotInfo:CreateForSavedSnapshot(modulesData, source)
    return self:Create(source and source.CharacterName, snapshotInfo)
end

--[[ Instance: reads (data concerns delegate to SnapshotInfo) ]]

-- True for the live snapshot (an unsaved current setup) versus a saved snapshot.
function Snapshot:IsLive()
    return self.info.Live == true
end

-- True when this live snapshot is the currently connected character's live setup.
function Snapshot:IsCharacterConnected()
    return self.info.Connected == true
end

-- The character this snapshot belongs to: its owning profile key, the character
-- it was captured from, and the class it was captured on.
function Snapshot:GetCharacterInfo()
    if self.characterInfo then
        return self.characterInfo
    end
    local source = self.info.Source
    self.characterInfo = {
        Key = self.charKey,
        Character = source and (source.CharacterName or source.Character),
        ClassID = source and source.ClassID,
    }
    return self.characterInfo
end

-- The class id the snapshot was captured on.
function Snapshot:GetClassID()
    return self:GetCharacterInfo().ClassID
end

-- The moment the snapshot was captured.
function Snapshot:GetTimestamp()
    return self.info.Timestamp
end

-- Human-readable capture time, e.g. "22 Jun 2026 16:47".
function Snapshot:GetSubject()
    return SnapshotInfo:Subject(self.info)
end

-- The editable note attached to a saved snapshot ("" when unset or on the live
-- snapshot).
function Snapshot:GetNotes()
    return self.info.Notes or ""
end

-- True when the snapshot is pinned (exempt from pruning). The live snapshot is
-- never pinned.
function Snapshot:IsPinned()
    return self.info.Pinned or false
end

-- The sorted module names the snapshot carries, optionally narrowed to a
-- { [name] = true } subset.
function Snapshot:GetModuleNames(moduleSet)
    return SnapshotInfo:ModuleNames(self.info, moduleSet)
end

-- The "<hash>#<index>" selector for a saved snapshot, or nil for the live snapshot.
function Snapshot:GetSelector()
    return SnapshotInfo:Selector(self.info)
end

-- The profile-local index assigned to a saved snapshot, or nil for the live snapshot.
function Snapshot:GetIndex()
    return self.info.Index
end

-- The combined content-hash string this snapshot stands for.
function Snapshot:HashValue()
    return SnapshotInfo:HashValue(self.info)
end

-- The content fingerprint this snapshot stands for, as a HashedSnapshot.
function Snapshot:GetHash()
    return SnapshotInfo:Hashed(self.info)
end

-- The decoded { [moduleName] = capturedData } table the snapshot carries,
-- optionally narrowed to a { [name] = true } / nested plugin-submodule selection.
function Snapshot:Modules(moduleSet)
    return SnapshotInfo:Modules(self.info, moduleSet)
end

-- True when this snapshot has the same content as another (same combined hash).
function Snapshot:Equals(other)
    Snapshot.Validate(other, 2)
    return self:HashValue() == other:HashValue()
end

-- True when this snapshot is in sync with another: every module it carries is
-- present in the other with identical content, so applying it would change
-- nothing. Compares stored per-module hashes, so neither payload is decoded.
function Snapshot:IsSynchronizedTo(other)
    Snapshot.Validate(other, 2)
    return self:GetHash():IsSubsetOf(other:GetHash())
end

-- Guard that value is a Snapshot, returning it for convenient chaining.
function Snapshot.Validate(value, pos)
    C:Ensures(getmetatable(value) == Snapshot, "bad argument #%d: expected a Snapshot", pos or 1)
    return value
end

--[[ Persistence boundary (repositories only) ]]

-- The backing snapshotInfo, for a repository to store.
function Snapshot:ToStore()
    return self.info
end
