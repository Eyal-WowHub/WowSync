local _, addon = ...
local ImportManager = addon:NewObject("ImportManager")

--[[
    ImportManager — the import subsystem's facade.

    It turns a pasted shared string back into a stored imported snapshot and
    manages the class-locked containers that hold imported history. Imports
    decode the shared string (via ShareCodec, which validates the untrusted
    shape), build a snapshot from it, then hand it to ImportStore (which enforces
    the container's class). Applying an imported snapshot defers to
    SnapshotManager.
]]

local C = addon.Contracts
local Snapshot = addon.Snapshot
local SnapshotInfo = addon.SnapshotInfo
local Time = addon.Time

local ImportStore = addon:GetObject("ImportStore")
local ShareCodec = addon:GetObject("ShareCodec")
local SnapshotManager = addon:GetObject("SnapshotManager")

-- Build a storable snapshot from decoded shared data, keeping the original
-- capture time and note and recording when it was imported.
local function BuildImportSnapshot(sharedData)
    local snapshotInfo = SnapshotInfo:CreateForSavedSnapshot(sharedData.Modules, { ClassID = sharedData.ClassID })
    snapshotInfo.Timestamp = sharedData.Timestamp
    snapshotInfo.Notes = sharedData.Notes
    snapshotInfo.ImportedAt = Time:Now()
    return snapshotInfo
end

-- Selector parts: a hash (or prefix) and an optional #Index disambiguator.
local function ParseSelector(selector)
    local hash, indexText = selector:match("^([%w]+)#(%d+)$")
    if indexText then
        return hash:lower(), tonumber(indexText)
    end
    return selector:lower(), nil
end

-- Resolve an entry within a container by hash/prefix, optionally pinned to a
-- specific #Index. Returns the raw stored entry, or nil + a reason
-- ("not-found" / "ambiguous") + candidates. Entries are hashed through the
-- store, which normalizes a payload-less duplicate shell to its owner's hash.
local function FindSnapshot(container, selector)
    local snapshots = container.Snapshots
    local hash, snapshotIndex = ParseSelector(selector)

    if snapshotIndex then
        for index = 1, #snapshots do
            local snapshot = snapshots[index]
            if snapshot.Index == snapshotIndex then
                if ImportStore:HashOf(container, snapshot):sub(1, #hash) == hash then
                    return snapshot
                end
                return nil, "not-found"
            end
        end
        return nil, "not-found"
    end

    local match, candidates
    for index = 1, #snapshots do
        if ImportStore:HashOf(container, snapshots[index]):sub(1, #hash) == hash then
            if match then
                candidates = candidates or { match }
                tinsert(candidates, snapshots[index])
            else
                match = snapshots[index]
            end
        end
    end

    if candidates then
        return nil, "ambiguous", candidates
    end
    if match then
        return match
    end
    return nil, "not-found"
end

-- Resolve importID + selector to (container, entry). The container is returned
-- even when only the snapshot is missing, alongside nil + reason + candidates.
local function ResolveEntry(importID, selector)
    local container = ImportStore:GetImport(importID)
    if not container then
        return nil, nil, "not-found"
    end
    local snapshot, reason, candidates = FindSnapshot(container, selector)
    return container, snapshot, reason, candidates
end

--[[ Import ]]

-- Import a shared string. With opts.targetID it is appended to that container;
-- otherwise a new container named opts.name is created. Returns
-- { ImportID, Name, Duplicate }, or nil + a reason.
function ImportManager:ImportString(text, opts)
    C:IsString(text, 2)
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

    local container, importIDOrReason = ImportStore:CreateImport(opts.name, sharedData.ClassID)
    if not container then
        return nil, importIDOrReason
    end

    local importID = importIDOrReason
    local stored, warning = ImportStore:AddSnapshot(importID, snapshot)
    if not stored then
        ImportStore:DeleteImport(importID)
        return nil, warning
    end
    return { ImportID = importID, Name = container.Name, Duplicate = warning == "duplicate" }
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
    for importID, container in pairs(ImportStore:GetImports()) do
        local snapshots = container.Snapshots
        local lastImported
        for index = 1, #snapshots do
            local importedAt = snapshots[index].ImportedAt
            if importedAt and (not lastImported or importedAt > lastImported) then
                lastImported = importedAt
            end
        end
        tinsert(list, {
            ID = importID,
            Name = container.Name,
            ClassID = container.ClassID,
            Created = container.Created,
            Order = container.Order or container.Created or 0,
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
    C:IsString(importID, 2)
    return ImportStore:GetImport(importID)
end

-- A container's snapshots, oldest-first (empty when the id is unknown). These
-- are the raw stored records: the import list is a curated storage view (its
-- dedup/origin flags and per-row chrome read import-only fields), so it works
-- with them directly rather than through Snapshot.
function ImportManager:GetSnapshots(importID)
    C:IsString(importID, 2)
    return ImportStore:GetSnapshots(importID)
end

-- Resolve one imported snapshot by selector as a Snapshot object (its payload
-- followed to the owner), for the shared apply/preview UI. Nil + a reason when
-- it cannot be resolved.
function ImportManager:GetSnapshot(importID, selector)
    C:IsString(importID, 2)
    C:IsString(selector, 3)
    local container, snapshot, reason = ResolveEntry(importID, selector)
    if not snapshot then
        return nil, reason or "not-found"
    end
    return Snapshot:From(nil, ImportStore:ResolvePayload(container, snapshot))
end

-- Rename a container. Returns true, or false + a reason.
function ImportManager:RenameImport(importID, name)
    C:IsString(importID, 2)
    C:IsString(name, 3)
    return ImportStore:RenameImport(importID, name)
end

-- Remove a container and its snapshots. Returns whether one was removed.
function ImportManager:DeleteImport(importID)
    C:IsString(importID, 2)
    return ImportStore:DeleteImport(importID)
end

-- Move a container one step up within its class group. Returns whether it moved.
function ImportManager:MoveImportUp(importID)
    C:IsString(importID, 2)
    return ImportStore:MoveImport(importID, -1)
end

-- Move a container one step down within its class group. Returns whether it moved.
function ImportManager:MoveImportDown(importID)
    C:IsString(importID, 2)
    return ImportStore:MoveImport(importID, 1)
end

-- Remove one snapshot from a container by selector. Returns whether one was removed.
function ImportManager:DeleteSnapshot(importID, selector)
    C:IsString(importID, 2)
    C:IsString(selector, 3)
    local container, snapshot = ResolveEntry(importID, selector)
    if not snapshot then
        return false
    end
    return ImportStore:RemoveSnapshot(container, snapshot)
end

-- How many duplicates would be removed alongside the snapshot at selector, so
-- the UI can warn before deleting an owner that others reference.
function ImportManager:CountDependentDuplicates(importID, selector)
    C:IsString(importID, 2)
    C:IsString(selector, 3)
    local container, snapshot = ResolveEntry(importID, selector)
    if not snapshot then
        return 0
    end
    return ImportStore:CountDependents(container, snapshot)
end

-- Replace an imported snapshot's editable note. Returns whether it was found.
function ImportManager:SetSnapshotNotes(importID, selector, text)
    C:IsString(importID, 2)
    C:IsString(selector, 3)
    C:IsString(text, 4)
    local _, snapshot = ResolveEntry(importID, selector)
    if not snapshot then
        return false
    end
    snapshot.Notes = text
    return true
end

-- Pin an imported snapshot, floating it to the top of the container as a marked
-- reference. Returns whether it was found.
function ImportManager:PinSnapshot(importID, selector)
    C:IsString(importID, 2)
    C:IsString(selector, 3)
    local _, snapshot = ResolveEntry(importID, selector)
    if not snapshot then
        return false
    end
    snapshot.Pinned = true
    return true
end

-- Clear an imported snapshot's pin. Returns whether it was found.
function ImportManager:UnpinSnapshot(importID, selector)
    C:IsString(importID, 2)
    C:IsString(selector, 3)
    local _, snapshot = ResolveEntry(importID, selector)
    if not snapshot then
        return false
    end
    snapshot.Pinned = false
    return true
end

--[[ Apply ]]

-- Preview applying an imported snapshot over the logged-in character's Current.
-- Returns the preview, or nil + a reason.
function ImportManager:PreviewApplySnapshot(importID, selector, moduleSet)
    C:IsString(importID, 2)
    C:IsString(selector, 3)
    local container, snapshot, reason = ResolveEntry(importID, selector)
    if not snapshot then
        return nil, reason or "not-found"
    end
    return SnapshotManager:Preview(Snapshot:From(nil, ImportStore:ResolvePayload(container, snapshot)), moduleSet)
end

-- Apply an imported snapshot to the logged-in character, pushing a rollback
-- snapshot first. Returns the apply results, or nil + a reason.
function ImportManager:ApplySnapshot(importID, selector, strategy, moduleSet)
    C:IsString(importID, 2)
    C:IsString(selector, 3)
    local container, snapshot, reason = ResolveEntry(importID, selector)
    if not snapshot then
        return nil, reason or "not-found"
    end
    return SnapshotManager:Apply(Snapshot:From(nil, ImportStore:ResolvePayload(container, snapshot)), strategy, moduleSet)
end
