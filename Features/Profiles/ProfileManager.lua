local _, addon = ...
local ProfileManager = addon:NewObject("ProfileManager")

local C = LibStub("Contracts-1.0")
local CharacterInfo = LibStub("CharacterInfo-1.0")
local BoundedList = addon.BoundedList

--[[
    ProfileManager — the business layer over the profile store.

    A profile is one character's record: its saved snapshot history plus the live
    head (its current setup) and the metadata kept alongside them. ProfileManager
    owns the RULES — assigning a snapshot's index, pruning to the cap (protecting
    pinned entries), resolving a selector, the pin/note/delete mutations, and
    producing the character's head and full timeline. It accepts and returns
    Snapshot objects; ProfileStore underneath only stores and retrieves the raw
    records, and CurrentStore holds the live setup a head wraps.
]]

local ProfileStore = addon:GetObject("ProfileStore")
local CurrentStore = addon:GetObject("CurrentStore")
local SnapshotInfo = addon.SnapshotInfo
local Snapshot = addon.Snapshot

-- One stable head snapshotInfo per character, refreshed in place so a head keeps
-- its Snapshot identity across captures.
local headInfoByCharKey = {}

--[[ Profile CRUD ]]

function ProfileManager:GetProfile(profileName)
    return ProfileStore:GetProfile(profileName)
end

function ProfileManager:GetProfiles()
    return ProfileStore:GetProfiles()
end

function ProfileManager:DeleteProfile(profileName)
    C:IsString(profileName, 2)
    return ProfileStore:DeleteProfile(profileName)
end

-- Wipes every character record (saved snapshots, current captures and undo
-- history) while leaving user settings intact. The table is emptied in place so
-- the stores' cached references stay valid; callers are expected to reload the
-- UI afterwards so every view reinitialises from the now-empty database.
function ProfileManager:ResetDatabase()
    wipe(addon.DB.Profiles)
end

--[[ Snapshot history ]]

-- The soft cap on snapshots kept per character profile.
function ProfileManager:GetMaxSnapshots()
    return ProfileStore:GetMaxSnapshots()
end

-- Append a snapshot to its character's history: assign its index, tag the
-- optional note, and prune the oldest un-pinned entries to the cap. A save
-- always appends, even when nothing changed. Returns the stored Snapshot.
function ProfileManager:AddSnapshot(snapshot, note)
    Snapshot.Validate(snapshot, 2)

    local charKey = snapshot:GetCharacterInfo().Character
    local snapshotInfo = snapshot:ToStore()
    if note ~= nil then
        snapshotInfo.Notes = note
    end

    local record = ProfileStore:CreateProfile(charKey)
    snapshotInfo.Index = record.Metadata.NextIndex
    record.Metadata.NextIndex = record.Metadata.NextIndex + 1

    BoundedList:Wrap(record.Snapshots, {
        max = function() return ProfileStore:GetMaxSnapshots() end,
        isProtected = function(entry) return entry.Pinned end,
    }):Push(snapshotInfo)
    return snapshot
end

-- A character's most recent saved snapshot as a Snapshot, or nil when none exist.
function ProfileManager:Latest(charKey)
    local snapshotInfo = ProfileStore:GetLatestSnapshot(charKey)
    if not snapshotInfo then
        return nil
    end
    return Snapshot:From(charKey, snapshotInfo)
end

-- The snapshot a save would prune to stay within the cap (the oldest un-pinned
-- once the history is at/over the cap) as a Snapshot, or nil when a save would
-- evict nothing (under the cap, or every snapshot is pinned).
function ProfileManager:PendingEviction(charKey)
    local record = ProfileStore:GetProfile(charKey)
    if not record then
        return nil
    end

    local snapshots = record.Snapshots
    if #snapshots < ProfileStore:GetMaxSnapshots() then
        return nil
    end
    for index = 1, #snapshots do
        if not snapshots[index].Pinned then
            return Snapshot:From(charKey, snapshots[index])
        end
    end
    return nil
end

-- Order saved snapshots newest-first: a later timestamp wins, index breaks ties.
local function NewerFirst(left, right)
    if left.Timestamp ~= right.Timestamp then
        return left.Timestamp > right.Timestamp
    end
    return (left.Index or 0) > (right.Index or 0)
end

-- A character's saved history as Snapshot objects, pinned entries first and
-- newest-first within each group (the order a timeline shows them under the head).
function ProfileManager:GetHistory(charKey)
    local record = ProfileStore:GetProfile(charKey)
    if not record then
        return {}
    end

    local pinned, unpinned = {}, {}
    for _, snapshotInfo in ipairs(record.Snapshots) do
        if snapshotInfo.Pinned then
            tinsert(pinned, snapshotInfo)
        else
            tinsert(unpinned, snapshotInfo)
        end
    end
    table.sort(pinned, NewerFirst)
    table.sort(unpinned, NewerFirst)

    local history = {}
    for _, snapshotInfo in ipairs(pinned) do
        tinsert(history, Snapshot:From(charKey, snapshotInfo))
    end
    for _, snapshotInfo in ipairs(unpinned) do
        tinsert(history, Snapshot:From(charKey, snapshotInfo))
    end
    return history
