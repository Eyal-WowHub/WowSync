local _, addon = ...
local Differ = addon:NewObject("Differ")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

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

-- Preview applying snapshotModules over currentModules.
-- moduleSet (optional) restricts the preview to the given module names; when
-- omitted, every module present in the snapshot is considered.
function Differ:Preview(currentModules, snapshotModules, moduleSet)
    currentModules = currentModules or EMPTY
    snapshotModules = snapshotModules or EMPTY

    local perModule = {}
    local totals = { added = 0, changed = 0, removed = 0 }

    for name in pairs(moduleSet or snapshotModules) do
        local module = ModuleRegistry:Get(name)
        local snapshotData = snapshotModules[name]

        if module and module.Diff and snapshotData ~= nil then
            local diff = module:Diff(currentModules[name], snapshotData)
            if diff then
                perModule[name] = diff
                totals.added = totals.added + Count(diff.added)
                totals.changed = totals.changed + Count(diff.changed)
                totals.removed = totals.removed + Count(diff.removed)
            end
        end
    end

    return { perModule = perModule, totals = totals }
end
