local _, addon = ...
local ProfileStore = addon:NewObject("ProfileStore")

local profiles

function ProfileStore:OnInitialized()
    profiles = addon.DB.global.Profiles
end

function ProfileStore:Set(name, profile)
    profiles[name] = profile
end

function ProfileStore:Get(name)
    return profiles[name]
end

function ProfileStore:GetAll()
    return profiles
end

function ProfileStore:Delete(name)
    if profiles[name] then
        profiles[name] = nil
        return true
    end

    return false
end

function ProfileStore:Rename(oldName, newName)
    local profile = profiles[oldName]
    if not profile then
        return false
    end

    if profiles[newName] then
        return false
    end

    profiles[newName] = profile
    profiles[oldName] = nil
    return true
end
