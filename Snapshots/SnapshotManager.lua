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
    safety-snapshot stack (UndoStore), the snapshot value-object (Snapshot), and
    the apply preview (Differ).

    Flow:
      Save    -> capture Current, build a Snapshot, append to the profile
                 (skipped when nothing changed since the latest snapshot).
      Apply   -> push a FULL safety snapshot of Current to the undo stack, then
                 apply the chosen snapshot's modules (per-module Merge/Exact).
      Undo    -> re-apply the top safety snapshot in Exact mode, then pop it.
]]

local ModuleRegistry = addon:GetObject("ModuleRegistry")
local ProfileStore = addon:GetObject("ProfileStore")
local CurrentStore = addon:GetObject("CurrentStore")
local UndoStore = addon:GetObject("UndoStore")
local Snapshot = addon:GetObject("Snapshot")
local Differ = addon:GetObject("Differ")
local GameWatcher = addon:GetObject("GameWatcher")
local SaveTask = addon:GetObject("SaveTask")

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

--[[ Internal helpers ]]

local function CurrentSource()
    return {
        Character = CharacterInfo:GetFullName(),
        ClassID = PlayerUtil.GetClassID(),
    }
end

-- The meta passed to a module's CanApply/Apply, derived from a snapshot's source.
local function MetaOf(snapshot)
    return { ClassID = snapshot.Source and snapshot.Source.ClassID }
end

-- The chosen module subset (intersected with what was actually captured), or
-- the whole capture when no subset is given.
local function SubsetOf(modules, moduleSet)
    if not moduleSet then
        return modules or {}
    end
    local subset = {}
    if modules then
        for name in pairs(moduleSet) do
            if modules[name] ~= nil then
                subset[name] = modules[name]
            end
        end
    end
    return subset
end

-- Resolve the effective set of module names: the chosen subset intersected with
-- what the snapshot actually contains, or everything in the snapshot when no
-- subset is given.
local function ResolveNames(moduleModules, moduleSet)
    local names = {}
    if moduleSet then
        for name in pairs(moduleSet) do
            if moduleModules[name] ~= nil then
                names[name] = true
            end
        end
    else
        for name in pairs(moduleModules) do
            names[name] = true
        end
    end
    return names
end

