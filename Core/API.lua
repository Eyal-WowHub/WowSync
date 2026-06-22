local _, addon = ...

WowSync = addon:NewObject(addon:GetName())

local ProfileManager = addon:GetObject("ProfileManager")

function WowSync:GetProfileManager()
    return ProfileManager
end

function WowSync:HasUndo()
    return ProfileManager:HasUndo()
end

function WowSync:GetUndoInfo()
    return ProfileManager:GetUndoInfo()
end

function WowSync:Undo(moduleSet)
    return ProfileManager:Undo(moduleSet)
end
