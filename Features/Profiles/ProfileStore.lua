local _, addon = ...
local ProfileStore = addon:NewObject("ProfileStore")

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
    the end); each entry has the snapshotInfo shape (Hash + Timestamp + Modules + ...).
    ProfileStore only stores and retrieves these records; the rules over the
    history — assigning indices, pruning to the cap, resolving selectors, and the
    pin/note/delete mutations — live in ProfileManager.
]]

local Time = addon.Time

local DEFAULT_MAX_SNAPSHOTS = 20

local profiles

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

-- The soft cap on snapshots per profile.
function ProfileStore:GetMaxSnapshots()
    return GetMaxSnapshotsSetting()
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
