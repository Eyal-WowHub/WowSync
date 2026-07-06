local _, addon = ...
local SnapshotManager = addon:NewObject("SnapshotManager")

local C = LibStub("Contracts-1.0")
local CharacterInfo = LibStub("CharacterInfo-1.0")

local ApplyResult = addon.ApplyResult
local ModuleRegistry = addon.ModuleRegistry
local Snapshot = addon.Snapshot
local SnapshotApplyMode = addon.SnapshotApplyMode

local Debugger = addon:GetObject("Debugger")
local Differ = addon:GetObject("Differ")
local ProfileManager = addon:GetObject("ProfileManager")
local SaveTask = addon:GetObject("SaveTask")

--[[
    SnapshotManager — the snapshot subsystem's orchestrator/facade.

    It owns no state of its own; it coordinates the registry, the profile
    history, per-character live setup and undo stack (ProfileManager), the
    snapshot value-object (Snapshot), and the apply preview (Differ).

    Flow:
      Save    -> capture Current, build a Snapshot, append to the profile
                 (skipped when nothing changed since the latest snapshot).
      Apply   -> push a FULL rollback snapshot of Current to the undo stack, then
                 apply the chosen snapshot's modules (per-module Merge/Exact).
      Undo    -> re-apply the top rollback snapshot in Exact mode, then pop it.
]]

function SnapshotManager:OnInitialized()
    -- Finish any in-flight sliced save before SavedVariables is written, so an
    -- explicit Save started just before logout still lands, then capture and
    -- compress the final live setup for storage.
    self:RegisterEvent("PLAYER_LOGOUT", function()
        SaveTask:Drain()
        ProfileManager:StoreLiveSnapshot()
    end)
end

--[[ Combat ]]

-- True while the live setup must not be touched: the protected talent and
-- action-bar APIs an apply or undo relies on are locked during combat. Save,
-- apply and undo all short-circuit while this holds.
function SnapshotManager:IsCombatLocked()
    return InCombatLockdown()
end

--[[ Internal helpers ]]

local function BuildCurrentSource()
    return {
        Character = CharacterInfo:GetFullName(),
        ClassID = PlayerUtil.GetClassID(),
    }
end

-- The meta passed to a module's CanApply/Apply, derived from a Snapshot.
local function BuildApplyMeta(snapshot)
    return { ClassID = snapshot:GetCharacterInfo().ClassID }
end

-- The chosen module subset (intersected with what was actually captured), or
-- the whole capture when no subset is given.
local function FilterCapturedModules(capturedModules, moduleSet)
    if not moduleSet then
        return capturedModules or {}
    end
    local subset = {}
    if capturedModules then
        for name in pairs(moduleSet) do
            if capturedModules[name] ~= nil then
                subset[name] = capturedModules[name]
            end
        end
    end
    return subset
end

-- Resolve the effective set of module names: the chosen subset intersected with
-- what the snapshot actually contains, or everything in the snapshot when no
-- subset is given.
local function ResolveModuleNames(capturedModules, moduleSet)
    local moduleNames = {}
    if moduleSet then
        for name in pairs(moduleSet) do
            if capturedModules[name] ~= nil then
                moduleNames[name] = true
            end
        end
    else
        for name in pairs(capturedModules) do
            moduleNames[name] = true
        end
    end
    return moduleNames
end

-- Write captured module payloads into the live game in module priority order
-- (so dependencies like Macros land before the modules that reference them),
-- honoring each module's CanApply gate and apply mode. Returns the per-module
-- results and whether anything was actually applied.
local function ApplyModules(sourceModules, meta, moduleNames, strategy)
    local defaultMode = strategy.default or "merge"
    local overrides = strategy.overrides or {}
    local applyResults = {}
    local applied = false
    for name, module in ModuleRegistry:IterableModulesByPriority(moduleNames) do
        local capturedData = sourceModules[name]
        if module and capturedData ~= nil then
            local canApply, warning = module:CanApply(meta)
            if not canApply then
                applyResults[name] = { applied = false, reason = warning }
            else
                local mode = overrides[name] or defaultMode
                local applySucceeded, applyError = pcall(module.Apply, module, capturedData, meta, { mode = mode })
                if applySucceeded then
                    applyResults[name] = { applied = true, mode = mode, warning = warning }
                    applied = true
                else
                    applyResults[name] = { applied = false, reason = tostring(applyError) }
                end
            end
        end
    end
    return applyResults, applied
end

