local _, addon = ...
local ImportStore = addon:NewObject("ImportStore")

local SnapshotInfo = addon.SnapshotInfo
local Time = addon.Time

--[[
    ImportStore — storage for imported profiles.

    An imported profile is a named, class-locked container of snapshots brought
    in from another character. Unlike a real profile it has no live Current, no
    undo stack and no live snapshot; it is purely a curated history. Each container
    lives under DB.Imports, keyed by a generated numeric id:

        {
            Name      = <unique, user-given display name>,
            ClassID   = <fixed at creation; every snapshot must match it>,
            Created   = <moment the container was made (Core/Time)>,
            NextIndex = <next per-container snapshot Index to assign>,
            Snapshots = { <snapshot>, ... },  -- the Snapshot shape, oldest-first
        }

    The ClassID is the container's invariant: snapshots from a different class are
    rejected. A snapshot whose Hash already exists is still added as its own entry
    but stored lean: its heavy Data is dropped and a Ref points at the first entry
    with that Hash (the owner), which keeps the payload. Deleting an owner cascades
    to the duplicates that reference it. There is no cap and no pruning; imports
    are user-curated.
]]

local imports
local db
local FindByIndex

local ShareUtils = addon:GetObject("ShareUtils")
local Trim = ShareUtils.Trim
local IsValidClassID = ShareUtils.IsValidClassID

local function SnapshotHash(container, snapshot)
    if not snapshot then
        return nil
    end

    -- Import duplicates can be payload-less shells. Align them to their owner's
    -- normalized hash so duplicate grouping and selector matching stay stable.
    if snapshot.Ref ~= nil and snapshot.Data == nil and snapshot.ModuleHashes == nil then
        local owner = FindByIndex and FindByIndex(container, snapshot.Ref)
        if owner then
            local ownerHash = SnapshotInfo:HashValue(owner)
            snapshot.Hash = ownerHash
            if owner.ModuleHashes ~= nil then
                snapshot.ModuleHashes = owner.ModuleHashes
            end
            return ownerHash
        end
        return snapshot.Hash
    end

    return SnapshotInfo:HashValue(snapshot)
end

-- True when a container with this name (case-insensitively) already exists,
-- ignoring the container with skipID.
local function NameTaken(name, skipID)
    local needle = Trim(name):lower()
    for importID, container in pairs(imports) do
        if importID ~= skipID and container.Name:lower() == needle then
            return true
        end
    end
    return false
end

function ImportStore:OnInitialized()
    db = addon.DB
    imports = db.Imports
end

--[[ Container CRUD ]]

-- The map of imported profiles, keyed by id.
function ImportStore:GetImports()
    return imports
end

-- The imported profile with this id, or nil.
function ImportStore:GetImport(importID)
    return imports[importID]
end

-- Create an empty class-locked container with a unique name. Returns the
-- container and its id, or nil + a reason ("invalid-name", "invalid-class",
-- "duplicate-name").
function ImportStore:CreateImport(name, classID)
    if type(name) ~= "string" or Trim(name) == "" then
        return nil, "invalid-name"
    end
    if not IsValidClassID(classID) then
        return nil, "invalid-class"
    end
    if NameTaken(name) then
        return nil, "duplicate-name"
    end

    local importID = db.ImportSequence + 1
    db.ImportSequence = importID

    local container = {
        Name = Trim(name),
        ClassID = classID,
        Created = Time:Now(),
        NextIndex = 1,
        Snapshots = {},
    }
    imports[importID] = container
    return container, importID
end

-- Rename a container. Returns true, or false + a reason ("not-found",
-- "invalid-name", "duplicate-name").
function ImportStore:RenameImport(importID, name)
    local container = imports[importID]
    if not container then
        return false, "not-found"
    end
    if type(name) ~= "string" or Trim(name) == "" then
        return false, "invalid-name"
    end
    if NameTaken(name, importID) then
        return false, "duplicate-name"
    end

    container.Name = Trim(name)
    return true
end

-- Remove a container and its snapshots. Returns whether one was removed.
function ImportStore:DeleteImport(importID)
    if imports[importID] then
        imports[importID] = nil
        return true
    end
    return false
end

