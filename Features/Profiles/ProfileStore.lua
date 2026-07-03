local _, addon = ...
local ProfileStore = addon:NewObject("ProfileStore")

local BoundedList = addon.BoundedList

--[[
    ProfileStore — one record per character, owning that character's history.

    A character's record lives under DB.Profiles[profileName], keyed by its full name. It
    bundles everything stored for that character:

        {
            Metadata  = { Created, NextIndex, ClassID, LastSeen },
            Current   = <live setup; owned by CurrentStore>,
            Undo      = { <rollback snapshot>, ... }, -- owned by UndoStore
            Snapshots = { <snapshot>, ... },          -- the saved history
        }

    ProfileStore owns the record's shell (it creates the canonical shape) and the
    Snapshots history; CurrentStore and UndoStore fill in Current and Undo on the
    same record. Every save appends a snapshot; notes belong to the snapshot (its
    Notes), not the record. Snapshots are ordered oldest-first (newest appended at
    the end); each entry has the Snapshot shape (Hash + Timestamp + Modules + ...).
    A save always appends, even when nothing changed since the last one. The
    history is kept near Settings.MaxSnapshots by pruning the oldest UN-pinned
    snapshots first; pinned snapshots are never pruned, so a record with many pins
    can hold more than MaxSnapshots (a soft cap).
]]

local Time = addon.Time

local DEFAULT_MAX_SNAPSHOTS = 20

local profiles

local function ParseSelector(selector)
    local hash, indexText = selector:match("^([%w]+)#(%d+)$")
    if indexText then
        return hash:lower(), tonumber(indexText)
    end
    return selector:lower(), nil
end

local function SnapshotHash(snapshot)
    local snapshotObject = addon:GetObject("Snapshot")
    if snapshotObject and snapshotObject.HashValue then
        return snapshotObject:HashValue(snapshot)
    end
    return snapshot and snapshot.Hash
end

local function EnsureMetadata(profile)
    profile.Metadata = profile.Metadata or profile.Meta or {}
    profile.Meta = nil

    local metadata = profile.Metadata
    local snapshots = profile.Snapshots or {}
    profile.Snapshots = snapshots

    local maxIndex = 0
    for index = 1, #snapshots do
        local snapshotIndex = tonumber(snapshots[index].Index)
        if snapshotIndex then
            snapshots[index].Index = snapshotIndex
            if snapshotIndex > maxIndex then
                maxIndex = snapshotIndex
            end
        end
    end

    for index = 1, #snapshots do
        if not tonumber(snapshots[index].Index) then
            maxIndex = maxIndex + 1
            snapshots[index].Index = maxIndex
        end
    end

    local nextIndex = tonumber(metadata.NextIndex)
    if not nextIndex or nextIndex <= maxIndex then
        metadata.NextIndex = maxIndex + 1
    else
        metadata.NextIndex = nextIndex
    end

    return metadata
end

-- The soft cap on snapshots per profile (pinned snapshots may exceed it).
local function GetMaxSnapshotsSetting()
    return addon.DB.Settings.MaxSnapshots or DEFAULT_MAX_SNAPSHOTS
end

