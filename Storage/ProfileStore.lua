local _, addon = ...
local ProfileStore = addon:NewObject("ProfileStore")

--[[
    ProfileStore — account-wide named profiles, each a history of snapshots.

    A profile lives under DB.global.Profiles[name]:

        { Meta = { Created, Notes }, Snapshots = { <snapshot>, ... } }

    Snapshots are ordered oldest-first (newest appended at the end); each entry
    has the Snapshot shape (Hash + Timestamp + Modules + ...). Saving is
    idempotent: a snapshot whose Hash matches the latest one is rejected as
    "unchanged". The history is capped at Settings.MaxSnapshots, pruning the
    oldest UN-pinned snapshots first; pinned snapshots are never pruned.
]]

local Time = addon.Time

local profiles

local function FindSnapshot(profile, hash)
    local snapshots = profile.Snapshots
    for index = 1, #snapshots do
        if snapshots[index].Hash == hash then
            return snapshots[index], index
        end
    end
    return nil
end

-- Drop oldest UN-pinned snapshots until the history fits within max.
local function Prune(snapshots, max)
    local index = 1
    while #snapshots > max and index <= #snapshots do
        if snapshots[index].Pinned then
            index = index + 1
        else
            tremove(snapshots, index)
        end
    end
end

function ProfileStore:OnInitialized()
    profiles = addon.DB.global.Profiles
end

--[[ Profile CRUD ]]

-- Create the profile if it does not exist; returns the profile either way.
function ProfileStore:CreateProfile(name)
    local profile = profiles[name]
    if not profile then
        profile = {
            Meta = { Created = Time:Now() },
            Snapshots = {},
        }
        profiles[name] = profile
    end
    return profile
end

function ProfileStore:GetProfile(name)
    return profiles[name]
end

function ProfileStore:GetProfiles()
    return profiles
end

function ProfileStore:DeleteProfile(name)
    if profiles[name] then
        profiles[name] = nil
        return true
    end
    return false
end

function ProfileStore:RenameProfile(oldName, newName)
    local profile = profiles[oldName]
    if not profile or profiles[newName] then
        return false
    end

    profiles[newName] = profile
    profiles[oldName] = nil
    return true
end

--[[ Snapshot history ]]

-- Append a snapshot to a profile, creating the profile if needed. Returns the
-- stored snapshot, or nil + "unchanged" when its Hash matches the latest one.
function ProfileStore:AddSnapshot(name, snapshot)
    local profile = self:CreateProfile(name)
    local snapshots = profile.Snapshots

    local latest = snapshots[#snapshots]
    if latest and latest.Hash == snapshot.Hash then
        return nil, "unchanged"
    end

    tinsert(snapshots, snapshot)
    Prune(snapshots, addon.DB.global.Settings.MaxSnapshots or 20)
    return snapshot
end

function ProfileStore:GetLatestSnapshot(name)
    local profile = profiles[name]
    if not profile then
        return nil
    end
    return profile.Snapshots[#profile.Snapshots]
end

function ProfileStore:GetSnapshot(name, hash)
    local profile = profiles[name]
    if not profile then
        return nil
    end
    return (FindSnapshot(profile, hash))
end

function ProfileStore:DeleteSnapshot(name, hash)
    local profile = profiles[name]
    if not profile then
        return false
    end

    local _, index = FindSnapshot(profile, hash)
    if not index then
        return false
    end

    tremove(profile.Snapshots, index)
    return true
end

function ProfileStore:SetSnapshotBody(name, hash, text)
    local profile = profiles[name]
    if not profile then
        return false
    end

    local snapshot = FindSnapshot(profile, hash)
    if not snapshot then
        return false
    end

    snapshot.Body = text
    return true
end

function ProfileStore:PinSnapshot(name, hash)
    local profile = profiles[name]
    if not profile then
        return false
    end

    local snapshot = FindSnapshot(profile, hash)
    if not snapshot then
        return false
    end

    snapshot.Pinned = true
    return true
end

function ProfileStore:UnpinSnapshot(name, hash)
    local profile = profiles[name]
    if not profile then
        return false
    end

    local snapshot = FindSnapshot(profile, hash)
    if not snapshot then
        return false
    end

    snapshot.Pinned = false
    return true
end
