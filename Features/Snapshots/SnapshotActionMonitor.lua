local _, addon = ...
local SnapshotActionMonitor = addon:NewObject("SnapshotActionMonitor")

--[[
    SnapshotActionMonitor — the single source of truth for "a snapshot action
    (save, apply or undo) is in progress."

    Save, apply and undo each bracket their work with STARTED/FINISHED lifecycle
    events. The apply and undo paths defer their FINISHED until every module's
    asynchronous work has settled (see AsyncTask), so an action stays counted for
    its entire duration -- sync body and async tail alike -- without this object
    needing to know async happened at all. It collapses the three actions into one
    busy state and re-broadcasts:

        WOWSYNC_SNAPSHOT_ACTION_STARTED  (kind = "save"|"apply"|"undo")
        WOWSYNC_SNAPSHOT_ACTION_FINISHED

    so any consumer can gate on "is a snapshot action happening" -- disabling
    buttons, pausing work -- without tracking each action individually.
]]

-- Snapshot actions currently in progress. An action is counted from its STARTED
-- event until its (possibly deferred) FINISHED event.
local activeActions = 0

-- The kind of the action that opened the current busy stretch, carried on
-- WOWSYNC_SNAPSHOT_ACTION_STARTED so a consumer can spin the matching button.
-- nil while idle.
local currentKind

local function IsBusy()
    return activeActions > 0
end

-- True while any snapshot action (including an async module's tail) runs.
function SnapshotActionMonitor:IsBusy()
    return IsBusy()
end

-- Re-broadcast a busy-state edge as the coarse snapshot-action events.
local function Emit(wasBusy)
    local busy = IsBusy()
    if busy == wasBusy then return end
    if busy then
        WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_ACTION_STARTED", currentKind)
    else
        currentKind = nil
        WowSync:TriggerEvent("WOWSYNC_SNAPSHOT_ACTION_FINISHED")
    end
end

local function Begin(kind)
    local wasBusy = IsBusy()
    if not wasBusy then
        currentKind = kind
    end
    activeActions = activeActions + 1
    Emit(wasBusy)
end

local function End()
    local wasBusy = IsBusy()
    if activeActions > 0 then
        activeActions = activeActions - 1
    end
    Emit(wasBusy)
end

function SnapshotActionMonitor:OnInitialized()
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_SAVE_STARTED", function() Begin("save") end)
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_SAVE_FINISHED", function() End() end)
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_APPLY_STARTED", function() Begin("apply") end)
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_APPLY_FINISHED", function() End() end)
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_UNDO_STARTED", function() Begin("undo") end)
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_UNDO_FINISHED", function() End() end)
end
