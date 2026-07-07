local _, addon = ...
local SnapshotManager = addon:NewObject("SnapshotManager")

local C = addon.Contracts
local ApplyResult = addon.ApplyResult
local ModuleRegistry = addon.ModuleRegistry
local Snapshot = addon.Snapshot

local CharacterInfo = LibStub("CharacterInfo-1.0")

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
        CharacterName = CharacterInfo:GetFullName(),
        ClassID = PlayerUtil.GetClassID(),
    }
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

-- Shared apply core: capture a FULL rollback snapshot of Current before touching
-- anything (so any change, including Exact deletions and per-module undo, can be
-- rolled back), then apply the given module set with the per-module strategy.
-- The rollback snapshot is only pushed to the undo stack when an apply actually
-- happens. Returns an ApplyResult.
local function ApplyCapturedModules(snapshot, moduleSet, strategy)
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
    local rollbackSnapshot = Snapshot:FromCapturedModuleSet(liveSnapshot:Modules(), BuildCurrentSource())

    local sourceModules = snapshot:Modules()
    local moduleNames = snapshot:GetModuleNames(moduleSet)

    local debugHandle = Debugger:IsEnabled() and Debugger:BeginOperation("apply", {
        Profile = snapshot:GetCharacterInfo().Key,
        Strategy = strategy,
    }, moduleNames)

    -- Announce the write so the live-mirror watcher pauses: our own apply fires
    -- the very game events it tracks, and it must not mirror them back as if the
    -- player had made them.
    WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_APPLY_STARTED")
    local applyResults, applied = ModuleRegistry:ApplyModules(moduleNames, sourceModules, strategy, snapshot:GetClassID())
    -- Only record an undo point when an apply actually happened.
    if applied then
        WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_APPLY_CHANGED", rollbackSnapshot)
        ProfileManager:RefreshLiveSnapshot()
    end
    WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_APPLY_FINISHED")

    if Debugger:IsEnabled() then
        Debugger:EndOperation(debugHandle, sourceModules, applyResults)
    end

    return ApplyResult:New(applyResults)
end

--[[ Current ]]

-- True when the logged-in character has anything captured to save.
function SnapshotManager:HasCapturedGameData()
    return ProfileManager:GetLiveSnapshot(ProfileManager:GetCurrentProfile()) ~= nil
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
        local snapshot = Snapshot:FromCapturedModuleSet(snapshotModules, BuildCurrentSource())

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
    local profile = ProfileManager:GetProfile(charKey or CharacterInfo:GetFullName())
    return profile and ProfileManager:PendingEviction(profile) or nil
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
        local profile = ProfileManager:GetProfile(charKey)
        local liveSnapshot = profile and ProfileManager:GetLiveSnapshot(profile)
        if not liveSnapshot then
            return nil, "unknown-character"
        end

        local snapshotModules = FilterCapturedModules(liveSnapshot:Modules(), moduleSet)
        local snapshot = Snapshot:FromCapturedModuleSet(snapshotModules, {
            CharacterName = charKey,
            ClassID = liveSnapshot:GetClassID(),
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
    local liveSnapshot = cached and ProfileManager:GetLiveSnapshot(ProfileManager:GetCurrentProfile())
        or ProfileManager:RefreshLiveSnapshot()
    return Differ:Preview(liveSnapshot and liveSnapshot:Modules(), snapshot:Modules(), moduleSet)
end

--[[ Apply ]]

-- Apply a snapshot (a stored entry, the live snapshot, or an import) to the connected
-- character. strategy = { default = "merge"|"exact", overrides = { [name]=mode } }.
-- A full rollback snapshot of Current is pushed to the undo stack first.
function SnapshotManager:Apply(snapshot, strategy, moduleSet)
    Snapshot.Validate(snapshot, 2)
    return ApplyCapturedModules(snapshot, moduleSet, strategy)
end

