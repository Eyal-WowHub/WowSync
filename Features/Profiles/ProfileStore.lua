local _, addon = ...
local ProfileStore = addon:NewObject("ProfileStore")

local C = LibStub("Contracts-1.0")

local BoundedList = addon.BoundedList
local Snapshot = addon.Snapshot
local Time = addon.Time

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
    same record. Notes belong to the snapshot (its Notes), not the record.
    Snapshots are ordered oldest-first (newest appended at the end); each entry
    has the snapshotInfo shape (Hash + Timestamp + Modules + ...).

    ProfileStore takes and returns Snapshot objects, persisting their plain
    backing tables (via :ToStore()) and owning the storage mechanics over the
    history: appending a save, assigning its index, capping to the soft limit
    (protecting pinned entries), and removing an entry. The higher-level rules —
    resolving a selector and the pin/note policy — live in ProfileManager.
]]

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
    local snapshotInfo = profile.Snapshots[#profile.Snapshots]
    if not snapshotInfo then
        return nil
    end
    return Snapshot:From(profileName, snapshotInfo)
end

-- The profile's saved snapshot history as Snapshot objects, oldest-first (empty
-- when none).
function ProfileStore:GetSnapshots(profileName)
    local profile = profiles[profileName]
    if not profile then
        return {}
    end
    EnsureMetadata(profile)

    local snapshots = {}
    for index = 1, #profile.Snapshots do
        snapshots[index] = Snapshot:From(profileName, profile.Snapshots[index])
    end
    return snapshots
end

-- Append a snapshot to its character's saved history: persist its backing data,
-- tag the optional note, assign the next index, and prune the oldest un-pinned
-- entries down to the soft cap. Returns the same Snapshot.
function ProfileStore:AppendSnapshot(snapshot, note)
    Snapshot.Validate(snapshot, 2)
    -- A head is a live view of Current, not a history entry; a save mints a fresh
    -- snapshot from its content, so the head object itself is never appended.
    C:Ensures(not snapshot:IsHead(), "cannot append a head to the history")

    local snapshotInfo = snapshot:ToStore()
    if note ~= nil then
        snapshotInfo.Notes = note
    end

    local profile = self:CreateProfile(snapshot:GetCharacterInfo().Key)
    snapshotInfo.Index = profile.Metadata.NextIndex
    profile.Metadata.NextIndex = profile.Metadata.NextIndex + 1

    BoundedList:Wrap(profile.Snapshots, {
        max = function() return GetMaxSnapshotsSetting() end,
        isProtected = function(entry) return entry.Pinned end,
    }):Push(snapshotInfo)
    return snapshot
end

-- Remove a snapshot from its character's saved history by identity. Returns
-- whether it was found and removed.
function ProfileStore:RemoveSnapshot(snapshot)
    Snapshot.Validate(snapshot, 2)

    local profile = profiles[snapshot:GetCharacterInfo().Key]
    if not profile then
        return false
    end

    local snapshotInfo = snapshot:ToStore()
    for index = 1, #profile.Snapshots do
        if profile.Snapshots[index] == snapshotInfo then
            tremove(profile.Snapshots, index)
            return true
        end
    end
    return false
end
