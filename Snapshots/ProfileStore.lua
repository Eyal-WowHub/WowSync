local _, addon = ...
local ProfileStore = addon:NewObject("ProfileStore")

local BoundedList = addon.BoundedList

--[[
    ProfileStore — one profile per character, each a history of snapshots.

    A profile lives under DB.global.Profiles[id], keyed by the owning character's
    full name (one profile per character):

        { Metadata = { Created, NextIndex }, Snapshots = { <snapshot>, ... } }

    Every save appends a snapshot; notes belong to the snapshot (its Body), not
    the profile. Snapshots are ordered oldest-first (newest appended at the
    end); each entry
    has the Snapshot shape (Hash + Timestamp + Modules + ...). A save always
    appends, even when nothing changed since the last one. The history is kept
    near Settings.MaxSnapshots by pruning the
    oldest UN-pinned snapshots first; pinned snapshots are never pruned, so a
    profile with many pins can hold more than MaxSnapshots (a soft cap).
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
local function MaxSnapshots()
    return addon.DB.global.Settings.MaxSnapshots or DEFAULT_MAX_SNAPSHOTS
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
                if snapshot.Hash:sub(1, #hash) == hash then
                    return snapshot, index
                end
                return nil, nil, "not-found"
            end
        end
        return nil, nil, "not-found"
    end

    local exactMatches = {}
    for index = 1, #snapshots do
        if snapshots[index].Hash == hash then
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
    local match, matchIndex, candidates
    for index = 1, #snapshots do
        if snapshots[index].Hash:sub(1, #hash) == hash then
            if match then
                candidates = candidates or { match }
                tinsert(candidates, snapshots[index])
            else
                match, matchIndex = snapshots[index], index
            end
        end
    end

    if candidates then
        return nil, nil, "ambiguous", candidates
    end

    if match then
        return match, matchIndex
    end
    return nil, nil, "not-found"
end

function ProfileStore:OnInitialized()
    profiles = addon.DB.global.Profiles
    for _, profile in pairs(profiles) do
        EnsureMetadata(profile)
    end
end

--[[ Profile CRUD ]]

-- Create the profile if it does not exist; returns the profile either way.
function ProfileStore:CreateProfile(id)
    local profile = profiles[id]
    if not profile then
        profile = {
            Metadata = { Created = Time:Now(), NextIndex = 1 },
            Snapshots = {},
        }
        profiles[id] = profile
    else
        EnsureMetadata(profile)
    end
    return profile
end

function ProfileStore:GetProfile(name)
    if profiles[name] then
        EnsureMetadata(profiles[name])
    end
    return profiles[name]
end

function ProfileStore:GetProfiles()
    for _, profile in pairs(profiles) do
        EnsureMetadata(profile)
    end
    return profiles
end

function ProfileStore:DeleteProfile(name)
    if profiles[name] then
        profiles[name] = nil
        return true
    end
    return false
end

--[[ Snapshot history ]]

-- Append a snapshot to a profile, creating the profile if needed. Always stores
-- the snapshot (a save is a save, even when nothing changed) and returns it.
function ProfileStore:AddSnapshot(name, snapshot)
    local profile = self:CreateProfile(name)
    local snapshots = profile.Snapshots

    local metadata = EnsureMetadata(profile)
    snapshot.Index = metadata.NextIndex
    metadata.NextIndex = metadata.NextIndex + 1

    BoundedList:Wrap(snapshots, {
        max = MaxSnapshots,
        isProtected = function(entry) return entry.Pinned end,
    }):Push(snapshot)
    return snapshot
end

-- The soft cap on snapshots per profile.
function ProfileStore:GetMaxSnapshots()
    return MaxSnapshots()
end

-- The snapshot a save would prune to stay within the cap: the oldest un-pinned
-- snapshot once the history is at (or over) MaxSnapshots. Returns nil when a
-- save would evict nothing (under the cap, or every snapshot is pinned).
function ProfileStore:PendingEviction(name)
    local profile = profiles[name]
    if not profile then
        return nil
    end

    EnsureMetadata(profile)
    local snapshots = profile.Snapshots
    if #snapshots < MaxSnapshots() then
        return nil
    end

    for index = 1, #snapshots do
        if not snapshots[index].Pinned then
            return snapshots[index]
        end
    end
    return nil
end

function ProfileStore:GetLatestSnapshot(name)
    local profile = profiles[name]
    if not profile then
        return nil
    end
    EnsureMetadata(profile)
    return profile.Snapshots[#profile.Snapshots]
end

function ProfileStore:GetSnapshot(name, selector)
    local profile = profiles[name]
    if not profile then
        return nil, "not-found"
    end
    local snapshot, _, reason, candidates = FindSnapshot(profile, selector)
    return snapshot, reason, candidates
end

function ProfileStore:DeleteSnapshot(name, selector)
    local profile = profiles[name]
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

function ProfileStore:SetSnapshotBody(name, selector, text)
    local profile = profiles[name]
    if not profile then
        return false
    end

    local snapshot = FindSnapshot(profile, selector)
    if not snapshot then
        return false
    end

    snapshot.Body = text
    return true
end

function ProfileStore:PinSnapshot(name, selector)
    local profile = profiles[name]
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

function ProfileStore:UnpinSnapshot(name, selector)
    local profile = profiles[name]
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
