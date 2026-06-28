local _, addon = ...
local SnapshotManager = addon:NewObject("SnapshotManager")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local C = LibStub("Contracts-1.0")
local SnapshotApplyMode = addon.SnapshotApplyMode
local ApplyResult = addon.ApplyResult

--[[
    SnapshotManager — the snapshot subsystem's orchestrator/facade.

    It owns no state of its own; it coordinates the registry, the profile
    history (ProfileStore), the per-character live setup (CurrentStore), the
    rollback snapshot stack (UndoStore), the snapshot value-object (Snapshot), and
    the apply preview (Differ).

    Flow:
      Save    -> capture Current, build a Snapshot, append to the profile
                 (skipped when nothing changed since the latest snapshot).
      Apply   -> push a FULL rollback snapshot of Current to the undo stack, then
                 apply the chosen snapshot's modules (per-module Merge/Exact).
      Undo    -> re-apply the top rollback snapshot in Exact mode, then pop it.
]]

local ModuleRegistry = addon:GetObject("ModuleRegistry")
local ProfileStore = addon:GetObject("ProfileStore")
local CurrentStore = addon:GetObject("CurrentStore")
local UndoStore = addon:GetObject("UndoStore")
local Snapshot = addon:GetObject("Snapshot")
local Differ = addon:GetObject("Differ")
local GameWatcher = addon:GetObject("GameWatcher")
local SaveTask = addon:GetObject("SaveTask")
local Debugger = addon:GetObject("Debugger")

function SnapshotManager:OnInitialized()
    -- Finish any in-flight sliced save before SavedVariables is written, so an
    -- explicit Save started just before logout still lands. Draining re-captures
    -- Current as a raw table, so compress it again here; CurrentStore's logout
    -- handler also ends in a compress, so whichever of the two runs last leaves
    -- Current stored compressed.
    self:RegisterEvent("PLAYER_LOGOUT", function()
        SaveTask:Drain()
        CurrentStore:Compress()
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

-- The meta passed to a module's CanApply/Apply, derived from a snapshot's source.
local function BuildApplyMeta(snapshot)
    return { ClassID = snapshot.Source and snapshot.Source.ClassID }
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
    local defaultMode = strategy.default or "merge"
    local overrides = strategy.overrides or {}

    local rollbackSnapshot = Snapshot:New(CurrentStore:Capture(), BuildCurrentSource())

    local moduleNames = ResolveModuleNames(sourceModules, moduleSet)
    local applyResults = {}
    local applied = false

    local debugHandle = Debugger:IsEnabled() and Debugger:BeginOperation("apply", {
        Profile = info and info.Profile,
        Selector = info and info.Selector,
        Strategy = strategy,
    }, moduleNames)

    -- Don't let our own writes echo back in as if the player made them.
    GameWatcher:SuspendTracking()

    -- Apply in module priority order so dependencies (e.g. Macros) land before
    -- the modules that reference them (e.g. ActionBars).
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

    if applied then
        UndoStore:Push(nil, rollbackSnapshot)
        CurrentStore:Capture()
    end

    GameWatcher:ResumeTracking()
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

--[[ Current ]]

-- Re-capture the logged-in character's live setup; returns the captured modules.
function SnapshotManager:CaptureGameData()
    return CurrentStore:Capture()
end

-- True when the logged-in character has anything captured to save.
function SnapshotManager:HasCapturedGameData()
    local capturedModules = CurrentStore:Get()
    return capturedModules ~= nil and next(capturedModules) ~= nil
end

-- The logged-in character's profile key (its full name).
function SnapshotManager:GetCurrentCharKey()
    return CharacterInfo:GetFullName()
end

-- A derived "head" describing a character's current setup (live for the
-- logged-in character, last-captured for an alt), or nil when nothing is
-- captured. Not a stored snapshot: it carries a content Hash but no Index. The
-- companion UI floats it above the saved history as the always-current top of
-- the timeline.
function SnapshotManager:GetCharInfo(charKey)
    charKey = charKey or CharacterInfo:GetFullName()

    local capturedModules = CurrentStore:Get(charKey)
    if not capturedModules or not next(capturedModules) then
        return nil
    end

    local charMeta = CurrentStore:GetMetadata(charKey)
    return {
        Hash = Snapshot:Fingerprint(capturedModules),
        Modules = capturedModules,
        LastSeen = charMeta and charMeta.LastSeen,
        ClassID = charMeta and charMeta.ClassID,
        IsCurrent = charKey == CharacterInfo:GetFullName(),
    }
