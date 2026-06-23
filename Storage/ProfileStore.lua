local _, addon = ...
local ProfileStore = addon:NewObject("ProfileStore")

local CappedHistory = addon.CappedHistory

--[[
    ProfileStore — account-wide named profiles, each a history of snapshots.

    A profile lives under DB.global.Profiles[name]:

        { Meta = { Created, Notes }, Snapshots = { <snapshot>, ... } }

    Snapshots are ordered oldest-first (newest appended at the end); each entry
    has the Snapshot shape (Hash + Timestamp + Modules + ...). Saving is
    idempotent: a snapshot whose Hash matches the latest one is rejected as
    "unchanged". The history is kept near Settings.MaxSnapshots by pruning the
    oldest UN-pinned snapshots first; pinned snapshots are never pruned, so a
    profile with many pins can hold more than MaxSnapshots (a soft cap).
]]

local Time = addon.Time

local profiles

-- Resolve a snapshot by exact hash or an unambiguous hash prefix (git-style).
-- Returns snapshot, index — or nil, nil, reason ("not-found" | "ambiguous").
local function FindSnapshot(profile, hash)
    local snapshots = profile.Snapshots

    -- An exact match always wins, even if it is also a prefix of others.
    for index = 1, #snapshots do
        if snapshots[index].Hash == hash then
            return snapshots[index], index
        end
    end

    -- Otherwise accept a single prefix match; more than one is ambiguous.
    local match, matchIndex
    for index = 1, #snapshots do
        if snapshots[index].Hash:sub(1, #hash) == hash then
            if match then
                return nil, nil, "ambiguous"
            end
            match, matchIndex = snapshots[index], index
        end
    end

    if match then
        return match, matchIndex
    end
    return nil, nil, "not-found"
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

    CappedHistory:Wrap(snapshots, {
        max = function() return addon.DB.global.Settings.MaxSnapshots or 20 end,
        isProtected = function(entry) return entry.Pinned end,
    }):Push(snapshot)
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
        return nil, "not-found"
    end
    local snapshot, _, reason = FindSnapshot(profile, hash)
    return snapshot, reason
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
