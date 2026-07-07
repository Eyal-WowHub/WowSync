local _, addon = ...
local UndoManager = addon:NewObject("UndoManager")

--[[
    UndoManager — the per-character undo stack and the undo operation.

    Before an apply touches the live setup, SnapshotManager captures a full
    rollback snapshot and pushes it here. Undoing re-applies the most recent
    rollback in Exact mode over the current setup and pops it, so applies unwind
    newest-first. The stack lives on the logged-in character's record (its Undo
    slice); this manager owns both the stack and the operation, and shares the
    priority-ordered write path (ModuleRegistry:ApplyModules) with SnapshotManager.
]]

local ApplyResult = addon.ApplyResult
local ModuleRegistry = addon.ModuleRegistry
local Snapshot = addon.Snapshot

local Debugger = addon:GetObject("Debugger")
local Differ = addon:GetObject("Differ")
local ProfileManager = addon:GetObject("ProfileManager")
local SaveTask = addon:GetObject("SaveTask")
local UndoStore = addon:GetObject("UndoStore")

--[[ Lifecycle ]]

function UndoManager:OnInitialized()
    -- An apply announces its rollback point with this event rather than calling
    -- in, so the apply path never needs to know the undo stack exists.
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_APPLY_CHANGED", function(_, _, rollbackSnapshot)
        self:Push(rollbackSnapshot)
    end)
end

--[[ Undo stack ]]

-- Wrap a rollback snapshotInfo as a Snapshot, keyed to its source character.
local function WrapRollback(rollbackInfo)
    return rollbackInfo and Snapshot:Create(rollbackInfo.Source and (rollbackInfo.Source.CharacterName or rollbackInfo.Source.Character), rollbackInfo)
end

-- Push a rollback snapshot onto the logged-in character's undo stack.
function UndoManager:Push(snapshot)
    Snapshot.Validate(snapshot, 2)
    local profile = ProfileManager:GetCurrentProfile()
    UndoStore:Push(profile:ToStore(), snapshot:ToStore())
end

-- The most recent rollback snapshot, or nil when there is nothing to undo.
function UndoManager:Peek()
    local profile = ProfileManager:GetCurrentProfile()
    return WrapRollback(UndoStore:Peek(profile:ToStore()))
end

-- Pop and return the most recent rollback snapshot, or nil when the stack is empty.
function UndoManager:Pop()
    local profile = ProfileManager:GetCurrentProfile()
    return WrapRollback(UndoStore:Pop(profile:ToStore()))
end

-- The logged-in character's undo stack as rollback Snapshots, oldest-first.
function UndoManager:List()
    local profile = ProfileManager:GetCurrentProfile()
    local rollbackInfos = UndoStore:List(profile:ToStore())
    local rollbackSnapshots = {}
    for index = 1, #rollbackInfos do
        rollbackSnapshots[index] = WrapRollback(rollbackInfos[index])
    end
    return rollbackSnapshots
end

-- True when the logged-in character has anything to undo.
function UndoManager:Has()
    local profile = ProfileManager:GetCurrentProfile()
    return UndoStore:Has(profile:ToStore())
end

--[[ Undo operation ]]

-- True when the logged-in character has an apply that can be rolled back.
function UndoManager:CanUndo()
    return self:Has()
end

-- Subject + sorted module names describing a single rollback snapshot.
local function DescribeRollbackSnapshot(snapshot)
    return {
        Subject = snapshot:GetSubject(),
        Timestamp = snapshot:GetTimestamp(),
        ModuleNames = snapshot:GetModuleNames(),
    }
end

-- Subject + module names of the change that UndoLastApply would roll back.
function UndoManager:GetNextUndoPoint()
    local rollbackSnapshot = self:Peek()
    if not rollbackSnapshot then
        return nil
    end
    return DescribeRollbackSnapshot(rollbackSnapshot)
end

-- Preview what undoing the most recent apply would change: the top rollback
-- snapshot re-applied over the current setup. Nil when there is nothing to undo.
function UndoManager:PreviewUndo()
    local rollbackSnapshot = self:Peek()
    if not rollbackSnapshot then
        return nil
    end
    local liveSnapshot = ProfileManager:RefreshLiveSnapshot()
    return Differ:Preview(liveSnapshot and liveSnapshot:Modules(), rollbackSnapshot:Modules())
end

-- The undo points newest-first, each describing one apply that can be rolled
-- back. Index 1 is the most recent (what a single UndoLastApply reverts); undoing
-- to a deeper index rolls back every apply above it as well.
function UndoManager:GetUndoPoints()
    local rollbackSnapshots = self:List()
    local undoPoints = {}
    for i = #rollbackSnapshots, 1, -1 do
        tinsert(undoPoints, DescribeRollbackSnapshot(rollbackSnapshots[i]))
    end
    return undoPoints
end

-- Roll back the most recent apply by re-applying the top rollback snapshot in
-- Exact mode (optionally limited to a subset), then pop it off the stack.
function UndoManager:UndoLastApply(moduleSet)
    if InCombatLockdown() then
        return nil
    end

    -- Finish any in-flight save first so it cannot capture a half-undone setup.
    SaveTask:Drain()

    local snapshot = self:Peek()
    if not snapshot then
        return nil
    end

    local rollbackModules = snapshot:Modules()
    local moduleNames = snapshot:GetModuleNames(moduleSet)

    local debugHandle = Debugger:IsEnabled() and Debugger:BeginOperation("undo", {
        Subject = snapshot:GetSubject(),
    }, moduleNames)

    -- Announce the write so the live-mirror watcher pauses: our own undo fires
    -- the very game events it tracks, and it must not mirror them back as if the
    -- player had made them.
    WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_UNDO_STARTED")
    local applyResults = ModuleRegistry:ApplyModules(moduleNames, rollbackModules, { default = "exact" }, snapshot:GetClassID())
    self:Pop()
    ProfileManager:RefreshLiveSnapshot()
    WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_UNDO_FINISHED")

    if Debugger:IsEnabled() then
        Debugger:EndOperation(debugHandle, rollbackModules, applyResults)
    end
    return ApplyResult:New(applyResults)
end

-- Roll back the most recent `count` applies, newest first, by undoing one step
-- at a time. Returns the aggregated per-module results across every step that
-- ran (later steps win when a module appears in more than one).
function UndoManager:UndoApplies(count)
    count = count or 1
    local aggregate = ApplyResult:New()
    for _ = 1, count do
        if not self:Has() then
            break
        end

        local stepResult = self:UndoLastApply()
        if stepResult then
            aggregate:Merge(stepResult)
        end
    end

    return aggregate
end
