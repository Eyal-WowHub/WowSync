local _, addon = ...
local ProfileManager = addon:NewObject("ProfileManager")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local C = LibStub("Contracts-1.0")
local SnapshotApplyMode = addon.SnapshotApplyMode

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

function ProfileManager:OnInitialized()
    registry = addon:GetObject("ModuleRegistry")
    profileStore = addon:GetObject("ProfileStore")
    currentStore = addon:GetObject("CurrentStore")
    undoStore = addon:GetObject("UndoStore")
    snapshots = addon:GetObject("Snapshot")
    differ = addon:GetObject("Differ")
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

-- Capture Current (optionally a subset) and append it to a profile's history.
-- Returns the stored snapshot, or nil + "unchanged" when nothing changed since
-- the profile's latest snapshot.
function ProfileManager:Save(profileName, moduleSet, body)
    C:IsString(profileName, 2)
    C:Ensures(profileName ~= "", "Save: 'profileName' must be a non-empty string")

    local current = currentStore:Refresh()

    local modules = current
    if moduleSet then
        modules = {}
        for name in pairs(moduleSet) do
            if current[name] ~= nil then
                modules[name] = current[name]
            end
        end
    end

    local snapshot = snapshots:New(modules, CurrentSource())
    snapshot.Body = body

    return profileStore:AddSnapshot(profileName, snapshot)
end

--[[ Preview ]]

-- Preview applying a profile snapshot (latest when hash is nil) over Current.
function ProfileManager:PreviewApply(profileName, hash, moduleSet)
    C:IsString(profileName, 2)

    local snapshot = hash and profileStore:GetSnapshot(profileName, hash)
        or profileStore:GetLatestSnapshot(profileName)
    if not snapshot then
        return nil
    end

    local current = currentStore:Refresh()
    return differ:Preview(current, snapshot.Modules, moduleSet)
end

--[[ Apply ]]

-- Apply a profile snapshot (latest when hash is nil) to the current character.
-- strategy = { default = "merge"|"exact", overrides = { [name] = mode } }.
-- A full safety snapshot of Current is pushed to the undo stack first.
function ProfileManager:Apply(profileName, hash, strategy, moduleSet)
    C:IsString(profileName, 2)

    local snapshot = hash and profileStore:GetSnapshot(profileName, hash)
        or profileStore:GetLatestSnapshot(profileName)
    C:Ensures(snapshot, "Apply: profile '%s' has no snapshot to apply", profileName)

    strategy = strategy or {}
    local defaultMode = strategy.default or "merge"
    local overrides = strategy.overrides or {}

    -- Capture a FULL safety snapshot of Current before touching anything so any
    -- change (including Exact deletions and per-module undo) can be rolled
    -- back. It is only pushed to the undo stack if an apply actually happens.
    local safety = snapshots:New(currentStore:Refresh(), CurrentSource())

    local meta = MetaOf(snapshot)
    local names = ResolveNames(snapshot.Modules, moduleSet)
    local results = {}
    local applied = false

    for name in pairs(names) do
        local module = registry:Get(name)
        local data = snapshot.Modules[name]

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

    return results
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
    return results
end

-- Roll back the most recent `count` applies, newest first, by undoing one step
-- at a time. Returns the aggregated per-module results across every step that
-- ran (later steps win when a module appears in more than one).
function ProfileManager:UndoSteps(count)
    count = count or 1
    local results = {}
    for _ = 1, count do
        if not undoStore:Has() then
            break
        end

        local step = self:Undo()
        if step then
            for name, result in pairs(step) do
                results[name] = result
            end
        end
    end

    return results
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

function ProfileManager:RenameProfile(oldName, newName)
    C:IsString(oldName, 2)
    C:IsString(newName, 3)
    C:Ensures(newName ~= "", "RenameProfile: 'newName' must be a non-empty string")
    return profileStore:RenameProfile(oldName, newName)
end

--[[ Snapshot read/management ]]

function ProfileManager:DeleteSnapshot(profileName, hash)
    C:IsString(profileName, 2)
    C:IsString(hash, 3)
    return profileStore:DeleteSnapshot(profileName, hash)
end

function ProfileManager:SetSnapshotBody(profileName, hash, text)
    C:IsString(profileName, 2)
    C:IsString(hash, 3)
    C:IsString(text, 4)
    return profileStore:SetSnapshotBody(profileName, hash, text)
end

function ProfileManager:PinSnapshot(profileName, hash)
    C:IsString(profileName, 2)
    C:IsString(hash, 3)
    return profileStore:PinSnapshot(profileName, hash)
end

function ProfileManager:UnpinSnapshot(profileName, hash)
    C:IsString(profileName, 2)
    C:IsString(hash, 3)
    return profileStore:UnpinSnapshot(profileName, hash)
end

--[[ Cross-character ]]

-- Other characters (not the logged-in one) that have a captured Current,
-- newest-seen first: { { Key, ClassID, LastSeen }, ... }. Drives the
-- cross-character browser; capture happens on each character's logout.
function ProfileManager:GetOtherCharacters()
    local me = CharacterInfo:GetFullName()
    local out = {}

    for key, entry in pairs(currentStore:GetCharacters()) do
        if key ~= me and entry.Current and next(entry.Current) then
            tinsert(out, {
                Key = key,
                ClassID = entry.Meta and entry.Meta.ClassID,
                LastSeen = entry.Meta and entry.Meta.LastSeen,
            })
        end
    end

    table.sort(out, function(a, b)
        return (a.LastSeen or 0) > (b.LastSeen or 0)
    end)

    return out
end

-- The captured Current modules for a character (read-only), or nil when unknown.
function ProfileManager:GetCharacterCurrent(charKey)
    C:IsString(charKey, 2)
    return currentStore:Get(charKey)
end

-- Build a snapshot from another character's captured Current and append it to a
-- profile. Like Save, but sources a stored character instead of a live capture,
-- so the snapshot's identity reflects that character. Returns the stored
-- snapshot, or nil + a reason ("unknown-character" / "unchanged").
function ProfileManager:SaveFromCharacter(profileName, charKey, moduleSet, body)
    C:IsString(profileName, 2)
    C:Ensures(profileName ~= "", "SaveFromCharacter: 'profileName' must be a non-empty string")
    C:IsString(charKey, 3)

    local source = currentStore:Get(charKey)
    if not source then
        return nil, "unknown-character"
    end

    local modules = source
    if moduleSet then
        modules = {}
        for name in pairs(moduleSet) do
            if source[name] ~= nil then
                modules[name] = source[name]
            end
        end
    end

    local meta = currentStore:GetMeta(charKey)
    local snapshot = snapshots:New(modules, {
        Character = charKey,
        ClassID = meta and meta.ClassID,
    })
    snapshot.Body = body

    return profileStore:AddSnapshot(profileName, snapshot)
end
