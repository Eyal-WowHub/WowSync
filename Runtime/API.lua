local _, addon = ...
WowSync = addon:NewObject(addon:GetName())
local ProfileManager = addon:GetObject("ProfileManager")
local Snapshot = addon:GetObject("Snapshot")

local L = addon.L

-- Public value objects, exposed so other addons (e.g. the companion UI) can
-- interpret data this addon returns.
WowSync.Models = {
    SnapshotApplyMode = addon.SnapshotApplyMode,
}

function WowSync:GetProfileManager()
    return ProfileManager
end

-- The stable <hash>#<index> selector for a snapshot, used by the companion UI
-- to address a specific snapshot unambiguously.
function WowSync:GetSnapshotSelector(snapshot)
    return Snapshot:GetSelector(snapshot)
end

--[[ Addon entry points ]]

-- Public alias for addon:Print.
WowSync.Print = addon.Print

-- Loads the companion UI addon on demand, then fires WOWSYNC_UI_TOGGLED so the
-- UI can open or toggle its window.
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