-- Move a container one step within its class group. direction is -1 (up) or +1
-- (down). The group's effective order is "Order, else Created", so an unmoved
-- group reads in creation order; the first move normalises the whole group to
-- sequential orders so a single swap always changes the neighbours' places.
-- Returns whether the container moved (false at a group boundary, for a lone
-- container, or when the id is unknown).
function ImportStore:MoveImport(importID, direction)
    local container = imports[importID]
    if not container then
        return false
    end

    local group = {}
    for id, entry in pairs(imports) do
        if entry.ClassID == container.ClassID then
            group[#group + 1] = { id = id, container = entry }
        end
    end
    if #group < 2 then
        return false
    end

    table.sort(group, function(a, b)
        local ao = a.container.Order or a.container.Created or 0
        local bo = b.container.Order or b.container.Created or 0
        if ao ~= bo then
            return ao < bo
        end
        return a.id < b.id
    end)

    -- Normalise to sequential orders so the swap below always moves the row.
    for index = 1, #group do
        group[index].container.Order = index
    end

    local pos
    for index = 1, #group do
        if group[index].id == importID then
            pos = index
            break
        end
    end

    local target = pos + direction
    if target < 1 or target > #group then
        return false
    end

    group[pos].container.Order, group[target].container.Order =
        group[target].container.Order, group[pos].container.Order
    return true
end

--[[ Snapshot history ]]

-- The container entry that carries its own payload for this hash (the owner), or
-- nil. Duplicates drop their heavy Data and reference the owner's Index instead.
local function FindOwner(container, hash)
    for index = 1, #container.Snapshots do
        local entry = container.Snapshots[index]
        if entry.Ref == nil and SnapshotHash(container, entry) == hash then
            return entry
        end
    end
    return nil
end

-- The container entry with this per-container Index, or nil.
FindByIndex = function(container, snapshotIndex)
    for index = 1, #container.Snapshots do
        if container.Snapshots[index].Index == snapshotIndex then
            return container.Snapshots[index]
        end
    end
    return nil
end

-- The normalized content hash of a stored entry, resolving a payload-less
-- duplicate shell to its owner's hash. A caller hashes entries through this when
-- resolving a selector to a stored entry.
function ImportStore:HashOf(container, snapshot)
    return SnapshotHash(container, snapshot)
end

-- A duplicate stores no payload of its own; resolve it against its owner so
-- callers always see a snapshot with the real Data. Owners resolve to themselves.
function ImportStore:ResolvePayload(container, snapshot)
    if snapshot.Ref == nil then
        return snapshot
    end
    local owner = FindByIndex(container, snapshot.Ref)
    if not owner then
        return snapshot
    end
    local resolved = {}
    for key, value in pairs(snapshot) do
        resolved[key] = value
    end
    resolved.Hash = SnapshotHash(container, snapshot)
    resolved.Data = owner.Data
    resolved.Modules = owner.Modules
    resolved.ModuleHashes = owner.ModuleHashes or snapshot.ModuleHashes
    return resolved
end

-- Append a snapshot to a container, enforcing the container's class. A snapshot
-- whose Hash is already present is stored lean: its heavy Data is dropped and a
-- Ref points at the owner (the first entry with that Hash), which keeps the
-- payload. Returns the stored snapshot and a warning ("duplicate" when its Hash
-- was already present), or nil + a reason ("not-found", "class-mismatch").
function ImportStore:AddSnapshot(importID, snapshot)
    local container = imports[importID]
    if not container then
        return nil, "not-found"
    end

    local classID = snapshot.Source and snapshot.Source.ClassID
    if classID ~= container.ClassID then
        return nil, "class-mismatch"
    end

    local warning
    local snapshotHash = SnapshotHash(container, snapshot)
    local owner = FindOwner(container, snapshotHash)
    if owner then
        warning = "duplicate"
        -- Share the owner's payload when it is compressed; the raw-fallback case
        -- (no Data) is rare enough to keep as an independent copy.
        if owner.Data ~= nil then
            snapshot.Data = nil
            snapshot.Ref = owner.Index
            if owner.ModuleHashes ~= nil then
                snapshot.ModuleHashes = owner.ModuleHashes
            end
        end
    end

    snapshot.Index = container.NextIndex
    container.NextIndex = container.NextIndex + 1
    tinsert(container.Snapshots, snapshot)
    return snapshot, warning
end

-- The container's snapshots, oldest-first (empty when the id is unknown).
function ImportStore:GetSnapshots(importID)
    local container = imports[importID]
    return container and container.Snapshots or {}
end

-- Remove a resolved snapshot entry from its container. Deleting an owner (an
-- entry that duplicates reference) also removes those duplicates, since they
-- hold no payload of their own. Returns whether anything was removed.
function ImportStore:RemoveSnapshot(container, snapshot)
    if snapshot.Ref == nil then
        local ownerIndex = snapshot.Index
        for i = #container.Snapshots, 1, -1 do
            local entry = container.Snapshots[i]
            if entry == snapshot or entry.Ref == ownerIndex then
                tremove(container.Snapshots, i)
            end
        end
    else
        for i = #container.Snapshots, 1, -1 do
            if container.Snapshots[i] == snapshot then
                tremove(container.Snapshots, i)
                break
            end
        end
    end
    return true
end

-- How many duplicates reference the given owner entry (0 when it is itself a
-- duplicate or has no dependents). Lets callers warn before an owner delete
-- cascades.
function ImportStore:CountDependents(container, snapshot)
    if snapshot.Ref ~= nil then
        return 0
    end
    local count = 0
    for index = 1, #container.Snapshots do
        if container.Snapshots[index].Ref == snapshot.Index then
            count = count + 1
        end
    end
    return count
end
