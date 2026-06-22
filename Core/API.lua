local _, addon = ...

WowSync = addon:NewObject(addon:GetName())

local ProfileManager = addon:GetObject("ProfileManager")

-- Public value objects, exposed so other addons (e.g. the companion UI) can
-- interpret data this addon returns.
WowSync.Models = {
    SnapshotApplyMode = addon.SnapshotApplyMode,
}

function WowSync:GetProfileManager()
    return ProfileManager
end

function WowSync:HasUndo()
    return ProfileManager:HasUndo()
end

function WowSync:GetUndoInfo()
    return ProfileManager:GetUndoInfo()
end

function WowSync:GetUndoStack()
    return ProfileManager:GetUndoStack()
end

function WowSync:Undo(moduleSet)
    return ProfileManager:Undo(moduleSet)
end

function WowSync:UndoSteps(count)
    return ProfileManager:UndoSteps(count)
end
