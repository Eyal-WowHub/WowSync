local _, addon = ...
local SnapshotHandleCache = addon:NewObject("SnapshotHandleCache")

--[[
    SnapshotHandleCache — the source of a character's Snapshot objects.

    Resolves a character's snapshots (its head, its latest saved, the one a
    save would evict, or its full ordered timeline) and returns them as Snapshot
    objects. Identity is owned by the Snapshot factories, so repeated lookups
    return the same instance, letting callers track selection across refreshes.
]]

local ProfileStore = addon:GetObject("ProfileStore")
local Snapshot = addon:GetObject("Snapshot")

-- Newest-first ordering: later timestamp wins, index breaks ties.
local function NewerSnapshotFirst(leftSnapshot, rightSnapshot)
    if leftSnapshot.Timestamp ~= rightSnapshot.Timestamp then
        return leftSnapshot.Timestamp > rightSnapshot.Timestamp
    end
    return (leftSnapshot.Index or 0) > (rightSnapshot.Index or 0)
end

-- A character's head, or nil when nothing is captured.
function SnapshotHandleCache:GetHead(charKey)
    return Snapshot:FromHead(charKey)
end

-- A character's most recent saved snapshot, or nil when none exist.
function SnapshotHandleCache:GetLatestSaved(charKey)
    return Snapshot:FromStore(charKey, ProfileStore:GetLatestSnapshot(charKey))
end

-- The snapshot a save would prune, or nil when a save evicts nothing.
function SnapshotHandleCache:GetPendingEviction(charKey)
    return Snapshot:FromStore(charKey, ProfileStore:PendingEviction(charKey))
end

-- The character's full timeline as ordered Snapshot objects: head first, then
-- pinned snapshots newest-first, then un-pinned snapshots newest-first.
function SnapshotHandleCache:GetTimeline(charKey)
    local timeline = {}

    local head = Snapshot:FromHead(charKey)
    if head then
        tinsert(timeline, head)
    end

    local pinnedSnapshots, unpinnedSnapshots = {}, {}
    for _, snapshot in ipairs(ProfileStore:GetSnapshots(charKey)) do
        if snapshot.Pinned then
            tinsert(pinnedSnapshots, snapshot)
        else
            tinsert(unpinnedSnapshots, snapshot)
        end
    end
    table.sort(pinnedSnapshots, NewerSnapshotFirst)
    table.sort(unpinnedSnapshots, NewerSnapshotFirst)

    for _, snapshot in ipairs(pinnedSnapshots) do
        tinsert(timeline, Snapshot:FromStore(charKey, snapshot))
    end
    for _, snapshot in ipairs(unpinnedSnapshots) do
        tinsert(timeline, Snapshot:FromStore(charKey, snapshot))
    end

    return timeline
end
