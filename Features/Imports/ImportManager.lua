local _, addon = ...
local ImportManager = addon:NewObject("ImportManager")

local Time = addon.Time
local Codec = addon.Codec

--[[
    ImportManager — the import/export subsystem's facade.

    It turns a profile snapshot or a character's head into a portable text string
    and turns a pasted string back into a stored imported snapshot. Exports are
    anonymised: only the class, capture time and note travel with the captured
    module data — character and realm names are dropped.

    The share format is an envelope: ENVELOPE_PREFIX followed by a single
    Codec-encoded payload carrying the raw module data plus its class, timestamp
    and note. Imports decode the envelope, validate the untrusted shape, then hand
    a freshly built snapshot to ImportStore (which enforces the container's
    class). Applying an imported snapshot defers to SnapshotManager.
]]

-- Identifies a WowSync share string; the rest is a Codec-encoded payload.
local ENVELOPE_PREFIX = "WSYNC1:"

local ImportStore = addon:GetObject("ImportStore")
local SnapshotManager = addon:GetObject("SnapshotManager")
local ProfileStore = addon:GetObject("ProfileStore")
local Snapshot = addon:GetObject("Snapshot")

-- Trim surrounding whitespace from a pasted string.
local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- True when classID names a real player class.
local function IsValidClassID(classID)
    return type(classID) == "number" and C_CreatureInfo.GetClassInfo(classID) ~= nil
end

-- Anonymise a captured module set into a share string. Returns the string, or
-- nil + a reason ("no-class", "encode-failed").
local function EncodeSharedString(modules, classID, timestamp, notes)
    if not IsValidClassID(classID) then
        return nil, "no-class"
    end

    local payload = {
        Timestamp = timestamp or Time:Now(),
        Source = { ClassID = classID },
        Notes = notes,
        Modules = modules,
    }

    local encoded, err = Codec:Encode(payload)
    if not encoded then
        return nil, err or "encode-failed"
    end
    return ENVELOPE_PREFIX .. encoded
end

