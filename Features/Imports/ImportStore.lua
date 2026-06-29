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
    rejected. A snapshot whose Hash already exists in the container is still
    stored, but the add reports it as a duplicate so callers can warn. There is no
    cap and no pruning; imports are user-curated.
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

--[[ Snapshot history ]]

-- Append a snapshot to a container, enforcing the container's class. Returns the
-- stored snapshot and a warning ("duplicate" when its Hash was already present),
-- or nil + a reason ("not-found", "class-mismatch").
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
    for index = 1, #record.Snapshots do
        if record.Snapshots[index].Hash == snapshot.Hash then
            warning = "duplicate"
            break
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

-- Resolve a snapshot in a container by selector. Returns snapshot, reason,
-- candidates (mirrors ProfileStore:GetSnapshot).
function ImportStore:GetSnapshot(importID, selector)
    local record = imports[importID]
    if not record then
        return nil, "not-found"
    end
    local snapshot, _, reason, candidates = FindSnapshot(record, selector)
    return snapshot, reason, candidates
end

-- Remove a snapshot from a container by selector. Returns whether one was removed.
function ImportStore:DeleteSnapshot(importID, selector)
    local record = imports[importID]
    if not record then
        return false
    end

    local _, index = FindSnapshot(record, selector)
    if not index then
        return false
    end

    tremove(record.Snapshots, index)
    return true
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
