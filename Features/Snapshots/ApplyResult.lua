local _, addon = ...
local ApplyResult = {}
addon.ApplyResult = ApplyResult

--[[
    ApplyResult — the per-module outcome of an apply or undo.

    SnapshotManager:Apply / :UndoLastApply / :UndoApplies build a { [moduleName] = outcome }
    map, where each outcome is one of:

        { applied = true,  mode = "merge"|"exact", warning = string? }
        { applied = false, reason = string }

    Wrapping that map gives every caller (the slash commands and the companion
    UI) the same deterministic, sorted views instead of each re-implementing an
    unordered pairs() loop. The wrapper is transient — it is never stored in
    saved variables — so a metatable is safe here.
]]

ApplyResult.__index = ApplyResult

function ApplyResult:New(outcomes)
    return setmetatable({ outcomes = outcomes or {} }, self)
end

-- Record (or overwrite) a single module's outcome.
function ApplyResult:Set(moduleName, outcome)
    self.outcomes[moduleName] = outcome
    return self
end

function ApplyResult:Get(moduleName)
    return self.outcomes[moduleName]
end

-- True when at least one module produced an outcome.
function ApplyResult:Any()
    return next(self.outcomes) ~= nil
end

-- True when at least one module was actually applied.
function ApplyResult:Changed()
    for _, outcome in pairs(self.outcomes) do
        if outcome.applied then
            return true
        end
    end
    return false
end

-- Fold another result into this one; later outcomes win on key collisions.
function ApplyResult:Merge(otherResult)
    for name, outcome in pairs(otherResult.outcomes) do
        self.outcomes[name] = outcome
    end
    return self
end

local function SortOutcomeNames(outcomes, applied)
    local moduleNames = {}
    for name, outcome in pairs(outcomes) do
        if outcome.applied == applied then
            tinsert(moduleNames, name)
        end
    end
    table.sort(moduleNames)
    return moduleNames
end

-- Sorted module names that were applied, for stable output order.
function ApplyResult:Applied()
    return SortOutcomeNames(self.outcomes, true)
end

-- Sorted module names that were skipped, for stable output order.
function ApplyResult:Skipped()
    return SortOutcomeNames(self.outcomes, false)
end

-- Applied and skipped counts, handy for status summaries.
function ApplyResult:Counts()
    local applied, skipped = 0, 0
    for _, outcome in pairs(self.outcomes) do
        if outcome.applied then
            applied = applied + 1
        else
            skipped = skipped + 1
        end
    end
    return applied, skipped
end
