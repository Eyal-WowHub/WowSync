local _, addon = ...
local UndoStore = addon:NewObject("UndoStore")

local BoundedList = addon.BoundedList

--[[
    UndoStore — a per-character stack of rollback snapshots.

    Before any apply, the current live setup is captured and pushed here so the
    change can be undone. Entries share the snapshotInfo shape and live on the
    record's Undo slice; UndoManager hands the record in, so this store is a
    stateless transformer over the slice it is given. The stack is capped at
    Settings.MaxUndo; the oldest entry is dropped when the cap is exceeded.
]]

-- Push a rollback snapshotInfo onto the record's undo stack, capping it at
-- Settings.MaxUndo (the oldest entry drops when the cap is exceeded).
function UndoStore:Push(profile, rollbackSnapshot)
    BoundedList:Wrap(profile.Undo, {
        max = function() return addon.DB.Settings.MaxUndo or 10 end,
    }):Push(rollbackSnapshot)
end

-- The most recent rollback snapshotInfo on the record, or nil when empty.
function UndoStore:Peek(profile)
    local rollbackStack = profile and profile.Undo
    return rollbackStack and rollbackStack[#rollbackStack]
end

-- Pop and return the most recent rollback snapshotInfo, or nil when empty.
function UndoStore:Pop(profile)
    local rollbackStack = profile and profile.Undo
    if rollbackStack and #rollbackStack > 0 then
        return tremove(rollbackStack)
    end
end

-- The record's undo stack (oldest-first), or an empty table when it has none.
function UndoStore:List(profile)
    return (profile and profile.Undo) or {}
end

-- True when the record has anything to undo.
function UndoStore:Has(profile)
    local rollbackStack = profile and profile.Undo
    return rollbackStack ~= nil and #rollbackStack > 0
end

-- Clear the record's undo stack.
function UndoStore:Clear(profile)
    if profile then
        profile.Undo = {}
    end
end
