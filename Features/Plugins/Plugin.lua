local _, addon = ...
local Plugin = addon:NewObject("Plugin")

local ModuleRegistry = addon.ModuleRegistry
local PluginManager = addon.PluginManager
local SnapshotApplyMode = addon.SnapshotApplyMode

--[[
    Plugin — the single umbrella module (id 1000000) that represents every
    installed plugin as one WowSync module.

    It owns no data of its own: capture, apply and diff all delegate to
    PluginManager, which fans out to the plugin modules registered beneath it and
    groups their data by plugin name. Consolidating plugins under one permanent
    identity is what lets a third-party addon extend WowSync without ever minting
    a module id or touching the identity registry.
]]

Plugin.Config = {
    -- Applies after the built-in modules, so a plugin that rebuilds itself from
    -- the final game state (e.g. a UI addon) sees everything already in place.
    ApplyPriority = 200,
    SnapshotApplyMode = SnapshotApplyMode.All,
}

function Plugin:OnInitialized()
    ModuleRegistry:Register(self)
end

-- Capture every installed plugin's live state, grouped by plugin. Nil when no
-- plugin contributes, so the umbrella leaves no trace when nothing is installed.
function Plugin:Capture()
    return PluginManager:CaptureAll()
end

-- The umbrella is always applicable; each plugin module's own CanApply gate is
-- honoured per-slice during Apply.
function Plugin:CanApply()
    return true
end

-- Apply the consolidated plugin data, dispatching each slice back to its owner.
function Plugin:Apply(capturedData, sourceMetadata, applyOptions)
    PluginManager:ApplyAll(capturedData, sourceMetadata, applyOptions)
end

-- Preview the consolidated plugin changes, aggregated across every plugin module.
function Plugin:Diff(currentData, snapshotData)
    return PluginManager:DiffAll(currentData, snapshotData)
end