-- Shared apply core: capture a FULL safety snapshot of Current before touching
-- anything (so any change, including Exact deletions and per-module undo, can be
-- rolled back), then apply the given module set with the per-module strategy.
-- The safety snapshot is only pushed to the undo stack when an apply actually
-- happens. Returns an ApplyResult.
local function ApplyModules(sourceModules, meta, strategy, moduleSet)
    -- Finish any in-flight save first so it cannot capture a half-applied setup.
    SaveTask:Drain()

    strategy = strategy or {}
    local defaultMode = strategy.default or "merge"
    local overrides = strategy.overrides or {}

    local safety = Snapshot:New(CurrentStore:Capture(), CurrentSource())

    local names = ResolveNames(sourceModules, moduleSet)
    local results = {}
    local applied = false

    -- Don't let our own writes echo back in as if the player made them.
    GameWatcher:SuspendTracking()

    for name in pairs(names) do
        local module = ModuleRegistry:Get(name)
        local data = sourceModules[name]

        if module and data ~= nil then
            local canApply, warning = module:CanApply(meta)
            if not canApply then
                results[name] = { applied = false, reason = warning }
            else
                local mode = overrides[name] or defaultMode
                local ok, err = pcall(module.Apply, module, data, meta, { mode = mode })
                if ok then
                    results[name] = { applied = true, mode = mode, warning = warning }
                    applied = true
                else
                    results[name] = { applied = false, reason = tostring(err) }
                end
            end
        end
    end

    if applied then
        UndoStore:Push(nil, safety)
        CurrentStore:Capture()
    end

    GameWatcher:ResumeTracking()

    return ApplyResult:New(results)
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
    local current = CurrentStore:Get()
    return current ~= nil and next(current) ~= nil
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

    local current = CurrentStore:Get(charKey)
    if not current or not next(current) then
        return nil
    end

    local charMeta = CurrentStore:GetMetadata(charKey)
    return {
        Hash = Snapshot:Fingerprint(current),
        Modules = current,
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
    SaveTask:Run(function()
        local modules = SubsetOf(CurrentStore:Capture(), moduleSet)

        local id = CharacterInfo:GetFullName()
        ProfileStore:CreateProfile(id)

        local snapshot = Snapshot:New(modules, CurrentSource())
        snapshot.Notes = note

        return ProfileStore:AddSnapshot(id, snapshot)
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

    SaveTask:Run(function()
        local source = CurrentStore:Get(charKey)
        if not source then
            return nil, "unknown-character"
        end

        local modules = SubsetOf(source, moduleSet)

        local meta = CurrentStore:GetMetadata(charKey)
        ProfileStore:CreateProfile(charKey)

        local snapshot = Snapshot:New(modules, {
            Character = charKey,
            ClassID = meta and meta.ClassID,
        })
        snapshot.Notes = note

        return ProfileStore:AddSnapshot(charKey, snapshot)
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

    local current = CurrentStore:Capture()
    return Differ:Preview(current, Snapshot:GetModules(snapshot), moduleSet)
end

-- Preview applying a character's current setup (its head) over the logged-in
-- character's Current. Mirrors PreviewApplySnapshot but sources a character's
-- live or last-captured modules instead of a stored snapshot.
function SnapshotManager:PreviewApplyHeadByCharKey(charKey, moduleSet)
    C:IsString(charKey, 2)

    local source = CurrentStore:Get(charKey)
    if not source then
        return nil
    end

    local current = CurrentStore:Capture()
    return Differ:Preview(current, source, moduleSet)
end

--[[ Apply ]]

-- Apply a profile snapshot (latest when selector is nil) to the current character.
-- strategy = { default = "merge"|"exact", overrides = { [name] = mode } }.
-- A full safety snapshot of Current is pushed to the undo stack first.
function SnapshotManager:ApplySnapshot(profileName, selector, strategy, moduleSet)
    C:IsString(profileName, 2)

    local snapshot
    if selector then
        snapshot = ProfileStore:GetSnapshot(profileName, selector)
    else
        snapshot = ProfileStore:GetLatestSnapshot(profileName)
    end
    C:Ensures(snapshot, "Apply: profile '%s' has no snapshot to apply", profileName)

    return ApplyModules(Snapshot:GetModules(snapshot), MetaOf(snapshot), strategy, moduleSet)
end

-- Apply a character's current setup (its head) to the logged-in character. Like
-- ApplySnapshot, but sources a character's live or last-captured modules instead
-- of a stored snapshot. A full safety snapshot of Current is pushed first.
function SnapshotManager:ApplyHeadByCharKey(charKey, strategy, moduleSet)
    C:IsString(charKey, 2)

    local source = CurrentStore:Get(charKey)
    C:Ensures(source, "ApplyCurrentOf: character '%s' has nothing captured", charKey)

    local charMeta = CurrentStore:GetMetadata(charKey)
    local meta = { ClassID = charMeta and charMeta.ClassID }
    return ApplyModules(source, meta, strategy, moduleSet)
end

--[[ Undo ]]

function SnapshotManager:CanUndo()
    return UndoStore:Has()
end

-- Subject + sorted module names describing a single safety snapshot.
local function DescribeSafety(safety)
    local moduleNames = {}
    for name in pairs(safety.Modules) do
        tinsert(moduleNames, name)
    end
    table.sort(moduleNames)

    return {
        Subject = Snapshot:GetSubject(safety),
        Timestamp = safety.Timestamp,
        ModuleNames = moduleNames,
    }
end

-- Subject + module names of the change that UndoLastApply would roll back.
function SnapshotManager:GetNextUndoPoint()
    local safety = UndoStore:Peek()
    if not safety then
        return nil
    end

    return DescribeSafety(safety)
end

-- The undo points newest-first, each describing one apply that can be rolled
-- back. Index 1 is the most recent (what a single UndoLastApply reverts); undoing
-- to a deeper index rolls back every apply above it as well.
function SnapshotManager:GetUndoPoints()
    local stack = UndoStore:List()
    local out = {}
    for i = #stack, 1, -1 do
        tinsert(out, DescribeSafety(stack[i]))
    end
    return out
end

-- Roll back the most recent apply by re-applying the top safety snapshot in
-- Exact mode (optionally limited to a subset), then pop it off the stack.
function SnapshotManager:UndoLastApply(moduleSet)
    -- Finish any in-flight save first so it cannot capture a half-undone setup.
    SaveTask:Drain()

    local safety = UndoStore:Peek()
    if not safety then
        return nil
    end

    local meta = MetaOf(safety)
    local safetyModules = Snapshot:GetModules(safety)
    local names = ResolveNames(safetyModules, moduleSet)
    local results = {}

    GameWatcher:SuspendTracking()

    for name in pairs(names) do
        local module = ModuleRegistry:Get(name)
        local data = safetyModules[name]

        if module and data ~= nil then
            local ok, err = pcall(module.Apply, module, data, meta, { mode = "exact" })
            if ok then
                results[name] = { applied = true }
            else
                results[name] = { applied = false, reason = tostring(err) }
            end
        end
    end

    UndoStore:Pop()
    CurrentStore:Capture()
    GameWatcher:ResumeTracking()
    return ApplyResult:New(results)
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

        local step = self:UndoLastApply()
        if step then
            aggregate:Merge(step)
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
