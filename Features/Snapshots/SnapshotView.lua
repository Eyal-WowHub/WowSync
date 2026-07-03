local _, addon = ...
local SnapshotView = addon:NewObject("SnapshotView")

--[[
    SnapshotView — deprecated thin shim over the Snapshot object.

    Snapshot is now a live object; callers should hold one and call its methods
    directly. This shim forwards the old handle-first calls to the object so the
    companion UI keeps working during the migration, and is removed once the UI
    is cut over.
]]

function SnapshotView:IsHead(snapshot)
    return snapshot:IsHead()
end

function SnapshotView:IsOwnCharacter(snapshot)
    return snapshot:IsCharacterConnected()
end

function SnapshotView:IsCurrent(snapshot)
    return snapshot:IsUpToDate()
end

function SnapshotView:GetCharacterInfo(snapshot)
    return snapshot:GetCharacterInfo()
end

function SnapshotView:GetTimestamp(snapshot)
    return snapshot:GetTimestamp()
end

function SnapshotView:GetNotes(snapshot)
    return snapshot:GetNotes()
end

function SnapshotView:IsPinned(snapshot)
    return snapshot:IsPinned()
end

function SnapshotView:GetModuleNames(snapshot)
    return snapshot:GetModuleNames()
end

function SnapshotView:GetSelector(snapshot)
    return snapshot:GetSelector()
end

function SnapshotView:SetNotes(snapshot, text)
    return snapshot:SetNotes(text)
end

function SnapshotView:Pin(snapshot)
    return snapshot:Pin()
end

function SnapshotView:Unpin(snapshot)
    return snapshot:Unpin()
end

function SnapshotView:Preview(snapshot, moduleSet, cached)
    return snapshot:Preview(moduleSet, cached)
end

function SnapshotView:Apply(snapshot, strategy, moduleSet)
    return snapshot:Apply(strategy, moduleSet)
end

function SnapshotView:Delete(snapshot)
    return snapshot:Delete()
end