-- Shared apply core: capture a FULL rollback snapshot of Current before touching
-- anything (so any change, including Exact deletions and per-module undo, can be
-- rolled back), then apply the given module set with the per-module strategy.
-- The rollback snapshot is only pushed to the undo stack when an apply actually
-- happens. Returns an ApplyResult.
local function ApplyCapturedModules(sourceModules, meta, strategy, moduleSet, info)
    -- Never change the live setup during combat; the protected talent and
    -- action-bar APIs are locked. Report nothing applied.
    if InCombatLockdown() then
        return ApplyResult:New({})
    end

    -- Finish any in-flight save first so it cannot capture a half-applied setup.
    SaveTask:Drain()

    strategy = strategy or {}

    local liveSnapshot = ProfileManager:RefreshLiveSnapshot()
    C:Ensures(liveSnapshot ~= nil, "expected a live snapshot to roll back to, but the logged-in character captured nothing")
    local rollbackSnapshot = Snapshot:Create(liveSnapshot:Modules(), BuildCurrentSource())

    local moduleNames = ResolveModuleNames(sourceModules, moduleSet)

    local debugHandle = Debugger:IsEnabled() and Debugger:BeginOperation("apply", {
        Profile = info and info.Profile,
        Selector = info and info.Selector,
        Strategy = strategy,
    }, moduleNames)

    -- Announce the write so the live-mirror watcher pauses: our own apply fires
    -- the very game events it tracks, and it must not mirror them back as if the
    -- player had made them.
    WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_APPLY_STARTED")
    local applyResults, applied = ApplyModules(sourceModules, meta, moduleNames, strategy)
    -- Only record an undo point when an apply actually happened.
    if applied then
        ProfileManager:PushUndo(rollbackSnapshot)
        ProfileManager:RefreshLiveSnapshot()
    end
    WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_APPLY_FINISHED")

    if Debugger:IsEnabled() then
        Debugger:EndOperation(debugHandle, sourceModules, applyResults)
    end

    return ApplyResult:New(applyResults)
end

--[[ Modules ]]

-- The apply modes a module supports (None when unknown), so the apply UI can
-- offer Merge/Exact only where each is meaningful.
function SnapshotManager:GetModuleApplyMode(name)
    C:IsString(name, 2)
    local module = ModuleRegistry:Get(name)
    return module and module.Config and module.Config.SnapshotApplyMode or SnapshotApplyMode.None
end

-- The fallback icon a module supplies for entries that carry none of their own,
-- giving each module a visual identity in the diff preview. Nil when unset.
function SnapshotManager:GetModuleDefaultIcon(name)
    C:IsString(name, 2)
    local module = ModuleRegistry:Get(name)
    return module and module.Config and module.Config.DefaultIcon or nil
end

--[[ Current ]]

-- True when the logged-in character has anything captured to save.
function SnapshotManager:HasCapturedGameData()
    return ProfileManager:GetLiveSnapshot() ~= nil
end

-- The logged-in character's profile key (its full name).
function SnapshotManager:GetCurrentCharKey()
    return CharacterInfo:GetFullName()
end

-- The soft cap on snapshots kept per character profile.
function SnapshotManager:GetSnapshotLimit()
    return ProfileManager:GetMaxSnapshots()
end

--[[ Save ]]

-- Capture Current (optionally a subset) and append it as a snapshot to the
-- logged-in character's profile, tagging it with the given optional note. The
-- capture and fingerprint are sliced across frames, bracketed by
-- WOWSYNC_SNAPSHOT_SAVE_STARTED/FINISHED so the UI can show progress; the stored
-- snapshot is handed to onComplete.
function SnapshotManager:SaveCurrentSnapshot(note, moduleSet, onComplete)
    if InCombatLockdown() then
        if onComplete then onComplete(nil, "combat") end
        return
    end

    SaveTask:Run(function()
        local liveSnapshot = ProfileManager:RefreshLiveSnapshot()
        C:Ensures(liveSnapshot ~= nil, "expected a live snapshot to save, but the logged-in character captured nothing")
        local snapshotModules = FilterCapturedModules(liveSnapshot:Modules(), moduleSet)
        local snapshot = Snapshot:Create(snapshotModules, BuildCurrentSource())

        local stored = ProfileManager:AddSnapshot(snapshot, note)
        if Debugger:IsEnabled() then
            Debugger:RecordSave({
                Profile = snapshot:GetCharacterInfo().Character,
                Hash = snapshot:HashValue(),
                Selector = stored and stored:GetSelector(),
            }, snapshotModules)
        end
        return stored
    end, onComplete)
end

-- Preview what saving the given module subset would do for a character
-- (default: the logged-in one). A save always creates a snapshot, so this only
-- reports the eviction it would cause. Returns:
--   evicted - the snapshot a save would prune to stay within MaxSnapshots, or
--             nil when nothing would be removed (under the cap, or all pinned).
function SnapshotManager:PreviewSaveSnapshotByCharKey(moduleSet, charKey)
    charKey = charKey or CharacterInfo:GetFullName()
    return ProfileManager:PendingEviction(charKey)
end

