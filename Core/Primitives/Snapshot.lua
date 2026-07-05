local _, addon = ...
local Snapshot = {}
addon.Snapshot = Snapshot
Snapshot.__index = Snapshot

local C = LibStub("Contracts-1.0")

local SnapshotInfo = addon.SnapshotInfo

-- Identity cache so exactly one wrapper exists per backing snapshotInfo (weak,
-- so a dropped snapshot's wrapper is collected).
local cache = setmetatable({}, { __mode = "k" })

--[[
    Snapshot — the behaviour/identity object wrapping one snapshotInfo (the
    immutable data, owned and built by SnapshotInfo). A Snapshot is either a
    stored history entry or a character's live head; a head is just a snapshot
    that has not been saved. The entity only reads and derives from its data and
    compares against other snapshots — every operation (apply, save, pin, delete)
    lives on a manager that takes a Snapshot. Wrappers are identity-cached, so one
    Snapshot exists per snapshotInfo.
]]

--[[ Factories (identity-cached) ]]

-- Wrap a snapshotInfo (a stored entry or a live head) owned by the given
-- character. Returns the same wrapper per snapshotInfo across calls.
function Snapshot:From(charKey, snapshotInfo)
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

-- Mint a new, unsaved snapshot from a captured module set.
function Snapshot:Create(modulesData, source)
    local snapshotInfo = SnapshotInfo:Create(modulesData, source)
    return self:From(source and source.Character, snapshotInfo)
end

--[[ Instance: reads (data concerns delegate to SnapshotInfo) ]]

-- True for a live head (an unsaved current setup) versus a saved snapshot.
function Snapshot:IsHead()
    return self.info.Live == true
end

-- True when this head is the currently connected character's live setup.
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
        Character = source and source.Character,
        ClassID = source and source.ClassID,
    }
    return self.characterInfo
end

-- The moment the snapshot was captured.
function Snapshot:GetTimestamp()
    return self.info.Timestamp
end

-- Human-readable capture time, e.g. "22 Jun 2026 16:47".
function Snapshot:GetSubject()
    return SnapshotInfo:Subject(self.info)
end

-- The editable note attached to a saved snapshot ("" when unset or a head).
function Snapshot:GetNotes()
    return self.info.Notes or ""
end

-- True when the snapshot is pinned (exempt from pruning). A head is never pinned.
function Snapshot:IsPinned()
    return self.info.Pinned or false
end

-- The sorted module names the snapshot carries.
function Snapshot:GetModuleNames()
    return SnapshotInfo:ModuleNames(self.info)
end

-- The "<hash>#<index>" selector for a saved snapshot, or nil for a head.
function Snapshot:GetSelector()
    return SnapshotInfo:Selector(self.info)
end

-- The combined content-hash string this snapshot stands for.
function Snapshot:HashValue()
    return SnapshotInfo:HashValue(self.info)
end

-- The content fingerprint this snapshot stands for, as a HashedSnapshot.
function Snapshot:GetHash()
    return SnapshotInfo:Hashed(self.info)
end

-- The decoded { [moduleName] = capturedData } table the snapshot carries.
function Snapshot:Modules()
    return SnapshotInfo:Modules(self.info)
end

-- True when this snapshot has the same content as another (same combined hash).
function Snapshot:CompareTo(other)
    Snapshot.Validate(other, 2)
    return self:HashValue() == other:HashValue()
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
