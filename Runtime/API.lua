local _, addon = ...
WowSync = addon:NewObject(addon:GetName())
local ProfileManager = addon:GetObject("ProfileManager")
local SnapshotManager = addon:GetObject("SnapshotManager")
local CharacterManager = addon:GetObject("CharacterManager")
local ModuleRegistry = addon:GetObject("ModuleRegistry")
local SnapshotView = addon:GetObject("SnapshotView")
local SnapshotHandleCache = addon:GetObject("SnapshotHandleCache")
local GameWatcher = addon:GetObject("GameWatcher")

local L = addon.L

-- Public value objects returned by this addon's APIs.
WowSync.Models = {
    SnapshotApplyMode = addon.SnapshotApplyMode,
}

function WowSync:GetProfileManager()
    return ProfileManager
end

-- Captures, saves, applies, previews and undoes snapshots, and reports a
-- character's current head.
function WowSync:GetSnapshotManager()
    return SnapshotManager
end

-- The roster of characters that have a profile or a captured current setup, and
-- token-to-character resolution.
function WowSync:GetCharacterManager()
    return CharacterManager
end

-- The registry of installed modules (lookup by name and iteration).
function WowSync:GetModuleRegistry()
    return ModuleRegistry
end

-- The accessor/mutator interface onto an individual snapshot handle.
function WowSync:GetSnapshotView()
    return SnapshotView
end

-- The source of stable snapshot handles, keyed by character (head, latest
-- saved, pending eviction, full timeline).
function WowSync:GetSnapshotHandleCache()
    return SnapshotHandleCache
end

-- Registers interest in live tracking under a consumer id; while any attachment is
-- present, lazy mode keeps the current setup mirrored.
function WowSync:Attach(consumerId)
    GameWatcher:Attach(consumerId)
end

-- Drops an attachment's interest; tracking stops once the last one leaves.
function WowSync:Detach(consumerId)
    GameWatcher:Detach(consumerId)
end

-- True while at least one consumer is attached.
function WowSync:HasAttachments()
    return GameWatcher:HasAttachments()
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