-- Decode and validate an untrusted share string. Returns a normalised
-- { Modules, ClassID, Timestamp, Notes } table, or nil + a reason
-- ("invalid-input", "bad-format", "invalid-class").
local function DecodeSharedString(text)
    if type(text) ~= "string" then
        return nil, "invalid-input"
    end

    text = Trim(text)
    if text:sub(1, #ENVELOPE_PREFIX) ~= ENVELOPE_PREFIX then
        return nil, "bad-format"
    end

    local payload = Codec:Decode(text:sub(#ENVELOPE_PREFIX + 1))
    if type(payload) ~= "table" or type(payload.Modules) ~= "table" or next(payload.Modules) == nil then
        return nil, "bad-format"
    end
    for name in pairs(payload.Modules) do
        if type(name) ~= "string" then
            return nil, "bad-format"
        end
    end

    local classID = type(payload.Source) == "table" and payload.Source.ClassID or nil
    if not IsValidClassID(classID) then
        return nil, "invalid-class"
    end

    return {
        Modules = payload.Modules,
        ClassID = classID,
        Timestamp = type(payload.Timestamp) == "number" and payload.Timestamp or Time:Now(),
        Notes = type(payload.Notes) == "string" and payload.Notes or nil,
    }
end

-- Build a storable snapshot from decoded share data, keeping the original
-- capture time and note and recording when it was imported.
local function BuildImportSnapshot(sharedData)
    local snapshot = Snapshot:New(sharedData.Modules, { ClassID = sharedData.ClassID })
    snapshot.Timestamp = sharedData.Timestamp
    snapshot.Notes = sharedData.Notes
    snapshot.ImportedAt = Time:Now()
    return snapshot
end

--[[ Export ]]

-- Keep only the modules named in `allowed` (a { [name] = true } set). With no
-- set the full { [name] = data } table passes through unchanged.
local function FilterModules(modules, allowed)
    if not allowed then
        return modules
    end
    local filtered = {}
    for name, data in pairs(modules) do
        if allowed[name] then
            filtered[name] = data
        end
    end
    return filtered
end

-- Anonymised share string for a profile snapshot (latest when selector is
-- nil). opts.modules narrows the export to a { [name] = true } subset and
-- opts.notes sets the travelling note (falling back to the snapshot's own).
-- Returns the string, or nil + a reason.
function ImportManager:ExportSnapshot(profileName, selector, opts)
    opts = opts or {}

    local snapshot, reason
    if selector then
        snapshot, reason = ProfileStore:GetSnapshot(profileName, selector)
    else
        snapshot = ProfileStore:GetLatestSnapshot(profileName)
    end
    if not snapshot then
        return nil, reason or "not-found"
    end

    local modules = FilterModules(Snapshot:GetModules(snapshot), opts.modules)
    if next(modules) == nil then
        return nil, "no-modules"
    end

    local classID = snapshot.Source and snapshot.Source.ClassID
    local notes = opts.notes ~= nil and opts.notes or snapshot.Notes
    return EncodeSharedString(modules, classID, snapshot.Timestamp, notes)
end

-- Anonymised share string for a character's current head. opts.modules narrows
-- the export to a { [name] = true } subset and opts.notes attaches a note.
-- Returns the string, or nil + a reason.
function ImportManager:ExportHead(charKey, opts)
    opts = opts or {}

    local head = SnapshotManager:GetCharInfo(charKey)
    if not head then
        return nil, "not-found"
    end

    local modules = FilterModules(head.Modules, opts.modules)
    if next(modules) == nil then
        return nil, "no-modules"
    end
    return EncodeSharedString(modules, head.ClassID, head.LastSeen, opts.notes)
end

--[[ Import ]]

-- Import a share string. With opts.targetID it is appended to that container;
-- otherwise a new container named opts.name is created. Returns
-- { ImportID, Name, Duplicate }, or nil + a reason.
function ImportManager:ImportString(text, opts)
    opts = opts or {}

    local sharedData, reason = DecodeSharedString(text)
    if not sharedData then
        return nil, reason
    end

    local snapshot = BuildImportSnapshot(sharedData)

    if opts.targetID then
        local stored, warning = ImportStore:AddSnapshot(opts.targetID, snapshot)
        if not stored then
            return nil, warning
        end
        return { ImportID = opts.targetID, Duplicate = warning == "duplicate" }
    end

    local record, importIDOrReason = ImportStore:CreateImport(opts.name, sharedData.ClassID)
    if not record then
        return nil, importIDOrReason
    end

    local importID = importIDOrReason
    local stored, warning = ImportStore:AddSnapshot(importID, snapshot)
    if not stored then
        ImportStore:DeleteImport(importID)
        return nil, warning
    end
    return { ImportID = importID, Name = record.Name, Duplicate = warning == "duplicate" }
end

--[[ Containers (UI) ]]

-- The imported profiles as flat summaries, sorted by class then saved order so
-- the UI can group them by class and reorder within a group. A container's
-- order is "Order, else Created", so a never-reordered group reads in creation
-- order. Each entry is
-- { ID, Name, ClassID, Created, Order, SnapshotCount, LastImported }.
function ImportManager:GetImportedProfiles()
    local list = {}
    for importID, record in pairs(ImportStore:GetImports()) do
        local snapshots = record.Snapshots
        local lastImported
        for index = 1, #snapshots do
            local importedAt = snapshots[index].ImportedAt
            if importedAt and (not lastImported or importedAt > lastImported) then
                lastImported = importedAt
            end
        end
        tinsert(list, {
            ID = importID,
            Name = record.Name,
            ClassID = record.ClassID,
            Created = record.Created,
            Order = record.Order or record.Created or 0,
            SnapshotCount = #snapshots,
            LastImported = lastImported,
        })
    end

    table.sort(list, function(a, b)
        if a.ClassID ~= b.ClassID then
            return a.ClassID < b.ClassID
        end
        if a.Order ~= b.Order then
            return a.Order < b.Order
        end
        return a.Name:lower() < b.Name:lower()
    end)
    return list
end

-- A container by id, or nil.
function ImportManager:GetImport(importID)
    return ImportStore:GetImport(importID)
end

-- A container's snapshots, oldest-first (empty when the id is unknown).
function ImportManager:GetImportSnapshots(importID)
    return ImportStore:GetSnapshots(importID)
end

-- Map of hash -> owning container for every hash present across all imports, in
-- a single pass. The owner is the container holding the earliest-imported copy
-- (by ImportedAt; ties broken by the older container, then its id for
-- determinism). Each entry is { ID = importID, Name = containerName }. Lets the
-- UI resolve every row's owner from one scan instead of re-querying per row, and
-- leave the first-added copy unflagged while pointing later copies back at it.
function ImportManager:GetHashOwners()
    local owners = {}
    for importID, record in pairs(ImportStore:GetImports()) do
        local created = record.Created or 0
        for index = 1, #record.Snapshots do
            local hash = record.Snapshots[index].Hash
            if hash then
                local added = record.Snapshots[index].ImportedAt or 0
                local best = owners[hash]
                if not best
                    or added < best.Added
                    or (added == best.Added and created < best.Created)
                    or (added == best.Added and created == best.Created and importID < best.ID) then
                    owners[hash] = { ID = importID, Name = record.Name, Added = added, Created = created }
                end
            end
        end
    end
    return owners
end

-- Rename a container. Returns true, or false + a reason.
function ImportManager:RenameImport(importID, name)
    return ImportStore:RenameImport(importID, name)
end

-- Remove a container and its snapshots. Returns whether one was removed.
function ImportManager:DeleteImport(importID)
    return ImportStore:DeleteImport(importID)
end

-- Move a container one step up within its class group. Returns whether it moved.
function ImportManager:MoveImportUp(importID)
    return ImportStore:MoveImport(importID, -1)
end

-- Move a container one step down within its class group. Returns whether it moved.
function ImportManager:MoveImportDown(importID)
    return ImportStore:MoveImport(importID, 1)
end

-- Remove one snapshot from a container by selector. Returns whether one was removed.
function ImportManager:DeleteSnapshot(importID, selector)
    return ImportStore:DeleteSnapshot(importID, selector)
end

-- How many duplicates would be removed alongside the snapshot at selector, so
-- the UI can warn before deleting an owner that others reference.
function ImportManager:CountDependentDuplicates(importID, selector)
    return ImportStore:CountDependentDuplicates(importID, selector)
end

-- Replace an imported snapshot's editable note. Returns whether it was found.
function ImportManager:SetSnapshotNotes(importID, selector, text)
    return ImportStore:SetSnapshotNotes(importID, selector, text)
end

-- Pin an imported snapshot, floating it to the top of the container as a marked
-- reference. Returns whether it was found.
function ImportManager:PinSnapshot(importID, selector)
    return ImportStore:PinSnapshot(importID, selector)
end

-- Clear an imported snapshot's pin. Returns whether it was found.
function ImportManager:UnpinSnapshot(importID, selector)
    return ImportStore:UnpinSnapshot(importID, selector)
end

--[[ Apply ]]

-- Preview applying an imported snapshot over the logged-in character's Current.
-- Returns the preview, or nil + a reason.
function ImportManager:PreviewApplySnapshot(importID, selector, moduleSet)
    local snapshot, reason = ImportStore:GetSnapshot(importID, selector)
    if not snapshot then
        return nil, reason or "not-found"
    end
    return SnapshotManager:PreviewApplyImportSnapshot(snapshot, moduleSet)
end

-- Apply an imported snapshot to the logged-in character, pushing a rollback
-- snapshot first. Returns the apply results, or nil + a reason.
function ImportManager:ApplySnapshot(importID, selector, strategy, moduleSet)
    local snapshot, reason = ImportStore:GetSnapshot(importID, selector)
    if not snapshot then
        return nil, reason or "not-found"
    end
    return SnapshotManager:ApplyImportSnapshot(snapshot, strategy, moduleSet)
end
