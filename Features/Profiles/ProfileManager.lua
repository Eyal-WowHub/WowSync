local _, addon = ...
local ProfileManager = addon:NewObject("ProfileManager")

local C = LibStub("Contracts-1.0")
local CharacterInfo = LibStub("CharacterInfo-1.0")

local Snapshot = addon.Snapshot
local SnapshotInfo = addon.SnapshotInfo

local CurrentStore = addon:GetObject("CurrentStore")
local ProfileStore = addon:GetObject("ProfileStore")

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

-- Append a snapshot to its character's history: a save always appends, even when
-- nothing changed. Returns the stored Snapshot.
function ProfileManager:AddSnapshot(snapshot, note)
    return ProfileStore:AppendSnapshot(snapshot, note)
end

-- A character's most recent saved snapshot as a Snapshot, or nil when none exist.
function ProfileManager:Latest(charKey)
    return ProfileStore:GetLatestSnapshot(charKey)
end

-- The snapshot a save would prune to stay within the cap (the oldest un-pinned
-- once the history is at/over the cap) as a Snapshot, or nil when a save would
-- evict nothing (under the cap, or every snapshot is pinned).
function ProfileManager:PendingEviction(charKey)
    local snapshots = ProfileStore:GetSnapshots(charKey)
    if #snapshots < ProfileStore:GetMaxSnapshots() then
        return nil
    end
    for index = 1, #snapshots do
        if not snapshots[index]:IsPinned() then
            return snapshots[index]
        end
    end
    return nil
end

-- Order saved snapshots newest-first: a later timestamp wins, index breaks ties.
local function NewerFirst(left, right)
    if left:GetTimestamp() ~= right:GetTimestamp() then
        return left:GetTimestamp() > right:GetTimestamp()
    end
    return (left:GetIndex() or 0) > (right:GetIndex() or 0)
end

-- A character's saved history as Snapshot objects, pinned entries first and
-- newest-first within each group (the order a timeline shows them under the head).
function ProfileManager:GetHistory(charKey)
    local pinned, unpinned = {}, {}
    for _, snapshot in ipairs(ProfileStore:GetSnapshots(charKey)) do
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

    local snapshots = ProfileStore:GetSnapshots(charKey)
    local hash, wantedIndex = SnapshotInfo.ParseSelector(selector)

    if wantedIndex then
        for index = 1, #snapshots do
            local snapshot = snapshots[index]
            if snapshot:GetIndex() == wantedIndex then
                if snapshot:HashValue():sub(1, #hash) == hash then
                    return snapshot
                end
                return nil, "not-found"
            end
        end
        return nil, "not-found"
    end

    local exactMatches = {}
    for index = 1, #snapshots do
        if snapshots[index]:HashValue() == hash then
            tinsert(exactMatches, snapshots[index])
        end
    end
    if #exactMatches > 1 then
        return nil, "ambiguous", exactMatches
    elseif #exactMatches == 1 then
        return exactMatches[1]
    end

    local prefixMatch, candidates
    for index = 1, #snapshots do
        if snapshots[index]:HashValue():sub(1, #hash) == hash then
            if prefixMatch then
                candidates = candidates or { prefixMatch }
                tinsert(candidates, snapshots[index])
            else
                prefixMatch = snapshots[index]
            end
        end
    end
    if candidates then
        return nil, "ambiguous", candidates
    end
    if prefixMatch then
        return prefixMatch
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
    return ProfileStore:RemoveSnapshot(snapshot)
end
