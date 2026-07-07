local _, addon = ...
local Profile = {}
addon.Profile = Profile
Profile.__index = Profile

local C = addon.Contracts
local Snapshot = addon.Snapshot

local CharacterInfo = LibStub("CharacterInfo-1.0")

-- Identity cache so exactly one wrapper exists per backing record (weak, so a
-- deleted character's wrapper is collected).
local cache = setmetatable({}, { __mode = "k" })

--[[
    Profile — the behaviour/identity object wrapping one character's record.

    A character's record (owned by ProfileStore) bundles that character's saved
    snapshot history, its live setup and the metadata kept alongside them. The
    Profile only reads and derives from that record; the RULES over it — appending
    a save, pruning, pinning, resolving a selector — live on ProfileManager, which
    takes and returns Profile and Snapshot objects. Wrappers are identity-cached,
    so one Profile exists per record.
]]

--[[ Factory (identity-cached) ]]

-- Wrap a character's record under the given key. Returns the same wrapper per
-- record across calls.
function Profile:From(charKey, charRecord)
    local profile = cache[charRecord]
    if not profile then
        profile = setmetatable({ charKey = charKey, charRecord = charRecord }, Profile)
        cache[charRecord] = profile
    elseif charKey ~= nil then
        profile.charKey = charKey
    end
    return profile
end

--[[ Instance: reads ]]

-- The profile's key: the full character name it is stored under.
function Profile:Key()
    return self.charKey
end

-- True when this profile belongs to the currently logged-in character.
function Profile:IsCharacterConnected()
    return self.charKey == CharacterInfo:GetFullName()
end

-- True when the character has a captured live snapshot (its current setup, kept
-- so other characters can browse it). A compressed capture is stored as a
-- string; an in-session one as a non-empty table.
function Profile:HasLiveSnapshot()
    local current = self.charRecord.Current
    return type(current) == "string"
        or (type(current) == "table" and next(current) ~= nil)
end

-- True when the character has at least one saved snapshot.
function Profile:HasHistory()
    local snapshots = self.charRecord.Snapshots
    return snapshots ~= nil and #snapshots > 0
end

-- True when the character has neither a captured live snapshot nor saved history.
function Profile:IsEmpty()
    return not self:HasLiveSnapshot() and not self:HasHistory()
end

-- The character's saved history as Snapshot objects, oldest-first.
function Profile:Snapshots()
    local snapshots = {}
    local stored = self.charRecord.Snapshots or {}
    for index = 1, #stored do
        snapshots[index] = Snapshot:From(self.charKey, stored[index])
    end
    return snapshots
end

-- Order saved snapshots newest-first: a later timestamp wins, index breaks ties.
local function NewerFirst(left, right)
    if left:GetTimestamp() ~= right:GetTimestamp() then
        return left:GetTimestamp() > right:GetTimestamp()
    end
    return (left:GetIndex() or 0) > (right:GetIndex() or 0)
end

-- The character's saved history as Snapshot objects, pinned entries first and
-- newest-first within each group (the order a timeline shows them under the live
-- snapshot).
function Profile:GetHistory()
    local pinned, unpinned = {}, {}
    for _, snapshot in ipairs(self:Snapshots()) do
        if snapshot:IsPinned() then
            tinsert(pinned, snapshot)
        else
            tinsert(unpinned, snapshot)
        end
    end
    table.sort(pinned, NewerFirst)
    table.sort(unpinned, NewerFirst)

    local history = {}
    for _, snapshot in ipairs(pinned) do
        tinsert(history, snapshot)
    end
    for _, snapshot in ipairs(unpinned) do
        tinsert(history, snapshot)
    end
    return history
end

-- The character's most recent saved snapshot as a Snapshot, or nil when none exist.
function Profile:GetLatestSnapshot()
    local stored = self.charRecord.Snapshots
    local latest = stored and stored[#stored]
    return latest and Snapshot:From(self.charKey, latest) or nil
end

-- The class id the character was captured on: its recorded metadata, falling
-- back to its latest snapshot's class when the metadata carries none (history
-- kept, live data pruned).
function Profile:GetClassID()
    local metadata = self.charRecord.Metadata
    if metadata and metadata.ClassID then
        return metadata.ClassID
    end
    local latest = self:GetLatestSnapshot()
    return latest and latest:GetClassID() or nil
end

-- The moment the character was last seen: its recorded metadata, falling back to
-- its latest snapshot's timestamp when the metadata carries none.
function Profile:GetLastSeenTime()
    local metadata = self.charRecord.Metadata
    if metadata and metadata.LastSeen then
        return metadata.LastSeen
    end
    local latest = self:GetLatestSnapshot()
    return latest and latest:GetTimestamp() or nil
end

-- Guard that value is a Profile, returning it for convenient chaining.
function Profile.Validate(value, pos)
    C:Ensures(getmetatable(value) == Profile, "bad argument #%d: expected a Profile", pos or 1)
    return value
end

--[[ Persistence boundary (repositories only) ]]

-- The backing record, for a repository to store.
function Profile:ToStore()
    return self.charRecord
end
