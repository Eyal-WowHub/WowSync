local _, addon = ...
local Differ = addon:NewObject("Differ")

local Module = addon.Module

--[[
    Differ — preview what applying a snapshot would change.

    Each module that supports diffing implements Diff(currentData, snapshotData)
    and returns { added = {...}, changed = {...}, removed = {...} } describing the
    entries that would be created, overwritten, or (in Exact mode) deleted.
    Differ aggregates those into a per-module map plus overall totals for the
    apply preview dialog.
]]

local EMPTY = {}

local function Count(list)
    return list and #list or 0
end

-- Add a module diff's counts into totals. The Plugin umbrella's diff, shaped
-- { plugins = { { subModules = { { added, changed, removed } } } } }, is summed
-- across its plugins and their submodules; a plain module diff is summed directly.
local function AddDiffTotals(totals, moduleDiff)
    if moduleDiff.plugins then
        for _, plugin in ipairs(moduleDiff.plugins) do
            for _, subModule in ipairs(plugin.subModules) do
                totals.added = totals.added + Count(subModule.added)
                totals.changed = totals.changed + Count(subModule.changed)
                totals.removed = totals.removed + Count(subModule.removed)
            end
        end
    else
        totals.added = totals.added + Count(moduleDiff.added)
        totals.changed = totals.changed + Count(moduleDiff.changed)
        totals.removed = totals.removed + Count(moduleDiff.removed)
    end
end

-- Preview applying snapshotModules over currentModules.
-- moduleSet (optional) restricts the preview to the given module names; when
-- omitted, every module present in the snapshot is considered.
function Differ:Preview(currentModules, snapshotModules, moduleSet)
    currentModules = currentModules or EMPTY
    snapshotModules = snapshotModules or EMPTY

    local moduleDiffs = {}
    local diffTotals = { added = 0, changed = 0, removed = 0 }

    for name in pairs(moduleSet or snapshotModules) do
        local module = Module:FromRegisteredModule(name)
        local snapshotData = snapshotModules[name]

        if module and snapshotData ~= nil then
            local moduleDiff = module:Diff(currentModules[name], snapshotData)
            if moduleDiff then
                moduleDiffs[name] = moduleDiff
                AddDiffTotals(diffTotals, moduleDiff)
            end
        end
    end

    return { perModule = moduleDiffs, totals = diffTotals }
end
