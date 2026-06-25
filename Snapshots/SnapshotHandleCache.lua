local _, addon = ...
local SnapshotHandleCache = addon:NewObject("SnapshotHandleCache")

--[[
    SnapshotHandleCache — the source of stable snapshot handles.

    Resolves a character's snapshots (its live head, its latest saved, the one a
    save would evict, or its full ordered timeline) and returns them as opaque
    handles. Handles are cached per underlying snapshot so repeated lookups
    return the same instance, letting callers track selection by identity across
    refreshes.

    A handle stands for either a stored snapshot or a character's live "head"
    (its current, unsaved setup). SnapshotView interprets a handle; this object
    produces it.
]]

-- Cache of handles by their underlying snapshot, weak so deleted snapshots'
-- handles are collected. Head handles are cached per character and refreshed in
-- place, so a character's head keeps the same identity across captures.
local storedHandles = setmetatable({}, { __mode = "k" })
local headHandles = {}

local ProfileStore = addon:GetObject("ProfileStore")
local SnapshotManager = addon:GetObject("SnapshotManager")

-- Newest-first ordering: later timestamp wins, index breaks ties.
local function NewerFirst(a, b)
    if a.Timestamp ~= b.Timestamp then
        return a.Timestamp > b.Timestamp
    end
    return (a.Index or 0) > (b.Index or 0)
end

-- A stable handle for a stored snapshot owned by the given character.
local function EnsureStoredHandle(snapshot, charKey)
    if not snapshot then
        return nil
    end
    local handle = storedHandles[snapshot]
    if not handle then
        handle = { isHead = false, raw = snapshot, charKey = charKey }
        storedHandles[snapshot] = handle
    else
        handle.charKey = charKey
    end
    return handle
end

-- A stable handle for a character's live head, or nil when nothing is captured.
function SnapshotHandleCache:GetHead(charKey)
    local head = SnapshotManager:GetCharInfo(charKey)
    if not head then
        headHandles[charKey] = nil
        return nil
    end
    local handle = headHandles[charKey]
    if not handle then
        handle = { isHead = true, charKey = charKey }
        headHandles[charKey] = handle
    end
    handle.head = head
    return handle
end

-- A character's most recent saved snapshot as a handle, or nil when none exist.
function SnapshotHandleCache:GetLatestSaved(charKey)
    return EnsureStoredHandle(ProfileStore:GetLatestSnapshot(charKey), charKey)
end

-- The snapshot a save would prune as a handle, or nil when a save evicts nothing.
function SnapshotHandleCache:GetPendingEviction(charKey)
    return EnsureStoredHandle(ProfileStore:PendingEviction(charKey), charKey)
end

-- The character's full timeline as ordered handles: head first, then pinned
-- snapshots newest-first, then un-pinned snapshots newest-first.
function SnapshotHandleCache:GetTimeline(charKey)
    local handles = {}

    local head = self:GetHead(charKey)
    if head then
        tinsert(handles, head)
    end

    local pinned, history = {}, {}
    for _, snapshot in ipairs(ProfileStore:GetSnapshots(charKey)) do
        if snapshot.Pinned then
            tinsert(pinned, snapshot)
        else
            tinsert(history, snapshot)
        end
    end
    table.sort(pinned, NewerFirst)
    table.sort(history, NewerFirst)

    for _, snapshot in ipairs(pinned) do
        tinsert(handles, EnsureStoredHandle(snapshot, charKey))
    end
    for _, snapshot in ipairs(history) do
        tinsert(handles, EnsureStoredHandle(snapshot, charKey))
    end

    return handles
end
