local _, addon = ...

WowSync = addon:NewObject(addon:GetName())

local ProfileManager = addon:GetObject("ProfileManager")
local Colorizer = addon.Colorizer
local L = addon.L

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

--[[ Addon entry points ]]

function WowSync:Print(msg)
    local prefix = Colorizer:ToAccent(self:GetName()) .. ": "
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
end

-- Loads the companion UI addon on demand, then fires WOWSYNC_UI_TOGGLED so the
-- UI can open or toggle its window. This mirrors how WowInfo hands off to
-- WowInfo_Options, keeping WowSync free of any direct dependency on the UI.
function WowSync:ToggleUI()
    if not C_AddOns.IsAddOnLoaded("WowSync_UI") and not C_AddOns.LoadAddOn("WowSync_UI") then
        self:Print(L["WowSync_UI addon not found."])
        return
    end

    WowSync:TriggerEvent("WOWSYNC_UI_TOGGLED")
end

function WowSync_OnAddonCompartmentClick()
    WowSync:ToggleUI()
end