-- Resolve a snapshot by exact hash/prefix, optionally disambiguated by #Index.
-- Returns snapshot, array index — or nil, nil, reason, candidates.
local function FindSnapshot(profile, selector)
    EnsureMetadata(profile)
    local snapshots = profile.Snapshots
    local hash, snapshotIndex = ParseSelector(selector)

    if snapshotIndex then
        for index = 1, #snapshots do
            local snapshot = snapshots[index]
            if snapshot.Index == snapshotIndex then
                if SnapshotHash(snapshot):sub(1, #hash) == hash then
                    return snapshot, index
                end
                return nil, nil, "not-found"
            end
        end
        return nil, nil, "not-found"
    end

    local exactMatches = {}
    for index = 1, #snapshots do
        if SnapshotHash(snapshots[index]) == hash then
            tinsert(exactMatches, snapshots[index])
        end
    end

    if #exactMatches > 1 then
        return nil, nil, "ambiguous", exactMatches
    elseif #exactMatches == 1 then
        local snapshot = exactMatches[1]
        for index = 1, #snapshots do
            if snapshots[index] == snapshot then
                return snapshot, index
            end
        end
    end

    -- Otherwise accept a single prefix match; more than one is ambiguous.
    local prefixMatch, prefixIndex, candidates
    for index = 1, #snapshots do
        if SnapshotHash(snapshots[index]):sub(1, #hash) == hash then
            if prefixMatch then
                candidates = candidates or { prefixMatch }
                tinsert(candidates, snapshots[index])
            else
                prefixMatch, prefixIndex = snapshots[index], index
            end
        end
    end

    if candidates then
        return nil, nil, "ambiguous", candidates
    end

    if prefixMatch then
        return prefixMatch, prefixIndex
    end
    return nil, nil, "not-found"
end

function ProfileStore:OnInitialized()
    profiles = addon.DB.Profiles
    for _, profile in pairs(profiles) do
        EnsureMetadata(profile)
    end
end

--[[ Profile CRUD ]]

-- Create the character's record if it does not exist, ensuring the canonical
-- shape (Metadata + Current + Undo + Snapshots); returns it either way.
function ProfileStore:CreateProfile(profileName)
    local profile = profiles[profileName]
    if not profile then
        profile = {
            Metadata = { Created = Time:Now(), NextIndex = 1 },
            Current = {},
            Undo = {},
            Snapshots = {},
        }
        profiles[profileName] = profile
    else
        profile.Current = profile.Current or {}
        profile.Undo = profile.Undo or {}
        EnsureMetadata(profile)
    end
    return profile
end

function ProfileStore:GetProfile(profileName)
    if profiles[profileName] then
        EnsureMetadata(profiles[profileName])
    end
    return profiles[profileName]
end

function ProfileStore:GetProfiles()
    for _, profile in pairs(profiles) do
        EnsureMetadata(profile)
    end
    return profiles
end

function ProfileStore:DeleteProfile(profileName)
    if profiles[profileName] then
        profiles[profileName] = nil
        return true
    end
    return false
end

--[[ Snapshot history ]]

-- Append a snapshot to a profile, creating the profile if needed. Always stores
-- the snapshot (a save is a save, even when nothing changed) and returns it.
function ProfileStore:AddSnapshot(profileName, snapshot)
    local profile = self:CreateProfile(profileName)
    local snapshots = profile.Snapshots

    local metadata = EnsureMetadata(profile)
    snapshot.Index = metadata.NextIndex
    metadata.NextIndex = metadata.NextIndex + 1

    BoundedList:Wrap(snapshots, {
        max = GetMaxSnapshotsSetting,
        isProtected = function(snapshotEntry) return snapshotEntry.Pinned end,
    }):Push(snapshot)
    return snapshot
end

-- The soft cap on snapshots per profile.
function ProfileStore:GetMaxSnapshots()
    return GetMaxSnapshotsSetting()
end

-- The snapshot a save would prune to stay within the cap: the oldest un-pinned
-- snapshot once the history is at (or over) MaxSnapshots. Returns nil when a
-- save would evict nothing (under the cap, or every snapshot is pinned).
function ProfileStore:PendingEviction(profileName)
    local profile = profiles[profileName]
    if not profile then
        return nil
    end

    EnsureMetadata(profile)
    local snapshots = profile.Snapshots
    if #snapshots < GetMaxSnapshotsSetting() then
        return nil
    end

    for index = 1, #snapshots do
        if not snapshots[index].Pinned then
            return snapshots[index]
        end
    end
    return nil
end

function ProfileStore:GetLatestSnapshot(profileName)
    local profile = profiles[profileName]
    if not profile then
        return nil
    end
    EnsureMetadata(profile)
    return profile.Snapshots[#profile.Snapshots]
end

-- The profile's saved snapshot history, oldest-first (empty when none).
function ProfileStore:GetSnapshots(profileName)
    local profile = profiles[profileName]
    if not profile then
        return {}
    end
    EnsureMetadata(profile)
    return profile.Snapshots
end

function ProfileStore:GetSnapshot(profileName, selector)
    local profile = profiles[profileName]
    if not profile then
        return nil, "not-found"
    end
    local snapshot, _, reason, candidates = FindSnapshot(profile, selector)
    return snapshot, reason, candidates
end

function ProfileStore:DeleteSnapshot(profileName, selector)
    local profile = profiles[profileName]
    if not profile then
        return false
    end

    local _, index = FindSnapshot(profile, selector)
    if not index then
        return false
    end

    tremove(profile.Snapshots, index)
    return true
end

function ProfileStore:SetSnapshotNotes(profileName, selector, text)
    local profile = profiles[profileName]
    if not profile then
        return false
    end

    local snapshot = FindSnapshot(profile, selector)
    if not snapshot then
        return false
    end

    snapshot.Notes = text
    return true
end

function ProfileStore:PinSnapshot(profileName, selector)
    local profile = profiles[profileName]
    if not profile then
        return false
    end

    local snapshot = FindSnapshot(profile, selector)
    if not snapshot then
        return false
    end

    snapshot.Pinned = true
    return true
end

function ProfileStore:UnpinSnapshot(profileName, selector)
    local profile = profiles[profileName]
    if not profile then
        return false
    end

    local snapshot = FindSnapshot(profile, selector)
    if not snapshot then
        return false
    end

    snapshot.Pinned = false
    return true
end
