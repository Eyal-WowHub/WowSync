local _, addon = ...
local ProfileManager = addon:NewObject("ProfileManager")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local C = LibStub("Contracts-1.0")
local SnapshotApplyMode = addon.SnapshotApplyMode
local ApplyResult = addon.ApplyResult

--[[
    ProfileManager — the storage subsystem's orchestrator/facade.

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

local registry
local profileStore
local currentStore
local undoStore
local snapshots
local differ
local gameWatcher

function ProfileManager:OnInitialized()
    registry = addon:GetObject("ModuleRegistry")
    profileStore = addon:GetObject("ProfileStore")
    currentStore = addon:GetObject("CurrentStore")
    undoStore = addon:GetObject("UndoStore")
    snapshots = addon:GetObject("Snapshot")
    differ = addon:GetObject("Differ")
    gameWatcher = addon:GetObject("GameWatcher")
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
    strategy = strategy or {}
    local defaultMode = strategy.default or "merge"
    local overrides = strategy.overrides or {}

    local safety = snapshots:New(currentStore:Refresh(), CurrentSource())

    local names = ResolveNames(sourceModules, moduleSet)
    local results = {}
    local applied = false

    -- Don't let our own writes echo back in as if the player made them.
    gameWatcher:PauseForApply()

    for name in pairs(names) do
        local module = registry:Get(name)
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
        undoStore:Push(nil, safety)
        currentStore:Refresh()
    end

    gameWatcher:ResumeAfterApply()

    return ApplyResult:New(results)
end

--[[ Module Registration ]]

function ProfileManager:RegisterModule(module)
    registry:Register(module)
end

function ProfileManager:GetModule(name)
    return registry:Get(name)
end

function ProfileManager:IterableModules()
    return registry:Iterate()
end

-- The apply modes a module supports (None when unknown), so the apply UI can
-- offer Merge/Exact only where each is meaningful.
function ProfileManager:GetModuleSnapshotApplyMode(name)
    C:IsString(name, 2)
    local module = registry:Get(name)
    return module and module.Config and module.Config.SnapshotApplyMode or SnapshotApplyMode.None
end

--[[ Current ]]

-- Re-capture the logged-in character's live setup; returns the captured modules.
function ProfileManager:CaptureCurrent()
    return currentStore:Refresh()
end

--[[ Save ]]

-- Capture Current (optionally a subset) and append it as a snapshot to the
-- logged-in character's profile, tagging it with the given optional note.
-- Always appends a snapshot. Returns the profile id and the stored snapshot.
function ProfileManager:Save(note, moduleSet)
    local modules = SubsetOf(currentStore:Refresh(), moduleSet)

    local id = CharacterInfo:GetFullName()
    profileStore:CreateProfile(id)

    local snapshot = snapshots:New(modules, CurrentSource())
    snapshot.Body = note

    local stored, reason = profileStore:AddSnapshot(id, snapshot)
    return id, stored, reason
end

-- True when the logged-in character has anything captured to save.
function ProfileManager:HasCurrent()
    local current = currentStore:Get()
    return current ~= nil and next(current) ~= nil
end

-- The logged-in character's profile key (its full name).
function ProfileManager:GetCurrentCharacterKey()
    return CharacterInfo:GetFullName()
end

-- A derived "head" describing a character's current setup (live for the
-- logged-in character, last-captured for an alt), or nil when nothing is
-- captured. Not a stored snapshot: it carries a content Hash but no Index. The
-- companion UI floats it above the saved history as the always-current top of
-- the timeline.
function ProfileManager:GetCurrentHead(charKey)
    charKey = charKey or CharacterInfo:GetFullName()

    local current = currentStore:Get(charKey)
    if not current or not next(current) then
        return nil
    end

    local charMeta = currentStore:GetMeta(charKey)
    return {
        Hash = snapshots:Fingerprint(current),
        Modules = current,
        LastSeen = charMeta and charMeta.LastSeen,
        ClassID = charMeta and charMeta.ClassID,
        IsCurrent = charKey == CharacterInfo:GetFullName(),
    }
end

-- The soft cap on snapshots kept per character profile.
function ProfileManager:GetMaxSnapshots()
    return profileStore:GetMaxSnapshots()
end

-- Preview what saving the given module subset would do for a character
-- (default: the logged-in one). A save always creates a snapshot, so this only
-- reports the eviction it would cause. Returns:
--   evicted - the snapshot a save would prune to stay within MaxSnapshots, or
--             nil when nothing would be removed (under the cap, or all pinned).
function ProfileManager:PreviewSave(moduleSet, charKey)
    charKey = charKey or CharacterInfo:GetFullName()
    return profileStore:PendingEviction(charKey)
end

--[[ Preview ]]

-- Preview applying a profile snapshot (latest when selector is nil) over Current.
function ProfileManager:PreviewApply(profileName, selector, moduleSet)
    C:IsString(profileName, 2)

    local snapshot
    if selector then
        snapshot = profileStore:GetSnapshot(profileName, selector)
    else
        snapshot = profileStore:GetLatestSnapshot(profileName)
    end
    if not snapshot then
        return nil
    end

    local current = currentStore:Refresh()
    return differ:Preview(current, snapshot.Modules, moduleSet)
end

-- Preview applying a character's current setup (its head) over the logged-in
-- character's Current. Mirrors PreviewApply but sources a character's live or
-- last-captured modules instead of a stored snapshot.
function ProfileManager:PreviewApplyCurrentOf(charKey, moduleSet)
    C:IsString(charKey, 2)

    local source = currentStore:Get(charKey)
    if not source then
        return nil
    end

    local current = currentStore:Refresh()
    return differ:Preview(current, source, moduleSet)
end

--[[ Apply ]]

-- Apply a profile snapshot (latest when selector is nil) to the current character.
-- strategy = { default = "merge"|"exact", overrides = { [name] = mode } }.
-- A full safety snapshot of Current is pushed to the undo stack first.
function ProfileManager:Apply(profileName, selector, strategy, moduleSet)
    C:IsString(profileName, 2)

    local snapshot
    if selector then
        snapshot = profileStore:GetSnapshot(profileName, selector)
    else
        snapshot = profileStore:GetLatestSnapshot(profileName)
    end
    C:Ensures(snapshot, "Apply: profile '%s' has no snapshot to apply", profileName)

    return ApplyModules(snapshot.Modules, MetaOf(snapshot), strategy, moduleSet)
end

-- Apply a character's current setup (its head) to the logged-in character. Like
-- Apply, but sources a character's live or last-captured modules instead of a
-- stored snapshot. A full safety snapshot of Current is pushed first.
function ProfileManager:ApplyCurrentOf(charKey, strategy, moduleSet)
    C:IsString(charKey, 2)

    local source = currentStore:Get(charKey)
    C:Ensures(source, "ApplyCurrentOf: character '%s' has nothing captured", charKey)

    local charMeta = currentStore:GetMeta(charKey)
    local meta = { ClassID = charMeta and charMeta.ClassID }
    return ApplyModules(source, meta, strategy, moduleSet)
end

--[[ Undo ]]

function ProfileManager:HasUndo()
    return undoStore:Has()
end

-- Subject + sorted module names describing a single safety snapshot.
local function DescribeSafety(safety)
    local moduleNames = {}
    for name in pairs(safety.Modules) do
        tinsert(moduleNames, name)
    end
    table.sort(moduleNames)

    return {
        Subject = snapshots:GetSubject(safety),
        Timestamp = safety.Timestamp,
        ModuleNames = moduleNames,
    }
end

-- Subject + module names of the change that Undo would roll back.
function ProfileManager:GetUndoInfo()
    local safety = undoStore:Peek()
    if not safety then
        return nil
    end

    return DescribeSafety(safety)
end

-- The undo points newest-first, each describing one apply that can be rolled
-- back. Index 1 is the most recent (what a single Undo reverts); undoing to a
-- deeper index rolls back every apply above it as well.
function ProfileManager:GetUndoStack()
    local stack = undoStore:List()
    local out = {}
    for i = #stack, 1, -1 do
        tinsert(out, DescribeSafety(stack[i]))
    end
    return out
end

-- Roll back the most recent apply by re-applying the top safety snapshot in
-- Exact mode (optionally limited to a subset), then pop it off the stack.
function ProfileManager:Undo(moduleSet)
    local safety = undoStore:Peek()
    if not safety then
        return nil
    end

    local meta = MetaOf(safety)
    local names = ResolveNames(safety.Modules, moduleSet)
    local results = {}

    gameWatcher:PauseForApply()

    for name in pairs(names) do
        local module = registry:Get(name)
        local data = safety.Modules[name]

        if module and data ~= nil then
            local ok, err = pcall(module.Apply, module, data, meta, { mode = "exact" })
            if ok then
                results[name] = { applied = true }
            else
                results[name] = { applied = false, reason = tostring(err) }
            end
        end
    end

    undoStore:Pop()
    currentStore:Refresh()
    gameWatcher:ResumeAfterApply()
    return ApplyResult:New(results)
end

-- Roll back the most recent `count` applies, newest first, by undoing one step
-- at a time. Returns the aggregated per-module results across every step that
-- ran (later steps win when a module appears in more than one).
function ProfileManager:UndoSteps(count)
    count = count or 1
    local aggregate = ApplyResult:New()
    for _ = 1, count do
        if not undoStore:Has() then
            break
        end

        local step = self:Undo()
        if step then
            aggregate:Merge(step)
        end
    end

    return aggregate
end

--[[ Profile read/management ]]

function ProfileManager:GetProfile(profileName)
    return profileStore:GetProfile(profileName)
end

function ProfileManager:GetProfiles()
    return profileStore:GetProfiles()
end

function ProfileManager:DeleteProfile(profileName)
    C:IsString(profileName, 2)
    return profileStore:DeleteProfile(profileName)
end

-- Wipes every saved profile and all per-character data (snapshots, current
-- captures and undo history) while leaving user settings intact. The tables
-- are emptied in place so the stores' cached references stay valid; callers
-- are expected to reload the UI afterwards so every view reinitialises from
-- the now-empty database.
function ProfileManager:ResetDatabase()
    wipe(addon.DB.global.Profiles)
    wipe(addon.DB.global.Characters)
end

--[[ Snapshot read/management ]]

-- Resolve a snapshot within a profile by exact hash, unambiguous prefix, or
-- <hash>#<index>. Returns snapshot, or nil + reason + candidates.
function ProfileManager:GetSnapshot(profileName, selector)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    return profileStore:GetSnapshot(profileName, selector)
end

function ProfileManager:DeleteSnapshot(profileName, selector)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    return profileStore:DeleteSnapshot(profileName, selector)
end

function ProfileManager:SetSnapshotBody(profileName, selector, text)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    C:IsString(text, 4)
    return profileStore:SetSnapshotBody(profileName, selector, text)
end

function ProfileManager:PinSnapshot(profileName, selector)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    return profileStore:PinSnapshot(profileName, selector)
end

function ProfileManager:UnpinSnapshot(profileName, selector)
    C:IsString(profileName, 2)
    C:IsString(selector, 3)
    return profileStore:UnpinSnapshot(profileName, selector)
end

--[[ Cross-character ]]

-- Every character that has a profile (saved history) and/or a captured Current,
-- including the logged-in one. Drives the merged character list. Each entry:
--   { Key, ClassID, LastSeen, IsCurrent, HasCurrent, HasHistory }
-- Sorted with the logged-in character first, then most-recently-seen.
function ProfileManager:ListCharacters()
    local me = CharacterInfo:GetFullName()
    local byKey = {}

    local function ensure(key)
        local entry = byKey[key]
        if not entry then
            entry = { Key = key, IsCurrent = key == me }
            byKey[key] = entry
        end
        return entry
    end

    -- Characters with a captured Current (includes the logged-in one).
    for key, stored in pairs(currentStore:GetCharacters()) do
        if stored.Current and next(stored.Current) then
            local entry = ensure(key)
            entry.HasCurrent = true
            entry.ClassID = stored.Meta and stored.Meta.ClassID
            entry.LastSeen = stored.Meta and stored.Meta.LastSeen
        end
    end

    -- Characters with saved history; fill identity from the latest snapshot's
    -- source when no Current is present (e.g. data pruned but a profile kept).
    for key, profile in pairs(profileStore:GetProfiles()) do
        local history = profile.Snapshots
        if history and #history > 0 then
            local entry = ensure(key)
            entry.HasHistory = true
            if not entry.ClassID then
                local latest = history[#history]
                entry.ClassID = latest.Source and latest.Source.ClassID
                entry.LastSeen = entry.LastSeen or latest.Timestamp
            end
        end
    end

    local out = {}
    for _, entry in pairs(byKey) do
        tinsert(out, entry)
    end

    table.sort(out, function(a, b)
        if a.IsCurrent ~= b.IsCurrent then
            return a.IsCurrent
        end
        return (a.LastSeen or 0) > (b.LastSeen or 0)
    end)

    return out
end

-- Append a snapshot built from another character's captured Current to that
-- character's profile, tagging it with the given optional note. Like Save, but
-- sources a stored character instead of a live capture. Returns the stored
-- snapshot, or nil + a reason ("unknown-character").
function ProfileManager:SaveFromCharacter(charKey, moduleSet, note)
    C:IsString(charKey, 2)

    local source = currentStore:Get(charKey)
    if not source then
        return nil, "unknown-character"
    end

    local modules = SubsetOf(source, moduleSet)

    local meta = currentStore:GetMeta(charKey)
    profileStore:CreateProfile(charKey)

    local snapshot = snapshots:New(modules, {
        Character = charKey,
        ClassID = meta and meta.ClassID,
    })
    snapshot.Body = note

    return profileStore:AddSnapshot(charKey, snapshot)
end
