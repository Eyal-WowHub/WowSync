local _, addon = ...
local ImportStore = addon:NewObject("ImportStore")

local Time = addon.Time

--[[
    ImportStore — storage for imported profiles.

    An imported profile is a named, class-locked container of snapshots brought
    in from another character. Unlike a real profile it has no live Current, no
    undo stack and no head; it is purely a curated history. Records live under
    DB.Imports, keyed by a generated numeric id:

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

-- Trim surrounding whitespace from a display name.
local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- True when classID names a real player class.
local function IsValidClassID(classID)
    return type(classID) == "number" and C_CreatureInfo.GetClassInfo(classID) ~= nil
end

-- True when a container with this name (case-insensitively) already exists,
-- ignoring the container with skipID.
local function NameTaken(name, skipID)
    local needle = Trim(name):lower()
    for importID, record in pairs(imports) do
        if importID ~= skipID and record.Name:lower() == needle then
            return true
        end
    end
    return false
end

-- Selector parts: a hash (or prefix) and an optional #Index disambiguator.
local function ParseSelector(selector)
    local hash, indexText = selector:match("^([%w]+)#(%d+)$")
    if indexText then
        return hash:lower(), tonumber(indexText)
    end
    return selector:lower(), nil
end

-- Resolve a snapshot within a container by hash/prefix, optionally pinned to a
-- specific #Index. Returns snapshot, array index — or nil, nil, reason.
local function FindSnapshot(record, selector)
    local snapshots = record.Snapshots
    local hash, snapshotIndex = ParseSelector(selector)

    if snapshotIndex then
        for index = 1, #snapshots do
            local snapshot = snapshots[index]
            if snapshot.Index == snapshotIndex then
                if snapshot.Hash:sub(1, #hash) == hash then
                    return snapshot, index
                end
                return nil, nil, "not-found"
            end
        end
        return nil, nil, "not-found"
    end

    local match, matchIndex, candidates
    for index = 1, #snapshots do
        if snapshots[index].Hash:sub(1, #hash) == hash then
            if match then
                candidates = candidates or { match }
                tinsert(candidates, snapshots[index])
            else
                match, matchIndex = snapshots[index], index
            end
        end
    end

    if candidates then
        return nil, nil, "ambiguous", candidates
    end
    if match then
        return match, matchIndex
    end
    return nil, nil, "not-found"
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
-- record and its id, or nil + a reason ("invalid-name", "invalid-class",
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

    local record = {
        Name = Trim(name),
        ClassID = classID,
        Created = Time:Now(),
        NextIndex = 1,
        Snapshots = {},
    }
    imports[importID] = record
    return record, importID
end

-- Rename a container. Returns true, or false + a reason ("not-found",
-- "invalid-name", "duplicate-name").
function ImportStore:RenameImport(importID, name)
    local record = imports[importID]
    if not record then
        return false, "not-found"
    end
    if type(name) ~= "string" or Trim(name) == "" then
        return false, "invalid-name"
    end
    if NameTaken(name, importID) then
        return false, "duplicate-name"
    end

    record.Name = Trim(name)
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
    local record = imports[importID]
    if not record then
        return false
    end

    local group = {}
    for id, entry in pairs(imports) do
        if entry.ClassID == record.ClassID then
            group[#group + 1] = { id = id, record = entry }
        end
    end
    if #group < 2 then
        return false
    end

    table.sort(group, function(a, b)
        local ao = a.record.Order or a.record.Created or 0
        local bo = b.record.Order or b.record.Created or 0
        if ao ~= bo then
            return ao < bo
        end
        return a.id < b.id
    end)

    -- Normalise to sequential orders so the swap below always moves the row.
    for index = 1, #group do
        group[index].record.Order = index
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

    group[pos].record.Order, group[target].record.Order =
        group[target].record.Order, group[pos].record.Order
    return true
end

--[[ Snapshot history ]]

-- The container entry that carries its own payload for this hash (the owner), or
-- nil. Duplicates drop their heavy Data and reference the owner's Index instead.
local function FindOwner(record, hash)
    for index = 1, #record.Snapshots do
        local entry = record.Snapshots[index]
        if entry.Hash == hash and entry.Ref == nil then
            return entry
        end
    end
    return nil
end

-- The container entry with this per-container Index, or nil.
local function FindByIndex(record, snapshotIndex)
    for index = 1, #record.Snapshots do
        if record.Snapshots[index].Index == snapshotIndex then
            return record.Snapshots[index]
        end
    end
    return nil
end

-- A duplicate stores no payload of its own; resolve it against its owner so
-- callers always see a snapshot with the real Data. Owners resolve to themselves.
local function ResolvePayload(record, snapshot)
    if snapshot.Ref == nil then
        return snapshot
    end
    local owner = FindByIndex(record, snapshot.Ref)
    if not owner then
        return snapshot
    end
    local resolved = {}
    for key, value in pairs(snapshot) do
        resolved[key] = value
    end
    resolved.Data = owner.Data
    resolved.Modules = owner.Modules
    return resolved
end

-- Append a snapshot to a container, enforcing the container's class. A snapshot
-- whose Hash is already present is stored lean: its heavy Data is dropped and a
-- Ref points at the owner (the first entry with that Hash), which keeps the
-- payload. Returns the stored snapshot and a warning ("duplicate" when its Hash
-- was already present), or nil + a reason ("not-found", "class-mismatch").
function ImportStore:AddSnapshot(importID, snapshot)
    local record = imports[importID]
    if not record then
        return nil, "not-found"
    end

    local classID = snapshot.Source and snapshot.Source.ClassID
    if classID ~= record.ClassID then
        return nil, "class-mismatch"
    end

    local warning
    local owner = FindOwner(record, snapshot.Hash)
    if owner then
        warning = "duplicate"
        -- Share the owner's payload when it is compressed; the raw-fallback case
        -- (no Data) is rare enough to keep as an independent copy.
        if owner.Data ~= nil then
            snapshot.Data = nil
            snapshot.Ref = owner.Index
        end
    end

    snapshot.Index = record.NextIndex
    record.NextIndex = record.NextIndex + 1
    tinsert(record.Snapshots, snapshot)
    return snapshot, warning
end

-- The container's snapshots, oldest-first (empty when the id is unknown).
function ImportStore:GetSnapshots(importID)
    local record = imports[importID]
    return record and record.Snapshots or {}
end

-- Resolve a snapshot in a container by selector, following a duplicate's Ref to
-- the owner so the returned snapshot always carries the real payload. Returns
-- snapshot, reason, candidates (mirrors ProfileStore:GetSnapshot).
function ImportStore:GetSnapshot(importID, selector)
    local record = imports[importID]
    if not record then
        return nil, "not-found"
    end
    local snapshot, _, reason, candidates = FindSnapshot(record, selector)
    if not snapshot then
        return nil, reason, candidates
    end
    return ResolvePayload(record, snapshot), reason, candidates
end

-- Remove a snapshot from a container by selector. Deleting an owner (a snapshot
-- that duplicates reference) also removes those duplicates, since they hold no
-- payload of their own. Returns whether anything was removed.
function ImportStore:DeleteSnapshot(importID, selector)
    local record = imports[importID]
    if not record then
        return false
    end

    local snapshot, index = FindSnapshot(record, selector)
    if not index then
        return false
    end

    if snapshot.Ref == nil then
        local ownerIndex = snapshot.Index
        for i = #record.Snapshots, 1, -1 do
            local entry = record.Snapshots[i]
            if entry == snapshot or entry.Ref == ownerIndex then
                tremove(record.Snapshots, i)
            end
        end
    else
        tremove(record.Snapshots, index)
    end
    return true
end

-- How many duplicates reference the snapshot addressed by selector (0 when it is
-- itself a duplicate or has no dependents). Lets callers warn before a cascade.
function ImportStore:CountDependentDuplicates(importID, selector)
    local record = imports[importID]
    if not record then
        return 0
    end

    local snapshot = FindSnapshot(record, selector)
    if not snapshot or snapshot.Ref ~= nil then
        return 0
    end

    local count = 0
    for index = 1, #record.Snapshots do
        if record.Snapshots[index].Ref == snapshot.Index then
            count = count + 1
        end
    end
    return count
end

-- Replace a snapshot's editable note. Returns whether the snapshot was found.
function ImportStore:SetSnapshotNotes(importID, selector, text)
    local record = imports[importID]
    if not record then
        return false
    end

    local snapshot = FindSnapshot(record, selector)
    if not snapshot then
        return false
    end

    snapshot.Notes = text
    return true
end

-- Pin a snapshot in a container by selector, protecting it from nothing (imports
-- never prune) but floating it to the top of the list as a marked reference.
-- Pins the exact entry addressed, whether it owns its hash or duplicates one.
-- Returns whether it was found.
function ImportStore:PinSnapshot(importID, selector)
    local record = imports[importID]
    if not record then
        return false
    end

    local snapshot = FindSnapshot(record, selector)
    if not snapshot then
        return false
    end

    snapshot.Pinned = true
    return true
end

-- Clear a snapshot's pin by selector. Returns whether it was found.
function ImportStore:UnpinSnapshot(importID, selector)
    local record = imports[importID]
    if not record then
        return false
    end

    local snapshot = FindSnapshot(record, selector)
    if not snapshot then
        return false
    end

    snapshot.Pinned = false
    return true
end