-- Append a snapshot built from another character's captured Current to that
-- character's profile, tagging it with the given optional note. Like
-- SaveCurrentSnapshot, it is sliced across frames with start/finish events;
-- onComplete receives the stored snapshot, or nil + a reason ("unknown-character").
function SnapshotManager:SaveSnapshotByCharKey(charKey, moduleSet, note, onComplete)
    C:IsString(charKey, 2)

    if InCombatLockdown() then
        if onComplete then onComplete(nil, "combat") end
        return
    end

    SaveTask:Run(function()
        local liveSnapshot = ProfileManager:GetLiveSnapshot(charKey)
        if not liveSnapshot then
            return nil, "unknown-character"
        end

        local snapshotModules = FilterCapturedModules(liveSnapshot:Modules(), moduleSet)
        local snapshot = Snapshot:Create(snapshotModules, {
            Character = charKey,
            ClassID = liveSnapshot:GetCharacterInfo().ClassID,
        })

        local stored = ProfileManager:AddSnapshot(snapshot, note)
        if Debugger:IsEnabled() then
            Debugger:RecordSave({
                Profile = charKey,
                Hash = snapshot:HashValue(),
                Selector = stored and stored:GetSelector(),
            }, snapshotModules)
        end
        return stored
    end, onComplete)
end

--[[ Preview / Apply ]]

-- Preview applying a snapshot (a stored entry, the live snapshot, or an import)
-- over the connected character's current setup. cached diffs against the
-- already-captured Current instead of re-scanning the live setup, for cheap
-- repeated previews.
function SnapshotManager:Preview(snapshot, moduleSet, cached)
    Snapshot.Validate(snapshot, 2)
    local liveSnapshot = cached and ProfileManager:GetLiveSnapshot() or ProfileManager:RefreshLiveSnapshot()
    return Differ:Preview(liveSnapshot and liveSnapshot:Modules(), snapshot:Modules(), moduleSet)
end

--[[ Apply ]]

-- Apply a snapshot (a stored entry, the live snapshot, or an import) to the connected
-- character. strategy = { default = "merge"|"exact", overrides = { [name]=mode } }.
-- A full rollback snapshot of Current is pushed to the undo stack first.
function SnapshotManager:Apply(snapshot, strategy, moduleSet)
    Snapshot.Validate(snapshot, 2)
    return ApplyCapturedModules(snapshot:Modules(), BuildApplyMeta(snapshot), strategy, moduleSet, {
        Profile = snapshot:GetCharacterInfo().Key,
    })
end

--[[ Undo ]]

function SnapshotManager:CanUndo()
    return ProfileManager:HasUndo()
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
function SnapshotManager:GetNextUndoPoint()
    local rollbackSnapshot = ProfileManager:PeekUndo()
    if not rollbackSnapshot then
        return nil
    end

    return DescribeRollbackSnapshot(rollbackSnapshot)
end

-- Preview what undoing the most recent apply would change: the top rollback
-- snapshot re-applied in Exact mode over the current setup. Nil when there is
-- nothing to undo.
function SnapshotManager:PreviewUndo()
    local rollbackSnapshot = ProfileManager:PeekUndo()
    if not rollbackSnapshot then
        return nil
    end
    return self:Preview(rollbackSnapshot)
end

-- The undo points newest-first, each describing one apply that can be rolled
-- back. Index 1 is the most recent (what a single UndoLastApply reverts); undoing
-- to a deeper index rolls back every apply above it as well.
function SnapshotManager:GetUndoPoints()
    local rollbackSnapshots = ProfileManager:ListUndo()
    local undoPoints = {}
    for i = #rollbackSnapshots, 1, -1 do
        tinsert(undoPoints, DescribeRollbackSnapshot(rollbackSnapshots[i]))
    end
    return undoPoints
end

-- Roll back the most recent apply by re-applying the top rollback snapshot in
-- Exact mode (optionally limited to a subset), then pop it off the stack.
function SnapshotManager:UndoLastApply(moduleSet)
    if InCombatLockdown() then
        return nil
    end

    -- Finish any in-flight save first so it cannot capture a half-undone setup.
    SaveTask:Drain()

    local snapshot = ProfileManager:PeekUndo()
    if not snapshot then
        return nil
    end

    local applyMeta = BuildApplyMeta(snapshot)
    local rollbackModules = snapshot:Modules()
    local moduleNames = ResolveModuleNames(rollbackModules, moduleSet)

    local debugHandle = Debugger:IsEnabled() and Debugger:BeginOperation("undo", {
        Subject = snapshot:GetSubject(),
    }, moduleNames)

    WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_UNDO_STARTED")
    local applyResults = ApplyModules(rollbackModules, applyMeta, moduleNames, { default = "exact" })
    ProfileManager:PopUndo()
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
function SnapshotManager:UndoApplies(count)
    count = count or 1
    local aggregate = ApplyResult:New()
    for _ = 1, count do
        if not ProfileManager:HasUndo() then
            break
        end

        local stepResult = self:UndoLastApply()
        if stepResult then
            aggregate:Merge(stepResult)
        end
    end

    return aggregate
end

