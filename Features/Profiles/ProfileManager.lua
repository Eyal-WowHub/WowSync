local _, addon = ...
local ProfileManager = addon:NewObject("ProfileManager")

local C = LibStub("Contracts-1.0")

--[[
    ProfileManager — read/management of stored character profiles.

    A profile is one character's saved record: its snapshot history plus the
    metadata kept alongside it. This exposes the profile-level operations —
    reading a single profile or the whole set, deleting one, and wiping them all.
]]

local ProfileStore = addon:GetObject("ProfileStore")

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