end

-- A character's head: its current setup as a live Snapshot (the connected
-- character's is live, an alt's is its last capture), or nil when nothing is
-- captured. A head carries no Index; the companion UI floats it above the saved
-- history as the always-current top of the timeline. The head snapshotInfo is
-- kept and refreshed in place so the head keeps its Snapshot identity across
-- captures.
function ProfileManager:GetHead(charKey)
    charKey = charKey or CharacterInfo:GetFullName()

    local capturedModules = CurrentStore:Get(charKey)
    if not capturedModules or not next(capturedModules) then
        headInfoByCharKey[charKey] = nil
        return nil
    end

    local charMeta = CurrentStore:GetMetadata(charKey)
    local fresh = SnapshotInfo:CreateHead(capturedModules, {
        Character = charKey,
        ClassID = charMeta and charMeta.ClassID,
        LastSeen = charMeta and charMeta.LastSeen,
        Connected = charKey == CharacterInfo:GetFullName(),
    })

    local headInfo = headInfoByCharKey[charKey]
    if headInfo then
        wipe(headInfo)
        for key, value in pairs(fresh) do
            headInfo[key] = value
        end
    else
        headInfo = fresh
        headInfoByCharKey[charKey] = headInfo
    end
    return Snapshot:From(charKey, headInfo)
end

-- A character's full timeline as ordered Snapshot objects: the live head first
-- (when anything is captured), then its saved history (pinned newest-first, then
-- un-pinned newest-first).
function ProfileManager:GetTimeline(charKey)
    charKey = charKey or CharacterInfo:GetFullName()

    local timeline = {}
    local head = self:GetHead(charKey)
    if head then
        tinsert(timeline, head)
    end
    for _, snapshot in ipairs(self:GetHistory(charKey)) do
        tinsert(timeline, snapshot)
    end
    return timeline
end

-- Resolve a selector (<hash>, an unambiguous <hash-prefix>, or <hash>#<index>)
-- within a character's history. Returns a Snapshot, or nil + a reason
-- ("not-found" / "ambiguous") + a list of candidate Snapshots.
function ProfileManager:FindSnapshot(charKey, selector)
    C:IsString(charKey, 2)
    C:IsString(selector, 3)

    local record = ProfileStore:GetProfile(charKey)
    if not record then
        return nil, "not-found"
    end

    local snapshots = record.Snapshots
    local hash, wantedIndex = SnapshotInfo.ParseSelector(selector)

    local function wrap(info) return Snapshot:From(charKey, info) end
    local function hashOf(info) return SnapshotInfo:HashValue(info) end

    if wantedIndex then
        for index = 1, #snapshots do
            local info = snapshots[index]
            if info.Index == wantedIndex then
                if hashOf(info):sub(1, #hash) == hash then
                    return wrap(info)
                end
                return nil, "not-found"
            end
        end
        return nil, "not-found"
    end

    local exactMatches = {}
    for index = 1, #snapshots do
        if hashOf(snapshots[index]) == hash then
            tinsert(exactMatches, snapshots[index])
        end
    end
    if #exactMatches > 1 then
        local candidates = {}
        for i = 1, #exactMatches do
            candidates[i] = wrap(exactMatches[i])
        end
        return nil, "ambiguous", candidates
    elseif #exactMatches == 1 then
        return wrap(exactMatches[1])
    end

    local prefixMatch, candidates
    for index = 1, #snapshots do
        if hashOf(snapshots[index]):sub(1, #hash) == hash then
            if prefixMatch then
                candidates = candidates or { wrap(prefixMatch) }
                tinsert(candidates, wrap(snapshots[index]))
            else
                prefixMatch = snapshots[index]
            end
        end
    end
    if candidates then
        return nil, "ambiguous", candidates
    end
    if prefixMatch then
        return wrap(prefixMatch)
    end
    return nil, "not-found"
end

--[[ Snapshot mutations (take a Snapshot) ]]

-- Pin a saved snapshot so pruning skips it.
function ProfileManager:Pin(snapshot)
    Snapshot.Validate(snapshot, 2)
    snapshot:ToStore().Pinned = true
end

-- Clear a saved snapshot's pin.
function ProfileManager:Unpin(snapshot)
    Snapshot.Validate(snapshot, 2)
    snapshot:ToStore().Pinned = false
end

-- Set the editable note on a saved snapshot.
function ProfileManager:SetNotes(snapshot, text)
    Snapshot.Validate(snapshot, 2)
    C:IsString(text, 3)
    snapshot:ToStore().Notes = text
end

-- Permanently remove a snapshot from its character's history. Returns whether it
-- was found and removed.
function ProfileManager:Remove(snapshot)
    Snapshot.Validate(snapshot, 2)

    local charKey = snapshot:GetCharacterInfo().Key
    local record = ProfileStore:GetProfile(charKey)
    if not record then
        return false
    end

    local snapshotInfo = snapshot:ToStore()
    for index = 1, #record.Snapshots do
        if record.Snapshots[index] == snapshotInfo then
            tremove(record.Snapshots, index)
            return true
        end
    end
    return false
end
