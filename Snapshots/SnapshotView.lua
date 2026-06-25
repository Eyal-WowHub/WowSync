local _, addon = ...
local SnapshotView = addon:NewObject("SnapshotView")

local C = LibStub("Contracts-1.0")
local Snapshot = addon:GetObject("Snapshot")

--[[
    SnapshotView — the accessor/mutator onto a single snapshot handle.

    Callers (notably the companion UI) never read a snapshot's stored fields;
    they hold an opaque handle and ask SnapshotView for what a feature needs.
    Every read models an intent (a note, a pinned flag, the modules it carries)
    rather than the storage shape, and every write is validated. This keeps the
    on-disk format free to change without touching anything outside storage.

    A handle stands for either a stored snapshot or a character's live "head"
    (its current, unsaved setup); SnapshotView interprets either shape.
]]

local ProfileStore = addon:GetObject("ProfileStore")
local SnapshotManager = addon:GetObject("SnapshotManager")

-- Per-handle cache of the character-info DTO, weak so an entry is collected with
-- the handle it describes. The fields it holds (owning key, captured character,
-- class) are fixed for the life of a handle, so the DTO can be reused.
local characterInfo = setmetatable({}, { __mode = "k" })

local function SortedNames(set)
    local moduleNames = {}
    if set then
        for name in pairs(set) do
            tinsert(moduleNames, name)
        end
    end
    table.sort(moduleNames)
    return moduleNames
end

-- The content fingerprint a handle stands for, used to tell whether applying it
-- would change anything.
local function HashOf(handle)
    if handle.isHead then
        return handle.head.Hash
    end
    return handle.raw.Hash
end

--[[ Reads ]]

-- True for a character's live head (its current, unsaved setup) versus a saved snapshot.
function SnapshotView:IsHead(handle)
    return handle.isHead
end

-- True when the handle is the logged-in character's own head.
function SnapshotView:IsOwnCharacter(handle)
    return handle.isHead and handle.head.IsCurrent or false
end

-- The character a snapshot belongs to: its owning profile key, the character it
-- was captured from, and the class it was captured on.
function SnapshotView:GetCharacterInfo(handle)
    local cachedCharacterInfo = characterInfo[handle]
    if cachedCharacterInfo then
        return cachedCharacterInfo
    end

    local snapshotCharacterInfo
    if handle.isHead then
        snapshotCharacterInfo = {
            Key = handle.charKey,
            Character = handle.charKey,
            ClassID = handle.head.ClassID,
        }
    else
        local snapshotSource = handle.raw.Source
        snapshotCharacterInfo = {
            Key = handle.charKey,
            Character = snapshotSource and snapshotSource.Character,
            ClassID = snapshotSource and snapshotSource.ClassID,
        }
    end

    characterInfo[handle] = snapshotCharacterInfo
    return snapshotCharacterInfo
end

-- The moment the snapshot was captured (the head reports when it was last seen).
function SnapshotView:GetTimestamp(handle)
    if handle.isHead then
        return handle.head.LastSeen
    end
    return handle.raw.Timestamp
end

-- The editable note attached to a saved snapshot ("" for the head or when unset).
function SnapshotView:GetNotes(handle)
    if handle.isHead then
        return ""
    end
    return handle.raw.Notes or ""
end

-- True when the snapshot is pinned (exempt from pruning). The head is never pinned.
function SnapshotView:IsPinned(handle)
    return (not handle.isHead) and handle.raw.Pinned or false
end

-- The sorted module names the snapshot carries.
function SnapshotView:GetModuleNames(handle)
    if handle.isHead then
        return SortedNames(handle.head.Modules)
    end
    return Snapshot:GetModuleNames(handle.raw)
end

-- True when the snapshot is identical to the logged-in character's current setup
-- (so applying it would change nothing).
function SnapshotView:IsCurrent(handle)
    local currentHead = SnapshotManager:GetCharInfo()
    return currentHead ~= nil and HashOf(handle) == currentHead.Hash
end

--[[ Writes (validated) ]]

-- Set the editable note on a saved snapshot. No-op for the head.
function SnapshotView:SetNotes(handle, text)
    C:IsString(text, 3)
    if handle.isHead then
        return
    end
    ProfileStore:SetSnapshotNotes(handle.charKey, Snapshot:GetSelector(handle.raw), text)
end

-- Pin a saved snapshot so pruning skips it. No-op for the head.
function SnapshotView:Pin(handle)
    if handle.isHead then
        return
    end
    ProfileStore:PinSnapshot(handle.charKey, Snapshot:GetSelector(handle.raw))
end

-- Unpin a previously pinned snapshot. No-op for the head.
function SnapshotView:Unpin(handle)
    if handle.isHead then
        return
    end
    ProfileStore:UnpinSnapshot(handle.charKey, Snapshot:GetSelector(handle.raw))
end

--[[ Operations ]]

-- Preview applying the snapshot (optionally a module subset) over the logged-in
-- character's current setup.
function SnapshotView:Preview(handle, moduleSet)
    if handle.isHead then
        return SnapshotManager:PreviewApplyHeadByCharKey(handle.charKey, moduleSet)
    end
    return SnapshotManager:PreviewApplySnapshot(handle.charKey, Snapshot:GetSelector(handle.raw), moduleSet)
end

-- Apply the snapshot (optionally a module subset) to the logged-in character,
-- pushing a rollback snapshot first. Returns an ApplyResult.
function SnapshotView:Apply(handle, strategy, moduleSet)
    if handle.isHead then
        return SnapshotManager:ApplyHeadByCharKey(handle.charKey, strategy, moduleSet)
    end
    return SnapshotManager:ApplySnapshot(handle.charKey, Snapshot:GetSelector(handle.raw), strategy, moduleSet)
end

-- Permanently remove a saved snapshot from its character's history. No-op for the head.
function SnapshotView:Delete(handle)
    if handle.isHead then
        return
    end
    SnapshotManager:DeleteSnapshot(handle.charKey, Snapshot:GetSelector(handle.raw))
end
