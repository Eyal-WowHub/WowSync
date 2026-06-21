local _, addon = ...

WowSync = addon:NewObject(addon:GetName())

local ProfileManager = addon:GetObject("ProfileManager")

function WowSync:GetProfileManager()
    return ProfileManager
end

function WowSync:HasRevertPoint()
    return ProfileManager:HasRevertPoint()
end

function WowSync:GetRevertInfo()
    return ProfileManager:GetRevertInfo()
end

function WowSync:Revert()
    return ProfileManager:Revert()
end
