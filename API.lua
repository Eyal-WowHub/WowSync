local _, addon = ...
WowSync = addon:NewObject(addon:GetName())
local ProfileManager = addon:GetObject("ProfileManager")
local SnapshotManager = addon:GetObject("SnapshotManager")
local ImportManager = addon:GetObject("ImportManager")
local ExportManager = addon:GetObject("ExportManager")
local ImportedHashDictionary = addon:GetObject("ImportedHashDictionary")
local CharacterManager = addon:GetObject("CharacterManager")
local ModuleRegistry = addon:GetObject("ModuleRegistry")
local SnapshotView = addon:GetObject("SnapshotView")
local SnapshotHandleCache = addon:GetObject("SnapshotHandleCache")
local GameWatcher = addon:GetObject("GameWatcher")
local Debugger = addon:GetObject("Debugger")

local L = addon.L
local ChangeBadge = addon.ChangeBadge

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

-- Imports shared strings into class-locked containers, manages those
-- containers, and applies imported snapshots.
function WowSync:GetImportManager()
    return ImportManager
end

-- Exports profile snapshots and heads to portable shared strings.
function WowSync:GetExportManager()
    return ExportManager
end

-- Resolves, across every container, which one owns each imported snapshot hash
-- (the earliest-imported copy).
function WowSync:GetImportedHashDictionary()
    return ImportedHashDictionary
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

-- The opt-in debug recorder, for tagging an action's source and logging UI
-- interactions into WowSyncDebugDB.
function WowSync:GetDebugger()
    return Debugger
end

-- The shared formatter for coloured "+A ~C -R" diff strings, used by companion
-- UI addons to render one consistent change figure.
function WowSync:FormatDiffString(counts, prefix)
    return ChangeBadge.FormatDiffString(counts, prefix)
end

--[[ Addon entry points ]]

-- Public alias for addon:Print.
WowSync.Print = addon.Print

-- Public alias for addon:PrintLine.
WowSync.PrintLine = addon.PrintLine

-- Loads the companion UI addon on demand, then fires WOWSYNC_UI_TOGGLED so the
-- UI can open or toggle its window.
function WowSync:ToggleUI()
    if not C_AddOns.IsAddOnLoaded("WowSync_UI") and not C_AddOns.LoadAddOn("WowSync_UI") then
        self:Print(L["WowSync_UI addon not found."])
        return
    end

    WowSync:TriggerEvent("WOWSYNC_UI_TOGGLED")
end

-- Loads the companion UI addon on demand, then fires WOWSYNC_UI_OPEN_SHARE_DIALOG
-- so the UI can open its share dialog; action is "import" or "export". Prints a
-- notice and does nothing when the UI addon is disabled or missing.
function WowSync:OpenShareDialog(action)
    if not C_AddOns.IsAddOnLoaded("WowSync_UI") and not C_AddOns.LoadAddOn("WowSync_UI") then
        self:Print(L["WowSync_UI is required to import and export. Enable it in your AddOns list."])
        return
    end

    WowSync:TriggerEvent("WOWSYNC_UI_OPEN_SHARE_DIALOG", action)
end

function WowSync_OnAddonCompartmentClick()
    WowSync:ToggleUI()
end