end

-- The soft cap on snapshots kept per character profile.
function SnapshotManager:GetSnapshotLimit()
    return ProfileStore:GetMaxSnapshots()
end

--[[ Save ]]

-- Capture Current (optionally a subset) and append it as a snapshot to the
-- logged-in character's profile, tagging it with the given optional note. The
-- capture and fingerprint are sliced across frames, bracketed by
-- WOWSYNC_SAVE_STARTED/FINISHED so the UI can show progress; the stored
-- snapshot is handed to onComplete.
function SnapshotManager:SaveCurrentSnapshot(note, moduleSet, onComplete)
    if InCombatLockdown() then
        if onComplete then onComplete(nil, "combat") end
        return
    end

    SaveTask:Run(function()
        local snapshotModules = FilterCapturedModules(CurrentStore:Capture(), moduleSet)

        local profileName = CharacterInfo:GetFullName()
        ProfileStore:CreateProfile(profileName)

        local snapshot = Snapshot:New(snapshotModules, BuildCurrentSource())
        snapshot.Notes = note

        local stored = ProfileStore:AddSnapshot(profileName, snapshot)
        if Debugger:IsEnabled() then
            Debugger:RecordSave({
                Profile = profileName,
                Hash = snapshot.Hash,
                Selector = stored and stored.Index,
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
    return ProfileStore:PendingEviction(charKey)
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
        local capturedModules = CurrentStore:Get(charKey)
        if not capturedModules then
            return nil, "unknown-character"
        end

        local snapshotModules = FilterCapturedModules(capturedModules, moduleSet)

        local characterMetadata = CurrentStore:GetMetadata(charKey)
        ProfileStore:CreateProfile(charKey)

        local snapshot = Snapshot:New(snapshotModules, {
            Character = charKey,
            ClassID = characterMetadata and characterMetadata.ClassID,
        })
        snapshot.Notes = note

        local stored = ProfileStore:AddSnapshot(charKey, snapshot)
        if Debugger:IsEnabled() then
            Debugger:RecordSave({
                Profile = charKey,
                Hash = snapshot.Hash,
                Selector = stored and stored.Index,
            }, snapshotModules)
        end
        return stored
    end, onComplete)
end

--[[ Preview ]]

-- Preview applying a profile snapshot (latest when selector is nil) over Current.
function SnapshotManager:PreviewApplySnapshot(profileName, selector, moduleSet)
    C:IsString(profileName, 2)

    local snapshot
    if selector then
        snapshot = ProfileStore:GetSnapshot(profileName, selector)
    else
        snapshot = ProfileStore:GetLatestSnapshot(profileName)
    end
    if not snapshot then
        return nil
    end

    local currentModules = CurrentStore:Capture()
    return Differ:Preview(currentModules, Snapshot:GetModules(snapshot), moduleSet)
end

-- Preview applying a character's current setup (its head) over the logged-in
-- character's Current. Mirrors PreviewApplySnapshot but sources a character's
-- live or last-captured modules instead of a stored snapshot.
function SnapshotManager:PreviewApplyHeadByCharKey(charKey, moduleSet)
    C:IsString(charKey, 2)

    local sourceModules = CurrentStore:Get(charKey)
    if not sourceModules then
        return nil
    end

    local currentModules = CurrentStore:Capture()
    return Differ:Preview(currentModules, sourceModules, moduleSet)
end

--[[ Apply ]]

-- Apply a profile snapshot (latest when selector is nil) to the current character.
-- strategy = { default = "merge"|"exact", overrides = { [name] = mode } }.
-- A full rollback snapshot of Current is pushed to the undo stack first.
function SnapshotManager:ApplySnapshot(profileName, selector, strategy, moduleSet)
    C:IsString(profileName, 2)

    local snapshot
    if selector then
        snapshot = ProfileStore:GetSnapshot(profileName, selector)
    else
        snapshot = ProfileStore:GetLatestSnapshot(profileName)
    end
    C:Ensures(snapshot, "ApplySnapshot: profile '%s' has no snapshot to apply", profileName)

    return ApplyCapturedModules(Snapshot:GetModules(snapshot), BuildApplyMeta(snapshot), strategy, moduleSet, {
        Profile = profileName,
        Selector = selector,
    })
end

-- Apply a character's current setup (its head) to the logged-in character. Like
-- ApplySnapshot, but sources a character's live or last-captured modules instead
-- of a stored snapshot. A full rollback snapshot of Current is pushed first.
function SnapshotManager:ApplyHeadByCharKey(charKey, strategy, moduleSet)
    C:IsString(charKey, 2)

    local sourceModules = CurrentStore:Get(charKey)
    C:Ensures(sourceModules, "ApplyHeadByCharKey: character '%s' has nothing captured", charKey)

    local characterMetadata = CurrentStore:GetMetadata(charKey)
    local applyMeta = { ClassID = characterMetadata and characterMetadata.ClassID }
    return ApplyCapturedModules(sourceModules, applyMeta, strategy, moduleSet, { Profile = charKey })
end

--[[ Undo ]]

function SnapshotManager:CanUndo()
    return UndoStore:Has()
end

-- Subject + sorted module names describing a single rollback snapshot.
local function DescribeRollbackSnapshot(rollbackSnapshot)
    local moduleNames = {}
    for name in pairs(rollbackSnapshot.Modules) do
        tinsert(moduleNames, name)
    end
    table.sort(moduleNames)

    return {
        Subject = Snapshot:GetSubject(rollbackSnapshot),
        Timestamp = rollbackSnapshot.Timestamp,
        ModuleNames = moduleNames,
    }
end

-- Subject + module names of the change that UndoLastApply would roll back.
function SnapshotManager:GetNextUndoPoint()
    local rollbackSnapshot = UndoStore:Peek()
    if not rollbackSnapshot then
        return nil
    end

    return DescribeRollbackSnapshot(rollbackSnapshot)
end

-- Preview what undoing the most recent apply would change: the top rollback
-- snapshot re-applied in Exact mode over the current setup. Nil when there is
-- nothing to undo.
function SnapshotManager:PreviewUndo()
    local rollbackSnapshot = UndoStore:Peek()
    if not rollbackSnapshot then
        return nil
    end

    return Differ:Preview(CurrentStore:Capture(), Snapshot:GetModules(rollbackSnapshot))
end

-- The undo points newest-first, each describing one apply that can be rolled
-- back. Index 1 is the most recent (what a single UndoLastApply reverts); undoing
-- to a deeper index rolls back every apply above it as well.
function SnapshotManager:GetUndoPoints()
    local rollbackSnapshots = UndoStore:List()
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

    local rollbackSnapshot = UndoStore:Peek()
    if not rollbackSnapshot then
        return nil
    end

    local applyMeta = BuildApplyMeta(rollbackSnapshot)
    local rollbackModules = Snapshot:GetModules(rollbackSnapshot)
    local moduleNames = ResolveModuleNames(rollbackModules, moduleSet)
    local applyResults = {}

    local debugHandle = Debugger:IsEnabled() and Debugger:BeginOperation("undo", {
        Subject = Snapshot:GetSubject(rollbackSnapshot),
    }, moduleNames)

    GameWatcher:SuspendTracking()

    for name in pairs(moduleNames) do
        local module = ModuleRegistry:Get(name)
        local capturedData = rollbackModules[name]

        if module and capturedData ~= nil then
            local applySucceeded, applyError = pcall(module.Apply, module, capturedData, applyMeta, { mode = "exact" })
            if applySucceeded then
                applyResults[name] = { applied = true }
            else
                applyResults[name] = { applied = false, reason = tostring(applyError) }
            end
        end
    end

    UndoStore:Pop()
    CurrentStore:Capture()
    GameWatcher:ResumeTracking()
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
        if not UndoStore:Has() then
            break
        end

        local stepResult = self:UndoLastApply()
        if stepResult then
            aggregate:Merge(stepResult)
        end
    end

    return aggregate
end

--[[ Snapshot read/management ]]

-- Resolve a snapshot within a profile by exact hash, unambiguous prefix, or
-- <hash>#<index>. Returns snapshot, or nil + reason + candidates.
function SnapshotManager:GetSnapshot(profileName, selector)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    return ProfileStore:GetSnapshot(profileName, selector)
end

function SnapshotManager:DeleteSnapshot(profileName, selector)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    return ProfileStore:DeleteSnapshot(profileName, selector)
end

function SnapshotManager:SetSnapshotNotes(profileName, selector, text)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    C:IsString(text, 4)
    return ProfileStore:SetSnapshotNotes(profileName, selector, text)
end

function SnapshotManager:PinSnapshot(profileName, selector)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    return ProfileStore:PinSnapshot(profileName, selector)
end

function SnapshotManager:UnpinSnapshot(profileName, selector)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    return ProfileStore:UnpinSnapshot(profileName, selector)
end
