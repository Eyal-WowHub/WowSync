local _, addon = ...
local ImportManager = addon:NewObject("ImportManager")

local Time = addon.Time

--[[
    ImportManager — the import subsystem's facade.

    It turns a pasted shared string back into a stored imported snapshot and
    manages the class-locked containers that hold imported history. Imports
    decode the shared string (via ShareCodec, which validates the untrusted
    shape), build a snapshot from it, then hand it to ImportStore (which enforces
    the container's class). Applying an imported snapshot defers to
    SnapshotManager.
]]

local ShareCodec = addon:GetObject("ShareCodec")
local ImportStore = addon:GetObject("ImportStore")
local SnapshotManager = addon:GetObject("SnapshotManager")
local Snapshot = addon:GetObject("Snapshot")

-- Build a storable snapshot from decoded shared data, keeping the original
-- capture time and note and recording when it was imported.
local function BuildImportSnapshot(sharedData)
    local snapshot = Snapshot:New(sharedData.Modules, { ClassID = sharedData.ClassID })
    snapshot.Timestamp = sharedData.Timestamp
    snapshot.Notes = sharedData.Notes
    snapshot.ImportedAt = Time:Now()
    return snapshot
end

--[[ Import ]]

-- Import a shared string. With opts.targetID it is appended to that container;
-- otherwise a new container named opts.name is created. Returns
-- { ImportID, Name, Duplicate }, or nil + a reason.
function ImportManager:ImportString(text, opts)
    opts = opts or {}

    local sharedData, reason = ShareCodec:Decode(text)
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
-- the UI can group them by class and reorder within a group. The logged-in
-- character's class leads, then the remaining classes by id; a container's order
-- is "Order, else Created", so a never-reordered group reads in creation order.
-- Each entry is
-- { ID, Name, ClassID, Created, Order, SnapshotCount, LastImported }.
function ImportManager:GetProfiles()
    local currentClassID = select(3, UnitClass("player"))

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
            -- The logged-in character's class always comes first.
            local aCurrent = a.ClassID == currentClassID
            local bCurrent = b.ClassID == currentClassID
            if aCurrent ~= bCurrent then
                return aCurrent
            end
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
function ImportManager:GetSnapshots(importID)
    return ImportStore:GetSnapshots(importID)
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
